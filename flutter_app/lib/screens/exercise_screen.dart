import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../data/workout_plan.dart';
import '../models/workout.dart';
import '../providers/gym_provider.dart';
import '../services/api_service.dart';
import '../services/link_service.dart';
import '../services/local_storage.dart';

/// The 5-day rotation: pick a day (defaults to "next up"), follow the
/// treadmill routine and exercises, log weight × reps per set, tick them off
/// and finish. Every change is saved straight away on the phone.
class ExerciseScreen extends StatefulWidget {
  const ExerciseScreen({super.key});
  @override
  State<ExerciseScreen> createState() => _ExerciseScreenState();
}

class _ExerciseScreenState extends State<ExerciseScreen> with WidgetsBindingObserver {
  static const _violet = Color(0xFF6C63FF);
  static const _orange = Color(0xFFFF6B35);

  WorkoutSession? _session;
  bool _stored = false;            // session exists in storage (user logged something)
  int _nextDay = 1;
  bool _loading = true;
  final Map<String, ExerciseLog?> _lastTime = {};
  final Set<String> _showTips = {};
  Timer? _saveTimer;

  String get _today => DateFormat('yyyy-MM-dd').format(DateTime.now());
  PlanDay get _plan => planDay(_session!.day);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flushSave();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _flushSave();
    // New day while the app was in the background: start from "next up" again
    if (state == AppLifecycleState.resumed && _session != null && _session!.date != _today) _init();
  }

  Future<void> _init() async {
    final active = await WorkoutStorage.inProgress(_today);
    final last = await WorkoutStorage.lastFinished();
    _nextDay = last == null ? 1 : (last.day % workoutPlan.length) + 1;
    // Open today's workout if one is under way (or already finished today)
    final day = active?.day ?? (last?.date == _today ? last!.day : _nextDay);
    await _openDay(day);
  }

  Future<void> _openDay(int day) async {
    _flushSave();
    final saved = await WorkoutStorage.get(_today, day);
    final session = saved ?? WorkoutSession.start(_today, day);
    session.ensurePlan();
    _lastTime.clear();
    for (final e in planDay(day).exercises) {
      // History is kept per machine: main and alternative separately
      for (final id in [e.id, if (e.alt != null) e.alt!.id]) {
        _lastTime[id] = await WorkoutStorage.lastTime(id, _today);
      }
    }
    if (!mounted) return;
    setState(() {
      _session = session;
      _stored = saved != null;
      _loading = false;
    });
  }

  // ── Saving ─────────────────────────────────────────────────────────────────

  /// Any edit: save on the phone shortly after (and to the server too once
  /// the workout is finished, so later corrections reach the charts).
  void _changed() {
    setState(() => _stored = true);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _flushSave);
  }

  void _flushSave() {
    final s = _session;
    if (_saveTimer == null || s == null) return;
    _saveTimer!.cancel();
    _saveTimer = null;
    ApiService.saveWorkout(s, push: s.finished);
  }

  Future<void> _finish() async {
    final s = _session!;
    if (s.exercisesDone == 0 && !s.treadmill.done) {
      final go = await _confirm('Nothing ticked yet', 'Finish this workout anyway?');
      if (!go) return;
    }
    _saveTimer?.cancel();
    _saveTimer = null;
    setState(() => s.finishedAt = DateTime.now().toIso8601String());

    final provider = context.read<GymProvider>();
    final pushed = await ApiService.saveWorkout(s);
    await provider.markGymAttended(s.date);
    provider.syncWatchDay(s.date); // pull the watch's heart rate / calories for today

    if (!mounted) return;
    setState(() {
      _stored = true;
      _nextDay = (s.day % workoutPlan.length) + 1;
    });
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text('${_plan.emoji} Day ${s.day} done!', style: const TextStyle(color: Colors.white)),
        content: Text(
          [
            '${s.exercisesDone} of ${s.exercises.length} exercises',
            if (s.volumeKg > 0) '${NumberFormat.decimalPattern().format(s.volumeKg.round())} kg lifted in total',
            if (s.treadmill.done) 'Treadmill ${s.treadmill.minutes?.toStringAsFixed(0) ?? '30'} min ✓',
            '"Gym" is ticked on today\'s log.',
            if (!pushed) '\nSaved on your phone. It will sync when the server is reachable.',
            '\nNext up: Day $_nextDay · ${planDay(_nextDay).title}',
          ].join('\n'),
          style: const TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Nice 💪'))],
      ),
    );
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          title: Text(title, style: const TextStyle(color: Colors.white)),
          content: Text(body, style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Finish')),
          ],
        ),
      ) ??
      false;

  Future<void> _open(String url) async {
    final ok = await LinkService.open(url);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Couldn't open the link"), behavior: SnackBarBehavior.floating));
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Exercise')),
      body: _loading || _session == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              children: [
                _daySelector(),
                const SizedBox(height: 12),
                _header(),
                if (_plan.format != null) ...[
                  const SizedBox(height: 12),
                  _infoBox(_plan.format!),
                ],
                const SizedBox(height: 16),
                _treadmillCard(),
                const SizedBox(height: 16),
                ..._exerciseCards(),
                const SizedBox(height: 8),
                _finishButton(),
              ],
            ),
    );
  }

  Widget _daySelector() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: _session!.day,
            isExpanded: true,
            dropdownColor: const Color(0xFF22223A),
            items: [
              for (final d in workoutPlan)
                DropdownMenuItem(
                  value: d.day,
                  child: Row(children: [
                    Flexible(
                      child: Text('${d.emoji}  Day ${d.day} · ${d.title}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    ),
                    if (d.day == _nextDay) ...[
                      const SizedBox(width: 8),
                      _chip('Next up', _violet),
                    ],
                  ]),
                ),
            ],
            onChanged: (d) {
              if (d != null && d != _session!.day) _openDay(d);
            },
          ),
        ),
      );

  Widget _header() {
    final s = _session!;
    final status = s.finished
        ? _chip('✅ Done ${DateFormat('h:mm a').format(DateTime.parse(s.finishedAt!))}', Colors.greenAccent)
        : _stored
            ? _chip('In progress', Colors.amber)
            : s.day == _nextDay
                ? _chip('Next up', _violet)
                : _chip('Not started', Colors.white38);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [_violet.withOpacity(0.3), const Color(0xFF1A1A2E)]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(_plan.emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Day ${s.day} · ${_plan.title}',
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                Text(_plan.focus, style: const TextStyle(color: Colors.white60, fontSize: 13)),
              ]),
            ),
            status,
          ]),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (s.exercisesDone + (s.treadmill.done ? 1 : 0)) / (s.exercises.length + 1),
              minHeight: 6,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation(Colors.greenAccent),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${s.treadmill.done ? '✓' : '○'} Treadmill · ${s.exercisesDone}/${s.exercises.length} exercises'
            '${s.volumeKg > 0 ? ' · ${NumberFormat.decimalPattern().format(s.volumeKg.round())} kg lifted' : ''}',
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _infoBox(String text) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _orange.withOpacity(0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _orange.withOpacity(0.35)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.timer_rounded, color: _orange, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4))),
        ]),
      );

  // ── Treadmill ──────────────────────────────────────────────────────────────

  Widget _treadmillCard() {
    final t = _session!.treadmill;
    final p = _plan.treadmill;
    final k = '${_session!.id}-tm';
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.directions_run_rounded, color: Colors.lightBlueAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Treadmill · 30 min', style: _titleStyle(t.done)),
                  Text('${p.name} · ${p.summary}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
                ]),
              ),
              Checkbox(
                value: t.done,
                activeColor: Colors.greenAccent,
                onChanged: (v) {
                  t.done = v ?? false;
                  _changed();
                },
              ),
            ]),
            const SizedBox(height: 6),
            for (final step in p.steps)
              Padding(
                padding: const EdgeInsets.only(bottom: 3, right: 8),
                child: Text('•  $step', style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.35)),
              ),
            const SizedBox(height: 4),
            _linkButton('▶ How it works', p.videoUrl),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(children: [
                _numField('$k-min', 'Min', t.minutes, (v) => t.minutes = v),
                _numField('$k-spd', 'km/h', t.speedKmh, (v) => t.speedKmh = v),
                _numField('$k-inc', 'Incline %', t.inclinePct, (v) => t.inclinePct = v),
                _numField('$k-dist', 'km', t.distanceKm, (v) => t.distanceKm = v, last: true),
              ]),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Heart rate and calories come from your watch automatically.',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Exercises ──────────────────────────────────────────────────────────────

  List<Widget> _exerciseCards() {
    final isCircuit = _plan.format != null;
    final widgets = <Widget>[];
    String? lastLetter;
    for (final pe in _plan.exercises) {
      final log = _session!.exercise(pe.id);
      if (log == null) continue;
      final letter = isCircuit ? 'Circuit' : pe.group.substring(0, 1);
      if (letter != lastLetter) {
        lastLetter = letter;
        final inGroup = _plan.exercises.where((e) => e.group.startsWith(letter)).length;
        widgets.add(_groupHeader(isCircuit
            ? 'Circuit · ${pe.sets} rounds'
            : inGroup > 1
                ? 'Superset $letter · do ${letter}1 then ${letter}2, then rest'
                : '$letter · straight sets'));
      }
      widgets.add(_exerciseCard(pe, log, isCircuit));
      widgets.add(const SizedBox(height: 10));
    }
    return widgets;
  }

  Widget _groupHeader(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
        child: Text(text.toUpperCase(),
            style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
      );

  Widget _exerciseCard(PlanExercise pe, ExerciseLog log, bool isCircuit) {
    // Main machine or its alternative (when the machine was busy)
    final alt = pe.alt;
    final usingAlt = alt != null && log.variant == alt.id;
    final name = usingAlt ? alt.name : pe.name;
    final tips = usingAlt ? alt.tips : pe.tips;
    final videoUrl = usingAlt ? alt.videoUrl : pe.videoUrl;
    final weighted = usingAlt ? alt.weighted : pe.weighted;
    final last = _lastTime[log.doneAs];
    final k = '${_session!.id}-${pe.id}';
    final target = isCircuit
        ? '${pe.sets} rounds × ${pe.reps}'
        : '${pe.sets} × ${pe.reps}${pe.restSec > 0 ? ' · rest ${pe.restSec} s' : ''}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              _badge(pe.group),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: _titleStyle(log.done)),
                  Text('$target · ${pe.muscles}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ]),
              ),
              Checkbox(
                value: log.done,
                activeColor: Colors.greenAccent,
                onChanged: (v) {
                  log.done = v ?? false;
                  _changed();
                },
              ),
            ]),
            if (last != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 8),
                child: Text('Last time: ${_describe(last)}',
                    style: const TextStyle(color: Colors.amber, fontSize: 12)),
              ),
            const SizedBox(height: 6),
            Wrap(spacing: 4, children: [
              _linkButton('▶ Watch', videoUrl),
              _linkButton('🔎 Search YouTube', searchUrl(name)),
              TextButton(
                style: TextButton.styleFrom(
                    foregroundColor: Colors.white70, visualDensity: VisualDensity.compact),
                onPressed: () => setState(() =>
                    _showTips.contains(pe.id) ? _showTips.remove(pe.id) : _showTips.add(pe.id)),
                child: Text(_showTips.contains(pe.id) ? 'Hide tips' : 'Form tips'),
              ),
            ]),
            if (_showTips.contains(pe.id))
              Padding(
                padding: const EdgeInsets.only(bottom: 6, right: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final tip in tips)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text('•  $tip',
                          style: const TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.35)),
                    ),
                ]),
              ),
            if (alt != null) _swapButton(pe, log, usingAlt),
            for (var i = 0; i < log.sets.length; i++) _setRow(weighted, log, i, last, k, isCircuit),
            Row(children: [
              TextButton.icon(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () {
                  log.sets.add(WorkoutSet());
                  _changed();
                },
                icon: const Icon(Icons.add_rounded, size: 16),
                label: Text(isCircuit ? 'Round' : 'Set'),
              ),
              if (log.sets.length > 1)
                TextButton.icon(
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.white38, visualDensity: VisualDensity.compact),
                  onPressed: () {
                    log.sets.removeLast();
                    _changed();
                  },
                  icon: const Icon(Icons.remove_rounded, size: 16),
                  label: const Text('Remove'),
                ),
            ]),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextFormField(
                key: ValueKey('$k-notes'),
                initialValue: log.notes,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Notes (e.g. felt easy, seat height 4)',
                ),
                onChanged: (v) {
                  log.notes = v;
                  _changed();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _setRow(bool weighted, ExerciseLog log, int i, ExerciseLog? last, String k, bool isCircuit) {
    final set = log.sets[i];
    final prev = last != null && i < last.sets.length ? last.sets[i] : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        SizedBox(
          width: 56,
          child: Text(isCircuit ? 'Round ${i + 1}' : 'Set ${i + 1}',
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ),
        if (weighted)
          _numField('$k-w$i', 'kg', set.weightKg, (v) => set.weightKg = v,
              hint: prev?.weightKg != null ? _fmt(prev!.weightKg!) : null),
        _numField('$k-r$i', isCircuit ? 'reps / cal' : 'reps', set.reps?.toDouble(),
            (v) => set.reps = v?.round(),
            hint: prev?.reps?.toString(), integer: true, last: true),
        Checkbox(
          value: set.done,
          activeColor: Colors.greenAccent,
          onChanged: (v) {
            set.done = v ?? false;
            // All sets done → the exercise is done
            if (log.sets.every((s) => s.done)) log.done = true;
            _changed();
          },
        ),
      ]),
    );
  }

  Widget _numField(String key, String label, double? value, void Function(double?) onSet,
      {String? hint, bool integer = false, bool last = false}) {
    return Expanded(
      child: Padding(
        padding: EdgeInsets.only(right: last ? 0 : 8),
        child: TextFormField(
          key: ValueKey(key),
          initialValue: value == null ? '' : (integer ? value.round().toString() : _fmt(value)),
          keyboardType: TextInputType.numberWithOptions(decimal: !integer),
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            isDense: true,
            labelText: label,
            hintText: hint,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          ),
          onChanged: (v) {
            onSet(v.trim().isEmpty ? null : double.tryParse(v.trim()));
            _changed();
          },
        ),
      ),
    );
  }

  Widget _finishButton() {
    final s = _session!;
    if (s.finished) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.greenAccent.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.greenAccent.withOpacity(0.4)),
        ),
        child: Text(
          '✅ Finished. Changes you make now are saved automatically.\n'
          'Next up: Day $_nextDay · ${planDay(_nextDay).title}',
          style: const TextStyle(color: Colors.greenAccent, fontSize: 13, height: 1.4),
        ),
      );
    }
    return ElevatedButton.icon(
      onPressed: _finish,
      icon: const Icon(Icons.flag_rounded),
      label: const Text('Finish workout'),
    );
  }

  // ── Small pieces ───────────────────────────────────────────────────────────

  TextStyle _titleStyle(bool done) => TextStyle(
        color: done ? Colors.greenAccent : Colors.white,
        fontWeight: FontWeight.w700,
        fontSize: 15,
      );

  Widget _badge(String text) => Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _violet.withOpacity(0.2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text, style: const TextStyle(color: _violet, fontWeight: FontWeight.w800, fontSize: 13)),
      );

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      );

  /// "Machine busy? Use: Smith machine bench press" ↔ "Back to: Seated chest press machine".
  /// Sets stay as typed; "last time" switches to that machine's own history.
  Widget _swapButton(PlanExercise pe, ExerciseLog log, bool usingAlt) => Padding(
        padding: const EdgeInsets.only(bottom: 6, right: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            log.variant = usingAlt ? null : pe.alt!.id;
            log.name = usingAlt ? pe.name : pe.alt!.name;
            _changed();
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: (usingAlt ? Colors.amber : Colors.white).withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: (usingAlt ? Colors.amber : Colors.white24).withOpacity(0.5)),
            ),
            child: Row(children: [
              Icon(Icons.swap_horiz_rounded, size: 18, color: usingAlt ? Colors.amber : Colors.white54),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  usingAlt ? 'Using the alternative · back to: ${pe.name}' : 'Machine busy? Use: ${pe.alt!.name}',
                  style: TextStyle(color: usingAlt ? Colors.amber : Colors.white60, fontSize: 12),
                ),
              ),
            ]),
          ),
        ),
      );

  Widget _linkButton(String label, String url) => TextButton(
        style: TextButton.styleFrom(foregroundColor: _orange, visualDensity: VisualDensity.compact),
        onPressed: () => _open(url),
        child: Text(label),
      );

  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  /// "20 kg × 12, 20 × 11, 20 × 10" or "12, 11, 10 reps"
  String _describe(ExerciseLog log) {
    final filled = log.sets.where((s) => s.reps != null || s.weightKg != null).toList();
    if (filled.isEmpty) return '—';
    final parts = <String>[];
    for (var i = 0; i < filled.length; i++) {
      final s = filled[i];
      final w = s.weightKg != null ? '${_fmt(s.weightKg!)}${i == 0 ? ' kg' : ''}' : null;
      final r = s.reps?.toString() ?? '?';
      parts.add(w != null ? '$w × $r' : r);
    }
    return parts.join(', ') + (filled.first.weightKg == null ? ' reps' : '');
  }
}
