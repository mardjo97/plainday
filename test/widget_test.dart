import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:plainday/main.dart';
import 'package:plainday/state/app_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Plainday home shows brand and start day', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load(enableNotifications: false);

    await tester.pumpWidget(PlaindayApp(store: store));
    await tester.pump();

    expect(find.text('Plainday'), findsWidgets);
    expect(find.text('Start day'), findsOneWidget);
    expect(find.text('Task'), findsOneWidget);
  });
}
