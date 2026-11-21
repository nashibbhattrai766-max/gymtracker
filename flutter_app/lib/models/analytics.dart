import 'entry.dart';

class DataPoint {
  final String date;
  final double? value;
  DataPoint({required this.date, this.value});
  factory DataPoint.fromJson(Map<String, dynamic> j) =>
      DataPoint(date: j['date'], value: j['value']?.toDouble());
}

class WeeklyAnalytics {
  final String weekStart;
  final String weekEnd;
  final int daysLogged;
  final int gymDays;
  final int gymStreak;
  final double? avgWeightKg;
  final double? weightChangeKg;
  final double? avgWaistCm;
  final double? waistChangeCm;
  final double totalCalories;
  final double avgDailyCalories;
  final double? avgSleepHours;
  final double? avgWaterLitres;
  final double? avgMoodScore;
  final String motivationMessage;
  final int performanceScore;
  final List<DailyEntry> entries;

  WeeklyAnalytics({
    required this.weekStart,
    required this.weekEnd,
    required this.daysLogged,
    required this.gymDays,
    required this.gymStreak,
    this.avgWeightKg,
    this.weightChangeKg,
    this.avgWaistCm,
    this.waistChangeCm,
    required this.totalCalories,
    required this.avgDailyCalories,
    this.avgSleepHours,
    this.avgWaterLitres,
    this.avgMoodScore,
    required this.motivationMessage,
    required this.performanceScore,
    required this.entries,
  });

  factory WeeklyAnalytics.fromJson(Map<String, dynamic> j) => WeeklyAnalytics(
        weekStart:          j['week_start'],
        weekEnd:            j['week_end'],
        daysLogged:         j['days_logged'] ?? 0,
        gymDays:            j['gym_days'] ?? 0,
        gymStreak:          j['gym_streak'] ?? 0,
        avgWeightKg:        j['avg_weight_kg']?.toDouble(),
        weightChangeKg:     j['weight_change_kg']?.toDouble(),
        avgWaistCm:         j['avg_waist_cm']?.toDouble(),
        waistChangeCm:      j['waist_change_cm']?.toDouble(),
        totalCalories:      (j['total_calories'] ?? 0).toDouble(),
        avgDailyCalories:   (j['avg_daily_calories'] ?? 0).toDouble(),
        avgSleepHours:      j['avg_sleep_hours']?.toDouble(),
        avgWaterLitres:     j['avg_water_litres']?.toDouble(),
        avgMoodScore:       j['avg_mood_score']?.toDouble(),
        motivationMessage:  j['motivation_message'] ?? '',
        performanceScore:   j['performance_score'] ?? 0,
        entries: (j['entries'] as List? ?? [])
            .map((e) => DailyEntry.fromJson(e))
            .toList(),
      );
}

class MonthlyAnalytics {
  final String month;
  final int daysLogged;
  final int gymDays;
  final double gymAttendancePct;
  final double? startWeightKg;
  final double? endWeightKg;
  final double? weightChangeKg;
  final double? weightChangePct;
  final double? startWaistCm;
  final double? endWaistCm;
  final double? waistChangeCm;
  final double avgDailyCalories;
  final int bestGymStreak;
  final List<DataPoint> weightSeries;
  final List<DataPoint> calorieSeries;
  final List<DataPoint> waistSeries;
  final List<DataPoint> moodSeries;
  final List<String> highlights;
  final String motivationMessage;

  MonthlyAnalytics({
    required this.month,
    required this.daysLogged,
    required this.gymDays,
    required this.gymAttendancePct,
    this.startWeightKg,
    this.endWeightKg,
    this.weightChangeKg,
    this.weightChangePct,
    this.startWaistCm,
    this.endWaistCm,
    this.waistChangeCm,
    required this.avgDailyCalories,
    required this.bestGymStreak,
    required this.weightSeries,
    required this.calorieSeries,
    required this.waistSeries,
    required this.moodSeries,
    required this.highlights,
    required this.motivationMessage,
  });

  factory MonthlyAnalytics.fromJson(Map<String, dynamic> j) => MonthlyAnalytics(
        month:             j['month'],
        daysLogged:        j['days_logged'] ?? 0,
        gymDays:           j['gym_days'] ?? 0,
        gymAttendancePct:  (j['gym_attendance_pct'] ?? 0).toDouble(),
        startWeightKg:     j['start_weight_kg']?.toDouble(),
        endWeightKg:       j['end_weight_kg']?.toDouble(),
        weightChangeKg:    j['weight_change_kg']?.toDouble(),
        weightChangePct:   j['weight_change_pct']?.toDouble(),
        startWaistCm:      j['start_waist_cm']?.toDouble(),
        endWaistCm:        j['end_waist_cm']?.toDouble(),
        waistChangeCm:     j['waist_change_cm']?.toDouble(),
        avgDailyCalories:  (j['avg_daily_calories'] ?? 0).toDouble(),
        bestGymStreak:     j['best_gym_streak'] ?? 0,
        weightSeries:  _parsePoints(j['weight_series']),
        calorieSeries: _parsePoints(j['calorie_series']),
        waistSeries:   _parsePoints(j['waist_series']),
        moodSeries:    _parsePoints(j['mood_series']),
        highlights:        List<String>.from(j['highlights'] ?? []),
        motivationMessage: j['motivation_message'] ?? '',
      );

  static List<DataPoint> _parsePoints(dynamic list) =>
      (list as List? ?? []).map((e) => DataPoint.fromJson(e)).toList();
}

class StreakInfo {
  final int currentStreak;
  final int longestStreak;
  final String? lastGymDate;
  final int totalGymDays;

  StreakInfo({
    required this.currentStreak,
    required this.longestStreak,
    this.lastGymDate,
    required this.totalGymDays,
  });

  factory StreakInfo.fromJson(Map<String, dynamic> j) => StreakInfo(
        currentStreak: j['current_streak'] ?? 0,
        longestStreak: j['longest_streak'] ?? 0,
        lastGymDate:   j['last_gym_date'],
        totalGymDays:  j['total_gym_days'] ?? 0,
      );
}
