import 'package:bf_stickytask/app/theme.dart';
import 'package:bf_stickytask/data/update_service.dart';
import 'package:bf_stickytask/data/updater.dart';
import 'package:bf_stickytask/ui/update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_installer.dart';

const AppRelease _newer = AppRelease(
  version: '1.4.0',
  tag: 'v1.4.0',
  notes: '- thêm auto update\n- confirm khi xoá',
  pageUrl: 'https://github.com/blackf-app/BF-StickyTask/releases/tag/v1.4.0',
  assets: [
    ReleaseAsset(
      name: 'BF-StickyTask-macos.zip',
      url: 'https://example.test/BF-StickyTask-macos.zip',
      size: 4,
    ),
  ],
);

/// [Updater] chỉ để dựng UI ở một trạng thái cho trước.
///
/// Không dùng [Updater] thật trong widget test: `testWidgets` chạy trong
/// `FakeAsync`, mà future của `dart:io` (tạo file tạm, ghi file) không bao giờ
/// complete trong đó — download thật sẽ treo ở giữa. Luồng tải/verify/cài thật
/// được test bằng `test()` thường ở `updater_test.dart`.
class _StubUpdater extends Updater {
  _StubUpdater({
    UpdatePhase phase = UpdatePhase.idle,
    this.stubError,
    this.installable = true,
    this.stubReceived = 0,
    this.stubTotal = 0,
  })  :
        // Không dùng initializing formal được: tham số named không được mang
        // tên private, mà `_phase` phải mutable để moveTo() đổi trạng thái.
        // ignore: prefer_initializing_formals
        _phase = phase,
        super(installer: FakeInstaller(), onQuit: _never);

  static Future<void> _never() async {}

  UpdatePhase _phase;
  final String? stubError;
  final bool installable;
  final int stubReceived;
  final int stubTotal;

  int runCalls = 0;
  int cancelCalls = 0;

  @override
  UpdatePhase get phase => _phase;

  @override
  String? get error => stubError;

  @override
  int get received => stubReceived;

  @override
  int get total => stubTotal;

  @override
  bool get supported => true;

  @override
  bool canInstall(AppRelease release) => installable;

  @override
  Future<void> run(AppRelease release) async {
    runCalls++;
    // Giả đúng thứ tự UI sẽ thấy: bắt đầu tải → (test tự đặt tiếp).
    _phase = UpdatePhase.downloading;
    notifyListeners();
  }

  @override
  void cancel() => cancelCalls++;

  /// Đẩy sang trạng thái khác giữa test.
  void moveTo(UpdatePhase next) {
    _phase = next;
    notifyListeners();
  }
}

Future<void> _open(
  WidgetTester tester,
  UpdateService update, {
  bool checkOnOpen = false,
  _StubUpdater? updater,
  // false khi popup có progress bar vô định: nó chạy mãi nên pumpAndSettle
  // không bao giờ trả về.
  bool settle = true,
}) async {
  final u = updater ?? _StubUpdater();
  await tester.pumpWidget(
    MaterialApp(
      theme: buildStickyTheme(Brightness.light),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showUpdateDialog(context, update, u, checkOnOpen: checkOnOpen),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('có bản mới: hiện version, release notes và nút cập nhật',
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
    expect(find.text('Cập nhật ngay'), findsOneWidget);
    expect(find.text('Bỏ qua bản này'), findsOneWidget);
    // Đang có bản mới thì không hiện nút kiểm lại nữa.
    expect(find.text('Kiểm tra cập nhật'), findsNothing);
  });

  testWidgets('đang bản mới nhất: hiện nút kiểm lại, không có nút cập nhật',
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
    expect(find.text('Cập nhật ngay'), findsNothing);
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

  testWidgets('lỗi thì hiện message, không hiện nút cập nhật', (tester) async {
    final update = UpdateService(
      fetcher: () async =>
          throw const UpdateException('Không thấy release nào.'),
      currentVersion: '1.0.0',
    );
    await update.check();
    await _open(tester, update);

    expect(find.text('Không thấy release nào.'), findsOneWidget);
    expect(find.text('Cập nhật ngay'), findsNothing);
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

  testWidgets('bấm Cập nhật ngay thì gọi Updater.run', (tester) async {
    final update = UpdateService(
      fetcher: () async => _newer,
      currentVersion: '1.0.0',
    );
    await update.check();

    final updater = _StubUpdater();
    await _open(tester, update, updater: updater);

    await tester.tap(find.text('Cập nhật ngay'));
    // pump chứ không pumpAndSettle: run() chuyển sang downloading và progress
    // bar vô định sẽ chạy mãi.
    await tester.pump();

    expect(updater.runCalls, 1);
  });

  testWidgets('đang tải: hiện progress, nút Huỷ, ẩn release notes',
      (tester) async {
    final update = UpdateService(
      fetcher: () async => _newer,
      currentVersion: '1.0.0',
    );
    await update.check();

    final updater = _StubUpdater(
      phase: UpdatePhase.downloading,
      stubReceived: 1024 * 1024,
      stubTotal: 4 * 1024 * 1024,
    );
    await _open(tester, update, updater: updater, settle: false);

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Đang tải… 1.0 MB / 4.0 MB'), findsOneWidget);
    expect(find.text('Huỷ'), findsOneWidget);
    // Đang tải thì không cho đóng popup — mất chỗ xem tiến trình lẫn lỗi.
    expect(find.text('Đóng'), findsNothing);
    // Release notes nhường chỗ cho progress.
    expect(find.text('Có gì mới'), findsNothing);

    await tester.tap(find.text('Huỷ'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(updater.cancelCalls, 1);
    expect(find.text('Cập nhật'), findsNothing);
  });

  testWidgets('đã bàn giao: hiện lời nhắn, không còn nút nào', (tester) async {
    final update = UpdateService(
      fetcher: () async => _newer,
      currentVersion: '1.0.0',
    );
    await update.check();

    await _open(
      tester,
      update,
      updater: _StubUpdater(phase: UpdatePhase.handedOff),
      settle: false,
    );

    expect(find.text('App sẽ tự đóng rồi mở lại.'), findsOneWidget);
    expect(find.text('Đóng'), findsNothing);
    expect(find.text('Cập nhật ngay'), findsNothing);
  });

  testWidgets('cài lỗi: hiện lỗi, còn nút Thử lại và Mở trang tải',
      (tester) async {
    final update = UpdateService(
      fetcher: () async => _newer,
      currentVersion: '1.0.0',
    );
    await update.check();

    await _open(
      tester,
      update,
      updater: _StubUpdater(
        phase: UpdatePhase.error,
        stubError: 'Cần quyền admin.',
      ),
    );

    expect(find.text('Cần quyền admin.'), findsOneWidget);
    expect(find.text('Thử lại'), findsOneWidget);
    expect(find.text('Mở trang tải'), findsOneWidget);
    // Hết progress bar khi đã lỗi.
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('release không có asset cho máy này: chỉ còn Mở trang tải',
      (tester) async {
    final update = UpdateService(
      fetcher: () async => _newer,
      currentVersion: '1.0.0',
    );
    await update.check();

    await _open(tester, update, updater: _StubUpdater(installable: false));

    expect(find.text('Cập nhật ngay'), findsNothing);
    expect(find.text('Mở trang tải'), findsOneWidget);
    expect(find.textContaining('chưa tự cài được'), findsOneWidget);
  });
}
