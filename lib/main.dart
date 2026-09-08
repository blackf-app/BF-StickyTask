import 'package:flutter/material.dart';

import 'app/desktop_integration.dart';
import 'app/settings_controller.dart';
import 'app/theme.dart';
import 'data/local_store.dart';
import 'data/note_repo.dart';
import 'data/sync_service.dart';
import 'ui/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Cửa sổ phải dựng xong trước runApp để không bị nháy khung mặc định.
  await DesktopIntegration.instance.setUpWindow();

  final repo = NoteRepo(LocalStore());
  await repo.load();

  final settings = SettingsController();
  await settings.load();

  runApp(
    BfStickyTaskApp(
      repo: repo,
      sync: SyncService(repo),
      settings: settings,
    ),
  );
}

class BfStickyTaskApp extends StatefulWidget {
  const BfStickyTaskApp({
    super.key,
    required this.repo,
    required this.sync,
    required this.settings,
  });

  final NoteRepo repo;
  final SyncService sync;
  final SettingsController settings;

  @override
  State<BfStickyTaskApp> createState() => _BfStickyTaskAppState();
}

class _BfStickyTaskAppState extends State<BfStickyTaskApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DesktopIntegration.instance.attach();
    widget.sync.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        widget.sync.syncNow();
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        widget.repo.flush();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.sync.dispose();
    widget.repo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) => MaterialApp(
        title: 'BF-StickyTask',
        debugShowCheckedModeBanner: false,
        theme: buildStickyTheme(Brightness.light),
        darkTheme: buildStickyTheme(Brightness.dark),
        themeMode: widget.settings.themeMode,
        home: Scaffold(
          backgroundColor: Colors.transparent,
          body: HomePage(
            repo: widget.repo,
            sync: widget.sync,
            settings: widget.settings,
          ),
        ),
      ),
    );
  }
}
