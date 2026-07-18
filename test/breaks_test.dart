import 'package:flutter_test/flutter_test.dart';

import 'package:plainday/models/profile.dart';
import 'package:plainday/utils/breaks.dart';

void main() {
  Profile profileWith(List<BreakWindow> breaks) {
    return Profile(
      name: 'Test',
      breaks: breaks,
      startMinutes: 9 * 60,
      endMinutes: 17 * 60,
    );
  }

  test('nextBreakWindow prefers current, then upcoming, then first', () {
    final lunch = BreakWindow(
      id: 'lunch',
      label: 'Lunch',
      startMinutes: 12 * 60 + 30,
      endMinutes: 13 * 60,
    );
    final coffee = BreakWindow(
      id: 'coffee',
      label: 'Coffee',
      startMinutes: 15 * 60,
      endMinutes: 15 * 60 + 15,
    );
    final profile = profileWith([lunch, coffee]);

    // Before lunch → lunch
    expect(
      nextBreakWindow(
        profile,
        now: DateTime(2026, 7, 18, 10, 0),
      )?.id,
      'lunch',
    );

    // During lunch → lunch
    expect(
      nextBreakWindow(
        profile,
        now: DateTime(2026, 7, 18, 12, 45),
      )?.id,
      'lunch',
    );

    // After lunch, before coffee → coffee
    expect(
      nextBreakWindow(
        profile,
        now: DateTime(2026, 7, 18, 14, 0),
      )?.id,
      'coffee',
    );

    // After all → first (tomorrow cycle)
    expect(
      nextBreakWindow(
        profile,
        now: DateTime(2026, 7, 18, 18, 0),
      )?.id,
      'lunch',
    );
  });

  test('resolveBreakWindow uses linked id when present', () {
    final lunch = BreakWindow(
      id: 'lunch',
      label: 'Lunch',
      startMinutes: 12 * 60 + 30,
      endMinutes: 13 * 60,
    );
    final coffee = BreakWindow(
      id: 'coffee',
      label: 'Coffee',
      startMinutes: 15 * 60,
      endMinutes: 15 * 60 + 15,
    );
    final profile = profileWith([lunch, coffee]);

    expect(
      resolveBreakWindow(
        profile,
        breakId: 'coffee',
        now: DateTime(2026, 7, 18, 10, 0),
      )?.label,
      'Coffee',
    );
    expect(
      resolveBreakWindow(
        profile,
        breakId: null,
        now: DateTime(2026, 7, 18, 10, 0),
      )?.label,
      'Lunch',
    );
  });
}
