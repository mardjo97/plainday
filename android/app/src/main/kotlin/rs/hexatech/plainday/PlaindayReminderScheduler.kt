package rs.hexatech.plainday

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * Single place for reminder alarms. Reads FlutterSharedPreferences and talks
 * to AlarmManager — works after widget taps and boot without a Flutter engine.
 */
object PlaindayReminderScheduler {
    private const val TAG = "PlaindayReminders"
    private const val FLUTTER_PREFS = "FlutterSharedPreferences"
    private const val KEY_DAY = "flutter.day_started"
    private const val KEY_PROFILES = "flutter.profiles"
    private const val KEY_ACTIVE = "flutter.active_profile_id"
    private const val KEY_ALARM_IDS = "flutter.native_alarm_ids"
    private const val KEY_STATUS = "flutter.native_reminder_status"
    private const val MIN_RESCHEDULE_GAP_MS = 2_500L
    const val CHANNEL_ID = "plainday_reminders"

    const val EXTRA_TITLE = "title"
    const val EXTRA_BODY = "body"
    const val EXTRA_PAYLOAD = "payload"
    const val ACTION_FIRE = "rs.hexatech.plainday.action.ALARM_FIRE"
    const val ACTION_SNOOZE = "rs.hexatech.plainday.action.ALARM_SNOOZE"

    @Volatile private var lastRescheduleAt = 0L
    @Volatile private var lastStatus: Status? = null

    data class Status(
        val scheduled: Int = 0,
        val intervals: Int = 0,
        val intervalConfigs: Int = 0,
        val skipReason: String? = null,
        val exactAllowed: Boolean = false,
        val usedInexact: Boolean = false,
    )

    fun reschedule(context: Context, force: Boolean = false): Status {
        val nowMs = System.currentTimeMillis()
        if (!force && lastStatus != null && nowMs - lastRescheduleAt < MIN_RESCHEDULE_GAP_MS) {
            return lastStatus!!
        }
        lastRescheduleAt = nowMs
        ensureChannel(context)
        val flutter = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
        cancelAll(context, flutter)

        val exactAllowed = canScheduleExact(context)
        val profile = activeProfile(flutter)
        if (profile == null) {
            return persistStatus(
                flutter,
                Status(skipReason = "No active profile", exactAllowed = exactAllowed),
            )
        }

        val dayStarted = flutter.getBoolean(KEY_DAY, false)
        val intervalConfigs = countIntervalConfigs(profile)
        val rules = profile.optJSONObject("rules")
        val silenceWhenInactive = rules?.optBoolean("silenceWhenInactive", false) ?: false

        val now = Calendar.getInstance()
        val alarmMgr = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val scheduledIds = mutableListOf<Int>()
        var intervals = 0
        var usedInexact = false
        var nextId = 3000

        fun schedule(
            whenMs: Long,
            title: String,
            body: String,
            payload: String,
            precise: Boolean,
        ): Boolean {
            if (whenMs <= System.currentTimeMillis() + 5_000L) return false
            val id = nextId++
            val ok = setAlarm(
                context = context,
                alarmMgr = alarmMgr,
                requestCode = id,
                triggerAtMs = whenMs,
                title = title,
                body = body,
                payload = payload,
                preferExact = precise || exactAllowed,
                exactAllowed = exactAllowed,
            )
            if (ok.first) {
                scheduledIds.add(id)
                if (ok.second) usedInexact = true
                return true
            }
            return false
        }

        if (!dayStarted) {
            if (silenceWhenInactive) {
                return persistStatus(
                    flutter,
                    Status(
                        intervalConfigs = intervalConfigs,
                        skipReason = "Day off — reminders cleared",
                        exactAllowed = exactAllowed,
                    ),
                )
            }
            if (!isActiveDay(profile, now)) {
                val reason =
                    "Day off / inactive weekday — reminders cleared (${profile.optString("name")})"
                Log.i(TAG, reason)
                return persistStatus(
                    flutter,
                    Status(
                        intervalConfigs = intervalConfigs,
                        skipReason = reason,
                        exactAllowed = exactAllowed,
                    ),
                )
            }
            scheduleStartReminders(profile, now, ::schedule)
            flutter.edit().putString(KEY_ALARM_IDS, JSONArray(scheduledIds).toString()).apply()
            return persistStatus(
                flutter,
                Status(
                    scheduled = scheduledIds.size,
                    intervalConfigs = intervalConfigs,
                    skipReason = "Day off — intervals cleared; start nudge kept if still upcoming",
                    exactAllowed = exactAllowed,
                    usedInexact = usedInexact,
                ),
            )
        }

        if (!isActiveDay(profile, now)) {
            Log.i(TAG, "day started on inactive weekday — scheduling anyway")
        }

        scheduleEndReminders(profile, now, ::schedule)
        scheduleBreakReminders(profile, now, ::schedule)
        intervals = scheduleIntervals(profile, now, ::schedule)

        flutter.edit().putString(KEY_ALARM_IDS, JSONArray(scheduledIds).toString()).apply()

        val skip = when {
            intervalConfigs == 0 -> "No enabled interval reminders on ${profile.optString("name")}"
            intervals == 0 ->
                "Interval configs found but none scheduled (check exact-alarm / time window)"
            !exactAllowed || usedInexact ->
                "Scheduled with limited exactness — allow exact alarms for reliable intervals"
            else -> null
        }

        return persistStatus(
            flutter,
            Status(
                scheduled = scheduledIds.size,
                intervals = intervals,
                intervalConfigs = intervalConfigs,
                skipReason = skip,
                exactAllowed = exactAllowed,
                usedInexact = usedInexact,
            ),
        )
    }

    fun snoozeStandUp(context: Context, minutes: Int = 10) {
        ensureChannel(context)
        val whenMs = System.currentTimeMillis() + minutes * 60_000L
        val alarmMgr = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val exactAllowed = canScheduleExact(context)
        setAlarm(
            context = context,
            alarmMgr = alarmMgr,
            requestCode = 2999,
            triggerAtMs = whenMs,
            title = "Stand up",
            body = "Snoozed reminder — take a short stretch.",
            payload = "stand_up",
            preferExact = true,
            exactAllowed = exactAllowed,
        )
    }

    fun canScheduleExact(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val alarmMgr = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return alarmMgr.canScheduleExactAlarms()
    }

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val mgr = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val existing = mgr.getNotificationChannel(CHANNEL_ID)
        if (existing != null) return
        mgr.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Reminders",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Profile start/end, breaks, and stand-up nudges"
            },
        )
    }

    private fun cancelAll(context: Context, flutter: SharedPreferences) {
        val alarmMgr = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val raw = flutter.getString(KEY_ALARM_IDS, null)
        val ids = mutableSetOf(2999) // snooze slot
        if (raw != null) {
            try {
                val arr = JSONArray(raw)
                for (i in 0 until arr.length()) ids.add(arr.getInt(i))
            } catch (_: Exception) {
            }
        }
        for (id in ids) {
            val pi = firePendingIntent(context, id, "", "", "", cancelOnly = true)
            alarmMgr.cancel(pi)
            pi.cancel()
        }
        flutter.edit().remove(KEY_ALARM_IDS).apply()
    }

    /** Returns Pair(success, usedInexact). */
    private fun setAlarm(
        context: Context,
        alarmMgr: AlarmManager,
        requestCode: Int,
        triggerAtMs: Long,
        title: String,
        body: String,
        payload: String,
        preferExact: Boolean,
        exactAllowed: Boolean,
    ): Pair<Boolean, Boolean> {
        val pi = firePendingIntent(context, requestCode, title, body, payload)
        return try {
            when {
                preferExact && exactAllowed -> {
                    val show = PendingIntent.getActivity(
                        context,
                        requestCode + 100_000,
                        Intent(context, MainActivity::class.java).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                                Intent.FLAG_ACTIVITY_SINGLE_TOP
                        },
                        pendingFlags(),
                    )
                    alarmMgr.setAlarmClock(
                        AlarmManager.AlarmClockInfo(triggerAtMs, show),
                        pi,
                    )
                    Pair(true, false)
                }
                exactAllowed -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        alarmMgr.setExactAndAllowWhileIdle(
                            AlarmManager.RTC_WAKEUP,
                            triggerAtMs,
                            pi,
                        )
                    } else {
                        @Suppress("DEPRECATION")
                        alarmMgr.setExact(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
                    }
                    Pair(true, false)
                }
                else -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        alarmMgr.setAndAllowWhileIdle(
                            AlarmManager.RTC_WAKEUP,
                            triggerAtMs,
                            pi,
                        )
                    } else {
                        @Suppress("DEPRECATION")
                        alarmMgr.set(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
                    }
                    Pair(true, true)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "setAlarm failed: $e")
            Pair(false, true)
        }
    }

    private fun firePendingIntent(
        context: Context,
        requestCode: Int,
        title: String,
        body: String,
        payload: String,
        cancelOnly: Boolean = false,
    ): PendingIntent {
        val intent = Intent(context, PlaindayAlarmReceiver::class.java).apply {
            action = ACTION_FIRE
            if (!cancelOnly) {
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_BODY, body)
                putExtra(EXTRA_PAYLOAD, payload)
            }
            // Unique data so PendingIntents don't collide.
            data = android.net.Uri.parse("plainday-alarm://$requestCode")
        }
        return PendingIntent.getBroadcast(context, requestCode, intent, pendingFlags())
    }

    private fun pendingFlags(): Int {
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return flags
    }

    private fun activeProfile(flutter: SharedPreferences): JSONObject? {
        val activeId = flutter.getString(KEY_ACTIVE, null) ?: return null
        val raw = flutter.getString(KEY_PROFILES, null) ?: return null
        return try {
            val profiles = JSONArray(raw)
            for (i in 0 until profiles.length()) {
                val p = profiles.getJSONObject(i)
                if (p.optString("id") == activeId) return p
            }
            null
        } catch (_: Exception) {
            null
        }
    }

    private fun countIntervalConfigs(profile: JSONObject): Int {
        val reminders = profile.optJSONArray("reminders") ?: return 0
        var n = 0
        for (i in 0 until reminders.length()) {
            val r = reminders.getJSONObject(i)
            if (!r.optBoolean("enabled", true)) continue
            if (r.optString("kind") != "interval") continue
            if (r.optInt("intervalMinutes", 0) > 0) n++
        }
        return n
    }

    private fun isActiveDay(profile: JSONObject, now: Calendar): Boolean {
        val days = profile.optJSONArray("activeDays") ?: return true
        val dartWeekday = dartWeekday(now)
        for (i in 0 until days.length()) {
            if (days.getInt(i) == dartWeekday) return true
        }
        return false
    }

    /** Dart DateTime.weekday: 1=Mon … 7=Sun */
    private fun dartWeekday(cal: Calendar): Int {
        return when (cal.get(Calendar.DAY_OF_WEEK)) {
            Calendar.MONDAY -> 1
            Calendar.TUESDAY -> 2
            Calendar.WEDNESDAY -> 3
            Calendar.THURSDAY -> 4
            Calendar.FRIDAY -> 5
            Calendar.SATURDAY -> 6
            else -> 7
        }
    }

    private fun onDayMs(day: Calendar, minutesFromMidnight: Int): Long {
        val c = day.clone() as Calendar
        val h = (minutesFromMidnight / 60).coerceIn(0, 23)
        val m = (minutesFromMidnight % 60).coerceIn(0, 59)
        c.set(Calendar.HOUR_OF_DAY, h)
        c.set(Calendar.MINUTE, m)
        c.set(Calendar.SECOND, 0)
        c.set(Calendar.MILLISECOND, 0)
        return c.timeInMillis
    }

    private fun scheduleStartReminders(
        profile: JSONObject,
        now: Calendar,
        schedule: (Long, String, String, String, Boolean) -> Boolean,
    ) {
        val reminders = profile.optJSONArray("reminders") ?: return
        val start = profile.optInt("startMinutes", 9 * 60)
        val name = profile.optString("name", "Plainday")
        for (i in 0 until reminders.length()) {
            val r = reminders.getJSONObject(i)
            if (!r.optBoolean("enabled", true)) continue
            if (r.optString("kind") != "atProfileStart") continue
            val whenMs = onDayMs(now, start + r.optInt("offsetMinutes", 0))
            schedule(
                whenMs,
                r.optString("label", "Start day"),
                "Start your $name day?",
                r.optString("actionId", "start_day").ifBlank { "start_day" },
                false,
            )
        }
    }

    private fun scheduleEndReminders(
        profile: JSONObject,
        now: Calendar,
        schedule: (Long, String, String, String, Boolean) -> Boolean,
    ) {
        val reminders = profile.optJSONArray("reminders") ?: return
        val end = profile.optInt("endMinutes", 17 * 60)
        val name = profile.optString("name", "Plainday")
        for (i in 0 until reminders.length()) {
            val r = reminders.getJSONObject(i)
            if (!r.optBoolean("enabled", true)) continue
            if (r.optString("kind") != "atProfileEnd") continue
            val whenMs = onDayMs(now, end + r.optInt("offsetMinutes", 0))
            schedule(
                whenMs,
                r.optString("label", "End day"),
                "Wrap up your $name day?",
                r.optString("actionId", "end_day").ifBlank { "end_day" },
                false,
            )
        }
    }

    private fun scheduleBreakReminders(
        profile: JSONObject,
        now: Calendar,
        schedule: (Long, String, String, String, Boolean) -> Boolean,
    ) {
        val reminders = profile.optJSONArray("reminders") ?: return
        val breaks = profile.optJSONArray("breaks") ?: return
        for (i in 0 until reminders.length()) {
            val r = reminders.getJSONObject(i)
            if (!r.optBoolean("enabled", true)) continue
            if (r.optString("kind") != "relativeToBreak") continue
            val breakId = r.optString("breakId", "")
            if (breakId.isBlank()) continue
            var window: JSONObject? = null
            for (j in 0 until breaks.length()) {
                val b = breaks.getJSONObject(j)
                if (b.optString("id") == breakId) {
                    window = b
                    break
                }
            }
            if (window == null) continue
            val label = r.optString("label", "Break")
            val actionId = r.optString("actionId", "")
            val isReturn = actionId == "return_from_break" ||
                label.lowercase().contains("return")
            val anchor = if (isReturn) {
                window.optInt("endMinutes")
            } else {
                window.optInt("startMinutes")
            }
            val whenMs = onDayMs(now, anchor + r.optInt("offsetMinutes", 0))
            val payload = actionId.ifBlank {
                if (isReturn) "return_from_break" else "go_to_break"
            }
            val body = if (isReturn) {
                "Ready to return from ${window.optString("label")}?"
            } else {
                "Time for ${window.optString("label")} soon."
            }
            schedule(whenMs, label, body, payload, false)
        }
    }

    private fun scheduleIntervals(
        profile: JSONObject,
        now: Calendar,
        schedule: (Long, String, String, String, Boolean) -> Boolean,
    ): Int {
        val reminders = profile.optJSONArray("reminders") ?: return 0
        val endMinutes = profile.optInt("endMinutes", 17 * 60)
        var windowEnd = onDayMs(now, endMinutes)
        val minWindow = System.currentTimeMillis() + 8L * 60L * 60L * 1000L
        if (windowEnd <= System.currentTimeMillis() + 2L * 60L * 1000L) {
            windowEnd = minWindow
        }

        var total = 0
        for (i in 0 until reminders.length()) {
            val r = reminders.getJSONObject(i)
            if (!r.optBoolean("enabled", true)) continue
            if (r.optString("kind") != "interval") continue
            val every = r.optInt("intervalMinutes", 0)
            if (every <= 0) continue
            var cursor = System.currentTimeMillis() + every * 60_000L
            var count = 0
            val maxCount = when {
                every <= 2 -> 45
                every <= 5 -> 24
                else -> 16
            }
            while (cursor <= windowEnd && count < maxCount) {
                val ok = schedule(
                    cursor,
                    r.optString("label", "Stand up"),
                    "Quick stretch — then back to it.",
                    "stand_up",
                    true,
                )
                if (ok) total++
                cursor += every * 60_000L
                count++
            }
        }
        return total
    }

    private fun persistStatus(flutter: SharedPreferences, status: Status): Status {
        val json = JSONObject()
            .put("scheduled", status.scheduled)
            .put("intervals", status.intervals)
            .put("intervalConfigs", status.intervalConfigs)
            .put("skipReason", status.skipReason ?: JSONObject.NULL)
            .put("exactAllowed", status.exactAllowed)
            .put("usedInexact", status.usedInexact)
            .put("at", System.currentTimeMillis())
        flutter.edit().putString(KEY_STATUS, json.toString()).apply()
        Log.i(
            TAG,
            "reschedule: scheduled=${status.scheduled} intervals=${status.intervals} " +
                "exact=${status.exactAllowed} reason=${status.skipReason}",
        )
        lastStatus = status
        return status
    }
}
