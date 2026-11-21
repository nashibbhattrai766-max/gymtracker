import 'dart:convert';

/// One day of Galaxy Watch data (Samsung Health → Health Connect).
/// Kept separate from [DailyEntry] so manual fields are never overwritten.
class WatchData {
  final String date;
  final int? steps;
  final double? distanceKm;
  final double? activeCalories;
  final double? totalCalories;
  final int? restingHr;
  final int? avgHr;
  final int? minHr;
  final int? maxHr;
  final int? sleepMinutes;
  final int? exerciseMinutes;
  final int? exerciseCount;
  final String? exercises; // JSON list: [{type, title, start, minutes}]

  WatchData({
    required this.date,
    this.steps,
    this.distanceKm,
    this.activeCalories,
    this.totalCalories,
    this.restingHr,
    this.avgHr,
    this.minHr,
    this.maxHr,
    this.sleepMinutes,
    this.exerciseMinutes,
    this.exerciseCount,
    this.exercises,
  });

  bool get isEmpty =>
      steps == null && avgHr == null && sleepMinutes == null &&
      activeCalories == null && (exerciseCount ?? 0) == 0;

  String? get sleepLabel => sleepMinutes == null
      ? null
      : '${sleepMinutes! ~/ 60}h ${(sleepMinutes! % 60).toString().padLeft(2, '0')}m';

  List<Map<String, dynamic>> get exerciseList {
    if (exercises == null || exercises!.isEmpty) return const [];
    try {
      return (jsonDecode(exercises!) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return const [];
    }
  }

  static int? _int(dynamic v) => v == null ? null : (v as num).toInt();
  static double? _dbl(dynamic v) => v == null ? null : (v as num).toDouble();

  factory WatchData.fromJson(Map<String, dynamic> j) => WatchData(
        date:            j['date'],
        steps:           _int(j['steps']),
        distanceKm:      _dbl(j['distance_km']),
        activeCalories:  _dbl(j['active_calories']),
        totalCalories:   _dbl(j['total_calories']),
        restingHr:       _int(j['resting_hr']),
        avgHr:           _int(j['avg_hr']),
        minHr:           _int(j['min_hr']),
        maxHr:           _int(j['max_hr']),
        sleepMinutes:    _int(j['sleep_minutes']),
        exerciseMinutes: _int(j['exercise_minutes']),
        exerciseCount:   _int(j['exercise_count']),
        exercises:       j['exercises'],
      );

  Map<String, dynamic> toJson() => {
        'date':             date,
        'steps':            steps,
        'distance_km':      distanceKm,
        'active_calories':  activeCalories,
        'total_calories':   totalCalories,
        'resting_hr':       restingHr,
        'avg_hr':           avgHr,
        'min_hr':           minHr,
        'max_hr':           maxHr,
        'sleep_minutes':    sleepMinutes,
        'exercise_minutes': exerciseMinutes,
        'exercise_count':   exerciseCount,
        'exercises':        exercises,
      };

  Map<String, dynamic> toDb() => {...toJson(), 'synced': 0};

  factory WatchData.fromDb(Map<String, dynamic> m) => WatchData.fromJson(m);
}
