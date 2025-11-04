import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../controller.dart';
import '../constants.dart';

// ============================================================================
// NOTIFICATION PANEL - OPTIMIZED WITH CACHED FORMATTER
// ============================================================================
class NotificationPanel extends StatelessWidget {
  final ScrollController scrollController;
  
  // Cached date formatter
  static final _dateFormatter = DateFormat('MMM d, h:mm a');

  const NotificationPanel({super.key, required this.scrollController});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appController,
      builder: (context, child) {
        final notifications = appController.notifications;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Notifications', style: TextStyle(color: Colors.white)),
            automaticallyImplyLeading: false,
            flexibleSpace: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(gradientStart),
                    Color(gradientEnd),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            actions: [
              if (notifications.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear_all, color: Colors.white),
                  tooltip: 'Clear All',
                  onPressed: appController.clearNotifications,
                ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          body: notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.notifications_none,
                        size: 80,
                        color: const Color(primaryColor).withOpacity(0.3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No notifications yet.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onBackground.withOpacity(0.6),
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: scrollController,
                  itemCount: notifications.length,
                  itemBuilder: (context, index) {
                    final notification = notifications[index];
                    return Card(
                      key: ValueKey('${notification.titleKey}_${notification.timestamp.millisecondsSinceEpoch}'), // Added key
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: _getNotificationIcon(notification),
                        title: Text(
                          notification.title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(notification.message),
                            const SizedBox(height: 4),
                            Text(
                              _dateFormatter.format(notification.timestamp),
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                              ),
                            ),
                          ],
                        ),
                        isThreeLine: true,
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  Widget _getNotificationIcon(notification) {
    IconData iconData;
    Color iconColor;

    switch (notification.titleKey) {
      case 'pump_on':
        iconData = Icons.power;
        iconColor = const Color(successColor);
        break;
      case 'pump_off':
        iconData = Icons.power_off;
        iconColor = Colors.grey;
        break;
      case 'manual_start':
        iconData = Icons.play_arrow;
        iconColor = const Color(primaryColor);
        break;
      case 'manual_stop':
        iconData = Icons.stop;
        iconColor = const Color(errorColor);
        break;
      case 'low_moisture':
        iconData = Icons.opacity;
        iconColor = const Color(warningColor);
        break;
      case 'high_moisture':
        iconData = Icons.water_drop;
        iconColor = const Color(accentColor);
        break;
      case 'flow_rate_anomaly':
        iconData = Icons.warning;
        iconColor = const Color(warningColor);
        break;
      default:
        iconData = Icons.notifications;
        iconColor = const Color(primaryColor);
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(iconData, color: iconColor, size: 24),
    );
  }
}