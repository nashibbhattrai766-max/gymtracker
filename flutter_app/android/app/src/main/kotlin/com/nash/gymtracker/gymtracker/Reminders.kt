package com.nash.gymtracker.gymtracker

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime

/**
 * Daily reminders built on AlarmManager + NotificationManager directly.
 *
 * No notification plugin is used (flutter_local_notifications crashes on
 * Android 16). Each reminder slot is its own alarm that re-arms itself for the
 * next day when it fires. Galaxy Watch mirrors these like any phone notification.
 */
object Reminders {
    val ZONE: ZoneId = ZoneId.systemDefault()

    const val KIND_WATER = "water"
    const val KIND_GYM   = "gym"
    const val KIND_LOG   = "log"

    private const val CH_WATER = "water_reminder"
    private const val CH_GYM   = "gym_reminder"
    private const val CH_LOG   = "daily_log_reminder"

    // Notification IDs — water reuses one ID so each hour replaces the last
    private const val NOTIF_WATER = 200
    private const val NOTIF_GYM   = 100
    private const val NOTIF_LOG   = 300
    private const val NOTIF_TEST  = 999

    private const val PREFS = "gymtracker_reminders"
    const val EXTRA_SLOT = "slot_id"
    const val EXTRA_OPEN_TAB = "open_tab"

    data class Slot(val id: Int, val kind: String, val hour: Int)

    /** Water 6 AM–9 PM hourly, gym 8 PM, daily log + watch sync 11 PM (local). */
    val SLOTS: List<Slot> =
        (6..21).map { Slot(200 + it, KIND_WATER, it) } +
        Slot(100, KIND_GYM, 20) +
        Slot(300, KIND_LOG, 23)

    // ── Settings ────────────────────────────────────────────────────────────

    fun isEnabled(ctx: Context, kind: String): Boolean =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean("${kind}_enabled", true)

    fun settings(ctx: Context): Map<String, Boolean> =
        listOf(KIND_WATER, KIND_GYM, KIND_LOG).associateWith { isEnabled(ctx, it) }

    fun saveSettings(ctx: Context, values: Map<String, Boolean>) {
        val edit = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
        values.forEach { (kind, on) -> edit.putBoolean("${kind}_enabled", on) }
        edit.apply()
    }

    // ── Scheduling ──────────────────────────────────────────────────────────

    fun scheduleAll(ctx: Context) {
        createChannels(ctx)
        SLOTS.forEach { slot ->
            if (isEnabled(ctx, slot.kind)) schedule(ctx, slot) else cancel(ctx, slot)
        }
    }

    fun schedule(ctx: Context, slot: Slot) {
        val am = ctx.getSystemService(AlarmManager::class.java)
        val trigger = nextTrigger(slot.hour)
        val pi = pendingIntent(ctx, slot)
        val canExact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || am.canScheduleExactAlarms()
        if (canExact) {
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger, pi)
        } else {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger, pi)
        }
    }

    private fun cancel(ctx: Context, slot: Slot) {
        ctx.getSystemService(AlarmManager::class.java).cancel(pendingIntent(ctx, slot))
    }

    private fun pendingIntent(ctx: Context, slot: Slot): PendingIntent {
        val intent = Intent(ctx, ReminderReceiver::class.java).putExtra(EXTRA_SLOT, slot.id)
        return PendingIntent.getBroadcast(
            ctx, slot.id, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun nextTrigger(hour: Int): Long {
        val now = ZonedDateTime.now(ZONE)
        var at = now.toLocalDate().atTime(hour, 0).atZone(ZONE)
        if (!at.isAfter(now)) at = at.plusDays(1)
        return at.toInstant().toEpochMilli()
    }

    fun today(): LocalDate = LocalDate.now(ZONE)

    // ── Notifications ───────────────────────────────────────────────────────

    private fun createChannels(ctx: Context) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CH_WATER, "Water reminders", NotificationManager.IMPORTANCE_DEFAULT)
                .apply { description = "Hourly hydration reminders, 6 AM – 9 PM" })
        nm.createNotificationChannel(
            NotificationChannel(CH_GYM, "Gym reminder", NotificationManager.IMPORTANCE_HIGH)
                .apply { description = "Daily 8 PM gym reminder" })
        nm.createNotificationChannel(
            NotificationChannel(CH_LOG, "Daily log reminder", NotificationManager.IMPORTANCE_HIGH)
                .apply { description = "11 PM reminder to log today's data" })
    }

    fun show(ctx: Context, slot: Slot) {
        when (slot.kind) {
            KIND_WATER -> post(
                ctx, NOTIF_WATER, CH_WATER,
                "💧 Drink water",
                if (slot.hour >= 18) "Evening hydration check — had enough water today?"
                else "Time to hydrate! Drink a glass of water.",
                openTab = null,
                // Clear before the next hourly one arrives
                timeoutMs = 55 * 60 * 1000L,
            )
            KIND_GYM -> post(
                ctx, NOTIF_GYM, CH_GYM,
                "🏋️ Gym time!",
                "Have you hit the gym today? Log your session in GymTracker.",
                openTab = "log",
            )
            KIND_LOG -> post(
                ctx, NOTIF_LOG, CH_LOG,
                "📝 Log today's data",
                "Enter calories, weight, waist and mood. Watch data is syncing now.",
                openTab = "log",
            )
        }
    }

    fun showTest(ctx: Context) {
        createChannels(ctx)
        post(ctx, NOTIF_TEST, CH_GYM, "✅ Notifications working!",
            "Water, gym and log reminders are set up 💧🏋️📝", openTab = null)
    }

    private fun post(
        ctx: Context, id: Int, channel: String, title: String, body: String,
        openTab: String?, timeoutMs: Long? = null,
    ) {
        val launch = Intent(ctx, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .apply { if (openTab != null) putExtra(EXTRA_OPEN_TAB, openTab) }
        val tapIntent = PendingIntent.getActivity(
            ctx, id, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = NotificationCompat.Builder(ctx, channel)
            .setSmallIcon(R.drawable.ic_stat_gym)
            .setColor(0xFF6C63FF.toInt())
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setContentIntent(tapIntent)
            .setAutoCancel(true)
        if (timeoutMs != null) builder.setTimeoutAfter(timeoutMs)

        val nm = NotificationManagerCompat.from(ctx)
        if (nm.areNotificationsEnabled()) {
            try {
                nm.notify(id, builder.build())
            } catch (_: SecurityException) {
                // POST_NOTIFICATIONS revoked — nothing to do
            }
        }
    }
}

/** Fires for each reminder slot: shows the notification and re-arms for tomorrow. */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        val slot = Reminders.SLOTS.firstOrNull { it.id == intent.getIntExtra(Reminders.EXTRA_SLOT, -1) }
            ?: return
        if (!Reminders.isEnabled(ctx, slot.kind)) return

        Reminders.show(ctx, slot)
        Reminders.schedule(ctx, slot)

        if (slot.kind == Reminders.KIND_LOG) {
            // Pull today's watch data (and yesterday's final totals) to the backend
            WatchSyncWorker.enqueueNightly(ctx)
        }
    }
}

/** Alarms are wiped on reboot / app update / clock change — re-arm them. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        Reminders.scheduleAll(ctx)
    }
}
