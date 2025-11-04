import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../controller.dart';
import '../constants.dart';

// ============================================================================
// PUMP STATUS CARD - OPTIMIZED WITH VALUELISTENABLEBUILDER
// ============================================================================
class PumpStatusCard extends StatefulWidget {
  final AnimationController pulseAnimation;
  
  const PumpStatusCard({super.key, required this.pulseAnimation});

  @override
  State<PumpStatusCard> createState() => _PumpStatusCardState();
}

class _PumpStatusCardState extends State<PumpStatusCard> {
  String _currentTime = '';
  Timer? _scheduleTimer;
  
  @override
  void initState() {
    super.initState();
    _updateTime();
    _startScheduleTimer();
  }
  
  void _updateTime() {
    if (mounted) {
      setState(() {
        _currentTime = DateFormat('h:mm a').format(DateTime.now());
      });
    }
  }
  
  void _startScheduleTimer() {
    _scheduleTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateTime();
      if (mounted && appController.scheduleEndTime != null) {
        setState(() {});
      }
    });
  }
  
  String _getTimeRemaining() {
    if (appController.scheduleEndTime == null) return '';
    
    final now = DateTime.now();
    final diff = appController.scheduleEndTime!.difference(now);
    
    if (diff.isNegative) return 'Ending...';
    
    final hours = diff.inHours;
    final minutes = diff.inMinutes.remainder(60);
    final seconds = diff.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }
  
  @override
  void dispose() {
    _scheduleTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: appController.pumpStatusNotifier,
      builder: (context, pumpStatus, child) {
        return ListenableBuilder(
          listenable: appController,
          builder: (context, _) {
            final isPumpOn = pumpStatus == 'ON';
            final cardColor = isPumpOn ? const Color(secondaryColor) : Colors.grey.shade400;
            final textColor = isPumpOn ? Colors.white : Colors.black;
            final isManualOverride = appController.isManualOverrideActive;
            final isScheduled = appController.currentScheduleName != null;
            
            String mainStatusDisplay = isPumpOn ? 'RUNNING' : 'OFF';
            String contextLabel = '';
            
            if (isScheduled && isPumpOn) {
              final scheduleName = appController.currentScheduleName ?? 'SCHEDULED';
              contextLabel = scheduleName.length > 15 ? '${scheduleName.substring(0, 15)}...' : scheduleName;
            } else if (isManualOverride) {
              contextLabel = 'MANUAL';
            } else if (isPumpOn && appController.automatedModeEnabled) {
              contextLabel = 'AUTO';
            }
            
            return Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              color: cardColor,
              child: Padding(
                padding: const EdgeInsets.all(14.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Pump',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: textColor.withOpacity(0.8)
                          )
                        ),
                        Text(
                          _currentTime,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: textColor.withOpacity(0.8)
                          )
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              mainStatusDisplay,
                              style: TextStyle(
                                fontSize: 32,
                                color: textColor,
                                fontWeight: FontWeight.bold,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                        if (contextLabel.isNotEmpty)
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                              decoration: BoxDecoration(
                                color: textColor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                contextLabel,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                  letterSpacing: 0.3,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (isScheduled && isPumpOn && appController.scheduleEndTime != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _getTimeRemaining(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: textColor.withOpacity(0.9),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}