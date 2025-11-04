import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'constants.dart';
import 'models.dart';

// ============================================================================
// UTILITY FUNCTIONS - WITH CACHED FORMATTERS
// ============================================================================

// Cached date formatters for performance
final _dateTimeFormatter = DateFormat('MMM d, yyyy h:mm a');
final _dateFormatter = DateFormat('MMM d, yyyy');
final _timeFormatter = DateFormat('h:mm a');

String formatFlowRate(double lpm, MetricSystem system) {
  if (system == MetricSystem.metric) {
    return '${lpm.toStringAsFixed(1)} L/min';
  } else {
    final gpm = lpm / literPerGallon;
    return '${gpm.toStringAsFixed(1)} gal/min';
  }
}

String formatVolume(double liters, MetricSystem system) {
  if (system == MetricSystem.metric) {
    return '${liters.toStringAsFixed(1)} L';
  } else {
    final gallons = liters / literPerGallon;
    return '${gallons.toStringAsFixed(1)} gal';
  }
}

String formatScheduleDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  
  if (hours > 0 && minutes > 0) {
    return '$hours hr $minutes min';
  } else if (hours > 0) {
    return '$hours hr';
  } else {
    return '$minutes min';
  }
}

String formatRepeatDays(List<bool> repeatDays) {
  if (repeatDays.every((day) => day == true)) {
    return 'Every day';
  }
  
  if (repeatDays.every((day) => day == false)) {
    return 'One-time';
  }
  
  const dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  final selectedDays = <String>[];
  
  for (int i = 0; i < repeatDays.length; i++) {
    if (repeatDays[i]) {
      selectedDays.add(dayNames[i]);
    }
  }
  
  if (selectedDays.length <= 3) {
    return selectedDays.join(', ');
  } else {
    return '${selectedDays.take(2).join(', ')}, +${selectedDays.length - 2} more';
  }
}

String formatDateTime(DateTime dateTime) {
  return _dateTimeFormatter.format(dateTime);
}

String formatDate(DateTime date) {
  return _dateFormatter.format(date);
}

String formatTime(DateTime time) {
  return _timeFormatter.format(time);
}