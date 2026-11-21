import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:gymtracker/config/api_config.dart';
import 'package:gymtracker/providers/gym_provider.dart';
import 'package:gymtracker/screens/log_screen.dart';
import 'package:gymtracker/services/api_service.dart';
import 'package:gymtracker/services/local_storage.dart';

/// The Log screen must never wipe values saved earlier in the day, and edits
/// saved while offline must survive the next load.
void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await databaseFactory.deleteDatabase('${await getDatabasesPath()}/gymtracker_cache.db');
    // Unreachable server: every request fails fast, like being off the VPN
    SharedPreferences.setMockInitialValues({'base_url': 'http://127.0.0.1:9'});
    await ApiConfig.load();
  });

  Widget app() => MaterialApp(
        home: ChangeNotifierProvider(create: (_) => GymProvider(), child: const LogScreen()),
      );

  Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 200; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
      await tester.pump();
      if (finder.evaluate().isNotEmpty) return;
    }
    fail('Timed out waiting for $finder');
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);
  final save = find.widgetWithText(TextButton, 'Save');
  final saved = find.textContaining('Saved. This is');

  testWidgets('saving later in the day keeps the morning weigh-in', (tester) async {
    // Tall screen so every field of the Log form is built without scrolling
    tester.view.physicalSize = const Size(1200, 8000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      // Morning: log weight only
      await tester.pumpWidget(app());
      await pumpUntil(tester, find.textContaining('Nothing saved for this day yet'));
      await tester.enterText(field('Weight (kg)'), '92.75');
      await tester.pump();
      expect(find.textContaining('Unsaved changes'), findsOneWidget);
      await tester.tap(save);
      await pumpUntil(tester, saved);
      // Form keeps showing what was saved (no more clearing)
      expect(find.widgetWithText(TextFormField, '92.75'), findsOneWidget);

      // Night: reopen the screen fresh (like reopening the app) and add food
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app());
      await pumpUntil(tester, saved);
      expect(find.widgetWithText(TextFormField, '92.75'), findsOneWidget,
          reason: "the day's saved weight is loaded into the form");
      await tester.enterText(field('Breakfast kcal'), '450');
      await tester.pump();
      await tester.tap(save);
      await pumpUntil(tester, saved);

      final stored = await LocalStorage.getEntry(today);
      expect(stored!.weightKg, 92.75, reason: 'morning weight survived the night save');
      expect(stored.calBreakfast, 450);

      // Saved offline → unsynced; loading again must not delete or replace it
      expect(await LocalStorage.isSynced(today), isFalse);
      final reloaded = await ApiService.getEntry(today);
      expect(reloaded?.weightKg, 92.75);
      expect(reloaded?.calBreakfast, 450);
    });
  });
}
