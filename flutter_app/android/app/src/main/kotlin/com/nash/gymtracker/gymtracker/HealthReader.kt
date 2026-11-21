package com.nash.gymtracker.gymtracker

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.HealthConnectFeatures
import androidx.health.connect.client.aggregate.AggregateMetric
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.DistanceRecord
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.RestingHeartRateRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.TotalCaloriesBurnedRecord
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import org.json.JSONArray
import org.json.JSONObject
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import kotlin.math.roundToInt

/**
 * Reads one local calendar day of Galaxy Watch data from Health Connect
 * (Samsung Health → Health Connect → here). Keys match the backend `watch_data` table.
 */
class HealthReader(private val ctx: Context) {

    companion object {
        val PERMISSIONS: Set<String> = setOf(
            HealthPermission.getReadPermission(StepsRecord::class),
            HealthPermission.getReadPermission(DistanceRecord::class),
            HealthPermission.getReadPermission(ActiveCaloriesBurnedRecord::class),
            HealthPermission.getReadPermission(TotalCaloriesBurnedRecord::class),
            HealthPermission.getReadPermission(HeartRateRecord::class),
            HealthPermission.getReadPermission(RestingHeartRateRecord::class),
            HealthPermission.getReadPermission(SleepSessionRecord::class),
            HealthPermission.getReadPermission(ExerciseSessionRecord::class),
        )
        const val BACKGROUND = HealthPermission.PERMISSION_READ_HEALTH_DATA_IN_BACKGROUND

        fun sdkStatus(ctx: Context): Int = HealthConnectClient.getSdkStatus(ctx)

        private val AWAKE_STAGES = setOf(
            SleepSessionRecord.STAGE_TYPE_AWAKE,
            SleepSessionRecord.STAGE_TYPE_AWAKE_IN_BED,
            SleepSessionRecord.STAGE_TYPE_OUT_OF_BED,
        )

        private val EXERCISE_NAMES = mapOf(
            ExerciseSessionRecord.EXERCISE_TYPE_STRENGTH_TRAINING to "Strength training",
            ExerciseSessionRecord.EXERCISE_TYPE_WEIGHTLIFTING to "Weightlifting",
            ExerciseSessionRecord.EXERCISE_TYPE_CALISTHENICS to "Calisthenics",
            ExerciseSessionRecord.EXERCISE_TYPE_HIGH_INTENSITY_INTERVAL_TRAINING to "HIIT",
            ExerciseSessionRecord.EXERCISE_TYPE_WALKING to "Walking",
            ExerciseSessionRecord.EXERCISE_TYPE_RUNNING to "Running",
            ExerciseSessionRecord.EXERCISE_TYPE_RUNNING_TREADMILL to "Treadmill",
            ExerciseSessionRecord.EXERCISE_TYPE_BIKING to "Cycling",
            ExerciseSessionRecord.EXERCISE_TYPE_BIKING_STATIONARY to "Exercise bike",
            ExerciseSessionRecord.EXERCISE_TYPE_ELLIPTICAL to "Elliptical",
            ExerciseSessionRecord.EXERCISE_TYPE_ROWING_MACHINE to "Rowing machine",
            ExerciseSessionRecord.EXERCISE_TYPE_STAIR_CLIMBING_MACHINE to "Stair machine",
            ExerciseSessionRecord.EXERCISE_TYPE_SWIMMING_POOL to "Swimming",
            ExerciseSessionRecord.EXERCISE_TYPE_HIKING to "Hiking",
            ExerciseSessionRecord.EXERCISE_TYPE_YOGA to "Yoga",
            ExerciseSessionRecord.EXERCISE_TYPE_PILATES to "Pilates",
            ExerciseSessionRecord.EXERCISE_TYPE_STRETCHING to "Stretching",
            ExerciseSessionRecord.EXERCISE_TYPE_BOXING to "Boxing",
        )
    }

    private val client by lazy { HealthConnectClient.getOrCreate(ctx) }

    suspend fun grantedPermissions(): Set<String> =
        client.permissionController.getGrantedPermissions()

    fun backgroundSupported(): Boolean =
        client.features.getFeatureStatus(HealthConnectFeatures.FEATURE_READ_HEALTH_DATA_IN_BACKGROUND) ==
            HealthConnectFeatures.FEATURE_STATUS_AVAILABLE

    suspend fun readDay(date: LocalDate): Map<String, Any?> {
        val granted = grantedPermissions()
        fun has(record: kotlin.reflect.KClass<out androidx.health.connect.client.records.Record>) =
            HealthPermission.getReadPermission(record) in granted

        val start = date.atStartOfDay(Reminders.ZONE).toInstant()
        val end = date.plusDays(1).atStartOfDay(Reminders.ZONE).toInstant()
        val out = linkedMapOf<String, Any?>("date" to date.toString())

        // ── Aggregates (Health Connect de-duplicates phone + watch sources) ──
        val metrics = mutableSetOf<AggregateMetric<*>>()
        if (has(StepsRecord::class)) metrics += StepsRecord.COUNT_TOTAL
        if (has(DistanceRecord::class)) metrics += DistanceRecord.DISTANCE_TOTAL
        if (has(ActiveCaloriesBurnedRecord::class)) metrics += ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL
        if (has(TotalCaloriesBurnedRecord::class)) metrics += TotalCaloriesBurnedRecord.ENERGY_TOTAL
        if (has(HeartRateRecord::class)) {
            metrics += HeartRateRecord.BPM_AVG
            metrics += HeartRateRecord.BPM_MIN
            metrics += HeartRateRecord.BPM_MAX
        }
        if (has(RestingHeartRateRecord::class)) metrics += RestingHeartRateRecord.BPM_AVG

        if (metrics.isNotEmpty()) {
            val agg = client.aggregate(AggregateRequest(metrics, TimeRangeFilter.between(start, end)))
            out["steps"] = agg[StepsRecord.COUNT_TOTAL]
            out["distance_km"] = agg[DistanceRecord.DISTANCE_TOTAL]?.inKilometers?.round(2)
            out["active_calories"] = agg[ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL]?.inKilocalories?.round(0)
            out["total_calories"] = agg[TotalCaloriesBurnedRecord.ENERGY_TOTAL]?.inKilocalories?.round(0)
            out["avg_hr"] = agg[HeartRateRecord.BPM_AVG]
            out["min_hr"] = agg[HeartRateRecord.BPM_MIN]
            out["max_hr"] = agg[HeartRateRecord.BPM_MAX]
            out["resting_hr"] = agg[RestingHeartRateRecord.BPM_AVG]
        }

        // ── Sleep: sessions that *ended* on this date (i.e. last night's sleep) ──
        if (has(SleepSessionRecord::class)) {
            val windowStart = date.minusDays(1).atTime(18, 0).atZone(Reminders.ZONE).toInstant()
            val windowEnd = date.atTime(18, 0).atZone(Reminders.ZONE).toInstant()
            val sessions = client.readRecords(
                ReadRecordsRequest(SleepSessionRecord::class, TimeRangeFilter.between(windowStart, windowEnd))
            ).records
                .filter { !it.endTime.isBefore(windowStart) && it.endTime.isBefore(windowEnd) }
                .sortedBy { it.startTime }

            var minutes = 0L
            var coveredUntil = Instant.MIN
            for (s in sessions) {
                if (s.startTime.isBefore(coveredUntil)) continue // overlapping duplicate from another app
                coveredUntil = s.endTime
                minutes += if (s.stages.isNotEmpty()) {
                    s.stages.filter { it.stage !in AWAKE_STAGES }
                        .sumOf { Duration.between(it.startTime, it.endTime).toMinutes() }
                } else {
                    Duration.between(s.startTime, s.endTime).toMinutes()
                }
            }
            out["sleep_minutes"] = if (sessions.isEmpty()) null else minutes.toInt()
        }

        // ── Exercise sessions started on this date ──
        if (has(ExerciseSessionRecord::class)) {
            val sessions = client.readRecords(
                ReadRecordsRequest(ExerciseSessionRecord::class, TimeRangeFilter.between(start, end))
            ).records
                .filter { !it.startTime.isBefore(start) }
                .sortedBy { it.startTime }

            val hhmm = DateTimeFormatter.ofPattern("HH:mm")
            val list = JSONArray()
            var totalMinutes = 0L
            var coveredUntil = Instant.MIN
            for (s in sessions) {
                if (s.startTime.isBefore(coveredUntil)) continue
                coveredUntil = s.endTime
                val mins = Duration.between(s.startTime, s.endTime).toMinutes()
                totalMinutes += mins
                list.put(JSONObject()
                    .put("type", EXERCISE_NAMES[s.exerciseType] ?: "Workout")
                    .put("title", s.title ?: JSONObject.NULL)
                    .put("start", s.startTime.atZone(Reminders.ZONE).format(hhmm))
                    .put("minutes", mins))
            }
            out["exercise_count"] = list.length()
            out["exercise_minutes"] = totalMinutes.toInt()
            out["exercises"] = list.toString()
        }

        return out
    }

    private fun Double.round(places: Int): Double {
        val f = Math.pow(10.0, places.toDouble())
        return (this * f).roundToInt() / f
    }
}
