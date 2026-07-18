package rs.hexatech.plainday

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Fires when a native reminder alarm triggers. Shows a notification and can
 * handle snooze / quick actions without starting Flutter.
 */
class PlaindayAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent == null) return
        when (intent.action) {
            PlaindayReminderScheduler.ACTION_SNOOZE -> {
                PlaindayReminderScheduler.snoozeStandUp(context.applicationContext)
                return
            }
            PlaindayReminderScheduler.ACTION_FIRE,
            null,
            -> show(context.applicationContext, intent)
            else -> {
                // Notification action buttons reuse widget action URIs.
                val data = intent.data
                if (data != null) {
                    PlaindayWidgetActions.handle(context.applicationContext, data)
                    PlaindayReminderScheduler.reschedule(context.applicationContext)
                }
            }
        }
    }

    private fun show(context: Context, intent: Intent) {
        PlaindayReminderScheduler.ensureChannel(context)
        val title = intent.getStringExtra(PlaindayReminderScheduler.EXTRA_TITLE) ?: "Plainday"
        val body = intent.getStringExtra(PlaindayReminderScheduler.EXTRA_BODY).orEmpty()
        val payload = intent.getStringExtra(PlaindayReminderScheduler.EXTRA_PAYLOAD).orEmpty()

        val open = PendingIntent.getActivity(
            context,
            payload.hashCode(),
            Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                data = android.net.Uri.parse("plainday://notif/$payload")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            pendingFlags(),
        )

        val builder = NotificationCompat.Builder(context, PlaindayReminderScheduler.CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setContentIntent(open)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)

        when (payload) {
            "stand_up" -> {
                builder.addAction(
                    0,
                    "Snooze 10m",
                    PendingIntent.getBroadcast(
                        context,
                        9101,
                        Intent(context, PlaindayAlarmReceiver::class.java).apply {
                            action = PlaindayReminderScheduler.ACTION_SNOOZE
                        },
                        pendingFlags(),
                    ),
                )
            }
            "start_day" -> addUriAction(context, builder, "Start day", "plainday://start_day", 9102)
            "end_day" -> addUriAction(context, builder, "End day", "plainday://end_day", 9103)
            "go_to_break" -> addUriAction(context, builder, "Go to break", "plainday://go_to_break", 9104)
            "return_from_break" ->
                addUriAction(context, builder, "Return", "plainday://return_from_break", 9105)
        }

        val id = (System.currentTimeMillis() % Int.MAX_VALUE).toInt()
        try {
            NotificationManagerCompat.from(context).notify(id, builder.build())
        } catch (e: SecurityException) {
            Log.w("PlaindayReminders", "notify blocked: $e")
        }
    }

    private fun addUriAction(
        context: Context,
        builder: NotificationCompat.Builder,
        label: String,
        uri: String,
        requestCode: Int,
    ) {
        val pi = PendingIntent.getBroadcast(
            context,
            requestCode,
            Intent(context, PlaindayAlarmReceiver::class.java).apply {
                action = "rs.hexatech.plainday.action.NOTIF_ACTION"
                data = android.net.Uri.parse(uri)
            },
            pendingFlags(),
        )
        builder.addAction(0, label, pi)
    }

    private fun pendingFlags(): Int {
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return flags
    }
}
