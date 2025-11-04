import 'package:flutter/material.dart';
import '../controller.dart';
import '../constants.dart';

// ============================================================================
// SHARED WIDGETS - GRADIENT APP BAR (OPTIMIZED)
// ============================================================================
PreferredSizeWidget buildGradientAppBar(
  BuildContext context, 
  String title, 
  {VoidCallback? onNotificationTap}
) {
  return AppBar(
    automaticallyImplyLeading: false,
    toolbarHeight: 80.0,
    title: Text(
      title, 
      style: const TextStyle(
        fontSize: 28, 
        fontWeight: FontWeight.bold, 
        color: Colors.white
      )
    ),
    centerTitle: true,
    flexibleSpace: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(gradientStart), 
            Color(gradientEnd)
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    ),
    elevation: 0,
    actions: onNotificationTap != null ? [
      ListenableBuilder(
        listenable: appController,
        builder: (context, child) => Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications, color: Colors.white, size: 30),
              onPressed: onNotificationTap,
              tooltip: 'Notifications',
            ),
            if (appController.hasUnreadNotifications)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Color(errorColor), 
                    shape: BoxShape.circle
                  ),
                  constraints: const BoxConstraints(minWidth: 10, minHeight: 10),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(width: 8),
    ] : null,
  );
}