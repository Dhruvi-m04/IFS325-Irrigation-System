import 'package:flutter/material.dart';
import '../controller.dart';
import '../constants.dart';

// ============================================================================
// MANUAL CONTROL CARD - WITH MICRO-ANIMATIONS
// ============================================================================
class ManualControlCard extends StatefulWidget {
  const ManualControlCard({super.key});

  @override
  State<ManualControlCard> createState() => _ManualControlCardState();
}

class _ManualControlCardState extends State<ManualControlCard> with TickerProviderStateMixin {
  late AnimationController _onButtonController;
  late AnimationController _offButtonController;
  late AnimationController _returnButtonController;
  
  late Animation<double> _onButtonScale;
  late Animation<double> _offButtonScale;
  late Animation<double> _returnButtonScale;
  
  @override
  void initState() {
    super.initState();
    
    _onButtonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _onButtonScale = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _onButtonController, curve: Curves.easeInOut),
    );
    
    _offButtonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _offButtonScale = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _offButtonController, curve: Curves.easeInOut),
    );
    
    _returnButtonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _returnButtonScale = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _returnButtonController, curve: Curves.easeInOut),
    );
  }
  
  @override
  void dispose() {
    _onButtonController.dispose();
    _offButtonController.dispose();
    _returnButtonController.dispose();
    super.dispose();
  }
  
  Future<void> _animateButton(AnimationController controller) async {
    await controller.forward();
    await controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appController,
      builder: (context, child) {
        final isActive = appController.isManualOverrideActive;
        final canStart = appController.canStartPump;
        final canStop = appController.canStopPump;
        
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.touch_app, color: Color(primaryColor), size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Manual Control',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ScaleTransition(
                        scale: _onButtonScale,
                        child: ElevatedButton(
                          onPressed: canStart
                              ? () async {
                                  await _animateButton(_onButtonController);
                                  appController.startManualPump();
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(successColor),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(successColor).withOpacity(0.3),
                            disabledForegroundColor: Colors.white.withOpacity(0.5),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            elevation: canStart ? 2 : 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('On', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ScaleTransition(
                        scale: _offButtonScale,
                        child: ElevatedButton(
                          onPressed: canStop
                              ? () async {
                                  await _animateButton(_offButtonController);
                                  appController.stopPumpAction();
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(errorColor),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(errorColor).withOpacity(0.3),
                            disabledForegroundColor: Colors.white.withOpacity(0.5),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            elevation: canStop ? 2 : 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('Off', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                  ],
                ),
                if (isActive) ...[
                  const SizedBox(height: 12),
                  ScaleTransition(
                    scale: _returnButtonScale,
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          await _animateButton(_returnButtonController);
                          await appController.clearManualOverride();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(primaryColor),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text(
                          'Return to Normal Mode',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}