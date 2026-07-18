package rs.hexatech.plainday

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.widget.Toast
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

/**
 * Handles widget button taps on the main thread without opening the app.
 * Updates Flutter SharedPreferences + HomeWidgetPreferences, then refreshes the widget.
 */
object PlaindayWidgetActions {
    private const val FLUTTER_PREFS = "FlutterSharedPreferences"
    private const val HOME_PREFS = "HomeWidgetPreferences"
    private const val KEY_DAY = "flutter.day_started"
    private const val KEY_ENTRIES = "flutter.activity_entries"
    private const val KEY_STACK_JSON = "flutter.paused_stack_json"
    private const val KEY_PROFILES = "flutter.profiles"
    private const val KEY_ACTIVE = "flutter.active_profile_id"
    private const val KEY_REVISION = "flutter.widget_revision"

    fun handle(context: Context, uri: Uri?): Boolean {
        if (uri == null) return false
        val host = uri.host ?: return false
        val flutter = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
        val home = context.getSharedPreferences(HOME_PREFS, Context.MODE_PRIVATE)

        val message = when (host) {
            "start_day" -> startDay(flutter, home)
            "end_day" -> endDay(flutter, home)
            "button" -> {
                val buttonId = uri.pathSegments.firstOrNull().orEmpty()
                if (buttonId.isEmpty()) "Unknown action"
                else toggleButton(flutter, home, buttonId)
            }
            "rename_save" -> {
                val name = uri.getQueryParameter("name").orEmpty()
                renameCurrent(flutter, home, name)
            }
            else -> return false
        }

        bumpRevision(flutter)
        refreshWidget(context)
        Handler(Looper.getMainLooper()).post {
            Toast.makeText(context.applicationContext, message, Toast.LENGTH_SHORT).show()
        }
        return true
    }

    fun runningEntry(flutter: SharedPreferences): JSONObject? {
        val entries = entriesArray(flutter)
        for (i in 0 until entries.length()) {
            val e = entries.getJSONObject(i)
            if (isRunning(e)) return e
        }
        return null
    }

    private fun startDay(flutter: SharedPreferences, home: SharedPreferences): String {
        if (flutter.getBoolean(KEY_DAY, false)) return "Day already on"
        val profile = activeProfile(flutter) ?: return "No profile"
        val now = isoNow()
        val entries = entriesArray(flutter)
        entries.put(
            dayMarker(
                profileId = profile.getString("id"),
                profileName = profile.optString("name", "Plainday"),
                kind = "dayStart",
                at = now,
            ),
        )
        flutter.edit()
            .putBoolean(KEY_DAY, true)
            .putString(KEY_ENTRIES, entries.toString())
            .putString(KEY_STACK_JSON, "[]")
            .apply()
        writeHomeGlance(flutter, home, profile)
        return "Day started"
    }

    private fun endDay(flutter: SharedPreferences, home: SharedPreferences): String {
        if (!flutter.getBoolean(KEY_DAY, false)) return "Day already off"
        val profile = activeProfile(flutter) ?: return "No profile"
        val now = isoNow()
        val nowMs = System.currentTimeMillis()
        val entries = entriesArray(flutter)
        for (i in 0 until entries.length()) {
            val e = entries.getJSONObject(i)
            if (!e.has("endedAt") || e.isNull("endedAt")) {
                e.put("accumulatedSeconds", elapsedSeconds(e, nowMs))
                e.put("endedAt", now)
                e.put("pausedAt", JSONObject.NULL)
            }
        }
        entries.put(
            dayMarker(
                profileId = profile.getString("id"),
                profileName = profile.optString("name", "Plainday"),
                kind = "dayEnd",
                at = now,
            ),
        )
        flutter.edit()
            .putBoolean(KEY_DAY, false)
            .putString(KEY_ENTRIES, entries.toString())
            .putString(KEY_STACK_JSON, "[]")
            .apply()
        writeHomeGlance(flutter, home, profile)
        return "Day ended"
    }

    private fun toggleButton(
        flutter: SharedPreferences,
        home: SharedPreferences,
        buttonId: String,
    ): String {
        val profile = activeProfile(flutter) ?: return "No profile"
        val buttons = profile.optJSONArray("buttons") ?: return "No actions"
        val button = findButton(buttons, buttonId) ?: return "Unknown action"

        val running = runningEntry(flutter)
        if (running != null && running.optString("buttonId") == buttonId) {
            endCurrentAndResume(flutter)
            writeHomeGlance(flutter, home, profile)
            return "Ended ${button.optString("label", "activity")}"
        }

        startButton(flutter, button, profile)
        writeHomeGlance(flutter, home, profile)
        return "Started ${button.optString("label", "activity")}"
    }

    private fun startButton(
        flutter: SharedPreferences,
        button: JSONObject,
        profile: JSONObject,
    ) {
        val now = isoNow()
        val nowMs = System.currentTimeMillis()
        val entries = entriesArray(flutter)
        val stack = stackArray(flutter)
        val buttonId = button.optString("id")

        if (!flutter.getBoolean(KEY_DAY, false)) {
            entries.put(
                dayMarker(
                    profileId = profile.getString("id"),
                    profileName = profile.optString("name", "Plainday"),
                    kind = "dayStart",
                    at = now,
                ),
            )
        }

        val pausesOthers = button.optBoolean("pausesOthers", true)
        if (pausesOthers) {
            for (i in 0 until entries.length()) {
                val e = entries.getJSONObject(i)
                if (isRunning(e)) {
                    e.put("accumulatedSeconds", elapsedSeconds(e, nowMs))
                    e.put("pausedAt", now)
                    stack.put(e.getString("id"))
                }
            }
        }

        val isBreak = button.optBoolean("isBreak", false) ||
            button.optString("activityKind") == "breakTime"
        val kind = if (isBreak) "breakTime" else "task"
        val label = if (isBreak) {
            resolveBreakLabel(profile, button) ?: migrateButtonLabel(button.optString("label", "Break"))
        } else {
            migrateButtonLabel(button.optString("label", "Activity"))
        }
        entries.put(
            JSONObject()
                .put("id", UUID.randomUUID().toString())
                .put("profileId", profile.getString("id"))
                .put("buttonId", buttonId)
                .put("label", label)
                .put("kind", kind)
                .put("startedAt", now)
                .put("endedAt", JSONObject.NULL)
                .put("pausedAt", JSONObject.NULL)
                .put("accumulatedSeconds", 0),
        )

        flutter.edit()
            .putBoolean(KEY_DAY, true)
            .putString(KEY_ENTRIES, entries.toString())
            .putString(KEY_STACK_JSON, stack.toString())
            .apply()
    }

    private fun endCurrentAndResume(flutter: SharedPreferences) {
        val now = isoNow()
        val nowMs = System.currentTimeMillis()
        val entries = entriesArray(flutter)
        val stack = stackArray(flutter)

        var endedId: String? = null
        for (i in 0 until entries.length()) {
            val e = entries.getJSONObject(i)
            if (isRunning(e)) {
                e.put("accumulatedSeconds", elapsedSeconds(e, nowMs))
                e.put("endedAt", now)
                e.put("pausedAt", JSONObject.NULL)
                endedId = e.optString("id")
                break
            }
        }

        // Resume previous from stack (skip the one we just ended).
        while (stack.length() > 0) {
            val prevId = stack.getString(stack.length() - 1)
            stack.remove(stack.length() - 1)
            if (prevId == endedId) continue
            val idx = indexOfEntry(entries, prevId)
            if (idx == -1) continue
            val prev = entries.getJSONObject(idx)
            if (!prev.isNull("endedAt")) continue
            if (!prev.isNull("pausedAt") || isRunning(prev)) {
                prev.put("startedAt", now)
                prev.put("pausedAt", JSONObject.NULL)
                // keep accumulatedSeconds
                break
            }
        }

        flutter.edit()
            .putString(KEY_ENTRIES, entries.toString())
            .putString(KEY_STACK_JSON, stack.toString())
            .apply()
    }

    fun renameCurrent(
        flutter: SharedPreferences,
        home: SharedPreferences,
        name: String,
    ): String {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return "Name required"
        val profile = activeProfile(flutter) ?: return "No profile"
        val entries = entriesArray(flutter)
        var found = false
        for (i in 0 until entries.length()) {
            val e = entries.getJSONObject(i)
            if (isRunning(e)) {
                e.put("label", trimmed)
                found = true
                break
            }
        }
        if (!found) return "Nothing running"
        flutter.edit().putString(KEY_ENTRIES, entries.toString()).apply()
        writeHomeGlance(flutter, home, profile)
        return "Named “$trimmed”"
    }

    private fun writeHomeGlance(
        flutter: SharedPreferences,
        home: SharedPreferences,
        profile: JSONObject,
    ) {
        val dayOn = flutter.getBoolean(KEY_DAY, false)
        val running = runningEntry(flutter)
        val buttons = profile.optJSONArray("buttons")
        val activeButtonId = running?.optString("buttonId")
        val activeButton =
            if (activeButtonId.isNullOrBlank() || buttons == null) null
            else findButton(buttons, activeButtonId)
        val label = running?.optString("label")
            ?: if (dayOn) "Nothing running" else "Tap to start day"
        val canName = running != null && activeButton?.optBoolean("requiresName", false) == true
        val buttonLabel = activeButton?.optString("label").orEmpty()
        val nameButton = when {
            !canName -> ""
            label == buttonLabel -> "Add name"
            else -> "Edit name"
        }

        val edit = home.edit()
            .putString("profile_name", profile.optString("name", "Plainday"))
            .putString("day_status", if (dayOn) "Day on" else "Day off")
            .putString("current_label", label)
            .putString(
                "current_elapsed",
                if (running == null) "--:--" else formatElapsed(elapsedSeconds(running, System.currentTimeMillis())),
            )
            .putString("hint", if (dayOn) "Logging" else "Ready when you are")
            .putBoolean("can_name", canName)
            .putString("name_button", nameButton)
            .putString("day_button_label", if (dayOn) "End day" else "Start day")
            .putString("day_button_action", if (dayOn) "end_day" else "start_day")
            .remove("toast_message")

        val count = minOf(buttons?.length() ?: 0, 4)
        edit.putInt("action_count", count)
        for (i in 0 until 4) {
            if (i < count && buttons != null) {
                val b = buttons.getJSONObject(i)
                val id = b.optString("id")
                val base = b.optString("label", "Action")
                val active = id == activeButtonId
                val shown = if (active) "End $base" else base
                edit.putString("action_${i}_label", shown)
                edit.putString("action_${i}_id", id)
            } else {
                edit.putString("action_${i}_label", "")
                edit.putString("action_${i}_id", "")
            }
        }
        edit.commit()
    }

    fun refreshWidget(context: Context) {
        val mgr = AppWidgetManager.getInstance(context)
        val cn = ComponentName(context, PlaindayWidgetProvider::class.java)
        val ids = mgr.getAppWidgetIds(cn)
        if (ids.isEmpty()) return
        val intent = Intent(context, PlaindayWidgetProvider::class.java).apply {
            action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
        }
        context.sendBroadcast(intent)
    }

    private fun bumpRevision(flutter: SharedPreferences) {
        flutter.edit()
            .putString(KEY_REVISION, System.currentTimeMillis().toString())
            .apply()
    }

    private fun activeProfile(flutter: SharedPreferences): JSONObject? {
        val activeId = flutter.getString(KEY_ACTIVE, null) ?: return null
        val raw = flutter.getString(KEY_PROFILES, null) ?: return null
        val profiles = JSONArray(raw)
        for (i in 0 until profiles.length()) {
            val p = profiles.getJSONObject(i)
            if (p.optString("id") == activeId) return p
        }
        return null
    }

    private fun findButton(buttons: JSONArray, buttonId: String): JSONObject? {
        for (i in 0 until buttons.length()) {
            val b = buttons.getJSONObject(i)
            if (b.optString("id") == buttonId) return b
        }
        return null
    }

    private fun entriesArray(flutter: SharedPreferences): JSONArray {
        val raw = flutter.getString(KEY_ENTRIES, null) ?: return JSONArray()
        return try {
            JSONArray(raw)
        } catch (_: Exception) {
            JSONArray()
        }
    }

    private fun stackArray(flutter: SharedPreferences): JSONArray {
        val raw = flutter.getString(KEY_STACK_JSON, null) ?: return JSONArray()
        return try {
            JSONArray(raw)
        } catch (_: Exception) {
            JSONArray()
        }
    }

    private fun indexOfEntry(entries: JSONArray, id: String): Int {
        for (i in 0 until entries.length()) {
            if (entries.getJSONObject(i).optString("id") == id) return i
        }
        return -1
    }

    private fun isRunning(e: JSONObject): Boolean {
        return e.isNull("endedAt") && e.isNull("pausedAt")
    }

    fun elapsedSeconds(e: JSONObject, nowMs: Long = System.currentTimeMillis()): Int {
        val acc = e.optInt("accumulatedSeconds", 0)
        if (!e.isNull("endedAt") || !e.isNull("pausedAt")) return acc
        val startedMs = parseIsoMs(e.optString("startedAt")) ?: return acc
        val extra = ((nowMs - startedMs) / 1000L).toInt().coerceAtLeast(0)
        return acc + extra
    }

    private fun parseIsoMs(iso: String): Long? {
        if (iso.isBlank()) return null
        return try {
            val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
            fmt.timeZone = TimeZone.getTimeZone("UTC")
            fmt.parse(iso)?.time
        } catch (_: Exception) {
            try {
                // Dart sometimes omits millis.
                val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
                fmt.timeZone = TimeZone.getTimeZone("UTC")
                fmt.parse(iso)?.time
            } catch (_: Exception) {
                null
            }
        }
    }

    private fun formatElapsed(totalSeconds: Int): String {
        val m = totalSeconds / 60
        val s = totalSeconds % 60
        return String.format(Locale.US, "%02d:%02d", m, s)
    }

    private fun dayMarker(
        profileId: String,
        profileName: String,
        kind: String,
        at: String,
    ): JSONObject {
        val isStart = kind == "dayStart"
        return JSONObject()
            .put("id", UUID.randomUUID().toString())
            .put("profileId", profileId)
            .put("buttonId", if (isStart) "__day_start__" else "__day_end__")
            .put(
                "label",
                if (isStart) "Day started — $profileName" else "Day ended — $profileName",
            )
            .put("kind", kind)
            .put("startedAt", at)
            .put("endedAt", at)
            .put("pausedAt", JSONObject.NULL)
            .put("accumulatedSeconds", 0)
    }

    private fun resolveBreakLabel(profile: JSONObject, button: JSONObject): String? {
        val breaks = profile.optJSONArray("breaks") ?: return null
        if (breaks.length() == 0) return null
        val linkedId = button.optString("breakId", "")
        if (linkedId.isNotBlank()) {
            for (i in 0 until breaks.length()) {
                val b = breaks.getJSONObject(i)
                if (b.optString("id") == linkedId) return b.optString("label").ifBlank { null }
            }
        }
        // Next / current by local clock (minutes from midnight).
        val cal = java.util.Calendar.getInstance()
        val minutes = cal.get(java.util.Calendar.HOUR_OF_DAY) * 60 + cal.get(java.util.Calendar.MINUTE)
        var current: JSONObject? = null
        var upcoming: JSONObject? = null
        var first: JSONObject? = null
        for (i in 0 until breaks.length()) {
            val b = breaks.getJSONObject(i)
            if (first == null) first = b
            val start = b.optInt("startMinutes", 0)
            val end = b.optInt("endMinutes", start)
            if (minutes in start..end) {
                current = b
                break
            }
            if (start > minutes && (upcoming == null || start < upcoming.optInt("startMinutes"))) {
                upcoming = b
            }
        }
        val chosen = current ?: upcoming ?: first
        return chosen?.optString("label")?.ifBlank { null }
    }

    private fun migrateButtonLabel(raw: String): String = when (raw) {
        "Add task" -> "Task"
        "Add meeting" -> "Meeting"
        else -> raw
    }

    private fun isoNow(): String {
        val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
        fmt.timeZone = TimeZone.getTimeZone("UTC")
        return fmt.format(Date())
    }
}
