package rs.hexatech.plainday

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import android.widget.Toast
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class PlaindayWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val toast = widgetData.getString("toast_message", null)
        if (!toast.isNullOrBlank()) {
            Handler(Looper.getMainLooper()).post {
                Toast.makeText(context.applicationContext, toast, Toast.LENGTH_SHORT).show()
            }
            widgetData.edit().remove("toast_message").apply()
        }

        val actionViewIds = intArrayOf(
            R.id.widget_action_0,
            R.id.widget_action_1,
            R.id.widget_action_2,
            R.id.widget_action_3,
        )

        val flutter = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

        appWidgetIds.forEach { widgetId ->
            val canName = widgetData.getBoolean("can_name", false)
            val actionCount = widgetData.getInt("action_count", 0)
            val views = RemoteViews(context.packageName, R.layout.plainday_widget).apply {
                setTextViewText(
                    R.id.widget_profile,
                    widgetData.getString("profile_name", "Plainday") ?: "Plainday",
                )
                setTextViewText(
                    R.id.widget_status,
                    widgetData.getString("day_status", "Day off") ?: "Day off",
                )
                setTextViewText(
                    R.id.widget_current,
                    widgetData.getString("current_label", "Tap to open") ?: "Tap to open",
                )
                applyElapsed(this, flutter)
                setTextViewText(
                    R.id.widget_hint,
                    widgetData.getString("hint", "") ?: "",
                )

                val openIntent = launchIntent(context, Uri.parse("plainday://open"), 1001)
                setOnClickPendingIntent(R.id.widget_container, openIntent)
                setOnClickPendingIntent(R.id.widget_open_button, openIntent)
                setOnClickPendingIntent(R.id.widget_profile, openIntent)
                setOnClickPendingIntent(R.id.widget_status, openIntent)
                setOnClickPendingIntent(R.id.widget_current, openIntent)
                setOnClickPendingIntent(R.id.widget_elapsed, openIntent)
                setOnClickPendingIntent(R.id.widget_hint, openIntent)

                val dayAction = widgetData.getString("day_button_action", "start_day")
                    ?: "start_day"
                val dayLabel = widgetData.getString("day_button_label", "Start day")
                    ?: "Start day"
                setTextViewText(R.id.widget_day_button, dayLabel)
                setOnClickPendingIntent(
                    R.id.widget_day_button,
                    actionIntent(context, Uri.parse("plainday://$dayAction"), 1003),
                )

                if (canName) {
                    val nameLabel = widgetData.getString("name_button", "Add name") ?: "Add name"
                    setTextViewText(R.id.widget_name_button, nameLabel.ifBlank { "Add name" })
                    setViewVisibility(R.id.widget_name_button, View.VISIBLE)
                    setOnClickPendingIntent(
                        R.id.widget_name_button,
                        renameIntent(context, 1002),
                    )
                } else {
                    setViewVisibility(R.id.widget_name_button, View.GONE)
                }

                for (i in actionViewIds.indices) {
                    val viewId = actionViewIds[i]
                    if (i < actionCount) {
                        val label = widgetData.getString("action_${i}_label", "") ?: ""
                        val buttonId = widgetData.getString("action_${i}_id", "") ?: ""
                        setTextViewText(viewId, label.ifBlank { "Action" })
                        setViewVisibility(viewId, View.VISIBLE)
                        if (buttonId.isNotBlank()) {
                            setOnClickPendingIntent(
                                viewId,
                                actionIntent(
                                    context,
                                    Uri.parse("plainday://button/$buttonId"),
                                    1100 + i,
                                ),
                            )
                        }
                    } else {
                        setViewVisibility(viewId, View.GONE)
                    }
                }
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    /** Live tick on the launcher — no periodic Flutter/widget rewrite needed. */
    private fun applyElapsed(views: RemoteViews, flutter: SharedPreferences) {
        val running = PlaindayWidgetActions.runningEntry(flutter)
        if (running == null) {
            views.setChronometer(R.id.widget_elapsed, SystemClock.elapsedRealtime(), null, false)
            views.setTextViewText(R.id.widget_elapsed, "--:--")
            return
        }
        val elapsedMs = PlaindayWidgetActions.elapsedSeconds(running).toLong() * 1000L
        val base = SystemClock.elapsedRealtime() - elapsedMs
        views.setChronometer(R.id.widget_elapsed, base, null, true)
    }

    private fun launchIntent(context: Context, uri: Uri, requestCode: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION
            data = uri
            // Reuse the existing task/activity — don't stack a new MainActivity per tap.
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
        }
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return PendingIntent.getActivity(context, requestCode, intent, flags)
    }

    private fun renameIntent(context: Context, requestCode: Int): PendingIntent {
        val intent = Intent(context, WidgetRenameActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return PendingIntent.getActivity(context, requestCode, intent, flags)
    }

    /** Native handler — toast + prefs + widget refresh, no Flutter Activity. */
    private fun actionIntent(context: Context, uri: Uri, requestCode: Int): PendingIntent {
        val intent = Intent(context, PlaindayWidgetActionReceiver::class.java).apply {
            action = PlaindayWidgetActionReceiver.ACTION
            data = uri
        }
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return PendingIntent.getBroadcast(context, requestCode, intent, flags)
    }
}
