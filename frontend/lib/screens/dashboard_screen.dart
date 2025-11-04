import 'package:flutter/material.dart';
import 'dart:async';
import '../controller.dart';
import '../constants.dart';
import '../widgets/gradient_app_bar.dart';
import '../widgets/notification_panel.dart';
import '../widgets/dashboard_metrics.dart';
import '../widgets/pump_status_card.dart';
import '../widgets/manual_control_card.dart';

// ============================================================================
// DASHBOARD SCREEN - OPTIMIZED WITH SELECTIVE REBUILDS
// ============================================================================
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  Timer? _clockTimer;
  
  @override
  void initState() {
    super.initState();
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    

    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {}); 
    });
  }
  
  @override
  void dispose() {
    _pulseController.dispose();
    _clockTimer?.cancel();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildGradientAppBar(context, 'Irrigation', onNotificationTap: _showNotificationPanel),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            PumpStatusCard(pulseAnimation: _pulseController),
            const SizedBox(height: 16),

            const AutomatedModeToggle(),
            const SizedBox(height: 16),
            

            const ManualControlCard(),
            const SizedBox(height: 16),
            

            const DashboardMetricsGrid(),
          ],
        ),
      ),
    );
  }
}


class AutomatedModeToggle extends StatelessWidget {
  const AutomatedModeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appController,
      builder: (context, child) {
        final isEnabled = appController.automatedModeEnabled;
        
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: isEnabled
                  ? [const Color(primaryColor).withOpacity(0.15), const Color(accentColor).withOpacity(0.15)]
                  : [const Color(primaryColor).withOpacity(0.05), const Color(primaryColor).withOpacity(0.08)],
            ),
            border: Border.all(
              color: isEnabled ? const Color(primaryColor).withOpacity(0.4) : const Color(primaryColor).withOpacity(0.2),
              width: 2,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                const Icon(
                  Icons.auto_awesome,
                  size: 24,
                  color: Color(primaryColor),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Automated Mode',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(primaryColor),
                    ),
                  ),
                ),
                Switch(
                  value: isEnabled,
                  onChanged: (value) => appController.setAutomatedModeEnabled(value),
                  activeColor: const Color(secondaryColor),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}