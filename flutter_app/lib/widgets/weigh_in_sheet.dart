import 'dart:async';
import 'package:flutter/material.dart';
import '../config/profile.dart';
import '../services/body_composition.dart';
import '../services/scale_service.dart';

/// Bottom sheet that connects to the Vitafit scale, shows the live weight and
/// returns the finished reading (or null if cancelled).
Future<BodyComposition?> showWeighInSheet(BuildContext context) =>
    showModalBottomSheet<BodyComposition>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const _WeighInSheet(),
    );

class _WeighInSheet extends StatefulWidget {
  const _WeighInSheet();
  @override
  State<_WeighInSheet> createState() => _WeighInSheetState();
}

class _WeighInSheetState extends State<_WeighInSheet> {
  StreamSubscription<ScaleEvent>? _sub;
  String _status = 'Starting…';
  double? _liveKg;
  bool _stable = false;
  BodyComposition? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sub = ScaleService.events.listen(_onEvent);
    _begin();
  }

  Future<void> _begin() async {
    setState(() {
      _error = null;
      _result = null;
      _liveKg = null;
      _stable = false;
      _status = 'Starting…';
    });
    final allowed = await ScaleService.requestPermission();
    if (!mounted) return;
    if (!allowed) {
      setState(() => _error =
          'GymTracker needs the "Nearby devices" permission to talk to the scale. '
          'Allow it in Android settings → Apps → GymTracker → Permissions.');
      return;
    }
    await ScaleService.start();
  }

  void _onEvent(ScaleEvent e) {
    if (!mounted) return;
    setState(() {
      switch (e) {
        case ScaleStatus(:final message):
          _status = message;
        case ScaleLiveWeight(:final weightKg, :final stable):
          _liveKg = weightKg;
          _stable = stable;
        case ScaleResult(:final weightKg, :final impedanceOhm):
          _result = BodyComposition.calculate(weightKg: weightKg, impedanceOhm: impedanceOhm);
          _liveKg = weightKg;
          _stable = true;
        case ScaleError(:final message):
          _error = message;
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    ScaleService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = _result;
    final kg = r?.weightKg ?? _liveKg;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            const Text('⚖️  Weigh in',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),

            // Big weight readout
            Center(
              child: Text(
                kg == null ? '— kg' : '${kg.toStringAsFixed(2)} kg',
                style: TextStyle(
                  color: _stable ? Colors.white : Colors.white54,
                  fontSize: 44,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                _error ?? (r != null ? 'Done — you can step off' : _status),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: _error != null ? Colors.orangeAccent : Colors.white60, fontSize: 13),
              ),
            ),

            if (r == null && _error == null) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(minHeight: 3),
            ],

            if (r != null) ...[
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _tile('BMI', r.bmi.toStringAsFixed(1)),
                  _tile('Body fat', _pct(r.bodyFatPct)),
                  _tile('Fat mass', _kg(BodyStats.fatMassKg(r.weightKg, r.bodyFatPct))),
                  _tile('Lean mass', _kg(BodyStats.leanMassKg(r.weightKg, r.bodyFatPct))),
                  _tile('Muscle mass', _pct(BodyStats.muscleMassPct(r.weightKg, r.bodyFatPct, r.boneKg))),
                  _tile('Skeletal muscle', _pct(r.musclePct)),
                  _tile('Body water', _pct(r.waterPct)),
                  _tile('Protein', _pct(BodyStats.proteinPct(r.weightKg, r.bodyFatPct, r.waterPct, r.boneKg))),
                  _tile('Bone mass', _kg(r.boneKg)),
                  _tile('BMR', '${r.bmrKcal.toStringAsFixed(0)} kcal'),
                  if (Profile.targetWeightKg != null)
                    _tile('To goal', r.weightKg <= Profile.targetWeightKg!
                        ? 'Reached 🎉'
                        : '${(r.weightKg - Profile.targetWeightKg!).toStringAsFixed(1)} kg'),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                r.impedanceOhm == null
                    ? 'Body composition needs you to stay on the scale barefoot until it finishes. Weight was saved.'
                    : 'Estimated from impedance (${r.impedanceOhm} Ω), ${Profile.heightCm!.toStringAsFixed(0)} cm, '
                        'age ${Profile.ageOn()}. Track the trend rather than single readings.',
                style: const TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, r),
                child: const Text('Use this reading'),
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _begin, child: const Text('Try again')),
            ],

            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(foregroundColor: theme.colorScheme.primary),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  String _pct(double? v) => v == null ? '—' : '${v.toStringAsFixed(1)}%';
  String _kg(double? v) => v == null ? '—' : '${v.toStringAsFixed(1)} kg';

  Widget _tile(String label, String value) => Container(
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
                style: const TextStyle(
                    color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
      );
}
