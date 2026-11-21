import 'dart:convert';
import '../data/workout_plan.dart';

/// One set of an exercise as logged in the gym.
class WorkoutSet {
  double? weightKg;
  int? reps;
  bool done;
  WorkoutSet({this.weightKg, this.reps, this.done = false});

  Map<String, dynamic> toJson() => {'weight_kg': weightKg, 'reps': reps, 'done': done};
  factory WorkoutSet.fromJson(Map<String, dynamic> j) => WorkoutSet(
        weightKg: (j['weight_kg'] as num?)?.toDouble(),
        reps: (j['reps'] as num?)?.toInt(),
        done: j['done'] == true,
      );
}

class ExerciseLog {
  final String id;        // plan exercise id (its slot in the day)
  String name;            // what was actually done
  String? variant;        // alternative id when the main machine was busy
  bool done;
  String notes;
  final List<WorkoutSet> sets;
  ExerciseLog({required this.id, required this.name, this.variant, this.done = false, this.notes = '', required this.sets});

  /// Id of the exercise actually performed ("last time" is tracked per machine).
  String get doneAs => variant ?? id;

  /// Total kg moved (weight × reps over completed-or-filled sets).
  double get volumeKg => sets.fold(0, (t, s) => t + (s.weightKg ?? 0) * (s.reps ?? 0));

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'variant': variant,
        'done': done,
        'notes': notes,
        'sets': sets.map((s) => s.toJson()).toList(),
      };
  factory ExerciseLog.fromJson(Map<String, dynamic> j) => ExerciseLog(
        id: j['id'],
        name: j['name'] ?? j['id'],
        variant: j['variant'],
        done: j['done'] == true,
        notes: j['notes'] ?? '',
        sets: ((j['sets'] as List?) ?? const [])
            .map((s) => WorkoutSet.fromJson(Map<String, dynamic>.from(s)))
            .toList(),
      );
}

class TreadmillLog {
  bool done;
  double? minutes;
  double? speedKmh;
  double? inclinePct;
  double? distanceKm;
  TreadmillLog({this.done = false, this.minutes, this.speedKmh, this.inclinePct, this.distanceKm});

  Map<String, dynamic> toJson() => {
        'done': done,
        'minutes': minutes,
        'speed_kmh': speedKmh,
        'incline_pct': inclinePct,
        'distance_km': distanceKm,
      };
  factory TreadmillLog.fromJson(Map<String, dynamic> j) => TreadmillLog(
        done: j['done'] == true,
        minutes: (j['minutes'] as num?)?.toDouble(),
        speedKmh: (j['speed_kmh'] as num?)?.toDouble(),
        inclinePct: (j['incline_pct'] as num?)?.toDouble(),
        distanceKm: (j['distance_km'] as num?)?.toDouble(),
      );
}

/// One gym session: a plan day done on a date. Saved after every change, so
/// nothing is lost if the app closes mid-workout.
class WorkoutSession {
  final String date;   // YYYY-MM-DD
  final int day;       // plan day 1–5
  final String startedAt;
  String? finishedAt;
  String notes;
  final TreadmillLog treadmill;
  final List<ExerciseLog> exercises;

  WorkoutSession({
    required this.date,
    required this.day,
    required this.startedAt,
    this.finishedAt,
    this.notes = '',
    required this.treadmill,
    required this.exercises,
  });

  String get id => '$date-d$day';
  bool get finished => finishedAt != null;
  int get exercisesDone => exercises.where((e) => e.done).length;
  double get volumeKg => exercises.fold(0, (t, e) => t + e.volumeKg);

  /// A fresh session for [day], with the plan's number of empty sets.
  factory WorkoutSession.start(String date, int day) {
    final plan = planDay(day);
    return WorkoutSession(
      date: date,
      day: day,
      startedAt: DateTime.now().toIso8601String(),
      treadmill: TreadmillLog(),
      exercises: [
        for (final e in plan.exercises)
          ExerciseLog(id: e.id, name: e.name, sets: List.generate(e.sets, (_) => WorkoutSet())),
      ],
    );
  }

  /// Sessions saved under an older version of the plan get logs for any
  /// exercises the plan now has, so every card shows.
  void ensurePlan() {
    for (final e in planDay(day).exercises) {
      if (exercise(e.id) == null) {
        exercises.add(ExerciseLog(id: e.id, name: e.name, sets: List.generate(e.sets, (_) => WorkoutSet())));
      }
    }
  }

  ExerciseLog? exercise(String id) {
    for (final e in exercises) {
      if (e.id == id) return e;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'date': date,
        'day': day,
        'title': planDay(day).title,
        'started_at': startedAt,
        'finished_at': finishedAt,
        'notes': notes,
        'treadmill': treadmill.toJson(),
        'exercises': exercises.map((e) => e.toJson()).toList(),
      };

  factory WorkoutSession.fromJson(Map<String, dynamic> j) => WorkoutSession(
        date: j['date'],
        day: (j['day'] as num).toInt(),
        startedAt: j['started_at'] ?? '',
        finishedAt: j['finished_at'],
        notes: j['notes'] ?? '',
        treadmill: TreadmillLog.fromJson(Map<String, dynamic>.from(j['treadmill'] ?? const {})),
        exercises: ((j['exercises'] as List?) ?? const [])
            .map((e) => ExerciseLog.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );

  String encode() => jsonEncode(toJson());
  static WorkoutSession decode(String s) => WorkoutSession.fromJson(jsonDecode(s));

  /// Payload for the backend /workouts endpoint.
  Map<String, dynamic> toApi() => {
        'id': id,
        'date': date,
        'plan_day': day,
        'started_at': startedAt,
        'finished_at': finishedAt,
        'data': encode(),
      };
}
