package rs.hexatech.plainday

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/** Re-arms native reminder alarms after reboot / app update. */
class PlaindayBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED &&
            action != "android.intent.action.QUICKBOOT_POWERON" &&
            action != "com.htc.intent.action.QUICKBOOT_POWERON"
        ) {
            return
        }
        Log.i("PlaindayReminders", "Boot/update — rescheduling alarms ($action)")
        PlaindayReminderScheduler.reschedule(context.applicationContext, force = true)
    }
}
