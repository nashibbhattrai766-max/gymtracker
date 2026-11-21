import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/profile.dart';
import '../models/entry.dart';
import '../services/body_composition.dart';

/// Target weight progress: current weight, kg to go, bar from the first logged weight.
class GoalCard extends StatelessWidget {
  final double? currentKg;
  final double? startKg;
  const GoalCard({super.key, required this.currentKg, required this.startKg});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = Profile.targetWeightKg;
    final current = currentKg;
    if (target == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Row(children: [
            Icon(Icons.flag_rounded, color: Colors.greenAccent, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text('Set a target weight in Profile (bottom of Home) to track your goal.',
                  style: TextStyle(color: Colors.white54, fontSize: 13)),
            ),
          ]),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.flag_rounded, color: Colors.greenAccent, size: 20),
              const SizedBox(width: 8),
              Text('Target ${target.toStringAsFixed(0)} kg',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
              const Spacer(),
              if (current != null)
                Text(
                  current <= target
                      ? 'Goal reached 🎉'
                      : '${(current - target).toStringAsFixed(1)} kg to go',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
            ]),
            const SizedBox(height: 14),
            if (current == null)
              const Text('Log your weight to track progress toward your goal.',
                  style: TextStyle(color: Colors.white54, fontSize: 13))
            else ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: BodyStats.goalProgress(startKg ?? current, current, target),
                  minHeight: 8,
                  backgroundColor: theme.colorScheme.primary.withOpacity(0.15),
                  valueColor: const AlwaysStoppedAnimation(Colors.greenAccent),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Text('Start ${(startKg ?? current).toStringAsFixed(1)} kg',
                    style: const TextStyle(color: Colors.white38, fontSize: 11)),
                const Spacer(),
                Text('Now ${current.toStringAsFixed(1)} kg',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('Goal ${target.toStringAsFixed(0)} kg',
                    style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ]),
              if (startKg != null && startKg! > current) ...[
                const SizedBox(height: 6),
                Text('${(startKg! - current).toStringAsFixed(1)} kg lost so far 💪',
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 12)),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Latest scale reading, Vitafit-style: fat vs lean mass plus the derived metrics.
class BodyCompCard extends StatelessWidget {
  final DailyEntry? comp;   // latest entry with body fat
  final DailyEntry? waist;  // latest entry with a waist measurement

  const BodyCompCard({super.key, required this.comp, required this.waist});

  @override
  Widget build(BuildContext context) {
    final c = comp;
    final whtr = BodyStats.waistToHeight(waist?.waistCm);

    String kg(double? v) => v == null ? '—' : '${v.toStringAsFixed(1)} kg';
    String pct(double? v) => v == null ? '—' : '${v.toStringAsFixed(1)}%';

    final w = c?.weightKg;
    final fatMass = BodyStats.fatMassKg(w, c?.bodyFatPct);
    final lean = BodyStats.leanMassKg(w, c?.bodyFatPct);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.accessibility_new_rounded, color: Color(0xFFFF6B35), size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Body composition',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              if (c != null)
                Text(DateFormat('d MMM').format(DateTime.parse(c.date)),
                    style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ]),
            const SizedBox(height: 14),
            if (c == null)
              const Text('Weigh in with the Vitafit scale on the Log screen to see body composition.',
                  style: TextStyle(color: Colors.white54, fontSize: 13))
            else ...[
              // Fat vs lean split — the key thing to watch while losing weight
              if (fatMass != null && lean != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Row(children: [
                    Expanded(
                      flex: (fatMass * 10).round(),
                      child: Container(height: 10, color: const Color(0xFFFF6B35)),
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      flex: (lean * 10).round(),
                      child: Container(height: 10, color: const Color(0xFF3987E5)),
                    ),
                  ]),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  _legend(const Color(0xFFFF6B35), 'Fat ${kg(fatMass)}'),
                  const SizedBox(width: 16),
                  _legend(const Color(0xFF3987E5), 'Lean ${kg(lean)}'),
                ]),
                const SizedBox(height: 16),
              ],
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _stat('Body fat', pct(c.bodyFatPct)),
                  _stat('BMI', BodyStats.bmi(w)?.toStringAsFixed(1) ?? '—'),
                  _stat('Muscle mass', pct(BodyStats.muscleMassPct(w, c.bodyFatPct, c.boneKg))),
                  _stat('Skeletal muscle', pct(c.musclePct)),
                  _stat('Body water', pct(c.waterPct)),
                  _stat('Protein', pct(BodyStats.proteinPct(w, c.bodyFatPct, c.waterPct, c.boneKg))),
                  _stat('Bone mass', kg(c.boneKg)),
                  _stat('BMR', c.bmrKcal == null ? '—' : '${c.bmrKcal!.toStringAsFixed(0)} kcal'),
                ],
              ),
            ],
            if (whtr != null) ...[
              const SizedBox(height: 14),
              const Divider(color: Colors.white12, height: 1),
              const SizedBox(height: 12),
              Row(children: [
                Icon(
                  whtr < 0.5 ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                  size: 18,
                  color: whtr < 0.5 ? Colors.greenAccent : whtr < 0.6 ? Colors.amber : const Color(0xFFFF6B35),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Waist-to-height ${whtr.toStringAsFixed(2)} · ${BodyStats.whtrLabel(whtr)}',
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
              const Padding(
                padding: EdgeInsets.only(left: 26, top: 2),
                child: Text('Belly-fat indicator · aim below 0.50',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _legend(Color color, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ]);

  Widget _stat(String label, String value) => Container(
        width: 100,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF22223A),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
      );
}
