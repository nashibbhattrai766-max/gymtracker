import 'package:shared_preferences/shared_preferences.dart';

/// Personal details for body-composition formulas, BMI, the goal card and
/// greetings. Entered in the app (Home → Profile) and stored only on the
/// phone. Nothing personal lives in the source code.
class Profile {
  static const _kName = 'profile_name';
  static const _kHeight = 'profile_height_cm';
  static const _kBirth = 'profile_birth_date';
  static const _kMale = 'profile_is_male';
  static const _kTarget = 'profile_target_kg';
  static const _kCalories = 'profile_calorie_target';
  static const _kProtein = 'profile_protein_target_g';

  static String name = '';
  static double? heightCm;
  static DateTime? birthDate;
  static bool isMale = true;
  static double? targetWeightKg;
  static double? calorieTarget;          // kcal per day
  static double proteinTargetG = 120;     // g per day

  /// Height and birth date are needed for body composition.
  static bool get isComplete => heightCm != null && birthDate != null;

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    name = p.getString(_kName) ?? '';
    heightCm = p.getDouble(_kHeight);
    final birth = p.getString(_kBirth);
    birthDate = birth == null ? null : DateTime.tryParse(birth);
    isMale = p.getBool(_kMale) ?? true;
    targetWeightKg = p.getDouble(_kTarget);
    calorieTarget = p.getDouble(_kCalories);
    proteinTargetG = p.getDouble(_kProtein) ?? 120;
  }

  static Future<void> save({
    required String name,
    required double? heightCm,
    required DateTime? birthDate,
    required bool isMale,
    required double? targetWeightKg,
    double? calorieTarget,
    double proteinTargetG = 120,
  }) async {
    Profile.calorieTarget = calorieTarget;
    Profile.proteinTargetG = proteinTargetG;
    Profile.name = name.trim();
    Profile.heightCm = heightCm;
    Profile.birthDate = birthDate;
    Profile.isMale = isMale;
    Profile.targetWeightKg = targetWeightKg;

    final p = await SharedPreferences.getInstance();
    await p.setString(_kName, Profile.name);
    await p.setBool(_kMale, isMale);
    heightCm == null ? await p.remove(_kHeight) : await p.setDouble(_kHeight, heightCm);
    calorieTarget == null ? await p.remove(_kCalories) : await p.setDouble(_kCalories, calorieTarget);
    await p.setDouble(_kProtein, proteinTargetG);
    targetWeightKg == null ? await p.remove(_kTarget) : await p.setDouble(_kTarget, targetWeightKg);
    birthDate == null
        ? await p.remove(_kBirth)
        : await p.setString(_kBirth, birthDate.toIso8601String().substring(0, 10));
  }

  /// "Hey <name>!" or "Hey there!"
  static String get greeting => name.isEmpty ? 'Hey there!' : 'Hey $name!';

  /// Age in whole years on [on] (defaults to today); null until a birth date is set.
  static int? ageOn([DateTime? on]) {
    final b = birthDate;
    if (b == null) return null;
    final d = on ?? DateTime.now();
    var age = d.year - b.year;
    if (d.month < b.month || (d.month == b.month && d.day < b.day)) age--;
    return age;
  }
}

/// Suggested daily calories for steady fat loss (~0.5 kg a week):
/// BMR (Mifflin-St Jeor) × 1.55 for 5 gym days a week, minus 500 kcal,
/// rounded to the nearest 50 and never below a safe floor.
double? suggestedCalorieTarget(double? weightKg, {double? heightCm, int? age, bool? isMale}) {
  final h = heightCm ?? Profile.heightCm;
  final a = age ?? Profile.ageOn();
  final male = isMale ?? Profile.isMale;
  if (weightKg == null || h == null || a == null) return null;
  final bmr = 10 * weightKg + 6.25 * h - 5 * a + (male ? 5 : -161);
  final target = ((bmr * 1.55 - 500) / 50).round() * 50.0;
  final floor = male ? 1500.0 : 1200.0;
  return target < floor ? floor : target;
}
