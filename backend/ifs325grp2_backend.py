import uvicorn
from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect, Depends, status
from pydantic import BaseModel, Field
import paho.mqtt.client as mqtt
import threading
from datetime import datetime, timedelta, timezone
from apscheduler.schedulers.background import BackgroundScheduler
from typing import List, Optional
import os
from fastapi.middleware.cors import CORSMiddleware
import json
import httpx
import asyncio
from contextlib import asynccontextmanager
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

# ==============================================================================
# GLOBAL STATE FOR EVENT LOOP
# ==============================================================================

_main_loop: Optional[asyncio.AbstractEventLoop] = None


def get_main_event_loop() -> Optional[asyncio.AbstractEventLoop]:
    """Get the main FastAPI event loop (thread-safe)"""
    global _main_loop
    if _main_loop and not _main_loop.is_closed():
        return _main_loop
    return None


def schedule_async_task(coro):
    """Schedule an async task from any thread (e.g., MQTT callbacks)"""
    loop = get_main_event_loop()
    if loop:
        try:
            asyncio.run_coroutine_threadsafe(coro, loop)
        except Exception as e:
            print(f"⚠️ Failed to schedule async task: {e}")
    else:
        print("⚠️ Main event loop not available")


# ==============================================================================
# CONFIGURATION SECTION
# ==============================================================================

class Config:
    """Central configuration class for all settings"""
    # MQTT Settings
    MQTT_BROKER = os.environ["MQTT_BROKER"]
    MQTT_PORT = int(os.environ["MQTT_PORT"])
    MQTT_TOPIC_CONTROL = os.environ["MQTT_TOPIC_CONTROL"]
    MQTT_TOPIC_DATA_FLOW = os.environ["MQTT_TOPIC_DATA_FLOW"]
    CLIENT_ID = os.environ["MQTT_CLIENT_ID"]

    # Pump Settings
    PUMP_AUTO_OFF_MINUTES = int(os.environ["PUMP_AUTO_OFF_MINUTES"])
    PRIMARY_PUMP_UID = os.environ["PRIMARY_PUMP_UID"]

    # Oracle ORDS Base URL
    ORDS_BASE = os.environ["ORDS_BASE_URL"]

    # Oracle ORDS Endpoints
    ORDS_AUDIT = f"{ORDS_BASE}/audit/"
    ORDS_SCHEDULE_CREATE = f"{ORDS_BASE}/schedule/"
    ORDS_ALERT_CREATE = f"{ORDS_BASE}/alerts/create/"
    ORDS_HISTORY = f"{ORDS_BASE}/history/pump_runs"
    ORDS_SCHEDULES_ALL = f"{ORDS_BASE}/schedules/all"
    ORDS_SCHEDULES_ACTIVE = f"{ORDS_BASE}/schedules/active"
    ORDS_SCHEDULE_DELETE = f"{ORDS_BASE}/schedule/delete"
    ORDS_SCHEDULE_STATUS = f"{ORDS_BASE}/schedule/status"
    ORDS_SCHEDULE_UPDATE = f"{ORDS_BASE}/schedule/update"
    ORDS_ALERTS_LIST = f"{ORDS_BASE}/alerts/list"
    ORDS_ALERTS_UNREAD = f"{ORDS_BASE}/alerts/unread"
    ORDS_SETTINGS_GET = f"{ORDS_BASE}/settings/thresholds"
    ORDS_SETTINGS_UPDATE = f"{ORDS_BASE}/settings/thresholds"
    ORDS_ANALYTICS = f"{ORDS_BASE}/analytics/telemetry"

    # Timezone
    LOCAL_TZ = timezone(
        timedelta(hours=int(os.environ["LOCAL_TIMEZONE_OFFSET"])),
        name=os.environ["LOCAL_TIMEZONE"]
    )

    # HTTP Client Settings
    HTTP_TIMEOUT = 10.0
    HTTP_MAX_RETRIES = 3

    # Alert Settings (cooldown periods in seconds)
    ALERT_COOLDOWN_CRITICAL = 3600 
    ALERT_COOLDOWN_INFO = 600  


config = Config()


# ==============================================================================
# DATABASE SECTION
# ==============================================================================

class Database:
    """In-memory state management for live data with thread safety."""

    def __init__(self):
        self._state = {
            "pump_is_on": False,
            "last_known_flow_lpm": 0.0,
            "last_known_moisture": 50.0,
            "automated_mode_enabled": True,
            "critical_low_threshold": 40.0,
            "critical_high_threshold": 80.0,
            "total_flow": 0.0,
            "current_cycle_volume_l": 0.0,

            # Manual override tracking
            "manual_override_active": False,
            "manual_override_state": None,
            "allow_manual_override_at_any_moisture": True,

            # Schedule tracking
            "current_schedule_name": None,
            "schedule_end_time": None,

            # Alert tracking (independent of mode)
            "last_critical_low_alert": None,
            "last_critical_high_alert": None,
            "last_normal_alert": None,
            "last_flow_rate": 0.0,
            "last_flow_rate_check": None,
        }
        self._lock = threading.Lock()

    def get(self, key: str, default=None):
        with self._lock:
            return self._state.get(key, default)

    def set(self, key: str, value):
        with self._lock:
            self._state[key] = value

    def update(self, **kwargs):
        with self._lock:
            self._state.update(kwargs)

    @property
    def state(self):
        with self._lock:
            return self._state.copy()


db = Database()


# ==============================================================================
# WEBSOCKET CONNECTION MANAGER
# ==============================================================================

class ConnectionManager:
    """Manages WebSocket connections for real-time updates."""

    def __init__(self):
        self.active_connections: List[WebSocket] = []
        self._lock = asyncio.Lock()

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        async with self._lock:
            self.active_connections.append(websocket)
        print(f"✓ Client connected. Total: {len(self.active_connections)}")

    async def disconnect(self, websocket: WebSocket):
        async with self._lock:
            if websocket in self.active_connections:
                self.active_connections.remove(websocket)
        print(f"✓ Client disconnected. Total: {len(self.active_connections)}")

    async def broadcast(self, message: dict):
        """Broadcast message to all connected clients"""
        if not self.active_connections:
            return

        message_str = json.dumps(message)
        async with self._lock:
            connections = list(self.active_connections)

        disconnected = []
        for connection in connections:
            try:
                await connection.send_text(message_str)
            except Exception as e:
                print(f"✗ Broadcast error: {e}")
                disconnected.append(connection)

        # Clean up disconnected clients
        if disconnected:
            async with self._lock:
                for conn in disconnected:
                    if conn in self.active_connections:
                        self.active_connections.remove(conn)


manager = ConnectionManager()


async def broadcast_current_state():
    """Helper to broadcast current system state"""
    schedule_end = db.get("schedule_end_time")
    state = {
        "pump_is_on": db.get("pump_is_on"),
        "current_flow_lpm": round(db.get("last_known_flow_lpm"), 2),
        "moisture": round(db.get("last_known_moisture"), 2),
        "automated_mode_enabled": db.get("automated_mode_enabled"),
        "manual_override_active": db.get("manual_override_active"),
        "manual_override_state": db.get("manual_override_state"),
        "allow_manual_override_at_any_moisture": db.get("allow_manual_override_at_any_moisture"),
        "current_schedule_name": db.get("current_schedule_name"),
        "schedule_end_time": schedule_end.isoformat() if schedule_end else None,
        "total_flow": round(db.get("total_flow", 0.0), 2),
        "current_cycle_volume_l": round(db.get("current_cycle_volume_l", 0.0), 2)
    }
    await manager.broadcast(state)


# ==============================================================================
# ORACLE INTEGRATION LAYER (OPTIMIZED)
# ==============================================================================

class OracleClient:
    """Optimized Oracle ORDS client with connection pooling and retries"""

    HEADERS = {
        "User-Agent": "FastAPI-Backend-v9.0",
        "Accept": "application/json",
        "Content-Type": "application/json"
    }

    _http_client: Optional[httpx.AsyncClient] = None

    @classmethod
    async def get_client(cls) -> httpx.AsyncClient:
        """Get or create persistent HTTP client (connection pooling)"""
        if cls._http_client is None or cls._http_client.is_closed:
            cls._http_client = httpx.AsyncClient(
                timeout=config.HTTP_TIMEOUT,
                limits=httpx.Limits(max_keepalive_connections=5, max_connections=10),
                headers=cls.HEADERS
            )
        return cls._http_client

    @classmethod
    async def close_client(cls):
        """Close HTTP client on shutdown"""
        if cls._http_client and not cls._http_client.is_closed:
            await cls._http_client.aclose()

    @staticmethod
    def _validate_device_uid(device_uid: str) -> str:
        """Validate and sanitize device UID"""
        if not device_uid or not device_uid.strip():
            raise ValueError("device_uid cannot be empty")
        return device_uid.strip()

    @classmethod
    async def _make_request(cls, method: str, url: str, **kwargs):
        """Make HTTP request with retry logic"""
        client = await cls.get_client()

        for attempt in range(config.HTTP_MAX_RETRIES):
            try:
                response = await getattr(client, method)(url, **kwargs)
                if 200 <= response.status_code < 300:
                    return response
                elif response.status_code >= 500 and attempt < config.HTTP_MAX_RETRIES - 1:
                    await asyncio.sleep(0.5 * (attempt + 1))
                    continue
                return None
            except httpx.RequestError as e:
                if attempt < config.HTTP_MAX_RETRIES - 1:
                    await asyncio.sleep(0.5 * (attempt + 1))
                    continue
                print(f"✗ Request error after {config.HTTP_MAX_RETRIES} attempts: {e}")
                return None
        return None

    @classmethod
    async def log_audit(cls, event_type: str, description: str, source: str,
                        severity: str = "INFO", device_uid: Optional[str] = None):
        """Log audit event (async, non-blocking)"""
        try:
            uid = cls._validate_device_uid(device_uid or config.PRIMARY_PUMP_UID)
            payload = {
                "device_uid": uid,
                "event_type": event_type,
                "description": description,
                "source": source,
                "severity": severity
            }
            await cls._make_request("post", config.ORDS_AUDIT, json=payload)
        except Exception as e:
            print(f"✗ Audit log error: {e}")

    @classmethod
    async def create_alert(cls, alert_type: str, message: str, severity: str = "INFO",
                           device_uid: Optional[str] = None) -> bool:
        """Create alert in database"""
        try:
            uid = cls._validate_device_uid(device_uid or config.PRIMARY_PUMP_UID)
            payload = {
                "device_uid": uid,
                "alert_type": alert_type,
                "message": message,
                "severity": severity.upper()
            }
            print(f"🚨 Alert: [{severity}] {alert_type} - {message}")
            response = await cls._make_request("post", config.ORDS_ALERT_CREATE, json=payload)
            return response is not None and response.status_code in [200, 201]
        except Exception as e:
            print(f"✗ Alert creation error: {e}")
            return False

    @classmethod
    async def get_settings(cls, device_uid: Optional[str] = None) -> Optional[dict]:
        """Fetch settings from Oracle database"""
        try:
            uid = cls._validate_device_uid(device_uid or config.PRIMARY_PUMP_UID)
            url = f"{config.ORDS_SETTINGS_GET}/{uid}"
            response = await cls._make_request("get", url)

            if response:
                data = response.json()
                if isinstance(data, dict) and 'items' in data:
                    items = data['items']
                    return items[0] if items else None
                elif isinstance(data, list):
                    return data[0] if data else None
                return data
            return None
        except Exception as e:
            print(f"✗ Error fetching settings: {e}")
            return None

    @classmethod
    async def save_settings(cls, settings_data: dict, device_uid: Optional[str] = None) -> bool:
        """Save settings to Oracle database"""
        try:
            uid = cls._validate_device_uid(device_uid or config.PRIMARY_PUMP_UID)
            url = f"{config.ORDS_SETTINGS_UPDATE}/{uid}"

            payload = {
                "device_uid": uid,
                "critical_low_threshold": float(settings_data.get("critical_low_threshold", 40.0)),
                "critical_high_threshold": float(settings_data.get("critical_high_threshold", 80.0)),
                "automated_mode_enabled": int(settings_data.get("automated_mode_enabled", 1)),
                "allow_manual_override_at_any_moisture": int(
                    settings_data.get("allow_manual_override_at_any_moisture", 1))
            }

            response = await cls._make_request("put", url, json=payload)
            return response is not None and response.status_code in [200, 201]
        except Exception as e:
            print(f"✗ Error saving settings: {e}")
            return False

    @classmethod
    async def get_alerts(cls, device_uid: Optional[str] = None) -> dict:
        """Get all alerts"""
        try:
            uid = cls._validate_device_uid(device_uid or config.PRIMARY_PUMP_UID)
            url = f"{config.ORDS_ALERTS_LIST}/{uid}"
            response = await cls._make_request("get", url)
            return response.json() if response else {"items": []}
        except Exception as e:
            print(f"✗ Error fetching alerts: {e}")
            return {"items": []}

    @classmethod
    async def get_unread_alerts(cls, device_uid: Optional[str] = None) -> dict:
        """Get unread alerts"""
        try:
            uid = cls._validate_device_uid(device_uid or config.PRIMARY_PUMP_UID)
            url = f"{config.ORDS_ALERTS_UNREAD}/{uid}"
            response = await cls._make_request("get", url)
            return response.json() if response else {"items": []}
        except Exception as e:
            print(f"✗ Error fetching unread alerts: {e}")
            return {"items": []}

    @classmethod
    async def log_schedule_to_db(cls, device_uid: str, start_time: datetime,
                                 duration_min: int, repeat_days: str, name: str):
        """Log schedule to database"""
        try:
            uid = cls._validate_device_uid(device_uid)
            payload = {
                "device_uid": uid,
                "start_time_of_day": start_time.strftime("%H:%M:%S"),
                "duration_min": duration_min,
                "is_active": 1,
                "repeat_days": repeat_days,
                "name": name
            }
            return await cls._make_request("post", config.ORDS_SCHEDULE_CREATE, json=payload)
        except Exception as e:
            print(f"✗ Error logging schedule: {e}")
            return None

    @classmethod
    async def get_history(cls, device_uid: Optional[str] = None) -> dict:
        """Get pump run history"""
        try:
            uid = cls._validate_device_uid(device_uid or config.PRIMARY_PUMP_UID)
            url = f"{config.ORDS_HISTORY}/{uid}"
            response = await cls._make_request("get", url)
            if response:
                return response.json()
            raise HTTPException(status_code=502, detail="Could not fetch history")
        except HTTPException:
            raise
        except Exception as e:
            print(f"✗ Error fetching history: {e}")
            raise HTTPException(status_code=502, detail="Could not fetch history")

    @classmethod
    async def get_all_schedules_from_db(cls, device_uid: Optional[str] = None) -> dict:
        """Get all schedules"""
        try:
            uid = cls._validate_device_uid(device_uid or config.PRIMARY_PUMP_UID)
            url = f"{config.ORDS_SCHEDULES_ALL}/{uid}"
            response = await cls._make_request("get", url)
            return response.json() if response else {"items": []}
        except Exception as e:
            print(f"✗ Error fetching schedules: {e}")
            return {"items": []}

    @classmethod
    async def get_active_schedules_from_db(cls, device_uid: Optional[str] = None) -> dict:
        """Get active schedules"""
        try:
            uid = cls._validate_device_uid(device_uid or config.PRIMARY_PUMP_UID)
            url = f"{config.ORDS_SCHEDULES_ACTIVE}/{uid}"
            response = await cls._make_request("get", url)
            return response.json() if response else {"items": []}
        except Exception as e:
            print(f"✗ Error fetching active schedules: {e}")
            return {"items": []}

    @classmethod
    async def delete_schedule_from_db(cls, schedule_id: str, device_uid: Optional[str] = None):
        """Delete schedule"""
        try:
            uid = cls._validate_device_uid(device_uid or config.PRIMARY_PUMP_UID)
            url = f"{config.ORDS_SCHEDULE_DELETE}/{uid}/{schedule_id}"
            return await cls._make_request("delete", url)
        except Exception as e:
            print(f"✗ Error deleting schedule: {e}")
            return None

    @classmethod
    async def update_schedule_status(cls, schedule_id: str, is_active: int,
                                     device_uid: Optional[str] = None):
        """Update schedule status"""
        try:
            uid = cls._validate_device_uid(device_uid or config.PRIMARY_PUMP_UID)
            url = f"{config.ORDS_SCHEDULE_STATUS}/{uid}/{schedule_id}"
            payload = {"is_active": is_active}
            return await cls._make_request("put", url, json=payload)
        except Exception as e:
            print(f"✗ Error updating schedule status: {e}")
            return None

    @classmethod
    async def update_schedule(cls, schedule_id: str, start_time_of_day: str,
                              duration_min: int, repeat_days: str, name: str,
                              device_uid: Optional[str] = None):
        """Update schedule details"""
        try:
            uid = cls._validate_device_uid(device_uid or config.PRIMARY_PUMP_UID)
            url = f"{config.ORDS_SCHEDULE_UPDATE}/{uid}/{schedule_id}"
            payload = {
                "start_time_of_day": start_time_of_day,
                "duration_min": duration_min,
                "repeat_days": repeat_days,
                "schedule_name": name
            }
            return await cls._make_request("put", url, json=payload)
        except Exception as e:
            print(f"✗ Error updating schedule: {e}")
            return None


oracle = OracleClient()

# ==============================================================================
# MQTT CLIENT SETUP (FIXED - THREAD-SAFE ASYNC OPERATIONS)
# ==============================================================================

auto_off_timer: Optional[threading.Timer] = None
auto_off_timer_lock = threading.Lock()
scheduler = BackgroundScheduler(timezone=config.LOCAL_TZ)


def on_connect(client, userdata, flags, rc):
    """MQTT connection callback"""
    if rc == 0:
        print("✓ MQTT connected")
        client.subscribe(config.MQTT_TOPIC_DATA_FLOW)
        print(f"✓ Subscribed to: {config.MQTT_TOPIC_DATA_FLOW}")
    else:
        print(f"✗ MQTT connection failed: {rc}")


def get_current_mode() -> str:
    """Get current operating mode as string"""
    if db.get("manual_override_active"):
        return "MANUAL"
    elif db.get("current_schedule_name"):
        return "SCHEDULED"
    elif db.get("automated_mode_enabled"):
        return "AUTOMATED"
    else:
        return "IDLE"


def should_send_alert(alert_key: str, cooldown_seconds: int) -> bool:
    """Check if alert should be sent based on cooldown period"""
    last_alert_time = db.get(alert_key)
    if last_alert_time is None:
        return True

    now = datetime.now(config.LOCAL_TZ)
    time_since_last = (now - last_alert_time).total_seconds()
    return time_since_last >= cooldown_seconds


def on_message(client, userdata, msg):
    """Handles incoming MQTT messages (SIMPLIFIED - 2 threshold system)"""
    try:
        payload = json.loads(msg.payload.decode())

        old_pump_status = db.get("pump_is_on")
        new_pump_status = (payload.get("pump_status") == "ON")

        db.update(
            last_known_flow_lpm=payload.get("flow_rate", 0.0),
            pump_is_on=new_pump_status,
            last_known_moisture=payload.get("moisture", db.get("last_known_moisture")),
            total_flow=payload.get("total_flow", db.get("total_flow")),
            current_cycle_volume_l=payload.get("cycle_usage", 0.0)
        )

        moisture = db.get("last_known_moisture")
        now = datetime.now(config.LOCAL_TZ)

        # Get simplified thresholds 
        critical_low = db.get("critical_low_threshold")
        critical_high = db.get("critical_high_threshold")

        manual_override_active = db.get("manual_override_active")
        manual_override_state = db.get("manual_override_state")
        allow_override_at_any_moisture = db.get("allow_manual_override_at_any_moisture")

        # Get current mode
        current_mode = get_current_mode()

        print(f"📊 MQTT: Moisture={moisture:.1f}%, Pump={'ON' if new_pump_status else 'OFF'}, "
              f"Mode={current_mode}")

        # ═══════════════════════════════════════════════════════════════════
        # ✅ SIMPLIFIED MOISTURE MONITORING 
        # ═══════════════════════════════════════════════════════════════════

        # ZONE 1: Critical Low
        if moisture < critical_low:
            if should_send_alert("last_critical_low_alert", config.ALERT_COOLDOWN_CRITICAL):
                schedule_async_task(oracle.create_alert(
                    alert_type="CRITICAL_LOW_MOISTURE",
                    message=f"🚨 CRITICAL: Soil moisture at {moisture:.1f}% (below {critical_low}%) | Mode: {current_mode}",
                    severity="CRITICAL"
                ))
                db.set("last_critical_low_alert", now)
                print(f"🚨 CRITICAL LOW moisture alert sent ({current_mode} mode)")

            # Reset other alert trackers
            db.set("last_normal_alert", None)
            db.set("last_critical_high_alert", None)

        # ZONE 2: Normal Range 
        elif critical_low <= moisture <= critical_high:
            if should_send_alert("last_normal_alert", config.ALERT_COOLDOWN_INFO):
                schedule_async_task(oracle.create_alert(
                    alert_type="NORMAL_MOISTURE",
                    message=f"✓ Soil moisture normal at {moisture:.1f}% ({critical_low}-{critical_high}%) | Mode: {current_mode}",
                    severity="INFO"
                ))
                db.set("last_normal_alert", now)
                print(f"✓ NORMAL moisture alert sent ({current_mode} mode)")

            # Reset critical alert trackers when back to normal
            db.set("last_critical_low_alert", None)
            db.set("last_critical_high_alert", None)

        # ZONE 3: Critical High
        elif moisture > critical_high:
            if should_send_alert("last_critical_high_alert", config.ALERT_COOLDOWN_CRITICAL):
                schedule_async_task(oracle.create_alert(
                    alert_type="CRITICAL_HIGH_MOISTURE",
                    message=f"🚨 CRITICAL: Soil moisture at {moisture:.1f}% (above {critical_high}%) | Mode: {current_mode}",
                    severity="CRITICAL"
                ))
                db.set("last_critical_high_alert", now)
                print(f"🚨 CRITICAL HIGH moisture alert sent ({current_mode} mode)")

            # Reset other alert trackers
            db.set("last_normal_alert", None)
            db.set("last_critical_low_alert", None)

        # ═══════════════════════════════════════════════════════════════════
        # EMERGENCY OVERRIDE (ALL MODES - if safety enabled)
        # ═══════════════════════════════════════════════════════════════════

        if moisture > critical_high and not allow_override_at_any_moisture:
            if new_pump_status:
                print(f"🚨 EMERGENCY: Forcing pump OFF (moisture={moisture:.1f}%, mode={current_mode})")
                turn_pump_off("Emergency - Soil Too Wet")
                db.update(manual_override_active=False, manual_override_state=None)
                schedule_async_task(broadcast_current_state())
                return

        # ═══════════════════════════════════════════════════════════════════
        # MANUAL OVERRIDE ENFORCEMENT
        # ═══════════════════════════════════════════════════════════════════

        if manual_override_active and manual_override_state:
            desired_state_on = (manual_override_state == 'ON')

            if desired_state_on and not new_pump_status:
                print(f"🎮 MANUAL OVERRIDE - Enforcing ON")
                turn_pump_on("Manual Override - Enforcement")
            elif not desired_state_on and new_pump_status:
                print(f"🎮 MANUAL OVERRIDE - Enforcing OFF")
                turn_pump_off("Manual Override - Enforcement")

        # ═══════════════════════════════════════════════════════════════════
        # SIMPLIFIED AUTOMATED CONTROL (2 thresholds)
        # ═══════════════════════════════════════════════════════════════════

        elif db.get("automated_mode_enabled"):
            pump_on = db.get("pump_is_on")

            # Turn pump ON if moisture falls below critical low
            if moisture < critical_low and not pump_on:
                print(f"🤖 AUTO: Moisture {moisture:.1f}% < {critical_low}%. Turning ON.")
                turn_pump_on("Automated - Critical Low Moisture")

            # Turn pump OFF if moisture rises into normal range (after being low)
            elif critical_low <= moisture <= critical_high and pump_on:
                print(f"🤖 AUTO: Moisture normal ({moisture:.1f}%). Turning OFF.")
                turn_pump_off("Automated - Normal Moisture Reached")

            # Turn pump OFF if moisture is critically high
            elif moisture > critical_high and pump_on:
                print(f"🤖 AUTO: Moisture critically high ({moisture:.1f}% > {critical_high}%). Turning OFF.")
                turn_pump_off("Automated - Critical High Moisture")

        # ═══════════════════════════════════════════════════════════════════
        # PUMP STATE CHANGE ALERTS (ALL MODES)
        # ═══════════════════════════════════════════════════════════════════

        if old_pump_status != new_pump_status:
            if new_pump_status:
                schedule_async_task(oracle.create_alert(
                    alert_type="PUMP_ON",
                    message=f"Pump turned ON | Mode: {current_mode} | Moisture: {moisture:.1f}%",
                    severity="INFO"
                ))
            else:
                schedule_async_task(oracle.create_alert(
                    alert_type="PUMP_OFF",
                    message=f"Pump turned OFF | Mode: {current_mode} | Moisture: {moisture:.1f}%",
                    severity="INFO"
                ))

                # Clear schedule tracking when pump stops
                if db.get("current_schedule_name"):
                    db.update(current_schedule_name=None, schedule_end_time=None)


        schedule_async_task(broadcast_current_state())

    except Exception as e:
        print(f"✗ MQTT handler error: {e}")


mqtt_client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION1, config.CLIENT_ID)
mqtt_client.on_connect = on_connect
mqtt_client.on_message = on_message


# ==============================================================================
# PUMP CONTROL LOGIC (FIXED - THREAD-SAFE ASYNC OPERATIONS)
# ==============================================================================

def turn_pump_on(source: str = "API"):
    """Turn pump ON with thread-safe timer management"""
    global auto_off_timer

    if db.get("pump_is_on"):
        print(f"ℹ️ Pump already ON, ignoring duplicate request")
        return

    schedule_async_task(oracle.log_audit(
        "PUMP_CONTROL", f"Pump turned ON - {source}", source, "INFO", config.PRIMARY_PUMP_UID
    ))

    print(f"💧 Turning pump ON ({source})")
    mqtt_client.publish(config.MQTT_TOPIC_CONTROL, "ON")
    db.set("pump_is_on", True)


    with auto_off_timer_lock:
        if auto_off_timer and auto_off_timer.is_alive():
            auto_off_timer.cancel()

        auto_off_timer = threading.Timer(
            config.PUMP_AUTO_OFF_MINUTES * 60,
            lambda: turn_pump_off("Auto-shutoff")
        )
        auto_off_timer.daemon = True
        auto_off_timer.start()

    schedule_async_task(broadcast_current_state())


def turn_pump_off(source: str = "API"):
    """Turn pump OFF with thread-safe timer management"""
    global auto_off_timer

    if not db.get("pump_is_on"):
        print(f"ℹ️ Pump already OFF, ignoring duplicate request")
        return

    schedule_async_task(oracle.log_audit(
        "PUMP_CONTROL", f"Pump turned OFF - {source}", source, "INFO", config.PRIMARY_PUMP_UID
    ))

    print(f"🛑 Turning pump OFF ({source})")
    mqtt_client.publish(config.MQTT_TOPIC_CONTROL, "OFF")
    db.update(pump_is_on=False, last_known_flow_lpm=0.0)

    with auto_off_timer_lock:
        if auto_off_timer and auto_off_timer.is_alive():
            auto_off_timer.cancel()
            auto_off_timer = None

    schedule_async_task(broadcast_current_state())


def _add_or_update_job_in_scheduler(schedule_data: dict):
    """Adds or updates a scheduled job with end time tracking"""
    try:
        schedule_id = str(schedule_data['id'])
        job_id_base = f"db_{schedule_id}"
        job_name = schedule_data.get('name') or f"Schedule {schedule_id}"
        duration = schedule_data['duration_min']
        time_parts = list(map(int, schedule_data['start_time_of_day'].split(':')))
        run_time_obj = datetime.now(config.LOCAL_TZ).replace(
            hour=time_parts[0],
            minute=time_parts[1],
            second=time_parts[2],
            microsecond=0
        )

        # Remove existing jobs first
        _remove_job_from_scheduler(schedule_id)

        if schedule_data.get('is_active') == 1:
            repeat_days_str = schedule_data.get("repeat_days", "")

            # Only schedule if it's a repeating job
            if repeat_days_str and '-' not in repeat_days_str:
                def start_scheduled_pump():
                    end_time = datetime.now(config.LOCAL_TZ) + timedelta(minutes=duration)
                    db.update(
                        current_schedule_name=job_name,
                        schedule_end_time=end_time
                    )
                    turn_pump_on(f"Scheduled: {job_name}")

                def stop_scheduled_pump():
                    turn_pump_off(f"Scheduled: {job_name} (complete)")
                    db.update(current_schedule_name=None, schedule_end_time=None)

                scheduler.add_job(
                    start_scheduled_pump,
                    trigger='cron',
                    day_of_week=repeat_days_str.lower(),
                    hour=run_time_obj.hour,
                    minute=run_time_obj.minute,
                    id=f"on_{job_id_base}",
                    name=job_name,
                    replace_existing=True
                )

                off_time = run_time_obj + timedelta(minutes=duration)
                scheduler.add_job(
                    stop_scheduled_pump,
                    trigger='cron',
                    day_of_week=repeat_days_str.lower(),
                    hour=off_time.hour,
                    minute=off_time.minute,
                    id=f"off_{job_id_base}",
                    name=f"{job_name} (Auto OFF)",
                    replace_existing=True
                )
                print(f"✓ Scheduled: {job_name} at {run_time_obj.strftime('%H:%M')} for {duration}min")
    except Exception as e:
        print(f"✗ Failed to add schedule: {e}")


def _remove_job_from_scheduler(schedule_id: str):
    """Remove jobs from scheduler"""
    job_id_base = f"db_{schedule_id}"
    for job_suffix in ["on", "off"]:
        try:
            scheduler.remove_job(f"{job_suffix}_{job_id_base}")
        except Exception:
            pass


# ==============================================================================
# LIFECYCLE MANAGEMENT WITH LIFESPAN
# ==============================================================================

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage application lifespan (startup/shutdown)"""
    global _main_loop

    # STARTUP
    try:
        _main_loop = asyncio.get_running_loop()
        print(f"✓ Main event loop captured")

        print(f"\n{'=' * 80}")
        print(f"🚀 ARC Irrigation Backend v9.0 (Simplified 2-Threshold System)")
        print(f"{'=' * 80}\n")

        # Connect MQTT
        print("🔌 Connecting to MQTT...")
        mqtt_client.connect(config.MQTT_BROKER, config.MQTT_PORT, 60)
        mqtt_client.loop_start()
        print("✓ MQTT connected")

        # Load settings from Oracle
        print("📥 Loading settings from Oracle database...")
        saved_settings = await oracle.get_settings(config.PRIMARY_PUMP_UID)

        if saved_settings:
            db.update(
                critical_low_threshold=float(saved_settings.get("critical_low_threshold", 40.0)),
                critical_high_threshold=float(saved_settings.get("critical_high_threshold", 80.0)),
                automated_mode_enabled=bool(saved_settings.get("automated_mode_enabled", 1)),
                allow_manual_override_at_any_moisture=bool(
                    saved_settings.get("allow_manual_override_at_any_moisture", 1))
            )
            print(f"✅ Settings loaded: Low={db.get('critical_low_threshold')}%, "
                  f"High={db.get('critical_high_threshold')}%")
        else:
            print("⚠️ No saved settings found, using defaults and saving...")
            success = await oracle.save_settings({
                "critical_low_threshold": db.get("critical_low_threshold"),
                "critical_high_threshold": db.get("critical_high_threshold"),
                "automated_mode_enabled": 1 if db.get("automated_mode_enabled") else 0,
                "allow_manual_override_at_any_moisture": 1 if db.get("allow_manual_override_at_any_moisture") else 0
            }, config.PRIMARY_PUMP_UID)

            if success:
                print("✓ Default settings saved to database")
            else:
                print("✗ Failed to save default settings")

        # Start scheduler
        print("⏰ Starting scheduler...")
        scheduler.start()
        print("✓ Scheduler started")

        # Load active schedules
        print("📋 Loading active schedules...")
        schedules_response = await oracle.get_active_schedules_from_db(config.PRIMARY_PUMP_UID)
        active_schedules = [s for s in schedules_response.get("items", []) if s.get("is_active") == 1]

        for schedule in active_schedules:
            _add_or_update_job_in_scheduler(schedule)

        print(f"✓ Loaded {len(active_schedules)} active schedule(s)")

        # Log startup
        await oracle.log_audit(
            "SYSTEM_START",
            "Backend started v9.0 (2-Threshold System)",
            "Backend",
            "INFO",
            config.PRIMARY_PUMP_UID
        )
        await oracle.create_alert("SYSTEM_START", "System started - Simplified 2-threshold monitoring", "INFO")

        print(f"\n{'=' * 80}")
        print("✅ Backend ready - Simplified monitoring (Low/High thresholds only)")
        print(f"{'=' * 80}\n")

    except Exception as e:
        print(f"✗ Startup error: {e}")
        raise

    # Application runs here
    yield

    # SHUTDOWN
    print("\n🛑 Shutting down...")

    turn_pump_off("Server Shutdown")

    global auto_off_timer
    with auto_off_timer_lock:
        if auto_off_timer and auto_off_timer.is_alive():
            auto_off_timer.cancel()

    mqtt_client.loop_stop()
    mqtt_client.disconnect()
    print("✓ MQTT disconnected")

    scheduler.shutdown(wait=False)
    print("✓ Scheduler stopped")

    await oracle.close_client()
    print("✓ HTTP client closed")

    _main_loop = None

    print("✅ Shutdown complete\n")


# ==============================================================================
# FASTAPI APP INITIALIZATION
# ==============================================================================

app = FastAPI(
    title="ARC Irrigation System API",
    description="Simplified 2-threshold irrigation control system",
    version="9.0.0 (Simplified Thresholds)",
    lifespan=lifespan
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ==============================================================================
# PYDANTIC MODELS
# ==============================================================================

class ScheduleRequest(BaseModel):
    action: str = Field(...)
    run_time: datetime = Field(...)
    duration_minutes: Optional[int] = Field(None, gt=0)
    repeat_days: Optional[str] = Field(None)
    name: Optional[str] = Field(None)


class ScheduleUpdateRequest(BaseModel):
    start_time_of_day: str = Field(...)
    duration_minutes: int = Field(..., gt=0)
    repeat_days: Optional[str] = Field(None)
    name: str = Field(...)


class SimplifiedThresholdSettings(BaseModel):
    """Simplified 2-threshold model"""
    critical_low_threshold: float = Field(..., ge=0, le=100)
    critical_high_threshold: float = Field(..., ge=0, le=100)


# ==============================================================================
# DEPENDENCIES
# ==============================================================================

async def validate_schedule_id(schedule_id: str) -> int:
    """Validate schedule ID"""
    try:
        return int(schedule_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Invalid schedule ID format"
        )


# ==============================================================================
# API ENDPOINTS - MONITORING
# ==============================================================================

@app.websocket("/ws/dashboard")
async def websocket_dashboard(websocket: WebSocket):
    """WebSocket endpoint for real-time dashboard updates"""
    await manager.connect(websocket)
    try:
        schedule_end = db.get("schedule_end_time")
        await websocket.send_text(json.dumps({
            "pump_is_on": db.get("pump_is_on"),
            "current_flow_lpm": round(db.get("last_known_flow_lpm"), 2),
            "moisture": round(db.get("last_known_moisture"), 2),
            "automated_mode_enabled": db.get("automated_mode_enabled"),
            "manual_override_active": db.get("manual_override_active"),
            "manual_override_state": db.get("manual_override_state"),
            "allow_manual_override_at_any_moisture": db.get("allow_manual_override_at_any_moisture"),
            "current_schedule_name": db.get("current_schedule_name"),
            "schedule_end_time": schedule_end.isoformat() if schedule_end else None,
            "total_flow": round(db.get("total_flow", 0.0), 2),
            "current_cycle_volume_l": round(db.get("current_cycle_volume_l", 0.0), 2)
        }))

        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        await manager.disconnect(websocket)
    except Exception as e:
        print(f"✗ WebSocket error: {e}")
        await manager.disconnect(websocket)


@app.get("/dashboard")
async def get_dashboard():
    """Get current dashboard state"""
    schedule_end = db.get("schedule_end_time")
    return {
        "pump_is_on": db.get("pump_is_on"),
        "current_flow_lpm": round(db.get("last_known_flow_lpm"), 2),
        "current_moisture": round(db.get("last_known_moisture"), 2),
        "automated_mode_enabled": db.get("automated_mode_enabled"),
        "manual_override_active": db.get("manual_override_active"),
        "manual_override_state": db.get("manual_override_state"),
        "allow_manual_override_at_any_moisture": db.get("allow_manual_override_at_any_moisture"),
        "current_schedule_name": db.get("current_schedule_name"),
        "schedule_end_time": schedule_end.isoformat() if schedule_end else None,
        "critical_low_threshold": db.get("critical_low_threshold"),
        "critical_high_threshold": db.get("critical_high_threshold"),
        "total_flow": round(db.get("total_flow", 0.0), 2),
        "current_cycle_volume_l": round(db.get("current_cycle_volume_l", 0.0), 2),
        "device_uid": config.PRIMARY_PUMP_UID,
        "current_mode": get_current_mode()
    }


@app.get("/history/pump_runs")
async def get_pump_run_history():
    """Get pump run history"""
    return await oracle.get_history(config.PRIMARY_PUMP_UID)


@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "version": "9.0.0",
        "mqtt_connected": mqtt_client.is_connected(),
        "scheduler_running": scheduler.running,
        "active_websockets": len(manager.active_connections),
        "event_loop_available": get_main_event_loop() is not None,
        "current_mode": get_current_mode(),
        "threshold_system": "simplified_2_thresholds"
    }


# ==============================================================================
# API ENDPOINTS - ALERTS
# ==============================================================================

@app.get("/alerts/list")
async def get_alerts_list():
    """Get all alerts"""
    return await oracle.get_alerts(config.PRIMARY_PUMP_UID)


@app.get("/alerts/unread")
async def get_unread_alerts():
    """Get unread alerts"""
    return await oracle.get_unread_alerts(config.PRIMARY_PUMP_UID)


# ==============================================================================
# API ENDPOINTS - ANALYTICS
# ==============================================================================

@app.get("/analytics/telemetry")
async def get_telemetry_analytics(
        device_uid: Optional[str] = config.PRIMARY_PUMP_UID,
        hours: Optional[int] = 24,
        metric: Optional[str] = "all"  
):
    """
    Get telemetry analytics data for charts

    Parameters:
    - device_uid: Device identifier
    - hours: Number of hours to look back (default 24)
    - metric: Specific metric to filter (default 'all')
    """
    try:

        url = f"{config.ORDS_BASE}/analytics/telemetry/{device_uid}"

        client = await OracleClient.get_client()
        response = await client.get(
            url,
            params={"hours": hours, "metric": metric}
        )

        if response.status_code == 200:
            return response.json()
        else:
            raise HTTPException(
                status_code=response.status_code,
                detail=f"Failed to fetch analytics data: {response.text}"
            )
    except Exception as e:
        print(f"✗ Error fetching analytics: {e}")
        raise HTTPException(status_code=502, detail=f"Could not fetch analytics data: {str(e)}")


# ==============================================================================
# API ENDPOINTS - PUMP CONTROL
# ==============================================================================

@app.post("/pump/on")
async def post_pump_on():
    """Manually turn pump ON"""
    db.update(
        manual_override_active=True,
        manual_override_state="ON",
        current_schedule_name=None,
        schedule_end_time=None
    )

    print(f"🎮 MANUAL OVERRIDE ACTIVATED - State: ON")

    moisture = db.get("last_known_moisture")
    await oracle.create_alert(
        alert_type="MANUAL_OVERRIDE_ON",
        message=f"Manual control: Pump started (moisture: {moisture:.1f}%)",
        severity="INFO"
    )

    turn_pump_on("Manual Control")
    await broadcast_current_state()

    return {
        "status": "success",
        "message": "Pump started manually",
        "manual_override_active": True,
        "manual_override_state": "ON"
    }


@app.post("/pump/off")
async def post_pump_off():
    """Manually turn pump OFF"""
    db.update(
        manual_override_active=True,
        manual_override_state="OFF",
        current_schedule_name=None,
        schedule_end_time=None
    )

    print(f"🎮 MANUAL OVERRIDE ACTIVATED - State: OFF")

    await oracle.create_alert(
        alert_type="MANUAL_OVERRIDE_OFF",
        message="Manual control: Pump stopped",
        severity="INFO"
    )

    turn_pump_off("Manual Control")
    await broadcast_current_state()

    return {
        "status": "success",
        "message": "Pump stopped manually",
        "manual_override_active": True,
        "manual_override_state": "OFF"
    }


@app.post("/manual_override/clear")
async def clear_manual_override():
    """Clear manual override and return to automatic operation"""
    db.update(manual_override_active=False, manual_override_state=None)
    print(f"🎮 MANUAL OVERRIDE CLEARED")

    await oracle.create_alert(
        alert_type="MANUAL_OVERRIDE_CLEARED",
        message="Returned to automatic operation",
        severity="INFO"
    )

    await broadcast_current_state()

    return {
        "status": "success",
        "message": "Automatic operation resumed",
        "manual_override_active": False
    }


# ==============================================================================
# API ENDPOINTS - SCHEDULING
# ==============================================================================

@app.post("/schedule/create")
async def create_schedule(schedule_data: ScheduleRequest):
    """Create a new irrigation schedule"""
    now = datetime.now(scheduler.timezone)
    run_time = schedule_data.run_time

    if run_time.tzinfo is None:
        run_time = run_time.replace(tzinfo=config.LOCAL_TZ)
    else:
        run_time = run_time.astimezone(config.LOCAL_TZ)

    if not schedule_data.repeat_days and run_time < now:
        raise HTTPException(status_code=400, detail="Run time cannot be in the past for one-time schedules")

    if schedule_data.action.upper() != "ON":
        raise HTTPException(status_code=400, detail="Action must be 'ON'")

    duration = schedule_data.duration_minutes or config.PUMP_AUTO_OFF_MINUTES
    repeat_days = schedule_data.repeat_days or run_time.strftime("%Y-%m-%d")
    name = schedule_data.name or f"Schedule {run_time.strftime('%Y-%m-%d %H:%M')}"

    response = await oracle.log_schedule_to_db(
        config.PRIMARY_PUMP_UID,
        run_time,
        duration,
        repeat_days,
        name
    )

    if not response or response.status_code not in [200, 201]:
        raise HTTPException(status_code=502, detail="Failed to save schedule to database")

    await oracle.create_alert(
        alert_type="SCHEDULE_CREATED",
        message=f"Schedule created: {name}",
        severity="INFO"
    )

    schedules_response = await oracle.get_active_schedules_from_db(config.PRIMARY_PUMP_UID)
    active_schedules = schedules_response.get("items", [])

    if active_schedules:
        latest_schedule = max(active_schedules, key=lambda s: s['id'])
        _add_or_update_job_in_scheduler(latest_schedule)
        return {
            "status": "success",
            "message": "Schedule created successfully",
            "schedule_id": latest_schedule['id']
        }

    return {"status": "error", "message": "Failed to reload schedule"}


@app.put("/schedule/update/{schedule_id}")
async def update_schedule(
        schedule_id: int = Depends(validate_schedule_id),
        schedule_data: ScheduleUpdateRequest = None
):
    """Update an existing schedule"""
    response = await oracle.update_schedule(
        str(schedule_id),
        schedule_data.start_time_of_day,
        schedule_data.duration_minutes,
        schedule_data.repeat_days or "",
        schedule_data.name,
        config.PRIMARY_PUMP_UID
    )

    if not response or response.status_code not in [200, 201]:
        raise HTTPException(status_code=404, detail=f"Schedule {schedule_id} not found or update failed")

    schedules_response = await oracle.get_all_schedules_from_db(config.PRIMARY_PUMP_UID)
    schedule_data_updated = next(
        (s for s in schedules_response.get("items", []) if s['id'] == schedule_id),
        None
    )

    if schedule_data_updated:
        _add_or_update_job_in_scheduler(schedule_data_updated)

    return {"status": "success", "message": "Schedule updated successfully"}


@app.get("/schedule/list")
async def get_schedules():
    """Get all schedules"""
    return await oracle.get_all_schedules_from_db(config.PRIMARY_PUMP_UID)


@app.delete("/schedule/delete/{schedule_id}")
async def delete_schedule(schedule_id: int = Depends(validate_schedule_id)):
    """Delete a schedule"""
    response = await oracle.delete_schedule_from_db(str(schedule_id), config.PRIMARY_PUMP_UID)

    if not response or response.status_code not in [200, 201]:
        raise HTTPException(status_code=404, detail=f"Schedule {schedule_id} not found")

    _remove_job_from_scheduler(str(schedule_id))

    await oracle.create_alert(
        alert_type="SCHEDULE_DELETED",
        message=f"Schedule {schedule_id} deleted",
        severity="INFO"
    )

    return {"status": "success", "message": "Schedule deleted successfully"}


@app.post("/schedule/pause/{schedule_id}")
async def pause_schedule(schedule_id: int = Depends(validate_schedule_id)):
    """Pause a schedule"""
    response = await oracle.update_schedule_status(str(schedule_id), 0, config.PRIMARY_PUMP_UID)

    if not response or response.status_code not in [200, 201]:
        raise HTTPException(status_code=404, detail=f"Schedule {schedule_id} not found")

    _remove_job_from_scheduler(str(schedule_id))
    return {"status": "success", "message": "Schedule paused"}


@app.post("/schedule/resume/{schedule_id}")
async def resume_schedule(schedule_id: int = Depends(validate_schedule_id)):
    """Resume a paused schedule"""
    response = await oracle.update_schedule_status(str(schedule_id), 1, config.PRIMARY_PUMP_UID)

    if not response or response.status_code not in [200, 201]:
        raise HTTPException(status_code=404, detail=f"Schedule {schedule_id} not found")

    schedules_response = await oracle.get_all_schedules_from_db(config.PRIMARY_PUMP_UID)
    schedule_data = next(
        (s for s in schedules_response.get("items", []) if s['id'] == schedule_id),
        None
    )

    if schedule_data:
        _add_or_update_job_in_scheduler(schedule_data)

    return {"status": "success", "message": "Schedule resumed"}


# ==============================================================================
# API ENDPOINTS - SETTINGS (SIMPLIFIED 2-THRESHOLD)
# ==============================================================================

@app.get("/settings/automated")
async def get_automated_settings():
    """Get automated settings (simplified 2-threshold)"""
    return {
        "automated_mode_enabled": db.get("automated_mode_enabled"),
        "critical_low_threshold": db.get("critical_low_threshold"),
        "critical_high_threshold": db.get("critical_high_threshold"),
        "allow_manual_override_at_any_moisture": db.get("allow_manual_override_at_any_moisture"),
        "device_uid": config.PRIMARY_PUMP_UID
    }


@app.post("/settings/automated/thresholds")
async def set_automated_thresholds(settings: SimplifiedThresholdSettings):
    """Update moisture thresholds (simplified - only 2 values)"""
    # Validate threshold order
    if not (settings.critical_low_threshold < settings.critical_high_threshold):
        raise HTTPException(
            status_code=400,
            detail="Invalid threshold order. Critical Low must be less than Critical High"
        )

    # Update in-memory state
    db.update(
        critical_low_threshold=settings.critical_low_threshold,
        critical_high_threshold=settings.critical_high_threshold
    )

    # Persist to Oracle database
    success = await oracle.save_settings({
        "critical_low_threshold": settings.critical_low_threshold,
        "critical_high_threshold": settings.critical_high_threshold,
        "automated_mode_enabled": 1 if db.get("automated_mode_enabled") else 0,
        "allow_manual_override_at_any_moisture": 1 if db.get("allow_manual_override_at_any_moisture") else 0
    }, config.PRIMARY_PUMP_UID)

    if not success:
        raise HTTPException(status_code=502, detail="Failed to save settings to database")

    await broadcast_current_state()

    await oracle.log_audit(
        "SETTINGS_UPDATED",
        f"Thresholds updated: Low={settings.critical_low_threshold}%, High={settings.critical_high_threshold}%",
        "API",
        "INFO"
    )

    print(f"💾 Settings saved: Low={settings.critical_low_threshold}%, High={settings.critical_high_threshold}%")

    return {"status": "success", "message": "Thresholds updated and saved to database"}


@app.post("/settings/automated/enable")
async def enable_automated_mode():
    """Enable automated mode (persists to database)"""
    if db.get("automated_mode_enabled"):
        return {"status": "success", "message": "Automated mode already enabled"}

    db.update(
        automated_mode_enabled=True,
        manual_override_active=False,
        manual_override_state=None
    )

    await oracle.save_settings({
        "critical_low_threshold": db.get("critical_low_threshold"),
        "critical_high_threshold": db.get("critical_high_threshold"),
        "automated_mode_enabled": 1,
        "allow_manual_override_at_any_moisture": 1 if db.get("allow_manual_override_at_any_moisture") else 0
    }, config.PRIMARY_PUMP_UID)

    await oracle.create_alert("AUTOMATED_MODE_ENABLED", "Smart mode enabled", "INFO")
    await broadcast_current_state()

    return {"status": "success", "message": "Automated mode enabled"}


@app.post("/settings/automated/disable")
async def disable_automated_mode():
    """Disable automated mode (persists to database)"""
    if not db.get("automated_mode_enabled"):
        return {"status": "success", "message": "Automated mode already disabled"}

    db.set("automated_mode_enabled", False)

    await oracle.save_settings({
        "critical_low_threshold": db.get("critical_low_threshold"),
        "critical_high_threshold": db.get("critical_high_threshold"),
        "automated_mode_enabled": 0,
        "allow_manual_override_at_any_moisture": 1 if db.get("allow_manual_override_at_any_moisture") else 0
    }, config.PRIMARY_PUMP_UID)

    await oracle.create_alert("AUTOMATED_MODE_DISABLED", "Smart mode disabled", "WARNING")
    await broadcast_current_state()

    return {"status": "success", "message": "Automated mode disabled"}


@app.post("/settings/manual_override/toggle")
async def toggle_manual_override_safety():
    """Toggle manual override safety controls (persists to database)"""
    current = db.get("allow_manual_override_at_any_moisture")
    new_value = not current
    db.set("allow_manual_override_at_any_moisture", new_value)

    await oracle.save_settings({
        "critical_low_threshold": db.get("critical_low_threshold"),
        "critical_high_threshold": db.get("critical_high_threshold"),
        "automated_mode_enabled": 1 if db.get("automated_mode_enabled") else 0,
        "allow_manual_override_at_any_moisture": 1 if new_value else 0
    }, config.PRIMARY_PUMP_UID)

    await broadcast_current_state()

    return {
        "status": "success",
        "message": f"Manual override safety {'disabled' if new_value else 'enabled'}",
        "allow_manual_override_at_any_moisture": new_value
    }


# ==============================================================================
# MAIN ENTRY POINT
# ==============================================================================

if __name__ == "__main__":
    uvicorn.run(
        "irrigation_backend:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
        log_level="info"
    )