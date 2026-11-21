import 'package:flutter/services.dart';
import '../models/watch_data.dart';

class HealthStatus {
  final String sdk; // available | update_required | unavailable
  final int granted;
  final int required;
  final bool background;
  final bool backgroundSupported;

  const HealthStatus({
    required this.sdk,
    this.granted = 0,
    this.required = 0,
    this.background = false,
    this.backgroundSupported = false,
  });

  bool get available => sdk == 'available';
  bool get connected => available && granted > 0;
  bool get fullyConnected =>
      available && granted == required && (background || !backgroundSupported);
}

/// Reads Galaxy Watch data from Health Connect via native Kotlin
/// (android/.../HealthReader.kt) — no third-party health plugin.
class HealthService {
  static const _channel = MethodChannel('gymtracker/health');

  static Future<HealthStatus> status() async {
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>('status') ?? {};
      return HealthStatus(
        sdk:                 m['sdk'] ?? 'unavailable',
        granted:             m['granted'] ?? 0,
        required:            m['required'] ?? 0,
        background:          m['background'] ?? false,
        backgroundSupported: m['backgroundSupported'] ?? false,
      );
    } catch (_) {
      return const HealthStatus(sdk: 'unavailable');
    }
  }

  /// Shows the Health Connect permission screen. Returns granted permissions.
  static Future<List<String>> requestPermissions() async {
    final granted = await _channel.invokeListMethod<String>('requestPermissions');
    return granted ?? const [];
  }

  /// Opens Health Connect settings (or the Play Store if it needs an update).
  static Future<void> openSettings() => _channel.invokeMethod('openSettings');

  /// Reads one day (YYYY-MM-DD, local time) from Health Connect.
  static Future<WatchData> readDay(String date) async {
    final m = await _channel.invokeMapMethod<String, dynamic>('readDay', {'date': date});
    return WatchData.fromJson(m!);
  }
}
