import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/entry.dart';
import '../services/food_service.dart';

const mealLabels = {
  'breakfast': 'Breakfast',
  'lunch': 'Lunch',
  'dinner': 'Dinner',
  'misc': 'Misc / snacks',
};

/// 📷 → camera or gallery → AI estimate → review/edit → returns the items to
/// add (all for one meal), or null if cancelled.
Future<List<MealItem>?> addFoodFromPhoto(BuildContext context, String meal) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: const Color(0xFF1A1A2E),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('📷 ${mealLabels[meal]} photo',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 4),
          const Text('Tip: include a fork or your hand for scale',
              style: TextStyle(color: Colors.white38, fontSize: 12)),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.photo_camera_rounded, color: Colors.white70),
            title: const Text('Take a photo', style: TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_rounded, color: Colors.white70),
            title: const Text('Choose from gallery', style: TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ]),
      ),
    ),
  );
  if (source == null || !context.mounted) return null;

  // Shrunk on the phone so it uploads fast (~200–400 KB)
  final photo = await ImagePicker().pickImage(
    source: source,
    maxWidth: 1280,
    maxHeight: 1280,
    imageQuality: 80,
  );
  if (photo == null || !context.mounted) return null;
  final bytes = await photo.readAsBytes();
  if (!context.mounted) return null;

  return showModalBottomSheet<List<MealItem>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1A1A2E),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => FoodReviewSheet(bytes: bytes, meal: meal),
  );
}

class FoodReviewSheet extends StatefulWidget {
  final List<int> bytes;
  final String meal;
  /// For tests: skip the network call and review these items.
  final FoodEstimate? preset;
  const FoodReviewSheet({super.key, required this.bytes, required this.meal, this.preset});

  @override
  State<FoodReviewSheet> createState() => _FoodReviewSheetState();
}

class _FoodReviewSheetState extends State<FoodReviewSheet> {
  late String _meal = widget.meal;
  FoodEstimate? _estimate;
  String? _error;
  int _version = 0; // bumps when items are added/removed so fields rebuild

  @override
  void initState() {
    super.initState();
    if (widget.preset != null) {
      _estimate = widget.preset;
    } else {
      _analyse();
    }
  }

  Future<void> _analyse() async {
    setState(() {
      _error = null;
      _estimate = null;
    });
    try {
      final e = await FoodService.analyse(widget.bytes, meal: _meal);
      if (mounted) setState(() => _estimate = e);
    } catch (e) {
      if (mounted) {
        setState(() => _error = '${e.toString().replaceFirst('Exception: ', '')}\n'
            'Check you\'re connected to the VPN.');
      }
    }
  }

  double get _kcal => _estimate?.items.fold<double>(0, (t, i) => t + i.kcal) ?? 0;
  double get _protein => _estimate?.items.fold<double>(0, (t, i) => t + i.proteinG) ?? 0;

  @override
  Widget build(BuildContext context) {
    final e = _estimate;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  const Text('🍽️  Food estimate',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  DropdownButton<String>(
                    value: _meal,
                    dropdownColor: const Color(0xFF22223A),
                    underline: const SizedBox(),
                    items: [
                      for (final m in mealLabels.entries)
                        DropdownMenuItem(
                            value: m.key,
                            child: Text(m.value, style: const TextStyle(color: Colors.white))),
                    ],
                    onChanged: (v) => setState(() => _meal = v ?? _meal),
                  ),
                ]),
                const SizedBox(height: 12),
                if (_error != null) ...[
                  Text('⚠️ $_error', style: const TextStyle(color: Colors.orangeAccent, height: 1.4)),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: _analyse, child: const Text('Try again')),
                ] else if (e == null) ...[
                  const SizedBox(height: 24),
                  const Center(child: CircularProgressIndicator()),
                  const SizedBox(height: 12),
                  const Center(
                    child: Text('Analysing your photo…', style: TextStyle(color: Colors.white60)),
                  ),
                  const SizedBox(height: 24),
                ] else ...[
                  if (e.note.isNotEmpty || e.confidence == 'low')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        '${e.confidence == 'low' ? 'Low confidence. Please check the portions. ' : ''}${e.note}',
                        style: const TextStyle(color: Colors.amber, fontSize: 12, height: 1.4),
                      ),
                    ),
                  if (e.items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text('No food items. Add one below.',
                          style: TextStyle(color: Colors.white54)),
                    ),
                  for (var i = 0; i < e.items.length; i++) _itemRow(e.items[i], i),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() {
                        e.items.add(FoodEstimateItem(name: '', kcal: 0, proteinG: 0));
                        _version++;
                      }),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add item'),
                    ),
                  ),
                  const Divider(color: Colors.white12),
                  Row(children: [
                    const Text('Total', style: TextStyle(color: Colors.white70)),
                    const Spacer(),
                    Text('${_kcal.round()} kcal · ${_protein.toStringAsFixed(0)} g protein',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                  ]),
                  const SizedBox(height: 4),
                  const Text('Estimates from a photo are roughly ±20–30%. Adjust portions if you know better.',
                      style: TextStyle(color: Colors.white38, fontSize: 11)),
                  const SizedBox(height: 14),
                  ElevatedButton(
                    onPressed: e.items.isEmpty
                        ? null
                        : () => Navigator.pop(context, [
                              for (final i in e.items)
                                if (i.kcal > 0 || i.proteinG > 0)
                                  MealItem(
                                    meal: _meal,
                                    name: i.name.trim().isEmpty ? 'Food' : i.name.trim(),
                                    portion: i.portion,
                                    kcal: i.kcal.roundToDouble(),
                                    proteinG: double.parse(i.proteinG.toStringAsFixed(1)),
                                  ),
                            ]),
                    child: Text('Add to ${mealLabels[_meal]}'),
                  ),
                ],
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _itemRow(FoodEstimateItem item, int i) {
    final k = '$_version-$i';
    InputDecoration deco(String label, [String? suffix]) => InputDecoration(
          isDense: true,
          labelText: label,
          suffixText: suffix,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: TextFormField(
              key: ValueKey('$k-name'),
              initialValue: item.name,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: deco(item.portion.isEmpty ? 'Food' : 'Food · ${item.portion}'),
              onChanged: (v) => item.name = v,
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.close_rounded, color: Colors.white38, size: 20),
            onPressed: () => setState(() {
              _estimate!.items.removeAt(i);
              _version++;
            }),
          ),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: TextFormField(
              key: ValueKey('$k-kcal'),
              initialValue: item.kcal.round().toString(),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              keyboardType: TextInputType.number,
              decoration: deco('Calories', 'kcal'),
              onChanged: (v) => setState(() => item.kcal = double.tryParse(v) ?? 0),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              key: ValueKey('$k-protein'),
              initialValue: item.proteinG.toStringAsFixed(item.proteinG % 1 == 0 ? 0 : 1),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: deco('Protein', 'g'),
              onChanged: (v) => setState(() => item.proteinG = double.tryParse(v) ?? 0),
            ),
          ),
          const SizedBox(width: 48),
        ]),
      ]),
    );
  }
}
