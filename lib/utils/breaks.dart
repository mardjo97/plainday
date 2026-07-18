import '../models/profile.dart';

BreakWindow? breakWindowById(Profile profile, String? id) {
  if (id == null) return null;
  for (final b in profile.breaks) {
    if (b.id == id) return b;
  }
  return null;
}

/// Current break if inside a window; otherwise the next upcoming today;
/// if all have passed, the first break (tomorrow's cycle).
BreakWindow? nextBreakWindow(Profile profile, {DateTime? now}) {
  if (profile.breaks.isEmpty) return null;
  final at = now ?? DateTime.now();
  final minutes = at.hour * 60 + at.minute;
  final sorted = List<BreakWindow>.from(profile.breaks)
    ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));

  for (final b in sorted) {
    if (minutes >= b.startMinutes && minutes <= b.endMinutes) return b;
  }
  for (final b in sorted) {
    if (b.startMinutes > minutes) return b;
  }
  return sorted.first;
}

/// [breakId] null → next upcoming / current. Unknown id falls back to next.
BreakWindow? resolveBreakWindow(
  Profile profile, {
  String? breakId,
  DateTime? now,
}) {
  final linked = breakWindowById(profile, breakId);
  if (linked != null) return linked;
  return nextBreakWindow(profile, now: now);
}
