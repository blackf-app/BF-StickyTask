import 'package:bf_stickytask/app/theme.dart';
import 'package:bf_stickytask/data/local_store.dart';
import 'package:bf_stickytask/data/note_repo.dart';
import 'package:bf_stickytask/data/sync_config.dart';
import 'package:bf_stickytask/data/sync_service.dart';
import 'package:bf_stickytask/ui/sync_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryStore extends LocalStore {
  @override
  Future<LocalSnapshot> load() async => const LocalSnapshot(notes: []);

  @override
  Future<void> save(List notes, {String? lastPull}) async {}
}

Future<SyncService> _openDialog(WidgetTester tester) async {
  final repo = NoteRepo(_MemoryStore());
  await repo.load();
  final sync = SyncService(repo);
  addTearDown(sync.dispose);

  await tester.pumpWidget(
    MaterialApp(
      theme: buildStickyTheme(Brightness.light),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showSyncDialog(context, sync),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return sync;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('chưa cấu hình thì mở thẳng form URL + publishable key',
      (tester) async {
    await _openDialog(tester);

    expect(find.text('Đồng bộ'), findsOneWidget);
    expect(find.text('Supabase URL'), findsOneWidget);
    expect(find.text('Publishable key'), findsOneWidget);
    expect(find.text('Lưu & đồng bộ'), findsOneWidget);

    // Không còn dấu vết của luồng đăng nhập cũ.
    expect(find.text('Email'), findsNothing);
    expect(find.text('Mật khẩu'), findsNothing);
    expect(find.text('Đăng nhập'), findsNothing);
  });

  testWidgets('dán secret key thì bị chặn ngay, không gọi mạng',
      (tester) async {
    final sync = await _openDialog(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Supabase URL'),
      'https://abcdefghijklmnop.supabase.co',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Publishable key'),
      'sb_secret_NopeNotThisOne',
    );
    await tester.tap(find.text('Lưu & đồng bộ'));
    await tester.pump();

    expect(find.textContaining('SECRET'), findsOneWidget);
    // Bị chặn ở validate nên service vẫn chưa có client nào.
    expect(sync.configured, isFalse);
    expect(sync.status, SyncStatus.notConfigured);
  });

  testWidgets('URL sai định dạng thì báo lỗi tại chỗ', (tester) async {
    final sync = await _openDialog(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Supabase URL'),
      'khong-phai-url',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Publishable key'),
      'sb_publishable_AbCdEf123456',
    );
    await tester.tap(find.text('Lưu & đồng bộ'));
    await tester.pump();

    expect(find.textContaining('không hợp lệ'), findsOneWidget);
    expect(sync.configured, isFalse);
  });

  testWidgets('nút con mắt bật/tắt che publishable key', (tester) async {
    await _openDialog(tester);

    TextField keyField() =>
        tester.widget<TextField>(find.widgetWithText(TextField, 'Publishable key'));

    expect(keyField().obscureText, isTrue);
    await tester.tap(find.byTooltip('Hiện key'));
    await tester.pump();
    expect(keyField().obscureText, isFalse);
    await tester.tap(find.byTooltip('Ẩn key'));
    await tester.pump();
    expect(keyField().obscureText, isTrue);
  });

  testWidgets('đã cấu hình sẵn thì hiện trạng thái + project ref, không hiện form',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'flutter.sync_url': 'https://abcdefghijklmnop.supabase.co',
      'flutter.sync_publishable_key': 'sb_publishable_AbCdEf123456',
    });

    final repo = NoteRepo(_MemoryStore());
    await repo.load();
    final sync = SyncService(repo);
    addTearDown(sync.dispose);
    // Nạp config nhưng không để nó thực sự đi mạng: chỉ cần config + client.
    await sync.applyConfig(
      SyncConfig.sanitized(
        url: 'https://abcdefghijklmnop.supabase.co',
        key: 'sb_publishable_AbCdEf123456',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildStickyTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSyncDialog(context, sync),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('abcdefghijklmnop'), findsOneWidget);
    expect(find.text('Đồng bộ ngay'), findsOneWidget);
    expect(find.text('Sửa'), findsOneWidget);
    expect(find.text('Ngắt'), findsOneWidget);
    expect(find.text('Supabase URL'), findsNothing);

    // Dispose ngay trong thân test: binding kiểm tra "còn timer treo không"
    // TRƯỚC khi chạy addTearDown, mà cấu hình thành công có dựng pull timer 60s.
    sync.dispose();
  });
}
