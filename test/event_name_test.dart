import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:plainday/models/profile.dart';
import 'package:plainday/state/app_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('events start with button label and can be renamed later', () async {
    final store = await AppStore.load(enableNotifications: false);
    final task =
        store.activeProfile!.buttons.firstWhere((b) => b.label == 'Task');
    final brk =
        store.activeProfile!.buttons.firstWhere((b) => b.isBreak);

    await store.startFromButton(task);
    expect(store.currentActivity?.label, task.label);
    expect(store.currentActivity?.kind, ActivityKind.task);
    expect(store.usesButtonLabel(store.currentActivity!), isTrue);
    expect(store.currentCanBeNamed, isTrue);

    await store.renameCurrentActivity('Ship P2');
    expect(store.currentActivity?.label, 'Ship P2');
    expect(store.usesButtonLabel(store.currentActivity!), isFalse);

    await store.startFromButton(brk);
    expect(store.currentActivity?.label, 'Lunch');
    expect(store.currentActivity?.kind, ActivityKind.breakTime);
    expect(store.currentCanBeNamed, isFalse);
  });

  test('custom button label becomes the event name', () async {
    final store = await AppStore.load(enableNotifications: false);
    final profile = store.activeProfile!;
    final custom = ProfileButton(
      id: 'custom-deep-work',
      label: 'Deep work',
      requiresName: true,
    );
    await store.updateProfile(
      profile.copyWith(buttons: [...profile.buttons, custom]),
    );

    await store.startFromButton(custom);
    expect(store.currentActivity?.label, 'Deep work');
    expect(store.usesButtonLabel(store.currentActivity!), isTrue);
  });

  test('legacy Add task label migrates to Task', () {
    final button = ProfileButton.fromJson({
      'id': '1',
      'label': 'Add task',
      'activityKind': 'task',
      'requiresName': true,
    });
    expect(button.label, 'Task');
    expect(button.isBreak, isFalse);
    expect(button.requiresName, isTrue);
  });
}
