import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../models/entry.dart';
import '../models/analytics.dart';
import '../models/watch_data.dart';
import '../services/health_service.dart';
import '../services/api_service.dart';
import '../services/local_storage.dart';

class GymProvider extends ChangeNotifier {
  // ── State ──────────────────────────────────────────────────────────────────
  bool _isOnline = false;
  bool _loading = false;
  String? _error;

  DailyEntry? _todayEntry;
  WeeklyAnalytics? _weeklyAnalytics;
  MonthlyAnalytics? _monthlyAnalytics;
  StreakInfo? _streakInfo;

  HealthStatus _healthStatus = const HealthStatus(sdk: 'unavailable');
  WatchData? _todayWatch;
  bool _watchSyncing = false;
  String? _watchError;
  DateTime? _lastWatchSync;

  /// Bumped whenever a day's entry is saved from anywhere (Log, scale,
  /// finishing a workout) so open screens can reload it.
  int _entryRevision = 0;
  int get entryRevision => _entryRevision;

  // Latest body readings (any day), for the goal + body composition cards
  DailyEntry? _latestWeight;
  DailyEntry? _latestComp;
  DailyEntry? _latestWaist;
  double? _startWeightKg;

  // ── Getters ────────────────────────────────────────────────────────────────
  bool get isOnline => _isOnline;
  bool get loading => _loading;
  String? get error => _error;
  DailyEntry? get todayEntry => _todayEntry;
  WeeklyAnalytics? get weeklyAnalytics => _weeklyAnalytics;
  MonthlyAnalytics? get monthlyAnalytics => _monthlyAnalytics;
  StreakInfo? get streakInfo => _streakInfo;
  HealthStatus get healthStatus => _healthStatus;
  WatchData? get todayWatch => _todayWatch;
  bool get watchSyncing => _watchSyncing;
  String? get watchError => _watchError;
  DailyEntry? get latestWeight => _latestWeight;
  DailyEntry? get latestComp => _latestComp;
  DailyEntry? get latestWaist => _latestWaist;
  double? get startWeightKg => _startWeightKg;

  String get today => DateFormat('yyyy-MM-dd').format(DateTime.now());
  String get thisMonth => DateFormat('yyyy-MM').format(DateTime.now());

  int get currentStreak => _streakInfo?.currentStreak ?? 0;
  double get todayCalories => _todayEntry?.totalCalories ?? 0;
  bool get gymToday => _todayEntry?.gymAttended ?? false;

  // ── Init ───────────────────────────────────────────────────────────────────

  Future<void> init() async {
    _isOnline = await ApiService.isOnline();
    if (_isOnline) {
      await ApiService.syncPending();
      await ApiService.syncPendingWatch();
      await ApiService.syncPendingWorkouts();
    }
    await loadDashboard();
    _todayWatch = await WatchStorage.get(today);
    notifyListeners();
    await refreshHealthStatus();
    await syncWatchData();
  }

  Future<void> checkConnectivity() async {
    _isOnline = await ApiService.isOnline();
    notifyListeners();
  }

  // ── Dashboard load ─────────────────────────────────────────────────────────

  Future<void> loadDashboard() async {
    _loading = true;
    _error = null;
    // Clear stale state before reloading
    _todayEntry      = null;
    _weeklyAnalytics = null;
    _streakInfo      = null;
    notifyListeners();

    try {
      await Future.wait([
        _loadTodayEntry(),
        _loadStreak(),
        _loadWeekly(),
      ]);
      await _loadBody();
    } catch (e) {
      _error = e.toString();
    }

    _loading = false;
    notifyListeners();
  }

  Future<void> _loadBody() async {
    _latestWeight = await LocalStorage.latestWith('weight_kg');
    _latestComp = await LocalStorage.latestWith('body_fat_pct', requireWeight: true);
    _latestWaist = await LocalStorage.latestWith('waist_cm');
    _startWeightKg = (await LocalStorage.latestWith('weight_kg', earliest: true))?.weightKg;
  }

  Future<void> _loadTodayEntry() async {
    _todayEntry = await ApiService.getEntry(today);
  }

  Future<void> _loadStreak() async {
    _streakInfo = await ApiService.getStreakInfo();
    // Fall back to local calculation if offline
    _streakInfo ??= _computeLocalStreak();
  }

  Future<void> _loadWeekly() async {
    _weeklyAnalytics = await ApiService.getWeeklyAnalytics(today);
  }

  StreakInfo? _computeLocalStreak() {
    // Simple offline fallback — just return null for now
    return null;
  }

  // ── Save entry ─────────────────────────────────────────────────────────────

  /// Saves the whole day (phone first, then server) and refreshes everything
  /// that depends on it. Returns the server result for the snackbar.
  Future<({bool success, String? error})> saveEntry(DailyEntry entry) async {
    final result = await ApiService.saveEntryWithDetail(entry);
    if (entry.date == today) _todayEntry = entry;
    _entryRevision++;

    // Refresh analytics after save
    _weeklyAnalytics = await ApiService.getWeeklyAnalytics(today);
    _streakInfo = await ApiService.getStreakInfo();
    await _loadBody();

    notifyListeners();
    return result;
  }

  /// Finishing a workout ticks "Gym" on that day's log, keeping everything
  /// else already saved for the day.
  Future<void> markGymAttended(String date) async {
    final stored = await ApiService.getEntry(date);
    if (stored?.gymAttended == true) return;
    await saveEntry(stored?.copyWith(gymAttended: true) ??
        DailyEntry(date: date, gymAttended: true));
  }

  /// Re-reads one day's watch data from Health Connect and saves it, so the
  /// day's final log has the latest numbers. Silently skipped if not connected.
  Future<void> syncWatchDay(String date) async {
    if (!_healthStatus.connected) return;
    try {
      final data = await HealthService.readDay(date);
      await ApiService.saveWatchData(data);
      if (date == today) _todayWatch = data;
      notifyListeners();
    } catch (_) {
      // Health Connect only keeps ~30 days; older dates simply have nothing new
    }
  }

  // ── Load analytics tabs ────────────────────────────────────────────────────

  Future<void> loadWeeklyAnalytics(String date) async {
    _loading = true;
    notifyListeners();
    _weeklyAnalytics = await ApiService.getWeeklyAnalytics(date);
    _loading = false;
    notifyListeners();
  }

  Future<void> loadMonthlyAnalytics(String month) async {
    _loading = true;
    notifyListeners();
    _monthlyAnalytics = await ApiService.getMonthlyAnalytics(month);
    _loading = false;
    notifyListeners();
  }

  // ── Galaxy Watch (Health Connect) ──────────────────────────────────────────

  Future<void> refreshHealthStatus() async {
    _healthStatus = await HealthService.status();
    notifyListeners();
  }

  /// Shows the Health Connect permission screen, then back-fills the last
  /// 30 days (the most Health Connect lets a newly connected app read).
  Future<void> connectHealth() async {
    try {
      await HealthService.requestPermissions();
    } catch (e) {
      _watchError = e.toString();
    }
    await refreshHealthStatus();
    if (_healthStatus.connected) await syncWatchData(days: 30, force: true);
  }

  /// Reads the last [days] days from Health Connect, saves locally and pushes
  /// to the backend. Re-syncing a day just overwrites it, so this is safe to
  /// call often; without [force] it runs at most every 15 minutes.
  Future<void> syncWatchData({int days = 7, bool force = false}) async {
    if (_watchSyncing || !_healthStatus.connected) return;
    if (!force &&
        _lastWatchSync != null &&
        DateTime.now().difference(_lastWatchSync!) < const Duration(minutes: 15)) {
      return;
    }

    _watchSyncing = true;
    _watchError = null;
    notifyListeners();

    final fmt = DateFormat('yyyy-MM-dd');
    final now = DateTime.now();
    try {
      for (var i = 0; i < days; i++) {
        final date = fmt.format(now.subtract(Duration(days: i)));
        final data = await HealthService.readDay(date);
        await ApiService.saveWatchData(data);
        if (date == today) _todayWatch = data;
      }
      _lastWatchSync = DateTime.now();
    } catch (e) {
      _watchError = e.toString();
    }

    _watchSyncing = false;
    notifyListeners();
  }

  /// Profile (name, height, goal…) changed: rebuild cards that use it.
  void profileChanged() => notifyListeners();

  Future<WatchData?> watchFor(String date) => WatchStorage.get(date);

  Future<void> openHealthSettings() => HealthService.openSettings();

  // ── Recent entries for home screen ────────────────────────────────────────

  Future<List<DailyEntry>> getRecentEntries(int days) async {
    final end = DateTime.now();
    final start = end.subtract(Duration(days: days));
    final fmt = DateFormat('yyyy-MM-dd');
    return LocalStorage.getEntriesInRange(fmt.format(start), fmt.format(end));
  }
}
