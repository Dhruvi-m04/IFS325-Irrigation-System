import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../controller.dart';
import '../constants.dart';
import '../models.dart';
import '../widgets/gradient_app_bar.dart';
import '../widgets/notification_panel.dart';

// ============================================================================
// HISTORY SCREEN - OPTIMIZED WITH KEYS
// ============================================================================
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  // Cached date formatter
  static final _dateFormatter = DateFormat('MMM d, yyyy  h:mm:ss a');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (appController.auditHistory.isEmpty && !appController.isLoadingHistory) {
        appController.fetchAuditHistory();
      }
    });
  }

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

  Icon _getEventIcon(AuditEvent event) {
    String descLower = event.description.toLowerCase();
    String sourceLower = event.source.toLowerCase();

    if (descLower.contains('pump turned on')) {
      return Icon(Icons.power, color: Colors.green.shade600, size: 28);
    } else if (descLower.contains('pump turned off')) {
      return Icon(Icons.power_off, color: Colors.grey.shade600, size: 28);
    } else if (descLower.contains('schedule cancelled')) {
      return Icon(Icons.cancel_schedule_send_outlined, color: Colors.orange.shade700, size: 28);
    } else if (sourceLower.contains('automated')) {
      return Icon(Icons.auto_mode, color: Colors.blue.shade600, size: 28);
    } else if (sourceLower.contains('api') || sourceLower.contains('manual')) {
      return Icon(Icons.touch_app, color: Colors.purple.shade400, size: 28);
    } else if (sourceLower.contains('schedule')) {
      return Icon(Icons.schedule, color: Colors.teal.shade600, size: 28);
    }
    return Icon(Icons.info_outline, color: Colors.blueGrey.shade400, size: 28);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildGradientAppBar(
        context,
        'Event History',
        onNotificationTap: _showNotificationPanel,
      ),
      body: ListenableBuilder(
        listenable: appController,
        builder: (context, child) {
          if (appController.isLoadingHistory && appController.auditHistory.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (appController.historyError.isNotEmpty && appController.auditHistory.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, color: Colors.red.shade300, size: 64),
                  const SizedBox(height: 16),
                  Text('Error Loading History', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0),
                    child: Text(
                      appController.historyError,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text("Retry"),
                    onPressed: () => appController.fetchAuditHistory(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(primaryColor),
                      foregroundColor: Colors.white,
                    ),
                  )
                ],
              ),
            );
          }

          if (appController.auditHistory.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_toggle_off_outlined, color: Colors.grey.shade400, size: 80),
                  const SizedBox(height: 24),
                  Text(
                    'No History Found',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pump events will appear here.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => appController.fetchAuditHistory(),
            color: const Color(primaryColor),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              itemCount: appController.auditHistory.length,
              itemBuilder: (context, index) {
                final event = appController.auditHistory[index];
                final formattedTime = _dateFormatter.format(event.eventTime);

                return ListTile(
                  key: ValueKey('${event.deviceUid}_${event.eventTime.millisecondsSinceEpoch}'), // Added key
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                    child: _getEventIcon(event),
                  ),
                  title: Text(
                    event.description,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    'Triggered by: ${event.source}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  trailing: Text(
                    formattedTime,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                );
              },
              separatorBuilder: (context, index) => const Divider(height: 1, indent: 72),
            ),
          );
        },
      ),
    );
  }
}