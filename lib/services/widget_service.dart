import 'package:home_widget/home_widget.dart';

import '../models/profile.dart';
import '../state/app_store.dart';

/// Pushes glanceable state to the Android (and future iOS) home-screen widget.
class WidgetService {
  static const androidProvider = 'PlaindayWidgetProvider';
  static const iosName = 'PlaindayWidget';
  static const maxActionButtons = 4;

  /// When false, skips platform channels (used in unit/widget tests).
  bool enabled = true;

  Future<void> update(AppStore store, {String? toast}) async {
    if (!enabled) return;

    try {
      final profile = store.activeProfile;
      final current = store.currentActivity;
      final canName = store.currentCanBeNamed;
      final buttons = profile?.buttons ?? const <ProfileButton>[];
      final activeButtonId = current?.buttonId;

      await HomeWidget.saveWidgetData<String>(
        'profile_name',
        profile?.name ?? 'Plainday',
      );
      await HomeWidget.saveWidgetData<String>(
        'day_status',
        store.dayStarted ? 'Day on' : 'Day off',
      );
      await HomeWidget.saveWidgetData<String>(
        'current_label',
        current?.label ??
            (store.dayStarted ? 'Nothing running' : 'Tap to start day'),
      );
      await HomeWidget.saveWidgetData<String>(
        'current_elapsed',
        current == null ? '--:--' : _format(current.elapsedSeconds()),
      );
      await HomeWidget.saveWidgetData<String>(
        'hint',
        _hint(store),
      );
      await HomeWidget.saveWidgetData<bool>('can_name', canName);
      await HomeWidget.saveWidgetData<String>(
        'name_button',
        !canName
            ? ''
            : (current != null && store.usesButtonLabel(current)
                ? 'Add name'
                : 'Edit name'),
      );

      await HomeWidget.saveWidgetData<String>(
        'day_button_label',
        store.dayStarted ? 'End day' : 'Start day',
      );
      await HomeWidget.saveWidgetData<String>(
        'day_button_action',
        store.dayStarted ? 'end_day' : 'start_day',
      );

      final shown = buttons.take(maxActionButtons).toList();
      await HomeWidget.saveWidgetData<int>('action_count', shown.length);
      for (var i = 0; i < maxActionButtons; i++) {
        if (i < shown.length) {
          final button = shown[i];
          final active = button.id == activeButtonId;
          await HomeWidget.saveWidgetData<String>(
            'action_${i}_label',
            active ? 'End ${button.label}' : button.label,
          );
          await HomeWidget.saveWidgetData<String>(
            'action_${i}_id',
            button.id,
          );
        } else {
          await HomeWidget.saveWidgetData<String>('action_${i}_label', '');
          await HomeWidget.saveWidgetData<String>('action_${i}_id', '');
        }
      }

      if (toast != null && toast.isNotEmpty) {
        await HomeWidget.saveWidgetData<String>('toast_message', toast);
      }

      await HomeWidget.updateWidget(
        name: androidProvider,
        androidName: androidProvider,
        iOSName: iosName,
        qualifiedAndroidName: 'rs.hexatech.plainday.PlaindayWidgetProvider',
      );
    } catch (_) {
      // Widget may not be installed / platform unavailable.
    }
  }

  String _hint(AppStore store) {
    final prompt = store.breakPrompt;
    return switch (prompt) {
      BreakPrompt.goToBreak => 'Suggestion: Go to break',
      BreakPrompt.returnFromBreak => 'Suggestion: Return from break',
      null => store.dayStarted ? 'Logging' : 'Ready when you are',
    };
  }

  String _format(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }
}
