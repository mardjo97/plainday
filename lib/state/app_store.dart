import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../data/presets.dart';
import '../models/profile.dart';
import '../services/notification_service.dart';
import '../services/reminder_scheduler.dart';
import '../services/widget_service.dart';
import '../utils/breaks.dart';
import '../utils/format.dart';

enum BreakPrompt { goToBreak, returnFromBreak }

class AppStore extends ChangeNotifier {
  AppStore(
    this._prefs, {
    NotificationService? notifications,
    WidgetService? widgets,
  })  : notifications = notifications ?? NotificationService(),
        widgets = widgets ?? WidgetService() {
    scheduler = ReminderScheduler(this.notifications);
  }

  final SharedPreferences _prefs;
  final NotificationService notifications;
  final WidgetService widgets;
  late final ReminderScheduler scheduler;

  static const _profilesKey = 'profiles';
  static const _activeProfileKey = 'active_profile_id';
  static const _dayStartedKey = 'day_started';
  static const _entriesKey = 'activity_entries';
  static const _stackKey = 'paused_stack';
  static const _stackJsonKey = 'paused_stack_json';
  static const _notifAskedKey = 'notif_permission_asked';

  List<Profile> profiles = [];
  String? activeProfileId;
  bool dayStarted = false;
  List<ActivityEntry> entries = [];
  List<String> pausedStack = [];
  bool notificationsAllowed = false;
  bool notificationPromptDismissed = false;

  Profile? get activeProfile {
    if (activeProfileId == null) return null;
    try {
      return profiles.firstWhere((p) => p.id == activeProfileId);
    } catch (_) {
      return profiles.isEmpty ? null : profiles.first;
    }
  }

  ActivityEntry? get currentActivity {
    try {
      return entries.firstWhere((e) => e.isRunning);
    } catch (_) {
      return null;
    }
  }

  List<ActivityEntry> get todayEntries {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    return entries
        .where(
          (e) => !e.startedAt.isBefore(start) && e.startedAt.isBefore(end),
        )
        .toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  }

  /// Contextual break suggestion from active profile break windows.
  BreakPrompt? get breakPrompt {
    final profile = activeProfile;
    if (profile == null || !dayStarted) return null;

    final now = DateTime.now();
    final minutes = now.hour * 60 + now.minute;
    final onBreak = currentActivity?.kind == ActivityKind.breakTime;

    for (final b in profile.breaks) {
      if (minutes >= b.startMinutes - 30 && minutes < b.startMinutes) {
        return onBreak ? BreakPrompt.returnFromBreak : BreakPrompt.goToBreak;
      }
      if (minutes >= b.startMinutes && minutes <= b.endMinutes + 15) {
        return onBreak ? BreakPrompt.returnFromBreak : BreakPrompt.goToBreak;
      }
    }
    return null;
  }

  /// Break window the suggestion is about (next / current in the prompt window).
  BreakWindow? get suggestedBreak {
    final profile = activeProfile;
    if (profile == null || breakPrompt == null) return null;
    return nextBreakWindow(profile);
  }

  bool get showNotificationBanner =>
      !notificationsAllowed && !notificationPromptDismissed;

  static Future<AppStore> load({
    bool enableNotifications = true,
    bool? enableWidgets,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final store = AppStore(prefs);
    await store._hydrate();
    final widgetsOn = enableWidgets ?? enableNotifications;
    store.widgets.enabled = widgetsOn;
    if (enableNotifications) {
      try {
        await store.notifications.init(
          onAction: store.handleNotificationAction,
        );
        store.notificationsAllowed =
            await store.notifications.hasPermission();
      } catch (_) {
        store.notificationsAllowed = false;
      }
    }
    store.notificationPromptDismissed =
        prefs.getBool(_notifAskedKey) ?? false;
    store._diskRevision = store._readRevision();
    await store._syncSideEffects();
    return store;
  }

  static const _widgetRevisionKey = 'widget_revision';
  int _diskRevision = 0;

  /// Reloads profiles/day/entries from disk (e.g. after a background widget tap).
  Future<void> reloadFromDisk() async {
    await _hydrate();
    _diskRevision = _readRevision();
    await _syncSideEffects();
    notifyListeners();
  }

  int _readRevision() {
    final asString = _prefs.getString(_widgetRevisionKey);
    if (asString != null) return int.tryParse(asString) ?? 0;
    return _prefs.getInt(_widgetRevisionKey) ?? 0;
  }

  /// Call periodically / on resume — reloads if the widget changed disk state.
  Future<bool> pullRemoteChanges() async {
    await _prefs.reload();
    final rev = _readRevision();
    if (rev == _diskRevision) return false;
    await reloadFromDisk();
    return true;
  }

  Future<void> _hydrate() async {
    final rawProfiles = _prefs.getString(_profilesKey);
    if (rawProfiles == null) {
      final work = ProfilePresets.work();
      profiles = [work];
      activeProfileId = work.id;
      await _persistProfiles();
      await _prefs.setString(_activeProfileKey, work.id);
    } else {
      final list = jsonDecode(rawProfiles) as List<dynamic>;
      profiles = list
          .map((e) => Profile.fromJson(e as Map<String, dynamic>))
          .toList();
      activeProfileId =
          _prefs.getString(_activeProfileKey) ?? profiles.first.id;
    }

    dayStarted = _prefs.getBool(_dayStartedKey) ?? false;

    final rawEntries = _prefs.getString(_entriesKey);
    if (rawEntries != null) {
      final list = jsonDecode(rawEntries) as List<dynamic>;
      entries = list
          .map((e) => ActivityEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    pausedStack = _prefs.getStringList(_stackKey) ?? [];
    final stackJson = _prefs.getString(_stackJsonKey);
    if (stackJson != null && stackJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(stackJson);
        if (decoded is List) {
          pausedStack = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }

    // Persist migrated button shape (isBreak, noun labels, drop activityKind).
    await _persistProfiles();
    notifyListeners();
  }

  Future<void> _persistProfiles() async {
    await _prefs.setString(
      _profilesKey,
      jsonEncode(profiles.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _persistEntries() async {
    await _prefs.setString(
      _entriesKey,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
    await _prefs.setStringList(_stackKey, pausedStack);
    await _prefs.setString(_stackJsonKey, jsonEncode(pausedStack));
  }

  Future<void> _syncSideEffects() async {
    try {
      await scheduler.reschedule(
        profile: activeProfile,
        dayStarted: dayStarted,
      );
    } catch (e) {
      debugPrint('Plainday reschedule failed: $e');
    }
    try {
      await widgets.update(this);
    } catch (_) {}
  }

  /// Reschedules reminders and returns a short status for the UI.
  Future<String> refreshReminders() async {
    // Re-prompt exact alarms / battery if needed before scheduling.
    await notifications.requestPermission();
    await _syncSideEffects();
    final pending = await notifications.pendingCount();
    final intervals = scheduler.lastIntervalCount;
    final configs = scheduler.lastIntervalConfigCount;
    final exact = await notifications.canScheduleExact();
    final skip = scheduler.lastSkipReason;
    final mode = notifications.lastScheduleMode;
    final inexact = notifications.lastUsedInexact;

    if (!exact || inexact) {
      return 'Intervals need exact alarms. '
          'Open Alarms & reminders for Plainday, allow exact alarms, '
          'then tap Refresh again. '
          'Pending: $pending'
          '${mode != null ? ' · mode: $mode' : ''}';
    }

    if (intervals > 0) {
      return 'Scheduled $intervals precise interval(s) '
          '(mode: ${mode ?? 'exact'}). Pending: $pending';
    }
    if (skip != null) {
      return '$skip · configs: $configs · pending: $pending';
    }
    return 'No interval reminders scheduled. '
        'Configs: $configs · pending: $pending';
  }

  Future<void> requestNotificationPermission() async {
    notificationsAllowed = await notifications.requestPermission();
    await _prefs.setBool(_notifAskedKey, true);
    notificationPromptDismissed = true;
    await _syncSideEffects();
    notifyListeners();
  }

  Future<void> dismissNotificationBanner() async {
    notificationPromptDismissed = true;
    await _prefs.setBool(_notifAskedKey, true);
    notifyListeners();
  }

  Future<void> handleNotificationAction(String payload) async {
    switch (payload) {
      case NotificationPayloads.startDay:
        await startDay();
      case NotificationPayloads.endDay:
        await endDay();
      case NotificationPayloads.goToBreak:
        await goToBreak();
      case NotificationPayloads.returnFromBreak:
        await returnFromBreak();
      case NotificationPayloads.snoozeStandUp:
        await notifications.scheduleSnoozeStandUp();
      case NotificationPayloads.standUp:
        // Open app / acknowledge — no timer change.
        break;
    }
  }

  /// True when a day is on or any timer is still open (running/paused).
  bool get hasOpenDaySession {
    if (dayStarted) return true;
    return entries.any((e) => e.endedAt == null);
  }

  Profile? profileById(String id) {
    for (final p in profiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  String profileNameFor(String id) => profileById(id)?.name ?? 'Unknown profile';

  int profileColorFor(String id) =>
      profileById(id)?.colorValue ?? 0xFF5A5A5A;

  Future<void> setActiveProfile(String id) async {
    if (id == activeProfileId) return;
    activeProfileId = id;
    await _prefs.setString(_activeProfileKey, id);
    await _syncSideEffects();
    notifyListeners();
  }

  /// Ends the current day (stops timers, logs day end), then switches profile.
  Future<void> switchProfileResettingDay(String id) async {
    if (id == activeProfileId) return;
    if (hasOpenDaySession) {
      await endDay();
    } else {
      // Still drop any leftover OS schedules from the previous profile.
      await notifications.cancelAll();
    }
    await setActiveProfile(id);
  }

  Future<Profile> addProfileFromPreset(
    Profile preset, {
    bool activate = true,
  }) async {
    final created = preset.duplicate(name: preset.name);
    profiles = [...profiles, created];
    await _persistProfiles();
    if (activate) {
      await setActiveProfile(created.id);
    } else {
      notifyListeners();
    }
    return created;
  }

  Future<Profile> addBlankProfile({bool activate = true}) {
    return addProfileFromPreset(ProfilePresets.blank(), activate: activate);
  }

  Future<Profile?> duplicateProfile(String id, {bool activate = true}) async {
    Profile? source;
    for (final p in profiles) {
      if (p.id == id) {
        source = p;
        break;
      }
    }
    if (source == null) return null;
    final copy = source.duplicate();
    profiles = [...profiles, copy];
    await _persistProfiles();
    if (activate) {
      await setActiveProfile(copy.id);
    } else {
      notifyListeners();
    }
    return copy;
  }

  Future<void> updateProfile(Profile updated) async {
    profiles = [
      for (final p in profiles)
        if (p.id == updated.id) updated else p,
    ];
    await _persistProfiles();
    await _syncSideEffects();
    notifyListeners();
  }

  Future<bool> deleteProfile(String id) async {
    if (profiles.length <= 1) return false;
    profiles = profiles.where((p) => p.id != id).toList();
    if (activeProfileId == id) {
      activeProfileId = profiles.first.id;
      await _prefs.setString(_activeProfileKey, activeProfileId!);
    }
    await _persistProfiles();
    await _syncSideEffects();
    notifyListeners();
    return true;
  }

  List<ActivityEntry> entriesInRange(DateTime start, DateTime end) {
    return entries
        .where(
          (e) => !e.startedAt.isBefore(start) && e.startedAt.isBefore(end),
        )
        .toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  }

  Map<ActivityKind, int> totalsForEntries(List<ActivityEntry> list) {
    final totals = <ActivityKind, int>{};
    final now = DateTime.now();
    for (final e in list) {
      if (activityKindIsDayMarker(e.kind)) continue;
      final secs = e.elapsedSeconds(now: now);
      totals[e.kind] = (totals[e.kind] ?? 0) + secs;
    }
    return totals;
  }

  ActivityEntry _dayMarker({
    required Profile profile,
    required ActivityKind kind,
    required DateTime at,
  }) {
    final isStart = kind == ActivityKind.dayStart;
    return ActivityEntry(
      profileId: profile.id,
      buttonId: isStart ? DayLogIds.start : DayLogIds.end,
      label: isStart
          ? 'Day started — ${profile.name}'
          : 'Day ended — ${profile.name}',
      kind: kind,
      startedAt: at,
      endedAt: at,
      accumulatedSeconds: 0,
    );
  }

  Map<ActivityKind, int> weekTotalsSeconds({DateTime? around}) {
    final anchor = around ?? DateTime.now();
    final start = DateTime(anchor.year, anchor.month, anchor.day)
        .subtract(Duration(days: anchor.weekday - 1));
    final end = start.add(const Duration(days: 7));
    return totalsForEntries(entriesInRange(start, end));
  }

  List<ActivityEntry> get weekEntries {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final end = start.add(const Duration(days: 7));
    return entriesInRange(start, end);
  }

  /// Day-keyed totals for the current week (Mon–Sun).
  Map<DateTime, int> weekDailyTotalsSeconds() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final result = <DateTime, int>{};
    for (var i = 0; i < 7; i++) {
      final day = start.add(Duration(days: i));
      final next = day.add(const Duration(days: 1));
      final secs = totalsForEntries(entriesInRange(day, next))
          .values
          .fold<int>(0, (a, b) => a + b);
      result[day] = secs;
    }
    return result;
  }

  String buildCsv({required bool week}) {
    final list = week ? weekEntries : todayEntries;
    final buf =
        StringBuffer('date,start,end,label,kind,seconds,profile,profileId\n');
    final now = DateTime.now();
    for (final e in list.reversed) {
      final secs = e.elapsedSeconds(now: now);
      final end = e.endedAt ?? e.pausedAt;
      final profileName = profileNameFor(e.profileId).replaceAll('"', '""');
      buf.writeln(
        [
          e.startedAt.toIso8601String().split('T').first,
          e.startedAt.toIso8601String(),
          end?.toIso8601String() ?? '',
          '"${e.label.replaceAll('"', '""')}"',
          e.kind.name,
          secs,
          '"$profileName"',
          e.profileId,
        ].join(','),
      );
    }
    return buf.toString();
  }

  Future<void> startDay() async {
    if (dayStarted) {
      await _syncSideEffects();
      notifyListeners();
      return;
    }
    final profile = activeProfile;
    final now = DateTime.now();
    dayStarted = true;
    await _prefs.setBool(_dayStartedKey, true);
    if (profile != null) {
      entries = [
        ...entries,
        _dayMarker(profile: profile, kind: ActivityKind.dayStart, at: now),
      ];
      await _persistEntries();
    }
    await _syncSideEffects();
    notifyListeners();
  }

  Future<void> endDay() async {
    final profile = activeProfile;
    final now = DateTime.now();
    final wasStarted = dayStarted;
    var next = entries.map((e) {
      if (e.endedAt != null) return e;
      final elapsed = e.elapsedSeconds(now: now);
      return e.copyWith(
        endedAt: now,
        accumulatedSeconds: elapsed,
        clearPausedAt: true,
      );
    }).toList();
    if (wasStarted && profile != null) {
      next = [
        ...next,
        _dayMarker(profile: profile, kind: ActivityKind.dayEnd, at: now),
      ];
    }
    entries = next;
    pausedStack = [];
    dayStarted = false;
    await _prefs.setBool(_dayStartedKey, false);
    await _persistEntries();
    // Wipe interval/break/end schedules before reschedule decides what (if
    // anything) to put back for a day-off state.
    await notifications.cancelAll();
    await _syncSideEffects();
    notifyListeners();
  }

  Future<void> goToBreak({String? breakWindowId}) async {
    final profile = activeProfile;
    if (profile == null) return;

    final window = resolveBreakWindow(profile, breakId: breakWindowId);

    ProfileButton? breakButton;
    if (window != null) {
      for (final b in profile.buttons) {
        if (b.isBreak && b.breakId == window.id) {
          breakButton = b;
          break;
        }
      }
    }
    if (breakButton == null) {
      for (final b in profile.buttons) {
        if (b.isBreak && b.breakId == null) {
          breakButton = b;
          break;
        }
      }
    }
    if (breakButton == null) {
      for (final b in profile.buttons) {
        if (b.isBreak) {
          breakButton = b;
          break;
        }
      }
    }
    breakButton ??= ProfileButton(
      id: const Uuid().v4(),
      label: 'Break',
      isBreak: true,
    );

    await startFromButton(
      breakButton,
      eventName: window?.label,
      breakWindowId: window?.id,
    );
  }

  Future<void> returnFromBreak() async {
    final current = currentActivity;
    if (current?.kind == ActivityKind.breakTime) {
      await endCurrent(resumePrevious: true);
    }
  }

  Future<void> renameActivity(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final index = entries.indexWhere((e) => e.id == id);
    if (index == -1) return;
    final next = List<ActivityEntry>.from(entries);
    next[index] = next[index].copyWith(label: trimmed);
    entries = next;
    await _persistEntries();
    await _syncSideEffects();
    notifyListeners();
  }

  Future<void> renameCurrentActivity(String name) async {
    final current = currentActivity;
    if (current == null) return;
    await renameActivity(current.id, name);
  }

  ProfileButton? buttonForEntry(ActivityEntry entry) {
    for (final profile in profiles) {
      if (profile.id != entry.profileId) continue;
      for (final button in profile.buttons) {
        if (button.id == entry.buttonId) return button;
      }
    }
    // Fallback: active profile only (legacy / moved buttons).
    final active = activeProfile;
    if (active == null) return null;
    for (final button in active.buttons) {
      if (button.id == entry.buttonId) return button;
    }
    return null;
  }

  /// True while the activity title is still the button label (or linked break name).
  bool usesButtonLabel(ActivityEntry entry) {
    final button = buttonForEntry(entry);
    if (button == null) return false;
    if (entry.label == button.label) return true;
    if (!button.isBreak) return false;
    Profile? profile;
    for (final p in profiles) {
      if (p.id == entry.profileId) {
        profile = p;
        break;
      }
    }
    profile ??= activeProfile;
    if (profile == null) return false;
    final window = resolveBreakWindow(profile, breakId: button.breakId);
    return window != null && entry.label == window.label;
  }

  bool get currentCanBeNamed {
    final current = currentActivity;
    if (current == null) return false;
    final button = buttonForEntry(current);
    if (button != null) return button.requiresName;
    return !activityKindIsDayMarker(current.kind) &&
        current.kind != ActivityKind.breakTime;
  }

  Future<void> startFromButtonId(String buttonId) async {
    final profile = activeProfile;
    if (profile == null) return;
    ProfileButton? button;
    for (final b in profile.buttons) {
      if (b.id == buttonId) {
        button = b;
        break;
      }
    }
    if (button == null) return;
    await startFromButton(button);
  }

  Future<void> startFromButton(
    ProfileButton button, {
    String? eventName,
    String? breakWindowId,
  }) async {
    final profile = activeProfile;
    if (profile == null) return;

    final now = DateTime.now();
    var next = List<ActivityEntry>.from(entries);
    var stack = List<String>.from(pausedStack);

    if (!dayStarted) {
      dayStarted = true;
      await _prefs.setBool(_dayStartedKey, true);
      next.add(
        _dayMarker(profile: profile, kind: ActivityKind.dayStart, at: now),
      );
    }

    if (profile.rules.oneActiveTimer && button.pausesOthers) {
      final runningIndex = next.indexWhere((e) => e.isRunning);
      if (runningIndex != -1) {
        final running = next[runningIndex];
        final elapsed = running.elapsedSeconds(now: now);
        next[runningIndex] = running.copyWith(
          pausedAt: now,
          accumulatedSeconds: elapsed,
        );
        if (profile.rules.resumePreviousOnEnd) {
          stack.add(running.id);
        }
      }
    }

    final trimmed = eventName?.trim();
    String label;
    if (trimmed != null && trimmed.isNotEmpty) {
      label = trimmed;
    } else if (button.isBreak) {
      final window = resolveBreakWindow(
        profile,
        breakId: breakWindowId ?? button.breakId,
        now: now,
      );
      label = window?.label ?? button.label;
    } else {
      label = button.label;
    }

    next.add(
      ActivityEntry(
        profileId: profile.id,
        buttonId: button.id,
        label: label,
        kind: button.entryKind,
        startedAt: now,
      ),
    );

    entries = next;
    pausedStack = stack;
    await _persistEntries();
    await _syncSideEffects();
    notifyListeners();
  }

  Future<void> endCurrent({bool resumePrevious = true}) async {
    final profile = activeProfile;
    final now = DateTime.now();
    final runningIndex = entries.indexWhere((e) => e.isRunning);
    if (runningIndex == -1) return;

    final running = entries[runningIndex];
    final elapsed = running.elapsedSeconds(now: now);
    final next = List<ActivityEntry>.from(entries);
    next[runningIndex] = running.copyWith(
      endedAt: now,
      accumulatedSeconds: elapsed,
      clearPausedAt: true,
    );

    var stack = List<String>.from(pausedStack);
    if (resumePrevious &&
        (profile?.rules.resumePreviousOnEnd ?? true) &&
        stack.isNotEmpty) {
      final prevId = stack.removeLast();
      final prevIndex = next.indexWhere((e) => e.id == prevId && e.isPaused);
      if (prevIndex != -1) {
        final prev = next[prevIndex];
        next[prevIndex] = prev.copyWith(
          startedAt: now,
          clearPausedAt: true,
          clearEndedAt: true,
        );
      }
    }

    entries = next;
    pausedStack = stack;
    await _persistEntries();
    await _syncSideEffects();
    notifyListeners();
  }

  Map<ActivityKind, int> todayTotalsSeconds() {
    final totals = <ActivityKind, int>{};
    final now = DateTime.now();
    for (final e in todayEntries) {
      final secs = e.elapsedSeconds(now: now);
      totals[e.kind] = (totals[e.kind] ?? 0) + secs;
    }
    return totals;
  }
}
