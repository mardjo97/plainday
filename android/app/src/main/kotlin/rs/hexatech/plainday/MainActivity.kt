package rs.hexatech.plainday

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "reschedule" -> {
                    val status = PlaindayReminderScheduler.reschedule(
                        applicationContext,
                        force = true,
                    )
                    result.success(
                        mapOf(
                            "scheduled" to status.scheduled,
                            "intervals" to status.intervals,
                            "intervalConfigs" to status.intervalConfigs,
                            "skipReason" to status.skipReason,
                            "exactAllowed" to status.exactAllowed,
                            "usedInexact" to status.usedInexact,
                        ),
                    )
                }
                "canScheduleExact" -> {
                    result.success(PlaindayReminderScheduler.canScheduleExact(applicationContext))
                }
                "snoozeStandUp" -> {
                    PlaindayReminderScheduler.snoozeStandUp(applicationContext)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    companion object {
        private const val CHANNEL = "rs.hexatech.plainday/reminders"
    }
}
