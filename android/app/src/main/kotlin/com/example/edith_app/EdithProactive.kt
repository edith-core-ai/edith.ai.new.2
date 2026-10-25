package com.example.edith_app

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
import org.json.JSONArray
import org.json.JSONObject

/**
 * Notifications EDITH sends on her own: daily messages, follow-ups and
 * reminders.
 *
 * Dart decides WHAT to say and WHEN, then calls [schedule]. The phone's
 * alarm clock fires [EdithAlarmReceiver] at that time, even when the app
 * is closed, and [EdithBootReceiver] puts the alarms back after a reboot.
 * Everything is stored in this file's own SharedPreferences, so no Dart
 * code needs to run when the alarm goes off.
 */
object EdithProactive {
    const val CHANNEL_ID = "edith_messages"
    const val ACTION_FIRE = "com.example.edith_app.EDITH_FIRE"
    const val EXTRA_ID = "edith_item_id"
    const val EXTRA_PAYLOAD = "edith_payload"

    private const val PREFS = "edith_proactive_store"
    private const val KEY_ITEMS = "items"
    private const val MAX_ITEMS = 40
    private const val DAY_MS = 24L * 60L * 60L * 1000L
    private const val LATE_LIMIT_MS = 12L * 60L * 60L * 1000L

    class Item(
        val id: Int,
        var at: Long,
        val title: String,
        val text: String,
        val daily: Boolean,
        val kind: String
    )

    // ───────────── storage ─────────────

    private fun load(ctx: Context): MutableList<Item> {
        val raw = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_ITEMS, null)
        val out = mutableListOf<Item>()
        if (raw.isNullOrEmpty()) return out
        try {
            val arr = JSONArray(raw)
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                out.add(
                    Item(
                        o.getInt("id"),
                        o.getLong("at"),
                        o.optString("title", "EDITH"),
                        o.optString("text", ""),
                        o.optBoolean("daily", false),
                        o.optString("kind", "proactive")
                    )
                )
            }
        } catch (e: Exception) {
            // A damaged store is dropped; the app writes fresh items.
        }
        return out
    }

    private fun save(ctx: Context, items: List<Item>) {
        val arr = JSONArray()
        for (item in items) {
            arr.put(
                JSONObject()
                    .put("id", item.id)
                    .put("at", item.at)
                    .put("title", item.title)
                    .put("text", item.text)
                    .put("daily", item.daily)
                    .put("kind", item.kind)
            )
        }
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(KEY_ITEMS, arr.toString()).apply()
    }

    // ───────────── alarms ─────────────

    private fun pendingFlags(): Int {
        var f = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            f = f or PendingIntent.FLAG_IMMUTABLE
        }
        return f
    }

    private fun firePending(ctx: Context, id: Int): PendingIntent {
        val intent = Intent(ctx, EdithAlarmReceiver::class.java)
            .setAction(ACTION_FIRE)
            .putExtra(EXTRA_ID, id)
        return PendingIntent.getBroadcast(ctx, id, intent, pendingFlags())
    }

    fun canExact(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return am.canScheduleExactAlarms()
    }

    /** Returns true when the alarm is exact (to the minute). */
    private fun arm(ctx: Context, item: Item): Boolean {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = firePending(ctx, item.id)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            am.setExact(AlarmManager.RTC_WAKEUP, item.at, pi)
            return true
        }
        if (canExact(ctx)) {
            try {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, item.at, pi)
                return true
            } catch (e: SecurityException) {
                // Exact alarms were switched off: fall through to inexact.
            }
        }
        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, item.at, pi)
        return false
    }

    private fun cancelAlarm(ctx: Context, id: Int) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(firePending(ctx, id))
    }

    // ───────────── public API (called from MainActivity) ─────────────

    fun schedule(ctx: Context, item: Item): Boolean {
        val items = load(ctx)
        items.removeAll { it.id == item.id }
        items.add(item)
        items.sortBy { it.at }
        while (items.size > MAX_ITEMS) {
            val dropped = items.removeAt(items.size - 1)
            cancelAlarm(ctx, dropped.id)
        }
        save(ctx, items)
        return arm(ctx, item)
    }

    fun cancel(ctx: Context, id: Int) {
        val items = load(ctx)
        items.removeAll { it.id == id }
        save(ctx, items)
        cancelAlarm(ctx, id)
    }

    fun list(ctx: Context): List<Map<String, Any>> {
        return load(ctx).sortedBy { it.at }.map {
            mapOf(
                "id" to it.id,
                "at" to it.at,
                "title" to it.title,
                "text" to it.text,
                "daily" to it.daily,
                "kind" to it.kind
            )
        }
    }

    // ───────────── firing ─────────────

    fun fire(ctx: Context, id: Int) {
        val items = load(ctx)
        val item = items.firstOrNull { it.id == id } ?: return
        notify(ctx, item)
        if (item.daily) {
            val now = System.currentTimeMillis()
            var next = item.at + DAY_MS
            while (next <= now) next += DAY_MS
            item.at = next
            save(ctx, items)
            arm(ctx, item)
        } else {
            items.removeAll { it.id == id }
            save(ctx, items)
        }
    }

    /** After a reboot or an app update: put every alarm back. */
    fun rearmAll(ctx: Context) {
        val now = System.currentTimeMillis()
        val items = load(ctx)
        val keep = mutableListOf<Item>()
        for (item in items) {
            if (item.at <= now) {
                if (item.daily) {
                    var next = item.at + DAY_MS
                    while (next <= now) next += DAY_MS
                    item.at = next
                } else {
                    // Missed while the phone was off: say it now unless it is
                    // very old.
                    if (now - item.at < LATE_LIMIT_MS) notify(ctx, item)
                    continue
                }
            }
            keep.add(item)
        }
        save(ctx, keep)
        for (item in keep) arm(ctx, item)
    }

    // ───────────── notification ─────────────

    private fun ensureChannel(ctx: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "EDITH messages",
            NotificationManager.IMPORTANCE_HIGH
        )
        channel.description = "Messages and reminders from EDITH"
        nm.createNotificationChannel(channel)
    }

    private fun notify(ctx: Context, item: Item) {
        if (!NotificationManagerCompat.from(ctx).areNotificationsEnabled()) return
        ensureChannel(ctx)

        val launch = Intent(ctx, MainActivity::class.java)
        launch.addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
        )
        launch.putExtra(
            EXTRA_PAYLOAD,
            JSONObject().put("kind", item.kind).put("text", item.text).toString()
        )
        val tap = PendingIntent.getActivity(ctx, item.id, launch, pendingFlags())

        val notification = NotificationCompat.Builder(ctx, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_edith)
            .setColor(0xFF2FE0FF.toInt())
            .setContentTitle(item.title)
            .setContentText(item.text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(item.text))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setAutoCancel(true)
            .setContentIntent(tap)
            .build()
        try {
            NotificationManagerCompat.from(ctx).notify(item.id, notification)
        } catch (e: SecurityException) {
            // Notification permission was taken away: nothing to do.
        }
    }
}

/** The alarm clock calls this when a scheduled message is due. */
class EdithAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == EdithProactive.ACTION_FIRE) {
            EdithProactive.fire(context, intent.getIntExtra(EdithProactive.EXTRA_ID, -1))
        }
    }
}

/** Puts the alarms back after a reboot, an app update, or when the exact-alarm permission changes. */
class EdithBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        EdithProactive.rearmAll(context)
    }
}
