import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/entry.dart';
import '../models/analytics.dart';
import '../models/watch_data.dart';
import '../models/workout.dart';
import 'local_storage.dart';

class ApiService {
  static const Duration _timeout = Duration(seconds: 10);

  // ── Connectivity check ─────────────────────────────────────────────────────

  static Future<bool> isOnline() async {
    try {
      final res = await http
          .get(Uri.parse(ApiConfig.health))
          .timeout(_timeout);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── Entries ────────────────────────────────────────────────────────────────

  static Future<DailyEntry?> getEntry(String date) async {
    final cached = await LocalStorage.getEntry(date);

    // Edits saved on the phone but not yet on the server are the newest copy:
    // never let the server's older copy (or a 404) replace them. Push them now.
    if (cached != null && !await LocalStorage.isSynced(date)) {
      await saveEntryWithDetail(cached);
      return cached;
    }

    try {
      final res = await http
          .get(Uri.parse(ApiConfig.entry(date)))
          .timeout(_timeout);
      if (res.statusCode == 200) {
        final entry = DailyEntry.fromJson(jsonDecode(res.body));
        await LocalStorage.upsertEntry(entry);
        await LocalStorage.markSynced(date); // it came from the server
        return entry;
      }
      if (res.statusCode == 404) {
        // Entry was deleted from server — clear local cache too
        await LocalStorage.deleteEntry(date);
        return null;
      }
      return cached;
    } catch (_) {
      // Offline — return cached version
      return cached;
    }
  }

  static Future<({bool success, String? error})> saveEntryWithDetail(DailyEntry entry) async {
    await LocalStorage.upsertEntry(entry);
    try {
      final body = jsonEncode(entry.toJson());
      final res = await http
          .post(
            Uri.parse(ApiConfig.entries),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(_timeout);
      if (res.statusCode == 200 || res.statusCode == 201) {
        await LocalStorage.markSynced(entry.date);
        return (success: true, error: null);
      }
      return (success: false, error: 'Server returned ${res.statusCode}: ${res.body}');
    } catch (e) {
      return (success: false, error: e.toString());
    }
  }

  static Future<bool> saveEntry(DailyEntry entry) async {
    final result = await saveEntryWithDetail(entry);
    return result.success;
  }

  /// Push all unsynced local entries to the server
  static Future<void> syncPending() async {
    final unsynced = await LocalStorage.getUnsyncedEntries();
    for (final entry in unsynced) {
      await saveEntry(entry);
    }
  }

  // ── Watch data ─────────────────────────────────────────────────────────────

  /// Save locally first, then push to the backend (upsert by date).
  static Future<bool> saveWatchData(WatchData data) async {
    await WatchStorage.upsert(data);
    try {
      final res = await http
          .post(
            Uri.parse(ApiConfig.watch),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(data.toJson()),
          )
          .timeout(_timeout);
      if (res.statusCode == 200 || res.statusCode == 201) {
        await WatchStorage.markSynced(data.date);
        return true;
      }
    } catch (_) {}
    return false;
  }

  // ── Workouts ───────────────────────────────────────────────────────────────

  /// Save locally first, then push to the backend (upsert by session id).
  static Future<bool> saveWorkout(WorkoutSession session, {bool push = true}) async {
    await WorkoutStorage.save(session);
    if (!push) return false;
    try {
      final res = await http
          .post(
            Uri.parse(ApiConfig.workouts),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(session.toApi()),
          )
          .timeout(_timeout);
      if (res.statusCode == 200 || res.statusCode == 201) {
        await WorkoutStorage.markSynced(session.id);
        return true;
      }
    } catch (_) {}
    return false;
  }

  static Future<void> syncPendingWorkouts() async {
    for (final s in await WorkoutStorage.unsynced()) {
      await saveWorkout(s);
    }
  }

  static Future<void> syncPendingWatch() async {
    for (final data in await WatchStorage.getUnsynced()) {
      await saveWatchData(data);
    }
  }

  // ── Analytics ──────────────────────────────────────────────────────────────

  static Future<WeeklyAnalytics?> getWeeklyAnalytics(String date) async {
    try {
      final res = await http
          .get(Uri.parse('${ApiConfig.weeklyAnalytics}?date=$date'))
          .timeout(_timeout);
      if (res.statusCode == 200) {
        return WeeklyAnalytics.fromJson(jsonDecode(res.body));
      }
    } catch (_) {}
    return null;
  }

  static Future<MonthlyAnalytics?> getMonthlyAnalytics(String month) async {
    try {
      final res = await http
          .get(Uri.parse('${ApiConfig.monthlyAnalytics}?month=$month'))
          .timeout(_timeout);
      if (res.statusCode == 200) {
        return MonthlyAnalytics.fromJson(jsonDecode(res.body));
      }
    } catch (_) {}
    return null;
  }

  static Future<StreakInfo?> getStreakInfo() async {
    try {
      final res = await http
          .get(Uri.parse(ApiConfig.streak))
          .timeout(_timeout);
      if (res.statusCode == 200) {
        return StreakInfo.fromJson(jsonDecode(res.body));
      }
    } catch (_) {}
    return null;
  }
}
