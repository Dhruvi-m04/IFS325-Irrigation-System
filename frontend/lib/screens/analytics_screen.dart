import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import '../controller.dart';
import '../constants.dart';
import '../widgets/gradient_app_bar.dart';

// ============================================================================
// ANALYTICS SCREEN - FIXED FOR cycle_usage_l + Zero Division Protection
// ============================================================================

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  String _selectedTimeRange = '24h';
  String _selectedMetric = 'all';
  bool _isLoading = true;
  String _error = '';
  List<TelemetryDataPoint> _data = [];

  final Map<String, int> _timeRangeHours = {
    '6h': 6,
    '12h': 12,
    '24h': 24,
    '48h': 48,
    '7d': 168,
  };

  @override
  void initState() {
    super.initState();
    _fetchAnalyticsData();
  }

  Future<void> _fetchAnalyticsData() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final hours = _timeRangeHours[_selectedTimeRange] ?? 24;
      final response = await appController.fetchAnalyticsData(
        hours: hours,
        metric: _selectedMetric,
      );

      if (response['items'] != null) {
        setState(() {
          _data = (response['items'] as List)
              .map((item) => TelemetryDataPoint.fromJson(item))
              .toList();
          _isLoading = false;
        });
      } else {
        throw Exception('No data returned');
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load analytics data: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: buildGradientAppBar(context, 'Analytics'),
      body: Column(
        children: [
          _buildFilterControls(theme),
          Expanded(
            child: _isLoading
                ? _buildLoadingState()
                : _error.isNotEmpty
                    ? _buildErrorState(theme)
                    : _data.isEmpty
                        ? _buildEmptyState(theme)
                        : _buildChartsView(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterControls(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Time Range',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _selectedTimeRange,
                      isExpanded: true,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor: theme.colorScheme.surface,
                      ),
                      items: _timeRangeHours.keys.map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(
                            _getTimeRangeLabel(value),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedTimeRange = value);
                          _fetchAnalyticsData();
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Metric',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _selectedMetric,
                      isExpanded: true,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor: theme.colorScheme.surface,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'all',
                          child: Text('All', overflow: TextOverflow.ellipsis),
                        ),
                        DropdownMenuItem(
                          value: 'moisture',
                          child: Text('Moisture', overflow: TextOverflow.ellipsis),
                        ),
                        DropdownMenuItem(
                          value: 'flow_rate',
                          child: Text('Flow Rate', overflow: TextOverflow.ellipsis),
                        ),
                        DropdownMenuItem(
                          value: 'cycle_usage',
                          child: Text('Cycle Usage', overflow: TextOverflow.ellipsis),
                        ),
                        DropdownMenuItem(
                          value: 'pump_status',
                          child: Text('Pump', overflow: TextOverflow.ellipsis),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedMetric = value);
                          _fetchAnalyticsData();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _fetchAnalyticsData,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh Data'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(primaryColor),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartsView(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSummaryStatsCard(theme),
        const SizedBox(height: 16),

        if (_selectedMetric == 'all' || _selectedMetric == 'moisture')
          _buildMoistureChart(theme),

        if (_selectedMetric == 'all' || _selectedMetric == 'moisture')
          const SizedBox(height: 16),

        if (_selectedMetric == 'all' || _selectedMetric == 'flow_rate')
          _buildFlowRateChart(theme),

        if (_selectedMetric == 'all' || _selectedMetric == 'flow_rate')
          const SizedBox(height: 16),

        if (_selectedMetric == 'all' || _selectedMetric == 'cycle_usage')
          _buildCycleUsageChart(theme),

        if (_selectedMetric == 'all' || _selectedMetric == 'cycle_usage')
          const SizedBox(height: 16),

        if (_selectedMetric == 'all' || _selectedMetric == 'pump_status')
          _buildPumpStatusChart(theme),
      ],
    );
  }

  Widget _buildSummaryStatsCard(ThemeData theme) {
    final moistureData = _data.where((d) => d.moisture != null).toList();
    final flowRateData = _data.where((d) => d.flowRate != null && d.flowRate! > 0).toList();

    final avgMoisture = moistureData.isNotEmpty
        ? moistureData.map((d) => d.moisture!).reduce((a, b) => a + b) / moistureData.length
        : 0.0;

    final avgFlowRate = flowRateData.isNotEmpty
        ? flowRateData.map((d) => d.flowRate!).reduce((a, b) => a + b) / flowRateData.length
        : 0.0;

    final pumpOnCount = _data.where((d) => d.pumpStatus == 'ON').length;
    final pumpOnPercent = _data.isNotEmpty ? (pumpOnCount / _data.length * 100) : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics, color: Color(primaryColor), size: 20),
                const SizedBox(width: 8),
                Text(
                  'Summary Statistics',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'Avg Moisture',
                    '${avgMoisture.toStringAsFixed(1)}%',
                    Icons.water_drop,
                    const Color(successColor),
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Avg Flow Rate',
                    '${avgFlowRate.toStringAsFixed(2)} L/min',
                    Icons.speed,
                    const Color(primaryColor),
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Pump Uptime',
                    '${pumpOnPercent.toStringAsFixed(1)}%',
                    Icons.power,
                    const Color(accentColor),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildMoistureChart(ThemeData theme) {
    final moistureData = _data.where((d) => d.moisture != null).toList();
    if (moistureData.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.water_drop, color: Color(successColor), size: 20),
                const SizedBox(width: 8),
                Text(
                  'Soil Moisture',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 250,
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: LineChart(
                  LineChartData(
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: 20,
                      getDrawingHorizontalLine: (value) {
                        return FlLine(
                          color: Colors.grey.withOpacity(0.2),
                          strokeWidth: 1,
                        );
                      },
                    ),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 42,
                          getTitlesWidget: (value, meta) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Text(
                                '${value.toInt()}%',
                                style: const TextStyle(fontSize: 10, color: Colors.grey),
                                textAlign: TextAlign.right,
                              ),
                            );
                          },
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 40,
                          interval: math.max(1, (moistureData.length / 5).ceilToDouble()),
                          getTitlesWidget: (value, meta) {
                            final index = value.toInt();
                            if (index >= 0 && index < moistureData.length) {
                              final time = moistureData[index].timestamp;
                              final now = DateTime.now();
                              final diff = now.difference(time);
                              
                              String label;
                              if (diff.inDays > 0) {
                                label = DateFormat('MMM d').format(time);
                              } else {
                                label = DateFormat('HH:mm').format(time);
                              }
                              
                              return SideTitleWidget(
                                meta: meta,
                                space: 8,
                                child: Transform.rotate(
                                  angle: -0.5,
                                  child: Text(
                                    label,
                                    style: const TextStyle(fontSize: 9, color: Colors.grey),
                                  ),
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(show: false),
                    minY: 0,
                    maxY: 100,
                    lineBarsData: [
                      LineChartBarData(
                        spots: moistureData.asMap().entries.map((entry) {
                          return FlSpot(entry.key.toDouble(), entry.value.moisture!);
                        }).toList(),
                        isCurved: true,
                        gradient: const LinearGradient(
                          colors: [Color(successColor), Color(accentColor)],
                        ),
                        barWidth: 3,
                        isStrokeCapRound: true,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            colors: [
                              const Color(successColor).withOpacity(0.3),
                              const Color(successColor).withOpacity(0.0),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ],
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (touchedSpot) => const Color(primaryColor),
                        getTooltipItems: (touchedSpots) {
                          return touchedSpots.map((spot) {
                            final index = spot.x.toInt();
                            final dataPoint = moistureData[index];
                            return LineTooltipItem(
                              '${dataPoint.moisture!.toStringAsFixed(1)}%\n${DateFormat('MMM d, HH:mm').format(dataPoint.timestamp)}',
                              const TextStyle(color: Colors.white, fontSize: 12),
                            );
                          }).toList();
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildThresholdLegend(),
          ],
        ),
      ),
    );
  }

  Widget _buildThresholdLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildLegendItem('Low', const Color(errorColor)),
        const SizedBox(width: 16),
        _buildLegendItem('Normal', const Color(successColor)),
        const SizedBox(width: 16),
        _buildLegendItem('High', const Color(warningColor)),
      ],
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  Widget _buildFlowRateChart(ThemeData theme) {
    final flowData = _data.where((d) => d.flowRate != null).toList();
    if (flowData.isEmpty) return const SizedBox.shrink();

    final maxFlow = flowData.map((d) => d.flowRate!).reduce(math.max);
    final yMax = math.max(1.0, (maxFlow * 1.2).ceilToDouble()); // ✅ FIX: Minimum 1.0

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.speed, color: Color(primaryColor), size: 20),
                const SizedBox(width: 8),
                Text(
                  'Flow Rate (L/min)',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 250,
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: LineChart(
                  LineChartData(
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: math.max(0.5, yMax / 5), // ✅ FIX: Never zero
                      getDrawingHorizontalLine: (value) {
                        return FlLine(
                          color: Colors.grey.withOpacity(0.2),
                          strokeWidth: 1,
                        );
                      },
                    ),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 50,
                          getTitlesWidget: (value, meta) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Text(
                                value.toStringAsFixed(1),
                                style: const TextStyle(fontSize: 10, color: Colors.grey),
                                textAlign: TextAlign.right,
                              ),
                            );
                          },
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 40,
                          interval: math.max(1, (flowData.length / 5).ceilToDouble()),
                          getTitlesWidget: (value, meta) {
                            final index = value.toInt();
                            if (index >= 0 && index < flowData.length) {
                              final time = flowData[index].timestamp;
                              final now = DateTime.now();
                              final diff = now.difference(time);
                              
                              String label;
                              if (diff.inDays > 0) {
                                label = DateFormat('MMM d').format(time);
                              } else {
                                label = DateFormat('HH:mm').format(time);
                              }
                              
                              return SideTitleWidget(
                                meta: meta,
                                space: 8,
                                child: Transform.rotate(
                                  angle: -0.5,
                                  child: Text(
                                    label,
                                    style: const TextStyle(fontSize: 9, color: Colors.grey),
                                  ),
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(show: false),
                    minY: 0,
                    maxY: yMax,
                    lineBarsData: [
                      LineChartBarData(
                        spots: flowData.asMap().entries.map((entry) {
                          return FlSpot(entry.key.toDouble(), entry.value.flowRate!);
                        }).toList(),
                        isCurved: true,
                        gradient: const LinearGradient(
                          colors: [Color(primaryColor), Color(accentColor)],
                        ),
                        barWidth: 3,
                        isStrokeCapRound: true,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            colors: [
                              const Color(primaryColor).withOpacity(0.3),
                              const Color(primaryColor).withOpacity(0.0),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ],
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (touchedSpot) => const Color(primaryColor),
                        getTooltipItems: (touchedSpots) {
                          return touchedSpots.map((spot) {
                            final index = spot.x.toInt();
                            final dataPoint = flowData[index];
                            return LineTooltipItem(
                              '${dataPoint.flowRate!.toStringAsFixed(2)} L/min\n${DateFormat('MMM d, HH:mm').format(dataPoint.timestamp)}',
                              const TextStyle(color: Colors.white, fontSize: 12),
                            );
                          }).toList();
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPumpStatusChart(ThemeData theme) {
    final pumpData = _data.where((d) => d.pumpStatus != null).toList();
    if (pumpData.isEmpty) return const SizedBox.shrink();

    final onCount = pumpData.where((d) => d.pumpStatus == 'ON').length;
    final offCount = pumpData.where((d) => d.pumpStatus == 'OFF').length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.power_settings_new, color: Color(accentColor), size: 20),
                const SizedBox(width: 8),
                Text(
                  'Pump Status Distribution',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: [
                    PieChartSectionData(
                      color: const Color(successColor),
                      value: onCount.toDouble(),
                      title: 'ON\n${(onCount / pumpData.length * 100).toStringAsFixed(1)}%',
                      radius: 80,
                      titleStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    PieChartSectionData(
                      color: Colors.grey,
                      value: offCount.toDouble(),
                      title: 'OFF\n${(offCount / pumpData.length * 100).toStringAsFixed(1)}%',
                      radius: 80,
                      titleStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildCycleUsageChart(ThemeData theme) {
    final cycleData = _data.where((d) => d.cycleUsage != null && d.cycleUsage! > 0).toList();
    
    if (cycleData.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.water, size: 48, color: Colors.grey.withOpacity(0.5)),
                const SizedBox(height: 16),
                Text(
                  'No cycle usage data available',
                  style: theme.textTheme.bodyLarge?.copyWith(color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Text(
                  'Cycle data appears when pump is running',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final maxCycle = cycleData.map((d) => d.cycleUsage!).reduce(math.max);
    final yMax = math.max(1.0, (maxCycle * 1.1).ceilToDouble()); // ✅ FIX: Minimum 1.0

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.water, color: Color(accentColor), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cycle Usage',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Water used in each pump cycle (difference between readings)',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 250,
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: LineChart(
                  LineChartData(
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: math.max(0.5, yMax / 5), // ✅ FIX: Never zero
                      getDrawingHorizontalLine: (value) {
                        return FlLine(
                          color: Colors.grey.withOpacity(0.2),
                          strokeWidth: 1,
                        );
                      },
                    ),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 50,
                          getTitlesWidget: (value, meta) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Text(
                                '${value.toStringAsFixed(1)}L',
                                style: const TextStyle(fontSize: 10, color: Colors.grey),
                                textAlign: TextAlign.right,
                              ),
                            );
                          },
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 40,
                          interval: math.max(1, (cycleData.length / 5).ceilToDouble()),
                          getTitlesWidget: (value, meta) {
                            final index = value.toInt();
                            if (index >= 0 && index < cycleData.length) {
                              final time = cycleData[index].timestamp;
                              final now = DateTime.now();
                              final diff = now.difference(time);
                              
                              String label;
                              if (diff.inDays > 0) {
                                label = DateFormat('MMM d').format(time);
                              } else {
                                label = DateFormat('HH:mm').format(time);
                              }
                              
                              return SideTitleWidget(
                                meta: meta,
                                space: 8,
                                child: Transform.rotate(
                                  angle: -0.5,
                                  child: Text(
                                    label,
                                    style: const TextStyle(fontSize: 9, color: Colors.grey),
                                  ),
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(show: false),
                    minY: 0,
                    maxY: yMax,
                    lineBarsData: [
                      LineChartBarData(
                        spots: cycleData.asMap().entries.map((entry) {
                          return FlSpot(entry.key.toDouble(), entry.value.cycleUsage!);
                        }).toList(),
                        isCurved: true,
                        color: const Color(accentColor),
                        barWidth: 3,
                        isStrokeCapRound: true,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            colors: [
                              const Color(accentColor).withOpacity(0.3),
                              const Color(accentColor).withOpacity(0.0),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ],
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (touchedSpot) => const Color(accentColor),
                        getTooltipItems: (touchedSpots) {
                          return touchedSpots.map((spot) {
                            final index = spot.x.toInt();
                            final dataPoint = cycleData[index];
                            return LineTooltipItem(
                              '${dataPoint.cycleUsage!.toStringAsFixed(2)}L\n${DateFormat('MMM d, HH:mm').format(dataPoint.timestamp)}',
                              const TextStyle(color: Colors.white, fontSize: 12),
                            );
                          }).toList();
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(accentColor).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(accentColor).withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Color(accentColor), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Shows water used between consecutive readings. Calculated as difference from previous total_flow.',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onBackground.withOpacity(0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Color(primaryColor)),
          SizedBox(height: 16),
          Text('Loading analytics data...'),
        ],
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Color(errorColor)),
            const SizedBox(height: 16),
            Text(
              'Error Loading Data',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _error,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _fetchAnalyticsData,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(primaryColor),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.insights_outlined,
              size: 80,
              color: const Color(primaryColor).withOpacity(0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'No Data Available',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'No telemetry data found for the selected time range.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _fetchAnalyticsData,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(primaryColor),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getTimeRangeLabel(String key) {
    switch (key) {
      case '6h':
        return 'Last 6 Hours';
      case '12h':
        return 'Last 12 Hours';
      case '24h':
        return 'Last 24 Hours';
      case '48h':
        return 'Last 48 Hours';
      case '7d':
        return 'Last 7 Days';
      default:
        return key;
    }
  }
}

// ============================================================================
// TELEMETRY DATA MODEL - UPDATED FOR cycle_usage_l
// ============================================================================

class TelemetryDataPoint {
  final DateTime timestamp;
  final double? moisture;
  final double? flowRate;
  final double? totalFlow;
  final double? cycleUsage;
  final String? pumpStatus;

  TelemetryDataPoint({
    required this.timestamp,
    this.moisture,
    this.flowRate,
    this.totalFlow,
    this.cycleUsage,
    this.pumpStatus,
  });

  factory TelemetryDataPoint.fromJson(Map<String, dynamic> json) {
    return TelemetryDataPoint(
      timestamp: DateTime.parse(json['timestamp']),
      moisture: json['moisture']?.toDouble(),
      flowRate: json['flow_rate']?.toDouble(),
      totalFlow: json['total_flow']?.toDouble(),
      cycleUsage: json['cycle_usage_l']?.toDouble(),
      pumpStatus: json['pump_status'],
    );
  }
}