import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../controller.dart';
import '../constants.dart';
import '../models.dart';
import '../widgets/gradient_app_bar.dart';

// ============================================================================
// ALERTS SCREEN - OPTIMIZED WITH LIFECYCLE MANAGEMENT
// ============================================================================
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  // Cached date formatter
  static final _dateFormatter = DateFormat('MMM d, yyyy  h:mm a');

  @override
  void initState() {
    super.initState();
    // Notify controller that alerts screen is active
    appController.setAlertScreenActive(true);
  }

  @override
  void dispose() {
    // Notify controller that alerts screen is inactive
    appController.setAlertScreenActive(false);
    super.dispose();
  }

  Icon _getAlertIcon(Alert alert) {
    IconData iconData;
    Color iconColor;

    switch (alert.alertType) {
      case 'CRITICAL_LOW_MOISTURE':
        iconData = Icons.water_damage;
        iconColor = const Color(errorColor);
        break;
      case 'OPTIMAL_REACHED':
        iconData = Icons.check_circle;
        iconColor = const Color(successColor);
        break;
      case 'OPTIMAL_MAINTAINED':
        iconData = Icons.thumb_up;
        iconColor = const Color(successColor);
        break;
      case 'HIGH_MOISTURE_WARNING':
        iconData = Icons.trending_up;
        iconColor = const Color(warningColor);
        break;
      case 'EMERGENCY_TOO_WET':
        iconData = Icons.warning_amber;
        iconColor = const Color(errorColor);
        break;
      case 'MANUAL_OVERRIDE_OPTIMAL':
        iconData = Icons.pan_tool;
        iconColor = const Color(warningColor);
        break;
      case 'MANUAL_OVERRIDE_HIGH':
        iconData = Icons.pan_tool;
        iconColor = const Color(errorColor);
        break;
      case 'MANUAL_OVERRIDE_NORMAL':
      case 'MANUAL_OVERRIDE_OFF':
        iconData = Icons.touch_app;
        iconColor = const Color(primaryColor);
        break;
      case 'LOW_MOISTURE':
        iconData = Icons.opacity;
        iconColor = const Color(errorColor);
        break;
      case 'HIGH_MOISTURE':
        iconData = Icons.water_drop;
        iconColor = const Color(accentColor);
        break;
      case 'FLOW_RATE_ANOMALY':
        iconData = Icons.warning;
        iconColor = const Color(warningColor);
        break;
      case 'PUMP_ON':
        iconData = Icons.power;
        iconColor = const Color(successColor);
        break;
      case 'PUMP_OFF':
        iconData = Icons.power_off;
        iconColor = Colors.grey.shade600;
        break;
      case 'SCHEDULE_CREATED':
      case 'SCHEDULE_DELETED':
        iconData = Icons.schedule;
        iconColor = const Color(primaryColor);
        break;
      case 'SYSTEM_START':
      case 'SYSTEM_SHUTDOWN':
        iconData = Icons.computer;
        iconColor = const Color(primaryColor);
        break;
      case 'AUTOMATED_MODE_ENABLED':
      case 'AUTOMATED_MODE_DISABLED':
        iconData = Icons.psychology;
        iconColor = const Color(primaryColor);
        break;
      default:
        iconData = Icons.notifications;
        iconColor = const Color(primaryColor);
    }

    return Icon(iconData, color: iconColor, size: 28);
  }

  Color _getSeverityColor(Alert alert) {
    switch (alert.severity) {
      case 'CRITICAL':
        return const Color(errorColor);
      case 'WARNING':
        return const Color(warningColor);
      default:
        return const Color(primaryColor);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildGradientAppBar(context, 'System Alerts'),
      body: ListenableBuilder(
        listenable: appController,
        builder: (context, child) {
          if (appController.isLoadingAlerts && appController.alerts.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (appController.alertsError.isNotEmpty && appController.alerts.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, color: Colors.red.shade300, size: 64),
                  const SizedBox(height: 16),
                  Text('Error Loading Alerts', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0),
                    child: Text(
                      appController.alertsError,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text("Retry"),
                    onPressed: () => appController.fetchAlerts(),
                  )
                ],
              ),
            );
          }

          if (appController.alerts.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none, color: Colors.grey.shade400, size: 80),
                  const SizedBox(height: 24),
                  Text(
                    'No Alerts',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'System alerts will appear here.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          final unreadCount = appController.unreadAlertCount;

          return Column(
            children: [
              if (unreadCount > 0)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(warningColor).withOpacity(0.15),
                        const Color(errorColor).withOpacity(0.15),
                      ],
                    ),
                    border: Border(
                      bottom: BorderSide(color: const Color(warningColor).withOpacity(0.3)),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.notification_important, color: Color(warningColor), size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '$unreadCount unread alert${unreadCount > 1 ? 's' : ''}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(warningColor),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Read-only view',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),

              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => appController.fetchAlerts(),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    itemCount: appController.alerts.length,
                    itemBuilder: (context, index) {
                      final alert = appController.alerts[index];
                      final formattedTime = _dateFormatter.format(alert.alertTime);
                      final severityColor = _getSeverityColor(alert);
                      final isUnread = alert.isUnread;

                      return Container(
                        key: ValueKey(alert.id), // Added key
                        color: isUnread
                            ? severityColor.withOpacity(0.05)
                            : Colors.transparent,
                        child: ListTile(
                          leading: Stack(
                            children: [
                              CircleAvatar(
                                backgroundColor: severityColor.withOpacity(0.15),
                                child: _getAlertIcon(alert),
                              ),
                              if (isUnread)
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: severityColor,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 2),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          title: Text(
                            alert.message,
                            style: TextStyle(
                              fontWeight: isUnread ? FontWeight.bold : FontWeight.w500,
                              color: isUnread ? severityColor : null,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: severityColor.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      alert.severity,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: severityColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    formattedTime,
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          trailing: isUnread
                              ? Icon(Icons.fiber_manual_record, color: severityColor, size: 12)
                              : Icon(Icons.check_circle, color: Colors.grey.shade400, size: 20),
                        ),
                      );
                    },
                    separatorBuilder: (context, index) => const Divider(height: 1, indent: 72),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}