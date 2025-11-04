import 'package:flutter/material.dart';
import '../controller.dart';
import '../constants.dart';
import '../models.dart';
import '../utils.dart';

// ============================================================================
// DASHBOARD METRICS GRID - SIMPLIFIED 2-THRESHOLD SYSTEM v9.0
// ============================================================================
class DashboardMetricsGrid extends StatelessWidget {
  const DashboardMetricsGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 0.9,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      children: const [
        SoilMoistureMetricCard(),
        FlowRateMetricCard(),
        CycleUsageMetricCard(),
        TotalVolumeMetricCard(),
      ],
    );
  }
}

// ============================================================================
// SOIL MOISTURE CARD - SIMPLIFIED 3-ZONE SYSTEM
// ============================================================================
class SoilMoistureMetricCard extends StatelessWidget {
  const SoilMoistureMetricCard({super.key});

  void _showSoilMoistureLegendDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        contentPadding: EdgeInsets.zero,
        content: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Moisture Zones (Simplified)',
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: const Color(primaryColor),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildLegendRow(
                    'Critical Low', 
                    'Below ${appController.criticalLowThreshold.toStringAsFixed(0)}%', 
                    const Color(errorColor),
                    'Pump turns ON'
                  ),
                  _buildLegendRow(
                    'Normal', 
                    '${appController.criticalLowThreshold.toStringAsFixed(0)}%-${appController.criticalHighThreshold.toStringAsFixed(0)}%', 
                    const Color(successColor),
                    'Safe zone'
                  ),
                  _buildLegendRow(
                    'Critical High', 
                    'Above ${appController.criticalHighThreshold.toStringAsFixed(0)}%', 
                    const Color(warningColor),
                    'Pump turns OFF'
                  ),
                ],
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendRow(String title, String subtitle, Color color, String action) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13)),
                Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                Text(action, style: TextStyle(fontSize: 10, color: color.withOpacity(0.7), fontStyle: FontStyle.italic)),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Color _getSoilMoistureColor(double moisture) {
    if (moisture < appController.criticalLowThreshold) {
      return const Color(errorColor); 
    } else if (moisture <= appController.criticalHighThreshold) {
      return const Color(successColor); 
    } else {
      return const Color(warningColor); 
    }
  }

  String _getSoilMoistureStatus(double moisture) {
    if (moisture < appController.criticalLowThreshold) {
      return 'Critical Low';
    } else if (moisture <= appController.criticalHighThreshold) {
      return 'Normal';
    } else {
      return 'Critical High';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: appController.soilMoistureNotifier,
      builder: (context, moisture, child) {
        final color = _getSoilMoistureColor(moisture);
        final status = _getSoilMoistureStatus(moisture);
        
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.2), width: 1),
            color: Theme.of(context).cardColor,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Flexible(
                      child: Text(
                        'Soil Moisture',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    InkWell(
                      onTap: () => _showSoilMoistureLegendDialog(context),
                      child: Icon(Icons.info_outline, color: color, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.water_drop, size: 28, color: color.withOpacity(0.5)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${moisture.toStringAsFixed(1)}%',
                          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  status,
                  style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ============================================================================
// FLOW RATE CARD
// ============================================================================
class FlowRateMetricCard extends StatelessWidget {
  const FlowRateMetricCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: appController.flowRateNotifier,
      builder: (context, flowRate, child) {
        return ValueListenableBuilder<String>(
          valueListenable: appController.pumpStatusNotifier,
          builder: (context, pumpStatus, child) {
            return ListenableBuilder(
              listenable: appController,
              builder: (context, _) {
                return _MetricCard(
                  title: 'Flow Rate',
                  value: formatFlowRate(flowRate, appController.metricSystem),
                  icon: Icons.speed,
                  color: const Color(primaryColor),
                  subtitle: pumpStatus == 'ON' ? 'Active' : 'Idle',
                );
              },
            );
          },
        );
      },
    );
  }
}

// ============================================================================
// CYCLE USAGE CARD
// ============================================================================
class CycleUsageMetricCard extends StatelessWidget {
  const CycleUsageMetricCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: appController.cycleUsageNotifier,
      builder: (context, cycleUsage, child) {
        return ValueListenableBuilder<String>(
          valueListenable: appController.pumpStatusNotifier,
          builder: (context, pumpStatus, child) {
            return ListenableBuilder(
              listenable: appController,
              builder: (context, _) {
                return _MetricCard(
                  title: 'Cycle Usage',
                  value: formatVolume(cycleUsage, appController.metricSystem),
                  icon: Icons.access_time,
                  color: pumpStatus == 'ON' ? const Color(warningColor) : Colors.grey,
                  subtitle: 'Current',
                );
              },
            );
          },
        );
      },
    );
  }
}

// ============================================================================
// TOTAL VOLUME CARD
// ============================================================================
class TotalVolumeMetricCard extends StatelessWidget {
  const TotalVolumeMetricCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: appController.totalVolumeNotifier,
      builder: (context, totalVolume, child) {
        return ListenableBuilder(
          listenable: appController,
          builder: (context, _) {
            return _MetricCard(
              title: 'Total Volume',
              value: formatVolume(totalVolume, appController.metricSystem),
              icon: Icons.assessment,
              color: const Color(accentColor),
              subtitle: 'Lifetime',
            );
          },
        );
      },
    );
  }
}

// ============================================================================
// BASE METRIC CARD WIDGET
// ============================================================================
class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).cardColor,
      ),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(icon, size: 28, color: color.withOpacity(0.5)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: color),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: TextStyle(fontSize: 11, color: color.withOpacity(0.8), fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }
}