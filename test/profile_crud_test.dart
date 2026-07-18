import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:plainday/data/presets.dart';
import 'package:plainday/state/app_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('duplicate profile creates new ids and keeps structure', () async {
    final store = await AppStore.load(enableNotifications: false);
    final originalId = store.activeProfileId!;
    final originalButtons = store.activeProfile!.buttons.length;

    await store.duplicateProfile(originalId);

    expect(store.profiles.length, 2);
    expect(store.activeProfileId, isNot(originalId));
    expect(store.activeProfile!.buttons.length, originalButtons);
    expect(store.activeProfile!.name.contains('copy'), isTrue);
  });

  test('delete refuses last profile', () async {
    final store = await AppStore.load(enableNotifications: false);
    expect(await store.deleteProfile(store.activeProfileId!), isFalse);
    expect(store.profiles.length, 1);
  });

  test('update profile persists name and schedule', () async {
    final store = await AppStore.load(enableNotifications: false);
    final updated = store.activeProfile!.copyWith(
      name: 'Office',
      startMinutes: 8 * 60,
    );
    await store.updateProfile(updated);
    expect(store.activeProfile!.name, 'Office');
    expect(store.activeProfile!.startMinutes, 8 * 60);
  });

  test('csv export includes header and rows', () async {
    final store = await AppStore.load(enableNotifications: false);
    await store.startFromButton(store.activeProfile!.buttons.first);
    final csv = store.buildCsv(week: false);
    expect(
      csv.startsWith('date,start,end,label,kind,seconds,profile,profileId'),
      isTrue,
    );
    expect(csv.split('\n').length, greaterThan(1));
  });

  test('blank preset adds empty-ish profile', () async {
    final store = await AppStore.load(enableNotifications: false);
    await store.addProfileFromPreset(ProfilePresets.blank());
    expect(store.activeProfile!.name, 'Blank');
  });
}
