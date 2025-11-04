import 'package:flutter/material.dart';
import '/controller.dart';
import '/constants.dart';
import 'screens/main_screen.dart';

// ============================================================================
// MAIN APP - OPTIMIZED
// ============================================================================
void main() {
  runApp(const ARCIrrigationApp());
}

class ARCIrrigationApp extends StatelessWidget {
  const ARCIrrigationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appController,
      builder: (context, child) => MaterialApp(
        title: 'ARC Irrigation System',
        debugShowCheckedModeBanner: false,
        themeMode: appController.themeMode,
        theme: _buildTheme(Brightness.light),
        darkTheme: _buildTheme(Brightness.dark),
        home: const MainScreenWrapper(),
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(primaryColor),
        primary: const Color(primaryColor),
        secondary: const Color(secondaryColor),
        tertiary: const Color(accentColor),
        error: const Color(errorColor),
        brightness: brightness,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(primaryColor),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Color(secondaryColor),
        foregroundColor: Colors.white,
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(primaryColor),
          foregroundColor: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const Color(secondaryColor);
          }
          return null;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const Color(secondaryColor).withOpacity(0.5);
          }
          return null;
        }),
      ),
    );
  }
}