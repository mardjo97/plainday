import 'package:uuid/uuid.dart';

import '../models/profile.dart';

const _uuid = Uuid();

/// Preset configs — data only. Creating from a preset copies into a Profile.
abstract final class ProfilePresets {
  static List<Profile> all() => [
        work(),
        deepFocus(),
        meetingDay(),
        study(),
        freelancer(),
        weekend(),
        vacation(),
        sickRest(),
        blank(),
      ];

  static Profile work() {
    const lunchId = 'break-lunch';
    return Profile(
      name: 'Work',
      colorValue: 0xFF2F6F5E,
      startMinutes: 9 * 60,
      endMinutes: 17 * 60,
      breaks: const [
        BreakWindow(
          id: lunchId,
          label: 'Lunch',
          startMinutes: 12 * 60 + 30,
          endMinutes: 13 * 60,
        ),
        BreakWindow(
          id: 'break-coffee',
          label: 'Coffee',
          startMinutes: 15 * 60,
          endMinutes: 15 * 60 + 15,
        ),
      ],
      reminders: [
        ProfileReminder(
          id: _uuid.v4(),
          label: 'Start day',
          kind: ReminderKind.atProfileStart,
          offsetMinutes: -5,
          actionId: 'start_day',
        ),
        ProfileReminder(
          id: _uuid.v4(),
          label: 'End day',
          kind: ReminderKind.atProfileEnd,
          offsetMinutes: 0,
          actionId: 'end_day',
        ),
        ProfileReminder(
          id: _uuid.v4(),
          label: 'Stand up',
          kind: ReminderKind.interval,
          intervalMinutes: 30,
        ),
        ProfileReminder(
          id: _uuid.v4(),
          label: 'Go to break',
          kind: ReminderKind.relativeToBreak,
          offsetMinutes: -30,
          breakId: lunchId,
          actionId: 'go_to_break',
        ),
        ProfileReminder(
          id: _uuid.v4(),
          label: 'Return from break',
          kind: ReminderKind.relativeToBreak,
          offsetMinutes: 0,
          breakId: lunchId,
          actionId: 'return_from_break',
        ),
      ],
      buttons: [
        ProfileButton(
          id: _uuid.v4(),
          label: 'Task',
          requiresName: true,
        ),
        ProfileButton(
          id: _uuid.v4(),
          label: 'Meeting',
          requiresName: true,
        ),
        ProfileButton(
          id: _uuid.v4(),
          label: 'Break',
          isBreak: true,
        ),
      ],
    );
  }

  static Profile deepFocus() {
    return Profile(
      name: 'Deep Focus',
      colorValue: 0xFF3D5A80,
      startMinutes: 9 * 60,
      endMinutes: 17 * 60,
      breaks: const [
        BreakWindow(
          id: 'break-lunch',
          label: 'Lunch',
          startMinutes: 12 * 60 + 30,
          endMinutes: 13 * 60,
        ),
      ],
      reminders: [
        ProfileReminder(
          id: _uuid.v4(),
          label: 'Start day',
          kind: ReminderKind.atProfileStart,
          actionId: 'start_day',
        ),
        ProfileReminder(
          id: _uuid.v4(),
          label: 'End day',
          kind: ReminderKind.atProfileEnd,
          actionId: 'end_day',
        ),
        ProfileReminder(
          id: _uuid.v4(),
          label: 'Stand up',
          kind: ReminderKind.interval,
          intervalMinutes: 45,
        ),
      ],
      buttons: [
        ProfileButton(
          id: _uuid.v4(),
          label: 'Task',
          requiresName: true,
        ),
        ProfileButton(
          id: _uuid.v4(),
          label: 'Short break',
          isBreak: true,
        ),
        ProfileButton(
          id: _uuid.v4(),
          label: 'Break',
          isBreak: true,
        ),
      ],
    );
  }

  static Profile meetingDay() {
    return Profile(
      name: 'Meeting Day',
      colorValue: 0xFF8B5E3C,
      startMinutes: 9 * 60,
      endMinutes: 18 * 60,
      breaks: const [
        BreakWindow(
          id: 'break-lunch',
          label: 'Lunch',
          startMinutes: 12 * 60 + 30,
          endMinutes: 13 * 60,
        ),
      ],
      reminders: [
        ProfileReminder(
          id: _uuid.v4(),
          label: 'Start day',
          kind: ReminderKind.atProfileStart,
          actionId: 'start_day',
        ),
        ProfileReminder(
          id: _uuid.v4(),
          label: 'End day',
          kind: ReminderKind.atProfileEnd,
          actionId: 'end_day',
        ),
        ProfileReminder(
          id: _uuid.v4(),
          label: 'Stand up',
          kind: ReminderKind.interval,
          intervalMinutes: 45,
        ),
      ],
      buttons: [
        ProfileButton(
          id: _uuid.v4(),
          label: 'Meeting',
          requiresName: true,
        ),
        ProfileButton(
          id: _uuid.v4(),
          label: 'Task',
          requiresName: true,
        ),
        ProfileButton(
          id: _uuid.v4(),
          label: 'Break',
          isBreak: true,
        ),
      ],
    );
  }

  static Profile study() {
    return Profile(
      name: 'Study',
      colorValue: 0xFF4A6FA5,
      startMinutes: 10 * 60,
      endMinutes: 18 * 60,
      activeDays: const [1, 2, 3, 4, 5, 6, 7],
      reminders: [
        ProfileReminder(
          id: _uuid.v4(),
          label: 'Start day',
          kind: ReminderKind.atProfileStart,
          actionId: 'start_day',
        ),
        ProfileReminder(
          id: _uuid.v4(),
          label: 'End day',
          kind: ReminderKind.atProfileEnd,
          actionId: 'end_day',
        ),
        ProfileReminder(
          id: _uuid.v4(),
          label: 'Focus break',
          kind: ReminderKind.interval,
          intervalMinutes: 50,
        ),
      ],
      buttons: [
        ProfileButton(
          id: _uuid.v4(),
          label: 'Study block',
          requiresName: true,
        ),
        ProfileButton(
          id: _uuid.v4(),
          label: 'Break',
          isBreak: true,
        ),
        ProfileButton(
          id: _uuid.v4(),
          label: 'Review',
          requiresName: true,
        ),
      ],
    );
  }

  static Profile freelancer() {
    return Profile(
      name: 'Freelancer',
      colorValue: 0xFF5C6B73,
      startMinutes: 9 * 60,
      endMinutes: 18 * 60,
      reminders: [
        ProfileReminder(
          id: _uuid.v4(),
          label: 'Start day',
          kind: ReminderKind.atProfileStart,
          actionId: 'start_day',
        ),
        ProfileReminder(
          id: _uuid.v4(),
          label: 'End day',
          kind: ReminderKind.atProfileEnd,
          actionId: 'end_day',
        ),
        ProfileReminder(
          id: _uuid.v4(),
          label: 'Stand up',
          kind: ReminderKind.interval,
          intervalMinutes: 30,
        ),
      ],
      buttons: [
        ProfileButton(
          id: _uuid.v4(),
          label: 'Client work',
          requiresName: true,
        ),
        ProfileButton(
          id: _uuid.v4(),
          label: 'Admin',
          requiresName: true,
        ),
        ProfileButton(
          id: _uuid.v4(),
          label: 'Meeting',
          requiresName: true,
        ),
        ProfileButton(
          id: _uuid.v4(),
          label: 'Break',
          isBreak: true,
        ),
      ],
    );
  }

  static Profile weekend() {
    return Profile(
      name: 'Weekend',
      colorValue: 0xFF6B7F5C,
      startMinutes: 10 * 60,
      endMinutes: 16 * 60,
      activeDays: const [6, 7],
      reminders: [
        ProfileReminder(
          id: _uuid.v4(),
          label: 'Start day',
          kind: ReminderKind.atProfileStart,
          actionId: 'start_day',
          enabled: false,
        ),
        ProfileReminder(
          id: _uuid.v4(),
          label: 'End day',
          kind: ReminderKind.atProfileEnd,
          actionId: 'end_day',
          enabled: false,
        ),
      ],
      buttons: [
        ProfileButton(
          id: _uuid.v4(),
          label: 'Personal task',
          requiresName: true,
        ),
        ProfileButton(
          id: _uuid.v4(),
          label: 'Errand',
          requiresName: true,
        ),
        ProfileButton(
          id: _uuid.v4(),
          label: 'Break',
          isBreak: true,
        ),
      ],
    );
  }

  static Profile vacation() {
    return Profile(
      name: 'Vacation',
      colorValue: 0xFF7A8B99,
      startMinutes: 0,
      endMinutes: 24 * 60 - 1,
      activeDays: const [1, 2, 3, 4, 5, 6, 7],
      reminders: const [],
      buttons: [
        ProfileButton(
          id: _uuid.v4(),
          label: 'Note',
          pausesOthers: false,
          requiresName: true,
        ),
      ],
      rules: const ProfileRules(
        oneActiveTimer: false,
        resumePreviousOnEnd: false,
        silenceWhenInactive: true,
      ),
    );
  }

  static Profile sickRest() {
    return Profile(
      name: 'Sick / Rest',
      colorValue: 0xFF9A8F7A,
      startMinutes: 0,
      endMinutes: 24 * 60 - 1,
      activeDays: const [1, 2, 3, 4, 5, 6, 7],
      reminders: [
        ProfileReminder(
          id: _uuid.v4(),
          label: 'Check in',
          kind: ReminderKind.atProfileEnd,
          offsetMinutes: -60,
          enabled: false,
        ),
      ],
      buttons: [
        ProfileButton(
          id: _uuid.v4(),
          label: 'Rest',
          isBreak: true,
        ),
        ProfileButton(
          id: _uuid.v4(),
          label: 'Note',
          pausesOthers: false,
          requiresName: true,
        ),
      ],
      rules: const ProfileRules(
        silenceWhenInactive: true,
      ),
    );
  }

  static Profile blank() {
    return Profile(
      name: 'Blank',
      colorValue: 0xFF5A5A5A,
      startMinutes: 9 * 60,
      endMinutes: 17 * 60,
      reminders: const [],
      breaks: const [],
      buttons: const [],
    );
  }
}
