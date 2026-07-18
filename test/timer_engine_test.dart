import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:plainday/models/profile.dart';
import 'package:plainday/state/app_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('start meeting pauses task and ending resumes it', () async {
    final store = await AppStore.load(enableNotifications: false);
    final profile = store.activeProfile!;
    final task = profile.buttons.firstWhere((b) => b.label == 'Task');
    final meeting = profile.buttons.firstWhere((b) => b.label == 'Meeting');

    await store.startFromButton(task);
    expect(store.currentActivity?.label, 'Task');

    await store.startFromButton(meeting);
    expect(store.currentActivity?.label, 'Meeting');
    expect(store.entries.where((e) => e.isPaused).length, 1);

    await store.endCurrent();
    expect(store.currentActivity?.label, 'Task');
  });

  test('end day clears running timers', () async {
    final store = await AppStore.load(enableNotifications: false);
    final task = store.activeProfile!.buttons.first;
    await store.startFromButton(task);
    await store.endDay();
    expect(store.dayStarted, isFalse);
    expect(store.currentActivity, isNull);
  });

  test('start and end day are logged on the timeline', () async {
    final store = await AppStore.load(enableNotifications: false);
    final profileName = store.activeProfile!.name;

    await store.startDay();
    expect(store.dayStarted, isTrue);
    expect(
      store.todayEntries.any((e) => e.kind == ActivityKind.dayStart),
      isTrue,
    );
    expect(
      store.todayEntries.firstWhere((e) => e.kind == ActivityKind.dayStart).label,
      contains(profileName),
    );

    await store.endDay();
    expect(store.dayStarted, isFalse);
    expect(
      store.todayEntries.any((e) => e.kind == ActivityKind.dayEnd),
      isTrue,
    );
  });

  test('switching profile while day is on ends day and resets timer', () async {
    final store = await AppStore.load(enableNotifications: false);
    final first = store.activeProfile!;
    final second = await store.addProfileFromPreset(
      Profile(
        name: 'Focus',
        startMinutes: 9 * 60,
        endMinutes: 17 * 60,
      ),
      activate: false,
    );

    final task = first.buttons.firstWhere((b) => b.label == 'Task');
    await store.startFromButton(task);
    expect(store.currentActivity, isNotNull);
    expect(store.hasOpenDaySession, isTrue);

    await store.switchProfileResettingDay(second.id);
    expect(store.activeProfileId, second.id);
    expect(store.dayStarted, isFalse);
    expect(store.currentActivity, isNull);
    expect(
      store.todayEntries.any(
        (e) => e.kind == ActivityKind.dayEnd && e.profileId == first.id,
      ),
      isTrue,
    );
  });
}
