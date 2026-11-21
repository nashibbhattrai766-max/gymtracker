package com.nash.gymtracker.gymtracker

import android.content.Context
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.TimeUnit

/**
 * Runs after the 11 PM reminder: reads yesterday + today from Health Connect and
 * POSTs each day to the backend `/watch/` endpoint. Retries with backoff if the
 * server is unreachable (e.g. VPN not connected). Anything it misses is back-filled
 * by the app the next time it's opened.
 */
class WatchSyncWorker(ctx: Context, params: WorkerParameters) : CoroutineWorker(ctx, params) {

    companion object {
        private const val TAG = "WatchSyncWorker"
        private const val DEFAULT_BASE_URL = "http://10.0.0.60:8000"

        fun enqueueNightly(ctx: Context) {
            val request = OneTimeWorkRequestBuilder<WatchSyncWorker>()
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .setBackoffCriteria(BackoffPolicy.LINEAR, 30, TimeUnit.MINUTES)
                .build()
            WorkManager.getInstance(ctx)
                .enqueueUniqueWork("watch_sync_nightly", ExistingWorkPolicy.REPLACE, request)
        }
    }

    override suspend fun doWork(): Result {
        val reader = HealthReader(applicationContext)
        val granted = try { reader.grantedPermissions() } catch (e: Exception) {
            Log.w(TAG, "Health Connect unavailable", e); return Result.failure()
        }
        if (HealthReader.BACKGROUND !in granted) {
            Log.i(TAG, "No background-read permission; app will sync on next open")
            return Result.failure()
        }

        val today = Reminders.today()
        return try {
            for (date in listOf(today.minusDays(1), today)) {
                post(JSONObject(reader.readDay(date)))
            }
            Result.success()
        } catch (e: Exception) {
            Log.w(TAG, "Sync attempt $runAttemptCount failed", e)
            if (runAttemptCount < 8) Result.retry() else Result.failure()
        }
    }

    private fun post(body: JSONObject) {
        val conn = URL("${baseUrl()}/watch/").openConnection() as HttpURLConnection
        try {
            conn.requestMethod = "POST"
            conn.connectTimeout = 10_000
            conn.readTimeout = 10_000
            conn.doOutput = true
            conn.setRequestProperty("Content-Type", "application/json")
            conn.outputStream.use { it.write(body.toString().toByteArray()) }
            val code = conn.responseCode
            if (code !in 200..299) throw IllegalStateException("Server returned $code")
        } finally {
            conn.disconnect()
        }
    }

    /** Same backend URL the Flutter app stores via shared_preferences. */
    private fun baseUrl(): String =
        applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getString("flutter.base_url", null)?.trimEnd('/') ?: DEFAULT_BASE_URL
}
