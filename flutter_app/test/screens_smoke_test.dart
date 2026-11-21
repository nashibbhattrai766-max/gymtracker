import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:gymtracker/config/api_config.dart';
import 'package:gymtracker/config/profile.dart';
import 'package:gymtracker/providers/gym_provider.dart';
import 'package:gymtracker/screens/ai_chat_screen.dart';
import 'package:gymtracker/screens/home_screen.dart';
import 'package:gymtracker/screens/progress_screen.dart';

/// Every main screen renders at phone width without layout overflows.
void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({'base_url': 'http://127.0.0.1:9'});
    await ApiConfig.load();
    Profile.heightCm = 170;
    Profile.birthDate = DateTime(1990, 6, 15);
    Profile.calorieTarget = 2300;
    Profile.targetWeightKg = 70;
  });

  for (final (name, screen) in [
    ('Home', const HomeScreen()),
    ('Progress', const ProgressScreen()),
    ('AI Coach', const AiChatScreen()),
  ]) {
    testWidgets('$name renders at phone width', (tester) async {
      tester.view.physicalSize = const Size(390, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        await tester.pumpWidget(MaterialApp(
          home: ChangeNotifierProvider(create: (_) => GymProvider(), child: screen),
        ));
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          await tester.pump();
        }
      });
      expect(tester.takeException(), isNull);
    });
  }
}
