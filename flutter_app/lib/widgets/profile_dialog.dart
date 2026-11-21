import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/profile.dart';

/// Edit the personal profile (name, height, birth date, sex, target weight).
/// Returns true if saved.
/// [latestWeightKg] lets the dialog suggest a calorie target.
Future<bool> showProfileDialog(BuildContext context, {double? latestWeightKg}) async =>
    await showDialog<bool>(
        context: context, builder: (_) => _ProfileDialog(latestWeightKg: latestWeightKg)) ??
    false;

class _ProfileDialog extends StatefulWidget {
  final double? latestWeightKg;
  const _ProfileDialog({this.latestWeightKg});
  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: Profile.name);
  late final _height = TextEditingController(text: _fmt(Profile.heightCm));
  late final _target = TextEditingController(text: _fmt(Profile.targetWeightKg));
  late final _calories = TextEditingController(text: _fmt(Profile.calorieTarget));
  late final _protein = TextEditingController(text: _fmt(Profile.proteinTargetG));
  late DateTime? _birth = Profile.birthDate;
  late bool _male = Profile.isMale;

  static String _fmt(double? v) =>
      v == null ? '' : (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString());

  @override
  void dispose() {
    _name.dispose();
    _height.dispose();
    _target.dispose();
    _calories.dispose();
    _protein.dispose();
    super.dispose();
  }

  String? _number(String? v, {required double min, required double max, bool required = false}) {
    if (v == null || v.trim().isEmpty) return required ? 'Required' : null;
    final n = double.tryParse(v.trim());
    if (n == null || n < min || n > max) return 'Enter ${min.toStringAsFixed(0)}–${max.toStringAsFixed(0)}';
    return null;
  }

  Future<void> _pickBirth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _birth ?? DateTime(DateTime.now().year - 30),
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null) setState(() => _birth = picked);
  }

  void _suggestCalories() {
    final h = double.tryParse(_height.text.trim());
    final b = _birth;
    final now = DateTime.now();
    final age = b == null
        ? null
        : now.year - b.year - ((now.month < b.month || (now.month == b.month && now.day < b.day)) ? 1 : 0);
    final kcal = suggestedCalorieTarget(widget.latestWeightKg, heightCm: h, age: age, isMale: _male);
    if (kcal == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(widget.latestWeightKg == null
            ? 'Log your weight first, then tap Suggest'
            : 'Fill in height and date of birth first'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() => _calories.text = kcal.toStringAsFixed(0));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_birth == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pick your date of birth'), behavior: SnackBarBehavior.floating));
      return;
    }
    await Profile.save(
      name: _name.text,
      heightCm: double.parse(_height.text.trim()),
      birthDate: _birth,
      isMale: _male,
      targetWeightKg: _target.text.trim().isEmpty ? null : double.parse(_target.text.trim()),
      calorieTarget: _calories.text.trim().isEmpty ? null : double.parse(_calories.text.trim()),
      proteinTargetG: _protein.text.trim().isEmpty ? 120 : double.parse(_protein.text.trim()),
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A2E),
      title: const Text('Profile', style: TextStyle(color: Colors.white)),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Used for body composition, BMI, your goal and greetings. Stored only on this phone.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
                style: const TextStyle(color: Colors.white),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _height,
                decoration: const InputDecoration(labelText: 'Height', suffixText: 'cm'),
                style: const TextStyle(color: Colors.white),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) => _number(v, min: 100, max: 250, required: true),
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: _pickBirth,
                borderRadius: BorderRadius.circular(14),
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Date of birth'),
                  child: Text(
                    _birth == null ? 'Tap to choose' : DateFormat('d MMM yyyy').format(_birth!),
                    style: TextStyle(color: _birth == null ? Colors.white38 : Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Male')),
                  ButtonSegment(value: false, label: Text('Female')),
                ],
                selected: {_male},
                onSelectionChanged: (s) => setState(() => _male = s.first),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Body-composition formulas differ by sex',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _target,
                decoration: const InputDecoration(labelText: 'Target weight (optional)', suffixText: 'kg'),
                style: const TextStyle(color: Colors.white),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) => _number(v, min: 30, max: 300),
              ),
              const SizedBox(height: 10),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: TextFormField(
                    controller: _calories,
                    decoration: const InputDecoration(labelText: 'Daily calories', suffixText: 'kcal'),
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.number,
                    validator: (v) => _number(v, min: 1000, max: 6000),
                  ),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: TextButton(onPressed: _suggestCalories, child: const Text('Suggest')),
                ),
              ]),
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('For weight loss: about 500 kcal under what you burn (~0.5 kg a week)',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _protein,
                decoration: const InputDecoration(labelText: 'Daily protein', suffixText: 'g'),
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.number,
                validator: (v) => _number(v, min: 30, max: 400),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(minimumSize: const Size(88, 40)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
