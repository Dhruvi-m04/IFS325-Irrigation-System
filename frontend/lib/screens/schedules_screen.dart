import 'package:flutter/material.dart';
import '../controller.dart';
import '../constants.dart';
import '../models.dart';
import '../utils.dart';
import '../widgets/gradient_app_bar.dart';
import '../widgets/notification_panel.dart';
import 'schedule_editor_screen.dart';

// ============================================================================
// SCHEDULES SCREEN - OPTIMIZED WITH KEYS
// ============================================================================
class SchedulesScreen extends StatefulWidget {
  const SchedulesScreen({super.key});

  @override
  State<SchedulesScreen> createState() => _SchedulesScreenState();
}

class _SchedulesScreenState extends State<SchedulesScreen> {
  void _showNotificationPanel() {
    appController.markNotificationsAsRead();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        builder: (context, scrollController) => NotificationPanel(scrollController: scrollController),
      ),
    );
  }

  void _openScheduleEditor(IrrigationSchedule? existingSchedule) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ScheduleEditorScreen(
          schedule: existingSchedule,
          onSave: () => appController.fetchSchedules(),
          onDelete: existingSchedule != null 
            ? () {
                Navigator.of(context).pop();
                _confirmAndDelete(existingSchedule);
              }
            : null,
        ),
      ),
    );
  }

  Future<void> _toggleSchedule(IrrigationSchedule schedule, bool newState) async {
    appController.setScheduleActive(schedule.id, newState);
  }

  Future<void> _confirmAndDelete(IrrigationSchedule schedule) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Delete Schedule?',
          style: TextStyle(color: Color(primaryColor)),
        ),
        content: Text('Are you sure you want to permanently delete "${schedule.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(errorColor),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await appController.deleteSchedule(schedule.id);
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Schedule deleted successfully.'),
            backgroundColor: Color(successColor),
            duration: Duration(seconds: 1),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete schedule.'),
            backgroundColor: Color(errorColor),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  String _getScheduleDetails(IrrigationSchedule schedule) {
    final repeats = schedule.repeatDays.any((day) => day == true);
    
    if (repeats) {
      return formatRepeatDays(schedule.repeatDays);
    } else {
      if (schedule.name.startsWith('One-time on')) {
        return schedule.name;
      }
      return 'One-time job';
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: buildGradientAppBar(
        context,
        'Irrigation Schedules',
        onNotificationTap: _showNotificationPanel,
      ),
      body: ListenableBuilder(
        listenable: appController,
        builder: (context, child) {
          if (appController.schedules.isEmpty) {
            return Center( 
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.schedule_outlined,
                    size: 80,
                    color: const Color(primaryColor).withOpacity(0.3),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'No Schedules Found',
                    style: textTheme.headlineSmall?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap the + button to create your first schedule.',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.6),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              await appController.fetchSchedules();
            },
            color: const Color(primaryColor),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: appController.schedules.length,
              itemBuilder: (context, index) {
                final schedule = appController.schedules[index];
                final scheduleDetails = _getScheduleDetails(schedule);
                final bool isEnabled = schedule.isEnabled;

                final Color primaryColorValue = isEnabled 
                    ? const Color(primaryColor)
                    : colorScheme.onSurface.withOpacity(0.4);
                final Color secondaryColorValue = isEnabled 
                    ? Colors.grey.shade600 
                    : Colors.grey.shade500;
                final Color headlineColorValue = isEnabled 
                    ? const Color(primaryColor)
                    : colorScheme.onSurface.withOpacity(0.5);

                return Card(
                  key: ValueKey(schedule.id), // Added key for optimization
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: isEnabled ? 2 : 0.5,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _openScheduleEditor(schedule),
                    onLongPress: () => _confirmAndDelete(schedule),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16.0, 16.0, 8.0, 16.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      schedule.time.format(context),
                                      style: textTheme.headlineMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: headlineColorValue,
                                        height: 1.1,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Pump ON (Local Time)',
                                      style: textTheme.bodySmall?.copyWith(
                                        color: secondaryColorValue,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),

                                if (schedule.name.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4.0),
                                    child: Text(
                                      schedule.name,
                                      style: textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w500,
                                        color: colorScheme.onSurface.withOpacity(
                                          isEnabled ? 1.0 : 0.5
                                        ),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),

                                Text(
                                  scheduleDetails,
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant.withOpacity(
                                      isEnabled ? 1.0 : 0.5
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),

                                Row(
                                  children: [
                                    Icon(Icons.timer_outlined, size: 14, color: secondaryColorValue),
                                    const SizedBox(width: 4),
                                    Text(
                                      formatScheduleDuration(schedule.duration),
                                      style: textTheme.bodySmall?.copyWith(color: secondaryColorValue),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: isEnabled,
                            onChanged: (newState) {
                              _toggleSchedule(schedule, newState);
                            },
                            activeColor: const Color(secondaryColor),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openScheduleEditor(null),
        backgroundColor: const Color(secondaryColor),
        foregroundColor: Colors.white,
        tooltip: 'Add Schedule',
        child: const Icon(Icons.add),
      ),
    );
  }
}