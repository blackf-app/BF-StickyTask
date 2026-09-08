import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bf_stickytask/app/settings_controller.dart';
import 'package:bf_stickytask/data/local_store.dart';
import 'package:bf_stickytask/data/note_repo.dart';
import 'package:bf_stickytask/data/sync_service.dart';
import 'package:bf_stickytask/app/theme.dart';
import 'package:bf_stickytask/ui/home_page.dart';

class _MemoryStore extends LocalStore {
  @override
  Future<LocalSnapshot> load() async => const LocalSnapshot(notes: []);

  @override
  Future<void> save(List notes, {String? lastPull}) async {}
}

Future<NoteRepo> _pumpApp(
  WidgetTester tester, {
  SettingsController? settings,
  Brightness brightness = Brightness.light,
}) async {
  final repo = NoteRepo(_MemoryStore());
  await repo.load();
  await tester.pumpWidget(
    MaterialApp(
      theme: buildStickyTheme(brightness),
      home: Scaffold(
        body: HomePage(
          repo: repo,
          sync: SyncService(repo),
          settings: settings ?? SettingsController(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

/// Cho debounce ghi file (200ms) chạy hết để test không còn timer treo.
Future<void> _drainDebounce(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

Future<void> _addNote(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).last, text);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('thêm việc ở ô dưới thì hiện lên tab Current', (tester) async {
    final repo = await _pumpApp(tester);

    expect(find.text('Không còn việc nào'), findsOneWidget);
    await _addNote(tester, 'mua sữa');

    expect(find.text('mua sữa'), findsOneWidget);
    expect(repo.current.single.text, 'mua sữa');
    await _drainDebounce(tester);
  });

  testWidgets('tick done thì dòng rời Current và nằm ở tab History',
      (tester) async {
    await _pumpApp(tester);
    await _addNote(tester, 'việc xong');

    // Bấm checkbox tròn đầu dòng.
    await tester.tap(find.byType(AnimatedContainer).last);
    await tester.pumpAndSettle();

    expect(find.text('việc xong'), findsNothing);
    expect(find.text('Không còn việc nào'), findsOneWidget);

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    expect(find.text('việc xong'), findsOneWidget);
    expect(find.text('1 việc đã xong'), findsOneWidget);
    await _drainDebounce(tester);
  });

  testWidgets('tap vào dòng để sửa inline rồi Enter là lưu', (tester) async {
    final repo = await _pumpApp(tester);
    await _addNote(tester, 'ten cu');

    await tester.tap(find.text('ten cu'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'ten moi');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(repo.current.single.text, 'ten moi');
    expect(find.text('ten moi'), findsOneWidget);
    await _drainDebounce(tester);
  });

  testWidgets('badge số lượng trên 2 tab khớp với dữ liệu', (tester) async {
    final repo = await _pumpApp(tester);
    await _addNote(tester, 'a');
    await _addNote(tester, 'b');
    await _addNote(tester, 'c');

    repo.setDone(repo.current.first.id, true);
    await tester.pumpAndSettle();

    expect(find.text('2'), findsOneWidget); // Current
    expect(find.text('1'), findsOneWidget); // History
    await _drainDebounce(tester);
  });

  testWidgets('nút giao diện xoay vòng tự động → sáng → tối', (tester) async {
    final settings = SettingsController();
    await _pumpApp(tester, settings: settings);

    expect(find.byIcon(Icons.brightness_auto_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.brightness_auto_outlined));
    await tester.pumpAndSettle();
    expect(settings.themeMode, ThemeMode.light);
    expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.light_mode_outlined));
    await tester.pumpAndSettle();
    expect(settings.themeMode, ThemeMode.dark);
    expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.dark_mode_outlined));
    await tester.pumpAndSettle();
    expect(settings.themeMode, ThemeMode.system);
  });

  testWidgets('theme tối thì chữ note dùng màu của bảng màu tối',
      (tester) async {
    await _pumpApp(tester, brightness: Brightness.dark);
    await _addNote(tester, 'viec trong dark mode');

    final text = tester.widget<Text>(find.text('viec trong dark mode'));
    expect(text.style?.color, PaperColors.dark.ink);
    await _drainDebounce(tester);
  });
}
