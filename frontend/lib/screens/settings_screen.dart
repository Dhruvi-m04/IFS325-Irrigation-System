import 'package:flutter/material.dart';
import '../controller.dart';
import '../constants.dart';
import '../models.dart';
import '../widgets/gradient_app_bar.dart';
import '../widgets/notification_panel.dart';

// ============================================================================
// SETTINGS SCREEN
// ============================================================================
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late double _tempCriticalLow;
  late double _tempCriticalHigh;
  bool _hasUnsavedChanges = false;

  @override
  void initState() {
    super.initState();
    _tempCriticalLow = appController.criticalLowThreshold;
    _tempCriticalHigh = appController.criticalHighThreshold;
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

  void _updateCriticalLow(double value) {
    setState(() {
      _tempCriticalLow = value;
      _hasUnsavedChanges = true;
      
      // Auto-adjust high threshold if needed
      if (_tempCriticalLow >= _tempCriticalHigh) {
        _tempCriticalHigh = _tempCriticalLow + 10;
        if (_tempCriticalHigh > 100) {
          _tempCriticalHigh = 100;
          _tempCriticalLow = 90;
        }
      }
    });
  }

  void _updateCriticalHigh(double value) {
    setState(() {
      _tempCriticalHigh = value;
      _hasUnsavedChanges = true;
      
      // Auto-adjust low threshold if needed
      if (_tempCriticalHigh <= _tempCriticalLow) {
        _tempCriticalLow = _tempCriticalHigh - 10;
        if (_tempCriticalLow < 0) {
          _tempCriticalLow = 0;
          _tempCriticalHigh = 10;
        }
      }
    });
  }

  Future<void> _saveThresholds() async {
    if (!(_tempCriticalLow < _tempCriticalHigh)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid thresholds! Critical Low must be less than Critical High.'),
          backgroundColor: Color(errorColor),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    appController.setCriticalLowThreshold(_tempCriticalLow);
    appController.setCriticalHighThreshold(_tempCriticalHigh);

    final success = await appController.saveThresholds();

    if (!mounted) return;

    if (success) {
      setState(() => _hasUnsavedChanges = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Thresholds saved successfully'),
          backgroundColor: Color(successColor),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✗ Failed to save thresholds'),
          backgroundColor: Color(errorColor),
        ),
      );
    }
  }

  void _resetToDefaults() {
    setState(() {
      _tempCriticalLow = 40.0;
      _tempCriticalHigh = 80.0;
      _hasUnsavedChanges = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: buildGradientAppBar(
        context,
        'Settings',
        onNotificationTap: _showNotificationPanel,
      ),
      body: ListenableBuilder(
        listenable: appController,
        builder: (context, child) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ══════════════════════════════════════════════════════════
                // APPEARANCE SECTION
                // ══════════════════════════════════════════════════════════
                _buildSectionHeader('Appearance', Icons.palette_outlined),
                Card(
                  child: Column(
                    children: [
                      _buildSettingTile(
                        icon: Icons.brightness_6_outlined,
                        title: 'Theme Mode',
                        trailing: DropdownButton<ThemeMode>(
                          value: appController.themeMode,
                          underline: const SizedBox(),
                          items: const [
                            DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
                            DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                            DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                          ],
                          onChanged: (mode) {
                            if (mode != null) appController.setThemeMode(mode);
                          },
                        ),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      _buildSettingTile(
                        icon: Icons.straighten_outlined,
                        title: 'Unit System',
                        trailing: DropdownButton<MetricSystem>(
                          value: appController.metricSystem,
                          underline: const SizedBox(),
                          items: const [
                            DropdownMenuItem(value: MetricSystem.metric, child: Text('Metric')),
                            DropdownMenuItem(value: MetricSystem.imperial, child: Text('Imperial')),
                          ],
                          onChanged: (system) {
                            if (system != null) appController.setMetricSystem(system);
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ══════════════════════════════════════════════════════════
                // AUTOMATION SECTION
                // ══════════════════════════════════════════════════════════
                _buildSectionHeader('Automation', Icons.settings_suggest_outlined),
                Card(
                  child: _buildSwitchTile(
                    icon: Icons.water_drop_outlined,
                    title: 'Low Moisture Alerts',
                    subtitle: 'Get notified when soil moisture is critical',
                    value: appController.lowMoistureAlertEnabled,
                    onChanged: appController.setLowMoistureAlertEnabled,
                  ),
                ),

                const SizedBox(height: 24),

                // ══════════════════════════════════════════════════════════
                // MANUAL OVERRIDE SAFETY SECTION
                // ══════════════════════════════════════════════════════════
                _buildSectionHeader('Manual Override Safety', Icons.security_outlined),
                Card(
                  child: Column(
                    children: [
                      _buildSwitchTile(
                        icon: Icons.pan_tool_outlined,
                        title: 'Unrestricted Manual Override',
                        subtitle: appController.allowManualOverrideAtAnyMoisture
                            ? 'Manual control works at ANY moisture level'
                            : 'Safety limits active',
                        value: appController.allowManualOverrideAtAnyMoisture,
                        onChanged: (_) => appController.toggleManualOverrideSafety(),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: appController.allowManualOverrideAtAnyMoisture
                                ? const Color(warningColor).withOpacity(0.1)
                                : const Color(successColor).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: appController.allowManualOverrideAtAnyMoisture
                                  ? const Color(warningColor).withOpacity(0.3)
                                  : const Color(successColor).withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                appController.allowManualOverrideAtAnyMoisture ? Icons.warning_amber : Icons.verified_user,
                                size: 20,
                                color: appController.allowManualOverrideAtAnyMoisture
                                    ? const Color(warningColor)
                                    : const Color(successColor),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  appController.allowManualOverrideAtAnyMoisture
                                      ? 'Manual control will work at critical levels. Use with caution.'
                                      : 'Safety controls prevent manual actions at critical moisture levels.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: appController.allowManualOverrideAtAnyMoisture
                                        ? const Color(warningColor)
                                        : const Color(successColor),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ══════════════════════════════════════════════════════════
                // MOISTURE THRESHOLDS SECTION (SIMPLIFIED 2-THRESHOLD)
                // ══════════════════════════════════════════════════════════
                _buildSectionHeader('Moisture Thresholds', Icons.tune_outlined),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(primaryColor).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(primaryColor).withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, color: Color(primaryColor), size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Simplified system: Pump turns ON below Low, OFF above High',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onBackground.withOpacity(0.8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 20),

                        // Critical Low Threshold
                        Row(
                          children: [
                            const Icon(Icons.water_drop_outlined, color: Color(errorColor), size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Critical Low',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: const Color(errorColor),
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(errorColor).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: const Color(errorColor).withOpacity(0.3)),
                              ),
                              child: Text(
                                '${_tempCriticalLow.toStringAsFixed(0)}%',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(errorColor),
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Pump turns ON when moisture falls below this level',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onBackground.withOpacity(0.6),
                          ),
                        ),
                        Slider(
                          value: _tempCriticalLow,
                          min: 0,
                          max: 100,
                          divisions: 100,
                          activeColor: const Color(errorColor),
                          label: '${_tempCriticalLow.toStringAsFixed(0)}%',
                          onChanged: _updateCriticalLow,
                        ),

                        const SizedBox(height: 24),

                        // Critical High Threshold
                        Row(
                          children: [
                            const Icon(Icons.water_drop, color: Color(warningColor), size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Critical High',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: const Color(warningColor),
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(warningColor).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: const Color(warningColor).withOpacity(0.3)),
                              ),
                              child: Text(
                                '${_tempCriticalHigh.toStringAsFixed(0)}%',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(warningColor),
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Pump turns OFF when moisture exceeds this level',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onBackground.withOpacity(0.6),
                          ),
                        ),
                        Slider(
                          value: _tempCriticalHigh,
                          min: 0,
                          max: 100,
                          divisions: 100,
                          activeColor: const Color(warningColor),
                          label: '${_tempCriticalHigh.toStringAsFixed(0)}%',
                          onChanged: _updateCriticalHigh,
                        ),

                        const SizedBox(height: 20),

                        // Visual range indicator (3 zones)
                        _buildRangeIndicator(theme),

                        const SizedBox(height: 20),

                        // Action buttons
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _resetToDefaults,
                                icon: const Icon(Icons.restore, size: 18),
                                label: const Text('Reset', style: TextStyle(fontSize: 13)),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton.icon(
                                onPressed: _hasUnsavedChanges ? _saveThresholds : null,
                                icon: const Icon(Icons.save, size: 18),
                                label: const Text('Save Thresholds', style: TextStyle(fontSize: 13)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(primaryColor),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  disabledBackgroundColor: Colors.grey.withOpacity(0.3),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // ══════════════════════════════════════════════════════════
                // NOTIFICATIONS SECTION
                // ══════════════════════════════════════════════════════════
                _buildSectionHeader('Notifications', Icons.notifications_outlined),
                Card(
                  child: Column(
                    children: [
                      _buildSwitchTile(
                        icon: Icons.volume_up_outlined,
                        title: 'Alert Sound',
                        subtitle: 'Play sound for alerts',
                        value: appController.alertSoundEnabled,
                        onChanged: appController.setAlertSoundEnabled,
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      _buildSwitchTile(
                        icon: Icons.vibration_outlined,
                        title: 'Vibration',
                        subtitle: 'Vibrate for alerts',
                        value: appController.alertVibrationEnabled,
                        onChanged: appController.setAlertVibrationEnabled,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ══════════════════════════════════════════════════════════
                // ABOUT SECTION
                // ══════════════════════════════════════════════════════════
                _buildSectionHeader('About', Icons.info_outline),
                Card(
                  child: Column(
                    children: [
                      _buildSettingTile(
                        icon: Icons.apps_outlined,
                        title: 'App Version',
                        trailing: const Text('9.0.0', style: TextStyle(color: Colors.grey)),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      _buildSettingTile(
                        icon: Icons.code_outlined,
                        title: 'Build',
                        trailing: const Text('Simplified 2-Threshold', style: TextStyle(color: Colors.grey, fontSize: 11)),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 80),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRangeIndicator(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Moisture Zones',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          
          // Visual bar (3 zones)
          Row(
            children: [
              // Critical Low zone
              Expanded(
                flex: _tempCriticalLow.toInt(),
                child: Container(
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(errorColor).withOpacity(0.3),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(6),
                      bottomLeft: Radius.circular(6),
                    ),
                  ),
                  child: const Center(
                    child: Text(
                      'LOW',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Color(errorColor),
                      ),
                    ),
                  ),
                ),
              ),
              
              // Normal zone
              Expanded(
                flex: (_tempCriticalHigh - _tempCriticalLow).toInt(),
                child: Container(
                  height: 32,
                  color: const Color(successColor).withOpacity(0.3),
                  child: const Center(
                    child: Text(
                      'NORMAL',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Color(successColor),
                      ),
                    ),
                  ),
                ),
              ),
              
              // Critical High zone
              Expanded(
                flex: (100 - _tempCriticalHigh).toInt(),
                child: Container(
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(warningColor).withOpacity(0.3),
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(6),
                      bottomRight: Radius.circular(6),
                    ),
                  ),
                  child: const Center(
                    child: Text(
                      'HIGH',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Color(warningColor),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildLegendItem(
                icon: Icons.water_drop_outlined,
                label: '< ${_tempCriticalLow.toInt()}%',
                sublabel: 'Pump ON',
                color: const Color(errorColor),
              ),
              _buildLegendItem(
                icon: Icons.check_circle,
                label: '${_tempCriticalLow.toInt()}-${_tempCriticalHigh.toInt()}%',
                sublabel: 'Safe',
                color: const Color(successColor),
              ),
              _buildLegendItem(
                icon: Icons.water_drop,
                label: '> ${_tempCriticalHigh.toInt()}%',
                sublabel: 'Pump OFF',
                color: const Color(warningColor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem({
    required IconData icon,
    required String label,
    required String sublabel,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          sublabel,
          style: TextStyle(
            fontSize: 9,
            color: color.withOpacity(0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(primaryColor)),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(primaryColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required Widget trailing,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(primaryColor).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: const Color(primaryColor), size: 22),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: trailing,
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      secondary: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(primaryColor).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: const Color(primaryColor), size: 22),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
      activeColor: const Color(secondaryColor),
    );
  }
}