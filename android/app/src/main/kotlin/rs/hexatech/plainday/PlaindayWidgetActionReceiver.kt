package rs.hexatech.plainday

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/** Receives widget action taps and applies them without launching the Flutter UI. */
class PlaindayWidgetActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val uri = intent?.data
        Log.i(TAG, "Widget action: $uri")
        val ok = PlaindayWidgetActions.handle(context, uri)
        if (!ok) {
            Log.w(TAG, "Unhandled widget action: $uri")
        }
    }

    companion object {
        private const val TAG = "PlaindayWidget"
        const val ACTION = "rs.hexatech.plainday.action.WIDGET"
    }
}
