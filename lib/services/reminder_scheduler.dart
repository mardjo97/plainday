import 'package:flutter/foundation.dart';

import '../models/profile.dart';
import 'notification_service.dart';

/// Builds OS schedules from a generic Profile config (no special kinds).
class ReminderScheduler {
  ReminderScheduler(this.notifications);

  final NotificationService notifications;

  /// How many interval reminders were scheduled in the last reschedule.
  int lastIntervalCount = 0;

  /// Enabled interval configs found on the profile (before OS scheduling).
  int lastIntervalConfigCount = 0;

  /// Why scheduling was skipped or limited (null when OK).
  String? lastSkipReason;

  Future<void> reschedule({
    required Profile? profile,
    required bool dayStarted,
  }) async {
    lastIntervalCount = 0;
    lastIntervalConfigCount = 0;
    lastSkipReason = null;
    notifications.lastScheduledCount = 0;

    // Always wipe OS schedules first (end day / profile switch rely on this).
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

    // Day off / stopped: stay silent — no intervals, breaks, or end nudges.
    // (Start-of-day nudges only when the day hasn't been started yet *and*
    // the profile wants them for an upcoming start time.)
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
    // If the profile day is still active past scheduled end (or end is soon),
    // keep scheduling intervals while the day is running.
    final minWindow = now.add(const Duration(hours: 8));
    if (!windowEnd.isAfter(now.add(const Duration(minutes: 2)))) {
      windowEnd = minWindow;
    }

    for (final r in profile.reminders) {
      if (!r.enabled || r.kind != ReminderKind.interval) continue;
      final every = r.intervalMinutes;
      if (every == null || every <= 0) continue;

      // First fire after one full interval from now.
      var cursor = now.add(Duration(minutes: every));
      var count = 0;
      // Short intervals: schedule a dense exact window (alarmClock).
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
