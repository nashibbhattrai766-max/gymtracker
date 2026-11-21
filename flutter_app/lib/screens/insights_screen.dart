import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/gym_provider.dart';
import '../widgets/gym_streak_badge.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});
  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final p = context.read<GymProvider>();
      await Future.wait([
        p.loadWeeklyAnalytics(DateFormat('yyyy-MM-dd').format(DateTime.now())),
        p.loadMonthlyAnalytics(DateFormat('yyyy-MM').format(DateTime.now())),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p      = context.watch<GymProvider>();
    final theme  = Theme.of(context);
    final weekly  = p.weeklyAnalytics;
    final monthly = p.monthlyAnalytics;
    final streak  = p.streakInfo;

    return Scaffold(
      appBar: AppBar(title: const Text('Insights')),
      body: p.loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await p.loadDashboard();
              },
              child: ListView(
                padding:
                    const EdgeInsets.fromLTRB(16, 0, 16, 100),
                children: [
                  const SizedBox(height: 16),

                  // ── Hero streak ────────────────────────────────────────
                  Center(
                    child: GymStreakBadge(streak: p.currentStreak)
                        .animate()
                        .scale(duration: 600.ms, curve: Curves.elasticOut),
                  ),
                  const SizedBox(height: 8),
                  if (streak != null)
                    Center(
                      child: Text(
                        'All-time best: ${streak.longestStreak} days  •  Total gym sessions: ${streak.totalGymDays}',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),

                  const SizedBox(height: 28),

                  // ── Weekly motivational message ────────────────────────
                  if (weekly != null) ...[
                    _card(
                      context,
                      gradient: [
                        theme.colorScheme.primary.withOpacity(0.3),
                        theme.colorScheme.primary.withOpacity(0.05),
                      ],
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('💬 This Week',
                              style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1)),
                          const SizedBox(height: 8),
                          Text(
                            weekly.motivationMessage,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              height: 1.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _scoreBar(weekly.performanceScore, context),
                        ],
                      ),
                    ).animate().fadeIn(delay: 100.ms, duration: 400.ms).slideY(begin: 0.1),
                    const SizedBox(height: 16),
                  ],

                  // ── Monthly message ────────────────────────────────────
                  if (monthly != null) ...[
                    _card(
                      context,
                      gradient: [
                        theme.colorScheme.secondary.withOpacity(0.3),
                        theme.colorScheme.secondary.withOpacity(0.05),
                      ],
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('🌟 This Month',
                              style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1)),
                          const SizedBox(height: 8),
                          Text(
                            monthly.motivationMessage,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              height: 1.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: 200.ms, duration: 400.ms).slideY(begin: 0.1),
                    const SizedBox(height: 16),
                  ],

                  // ── Monthly highlights as achievement tiles ────────────
                  if (monthly != null && monthly.highlights.isNotEmpty) ...[
                    const Text('ACHIEVEMENTS',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white38,
                            letterSpacing: 1.5)),
                    const SizedBox(height: 10),
                    ...monthly.highlights.asMap().entries.map(
                          (e) => _achievementTile(e.value, e.key, context),
                        ),
                    const SizedBox(height: 16),
                  ],

                  // ── Personal bests ────────────────────────────────────
                  if (streak != null) ...[
                    const Text('PERSONAL BESTS',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white38,
                            letterSpacing: 1.5)),
                    const SizedBox(height: 10),
                    _pbGrid(streak, context),
                    const SizedBox(height: 16),
                  ],

                  // ── Weekly radar summary ───────────────────────────────
                  if (weekly != null) ...[
                    const Text('WEEKLY BREAKDOWN',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white38,
                            letterSpacing: 1.5)),
                    const SizedBox(height: 10),
                    _weekBreakdown(weekly, context),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _card(BuildContext context,
      {required Widget child, List<Color>? gradient}) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: gradient != null
              ? LinearGradient(
                  colors: gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: gradient == null
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : null,
          borderRadius: BorderRadius.circular(20),
        ),
        child: child,
      );

  Widget _scoreBar(int score, BuildContext context) {
    final color = score >= 80
        ? Colors.greenAccent
        : score >= 60
            ? Colors.amber
            : const Color(0xFFFF6B35);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Performance Score',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            Text('$score / 100',
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 14)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: score / 100,
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 6,
          ),
        ),
      ],
    );
  }

  Widget _achievementTile(String text, int index, BuildContext context) {
    const medals = ['🥇', '🥈', '🥉', '⭐', '✨'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Text(
              index < medals.length ? medals[index] : '⭐',
              style: const TextStyle(fontSize: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ).animate().fadeIn(delay: Duration(milliseconds: 50 * index), duration: 300.ms).slideX(begin: -0.05),
    );
  }

  Widget _pbGrid(streak, BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _pbCard(
            '🔥',
            '${streak.longestStreak}',
            'Longest streak',
            const Color(0xFFFF6B35),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _pbCard(
            '🏋️',
            '${streak.totalGymDays}',
            'Total sessions',
            Colors.greenAccent,
          ),
        ),
      ],
    );
  }

  Widget _pbCard(String emoji, String value, String label, Color color) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(
                    color: color,
                    fontSize: 28,
                    fontWeight: FontWeight.w900)),
            Text(label,
                style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11),
                textAlign: TextAlign.center),
          ],
        ),
      );

  Widget _weekBreakdown(weekly, BuildContext context) {
    final theme = Theme.of(context);
    final items = [
      _BreakdownItem(
          'Gym',
          weekly.gymDays / (weekly.daysLogged > 0 ? weekly.daysLogged : 1),
          Colors.greenAccent,
          '${weekly.gymDays}/${weekly.daysLogged} days'),
      _BreakdownItem(
          'Calories',
          weekly.avgDailyCalories > 0
              ? (weekly.avgDailyCalories / 2500).clamp(0, 1).toDouble()
              : 0,
          Colors.amber,
          '${weekly.avgDailyCalories.toStringAsFixed(0)} avg'),
      if (weekly.avgSleepHours != null)
        _BreakdownItem(
            'Sleep',
            (weekly.avgSleepHours! / 8).clamp(0, 1).toDouble(),
            theme.colorScheme.primary,
            '${weekly.avgSleepHours!.toStringAsFixed(1)} hrs avg'),
      if (weekly.avgWaterLitres != null)
        _BreakdownItem(
            'Hydration',
            (weekly.avgWaterLitres! / 3).clamp(0, 1).toDouble(),
            Colors.cyan,
            '${weekly.avgWaterLitres!.toStringAsFixed(1)} L avg'),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: items
              .map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            Text(item.label,
                                style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                            Text(item.subtitle,
                                style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: item.progress,
                            backgroundColor: Colors.white12,
                            valueColor: AlwaysStoppedAnimation(item.color),
                            minHeight: 8,
                          ),
                        ),
                      ],
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }
}

class _BreakdownItem {
  final String label;
  final double progress;
  final Color color;
  final String subtitle;
  _BreakdownItem(this.label, this.progress, this.color, this.subtitle);
}
