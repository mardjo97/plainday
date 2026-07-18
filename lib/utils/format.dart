import '../models/profile.dart';

String formatMinutesOfDay(int minutes) {
  final h = (minutes ~/ 60).clamp(0, 23);
  final m = minutes % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

String formatDurationSeconds(int totalSeconds) {
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  if (h > 0) return '${h}h ${m}m';
  final s = totalSeconds % 60;
  if (m > 0) return '${m}m';
  return '${s}s';
}

String activityKindLabel(ActivityKind kind) {
  return switch (kind) {
    ActivityKind.task => 'Task',
    ActivityKind.meeting => 'Meeting',
    ActivityKind.breakTime => 'Break',
    ActivityKind.note => 'Note',
    ActivityKind.dayStart => 'Day start',
    ActivityKind.dayEnd => 'Day end',
  };
}

bool activityKindIsDayMarker(ActivityKind kind) {
  return kind == ActivityKind.dayStart || kind == ActivityKind.dayEnd;
}

String reminderKindLabel(ReminderKind kind) {
  return switch (kind) {
    ReminderKind.atProfileStart => 'Profile start',
    ReminderKind.atProfileEnd => 'Profile end',
    ReminderKind.interval => 'Interval',
    ReminderKind.relativeToBreak => 'Relative to break',
  };
}

const weekdayLabels = {
  1: 'Mon',
  2: 'Tue',
  3: 'Wed',
  4: 'Thu',
  5: 'Fri',
  6: 'Sat',
  7: 'Sun',
};

DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime startOfWeek(DateTime d) {
  final day = startOfDay(d);
  return day.subtract(Duration(days: day.weekday - 1));
}
