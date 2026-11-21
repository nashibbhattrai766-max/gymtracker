import 'package:flutter/services.dart';

/// Events from the native Vitafit scale driver (android/.../VitafitScale.kt).
sealed class ScaleEvent {}

class ScaleStatus extends ScaleEvent {
  final String message;
  ScaleStatus(this.message);
}

class ScaleLiveWeight extends ScaleEvent {
  final double weightKg;
  final bool stable;
  ScaleLiveWeight(this.weightKg, this.stable);
}

class ScaleResult extends ScaleEvent {
  final double weightKg;
  final int? impedanceOhm; // null if you stepped off before it was measured
  ScaleResult(this.weightKg, this.impedanceOhm);
}

class ScaleError extends ScaleEvent {
  final String message;
  ScaleError(this.message);
}

/// Vitafit smart scale over Bluetooth LE — native code, no plugin.
class ScaleService {
  static const _methods = MethodChannel('gymtracker/scale');
  static const _events = EventChannel('gymtracker/scale/events');

  static final Stream<ScaleEvent> events =
      _events.receiveBroadcastStream().map((raw) {
    final m = Map<String, dynamic>.from(raw as Map);
    switch (m['type']) {
      case 'live':
        return ScaleLiveWeight((m['weightKg'] as num).toDouble(), m['stable'] == true);
      case 'result':
        return ScaleResult(
            (m['weightKg'] as num).toDouble(), (m['impedanceOhm'] as num?)?.toInt());
      case 'error':
        return ScaleError(m['message'] ?? 'Something went wrong');
      default:
        return ScaleStatus(m['message'] ?? '');
    }
  });

  /// Android "Nearby devices" permission. Returns true if granted.
  static Future<bool> requestPermission() async =>
      await _methods.invokeMethod<bool>('requestPermission') ?? false;

  static Future<void> start() => _methods.invokeMethod('start');
  static Future<void> stop() => _methods.invokeMethod('stop');
}
