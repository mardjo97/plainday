import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/app_store.dart';

/// Background entry-point for home-widget taps (does not open the app).
///
/// Kept lightweight: no notification plugin init (that hangs on some OEMs).
@pragma('vm:entry-point')
Future<void> plaindayWidgetBackgroundCallback(Uri? uri) async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('Plainday widget background: $uri');
  if (uri == null) return;

  try {
    final store = await AppStore.load(
      enableNotifications: false,
      enableWidgets: true,
    );
    final message = await _handle(store, uri);
    await _bumpRevision();
    await store.widgets.update(store, toast: message);
    debugPrint('Plainday widget background done: $message');
  } catch (e, st) {
    debugPrint('Plainday widget background failed: $e\n$st');
    try {
      await HomeWidget.saveWidgetData<String>(
        'toast_message',
        'Action failed',
      );
      await HomeWidget.updateWidget(
        name: 'PlaindayWidgetProvider',
        androidName: 'PlaindayWidgetProvider',
        qualifiedAndroidName: 'rs.hexatech.plainday.PlaindayWidgetProvider',
      );
    } catch (_) {}
  }
}

Future<void> _bumpRevision() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    'widget_revision',
    DateTime.now().millisecondsSinceEpoch.toString(),
  );
}

Future<String> _handle(AppStore store, Uri uri) async {
  final host = uri.host;
  if (host == 'start_day') {
    if (store.dayStarted) return 'Day already on';
    await store.startDay();
    return 'Day started';
  }
  if (host == 'end_day') {
    if (!store.dayStarted) return 'Day already off';
    await store.endDay();
    return 'Day ended';
  }
  if (host == 'button') {
    final buttonId =
        uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
    if (buttonId.isEmpty) return 'Unknown action';
    final profile = store.activeProfile;
    var label = 'Activity';
    if (profile != null) {
      for (final b in profile.buttons) {
        if (b.id == buttonId) {
          label = b.label;
          break;
        }
      }
    }
    await store.startFromButtonId(buttonId);
    return 'Started $label';
  }
  return 'Updated';
}

/// Call once from the UI isolate so Android can find the background callback.
Future<void> registerPlaindayWidgetBackground() async {
  await HomeWidget.registerInteractivityCallback(
    plaindayWidgetBackgroundCallback,
  );
}
