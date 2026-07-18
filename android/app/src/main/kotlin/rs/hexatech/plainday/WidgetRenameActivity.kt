package rs.hexatech.plainday

import android.app.Activity
import android.app.AlertDialog
import android.os.Bundle
import android.widget.EditText
import android.widget.FrameLayout
import org.json.JSONArray
import org.json.JSONObject

/**
 * Tiny overlay for naming the current activity from the widget.
 * Home-screen widgets cannot host a reliable text field, so this dialog is the
 * lightest alternative (no full Flutter UI).
 */
class WidgetRenameActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val flutter = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        val running = PlaindayWidgetActions.runningEntry(flutter)
        if (running == null) {
            finish()
            return
        }

        val button = buttonFor(flutter, running)
        val buttonLabel = button?.optString("label").orEmpty()
        val current = running.optString("label", "")
        val stillDefault = buttonLabel.isNotEmpty() && current == buttonLabel
        val initial = if (stillDefault) "" else current
        val hintNoun = when {
            buttonLabel.isNotBlank() -> buttonLabel.lowercase()
            else -> "activity"
        }

        val pad = (20 * resources.displayMetrics.density).toInt()
        val input = EditText(this).apply {
            setText(initial)
            hint = "Name this $hintNoun"
            setSelection(text.length)
            setPadding(pad, pad / 2, pad, pad / 2)
        }
        val container = FrameLayout(this).apply {
            setPadding(pad, 0, pad, 0)
            addView(input)
        }

        AlertDialog.Builder(this)
            .setTitle(if (stillDefault) "Add name" else "Rename")
            .setView(container)
            .setNegativeButton("Cancel") { _, _ -> finish() }
            .setPositiveButton("Save") { _, _ ->
                val name = input.text?.toString().orEmpty()
                PlaindayWidgetActions.handle(
                    this,
                    android.net.Uri.parse(
                        "plainday://rename_save?name=${android.net.Uri.encode(name)}",
                    ),
                )
                finish()
            }
            .setOnCancelListener { finish() }
            .show()
    }

    private fun buttonFor(flutter: android.content.SharedPreferences, running: JSONObject): JSONObject? {
        val buttonId = running.optString("buttonId")
        if (buttonId.isBlank()) return null
        val activeId = flutter.getString("flutter.active_profile_id", null) ?: return null
        val raw = flutter.getString("flutter.profiles", null) ?: return null
        return try {
            val profiles = JSONArray(raw)
            for (i in 0 until profiles.length()) {
                val p = profiles.getJSONObject(i)
                if (p.optString("id") != activeId) continue
                val buttons = p.optJSONArray("buttons") ?: return null
                for (j in 0 until buttons.length()) {
                    val b = buttons.getJSONObject(j)
                    if (b.optString("id") == buttonId) return b
                }
            }
            null
        } catch (_: Exception) {
            null
        }
    }
}
