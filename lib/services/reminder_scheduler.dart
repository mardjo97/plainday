import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/profile.dart';
import 'notification_service.dart';

/// Builds OS schedules from a generic Profile config.
///
/// On Android, scheduling is owned by native [PlaindayReminderScheduler]
/// (AlarmManager) so widget taps and boot survive without Flutter.
class ReminderScheduler {
  ReminderScheduler(this.notifications);

  final NotificationService notifications;

  static const _channel = MethodChannel('rs.hexatech.plainday/reminders');

  /// How many interval reminders were scheduled in the last reschedule.
  int lastIntervalCount = 0;

  /// Enabled interval configs found on the profile (before OS scheduling).
  int lastIntervalConfigCount = 0;

  /// Why scheduling was skipped or limited (null when OK).
  String? lastSkipReason;

  bool lastExactAllowed = true;
  bool lastUsedInexact = false;
  int lastScheduledCount = 0;

  Future<void> reschedule({
    required Profile? profile,
    required bool dayStarted,
  }) async {
    lastIntervalCount = 0;
    lastIntervalConfigCount = 0;
    lastSkipReason = null;
    lastExactAllowed = true;
    lastUsedInexact = false;
    lastScheduledCount = 0;
    notifications.lastScheduledCount = 0;

    // Drop any leftover plugin alarms so we don't double-fire.
    await notifications.cancelAll();

    if (profile == null) {
      lastSkipReason = 'No active profile';
      return;
    }

    lastIntervalConfigCount = profile.reminders
        .where(
          (r) =>
              r.enabled &&
              r.kind == ReminderKind.interval &&
              (r.intervalMinutes ?? 0) > 0,
        )
        .length;

    if (Platform.isAndroid) {
      await _rescheduleNative();
      return;
    }

    await _rescheduleDart(profile: profile, dayStarted: dayStarted);
  }

  Future<void> _rescheduleNative() async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('reschedule');
      if (raw is! Map) {
        lastSkipReason = 'Native reschedule returned nothing';
        return;
      }
      final map = Map<String, dynamic>.from(raw);
      lastScheduledCount = map['scheduled'] as int? ?? 0;
      lastIntervalCount = map['intervals'] as int? ?? 0;
      lastIntervalConfigCount =
          map['intervalConfigs'] as int? ?? lastIntervalConfigCount;
      lastSkipReason = map['skipReason'] as String?;
      lastExactAllowed = map['exactAllowed'] as bool? ?? true;
      lastUsedInexact = map['usedInexact'] as bool? ?? false;
      notifications.lastScheduledCount = lastScheduledCount;
      notifications.lastUsedInexact = lastUsedInexact;
      notifications.lastScheduleMode =
          lastUsedInexact ? 'inexactAllowWhileIdle' : 'alarmClock';
      debugPrint(
        'Plainday native reminders: scheduled=$lastScheduledCount '
        'intervals=$lastIntervalCount exact=$lastExactAllowed '
        'reason=$lastSkipReason',
      );
    } catch (e) {
      lastSkipReason = 'Native reschedule failed: $e';
      debugPrint('Plainday: $lastSkipReason');
    }
  }

  Future<bool> canScheduleExactNative() async {
    if (!Platform.isAndroid) return notifications.canScheduleExact();
    try {
      final v = await _channel.invokeMethod<bool>('canScheduleExact');
      return v ?? await notifications.canScheduleExact();
    } catch (_) {
      return notifications.canScheduleExact();
    }
  }

  Future<void> snoozeStandUpNative() async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod<void>('snoozeStandUp');
        return;
      } catch (_) {}
    }
    await notifications.scheduleSnoozeStandUp();
  }

  Future<void> _rescheduleDart({
    required Profile profile,
    required bool dayStarted,
  }) async {
    if (!dayStarted) {
      if (profile.rules.silenceWhenInactive) {
        lastSkipReason = 'Day off — reminders cleared';
        return;
      }

      final now = DateTime.now();
      final activeToday = _isActiveDay(profile, now);
      if (!activeToday) {
        lastSkipReason =
            'Day off / inactive weekday — reminders cleared '
            '(${profile.name}: ${_formatDays(profile.activeDays)})';
        debugPrint('Plainday: $lastSkipReason');
        return;
      }

      await _scheduleStartReminders(profile, now);
      lastSkipReason =
          'Day off — intervals cleared; start nudge kept if still upcoming';
      return;
    }

    final now = DateTime.now();
    final activeToday = _isActiveDay(profile, now);
    if (!activeToday) {
      debugPrint(
        'Plainday: day started on inactive weekday — scheduling anyway',
      );
    }

    await _scheduleEndReminders(profile, now);
    await _scheduleBreakReminders(profile, now);
    await _scheduleIntervals(profile, now);

    if (lastIntervalConfigCount == 0) {
      lastSkipReason = 'No enabled interval reminders on ${profile.name}';
    } else if (lastIntervalCount == 0) {
      lastSkipReason = notifications.lastScheduleError ??
          'Interval configs found but none scheduled '
              '(check exact-alarm permission / time window)';
    } else {
      lastSkipReason = null;
    }
  }

  bool _isActiveDay(Profile profile, DateTime now) {
    return profile.activeDays.contains(now.weekday);
  }

  String _formatDays(List<int> days) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final sorted = [...days]..sort();
    return sorted.map((d) => names[(d - 1).clamp(0, 6)]).join(',');
  }

  DateTime _onDay(DateTime day, int minutesFromMidnight) {
    final h = (minutesFromMidnight ~/ 60).clamp(0, 23);
    final m = (minutesFromMidnight % 60).clamp(0, 59);
    return DateTime(day.year, day.month, day.day, h, m);
  }

  Future<void> _scheduleStartReminders(Profile profile, DateTime now) async {
    for (final r in profile.reminders) {
      if (!r.enabled || r.kind != ReminderKind.atProfileStart) continue;
      final when = _onDay(now, profile.startMinutes + r.offsetMinutes);
      await notifications.scheduleAt(
        when: when,
        title: r.label,
        body: 'Start your ${profile.name} day?',
        payload: r.actionId ?? NotificationPayloads.startDay,
      );
    }
  }

  Future<void> _scheduleEndReminders(Profile profile, DateTime now) async {
    for (final r in profile.reminders) {
      if (!r.enabled || r.kind != ReminderKind.atProfileEnd) continue;
      final when = _onDay(now, profile.endMinutes + r.offsetMinutes);
      await notifications.scheduleAt(
        when: when,
        title: r.label,
        body: 'Wrap up your ${profile.name} day?',
        payload: r.actionId ?? NotificationPayloads.endDay,
      );
    }
  }

  Future<void> _scheduleBreakReminders(Profile profile, DateTime now) async {
    for (final r in profile.reminders) {
      if (!r.enabled || r.kind != ReminderKind.relativeToBreak) continue;
      final breakId = r.breakId;
      if (breakId == null) continue;

      BreakWindow? window;
      for (final b in profile.breaks) {
        if (b.id == breakId) {
          window = b;
          break;
        }
      }
      if (window == null) continue;

      final isReturn = r.actionId == NotificationPayloads.returnFromBreak ||
          r.label.toLowerCase().contains('return');
      final anchor = isReturn ? window.endMinutes : window.startMinutes;
      final when = _onDay(now, anchor + r.offsetMinutes);
      final payload = r.actionId ??
          (isReturn
              ? NotificationPayloads.returnFromBreak
              : NotificationPayloads.goToBreak);

      await notifications.scheduleAt(
        when: when,
        title: r.label,
        body: isReturn
            ? 'Ready to return from ${window.label}?'
            : 'Time for ${window.label} soon.',
        payload: payload,
      );
    }
  }

  Future<void> _scheduleIntervals(Profile profile, DateTime now) async {
    var windowEnd = _onDay(now, profile.endMinutes);
    final minWindow = now.add(const Duration(hours: 8));
    if (!windowEnd.isAfter(now.add(const Duration(minutes: 2)))) {
      windowEnd = minWindow;
    }

    for (final r in profile.reminders) {
      if (!r.enabled || r.kind != ReminderKind.interval) continue;
      final every = r.intervalMinutes;
      if (every == null || every <= 0) continue;

      var cursor = now.add(Duration(minutes: every));
      var count = 0;
      final maxCount = every <= 2 ? 45 : (every <= 5 ? 24 : 16);
      while (!cursor.isAfter(windowEnd) && count < maxCount) {
        final ok = await notifications.scheduleAt(
          when: cursor,
          title: r.label,
          body: 'Quick stretch — then back to it.',
          payload: NotificationPayloads.standUp,
          precise: true,
        );
        if (ok) lastIntervalCount++;
        cursor = cursor.add(Duration(minutes: every));
        count++;
      }
    }
  }
}
