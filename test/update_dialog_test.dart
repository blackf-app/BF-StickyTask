import 'package:bf_stickytask/app/theme.dart';
import 'package:bf_stickytask/data/update_service.dart';
import 'package:bf_stickytask/ui/update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const AppRelease _newer = AppRelease(
  version: '1.4.0',
  tag: 'v1.4.0',
  notes: '- thêm auto update\n- confirm khi xoá',
  pageUrl: 'https://github.com/blackf-app/BF-StickyTask/releases/tag/v1.4.0',
);

Future<void> _open(
  WidgetTester tester,
  UpdateService update, {
  bool checkOnOpen = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildStickyTheme(Brightness.light),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showUpdateDialog(context, update, checkOnOpen: checkOnOpen),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('có bản mới: hiện version, release notes và nút tải',
      (tester) async {
    final update = UpdateService(
      fetcher: () async => _newer,
      currentVersion: '1.0.0',
    );
    await update.check();
    await _open(tester, update);

    expect(find.text('Cập nhật'), findsOneWidget);
    expect(find.text('Đang dùng: 1.0.0'), findsOneWidget);
    expect(find.text('Có bản mới: 1.4.0'), findsOneWidget);
    expect(find.text('Có gì mới'), findsOneWidget);
    expect(find.textContaining('thêm auto update'), findsOneWidget);
    expect(find.text('Tải bản mới'), findsOneWidget);
    expect(find.text('Bỏ qua bản này'), findsOneWidget);
    // Đang có bản mới thì không hiện nút kiểm lại nữa.
    expect(find.text('Kiểm tra cập nhật'), findsNothing);
  });

  testWidgets('đang bản mới nhất: hiện nút kiểm lại, không có nút tải',
      (tester) async {
    final update = UpdateService(
      fetcher: () async => const AppRelease(
        version: '1.0.0',
        tag: 'v1.0.0',
        notes: '',
        pageUrl: 'https://x/y',
      ),
      currentVersion: '1.0.0',
    );
    await update.check();
    await _open(tester, update);

    expect(find.text('Đang là bản mới nhất.'), findsOneWidget);
    expect(find.text('Kiểm tra cập nhật'), findsOneWidget);
    expect(find.text('Tải bản mới'), findsNothing);
    expect(find.text('Bỏ qua bản này'), findsNothing);
  });

  testWidgets('chưa kiểm lần nào thì nói vậy', (tester) async {
    final update = UpdateService(
      fetcher: () async => _newer,
      currentVersion: '1.0.0',
    );
    await _open(tester, update);

    expect(find.text('Chưa kiểm lần nào.'), findsOneWidget);
  });

  testWidgets('checkOnOpen: mở popup là tự kiểm luôn', (tester) async {
    final update = UpdateService(
      fetcher: () async => _newer,
      currentVersion: '1.0.0',
    );
    await _open(tester, update, checkOnOpen: true);

    expect(find.text('Có bản mới: 1.4.0'), findsOneWidget);
  });

  testWidgets('lỗi thì hiện message, không hiện nút tải', (tester) async {
    final update = UpdateService(
      fetcher: () async =>
          throw const UpdateException('Không thấy release nào.'),
      currentVersion: '1.0.0',
    );
    await update.check();
    await _open(tester, update);

    expect(find.text('Không thấy release nào.'), findsOneWidget);
    expect(find.text('Tải bản mới'), findsNothing);
    // Vẫn cho bấm kiểm lại.
    expect(find.text('Kiểm tra cập nhật'), findsOneWidget);
  });

  testWidgets('bấm Kiểm tra cập nhật thì gọi fetcher lại', (tester) async {
    var calls = 0;
    final update = UpdateService(
      fetcher: () async {
        calls++;
        return calls == 1 ? null : _newer;
      },
      currentVersion: '1.0.0',
    );
    await update.check();
    await _open(tester, update);
    expect(find.text('Đang là bản mới nhất.'), findsOneWidget);

    await tester.tap(find.text('Kiểm tra cập nhật'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('Có bản mới: 1.4.0'), findsOneWidget);
  });

  testWidgets('bấm Bỏ qua bản này thì lưu lại và đóng popup', (tester) async {
    final update = UpdateService(
      fetcher: () async => _newer,
      currentVersion: '1.0.0',
    );
    await update.load();
    await update.check();
    await _open(tester, update);

    await tester.tap(find.text('Bỏ qua bản này'));
    await tester.pumpAndSettle();

    expect(find.text('Cập nhật'), findsNothing);
    expect(update.skippedVersion, '1.4.0');
    // Lần mở app sau không popup lại nữa.
    expect(await update.checkOnStartup(), isNull);
  });

  testWidgets('nút Đóng đóng popup', (tester) async {
    final update = UpdateService(
      fetcher: () async => null,
      currentVersion: '1.0.0',
    );
    await update.check();
    await _open(tester, update);

    await tester.tap(find.text('Đóng'));
    await tester.pumpAndSettle();

    expect(find.text('Cập nhật'), findsNothing);
  });
}
