import 'dart:convert';

/// One food item added to a meal from a photo estimate (or by hand in the
/// review sheet). The meal's calorie field already includes it; the list is
/// kept so you can see where the numbers came from and remove a wrong one.
class MealItem {
  final String meal; // breakfast / lunch / dinner / misc
  final String name;
  final String portion;
  final double kcal;
  final double proteinG;

  const MealItem({
    required this.meal,
    required this.name,
    this.portion = '',
    required this.kcal,
    required this.proteinG,
  });

  Map<String, dynamic> toJson() =>
      {'meal': meal, 'name': name, 'portion': portion, 'kcal': kcal, 'protein_g': proteinG};

  factory MealItem.fromJson(Map<String, dynamic> j) => MealItem(
        meal: j['meal'] ?? 'misc',
        name: j['name'] ?? 'Food',
        portion: j['portion'] ?? '',
        kcal: (j['kcal'] as num?)?.toDouble() ?? 0,
        proteinG: (j['protein_g'] as num?)?.toDouble() ?? 0,
      );

  static List<MealItem> decodeList(String? json) {
    if (json == null || json.isEmpty) return [];
    try {
      return (jsonDecode(json) as List)
          .map((e) => MealItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static String? encodeList(List<MealItem> items) =>
      items.isEmpty ? null : jsonEncode(items.map((e) => e.toJson()).toList());
}

class DailyEntry {
  final int? id;
  final String date;
  final double calBreakfast;
  final double calLunch;
  final double calDinner;
  final double calMisc;
  final double? weightKg;
  final double? waistCm;
  // Body composition from the Vitafit scale
  final double? bodyFatPct;
  final double? waterPct;
  final double? musclePct;
  final double? boneKg;
  final double? bmrKcal;
  final int? impedanceOhm;
  // Nutrition: protein eaten, the targets in force that day, photo food items
  final double? proteinG;
  final double? calorieTarget;
  final double? proteinTargetG;
  final String? mealItems; // JSON list of MealItem
  final bool gymAttended;
  final double? sleepHours;
  final double? waterLitres;
  final int? moodScore;
  final String? notes;

  DailyEntry({
    this.id,
    required this.date,
    this.calBreakfast = 0,
    this.calLunch = 0,
    this.calDinner = 0,
    this.calMisc = 0,
    this.weightKg,
    this.waistCm,
    this.bodyFatPct,
    this.waterPct,
    this.musclePct,
    this.boneKg,
    this.bmrKcal,
    this.impedanceOhm,
    this.proteinG,
    this.calorieTarget,
    this.proteinTargetG,
    this.mealItems,
    this.gymAttended = false,
    this.sleepHours,
    this.waterLitres,
    this.moodScore,
    this.notes,
  });

  double get totalCalories =>
      calBreakfast + calLunch + calDinner + calMisc;

  List<MealItem> get items => MealItem.decodeList(mealItems);

  /// Positive = under the target (a deficit), negative = over.
  double? get caloriesUnderTarget =>
      calorieTarget == null || totalCalories <= 0 ? null : calorieTarget! - totalCalories;

  factory DailyEntry.fromJson(Map<String, dynamic> j) => DailyEntry(
        id:             j['id'],
        date:           j['date'],
        calBreakfast:   (j['cal_breakfast'] ?? 0).toDouble(),
        calLunch:       (j['cal_lunch']     ?? 0).toDouble(),
        calDinner:      (j['cal_dinner']    ?? 0).toDouble(),
        calMisc:        (j['cal_misc']      ?? 0).toDouble(),
        weightKg:       j['weight_kg']?.toDouble(),
        waistCm:        j['waist_cm']?.toDouble(),
        bodyFatPct:     j['body_fat_pct']?.toDouble(),
        waterPct:       j['water_pct']?.toDouble(),
        musclePct:      j['muscle_pct']?.toDouble(),
        boneKg:         j['bone_kg']?.toDouble(),
        bmrKcal:        j['bmr_kcal']?.toDouble(),
        impedanceOhm:   j['impedance_ohm']?.toInt(),
        proteinG:       j['protein_g']?.toDouble(),
        calorieTarget:  j['calorie_target']?.toDouble(),
        proteinTargetG: j['protein_target_g']?.toDouble(),
        mealItems:      j['meal_items'],
        gymAttended:    j['gym_attended'] ?? false,
        sleepHours:     j['sleep_hours']?.toDouble(),
        waterLitres:    j['water_litres']?.toDouble(),
        moodScore:      j['mood_score'],
        notes:          j['notes'],
      );

  Map<String, dynamic> toJson() => {
        'date':             date,
        'cal_breakfast':    calBreakfast,
        'cal_lunch':        calLunch,
        'cal_dinner':       calDinner,
        'cal_misc':         calMisc,
        'weight_kg':        weightKg,
        'waist_cm':         waistCm,
        'body_fat_pct':     bodyFatPct,
        'water_pct':        waterPct,
        'muscle_pct':       musclePct,
        'bone_kg':          boneKg,
        'bmr_kcal':         bmrKcal,
        'impedance_ohm':    impedanceOhm,
        'protein_g':        proteinG,
        'calorie_target':   calorieTarget,
        'protein_target_g': proteinTargetG,
        'meal_items':       mealItems,
        'gym_attended':     gymAttended,
        'sleep_hours':      sleepHours,
        'water_litres':     waterLitres,
        'mood_score':       moodScore,
        'notes':            notes,
      };

  // sqflite serialisation (booleans stored as int)
  Map<String, dynamic> toDb() => {
        ...toJson(),
        'gym_attended': gymAttended ? 1 : 0,
        'synced':       0,
      };

  factory DailyEntry.fromDb(Map<String, dynamic> m) => DailyEntry.fromJson({
        ...m,
        'gym_attended': (m['gym_attended'] ?? 0) == 1,
      });

  DailyEntry copyWith({
    String? date,
    double? calBreakfast,
    double? calLunch,
    double? calDinner,
    double? calMisc,
    double? weightKg,
    double? waistCm,
    bool? gymAttended,
    double? sleepHours,
    double? waterLitres,
    int? moodScore,
    String? notes,
    double? bodyFatPct,
    double? waterPct,
    double? musclePct,
    double? boneKg,
    double? bmrKcal,
    int? impedanceOhm,
    double? proteinG,
    double? calorieTarget,
    double? proteinTargetG,
    String? mealItems,
  }) =>
      DailyEntry(
        id:             id,
        date:           date           ?? this.date,
        calBreakfast:   calBreakfast   ?? this.calBreakfast,
        calLunch:       calLunch       ?? this.calLunch,
        calDinner:      calDinner      ?? this.calDinner,
        calMisc:        calMisc        ?? this.calMisc,
        weightKg:       weightKg       ?? this.weightKg,
        waistCm:        waistCm        ?? this.waistCm,
        bodyFatPct:     bodyFatPct     ?? this.bodyFatPct,
        waterPct:       waterPct       ?? this.waterPct,
        musclePct:      musclePct      ?? this.musclePct,
        boneKg:         boneKg         ?? this.boneKg,
        bmrKcal:        bmrKcal        ?? this.bmrKcal,
        impedanceOhm:   impedanceOhm   ?? this.impedanceOhm,
        proteinG:       proteinG       ?? this.proteinG,
        calorieTarget:  calorieTarget  ?? this.calorieTarget,
        proteinTargetG: proteinTargetG ?? this.proteinTargetG,
        mealItems:      mealItems      ?? this.mealItems,
        gymAttended:    gymAttended    ?? this.gymAttended,
        sleepHours:     sleepHours     ?? this.sleepHours,
        waterLitres:    waterLitres    ?? this.waterLitres,
        moodScore:      moodScore      ?? this.moodScore,
        notes:          notes          ?? this.notes,
      );
}
