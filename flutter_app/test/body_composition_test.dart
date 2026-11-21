import 'package:flutter_test/flutter_test.dart';
import 'package:gymtracker/config/profile.dart';
import 'package:gymtracker/services/body_composition.dart';

void main() {
  setUp(() {
    // Example profile (the real one is entered in the app, never in code)
    Profile.heightCm = 170;
    Profile.birthDate = DateTime(1990, 6, 15);
    Profile.isMale = true;
    Profile.targetWeightKg = 70;
  });

  test('matches openScale reference values (92.75 kg, 165 cm, male, 27, ~461 Ω)', () {
    // openScale showed BMI 34.1, fat 34.2 %, water 47.7 %, muscle 33.1 %,
    // BMR 1829 kcal for this reading and profile.
    final c = BodyComposition.calculate(
        weightKg: 92.75, impedanceOhm: 461, heightCm: 165, age: 27, isMale: true);
    expect(c.bmi, closeTo(34.1, 0.05));
    expect(c.bodyFatPct!, closeTo(34.2, 0.15));
    expect(c.waterPct!, closeTo(47.7, 0.15));
    expect(c.musclePct!, closeTo(33.1, 0.15));
    expect(c.bmrKcal, closeTo(1829, 1));
  });

  test('weight-only reading still gives BMI and BMR (uses the saved profile)', () {
    final c = BodyComposition.calculate(weightKg: 90);
    expect(c.bmi, closeTo(31.1, 0.05));
    expect(c.bodyFatPct, isNull);
  });

  test('derived stats match the Vitafit app (89.90 kg, 32.5 % fat, 45.7 % water, 3.06 kg bone)', () {
    expect(BodyStats.leanMassKg(89.90, 32.5)!, closeTo(60.72, 0.1));
    expect(BodyStats.muscleMassPct(89.90, 32.5, 3.06)!, closeTo(64.1, 0.1));
    expect(BodyStats.proteinPct(89.90, 32.5, 45.7, 3.06)!, closeTo(18.4, 0.1));
    expect(BodyStats.waistToHeight(85)!, closeTo(0.5, 0.001));
    expect(BodyStats.whtrLabel(0.49), 'Healthy');
    expect(BodyStats.whtrLabel(0.55), 'Increased risk');
    expect(BodyStats.goalProgress(90, 77.5, 65), closeTo(0.5, 0.001));
  });

  test('age from birth date, and no age until one is set', () {
    expect(Profile.ageOn(DateTime(2026, 6, 14)), 35);
    expect(Profile.ageOn(DateTime(2026, 6, 15)), 36);
    Profile.birthDate = null;
    expect(Profile.ageOn(), isNull);
    expect(Profile.isComplete, isFalse);
  });
}
