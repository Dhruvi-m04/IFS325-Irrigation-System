import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// ============================================================================
// DATA MODELS
// ============================================================================
class DataPoint {
  final DateTime date;
  final double value;
  const DataPoint(this.date, this.value);
}

class NotificationItem {
  final String title;
  final String message;
  final DateTime timestamp;
  final String titleKey;

  const NotificationItem({
    required this.title,
    required this.message,
    required this.timestamp,
    required this.titleKey,
  });
}

// Database-Backed Alert Model (Read-Only)
class Alert {
  final int id;
  final String deviceUid;
  final DateTime alertTime;
  final String alertType;
  final String message;
  final String severity; 
  final String status; 

  const Alert({
    required this.id,
    required this.deviceUid,
    required this.alertTime,
    required this.alertType,
    required this.message,
    required this.severity,
    required this.status,
  });

  factory Alert.fromJson(Map<String, dynamic> json) {
    DateTime parsedTime;
    try {
      parsedTime = DateTime.parse(json['alert_time'] as String? ?? '').toLocal();
    } catch (e) {
      debugPrint("Error parsing alert_time: ${json['alert_time']} -> $e");
      parsedTime = DateTime.now();
    }

    return Alert(
      id: (json['id'] as num?)?.toInt() ?? 0,
      deviceUid: json['device_uid'] as String? ?? '',
      alertTime: parsedTime,
      alertType: json['alert_type'] as String? ?? 'UNKNOWN',
      message: json['message'] as String? ?? 'No message',
      severity: json['severity'] as String? ?? 'INFO',
      status: json['status'] as String? ?? 'new',
    );
  }

  bool get isUnread => status == 'new';
  
  bool get isCritical => severity == 'CRITICAL';
  
  bool get isWarning => severity == 'WARNING';
  
  bool get isInfo => severity == 'INFO';
}

class IrrigationSchedule {
  final String id; 
  final TimeOfDay time;
  final Duration duration; 
  final bool isEnabled;
  final String name;
  final List<bool> repeatDays;

  const IrrigationSchedule({
    required this.id,
    required this.time,
    required this.duration,
    required this.isEnabled,
    required this.name,
    required this.repeatDays,
  });

  static List<bool> _parseRepeatDaysFromString(String? daysStr) {
    final daysList = List.filled(7, false);
    if (daysStr == null || daysStr.isEmpty) {
        return daysList;
    }
    
    if (daysStr.contains('-')) {
      return daysList;
    }

    const dayMap = {'sun': 0, 'mon': 1, 'tue': 2, 'wed': 3, 'thu': 4, 'fri': 5, 'sat': 6};
    final days = daysStr.toLowerCase().split(',');
    bool anyDaySet = false;
    for (final day in days) {
      final trimmedDay = day.trim();
      if (dayMap.containsKey(trimmedDay)) {
        daysList[dayMap[trimmedDay]!] = true;
        anyDaySet = true;
      }
    }
    return anyDaySet ? daysList : List.filled(7, false);
  }

  factory IrrigationSchedule.fromJson(Map<String, dynamic> json) {
    TimeOfDay parsedTime;
    try {
      final timeParts = (json['start_time_of_day'] as String? ?? '00:00:00').split(':');
      parsedTime = TimeOfDay(
        hour: int.parse(timeParts[0]),
        minute: int.parse(timeParts[1]),
      );
    } catch (e) {
      debugPrint("Error parsing start_time_of_day: ${json['start_time_of_day']} -> $e");
      parsedTime = const TimeOfDay(hour: 0, minute: 0);
    }
    
    final int parsedDurationMinutes = (json['duration_min'] as num?)?.toInt() ?? 15;
    final Duration scheduleDuration = Duration(minutes: parsedDurationMinutes);

    final String? parsedRepeatDaysStr = json['repeat_days'] as String?;
    final List<bool> scheduleRepeatDays = _parseRepeatDaysFromString(parsedRepeatDaysStr);
    
    DateTime? oneTimeDate;
    if(parsedRepeatDaysStr != null && parsedRepeatDaysStr.contains('-')) {
      try {
        oneTimeDate = DateTime.parse(parsedRepeatDaysStr);
      } catch(e) { /* ignore */ }
    }
    
    final String jobName = json['name'] as String? ?? 'Scheduled Irrigation';
    final String jobId = (json['id'] as num? ?? 0).toString();
    final bool scheduleIsEnabled = (json['is_active'] as num?) == 1;

    String finalName = jobName;
    if (oneTimeDate != null && jobName == 'Scheduled Irrigation') {
      finalName = 'One-time on ${DateFormat('MMM d, yyyy').format(oneTimeDate)}';
    }

    return IrrigationSchedule(
      id: jobId,
      name: finalName,
      time: parsedTime,
      duration: scheduleDuration,
      repeatDays: scheduleRepeatDays,
      isEnabled: scheduleIsEnabled,
    );
  }
}

class AuditEvent {
  final String deviceName;
  final String deviceUid;
  final DateTime eventTime;
  final String description;
  final String source;

  const AuditEvent({
    required this.deviceName,
    required this.deviceUid,
    required this.eventTime,
    required this.description,
    required this.source,
  });

  factory AuditEvent.fromJson(Map<String, dynamic> json) {
    DateTime parsedTime;
    try {
      parsedTime = DateTime.parse(json['event_time'] as String? ?? '').toLocal();
    } catch (e) {
      debugPrint("Error parsing audit event_time: ${json['event_time']} -> $e");
      parsedTime = DateTime(1970);
    }

    return AuditEvent(
      deviceName: json['device_name'] as String? ?? 'Unknown Device',
      deviceUid: json['device_uid'] as String? ?? 'Unknown UID',
      eventTime: parsedTime,
      description: json['description'] as String? ?? 'No description',
      source: json['source'] as String? ?? 'Unknown source',
    );
  }
}

// ============================================================================
// ENUMS
// ============================================================================
enum IrrigationMode { automated, scheduled, manual }
enum MetricSystem { metric, imperial }