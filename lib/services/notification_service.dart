import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

typedef NotificationActionHandler = Future<void> Function(String payload);

/// Payloads used by scheduled reminders and notification actions.
abstract final class NotificationPayloads {
  static const startDay = 'start_day';
  static const endDay = 'end_day';
  static const goToBreak = 'go_to_break';
  static const returnFromBreak = 'return_from_break';
  static const standUp = 'stand_up';
  static const snoozeStandUp = 'snooze_stand_up';
}

class NotificationService {
  NotificationService();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  NotificationActionHandler? onAction;
  bool _ready = false;
  int _seq = 0;
  int lastScheduledCount = 0;
  String? lastScheduleError;
  String? lastScheduleMode;
  bool lastUsedInexact = false;

  bool get isReady => _ready;

  Future<void> init({required NotificationActionHandler onAction}) async {
    this.onAction = onAction;
    tz_data.initializeTimeZones();
    await _configureLocalTimezone();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    final ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: [
        DarwinNotificationCategory(
          'STAND_UP',
          actions: [
            DarwinNotificationAction.plain(
              NotificationPayloads.snoozeStandUp,
              'Snooze 10m',
            ),
          ],
        ),
        DarwinNotificationCategory(
          'START_DAY',
          actions: [
            DarwinNotificationAction.plain(
              NotificationPayloads.startDay,
              'Start day',
            ),
          ],
        ),
        DarwinNotificationCategory(
          'GO_BREAK',
          actions: [
            DarwinNotificationAction.plain(
              NotificationPayloads.goToBreak,
              'Go to break',
            ),
          ],
        ),
        DarwinNotificationCategory(
          'RETURN_BREAK',
          actions: [
            DarwinNotificationAction.plain(
              NotificationPayloads.returnFromBreak,
              'Return',
            ),
          ],
        ),
        DarwinNotificationCategory(
          'END_DAY',
          actions: [
            DarwinNotificationAction.plain(
              NotificationPayloads.endDay,
              'End day',
            ),
          ],
        ),
      ],
    );

    await _plugin.initialize(
      settings: InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onResponse,
    );

    await _ensureAndroidChannel();

    final launch = await _plugin.getNotificationAppLaunchDetails();
    final response = launch?.notificationResponse;
    if (launch?.didNotificationLaunchApp == true &&
        response?.payload != null &&
        response!.payload!.isNotEmpty) {
      await onAction(response.payload!);
    }

    _ready = true;
  }

  Future<void> _configureLocalTimezone() async {
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
      return;
    } catch (e) {
      debugPrint('Plainday timezone lookup failed: $e');
    }
    // Fallbacks for devices that return non-IANA ids.
    for (final id in ['Europe/Belgrade', 'Europe/Berlin', 'UTC']) {
      try {
        tz.setLocalLocation(tz.getLocation(id));
        return;
      } catch (_) {}
    }
  }

  Future<void> _ensureAndroidChannel() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        'plainday_reminders',
        'Reminders',
        description: 'Profile start/end, breaks, and stand-up nudges',
        importance: Importance.high,
      ),
    );
  }

  void _onResponse(NotificationResponse response) {
    final action = response.actionId;
    final payload = response.payload;
    final effective = (action != null && action.isNotEmpty)
        ? action
        : (payload ?? '');
    if (effective.isEmpty) return;
    onAction?.call(effective);
  }

  Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    var ok = false;
    final notifStatus = await Permission.notification.request();
    if (notifStatus.isGranted || notifStatus.isLimited) ok = true;

    final androidNotif = await android?.requestNotificationsPermission();
    if (androidNotif == true) ok = true;

    // Exact alarms (needed for 1-minute intervals; otherwise Android batches ~15m).
    await Permission.scheduleExactAlarm.request();
    final canExact = await android?.canScheduleExactNotifications();
    if (canExact == false) {
      await android?.requestExactAlarmsPermission();
    }

    // Honor/Huawei often delay alarms unless unrestricted.
    final battery = await Permission.ignoreBatteryOptimizations.status;
    if (!battery.isGranted) {
      await Permission.ignoreBatteryOptimizations.request();
    }

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    final iosOk = await ios?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        ) ??
        false;
    if (iosOk) ok = true;

    return ok || await hasPermission();
  }

  Future<bool> canScheduleExact() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.canScheduleExactNotifications() ?? true;
  }

  /// Opens system screen to allow exact alarms (Android 12+).
  Future<void> openExactAlarmSettings() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestExactAlarmsPermission();
    await Permission.scheduleExactAlarm.request();
  }

  Future<void> openBatterySettings() async {
    await Permission.ignoreBatteryOptimizations.request();
  }

  Future<bool> hasPermission() async {
    final status = await Permission.notification.status;
    if (status.isGranted || status.isLimited) return true;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return defaultTargetPlatform == TargetPlatform.android &&
        (await android?.areNotificationsEnabled() ?? false);
  }

  /// Clears presented and scheduled reminders (AlarmManager pending included).
  Future<void> cancelAll() async {
    _seq = 0;
    lastScheduledCount = 0;
    lastUsedInexact = false;
    if (!_ready) return;

    try {
      // Pending (scheduled) first — cancelAll alone can miss these on some OEMs.
      try {
        await _plugin.cancelAllPendingNotifications();
      } catch (e) {
        debugPrint('Plainday cancelAllPendingNotifications: $e');
      }

      final pending = await _plugin.pendingNotificationRequests();
      for (final req in pending) {
        await _plugin.cancel(id: req.id);
      }

      await _plugin.cancelAll();

      final still = await _plugin.pendingNotificationRequests();
      if (still.isNotEmpty) {
        debugPrint(
          'Plainday: ${still.length} pending reminder(s) remain after cancel',
        );
        for (final req in still) {
          await _plugin.cancel(id: req.id);
        }
        try {
          await _plugin.cancelAllPendingNotifications();
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Plainday cancelAll failed: $e');
    }
  }

  Future<int> pendingCount() async {
    if (!_ready) return 0;
    final pending = await _plugin.pendingNotificationRequests();
    return pending.length;
  }

  /// Returns true when a notification was handed to the OS.
  ///
  /// Set [precise] for interval reminders — uses alarmClock / exact timing.
  /// Without exact-alarm permission, Android batches inexact alarms (~10–15m).
  Future<bool> scheduleAt({
    required DateTime when,
    required String title,
    required String body,
    required String payload,
    bool precise = false,
  }) async {
    if (!_ready) {
      lastScheduleError = 'Notifications not initialized';
      return false;
    }
    final earliest = DateTime.now().add(const Duration(seconds: 5));
    if (!when.isAfter(earliest)) return false;

    final id = 2000 + (_seq++ % 50000);
    final tzWhen = tz.TZDateTime.from(when, tz.local);

    final androidDetails = AndroidNotificationDetails(
      'plainday_reminders',
      'Reminders',
      channelDescription: 'Profile start/end, breaks, and stand-up nudges',
      importance: Importance.high,
      priority: Priority.high,
      category: precise
          ? AndroidNotificationCategory.alarm
          : AndroidNotificationCategory.reminder,
      actions: _androidActionsFor(payload),
    );

    final iosDetails = DarwinNotificationDetails(
      categoryIdentifier: _categoryFor(payload),
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final exactAllowed = await canScheduleExact();
    final modes = <AndroidScheduleMode>[
      if (precise && exactAllowed) AndroidScheduleMode.alarmClock,
      if (exactAllowed) AndroidScheduleMode.exactAllowWhileIdle,
      // Last resort — expect multi-minute delay on modern Android.
      AndroidScheduleMode.inexactAllowWhileIdle,
    ];

    for (final mode in modes) {
      try {
        await _plugin.zonedSchedule(
          id: id,
          title: title,
          body: body,
          scheduledDate: tzWhen,
          notificationDetails: details,
          androidScheduleMode: mode,
          payload: payload,
        );
        lastScheduledCount++;
        lastScheduleError = null;
        lastScheduleMode = mode.name;
        lastUsedInexact = mode == AndroidScheduleMode.inexactAllowWhileIdle;
        if (lastUsedInexact) {
          debugPrint(
            'Plainday: scheduled with inexact alarms — expect 10–15m drift',
          );
        }
        return true;
      } catch (e) {
        lastScheduleError = e.toString();
        debugPrint('Plainday schedule mode ${mode.name} failed: $e');
      }
    }
    return false;
  }

  Future<void> scheduleSnoozeStandUp({
    Duration delay = const Duration(minutes: 10),
  }) {
    return scheduleAt(
      when: DateTime.now().add(delay),
      title: 'Stand up',
      body: 'Snoozed reminder — take a short stretch.',
      payload: NotificationPayloads.standUp,
    );
  }

  /// Immediate test notification to verify permission/channel.
  Future<void> showTestNotification() async {
    if (!_ready) return;
    await _plugin.show(
      id: 9999,
      title: 'Plainday',
      body: 'Notifications are working.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'plainday_reminders',
          'Reminders',
          channelDescription: 'Profile start/end, breaks, and stand-up nudges',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  List<AndroidNotificationAction> _androidActionsFor(String payload) {
    return switch (payload) {
      NotificationPayloads.startDay => [
          const AndroidNotificationAction(
            NotificationPayloads.startDay,
            'Start day',
          ),
        ],
      NotificationPayloads.endDay => [
          const AndroidNotificationAction(
            NotificationPayloads.endDay,
            'End day',
          ),
        ],
      NotificationPayloads.goToBreak => [
          const AndroidNotificationAction(
            NotificationPayloads.goToBreak,
            'Go to break',
          ),
        ],
      NotificationPayloads.returnFromBreak => [
          const AndroidNotificationAction(
            NotificationPayloads.returnFromBreak,
            'Return',
          ),
        ],
      NotificationPayloads.standUp => [
          const AndroidNotificationAction(
            NotificationPayloads.snoozeStandUp,
            'Snooze 10m',
            showsUserInterface: false,
          ),
        ],
      _ => const [],
    };
  }

  String? _categoryFor(String payload) {
    return switch (payload) {
      NotificationPayloads.startDay => 'START_DAY',
      NotificationPayloads.endDay => 'END_DAY',
      NotificationPayloads.goToBreak => 'GO_BREAK',
      NotificationPayloads.returnFromBreak => 'RETURN_BREAK',
      NotificationPayloads.standUp => 'STAND_UP',
      _ => null,
    };
  }
}
