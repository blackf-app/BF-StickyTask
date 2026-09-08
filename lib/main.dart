import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/desktop_integration.dart';
import 'app/launch_at_startup.dart';
import 'app/settings_controller.dart';
import 'app/theme.dart';
import 'data/local_store.dart';
import 'data/note_repo.dart';
import 'data/sync_service.dart';
import 'data/update_service.dart';
import 'ui/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Cửa sổ phải dựng xong trước runApp để không bị nháy khung mặc định.
  await DesktopIntegration.instance.setUpWindow();

  final repo = NoteRepo(LocalStore());
  await repo.load();

  final settings = SettingsController();
  await settings.load();

  // Đọc xem OS đang có đặt mở app lúc khởi động máy không. Trạng thái thật
  // nằm ở OS (login item macOS / registry Windows) chứ không ở prefs, nên
  // phải hỏi lại mỗi lần mở — user tắt nó ở System Settings thì app biết.
  await LaunchAtStartup.instance.load();

  // Chỉ đọc version đang chạy + version đã bỏ qua; KHÔNG gọi mạng ở đây để
  // bootstrap không phải chờ GitHub. Việc kiểm bản mới do HomePage kích sau
  // frame đầu (xem `_checkUpdateOnStartup`).
  final update = UpdateService();
  await update.load();

  runApp(
    BfStickyTaskApp(
      repo: repo,
      sync: SyncService(repo),
      settings: settings,
      update: update,
    ),
  );
}

class BfStickyTaskApp extends StatefulWidget {
  const BfStickyTaskApp({
    super.key,
    required this.repo,
    required this.sync,
    required this.settings,
    required this.update,
  });

  final NoteRepo repo;
  final SyncService sync;
  final SettingsController settings;
  final UpdateService update;

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
        // Chuỗi dựng sẵn của Material (rõ nhất là date picker của bộ lọc
        // History) theo tiếng Việt cho khớp phần còn lại của app.
        locale: const Locale('vi'),
        supportedLocales: const [Locale('vi'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: buildStickyTheme(Brightness.light),
        darkTheme: buildStickyTheme(Brightness.dark),
        themeMode: widget.settings.themeMode,
        home: Scaffold(
          backgroundColor: Colors.transparent,
          body: HomePage(
            repo: widget.repo,
            sync: widget.sync,
            settings: widget.settings,
            update: widget.update,
          ),
        ),
      ),
    );
  }
}
