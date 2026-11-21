import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/entry.dart';
import '../providers/gym_provider.dart';
import '../models/watch_data.dart';
import '../services/api_service.dart';
import '../widgets/watch_card.dart';
import '../widgets/weigh_in_sheet.dart';
import '../widgets/food_photo_sheet.dart';
import '../widgets/profile_dialog.dart';
import '../config/profile.dart';

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});
  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _breakfastCtrl = TextEditingController();
  final _lunchCtrl     = TextEditingController();
  final _dinnerCtrl    = TextEditingController();
  final _miscCtrl      = TextEditingController();
  final _weightCtrl    = TextEditingController();
  final _waistCtrl     = TextEditingController();
  final _sleepCtrl     = TextEditingController();
  final _waterCtrl     = TextEditingController();
  final _notesCtrl     = TextEditingController();
  final _proteinCtrl   = TextEditingController();
  List<MealItem> _items = [];      // photo-estimated food for the day
  double? _loadedCalTarget;        // targets saved with the day (kept for past days)
  double? _loadedProteinTarget;

  bool  _gymAttended = false;
  int?  _moodScore;
  bool  _saving = false;
  bool  _loaded = false;
  DateTime _selectedDate = DateTime.now();
  WatchData? _pastWatch; // watch data when a past date is selected
  // Body composition from the Vitafit scale (part of the day's entry)
  ({double? fat, double? water, double? muscle, double? bone, double? bmr, int? ohm})? _scale;

  // The form always shows the selected day's saved entry. Edits are "dirty"
  // until Save, which stores the whole day (form + scale reading) in one go.
  bool _dirty = false;
  bool _hasSavedEntry = false;
  bool _followToday = true; // re-open on "today" after midnight if nothing is pending
  int _seenRevision = -1;   // provider.entryRevision last seen

  String get _dateKey => DateFormat('yyyy-MM-dd').format(_selectedDate);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDate(DateTime.now()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the app (e.g. from the 11 PM reminder): show the latest
    // saved data, but never throw away edits that haven't been saved yet.
    if (state == AppLifecycleState.resumed && !_dirty && !_saving) {
      _loadDate(_followToday ? DateTime.now() : _selectedDate);
    }
  }

  /// Loads [day]'s saved entry into the form (empty form if nothing saved).
  Future<void> _loadDate(DateTime day) async {
    final entry = await ApiService.getEntry(DateFormat('yyyy-MM-dd').format(day));
    if (!mounted) return;
    setState(() {
      _selectedDate = day;
      _fill(entry);
      _dirty = false;
      _loaded = true;
    });
    await _loadPastWatch();
  }

  String _num(double? v, int digits) => v == null ? '' : v.toStringAsFixed(digits);
  String _cal(double v) => v > 0 ? v.toStringAsFixed(0) : '';

  void _fill(DailyEntry? e) {
    _hasSavedEntry = e != null;
    _breakfastCtrl.text = _cal(e?.calBreakfast ?? 0);
    _lunchCtrl.text     = _cal(e?.calLunch ?? 0);
    _dinnerCtrl.text    = _cal(e?.calDinner ?? 0);
    _miscCtrl.text      = _cal(e?.calMisc ?? 0);
    // Scale weights have two decimals; keep them rather than rounding
    _weightCtrl.text    = e?.weightKg == null ? '' : _trim(e!.weightKg!);
    _waistCtrl.text     = _num(e?.waistCm, 1);
    _sleepCtrl.text     = _num(e?.sleepHours, 1);
    _waterCtrl.text     = _num(e?.waterLitres, 1);
    _notesCtrl.text     = e?.notes ?? '';
    _proteinCtrl.text   = e?.proteinG == null ? '' : _trim(e!.proteinG!);
    _items              = e?.items ?? [];
    _loadedCalTarget    = e?.calorieTarget;
    _loadedProteinTarget = e?.proteinTargetG;
    _gymAttended        = e?.gymAttended ?? false;
    _moodScore          = e?.moodScore;
    _scale = e == null || (e.bodyFatPct == null && e.impedanceOhm == null && e.bmrKcal == null)
        ? null
        : (fat: e.bodyFatPct, water: e.waterPct, muscle: e.musclePct,
           bone: e.boneKg, bmr: e.bmrKcal, ohm: e.impedanceOhm);
  }

  /// 92.75 → "92.75", 92.70 → "92.7"
  String _trim(double v) {
    final s = v.toStringAsFixed(2);
    return s.endsWith('0') ? v.toStringAsFixed(1) : s;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final c in [
      _breakfastCtrl, _lunchCtrl, _dinnerCtrl, _miscCtrl,
      _weightCtrl, _waistCtrl, _sleepCtrl, _waterCtrl, _notesCtrl, _proteinCtrl
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double get _totalCalories =>
      (_parse(_breakfastCtrl.text) ?? 0) +
      (_parse(_lunchCtrl.text)     ?? 0) +
      (_parse(_dinnerCtrl.text)    ?? 0) +
      (_parse(_miscCtrl.text)      ?? 0);

  bool get _isToday =>
      DateUtils.isSameDay(_selectedDate, DateTime.now());

  Future<void> _loadPastWatch() async {
    final data = await context.read<GymProvider>().watchFor(_dateKey);
    if (mounted) setState(() => _pastWatch = data);
  }

  double? _parse(String v) => v.isEmpty ? null : double.tryParse(v);

  /// The whole day as currently shown in the form.
  DailyEntry _formEntry() => DailyEntry(
        date:          _dateKey,
        calBreakfast:  _parse(_breakfastCtrl.text) ?? 0,
        calLunch:      _parse(_lunchCtrl.text)     ?? 0,
        calDinner:     _parse(_dinnerCtrl.text)    ?? 0,
        calMisc:       _parse(_miscCtrl.text)      ?? 0,
        weightKg:      _parse(_weightCtrl.text),
        waistCm:       _parse(_waistCtrl.text),
        gymAttended:   _gymAttended,
        sleepHours:    _parse(_sleepCtrl.text),
        waterLitres:   _parse(_waterCtrl.text),
        moodScore:     _moodScore,
        notes:         _notesCtrl.text.isEmpty ? null : _notesCtrl.text,
        bodyFatPct:    _scale?.fat,
        waterPct:      _scale?.water,
        musclePct:     _scale?.muscle,
        boneKg:        _scale?.bone,
        bmrKcal:       _scale?.bmr,
        impedanceOhm:  _scale?.ohm,
        proteinG:      _parse(_proteinCtrl.text),
        // Today uses the current Profile targets; past days keep the ones saved then
        calorieTarget:  _isToday ? Profile.calorieTarget : (_loadedCalTarget ?? Profile.calorieTarget),
        proteinTargetG: _isToday ? Profile.proteinTargetG : (_loadedProteinTarget ?? Profile.proteinTargetG),
        mealItems:     MealItem.encodeList(_items),
      );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final provider = context.read<GymProvider>();
    final entry = _formEntry();
    final result = await provider.saveEntry(entry);
    // Refresh the day's watch numbers too, so charts have the complete day
    await provider.syncWatchDay(entry.date);
    await _loadPastWatch();

    if (!mounted) return;
    setState(() {
      _saving = false;
      _dirty = false; // the form now matches what's saved, so keep it shown
      _hasSavedEntry = true;
    });

    final day = _isToday ? 'today' : DateFormat('EEE d MMM').format(_selectedDate);
    final detail = result.error != null ? '\n(${result.error})' : '';
    _snack(
      result.success
          ? '✅ Saved. Everything for $day is in your log'
          : '💾 Saved on your phone. It will sync when the server is reachable$detail',
      ok: result.success,
    );
  }

  void _snack(String msg, {bool ok = true}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: ok ? Colors.green.shade700 : Colors.orange.shade700,
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: ok ? 2 : 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  /// Save / unsaved indicator under the date picker.
  Widget _saveState() {
    final (icon, text, color) = _dirty
        ? (Icons.edit_note_rounded, 'Unsaved changes. Tap Save to keep them', Colors.amber)
        : _hasSavedEntry
            ? (Icons.check_circle_rounded, "Saved. This is what's in your log", Colors.greenAccent)
            : (Icons.radio_button_unchecked_rounded, 'Nothing saved for this day yet', Colors.white38);
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 4),
      child: Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 12))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // The day was saved somewhere else (workout finished, weigh-in): show it,
    // unless there are unsaved edits here.
    final rev = context.watch<GymProvider>().entryRevision;
    if (rev != _seenRevision) {
      _seenRevision = rev;
      if (_loaded && !_dirty && !_saving) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _loadDate(_selectedDate));
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Log'),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check_rounded),
            label: const Text('Save'),
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              onChanged: () => setState(() => _dirty = true), // also rebuilds total calories
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                children: [
                  // ── Date picker ────────────────────────────────────────
                  const SizedBox(height: 16),
                  _datePicker(context),
                  _saveState(),
                  const SizedBox(height: 24),

                  // ── Calories ───────────────────────────────────────────
                  _sectionHeader('🍽️ Calories & protein', context),
                  const SizedBox(height: 12),

                  _totalCalsCard(context),
                  const SizedBox(height: 12),

                  Row(children: [
                    Expanded(child: _calorieField('Breakfast', _breakfastCtrl, 'breakfast')),
                    const SizedBox(width: 10),
                    Expanded(child: _calorieField('Lunch', _lunchCtrl, 'lunch')),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _calorieField('Dinner', _dinnerCtrl, 'dinner')),
                    const SizedBox(width: 10),
                    Expanded(child: _calorieField('Snacks', _miscCtrl, 'misc')),
                  ]),
                  const SizedBox(height: 4),
                  const Text('📷 on a meal: snap your food and the AI estimates calories + protein',
                      style: TextStyle(color: Colors.white38, fontSize: 11)),
                  if (_items.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _itemsList(),
                  ],
                  const SizedBox(height: 10),
                  _numberField('Protein (g)', _proteinCtrl, Icons.egg_alt_rounded,
                      hint: 'Target ${Profile.proteinTargetG.toStringAsFixed(0)} g'),

                  const SizedBox(height: 24),

                  // ── Gym ────────────────────────────────────────────────
                  _sectionHeader('🏋️ Gym', context),
                  const SizedBox(height: 12),
                  _gymToggle(context),

                  const SizedBox(height: 24),

                  // ── Body metrics ───────────────────────────────────────
                  _sectionHeader('📏 Body Metrics', context),
                  const SizedBox(height: 12),

                  Row(children: [
                    Expanded(
                      child: _numberField(
                        'Weight (kg)', _weightCtrl,
                        Icons.monitor_weight_rounded,
                        hint: '78.5',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _numberField(
                        'Waist (cm)', _waistCtrl,
                        Icons.straighten_rounded,
                        hint: '85.0',
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  _scaleSection(context),

                  const SizedBox(height: 24),

                  // ── Wellness extras ────────────────────────────────────
                  _sectionHeader('😴 Wellness', context),
                  const SizedBox(height: 12),

                  Row(children: [
                    Expanded(
                      child: _numberField(
                        'Sleep (hrs)', _sleepCtrl,
                        Icons.bedtime_rounded,
                        hint: '7.5',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _numberField(
                        'Water (L)', _waterCtrl,
                        Icons.water_drop_rounded,
                        hint: '2.5',
                      ),
                    ),
                  ]),
                  const SizedBox(height: 16),

                  // ── Mood ───────────────────────────────────────────────
                  _moodSelector(context),

                  const SizedBox(height: 24),

                  // ── Galaxy Watch ───────────────────────────────────────
                  _sectionHeader('⌚ Galaxy Watch', context),
                  const SizedBox(height: 12),
                  WatchCard(
                    data: _isToday
                        ? context.watch<GymProvider>().todayWatch
                        : _pastWatch,
                    showSyncButton: true,
                    onSync: () async {
                      await context.read<GymProvider>().syncWatchData(force: true);
                      await _loadPastWatch();
                    },
                  ),

                  const SizedBox(height: 24),

                  // ── Notes ──────────────────────────────────────────────
                  _sectionHeader('📝 Notes', context),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _notesCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'How did today go?',
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),

                  const SizedBox(height: 32),

                  // ── Save button ────────────────────────────────────────
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save_rounded),
                    label:
                        Text(_saving ? 'Saving...' : 'Save Today\'s Log'),
                  ),
                ],
              ),
            ),
    );
  }

  // ── Vitafit scale ──────────────────────────────────────────────────────────

  Future<void> _weighIn() async {
    // Body composition needs height, age and sex: ask once before the first weigh-in
    if (!Profile.isComplete) {
      final saved = await showProfileDialog(context,
          latestWeightKg: context.read<GymProvider>().latestWeight?.weightKg);
      if (!mounted || !saved) return;
      context.read<GymProvider>().profileChanged();
    }
    final r = await showWeighInSheet(context);
    if (r == null || !mounted) return;
    setState(() {
      _weightCtrl.text = _trim(r.weightKg);
      _scale = (
        fat: r.bodyFatPct, water: r.waterPct, muscle: r.musclePct,
        bone: r.boneKg, bmr: r.bmrKcal, ohm: r.impedanceOhm,
      );
    });

    // Save the reading into the day straight away so it can't be lost.
    // Only the scale fields change; any other unsaved edits in the form stay
    // pending until Save, and the stored day keeps its other values.
    final provider = context.read<GymProvider>();
    final stored = await ApiService.getEntry(_dateKey);
    final merged = DailyEntry(
      date:          _dateKey,
      calBreakfast:  stored?.calBreakfast ?? 0,
      calLunch:      stored?.calLunch ?? 0,
      calDinner:     stored?.calDinner ?? 0,
      calMisc:       stored?.calMisc ?? 0,
      weightKg:      r.weightKg,
      waistCm:       stored?.waistCm,
      gymAttended:   stored?.gymAttended ?? false,
      sleepHours:    stored?.sleepHours,
      waterLitres:   stored?.waterLitres,
      moodScore:     stored?.moodScore,
      notes:         stored?.notes,
      proteinG:      stored?.proteinG,
      calorieTarget: stored?.calorieTarget ?? Profile.calorieTarget,
      proteinTargetG: stored?.proteinTargetG ?? Profile.proteinTargetG,
      mealItems:     stored?.mealItems,
      bodyFatPct:    r.bodyFatPct,
      waterPct:      r.waterPct,
      musclePct:     r.musclePct,
      boneKg:        r.boneKg,
      bmrKcal:       r.bmrKcal,
      impedanceOhm:  r.impedanceOhm,
    );
    final result = await provider.saveEntry(merged);
    if (!mounted) return;
    setState(() => _hasSavedEntry = true);
    _snack(
      result.success
          ? '⚖️ Weigh-in saved to your log'
          : '⚖️ Weigh-in saved on your phone. It will sync when the server is reachable',
      ok: result.success,
    );
  }

  /// Asks before switching days with unsaved edits.
  Future<bool> _confirmDiscard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Unsaved changes', style: TextStyle(color: Colors.white)),
        content: const Text(
            "You have changes for this day that aren't saved. Switch days and lose them?",
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep editing')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
        ],
      ),
    );
    return ok ?? false;
  }

  Widget _scaleSection(BuildContext context) {
    final s = _scale;
    String pct(double? v) => v == null ? '—' : '${v.toStringAsFixed(1)}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: _weighIn,
          icon: const Icon(Icons.bluetooth_searching_rounded, size: 18),
          label: Text(s == null ? 'Weigh in with Vitafit scale' : 'Weigh in again'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 46),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        if (s != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              Expanded(
                child: Wrap(spacing: 18, runSpacing: 8, children: [
                  _compStat('Body fat', pct(s.fat)),
                  _compStat('Water', pct(s.water)),
                  _compStat('Muscle', pct(s.muscle)),
                  if (s.bone != null) _compStat('Bone', '${s.bone!.toStringAsFixed(1)} kg'),
                  if (s.bmr != null) _compStat('BMR', '${s.bmr!.toStringAsFixed(0)} kcal'),
                ]),
              ),
              IconButton(
                tooltip: 'Remove scale reading',
                icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white38),
                onPressed: () => setState(() { _scale = null; _dirty = true; }),
              ),
            ]),
          ),
        ],
      ],
    );
  }

  Widget _compStat(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      );

  Widget _datePicker(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _selectedDate,
          firstDate: DateTime.now().subtract(const Duration(days: 365)),
          lastDate: DateTime.now(),
          builder: (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(
              colorScheme: ColorScheme.dark(
                primary: theme.colorScheme.primary,
              ),
            ),
            child: child!,
          ),
        );
        if (picked == null || DateUtils.isSameDay(picked, _selectedDate)) return;
        if (_dirty && !await _confirmDiscard()) return;
        _followToday = DateUtils.isSameDay(picked, DateTime.now());
        await _loadDate(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_rounded,
                color: Colors.white54, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white38),
          ],
        ),
      ),
    );
  }

  Widget _totalCalsCard(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Theme.of(context).colorScheme.primary.withOpacity(0.3),
              const Color(0xFF1A1A2E),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Icon(Icons.local_fire_department_rounded,
                color: Color(0xFFFF6B35), size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Total Calories',
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                  Text(
                    _calTarget == null
                        ? '${_totalCalories.toStringAsFixed(0)} kcal'
                        : '${_totalCalories.toStringAsFixed(0)} / ${_calTarget!.toStringAsFixed(0)} kcal',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  _targetLine(),
                ],
              ),
            ),
          ],
        ),
      );

  double? get _calTarget =>
      _isToday ? Profile.calorieTarget : (_loadedCalTarget ?? Profile.calorieTarget);

  /// "450 under target ✅" / "200 over target" / set-a-target hint, + protein.
  Widget _targetLine() {
    final target = _calTarget;
    final protein = _parse(_proteinCtrl.text);
    final proteinText = protein == null
        ? ''
        : '  ·  ${protein.toStringAsFixed(0)} / ${Profile.proteinTargetG.toStringAsFixed(0)} g protein';
    if (target == null) {
      return Text('Set a daily calorie target in Profile (Home)$proteinText',
          style: const TextStyle(color: Colors.white38, fontSize: 12));
    }
    if (_totalCalories <= 0) {
      return Text('Target ${target.toStringAsFixed(0)} kcal$proteinText',
          style: const TextStyle(color: Colors.white54, fontSize: 12));
    }
    final diff = target - _totalCalories;
    final under = diff >= 0;
    return Text(
      '${under ? '✅' : '⚠️'} ${diff.abs().toStringAsFixed(0)} ${under ? 'under' : 'over'} target$proteinText',
      style: TextStyle(
          color: under ? Colors.greenAccent : Colors.orangeAccent,
          fontSize: 12,
          fontWeight: FontWeight.w600),
    );
  }

  // ── Food photos ────────────────────────────────────────────────────────────

  TextEditingController _mealCtrl(String meal) => switch (meal) {
        'breakfast' => _breakfastCtrl,
        'lunch' => _lunchCtrl,
        'dinner' => _dinnerCtrl,
        _ => _miscCtrl,
      };

  void _addTo(TextEditingController ctrl, double delta) {
    final v = (_parse(ctrl.text) ?? 0) + delta;
    ctrl.text = v <= 0 ? '' : _trim(v);
  }

  /// Photo → estimate → added on top of what's already in that meal, then the
  /// whole day is saved so the estimate can't be lost.
  Future<void> _addPhoto(String meal) async {
    final added = await addFoodFromPhoto(context, meal);
    if (added == null || added.isEmpty || !mounted) return;
    setState(() {
      for (final item in added) {
        _addTo(_mealCtrl(item.meal), item.kcal);
        _addTo(_proteinCtrl, item.proteinG);
      }
      _items = [..._items, ...added];
    });
    await _save();
  }

  void _removeItem(MealItem item) {
    setState(() {
      _addTo(_mealCtrl(item.meal), -item.kcal);
      _addTo(_proteinCtrl, -item.proteinG);
      _items = [..._items]..remove(item);
      _dirty = true;
    });
  }

  Widget _itemsList() => Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final meal in mealLabels.keys)
              if (_items.any((i) => i.meal == meal)) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 2),
                  child: Text('📷 ${mealLabels[meal]}',
                      style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
                for (final item in _items.where((i) => i.meal == meal))
                  Row(children: [
                    Expanded(
                      child: Text(
                        '${item.name}${item.portion.isEmpty ? '' : ' (${item.portion})'}',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text('${item.kcal.toStringAsFixed(0)} kcal · ${item.proteinG.toStringAsFixed(0)} g',
                        style: const TextStyle(color: Colors.white, fontSize: 12)),
                    IconButton(
                      tooltip: 'Remove (takes it off the meal)',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_rounded, size: 16, color: Colors.white38),
                      onPressed: () => _removeItem(item),
                    ),
                  ]),
              ],
          ],
        ),
      );

  Widget _gymToggle(BuildContext context) => GestureDetector(
        onTap: () => setState(() { _gymAttended = !_gymAttended; _dirty = true; }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: _gymAttended
                ? Colors.greenAccent.withOpacity(0.15)
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _gymAttended
                  ? Colors.greenAccent.withOpacity(0.5)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.fitness_center_rounded,
                color: _gymAttended ? Colors.greenAccent : Colors.white38,
                size: 26,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  _gymAttended
                      ? 'Gym attended today! 💪'
                      : 'Did you go to the gym?',
                  style: TextStyle(
                    color: _gymAttended ? Colors.greenAccent : Colors.white60,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Switch(
                value: _gymAttended,
                onChanged: (v) => setState(() { _gymAttended = v; _dirty = true; }),
                activeColor: Colors.greenAccent,
              ),
            ],
          ),
        ),
      );

  Widget _moodSelector(BuildContext context) {
    const moods = ['😢', '😕', '😐', '😊', '🤩'];
    const labels = ['Rough', 'Meh', 'Okay', 'Good', 'Amazing'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Mood',
            style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1)),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(5, (i) {
            final score = i + 1;
            final selected = _moodScore == score;
            return GestureDetector(
              onTap: () => setState(
                  () { _moodScore = selected ? null : score; _dirty = true; }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.amber.withOpacity(0.2)
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: selected
                          ? Colors.amber
                          : Colors.transparent),
                ),
                child: Column(
                  children: [
                    Text(moods[i],
                        style: TextStyle(
                            fontSize: selected ? 28 : 22)),
                    const SizedBox(height: 2),
                    Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 9,
                        color: selected ? Colors.amber : Colors.white38,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _calorieField(String label, TextEditingController ctrl, String meal) =>
      TextFormField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: '$label kcal',
          suffixIcon: IconButton(
            tooltip: 'Add from a photo',
            icon: const Icon(Icons.photo_camera_rounded, size: 20, color: Color(0xFFFF6B35)),
            onPressed: () => _addPhoto(meal),
          ),
        ),
        style: const TextStyle(color: Colors.white),
        validator: (v) {
          if (v != null && v.isNotEmpty && double.tryParse(v) == null) {
            return 'Invalid';
          }
          return null;
        },
      );

  Widget _numberField(
    String label,
    TextEditingController ctrl,
    IconData icon, {
    String? hint,
  }) =>
      TextFormField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, size: 18, color: Colors.white38),
        ),
        style: const TextStyle(color: Colors.white),
        validator: (v) {
          if (v != null && v.isNotEmpty && double.tryParse(v) == null) {
            return 'Invalid';
          }
          return null;
        },
      );

  Widget _sectionHeader(String title, BuildContext context) => Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      );
}
