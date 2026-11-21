import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/gym_provider.dart';
import '../widgets/trend_chart.dart';
import '../widgets/stat_card.dart';
import '../models/analytics.dart';

class MonthlyScreen extends StatefulWidget {
  const MonthlyScreen({super.key});
  @override
  State<MonthlyScreen> createState() => _MonthlyScreenState();
}

class _MonthlyScreenState extends State<MonthlyScreen> {
  DateTime _monthRef = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String get _monthStr =>
      DateFormat('yyyy-MM').format(_monthRef);

  Future<void> _load() async {
    await context.read<GymProvider>().loadMonthlyAnalytics(_monthStr);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GymProvider>();
    final monthly  = provider.monthlyAnalytics;
    final theme    = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Monthly Report'),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () {
              setState(() => _monthRef =
                  DateTime(_monthRef.year, _monthRef.month - 1));
              _load();
            },
          ),
          TextButton(
            onPressed: () {
              setState(() => _monthRef = DateTime.now());
              _load();
            },
            child: Text('Now',
                style: TextStyle(
                    color: theme.colorScheme.primary, fontSize: 13)),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed:
                DateTime(_monthRef.year, _monthRef.month + 1)
                        .isBefore(DateTime.now())
                    ? () {
                        setState(() => _monthRef = DateTime(
                            _monthRef.year, _monthRef.month + 1));
                        _load();
                      }
                    : null,
          ),
        ],
      ),
      body: provider.loading
          ? const Center(child: CircularProgressIndicator())
          : monthly == null
              ? _empty(context)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _content(context, monthly),
                ),
    );
  }

  Widget _content(BuildContext context, MonthlyAnalytics m) {
    final theme = Theme.of(context);
    final monthLabel =
        DateFormat('MMMM yyyy').format(DateTime.parse('${m.month}-01'));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      children: [
        const SizedBox(height: 16),

        // Header
        Text(monthLabel,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800)),

        const SizedBox(height: 4),
        Text('${m.daysLogged} days logged  •  ${m.gymDays} gym sessions',
            style: const TextStyle(color: Colors.white54, fontSize: 13)),

        const SizedBox(height: 20),

        // ── Highlights ────────────────────────────────────────────────────
        _section('🏆 Highlights', context),
        const SizedBox(height: 10),
        ...m.highlights.map((h) => _highlightTile(h, context)),

        const SizedBox(height: 20),

        // ── Stats grid ────────────────────────────────────────────────────
        _section('📊 Stats', context),
        const SizedBox(height: 10),

        Row(children: [
          Expanded(
            child: MiniStatCard(
              label: 'Gym %',
              value: '${m.gymAttendancePct.toStringAsFixed(0)}%',
              icon: Icons.fitness_center_rounded,
              color: Colors.greenAccent,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: MiniStatCard(
              label: 'Best Streak',
              value: '${m.bestGymStreak} 🔥',
              icon: Icons.local_fire_department_rounded,
              color: const Color(0xFFFF6B35),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: MiniStatCard(
              label: 'Avg Calories',
              value: m.avgDailyCalories.toStringAsFixed(0),
              icon: Icons.restaurant_rounded,
              color: Colors.amber,
            ),
          ),
          const SizedBox(width: 10),
          if (m.weightChangeKg != null)
            Expanded(
              child: MiniStatCard(
                label: 'Weight Δ',
                value:
                    '${m.weightChangeKg! >= 0 ? '+' : ''}${m.weightChangeKg!.toStringAsFixed(1)} kg',
                icon: Icons.monitor_weight_rounded,
                color: m.weightChangeKg! <= 0
                    ? Colors.greenAccent
                    : const Color(0xFFFF6B35),
              ),
            ),
        ]),

        const SizedBox(height: 20),

        // ── Weight chart ───────────────────────────────────────────────────
        if (m.weightSeries.isNotEmpty) ...[
          TrendLineChart(
            data: m.weightSeries,
            title: 'Weight Trend (kg)',
            lineColor: theme.colorScheme.primary,
            unit: ' kg',
          ),
          const SizedBox(height: 10),
        ],

        // ── Calorie chart ──────────────────────────────────────────────────
        if (m.calorieSeries.isNotEmpty) ...[
          CalorieBarChart(data: m.calorieSeries),
          const SizedBox(height: 10),
        ],

        // ── Waist chart ────────────────────────────────────────────────────
        if (m.waistSeries.isNotEmpty) ...[
          TrendLineChart(
            data: m.waistSeries,
            title: 'Waist Trend (cm)',
            lineColor: const Color(0xFF9B59B6),
            unit: ' cm',
          ),
          const SizedBox(height: 10),
        ],

        // ── Mood chart ─────────────────────────────────────────────────────
        if (m.moodSeries.isNotEmpty) ...[
          TrendLineChart(
            data: m.moodSeries,
            title: 'Mood Score (1–5)',
            lineColor: Colors.amber,
            minY: 0,
            maxY: 6,
          ),
          const SizedBox(height: 16),
        ],

        // ── Comparison panel ───────────────────────────────────────────────
        if (m.startWeightKg != null && m.endWeightKg != null)
          _comparisonCard(m, context),

        const SizedBox(height: 16),

        // Motivation
        _motivationBanner(context, m.motivationMessage),
      ],
    );
  }

  Widget _highlightTile(String text, BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _comparisonCard(MonthlyAnalytics m, BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Month-over-Month',
                style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                    fontSize: 14)),
            const SizedBox(height: 14),
            _compareRow(
              'Weight',
              m.startWeightKg!,
              m.endWeightKg!,
              'kg',
              lowerIsBetter: true,
            ),
            if (m.startWaistCm != null && m.endWaistCm != null) ...[
              const Divider(color: Colors.white12, height: 20),
              _compareRow(
                'Waist',
                m.startWaistCm!,
                m.endWaistCm!,
                'cm',
                lowerIsBetter: true,
              ),
            ],
            if (m.weightChangePct != null) ...[
              const Divider(color: Colors.white12, height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('% Change',
                      style: TextStyle(color: Colors.white54, fontSize: 13)),
                  Text(
                    '${m.weightChangePct!.toStringAsFixed(2)}%',
                    style: TextStyle(
                      color: m.weightChangePct! <= 0
                          ? Colors.greenAccent
                          : const Color(0xFFFF6B35),
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _compareRow(
    String label,
    double start,
    double end,
    String unit, {
    required bool lowerIsBetter,
  }) {
    final change = end - start;
    final isGood = lowerIsBetter ? change <= 0 : change >= 0;
    final color  = isGood ? Colors.greenAccent : const Color(0xFFFF6B35);
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style:
                  const TextStyle(color: Colors.white54, fontSize: 13)),
        ),
        Text('${start.toStringAsFixed(1)} $unit',
            style: const TextStyle(color: Colors.white60, fontSize: 13)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Icon(Icons.arrow_forward_rounded,
              color: Colors.white24, size: 16),
        ),
        Text('${end.toStringAsFixed(1)} $unit',
            style:
                const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        Text(
          '(${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)})',
          style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _motivationBanner(BuildContext context, String msg) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Theme.of(context).colorScheme.secondary.withOpacity(0.25),
              Theme.of(context).colorScheme.primary.withOpacity(0.1),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🌟', style: TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(msg,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 14, height: 1.5)),
            ),
          ],
        ),
      );

  Widget _section(String title, BuildContext context) => Text(
        title,
        style: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
      );

  Widget _empty(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.calendar_month_rounded,
                color: Colors.white24, size: 60),
            const SizedBox(height: 16),
            const Text('No data for this month yet.',
                style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 12),
            ElevatedButton(
                onPressed: _load, child: const Text('Refresh')),
          ],
        ),
      );
}
