import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:gymtracker/config/api_config.dart';
import 'package:gymtracker/data/workout_plan.dart';
import 'package:gymtracker/models/workout.dart';
import 'package:gymtracker/providers/gym_provider.dart';
import 'package:gymtracker/screens/exercise_screen.dart';
import 'package:gymtracker/services/local_storage.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await databaseFactory.deleteDatabase('${await getDatabasesPath()}/gymtracker_cache.db');
    SharedPreferences.setMockInitialValues({'base_url': 'http://127.0.0.1:9'});
    await ApiConfig.load();
  });

  test('plan: 5 days, no repeats, every exercise and alternative has a video', () {
    expect(workoutPlan.length, 5);
    final all = workoutPlan.expand((d) => d.exercises).toList();
    final ids = [for (final e in all) ...[e.id, if (e.alt != null) e.alt!.id]];
    expect(ids.toSet().length, ids.length, reason: 'each machine has its own history id');
    for (final e in all) {
      expect(e.videoUrl, startsWith('https://www.youtube.com/watch?v='));
      if (e.alt != null) expect(e.alt!.videoUrl, startsWith('https://www.youtube.com/watch?v='));
    }
    // No dumbbells, kettlebells or floor planks in the main plan
    for (final e in all) {
      expect(e.name.toLowerCase(), isNot(anyOf(contains('dumbbell'), contains('kettlebell'), contains('plank'))));
    }
  });

  testWidgets('finish Day 1: saved, gym ticked, rotation moves to Day 2, "last time" shows',
      (tester) async {
    tester.view.physicalSize = const Size(390, 16000); // phone width: catches layout overflows
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<void> pumpUntil(Finder f) async {
      for (var i = 0; i < 200; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        await tester.pump();
        if (f.evaluate().isNotEmpty) return;
      }
      fail('Timed out waiting for $f');
    }

    await tester.runAsync(() async {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final provider = GymProvider();
      Widget app() => MaterialApp(
            home: ChangeNotifierProvider.value(value: provider, child: const ExerciseScreen()),
          );

      await tester.pumpWidget(app());
      await pumpUntil(find.text('Day 1 · Push'));

      // Log set 1 of the chest press machine and tick it
      await tester.enterText(find.widgetWithText(TextFormField, 'kg').first, '20');
      await tester.enterText(find.widgetWithText(TextFormField, 'reps').first, '12');
      await tester.pump();
      await tester.tap(find.byType(Checkbox).at(2)); // [treadmill, exercise, set 1]
      await tester.pump();

      // Shoulder press machine is busy: swap to the Smith machine and log a set
      await tester.tap(find.text('Machine busy? Use: Smith machine shoulder press (seated)'));
      await tester.pump();
      expect(find.text('Smith machine shoulder press (seated)'), findsOneWidget);
      expect(find.textContaining('Using the alternative'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextFormField, 'kg').at(3), '30'); // card 2, set 1
      await tester.enterText(find.widgetWithText(TextFormField, 'reps').at(3), '10');
      await tester.pump();

      await tester.ensureVisible(find.text('Finish workout'));
      await tester.tap(find.text('Finish workout'));
      // Only one set is done, so no whole exercise is done yet: it asks first
      await pumpUntil(find.text('Nothing ticked yet'));
      await tester.tap(find.text('Finish'));
      await pumpUntil(find.text('Nice 💪'));
      expect(find.textContaining('Next up: Day 2'), findsWidgets); // popup + finished banner
      await tester.tap(find.text('Nice 💪'));
      await tester.pump();

      final saved = await WorkoutStorage.get(today, 1);
      expect(saved!.finished, isTrue);
      expect(saved.exercise('chest_press_machine')!.sets.first.weightKg, 20);
      expect(saved.exercise('chest_press_machine')!.sets.first.reps, 12);
      final shoulder = saved.exercise('shoulder_press_machine')!;
      expect(shoulder.variant, 'smith_shoulder_press');
      expect(shoulder.name, 'Smith machine shoulder press (seated)');
      expect((await LocalStorage.getEntry(today))!.gymAttended, isTrue,
          reason: 'finishing a workout ticks Gym on the day');

      // A later session sees "last time", kept separately for each machine
      final tomorrow = DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days: 1)));
      expect((await WorkoutStorage.lastTime('chest_press_machine', tomorrow))!.sets.first.weightKg, 20);
      expect((await WorkoutStorage.lastTime('smith_shoulder_press', tomorrow))!.sets.first.weightKg, 30);
      expect(await WorkoutStorage.lastTime('shoulder_press_machine', tomorrow), isNull,
          reason: 'the main machine was not used, so it has no history yet');
      expect((await WorkoutStorage.lastFinished())!.day, 1);
      expect(WorkoutSession.start(today, 5).exercises.length, planDay(5).exercises.length);

      // Every day renders at phone width (no overflows), switched via the dropdown
      for (final d in workoutPlan.skip(1)) {
        await tester.ensureVisible(find.byType(DropdownButton<int>));
        await tester.tap(find.byType(DropdownButton<int>));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.textContaining('Day ${d.day} · ${d.title}').last);
        await pumpUntil(find.text('Day ${d.day} · ${d.title}'));
        expect(find.text(d.exercises.first.name), findsOneWidget);
      }
    });
  });
}
