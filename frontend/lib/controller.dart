import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:vibration/vibration.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'models.dart';
import 'constants.dart';

// ============================================================================
// APP CONTROLLER - SIMPLIFIED 2-THRESHOLD SYSTEM v9.0 (Audio removed)
// ============================================================================
class AppController extends ChangeNotifier {
  // --- Settings ---
  MetricSystem _metricSystem = MetricSystem.metric;
  ThemeMode _themeMode = ThemeMode.system;
  bool _automatedModeEnabled = true;
  bool _lowMoistureAlertEnabled = true;

  // Kept for UI compatibility; does nothing now that audio is removed
  bool _alertSoundEnabled = true;
  bool _alertVibrationEnabled = true;

  double _criticalLowThreshold = 40.0;
  double _criticalHighThreshold = 80.0;

  // Manual override safety setting
  bool _allowManualOverrideAtAnyMoisture = true;

  // Live state via ValueNotifiers for granular UI updates
  final ValueNotifier<String> pumpStatusNotifier = ValueNotifier<String>('OFF');
  final ValueNotifier<double> soilMoistureNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<double> flowRateNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<double> totalVolumeNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<double> cycleUsageNotifier = ValueNotifier<double>(0.0);

  IrrigationMode mode = IrrigationMode.automated;
  bool _isManualOverrideActive = false;
  String? _manualOverrideState;

  // Schedule tracking
  String? _currentScheduleName;
  DateTime? _scheduleEndTime;

  // --- In-App Notifications ---
  bool _lowMoistureAlertShown = false;
  bool _highMoistureAlertShown = false;
  double _lastFlowRate = 0.0;
  DateTime? _lastFlowRateCheck;
  List<NotificationItem> _notifications = [];
  bool _hasUnreadNotifications = false;
  bool? _hasVibrator;

  // --- Database-Backed Alerts ---
  List<Alert> _alerts = [];
  bool _isLoadingAlerts = false;
  String _alertsError = '';
  Timer? _alertRefreshTimer;
  bool _alertScreenActive = false;

  // --- Schedules & History ---
  List<IrrigationSchedule> schedules = [];
  List<AuditEvent> auditHistory = [];
  bool isLoadingHistory = false;
  String historyError = '';

  // --- Internal ---
  WebSocketChannel? _channel;
  Timer? _reconnectTimer;

  // Getters for ValueNotifiers
  String get pumpStatus => pumpStatusNotifier.value;
  double get soilMoisture => soilMoistureNotifier.value;
  double get flowRate => flowRateNotifier.value;
  double get totalVolume => totalVolumeNotifier.value;
  double get cycleUsage => cycleUsageNotifier.value;

  MetricSystem get metricSystem => _metricSystem;
  ThemeMode get themeMode => _themeMode;
  bool get automatedModeEnabled => _automatedModeEnabled;
  bool get lowMoistureAlertEnabled => _lowMoistureAlertEnabled;

  // Kept for UI toggles; no-op for sound
  bool get alertSoundEnabled => _alertSoundEnabled;
  bool get alertVibrationEnabled => _alertVibrationEnabled;

  double get criticalLowThreshold => _criticalLowThreshold;
  double get criticalHighThreshold => _criticalHighThreshold;

  bool get allowManualOverrideAtAnyMoisture => _allowManualOverrideAtAnyMoisture;
  bool get isManualOverrideActive => _isManualOverrideActive;
  String? get manualOverrideState => _manualOverrideState;

  String? get currentScheduleName => _currentScheduleName;
  DateTime? get scheduleEndTime => _scheduleEndTime;

  List<NotificationItem> get notifications => _notifications;
  bool get hasUnreadNotifications => _hasUnreadNotifications;

  List<Alert> get alerts => _alerts;
  List<Alert> get unreadAlerts => _alerts.where((a) => a.isUnread).toList();
  int get unreadAlertCount => unreadAlerts.length;
  bool get isLoadingAlerts => _isLoadingAlerts;
  String get alertsError => _alertsError;

  bool get canStartPump {
    if (_allowManualOverrideAtAnyMoisture) return true;
    return soilMoisture <= _criticalHighThreshold;
  }

  bool get canStopPump {
    if (_allowManualOverrideAtAnyMoisture) return true;
    return soilMoisture >= _criticalLowThreshold;
  }

  AppController() {
    _initializeVibration();
    _connectWebSocket();
    fetchSchedules();
    fetchAutomatedSettings();
    fetchAuditHistory();
  }

  Future<void> _initializeVibration() async {
    try {
      _hasVibrator = await Vibration.hasVibrator();
    } catch (_) {
      _hasVibrator = false;
    }
  }

  // --- Alert Screen Lifecycle Management ---
  void setAlertScreenActive(bool isActive) {
    _alertScreenActive = isActive;
    if (isActive) {
      fetchAlerts();
      _startAlertRefreshTimer();
    } else {
      _alertRefreshTimer?.cancel();
    }
  }

  // --- Settings Methods ---

  void setMetricSystem(MetricSystem newSystem) {
    if (_metricSystem != newSystem) {
      _metricSystem = newSystem;
      notifyListeners();
    }
  }

  void setThemeMode(ThemeMode newMode) {
    if (_themeMode != newMode) {
      _themeMode = newMode;
      notifyListeners();
    }
  }

  Future<void> setAutomatedModeEnabled(bool enabled) async {
    final previousState = _automatedModeEnabled;
    _automatedModeEnabled = enabled;

    if (enabled) {
      _lowMoistureAlertShown = false;
      _highMoistureAlertShown = false;
    }

    notifyListeners();

    try {
      final url = enabled
          ? '$backendBaseUrl/settings/automated/enable'
          : '$backendBaseUrl/settings/automated/disable';
      final response =
          await http.post(Uri.parse(url)).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        _automatedModeEnabled = previousState;
        notifyListeners();
      }
    } catch (_) {
      _automatedModeEnabled = previousState;
      notifyListeners();
    }
  }

  void setLowMoistureAlertEnabled(bool enabled) {
    if (_lowMoistureAlertEnabled != enabled) {
      _lowMoistureAlertEnabled = enabled;
      notifyListeners();
    }
  }

  // Kept for UI compatibility (no audio playback anymore)
  void setAlertSoundEnabled(bool enabled) {
    if (_alertSoundEnabled != enabled) {
      _alertSoundEnabled = enabled;
      notifyListeners();
    }
  }

  void setAlertVibrationEnabled(bool enabled) {
    if (_alertVibrationEnabled != enabled) {
      _alertVibrationEnabled = enabled;
      notifyListeners();
    }
  }

  void setCriticalLowThreshold(double value) {
    final clampedValue = value.clamp(0.0, 100.0);
    if (_criticalLowThreshold != clampedValue) {
      _criticalLowThreshold = clampedValue;
      notifyListeners();
    }
  }

  void setCriticalHighThreshold(double value) {
    final clampedValue = value.clamp(0.0, 100.0);
    if (_criticalHighThreshold != clampedValue) {
      _criticalHighThreshold = clampedValue;
      notifyListeners();
    }
  }

  Future<void> toggleManualOverrideSafety() async {
    final previousState = _allowManualOverrideAtAnyMoisture;
    _allowManualOverrideAtAnyMoisture = !previousState;
    notifyListeners();

    try {
      final response = await http
          .post(Uri.parse('$backendBaseUrl/settings/manual_override/toggle'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        _allowManualOverrideAtAnyMoisture = previousState;
        notifyListeners();
      }
    } catch (_) {
      _allowManualOverrideAtAnyMoisture = previousState;
      notifyListeners();
    }
  }

  Future<bool> saveThresholds() async {
    if (!(_criticalLowThreshold < _criticalHighThreshold)) {
      return false;
    }

    try {
      final response = await http
          .post(
            Uri.parse('$backendBaseUrl/settings/automated/thresholds'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'critical_low_threshold': _criticalLowThreshold,
              'critical_high_threshold': _criticalHighThreshold,
            }),
          )
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> fetchAutomatedSettings() async {
    try {
      final response = await http
          .get(Uri.parse('$backendBaseUrl/settings/automated'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _automatedModeEnabled = data['automated_mode_enabled'] ?? true;
        _criticalLowThreshold =
            (data['critical_low_threshold'] as num?)?.toDouble() ?? 40.0;
        _criticalHighThreshold =
          (data['critical_high_threshold'] as num?)?.toDouble() ?? 80.0;
        _allowManualOverrideAtAnyMoisture =
            data['allow_manual_override_at_any_moisture'] ?? true;
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error fetching settings: $e");
    }
  }

  Future<void> setMode(IrrigationMode newMode) async {
    if (mode != newMode) {
      mode = newMode;

      if (newMode != IrrigationMode.manual && _isManualOverrideActive) {
        await clearManualOverride();
      }

      notifyListeners();
    }
  }

  Future<void> clearManualOverride() async {
    if (!_isManualOverrideActive) return;

    try {
      final response = await http
          .post(Uri.parse('$backendBaseUrl/manual_override/clear'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        _isManualOverrideActive = false;
        _manualOverrideState = null;
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error clearing override: $e");
    }
  }

  Future<void> startManualPump() async {
    if (!canStartPump) {
      debugPrint("Cannot start pump - moisture too high and safety enabled");
      return;
    }

    mode = IrrigationMode.manual;
    _isManualOverrideActive = true;
    _manualOverrideState = 'ON';
    notifyListeners();

    try {
      final response = await http
          .post(Uri.parse('$backendBaseUrl/pump/on'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        debugPrint("✓ Manual pump ON");
      } else {
        throw Exception('Failed: ${response.statusCode}');
      }
    } catch (e) {
      _isManualOverrideActive = false;
      _manualOverrideState = null;
      mode = IrrigationMode.automated;
      notifyListeners();
    }
  }

  Future<void> stopPumpAction({bool fromModeChange = false}) async {
    if (!canStopPump) {
      debugPrint("Cannot stop pump - moisture too low and safety enabled");
      return;
    }

    mode = IrrigationMode.manual;
    _isManualOverrideActive = true;
    _manualOverrideState = 'OFF';
    notifyListeners();

    try {
      final response = await http
          .post(Uri.parse('$backendBaseUrl/pump/off'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        debugPrint("✓ Manual pump OFF");
      }
    } catch (e) {
      debugPrint("Error stopping pump: $e");
    }
  }

  void _connectWebSocket() {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(backendWebSocketUrl));

      _channel!.stream.listen(
        (message) {
          try {
            final data = json.decode(message);
            _processWebSocketData(data);
          } catch (e) {
            debugPrint("Error processing WebSocket: $e");
          }
        },
        onDone: () {
          if (mounted) _reconnectWebSocket();
        },
        onError: (error) {
          if (mounted) _reconnectWebSocket();
        },
        cancelOnError: true,
      );
      _reconnectTimer?.cancel();
    } catch (_) {
      if (mounted) _reconnectWebSocket();
    }
  }

  // Analytics (kept as-is)
  Future<Map<String, dynamic>> fetchAnalyticsData({
    int hours = 24,
    String metric = 'all',
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse('$backendBaseUrl/analytics/telemetry').replace(
              queryParameters: {'hours': hours.toString(), 'metric': metric},
            ),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to fetch analytics: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching analytics: $e');
      rethrow;
    }
  }

  void _processWebSocketData(Map<String, dynamic> data) {
    // Use ValueNotifiers for granular updates
    final bool newPumpStatus = data['pump_is_on'] as bool? ?? false;
    final String newPumpStatusStr = newPumpStatus ? 'ON' : 'OFF';

    if (pumpStatusNotifier.value != newPumpStatusStr) {
      pumpStatusNotifier.value = newPumpStatusStr;
    }

    final double newFlowRate =
        (data['current_flow_lpm'] as num?)?.toDouble() ?? 0.0;
    final double correctedFlowRate = newPumpStatus ? newFlowRate : 0.0;
    if (flowRateNotifier.value != correctedFlowRate) {
      flowRateNotifier.value = correctedFlowRate;
    }

    final double newSoilMoisture =
        (data['moisture'] as num?)?.toDouble() ?? soilMoisture;
    if (soilMoistureNotifier.value != newSoilMoisture) {
      soilMoistureNotifier.value = newSoilMoisture;
    }

    if (data.containsKey('total_flow')) {
      final double newTotalVolume =
          (data['total_flow'] as num?)?.toDouble() ?? totalVolume;
      if (totalVolumeNotifier.value != newTotalVolume) {
        totalVolumeNotifier.value = newTotalVolume;
      }
    }

    final double newCycleUsage =
        (data['current_cycle_volume_l'] as num?)?.toDouble() ??
        (newPumpStatus ? cycleUsage : 0.0);
    if (data.containsKey('current_cycle_volume_l') || !newPumpStatus) {
      if (cycleUsageNotifier.value != newCycleUsage) {
        cycleUsageNotifier.value = newCycleUsage;
      }
    }

    bool needsNotify = false;

    final bool newAutomatedModeEnabled =
        data['automated_mode_enabled'] as bool? ?? _automatedModeEnabled;
    if (_automatedModeEnabled != newAutomatedModeEnabled) {
      _automatedModeEnabled = newAutomatedModeEnabled;
      needsNotify = true;
    }

    final bool newManualOverrideActive =
        data['manual_override_active'] as bool? ?? false;
    if (_isManualOverrideActive != newManualOverrideActive) {
      _isManualOverrideActive = newManualOverrideActive;
      needsNotify = true;
    }

    final String? newManualOverrideState =
        data['manual_override_state'] as String?;
    if (_manualOverrideState != newManualOverrideState) {
      _manualOverrideState = newManualOverrideState;
      needsNotify = true;
    }

    final bool newAllowManualOverride =
        data['allow_manual_override_at_any_moisture'] as bool? ?? true;
    if (_allowManualOverrideAtAnyMoisture != newAllowManualOverride) {
      _allowManualOverrideAtAnyMoisture = newAllowManualOverride;
      needsNotify = true;
    }

    final String? newScheduleName = data['current_schedule_name'] as String?;
    final String? scheduleEndStr = data['schedule_end_time'] as String?;
    DateTime? newScheduleEnd;
    if (scheduleEndStr != null) {
      try {
        newScheduleEnd = DateTime.parse(scheduleEndStr);
      } catch (_) {
        newScheduleEnd = null;
      }
    }

    if (_currentScheduleName != newScheduleName) {
      _currentScheduleName = newScheduleName;
      needsNotify = true;
    }

    if (_scheduleEndTime != newScheduleEnd) {
      _scheduleEndTime = newScheduleEnd;
      needsNotify = true;
    }

    // In-app notifications (2-threshold system)
    if (_automatedModeEnabled &&
        _lowMoistureAlertEnabled &&
        !_isManualOverrideActive) {
      // Critical Low
      if (soilMoisture < _criticalLowThreshold && !_lowMoistureAlertShown) {
        _lowMoistureAlertShown = true;
        _highMoistureAlertShown = false;
        _addNotification(
          'Critical Low Moisture',
          'Soil moisture critically LOW (${soilMoisture.toStringAsFixed(1)}%).',
          'low_moisture',
        );
      }
      // Critical High
      else if (soilMoisture > _criticalHighThreshold &&
          !_highMoistureAlertShown) {
        _highMoistureAlertShown = true;
        _lowMoistureAlertShown = false;
        _addNotification(
          'Critical High Moisture',
          'Soil moisture CRITICALLY HIGH (${soilMoisture.toStringAsFixed(1)}%).',
          'high_moisture',
        );
      }
      // Normal Zone
      else if (soilMoisture >= _criticalLowThreshold &&
          soilMoisture <= _criticalHighThreshold) {
        if (_lowMoistureAlertShown || _highMoistureAlertShown) {
          _lowMoistureAlertShown = false;
          _highMoistureAlertShown = false;
        }
      }
    }

    // Flow Rate Anomaly Detection
    if (pumpStatus == 'ON' && flowRate > 0) {
      final now = DateTime.now();
      if (_lastFlowRateCheck != null && _lastFlowRate > 0) {
        final timeDiff = now.difference(_lastFlowRateCheck!).inSeconds;
        if (timeDiff >= 10) {
          final flowRateChange =
              ((flowRate - _lastFlowRate) / _lastFlowRate * 100).abs();

          if (flowRateChange > 30) {
            _addNotification(
              'Flow Rate Alert',
              'Flow rate changed by ${flowRateChange.toStringAsFixed(1)}%.',
              'flow_rate_anomaly',
            );
          }

          _lastFlowRate = flowRate;
          _lastFlowRateCheck = now;
        }
      } else {
        _lastFlowRate = flowRate;
        _lastFlowRateCheck = now;
      }
    } else {
      _lastFlowRate = 0.0;
      _lastFlowRateCheck = null;
    }

    if (needsNotify) {
      notifyListeners();
    }
  }

  void _reconnectWebSocket() {
    if (_reconnectTimer != null && _reconnectTimer!.isActive) return;
    _channel?.sink.close();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) _connectWebSocket();
    });
  }

  Future<void> fetchAlerts() async {
    if (_isLoadingAlerts) return;

    _isLoadingAlerts = true;
    _alertsError = '';
    notifyListeners();

    try {
      final response = await http
          .get(Uri.parse('$backendBaseUrl/alerts/list'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final Map<String, dynamic> decoded = json.decode(response.body);
        if (decoded.containsKey('items') && decoded['items'] is List) {
          final List<dynamic> data = decoded['items'];

          _alerts = data
              .map((jsonItem) {
                if (jsonItem is Map<String, dynamic>) {
                  try {
                    return Alert.fromJson(jsonItem);
                  } catch (_) {
                    return null;
                  }
                }
                return null;
              })
              .whereType<Alert>()
              .toList();

          _alerts.sort((a, b) => b.alertTime.compareTo(a.alertTime));
        }
      } else {
        _alertsError = "Failed to load alerts: ${response.statusCode}";
      }
    } catch (e) {
      _alertsError = "Error fetching alerts: $e";
    } finally {
      _isLoadingAlerts = false;
      notifyListeners();
    }
  }

  void _startAlertRefreshTimer() {
    _alertRefreshTimer?.cancel();
    if (_alertScreenActive) {
      _alertRefreshTimer = Timer.periodic(
        const Duration(seconds: alertRefreshInterval),
        (_) => fetchAlerts(),
      );
    }
  }

  Future<void> fetchSchedules() async {
    List<IrrigationSchedule> fetchedSchedules = [];
    try {
      final response = await http
          .get(Uri.parse('$backendBaseUrl/schedule/list'))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final Map<String, dynamic> decoded = json.decode(response.body);
        if (decoded.containsKey('items') && decoded['items'] is List) {
          final List<dynamic> data = decoded['items'];

          fetchedSchedules = data
              .map((jsonItem) {
                if (jsonItem is Map<String, dynamic>) {
                  try {
                    return IrrigationSchedule.fromJson(jsonItem);
                  } catch (_) {
                    return null;
                  }
                }
                return null;
              })
              .whereType<IrrigationSchedule>()
              .toList();
        }
      }
    } catch (e) {
      debugPrint("Error fetching schedules: $e");
    }
    schedules = fetchedSchedules;
    notifyListeners();
  }

  Future<bool> setScheduleActive(String scheduleId, bool isActive) async {
    final int index = schedules.indexWhere((s) => s.id == scheduleId);
    if (index != -1) {
      final oldSchedule = schedules[index];
      schedules[index] = IrrigationSchedule(
        id: oldSchedule.id,
        time: oldSchedule.time,
        duration: oldSchedule.duration,
        isEnabled: isActive,
        name: oldSchedule.name,
        repeatDays: oldSchedule.repeatDays,
      );
      notifyListeners();
    }

    final String endpoint = isActive ? 'resume' : 'pause';
    try {
      final response = await http
          .post(Uri.parse('$backendBaseUrl/schedule/$endpoint/$scheduleId'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        fetchSchedules();
        return true;
      } else {
        await fetchSchedules();
        return false;
      }
    } catch (_) {
      await fetchSchedules();
      return false;
    }
  }

  Future<bool> deleteSchedule(String scheduleId) async {
    try {
      final response = await http
          .delete(Uri.parse('$backendBaseUrl/schedule/delete/$scheduleId'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        schedules.removeWhere((s) => s.id == scheduleId);
        notifyListeners();
        return true;
      } else {
        await fetchSchedules();
        return false;
      }
    } catch (_) {
      await fetchSchedules();
      return false;
    }
  }

  Future<void> fetchAuditHistory() async {
    if (isLoadingHistory) return;
    isLoadingHistory = true;
    historyError = '';
    notifyListeners();

    List<AuditEvent> fetchedHistory = [];
    try {
      final response = await http
          .get(Uri.parse('$backendBaseUrl/history/pump_runs'))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final Map<String, dynamic> decoded = json.decode(response.body);
        if (decoded.containsKey('items') && decoded['items'] is List) {
          final List<dynamic> data = decoded['items'];
          fetchedHistory = data
              .map((jsonItem) {
                if (jsonItem is Map<String, dynamic>) {
                  try {
                    return AuditEvent.fromJson(jsonItem);
                  } catch (_) {
                    return null;
                  }
                }
                return null;
              })
              .whereType<AuditEvent>()
              .toList();
          fetchedHistory.sort((a, b) => b.eventTime.compareTo(a.eventTime));
          auditHistory = fetchedHistory;
        }
      } else {
        historyError = "Failed to load history: ${response.statusCode}";
      }
    } catch (e) {
      historyError = "Error fetching history: $e";
    } finally {
      isLoadingHistory = false;
      notifyListeners();
    }
  }

  Future<void> _addNotification(
    String title,
    String message,
    String titleKey,
  ) async {
    final notification = NotificationItem(
      title: title,
      message: message,
      timestamp: DateTime.now(),
      titleKey: titleKey,
    );

    _notifications.insert(0, notification);
    if (_notifications.length > maxNotifications) {
      _notifications = _notifications.sublist(0, maxNotifications);
    }
    _hasUnreadNotifications = true;

    // Audio removed: only vibrate if enabled and available
    if (_alertVibrationEnabled && (_hasVibrator ?? false)) {
      try {
        Vibration.vibrate(duration: 300);
      } catch (e) {
        debugPrint("Error vibrating: $e");
      }
    }

    notifyListeners();
  }

  void markNotificationsAsRead() {
    if (_hasUnreadNotifications) {
      _hasUnreadNotifications = false;
      notifyListeners();
    }
  }

  void clearNotifications() {
    _notifications.clear();
    _hasUnreadNotifications = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _mounted = false;
    _reconnectTimer?.cancel();
    _alertRefreshTimer?.cancel();
    _channel?.sink.close();
    pumpStatusNotifier.dispose();
    soilMoistureNotifier.dispose();
    flowRateNotifier.dispose();
    totalVolumeNotifier.dispose();
    cycleUsageNotifier.dispose();
    super.dispose();
  }

  bool _mounted = true;
  bool get mounted => _mounted;
}

final appController = AppController();