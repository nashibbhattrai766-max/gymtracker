import 'package:flutter/services.dart';

/// Water (hourly 6 AM–9 PM), gym (8 PM) and daily-log (11 PM) reminders,
/// local time. Scheduled natively with AlarmManager (android/.../Reminders.kt)
/// — no notification plugin. Galaxy Watch mirrors them automatically.
class ReminderService {
  static const _channel = MethodChannel('gymtracker/reminders');

  static const water = 'water';
  static const gym   = 'gym';
  static const log   = 'log';

  /// Android 13+ notification permission prompt. Returns true if allowed.
  static Future<bool> requestPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, bool>> getSettings() async {
    final m = await _channel.invokeMapMethod<String, bool>('getSettings');
    return m ?? {water: true, gym: true, log: true};
  }

  static Future<void> setSettings(Map<String, bool> settings) =>
      _channel.invokeMethod('setSettings', settings);

  static Future<void> sendTest() => _channel.invokeMethod('test');

  /// Tab requested by a tapped notification ('log'), consumed once.
  static Future<String?> consumeLaunchTab() async {
    try {
      return await _channel.invokeMethod<String>('consumeLaunchTab');
    } catch (_) {
      return null;
    }
  }
}
