import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:gymtracker/config/api_config.dart';
import 'package:gymtracker/config/profile.dart';
import 'package:gymtracker/models/entry.dart';
import 'package:gymtracker/providers/gym_provider.dart';
import 'package:gymtracker/screens/log_screen.dart';
import 'package:gymtracker/services/food_service.dart';
import 'package:gymtracker/services/local_storage.dart';
import 'package:gymtracker/widgets/food_photo_sheet.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await databaseFactory.deleteDatabase('${await getDatabasesPath()}/gymtracker_cache.db');
    SharedPreferences.setMockInitialValues({'base_url': 'http://127.0.0.1:9'});
    await ApiConfig.load();
    Profile.heightCm = 170;
    Profile.birthDate = DateTime(1990, 6, 15);
    Profile.isMale = true;
    Profile.calorieTarget = 2300;
    Profile.proteinTargetG = 120;
  });

  test('suggested calorie target = Mifflin BMR × 1.55 − 500, nearest 50', () {
    // 92.5 kg, 170 cm, 27 y, male → BMR 1857.5 → ×1.55 = 2879 → −500 = 2379 → 2400
    expect(suggestedCalorieTarget(92.5, heightCm: 170, age: 27, isMale: true), 2400);
    expect(suggestedCalorieTarget(null), isNull);
  });

  test('meal items round-trip and under/over target', () {
    final items = [const MealItem(meal: 'lunch', name: 'Rice', portion: '1 cup', kcal: 205, proteinG: 4.3)];
    final back = MealItem.decodeList(MealItem.encodeList(items));
    expect(back.single.name, 'Rice');
    expect(back.single.proteinG, 4.3);
    final e = DailyEntry(date: '2026-10-05', calLunch: 1800, calorieTarget: 2300);
    expect(e.caloriesUnderTarget, 500);
    expect(DailyEntry(date: 'x', calDinner: 2500, calorieTarget: 2300).caloriesUnderTarget, -200);
  });

  testWidgets('review sheet: edit an item, switch meal, add', (tester) async {
    List<MealItem>? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () async {
            result = await showModalBottomSheet<List<MealItem>>(
              context: ctx,
              isScrollControlled: true,
              builder: (_) => FoodReviewSheet(
                bytes: const [],
                meal: 'lunch',
                preset: FoodEstimate([
                  FoodEstimateItem(name: 'Chicken breast', portion: '~150 g', kcal: 248, proteinG: 46),
                  FoodEstimateItem(name: 'Rice', portion: '1 cup', kcal: 205, proteinG: 4.3),
                ], 'medium', ''),
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('453 kcal · 50 g protein'), findsOneWidget);

    // Two cups of rice, not one
    await tester.enterText(find.widgetWithText(TextFormField, 'Calories').at(1), '410');
    await tester.pump();
    expect(find.text('658 kcal · 50 g protein'), findsOneWidget);

    // It was actually dinner
    await tester.tap(find.text('Lunch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dinner').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to Dinner'));
    await tester.pumpAndSettle();

    expect(result!.length, 2);
    expect(result!.every((i) => i.meal == 'dinner'), isTrue);
    expect(result![1].kcal, 410);
  });

  testWidgets('Log screen shows photo items, protein and the target at phone width', (tester) async {
    tester.view.physicalSize = const Size(390, 9000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await LocalStorage.upsertEntry(DailyEntry(
        date: today,
        calLunch: 650,
        proteinG: 50,
        mealItems: MealItem.encodeList(const [
          MealItem(meal: 'lunch', name: 'Grilled chicken breast with a long description', portion: '~150 g', kcal: 248, proteinG: 46),
          MealItem(meal: 'lunch', name: 'Rice', portion: '1 cup', kcal: 402, proteinG: 4),
        ]),
      ));

      await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider(create: (_) => GymProvider(), child: const LogScreen()),
      ));
      for (var i = 0; i < 200 && find.text('📷 Lunch').evaluate().isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        await tester.pump();
      }
      expect(find.text('📷 Lunch'), findsOneWidget);
      expect(find.text('650 / 2300 kcal'), findsOneWidget);
      expect(find.textContaining('1650 under target'), findsOneWidget);
      expect(find.textContaining('50 / 120 g protein'), findsOneWidget);

      // Removing an item takes it off the meal and protein
      await tester.tap(find.byTooltip('Remove (takes it off the meal)').last);
      await tester.pump();
      expect(find.text('248 / 2300 kcal'), findsOneWidget);
      expect(find.textContaining('46 / 120 g protein'), findsOneWidget);
      expect(find.textContaining('Unsaved changes'), findsOneWidget);
    });
  });
}
