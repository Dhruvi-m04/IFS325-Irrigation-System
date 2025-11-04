import 'package:flutter/material.dart';
import '../controller.dart';
import '../constants.dart';
import './dashboard_screen.dart';
import './history_screen.dart';
import './analytics_screen.dart';
import './settings_screen.dart';
import './schedules_screen.dart';

// ============================================================================
// MAIN SCREEN WRAPPER - OPTIMIZED
// ============================================================================
class MainScreenWrapper extends StatefulWidget {
  const MainScreenWrapper({super.key});

  @override
  State<MainScreenWrapper> createState() => MainScreenWrapperState();
}

class MainScreenWrapperState extends State<MainScreenWrapper> {
  int _selectedIndex = 0;

  static const List<Widget> _screens = [
    DashboardScreen(),
    SchedulesScreen(),
    HistoryScreen(),
    AnalyticsScreen(),
    SettingsScreen(),
  ];

  void onItemTapped(int index) {
    setState(() => _selectedIndex = index);

    // Background data refresh on tab tap
    switch (index) {
      case 1: // Schedules Tab
        appController.fetchSchedules();
        break;
      case 2: // History Tab
        appController.fetchAuditHistory();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(toolbarHeight: 0, elevation: 0),
      body: IndexedStack(index: _selectedIndex, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.schedule_outlined),
            activeIcon: Icon(Icons.schedule),
            label: 'Schedules',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history_toggle_off_outlined),
            activeIcon: Icon(Icons.history),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.analytics_outlined),
            activeIcon: Icon(Icons.analytics),
            label: 'Analytics',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: const Color(primaryColor),
        unselectedItemColor: Colors.grey,
        onTap: onItemTapped,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        elevation: 8,
      ),
    );
  }
}