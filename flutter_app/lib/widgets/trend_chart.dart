import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/analytics.dart';

class TrendLineChart extends StatelessWidget {
  final List<DataPoint> data;
  final String title;
  final Color lineColor;
  final String unit;
  final double? minY;
  final double? maxY;

  const TrendLineChart({
    super.key,
    required this.data,
    required this.title,
    required this.lineColor,
    this.unit = '',
    this.minY,
    this.maxY,
  });

  @override
  Widget build(BuildContext context) {
    final filtered = data.where((d) => d.value != null).toList();
    if (filtered.isEmpty) {
      return _empty(context);
    }

    final spots = filtered.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value.value!);
    }).toList();

    final values = filtered.map((d) => d.value!).toList();
    final minVal = (minY ?? values.reduce((a, b) => a < b ? a : b)) - 1;
    final maxVal = (maxY ?? values.reduce((a, b) => a > b ? a : b)) + 1;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white70)),
            const SizedBox(height: 16),
            SizedBox(
              height: 160,
              child: LineChart(
                LineChartData(
                  minY: minVal,
                  maxY: maxVal,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: Colors.white10,
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (v, _) => Text(
                          '${v.toStringAsFixed(1)}$unit',
                          style: const TextStyle(
                              fontSize: 10, color: Colors.white38),
                        ),
                      ),
                    ),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: filtered.length <= 10,
                        getTitlesWidget: (v, _) {
                          final idx = v.toInt();
                          if (idx < 0 || idx >= filtered.length) {
                            return const SizedBox.shrink();
                          }
                          final d = DateTime.parse(filtered[idx].date);
                          return Text(
                            DateFormat('d/M').format(d),
                            style: const TextStyle(
                                fontSize: 9, color: Colors.white38),
                          );
                        },
                        reservedSize: 22,
                      ),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      curveSmoothness: 0.3,
                      color: lineColor,
                      barWidth: 2.5,
                      dotData: FlDotData(
                        show: filtered.length <= 14,
                        getDotPainter: (_, __, ___, ____) =>
                            FlDotCirclePainter(
                          radius: 3,
                          color: lineColor,
                          strokeWidth: 0,
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          colors: [
                            lineColor.withOpacity(0.3),
                            lineColor.withOpacity(0.0),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
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
    );
  }

  Widget _empty(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              'No data yet for $title',
              style: const TextStyle(color: Colors.white38),
            ),
          ),
        ),
      );
}

// ── Calorie bar chart ─────────────────────────────────────────────────────────

class CalorieBarChart extends StatelessWidget {
  final List<DataPoint> data;

  const CalorieBarChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();

    final bars = data.asMap().entries.map((e) {
      final val = e.value.value ?? 0;
      final isMet = val >= 1500 && val <= 2500;
      return BarChartGroupData(
        x: e.key,
        barRods: [
          BarChartRodData(
            toY: val,
            color: isMet
                ? const Color(0xFF6C63FF)
                : const Color(0xFFFF6B35),
            width: 10,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ],
      );
    }).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Daily Calories',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white70)),
            const SizedBox(height: 16),
            SizedBox(
              height: 140,
              child: BarChart(
                BarChartData(
                  barGroups: bars,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: Colors.white10, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (v, _) => Text(
                          '${(v / 1000).toStringAsFixed(1)}k',
                          style: const TextStyle(
                              fontSize: 10, color: Colors.white38),
                        ),
                      ),
                    ),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
