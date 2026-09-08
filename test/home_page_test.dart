import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bf_stickytask/app/settings_controller.dart';
import 'package:bf_stickytask/data/local_store.dart';
import 'package:bf_stickytask/data/note_repo.dart';
import 'package:bf_stickytask/data/sync_service.dart';
import 'package:bf_stickytask/data/update_service.dart';
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
  UpdateService? update,
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
          // Fetcher trả null: HomePage kiểm bản mới lúc mở nên test KHÔNG
          // được để nó gọi GitHub thật.
          update: update ?? _offlineUpdate(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

UpdateService _offlineUpdate() =>
    UpdateService(fetcher: () async => null, currentVersion: '1.0.0');

/// Cho debounce ghi file (200ms) chạy hết để test không còn timer treo.
Future<void> _drainDebounce(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

/// Hover vào dòng [row] rồi bấm nút xoá của nó. Trên desktop `_TileAction`
/// chỉ hiện khi hover — chưa hover là `IgnorePointer` nên tap không ăn.
///
/// Pointer được nhả ngay sau khi tap: thêm pointer chuột thứ hai khi chưa nhả
/// cái đầu là vỡ assert trong MouseTracker, mà test xoá thì bấm 2 lần (huỷ
/// rồi xoá thật).
Future<void> _tapDelete(WidgetTester tester, Finder row) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  await gesture.moveTo(tester.getCenter(row));
  await tester.pumpAndSettle();

  await tester.tap(find.byIcon(Icons.close_rounded));
  await tester.pumpAndSettle();

  await gesture.removePointer();
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

  testWidgets('xoá ở Current phải qua popup confirm — bấm Thôi thì việc còn',
      (tester) async {
    final repo = await _pumpApp(tester);
    await _addNote(tester, 'dung xoa toi');

    await _tapDelete(tester, find.text('dung xoa toi'));

    // Popup hiện, và hiện lại đúng nội dung dòng đang bị xoá.
    expect(find.text('Xoá việc này?'), findsOneWidget);
    expect(find.text('dung xoa toi'), findsNWidgets(2));

    await tester.tap(find.text('Thôi'));
    await tester.pumpAndSettle();

    expect(find.text('Xoá việc này?'), findsNothing);
    expect(repo.current.single.text, 'dung xoa toi');
    await _drainDebounce(tester);
  });

  testWidgets('xoá ở Current — bấm Xoá trong popup thì việc mất',
      (tester) async {
    final repo = await _pumpApp(tester);
    await _addNote(tester, 'xoa that');

    await _tapDelete(tester, find.text('xoa that'));

    await tester.tap(find.widgetWithText(FilledButton, 'Xoá'));
    await tester.pumpAndSettle();

    expect(repo.current, isEmpty);
    expect(find.text('Không còn việc nào'), findsOneWidget);
    await _drainDebounce(tester);
  });

  testWidgets('xoá ở History phải qua popup confirm', (tester) async {
    final repo = await _pumpApp(tester);
    await _addNote(tester, 'viec da xong');
    repo.setDone(repo.current.single.id, true);
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    await _tapDelete(tester, find.text('viec da xong'));

    expect(find.text('Xoá hẳn việc này?'), findsOneWidget);

    await tester.tap(find.text('Thôi'));
    await tester.pumpAndSettle();
    expect(repo.history.single.text, 'viec da xong');

    // Lần hai thì xoá thật.
    await _tapDelete(tester, find.text('viec da xong'));
    await tester.tap(find.widgetWithText(FilledButton, 'Xoá'));
    await tester.pumpAndSettle();

    expect(repo.history, isEmpty);
    await _drainDebounce(tester);
  });

  testWidgets('Xoá hết History phải qua popup confirm', (tester) async {
    final repo = await _pumpApp(tester);
    await _addNote(tester, 'a');
    await _addNote(tester, 'b');
    for (final note in [...repo.current]) {
      repo.setDone(note.id, true);
    }
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Xoá hết'));
    await tester.pumpAndSettle();

    expect(find.text('Xoá hết History?'), findsOneWidget);
    expect(find.text('2 việc đã xong sẽ bị xoá trên mọi máy.'), findsOneWidget);

    await tester.tap(find.text('Thôi'));
    await tester.pumpAndSettle();
    expect(repo.history.length, 2);

    await tester.tap(find.text('Xoá hết'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Xoá hết'));
    await tester.pumpAndSettle();

    expect(repo.history, isEmpty);
    await _drainDebounce(tester);
  });

  testWidgets('có bản mới thì popup tự bật khi mở app', (tester) async {
    await _pumpApp(
      tester,
      update: UpdateService(
        fetcher: () async => const AppRelease(
          version: '1.2.0',
          tag: 'v1.2.0',
          notes: 'thêm auto update',
          pageUrl: 'https://github.com/x/y/releases/tag/v1.2.0',
        ),
        currentVersion: '1.0.0',
      ),
    );

    expect(find.text('Cập nhật'), findsOneWidget);
    expect(find.text('Có bản mới: 1.2.0'), findsOneWidget);
    expect(find.text('thêm auto update'), findsOneWidget);
    expect(find.text('Tải bản mới'), findsOneWidget);
  });

  testWidgets('đang bản mới nhất thì KHÔNG popup lúc mở app', (tester) async {
    await _pumpApp(tester);
    expect(find.text('Cập nhật'), findsNothing);
  });

  testWidgets('bấm nút trên title bar thì mở popup cập nhật', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Cập nhật'), findsOneWidget);
    expect(find.text('Đang dùng: 1.0.0'), findsOneWidget);
    expect(find.text('Đang là bản mới nhất.'), findsOneWidget);
  });

}
