import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/gym_provider.dart';
import '../widgets/stat_card.dart';
import '../widgets/trend_chart.dart';
import '../models/analytics.dart';

class WeeklyScreen extends StatefulWidget {
  const WeeklyScreen({super.key});
  @override
  State<WeeklyScreen> createState() => _WeeklyScreenState();
}

class _WeeklyScreenState extends State<WeeklyScreen> {
  DateTime _weekRef = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final fmt = DateFormat('yyyy-MM-dd');
    await context
        .read<GymProvider>()
        .loadWeeklyAnalytics(fmt.format(_weekRef));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GymProvider>();
    final weekly   = provider.weeklyAnalytics;
    final theme    = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Weekly Report'),
        actions: [
          // Week navigation
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () {
              setState(() => _weekRef =
                  _weekRef.subtract(const Duration(days: 7)));
              _load();
            },
          ),
          TextButton(
            onPressed: () {
              setState(() => _weekRef = DateTime.now());
              _load();
            },
            child: Text(
              'This week',
              style: TextStyle(
                  color: theme.colorScheme.primary, fontSize: 13),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: _weekRef.isBefore(
                    DateTime.now().subtract(const Duration(days: 1)))
                ? () {
                    setState(() => _weekRef =
                        _weekRef.add(const Duration(days: 7)));
                    _load();
                  }
                : null,
          ),
        ],
      ),
      body: provider.loading
          ? const Center(child: CircularProgressIndicator())
          : weekly == null
              ? _emptyState(context)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _buildContent(context, weekly),
                ),
    );
  }

  Widget _buildContent(BuildContext context, WeeklyAnalytics weekly) {
    final fmt = DateFormat('MMM d');
    final start = DateTime.parse(weekly.weekStart);
    final end   = DateTime.parse(weekly.weekEnd);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      children: [
        const SizedBox(height: 16),

        // Week header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${fmt.format(start)} – ${fmt.format(end)}',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16),
              ),
              _scoreGauge(weekly.performanceScore, context),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── Stats grid ────────────────────────────────────────────────────
        Row(children: [
          Expanded(
            child: MiniStatCard(
              label: 'Gym Days',
              value: '${weekly.gymDays}/${weekly.daysLogged}',
              icon: Icons.fitness_center_rounded,
              color: Colors.greenAccent,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: MiniStatCard(
              label: 'Streak',
              value: '${weekly.gymStreak} 🔥',
              icon: Icons.local_fire_department_rounded,
              color: const Color(0xFFFF6B35),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: MiniStatCard(
              label: 'Avg Weight',
              value: weekly.avgWeightKg != null
                  ? '${weekly.avgWeightKg!.toStringAsFixed(1)} kg'
                  : '—',
              icon: Icons.monitor_weight_rounded,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: MiniStatCard(
              label: 'Avg Calories',
              value: '${weekly.avgDailyCalories.toStringAsFixed(0)}',
              icon: Icons.local_fire_department_rounded,
              color: Colors.amber,
            ),
          ),
        ]),

        const SizedBox(height: 16),

        // ── Change indicators ─────────────────────────────────────────────
        if (weekly.weightChangeKg != null)
          _changeCard(
            'Weight Change',
            weekly.weightChangeKg!,
            'kg',
            Icons.monitor_weight_rounded,
            lowerIsBetter: true,
          ),
        if (weekly.waistChangeCm != null) ...[
          const SizedBox(height: 10),
          _changeCard(
            'Waist Change',
            weekly.waistChangeCm!,
            'cm',
            Icons.straighten_rounded,
            lowerIsBetter: true,
          ),
        ],

        const SizedBox(height: 16),

        // ── Charts ────────────────────────────────────────────────────────
        CalorieBarChart(
          data: weekly.entries.map((e) {
            return DataPoint(date: e.date, value: e.totalCalories);
          }).toList(),
        ),
        const SizedBox(height: 10),

        if (weekly.entries.any((e) => e.weightKg != null))
          TrendLineChart(
            data: weekly.entries
                .where((e) => e.weightKg != null)
                .map((e) => DataPoint(date: e.date, value: e.weightKg))
                .toList(),
            title: 'Weight (kg)',
            lineColor: theme.colorScheme.primary,
            unit: ' kg',
          ),

        const SizedBox(height: 16),

        // ── Motivation ────────────────────────────────────────────────────
        _motivationBanner(context, weekly.motivationMessage),

        const SizedBox(height: 16),

        // ── Day-by-day table ──────────────────────────────────────────────
        _sectionHeader('Day Breakdown', context),
        const SizedBox(height: 10),
        ...weekly.entries.map((e) => _dayRow(e, context)),
      ],
    );
  }

  Widget _scoreGauge(int score, BuildContext context) {
    final color = score >= 80
        ? Colors.greenAccent
        : score >= 60
            ? Colors.amber
            : const Color(0xFFFF6B35);
    return Row(
      children: [
        Text('Score: ',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
        Text('$score',
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 18)),
        Text('/100',
            style: TextStyle(color: Colors.white38, fontSize: 12)),
      ],
    );
  }

  Widget _changeCard(
    String label,
    double change,
    String unit,
    IconData icon, {
    required bool lowerIsBetter,
  }) {
    final isGood = lowerIsBetter ? change <= 0 : change >= 0;
    final color  = isGood ? Colors.greenAccent : const Color(0xFFFF6B35);
    final prefix = change > 0 ? '+' : '';

    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
        trailing: Text(
          '$prefix${change.toStringAsFixed(1)} $unit',
          style: TextStyle(
              color: color, fontWeight: FontWeight.w800, fontSize: 18),
        ),
      ),
    );
  }

  Widget _motivationBanner(BuildContext context, String message) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Theme.of(context).colorScheme.primary.withOpacity(0.25),
              Theme.of(context).colorScheme.secondary.withOpacity(0.1),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('💬', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                    color: Colors.white, fontSize: 14, height: 1.5),
              ),
            ),
          ],
        ),
      );

  Widget _dayRow(entry, BuildContext context) {
    final fmt = DateFormat('EEE d');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: entry.gymAttended
              ? Colors.greenAccent.withOpacity(0.2)
              : Colors.white12,
          child: Icon(
            entry.gymAttended
                ? Icons.fitness_center_rounded
                : Icons.hotel_rounded,
            color: entry.gymAttended ? Colors.greenAccent : Colors.white38,
            size: 18,
          ),
        ),
        title: Text(
          fmt.format(DateTime.parse(entry.date)),
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          entry.weightKg != null
              ? '${entry.weightKg!.toStringAsFixed(1)} kg'
              : 'Weight not logged',
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
        trailing: Text(
          '${entry.totalCalories.toStringAsFixed(0)} kcal',
          style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
              fontSize: 14),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, BuildContext context) => Text(
        title.toUpperCase(),
        style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.white38,
            letterSpacing: 1.5),
      );

  Widget _emptyState(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bar_chart_rounded,
                color: Colors.white24, size: 60),
            const SizedBox(height: 16),
            const Text('No data for this week yet.',
                style: TextStyle(color: Colors.white54, fontSize: 16)),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _load,
              child: const Text('Refresh'),
            ),
          ],
        ),
      );
}

