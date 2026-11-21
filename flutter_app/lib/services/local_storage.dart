import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/entry.dart';
import '../models/watch_data.dart';
import '../models/workout.dart';

class LocalStorage {
  static Database? _db;

  static Future<Database> get db async {
    _db ??= await _init();
    return _db!;
  }

  static Future<Database> _init() async {
    final path = join(await getDatabasesPath(), 'gymtracker_cache.db');
    return openDatabase(
      path,
      version: 5,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE entries (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            date          TEXT NOT NULL UNIQUE,
            cal_breakfast REAL DEFAULT 0,
            cal_lunch     REAL DEFAULT 0,
            cal_dinner    REAL DEFAULT 0,
            cal_misc      REAL DEFAULT 0,
            weight_kg     REAL,
            waist_cm      REAL,
            body_fat_pct  REAL,
            water_pct     REAL,
            muscle_pct    REAL,
            bone_kg       REAL,
            bmr_kcal      REAL,
            impedance_ohm INTEGER,
            protein_g     REAL,
            calorie_target REAL,
            protein_target_g REAL,
            meal_items    TEXT,
            gym_attended  INTEGER DEFAULT 0,
            sleep_hours   REAL,
            water_litres  REAL,
            mood_score    INTEGER,
            notes         TEXT,
            synced        INTEGER DEFAULT 0
          )
        ''');
        await _createWatchTable(db);
        await _createWorkoutTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createWatchTable(db);
        if (oldVersion < 3) {
          for (final col in const [
            'body_fat_pct REAL', 'water_pct REAL', 'muscle_pct REAL',
            'bone_kg REAL', 'bmr_kcal REAL', 'impedance_ohm INTEGER',
          ]) {
            await db.execute('ALTER TABLE entries ADD COLUMN $col');
          }
        }
        if (oldVersion < 4) await _createWorkoutTable(db);
        if (oldVersion < 5) {
          for (final col in const [
            'protein_g REAL', 'calorie_target REAL', 'protein_target_g REAL', 'meal_items TEXT',
          ]) {
            await db.execute('ALTER TABLE entries ADD COLUMN $col');
          }
        }
      },
    );
  }

  // ── Write ──────────────────────────────────────────────────────────────────

  static Future<void> upsertEntry(DailyEntry entry) async {
    final database = await db;
    await database.insert(
      'entries',
      entry.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> markSynced(String date) async {
    final database = await db;
    await database.update(
      'entries',
      {'synced': 1},
      where: 'date = ?',
      whereArgs: [date],
    );
  }

  // ── Read ───────────────────────────────────────────────────────────────────

  static Future<bool> isSynced(String date) async {
    final database = await db;
    final rows = await database.query('entries',
        columns: ['synced'], where: 'date = ?', whereArgs: [date]);
    return rows.isEmpty || (rows.first['synced'] ?? 0) == 1;
  }

  static Future<DailyEntry?> getEntry(String date) async {
    final database = await db;
    final rows = await database.query(
      'entries',
      where: 'date = ?',
      whereArgs: [date],
    );
    if (rows.isEmpty) return null;
    return DailyEntry.fromDb(rows.first);
  }

  static Future<List<DailyEntry>> getEntriesInRange(
      String start, String end) async {
    final database = await db;
    final rows = await database.query(
      'entries',
      where: 'date >= ? AND date <= ?',
      whereArgs: [start, end],
      orderBy: 'date ASC',
    );
    return rows.map(DailyEntry.fromDb).toList();
  }

  /// Most recent (or earliest) entry where [column] has a value.
  static Future<DailyEntry?> latestWith(String column,
      {bool earliest = false, bool requireWeight = false}) async {
    final database = await db;
    final rows = await database.query(
      'entries',
      where: requireWeight ? '$column IS NOT NULL AND weight_kg IS NOT NULL' : '$column IS NOT NULL',
      orderBy: 'date ${earliest ? 'ASC' : 'DESC'}',
      limit: 1,
    );
    return rows.isEmpty ? null : DailyEntry.fromDb(rows.first);
  }

  static Future<List<DailyEntry>> getUnsyncedEntries() async {
    final database = await db;
    final rows = await database.query(
      'entries',
      where: 'synced = 0',
    );
    return rows.map(DailyEntry.fromDb).toList();
  }

  static Future<List<DailyEntry>> getAllEntries() async {
    final database = await db;
    final rows = await database.query('entries', orderBy: 'date ASC');
    return rows.map(DailyEntry.fromDb).toList();
  }

  // ── Delete ─────────────────────────────────────────────────────────────────

  static Future<void> deleteEntry(String date) async {
    final database = await db;
    await database.delete('entries', where: 'date = ?', whereArgs: [date]);
  }
}

// ── Watch data (Galaxy Watch via Health Connect) ─────────────────────────────

Future<void> _createWatchTable(Database db) => db.execute('''
      CREATE TABLE IF NOT EXISTS watch_data (
        date             TEXT PRIMARY KEY,
        steps            INTEGER,
        distance_km      REAL,
        active_calories  REAL,
        total_calories   REAL,
        resting_hr       INTEGER,
        avg_hr           INTEGER,
        min_hr           INTEGER,
        max_hr           INTEGER,
        sleep_minutes    INTEGER,
        exercise_minutes INTEGER,
        exercise_count   INTEGER,
        exercises        TEXT,
        synced           INTEGER DEFAULT 0
      )
    ''');

class WatchStorage {
  static Future<void> upsert(WatchData data) async {
    final database = await LocalStorage.db;
    await database.insert('watch_data', data.toDb(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> markSynced(String date) async {
    final database = await LocalStorage.db;
    await database.update('watch_data', {'synced': 1},
        where: 'date = ?', whereArgs: [date]);
  }

  static Future<WatchData?> get(String date) async {
    final database = await LocalStorage.db;
    final rows = await database.query('watch_data',
        where: 'date = ?', whereArgs: [date]);
    return rows.isEmpty ? null : WatchData.fromDb(rows.first);
  }

  static Future<List<WatchData>> getUnsynced() async {
    final database = await LocalStorage.db;
    final rows = await database.query('watch_data', where: 'synced = 0');
    return rows.map(WatchData.fromDb).toList();
  }
}

// ── Workouts (Exercise tab) ──────────────────────────────────────────────────

Future<void> _createWorkoutTable(Database db) => db.execute('''
      CREATE TABLE IF NOT EXISTS workouts (
        id          TEXT PRIMARY KEY,
        date        TEXT NOT NULL,
        plan_day    INTEGER NOT NULL,
        finished_at TEXT,
        data        TEXT NOT NULL,
        synced      INTEGER DEFAULT 0
      )
    ''');

class WorkoutStorage {
  static Future<void> save(WorkoutSession s) async {
    final database = await LocalStorage.db;
    await database.insert(
      'workouts',
      {
        'id': s.id,
        'date': s.date,
        'plan_day': s.day,
        'finished_at': s.finishedAt,
        'data': s.encode(),
        'synced': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> markSynced(String id) async {
    final database = await LocalStorage.db;
    await database.update('workouts', {'synced': 1}, where: 'id = ?', whereArgs: [id]);
  }

  static Future<WorkoutSession?> get(String date, int day) async {
    final database = await LocalStorage.db;
    final rows = await database.query('workouts', where: 'id = ?', whereArgs: ['$date-d$day']);
    return rows.isEmpty ? null : WorkoutSession.decode(rows.first['data'] as String);
  }

  /// Today's unfinished session, if a workout is in progress.
  static Future<WorkoutSession?> inProgress(String date) async {
    final database = await LocalStorage.db;
    final rows = await database.query('workouts',
        where: 'date = ? AND finished_at IS NULL', whereArgs: [date], limit: 1);
    return rows.isEmpty ? null : WorkoutSession.decode(rows.first['data'] as String);
  }

  /// Most recently finished session (for "next up" in the rotation).
  static Future<WorkoutSession?> lastFinished() async {
    final database = await LocalStorage.db;
    final rows = await database.query('workouts',
        where: 'finished_at IS NOT NULL', orderBy: 'finished_at DESC', limit: 1);
    return rows.isEmpty ? null : WorkoutSession.decode(rows.first['data'] as String);
  }

  /// Latest earlier session (before [beforeDate]) where the exercise actually
  /// performed ([doneAs] = main or alternative id) has a logged set.
  static Future<ExerciseLog?> lastTime(String exerciseId, String beforeDate) async {
    final database = await LocalStorage.db;
    final rows = await database.query('workouts',
        where: 'date < ? AND data LIKE ?',
        whereArgs: [beforeDate, '%"$exerciseId"%'],
        orderBy: 'date DESC',
        limit: 5);
    for (final r in rows) {
      final logs = WorkoutSession.decode(r['data'] as String).exercises.where((e) => e.doneAs == exerciseId);
      final log = logs.isEmpty ? null : logs.first;
      if (log != null && log.sets.any((s) => s.reps != null || s.weightKg != null)) return log;
    }
    return null;
  }

  static Future<List<WorkoutSession>> recent({int limit = 30}) async {
    final database = await LocalStorage.db;
    final rows = await database.query('workouts', orderBy: 'date DESC', limit: limit);
    return rows.map((r) => WorkoutSession.decode(r['data'] as String)).toList();
  }

  static Future<List<WorkoutSession>> unsynced() async {
    final database = await LocalStorage.db;
    final rows = await database.query('workouts', where: 'synced = 0');
    return rows.map((r) => WorkoutSession.decode(r['data'] as String)).toList();
  }
}
