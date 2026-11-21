import '../config/profile.dart';

/// Body composition from a smart-scale reading (weight + whole-body impedance).
///
/// Same science-based formulas openScale uses for impedance scales
/// (StandardImpedanceLib), so readings line up with openScale:
///  - Fat-free mass & total body water: Sun SS et al. (2003)
///  - Skeletal muscle mass: Janssen et al.
///  - BMR: Mifflin-St Jeor (what openScale shows on its overview)
///
/// Absolute values from consumer scales are approximate — the trend over
/// weeks is what matters. Weigh at the same time of day, not right after a
/// workout or a big meal.
class BodyComposition {
  final double weightKg;
  final int? impedanceOhm;
  final double bmi;
  final double bmrKcal;
  final double? bodyFatPct;
  final double? waterPct;
  final double? musclePct;
  final double? boneKg;

  const BodyComposition._({
    required this.weightKg,
    required this.impedanceOhm,
    required this.bmi,
    required this.bmrKcal,
    this.bodyFatPct,
    this.waterPct,
    this.musclePct,
    this.boneKg,
  });

  factory BodyComposition.calculate({
    required double weightKg,
    int? impedanceOhm,
    double? heightCm,
    int? age,
    bool? isMale,
  }) {
    // Callers check Profile.isComplete first (the Log screen asks for the profile)
    final h = heightCm ?? Profile.heightCm!;
    final a = age ?? Profile.ageOn()!;
    final male = isMale ?? Profile.isMale;
    final hM = h / 100;
    final bmi = weightKg / (hM * hM);
    final bmr = 10 * weightKg + 6.25 * h - 5 * a + (male ? 5 : -161);

    // The formulas only hold for a sane whole-body impedance
    final z = impedanceOhm;
    if (z == null || z <= 0 || z >= 1500) {
      return BodyComposition._(
          weightKg: weightKg, impedanceOhm: z, bmi: bmi, bmrKcal: bmr);
    }

    final h2r = h * h / z;
    final ffm = male
        ? -10.68 + 0.65 * h2r + 0.26 * weightKg + 0.02 * z
        : -9.53 + 0.69 * h2r + 0.17 * weightKg + 0.02 * z;
    final tbwLitres = male
        ? 1.2 + 0.45 * h2r + 0.18 * weightKg
        : 3.75 + 0.45 * h2r + 0.11 * weightKg;
    final smm = 0.401 * h2r + 3.825 * (male ? 1 : 0) - 0.071 * a + 5.102;

    return BodyComposition._(
      weightKg: weightKg,
      impedanceOhm: z,
      bmi: bmi,
      bmrKcal: bmr,
      bodyFatPct: (1 - ffm / weightKg) * 100,
      waterPct: 0.99513 * tbwLitres / weightKg * 100,
      musclePct: smm / weightKg * 100,
      boneKg: (male ? 0.057 : 0.05) * ffm,
    );
  }
}

/// Numbers derived from a stored reading (weight + body fat/water/bone + waist).
/// Same relationships the Vitafit app uses — e.g. its 89.90 kg reading with
/// 32.5 % fat, 45.7 % water and 3.06 kg bone gives muscle 64.1 %, protein 18.4 %.
class BodyStats {
  static double? bmi(double? weightKg) {
    final cm = Profile.heightCm;
    if (weightKg == null || cm == null) return null;
    final h = cm / 100;
    return weightKg / (h * h);
  }

  static double? fatMassKg(double? weightKg, double? fatPct) =>
      weightKg == null || fatPct == null ? null : weightKg * fatPct / 100;

  /// Fat-free ("lean") mass: everything that isn't fat — muscle, water, bone, organs.
  static double? leanMassKg(double? weightKg, double? fatPct) {
    final fat = fatMassKg(weightKg, fatPct);
    return fat == null ? null : weightKg! - fat;
  }

  /// Total muscle mass (incl. its water) as % of weight = lean mass − bone.
  static double? muscleMassPct(double? weightKg, double? fatPct, double? boneKg) {
    final lean = leanMassKg(weightKg, fatPct);
    if (lean == null || boneKg == null) return null;
    return (lean - boneKg) / weightKg! * 100;
  }

  /// Protein % = lean mass − water − bone, as % of weight.
  static double? proteinPct(double? weightKg, double? fatPct, double? waterPct, double? boneKg) {
    final lean = leanMassKg(weightKg, fatPct);
    if (lean == null || waterPct == null || boneKg == null) return null;
    return (lean - weightKg! * waterPct / 100 - boneKg) / weightKg * 100;
  }

  /// Waist-to-height ratio — a well-validated indicator of belly (visceral) fat.
  static double? waistToHeight(double? waistCm) {
    final cm = Profile.heightCm;
    return waistCm == null || cm == null ? null : waistCm / cm;
  }

  /// Standard cut-offs: < 0.5 healthy, 0.5–0.6 increased risk, ≥ 0.6 high risk.
  static String whtrLabel(double ratio) =>
      ratio < 0.5 ? 'Healthy' : ratio < 0.6 ? 'Increased risk' : 'High risk';

  /// 0 → 1 progress from [startKg] toward [targetKg].
  static double goalProgress(double startKg, double currentKg, double targetKg) {
    final span = startKg - targetKg;
    if (span <= 0) return currentKg <= targetKg ? 1 : 0;
    return ((startKg - currentKg) / span).clamp(0.0, 1.0);
  }
}
