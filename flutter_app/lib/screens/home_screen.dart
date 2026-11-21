import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/api_config.dart';
import '../config/profile.dart';
import '../models/entry.dart';
import '../widgets/body_cards.dart';
import '../widgets/profile_dialog.dart';
import '../providers/gym_provider.dart';
import '../widgets/stat_card.dart';
import '../widgets/gym_streak_badge.dart';
import '../widgets/watch_card.dart';
import '../services/reminder_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GymProvider>();
    final theme    = Theme.of(context);
    final today    = provider.todayEntry;
    final streak   = provider.currentStreak;
    final weekly   = provider.weeklyAnalytics;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: provider.loadDashboard,
        color: theme.colorScheme.primary,
        child: CustomScrollView(
          slivers: [
            // ── App Bar ─────────────────────────────────────────────────────
            SliverAppBar(
              expandedHeight: 140,
              floating: false,
              pinned: true,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.fromLTRB(20, 0, 16, 16),
                title: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '👋 ${Profile.greeting}',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontSize: 20,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      DateFormat('EEEE, MMMM d').format(DateTime.now()),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontSize: 12, color: Colors.white54),
                    ),
                  ],
                ),
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        theme.colorScheme.primary.withOpacity(0.3),
                        const Color(0xFF0F0F1A),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
              actions: [
                // Online/offline indicator
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Icon(
                    provider.isOnline
                        ? Icons.cloud_done_rounded
                        : Icons.cloud_off_rounded,
                    color: provider.isOnline
                        ? Colors.greenAccent
                        : Colors.orange,
                    size: 20,
                  ),
                ),
              ],
            ),

            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const SizedBox(height: 16),

                  // ── Streak badge ────────────────────────────────────────
                  if (streak > 0) ...[
                    GymStreakBadge(streak: streak),
                    const SizedBox(height: 16),
                  ],

                  // ── Today's summary ─────────────────────────────────────
                  _sectionHeader(context, "Today's Summary"),
                  const SizedBox(height: 10),

                  StatCard(
                    label: 'CALORIES',
                    value: Profile.calorieTarget != null
                        ? '${(today?.totalCalories ?? 0).toStringAsFixed(0)} / ${Profile.calorieTarget!.toStringAsFixed(0)} kcal'
                        : today != null
                            ? '${today.totalCalories.toStringAsFixed(0)} kcal'
                            : '— kcal',
                    subtitle: _calorieSubtitle(today, provider),
                    valueColor: _overTarget(today) ? Colors.orangeAccent : null,
                    icon: Icons.local_fire_department_rounded,
                    iconColor: const Color(0xFFFF6B35),
                  ),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: MiniStatCard(
                          label: 'Gym Today',
                          value: today?.gymAttended == true ? 'YES ✓' : 'No',
                          icon: Icons.fitness_center_rounded,
                          color: today?.gymAttended == true
                              ? Colors.greenAccent
                              : Colors.white38,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: MiniStatCard(
                          label: 'Weight',
                          value: today?.weightKg != null
                              ? '${today!.weightKg!.toStringAsFixed(1)} kg'
                              : '— kg',
                          icon: Icons.monitor_weight_rounded,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: MiniStatCard(
                          label: 'Waist',
                          value: today?.waistCm != null
                              ? '${today!.waistCm!.toStringAsFixed(1)} cm'
                              : '— cm',
                          icon: Icons.straighten_rounded,
                          color: const Color(0xFF9B59B6),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: MiniStatCard(
                          label: 'Mood',
                          value: today?.moodScore != null
                              ? _moodEmoji(today!.moodScore!)
                              : '—',
                          icon: Icons.mood_rounded,
                          color: Colors.amber,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // ── Goal + body composition (latest readings, any day) ─
                  _sectionHeader(context, 'Goal'),
                  const SizedBox(height: 10),
                  GoalCard(
                    currentKg: provider.latestWeight?.weightKg,
                    startKg: provider.startWeightKg,
                  ),
                  const SizedBox(height: 10),
                  BodyCompCard(
                    comp: provider.latestComp,
                    waist: provider.latestWaist,
                  ),

                  const SizedBox(height: 24),

                  // ── Galaxy Watch (Health Connect) ───────────────────────
                  _sectionHeader(context, 'Galaxy Watch'),
                  const SizedBox(height: 10),
                  WatchCard(data: provider.todayWatch),

                  const SizedBox(height: 24),

                  // ── This week overview ──────────────────────────────────
                  _sectionHeader(context, 'This Week'),
                  const SizedBox(height: 10),

                  if (weekly != null) ...[
                    StatCard(
                      label: 'GYM DAYS',
                      value: '${weekly.gymDays} / ${weekly.daysLogged}',
                      subtitle: 'days this week',
                      icon: Icons.sports_gymnastics_rounded,
                      iconColor: Colors.greenAccent,
                      trailing: _scoreChip(weekly.performanceScore, context),
                    ),
                    const SizedBox(height: 10),

                    if (weekly.weightChangeKg != null)
                      StatCard(
                        label: 'WEIGHT CHANGE',
                        value:
                            '${weekly.weightChangeKg! >= 0 ? '+' : ''}${weekly.weightChangeKg!.toStringAsFixed(1)} kg',
                        subtitle: weekly.avgWeightKg != null
                            ? 'avg ${weekly.avgWeightKg!.toStringAsFixed(1)} kg'
                            : null,
                        icon: Icons.trending_down_rounded,
                        iconColor: weekly.weightChangeKg! <= 0
                            ? Colors.greenAccent
                            : const Color(0xFFFF6B35),
                        valueColor: weekly.weightChangeKg! <= 0
                            ? Colors.greenAccent
                            : const Color(0xFFFF6B35),
                      ),

                    const SizedBox(height: 10),

                    // Motivation card
                    _motivationCard(context, weekly.motivationMessage),
                  ] else
                    _emptyWeekCard(context),

                  const SizedBox(height: 24),

                  // ── Settings link ────────────────────────────────────────
                  _profileTile(context, provider),
                  _remindersTile(context),
                  _healthConnectTile(context, provider),
                  _settingsTile(context),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _overTarget(DailyEntry? today) =>
      Profile.calorieTarget != null && (today?.totalCalories ?? 0) > Profile.calorieTarget!;

  /// Target status, protein, and the real deficit when the watch knows how
  /// much you burned: "✅ 450 under · 86/120 g protein · burned 2,650 → deficit 800".
  String _calorieSubtitle(DailyEntry? today, GymProvider provider) {
    final eaten = today?.totalCalories ?? 0;
    final parts = <String>[];
    final target = Profile.calorieTarget;
    if (eaten <= 0) {
      parts.add('Nothing logged yet');
    } else if (target != null) {
      final diff = target - eaten;
      parts.add(diff >= 0 ? '✅ ${diff.round()} under target' : '⚠️ ${(-diff).round()} over target');
    } else {
      parts.add('Set a calorie target in Profile');
    }
    if (today?.proteinG != null) {
      parts.add('${today!.proteinG!.round()}/${Profile.proteinTargetG.round()} g protein');
    }
    final burned = provider.todayWatch?.totalCalories;
    if (burned != null && burned > 0 && eaten > 0) {
      final deficit = burned - eaten;
      parts.add(deficit >= 0
          ? 'watch: burned ${burned.round()} → deficit ${deficit.round()}'
          : 'watch: burned ${burned.round()} → surplus ${(-deficit).round()}');
    }
    return parts.join(' · ');
  }

  Widget _sectionHeader(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.white38,
            letterSpacing: 1.5,
          ),
        ),
      );

  Widget _scoreChip(int score, BuildContext context) {
    final color = score >= 80
        ? Colors.greenAccent
        : score >= 60
            ? Colors.amber
            : const Color(0xFFFF6B35);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        '$score',
        style: TextStyle(
            color: color, fontWeight: FontWeight.w800, fontSize: 16),
      ),
    );
  }

  Widget _motivationCard(BuildContext context, String message) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Theme.of(context).colorScheme.primary.withOpacity(0.2),
              const Color(0xFF1A1A2E),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('✨', style: TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _emptyWeekCard(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Icon(Icons.bar_chart_rounded,
                  color: Colors.white24, size: 40),
              const SizedBox(height: 8),
              const Text('No data this week yet.',
                  style: TextStyle(color: Colors.white54)),
              const SizedBox(height: 4),
              Text('Start by logging today!',
                  style: TextStyle(
                      color:
                          Theme.of(context).colorScheme.primary,
                      fontSize: 13)),
            ],
          ),
        ),
      );

  Widget _profileTile(BuildContext context, GymProvider provider) {
    final goal = Profile.targetWeightKg;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.person_rounded, color: Colors.white38),
      title: const Text('Profile',
          style: TextStyle(color: Colors.white60, fontSize: 14)),
      subtitle: Text(
        Profile.isComplete
            ? '${Profile.heightCm!.toStringAsFixed(0)} cm · age ${Profile.ageOn()}'
                '${goal != null ? ' · goal ${goal.toStringAsFixed(0)} kg' : ''}'
            : 'Set your height, age and goal. Needed for body composition',
        style: TextStyle(
            color: Profile.isComplete ? Colors.white38 : Colors.amber, fontSize: 12),
      ),
      onTap: () async {
        if (await showProfileDialog(context, latestWeightKg: provider.latestWeight?.weightKg)) {
          provider.profileChanged();
        }
      },
    );
  }

  Widget _remindersTile(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.notifications_rounded, color: Colors.white38),
        title: const Text('Reminders',
            style: TextStyle(color: Colors.white60, fontSize: 14)),
        subtitle: const Text('Water, gym & daily log (local time)',
            style: TextStyle(color: Colors.white38, fontSize: 12)),
        onTap: () => showDialog(
          context: context,
          builder: (_) => const _RemindersDialog(),
        ),
      );

  Widget _healthConnectTile(BuildContext context, GymProvider provider) {
    final s = provider.healthStatus;
    final subtitle = !s.available
        ? 'Not connected'
        : s.fullyConnected
            ? 'Connected · nightly 11 PM sync on'
            : s.connected
                ? s.backgroundSupported && !s.background
                    ? 'Connected · allow background access for the 11 PM sync'
                    : 'Connected · some data types not allowed'
                : 'Not connected — tap to connect';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.watch_rounded, color: Colors.white38),
      title: const Text('Health Connect',
          style: TextStyle(color: Colors.white60, fontSize: 14)),
      subtitle: Text(subtitle,
          style: const TextStyle(color: Colors.white38, fontSize: 12)),
      // Re-requesting only asks for what's still missing (e.g. background access)
      onTap: () => s.fullyConnected
          ? provider.openHealthSettings()
          : provider.connectHealth(),
    );
  }

  Widget _settingsTile(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.settings_rounded, color: Colors.white38),
        title: const Text('Backend Settings',
            style: TextStyle(color: Colors.white60, fontSize: 14)),
        subtitle: Text(
          'Tap to configure server URL',
          style:
              const TextStyle(color: Colors.white38, fontSize: 12),
        ),
        onTap: () => _showSettingsDialog(context),
      );

  void _showSettingsDialog(BuildContext context) {
    final ctrl = TextEditingController(text: ApiConfig.baseUrl);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Backend URL',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            hintText: 'http://10.0.0.60:8000',
          ),
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (ctrl.text.isNotEmpty) {
                await ApiConfig.setBaseUrl(ctrl.text.trim());
                if (context.mounted) {
                  final provider = context.read<GymProvider>();
                  await provider.init();
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Server URL updated to ${ctrl.text.trim()}'),
                      backgroundColor: Colors.green.shade700,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  String _moodEmoji(int score) {
    const emojis = ['😢', '😕', '😐', '😊', '🤩'];
    if (score < 1 || score > 5) return '—';
    return emojis[score - 1];
  }
}

// ── Reminder settings ─────────────────────────────────────────────────────────

class _RemindersDialog extends StatefulWidget {
  const _RemindersDialog();
  @override
  State<_RemindersDialog> createState() => _RemindersDialogState();
}

class _RemindersDialogState extends State<_RemindersDialog> {
  Map<String, bool>? _settings;

  static const _items = [
    (ReminderService.water, '💧 Water', 'Every hour, 6 AM – 9 PM'),
    (ReminderService.gym,   '🏋️ Gym',   'Daily at 8 PM'),
    (ReminderService.log,   '📝 Daily log', '11 PM · also syncs watch data'),
  ];

  @override
  void initState() {
    super.initState();
    ReminderService.getSettings().then((s) {
      if (mounted) setState(() => _settings = s);
    });
  }

  Future<void> _toggle(String kind, bool on) async {
    setState(() => _settings![kind] = on);
    await ReminderService.setSettings(_settings!);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A2E),
      title: const Text('Reminders', style: TextStyle(color: Colors.white)),
      content: _settings == null
          ? const SizedBox(
              height: 80, child: Center(child: CircularProgressIndicator()))
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (kind, title, subtitle) in _items)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(title, style: const TextStyle(color: Colors.white)),
                    subtitle: Text(subtitle,
                        style: const TextStyle(color: Colors.white38, fontSize: 12)),
                    value: _settings![kind] ?? true,
                    onChanged: (v) => _toggle(kind, v),
                  ),
              ],
            ),
      actions: [
        TextButton(
          onPressed: () async {
            final allowed = await ReminderService.requestPermission();
            if (allowed) await ReminderService.sendTest();
            if (!context.mounted) return;
            if (!allowed) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Notifications are blocked — enable them in Android settings'),
                behavior: SnackBarBehavior.floating,
              ));
            }
          },
          child: const Text('Send test'),
        ),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done')),
      ],
    );
  }
}
