import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/watch_data.dart';
import '../providers/gym_provider.dart';

/// Galaxy Watch (Samsung Health → Health Connect) data for one day.
/// Shows a "Connect" prompt when Health Connect permissions aren't granted yet.
class WatchCard extends StatelessWidget {
  final WatchData? data;
  final bool showSyncButton;
  /// Called instead of the default sync when the button is pressed.
  final Future<void> Function()? onSync;

  const WatchCard({super.key, required this.data, this.showSyncButton = false, this.onSync});

  static const _teal = Color(0xFF00D1B2);

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GymProvider>();
    final status = provider.healthStatus;

    if (!status.connected) return _connectPrompt(context, provider);

    final d = data;
    final nf = NumberFormat.decimalPattern();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.watch_rounded, color: _teal, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Galaxy Watch',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                ),
                if (provider.watchSyncing)
                  const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            const SizedBox(height: 14),
            if (d == null || d.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('No watch data for this day yet.',
                    style: TextStyle(color: Colors.white54, fontSize: 13)),
              )
            else ...[
              Row(children: [
                _metric(Icons.directions_walk_rounded, 'Steps',
                    d.steps != null ? nf.format(d.steps) : '—', _teal),
                _metric(Icons.route_rounded, 'Distance',
                    d.distanceKm != null ? '${d.distanceKm!.toStringAsFixed(1)} km' : '—',
                    Colors.lightBlueAccent),
                _metric(Icons.local_fire_department_rounded, 'Active kcal',
                    d.activeCalories != null ? d.activeCalories!.toStringAsFixed(0) : '—',
                    const Color(0xFFFF6B35)),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                _metric(Icons.favorite_rounded, 'Avg HR',
                    d.avgHr != null ? '${d.avgHr} bpm' : '—', Colors.redAccent),
                _metric(Icons.monitor_heart_rounded, 'Resting HR',
                    d.restingHr != null ? '${d.restingHr} bpm' : '—',
                    Colors.pinkAccent),
                _metric(Icons.bedtime_rounded, 'Sleep', d.sleepLabel ?? '—',
                    const Color(0xFF9B59B6)),
              ]),
              if (d.exerciseList.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Divider(color: Colors.white12, height: 1),
                const SizedBox(height: 10),
                for (final ex in d.exerciseList)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      const Icon(Icons.fitness_center_rounded,
                          size: 15, color: Colors.greenAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          ex['title'] ?? ex['type'] ?? 'Workout',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ),
                      Text('${ex['start']} · ${ex['minutes']} min',
                          style: const TextStyle(color: Colors.white38, fontSize: 12)),
                    ]),
                  ),
              ],
            ],
            if (provider.watchError != null) ...[
              const SizedBox(height: 8),
              Text('⚠️ ${provider.watchError}',
                  style: const TextStyle(color: Colors.orangeAccent, fontSize: 12)),
            ],
            if (showSyncButton) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: provider.watchSyncing
                    ? null
                    : onSync ?? () => provider.syncWatchData(force: true),
                icon: const Icon(Icons.sync_rounded, size: 18),
                label: Text(provider.watchSyncing ? 'Syncing…' : 'Sync Watch Data'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _teal,
                  side: const BorderSide(color: _teal),
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metric(IconData icon, String label, String value, Color color) =>
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 4),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
            Text(label,
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
      );

  Widget _connectPrompt(BuildContext context, GymProvider provider) {
    final status = provider.healthStatus;
    final needsUpdate = status.sdk == 'update_required';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.watch_rounded, color: _teal, size: 20),
              SizedBox(width: 8),
              Flexible(
                child: Text('Connect Galaxy Watch',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
              ),
            ]),
            const SizedBox(height: 8),
            Text(
              needsUpdate
                  ? 'Health Connect needs an update before GymTracker can read your watch data.'
                  : status.available
                      ? 'Allow GymTracker to read steps, heart rate, sleep and workouts from Health Connect (synced from Samsung Health).'
                      : 'Health Connect isn\'t available on this device.',
              style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
            ),
            if (status.available || needsUpdate) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: needsUpdate
                    ? () => provider.openHealthSettings()
                    : () => provider.connectHealth(),
                icon: Icon(needsUpdate ? Icons.system_update_rounded : Icons.link_rounded,
                    size: 18),
                label: Text(needsUpdate ? 'Update Health Connect' : 'Connect'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _teal,
                  side: const BorderSide(color: _teal),
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
