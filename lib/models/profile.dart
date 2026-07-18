import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Generic profile — presets only fill these fields. No special profile kinds.
class Profile {
  Profile({
    String? id,
    required this.name,
    this.colorValue = 0xFF2F6F5E,
    this.startMinutes = 9 * 60,
    this.endMinutes = 17 * 60,
    this.activeDays = const [1, 2, 3, 4, 5],
    this.reminders = const [],
    this.breaks = const [],
    this.buttons = const [],
    this.rules = const ProfileRules(),
  }) : id = id ?? _uuid.v4();

  final String id;
  final String name;
  final int colorValue;
  /// Minutes from midnight.
  final int startMinutes;
  final int endMinutes;
  /// DateTime.weekday values (1=Mon … 7=Sun).
  final List<int> activeDays;
  final List<ProfileReminder> reminders;
  final List<BreakWindow> breaks;
  final List<ProfileButton> buttons;
  final ProfileRules rules;

  Profile copyWith({
    String? name,
    int? colorValue,
    int? startMinutes,
    int? endMinutes,
    List<int>? activeDays,
    List<ProfileReminder>? reminders,
    List<BreakWindow>? breaks,
    List<ProfileButton>? buttons,
    ProfileRules? rules,
  }) {
    return Profile(
      id: id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      startMinutes: startMinutes ?? this.startMinutes,
      endMinutes: endMinutes ?? this.endMinutes,
      activeDays: activeDays ?? this.activeDays,
      reminders: reminders ?? this.reminders,
      breaks: breaks ?? this.breaks,
      buttons: buttons ?? this.buttons,
      rules: rules ?? this.rules,
    );
  }

  /// Fresh profile with new ids (for duplicate / preset clone).
  Profile duplicate({String? name}) {
    final breakIdMap = <String, String>{};
    final newBreaks = breaks.map((b) {
      final nid = _uuid.v4();
      breakIdMap[b.id] = nid;
      return BreakWindow(
        id: nid,
        label: b.label,
        startMinutes: b.startMinutes,
        endMinutes: b.endMinutes,
      );
    }).toList();

    return Profile(
      name: name ?? '${this.name} copy',
      colorValue: colorValue,
      startMinutes: startMinutes,
      endMinutes: endMinutes,
      activeDays: List<int>.from(activeDays),
      breaks: newBreaks,
      reminders: reminders
          .map(
            (r) => ProfileReminder(
              id: _uuid.v4(),
              label: r.label,
              kind: r.kind,
              offsetMinutes: r.offsetMinutes,
              intervalMinutes: r.intervalMinutes,
              breakId: r.breakId == null ? null : breakIdMap[r.breakId],
              enabled: r.enabled,
              actionId: r.actionId,
            ),
          )
          .toList(),
      buttons: buttons
          .map(
            (b) => ProfileButton(
              id: _uuid.v4(),
              label: b.label,
              pausesOthers: b.pausesOthers,
              requiresName: b.requiresName,
              isBreak: b.isBreak,
              breakId: b.breakId == null ? null : breakIdMap[b.breakId],
            ),
          )
          .toList(),
      rules: rules,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'colorValue': colorValue,
        'startMinutes': startMinutes,
        'endMinutes': endMinutes,
        'activeDays': activeDays,
        'reminders': reminders.map((e) => e.toJson()).toList(),
        'breaks': breaks.map((e) => e.toJson()).toList(),
        'buttons': buttons.map((e) => e.toJson()).toList(),
        'rules': rules.toJson(),
      };

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String?,
      name: json['name'] as String,
      colorValue: json['colorValue'] as int? ?? 0xFF2F6F5E,
      startMinutes: json['startMinutes'] as int? ?? 9 * 60,
      endMinutes: json['endMinutes'] as int? ?? 17 * 60,
      activeDays: (json['activeDays'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          const [1, 2, 3, 4, 5],
      reminders: (json['reminders'] as List<dynamic>?)
              ?.map((e) => ProfileReminder.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      breaks: (json['breaks'] as List<dynamic>?)
              ?.map((e) => BreakWindow.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      buttons: (json['buttons'] as List<dynamic>?)
              ?.map((e) => ProfileButton.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      rules: json['rules'] != null
          ? ProfileRules.fromJson(json['rules'] as Map<String, dynamic>)
          : const ProfileRules(),
    );
  }
}

enum ReminderKind { atProfileStart, atProfileEnd, interval, relativeToBreak }

class ProfileReminder {
  const ProfileReminder({
    required this.id,
    required this.label,
    required this.kind,
    this.offsetMinutes = 0,
    this.intervalMinutes,
    this.breakId,
    this.enabled = true,
    this.actionId,
  });

  final String id;
  final String label;
  final ReminderKind kind;
  final int offsetMinutes;
  final int? intervalMinutes;
  final String? breakId;
  final bool enabled;
  final String? actionId;

  ProfileReminder copyWith({
    String? label,
    ReminderKind? kind,
    int? offsetMinutes,
    int? intervalMinutes,
    String? breakId,
    bool? enabled,
    String? actionId,
    bool clearBreakId = false,
    bool clearInterval = false,
    bool clearActionId = false,
  }) {
    return ProfileReminder(
      id: id,
      label: label ?? this.label,
      kind: kind ?? this.kind,
      offsetMinutes: offsetMinutes ?? this.offsetMinutes,
      intervalMinutes:
          clearInterval ? null : (intervalMinutes ?? this.intervalMinutes),
      breakId: clearBreakId ? null : (breakId ?? this.breakId),
      enabled: enabled ?? this.enabled,
      actionId: clearActionId ? null : (actionId ?? this.actionId),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'kind': kind.name,
        'offsetMinutes': offsetMinutes,
        'intervalMinutes': intervalMinutes,
        'breakId': breakId,
        'enabled': enabled,
        'actionId': actionId,
      };

  factory ProfileReminder.fromJson(Map<String, dynamic> json) {
    return ProfileReminder(
      id: json['id'] as String,
      label: json['label'] as String,
      kind: ReminderKind.values.byName(json['kind'] as String),
      offsetMinutes: json['offsetMinutes'] as int? ?? 0,
      intervalMinutes: json['intervalMinutes'] as int?,
      breakId: json['breakId'] as String?,
      enabled: json['enabled'] as bool? ?? true,
      actionId: json['actionId'] as String?,
    );
  }
}

class BreakWindow {
  const BreakWindow({
    required this.id,
    required this.label,
    required this.startMinutes,
    required this.endMinutes,
  });

  final String id;
  final String label;
  final int startMinutes;
  final int endMinutes;

  BreakWindow copyWith({
    String? label,
    int? startMinutes,
    int? endMinutes,
  }) {
    return BreakWindow(
      id: id,
      label: label ?? this.label,
      startMinutes: startMinutes ?? this.startMinutes,
      endMinutes: endMinutes ?? this.endMinutes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'startMinutes': startMinutes,
        'endMinutes': endMinutes,
      };

  factory BreakWindow.fromJson(Map<String, dynamic> json) {
    return BreakWindow(
      id: json['id'] as String,
      label: json['label'] as String,
      startMinutes: json['startMinutes'] as int,
      endMinutes: json['endMinutes'] as int,
    );
  }
}

enum ActivityKind { task, meeting, breakTime, note, dayStart, dayEnd }

/// Synthetic button ids for day boundary log entries.
abstract final class DayLogIds {
  static const start = '__day_start__';
  static const end = '__day_end__';
}

class ProfileButton {
  const ProfileButton({
    required this.id,
    required this.label,
    this.pausesOthers = true,
    this.requiresName = false,
    this.isBreak = false,
    this.breakId,
  });

  final String id;
  final String label;
  final bool pausesOthers;
  /// If true, the activity can be given a custom name.
  final bool requiresName;
  /// Break buttons power break suggestions / return-from-break.
  final bool isBreak;
  /// Linked break window. Null = next upcoming (or current) break.
  final String? breakId;

  /// Entry kind derived from button flags (no per-button type enum).
  ActivityKind get entryKind =>
      isBreak ? ActivityKind.breakTime : ActivityKind.task;

  ProfileButton copyWith({
    String? label,
    bool? pausesOthers,
    bool? requiresName,
    bool? isBreak,
    String? breakId,
    bool clearBreakId = false,
  }) {
    return ProfileButton(
      id: id,
      label: label ?? this.label,
      pausesOthers: pausesOthers ?? this.pausesOthers,
      requiresName: requiresName ?? this.requiresName,
      isBreak: isBreak ?? this.isBreak,
      breakId: clearBreakId ? null : (breakId ?? this.breakId),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'pausesOthers': pausesOthers,
        'requiresName': requiresName,
        'isBreak': isBreak,
        'breakId': breakId,
      };

  factory ProfileButton.fromJson(Map<String, dynamic> json) {
    final legacyKind = json['activityKind'] as String?;
    final isBreak =
        json['isBreak'] as bool? ?? legacyKind == 'breakTime';
    final rawLabel = json['label'] as String? ?? 'Action';
    return ProfileButton(
      id: json['id'] as String,
      label: migrateButtonLabel(rawLabel),
      pausesOthers: json['pausesOthers'] as bool? ?? true,
      requiresName: json['requiresName'] as bool? ?? !isBreak,
      isBreak: isBreak,
      breakId: json['breakId'] as String?,
    );
  }

  /// Old CTA-style presets → noun labels.
  static String migrateButtonLabel(String label) {
    return switch (label) {
      'Add task' => 'Task',
      'Add meeting' => 'Meeting',
      _ => label,
    };
  }
}

class ProfileRules {
  const ProfileRules({
    this.oneActiveTimer = true,
    this.resumePreviousOnEnd = true,
    this.silenceWhenInactive = false,
  });

  final bool oneActiveTimer;
  final bool resumePreviousOnEnd;
  final bool silenceWhenInactive;

  ProfileRules copyWith({
    bool? oneActiveTimer,
    bool? resumePreviousOnEnd,
    bool? silenceWhenInactive,
  }) {
    return ProfileRules(
      oneActiveTimer: oneActiveTimer ?? this.oneActiveTimer,
      resumePreviousOnEnd: resumePreviousOnEnd ?? this.resumePreviousOnEnd,
      silenceWhenInactive: silenceWhenInactive ?? this.silenceWhenInactive,
    );
  }

  Map<String, dynamic> toJson() => {
        'oneActiveTimer': oneActiveTimer,
        'resumePreviousOnEnd': resumePreviousOnEnd,
        'silenceWhenInactive': silenceWhenInactive,
      };

  factory ProfileRules.fromJson(Map<String, dynamic> json) {
    return ProfileRules(
      oneActiveTimer: json['oneActiveTimer'] as bool? ?? true,
      resumePreviousOnEnd: json['resumePreviousOnEnd'] as bool? ?? true,
      silenceWhenInactive: json['silenceWhenInactive'] as bool? ?? false,
    );
  }
}

class ActivityEntry {
  ActivityEntry({
    String? id,
    required this.profileId,
    required this.buttonId,
    required this.label,
    required this.kind,
    required this.startedAt,
    this.endedAt,
    this.pausedAt,
    this.accumulatedSeconds = 0,
  }) : id = id ?? _uuid.v4();

  final String id;
  final String profileId;
  final String buttonId;
  final String label;
  final ActivityKind kind;
  final DateTime startedAt;
  final DateTime? endedAt;
  final DateTime? pausedAt;
  final int accumulatedSeconds;

  bool get isRunning => endedAt == null && pausedAt == null;
  bool get isPaused => endedAt == null && pausedAt != null;

  int elapsedSeconds({DateTime? now}) {
    final n = now ?? DateTime.now();
    if (endedAt != null || pausedAt != null) {
      return accumulatedSeconds;
    }
    return accumulatedSeconds + n.difference(startedAt).inSeconds;
  }

  ActivityEntry copyWith({
    String? label,
    DateTime? endedAt,
    DateTime? pausedAt,
    DateTime? startedAt,
    int? accumulatedSeconds,
    bool clearPausedAt = false,
    bool clearEndedAt = false,
  }) {
    return ActivityEntry(
      id: id,
      profileId: profileId,
      buttonId: buttonId,
      label: label ?? this.label,
      kind: kind,
      startedAt: startedAt ?? this.startedAt,
      endedAt: clearEndedAt ? null : (endedAt ?? this.endedAt),
      pausedAt: clearPausedAt ? null : (pausedAt ?? this.pausedAt),
      accumulatedSeconds: accumulatedSeconds ?? this.accumulatedSeconds,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'profileId': profileId,
        'buttonId': buttonId,
        'label': label,
        'kind': kind.name,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt?.toIso8601String(),
        'pausedAt': pausedAt?.toIso8601String(),
        'accumulatedSeconds': accumulatedSeconds,
      };

  factory ActivityEntry.fromJson(Map<String, dynamic> json) {
    return ActivityEntry(
      id: json['id'] as String?,
      profileId: json['profileId'] as String,
      buttonId: json['buttonId'] as String,
      label: json['label'] as String,
      kind: ActivityKind.values.byName(json['kind'] as String),
      startedAt: DateTime.parse(json['startedAt'] as String),
      endedAt: json['endedAt'] != null
          ? DateTime.parse(json['endedAt'] as String)
          : null,
      pausedAt: json['pausedAt'] != null
          ? DateTime.parse(json['pausedAt'] as String)
          : null,
      accumulatedSeconds: json['accumulatedSeconds'] as int? ?? 0,
    );
  }
}
