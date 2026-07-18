import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'services/widget_background.dart';
import 'state/app_store.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await registerPlaindayWidgetBackground();
  final store = await AppStore.load();
  runApp(PlaindayApp(store: store));
}

class PlaindayApp extends StatefulWidget {
  const PlaindayApp({super.key, required this.store});

  final AppStore store;

  @override
  State<PlaindayApp> createState() => _PlaindayAppState();
}

class _PlaindayAppState extends State<PlaindayApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.store.pullRemoteChanges();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.store,
      child: MaterialApp(
        title: 'Plainday',
        debugShowCheckedModeBanner: false,
        theme: PlaindayTheme.light(),
        home: const HomeScreen(),
      ),
    );
  }
}
