🌿 ARC Smart Irrigation System

The ARC Smart Irrigation System is an intelligent IoT-based solution designed to automate and optimize agricultural irrigation.
It integrates Arduino (ESP32) hardware, a Python backend, and a Flutter-based mobile app, connected through MQTT and Oracle APEX for data management.

🚀 Project Overview

The system enables farmers to:

* Monitor soil moisture, water flow, and irrigation status in real time.
* Automatically or manually control the water pump via an app.
* Schedule irrigation cycles based on environmental conditions.
* View analytics and historical water usage data for decision-making.

🧩 System Components

| Component              | Description                                                                                                  |
| -----------------------| ------------------------------------------------------------------------------------------------------------ |
| ESP32 (IoT Device)     | Collects sensor data (soil moisture, flow rate) and controls the pump. Publishes/subscribes to MQTT topics.  |
| MQTT Broker            | Facilitates communication between IoT devices, backend, and frontend.                                        |
| Python Backend         | Processes incoming MQTT data, manages pump logic, and interacts with Oracle APEX via REST APIs.              |
| Oracle APEX (Database) | Stores sensor readings, irrigation schedules, and user data. Exposes RESTful APIs.                           |
| Flutter Frontend (App) | Provides farmers with a user-friendly dashboard to view analytics, control irrigation, and manage schedules. |

🧠 System Architecture

```
[ESP32 Sensors] 
     │
     ▼
 [MQTT Broker] ⇄ [Python Backend] ⇄ [Oracle APEX Database]
     │
     ▼
 [Flutter Frontend (Mobile)]
```

⚙️ Setup Instructions

1️⃣ Prerequisites

Ensure you have the following installed:

* Arduino IDE
* Python 3.10+
* Flutter SDK 3.16+
* Oracle APEX / Oracle Cloud Database
* MQTT Broker (e.g., Mosquitto or HiveMQ)
* Git

2️⃣ Installation

🖥 Backend Setup

```
# Clone the repository
git clone https://github.com/Dhruvi-m04/IFS325-Irrigation-System/edit/main/README.md
cd IFS325-Irrigation-System/backend

# Install dependencies
pip install -r requirements.txt

# Create environment variables
cp .env.example .env

# Run backend
python app.py
```

📡 Arduino (ESP32)

1. Open the `/arduino` folder in Arduino IDE.
2. Update Wi-Fi credentials and MQTT broker IP in the code.
3. Connect ESP32 via USB and upload the sketch.

📱 Frontend (Flutter)

```
cd ../frontend
flutter pub get
flutter run
```

🔐 Security Configuration

* Use MQTT over TLS/SSL and HTTPS for secure communication.
* Store credentials in a `.env` file (never hardcode).
* Implement access control for MQTT topics and API endpoints.
* Enforce strong password policies for Oracle APEX users.

💾 Backup & Recovery

Database: Export Oracle APEX data weekly.
Code: Commit and push regularly to GitHub.
Logs: Store MQTT and backend logs daily for traceability.
Restart backend using:

  ```
  systemctl restart irrigation-backend.service
  ```

📊 Monitoring & Maintenance

* Monitor MQTT traffic using Mosquitto Stats.
* Check backend uptime at `/api/health`.
* Use **Flutter DevTools** to track performance.
* Review Oracle APEX dashboard for data frequency and query speed.

🧱 Folder Structure

arc-smart-irrigation/
├── arduino/           # ESP32 firmware code
├── backend/           # Python backend (MQTT + REST API)
├── frontend/          # Flutter mobile application
└── .gitignore         # Ignored files and directories for Git

🌟 Future Enhancements

* Multi-language support.
* Tank level monitoring using ultrasonic sensors.
* Real-time notifications via Firebase Cloud Messaging.
* Weather API integration for smart scheduling.
* Fail-safes (automatic pump shutdown, alerts, fallback logic).
* Dockerized deployment for easier scaling.
