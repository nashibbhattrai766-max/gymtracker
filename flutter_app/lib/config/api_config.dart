import 'package:shared_preferences/shared_preferences.dart';

class ApiConfig {
  static const String _keyBaseUrl = 'base_url';
  static const String defaultBaseUrl = 'http://10.0.0.60:8000';

  static String _baseUrl = defaultBaseUrl;

  static String get baseUrl => _baseUrl;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(_keyBaseUrl) ?? defaultBaseUrl;
  }

  static Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBaseUrl, url);
    _baseUrl = url;
  }

  // Endpoint helpers
  static String get entries => '$_baseUrl/entries/';
  static String entry(String date) => '$_baseUrl/entries/$date';
  static String get weeklyAnalytics => '$_baseUrl/analytics/weekly';
  static String get monthlyAnalytics => '$_baseUrl/analytics/monthly';
  static String get streak => '$_baseUrl/analytics/streak';
  static String get health => '$_baseUrl/health';
  static String get watch => '$_baseUrl/watch/';
  static String get workouts => '$_baseUrl/workouts/';
}
