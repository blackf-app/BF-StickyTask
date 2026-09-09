import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:bf_stickytask/data/update_installer.dart';
import 'package:bf_stickytask/data/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

ReleaseAsset _asset(String name) =>
    ReleaseAsset(name: name, url: 'https://x/$name', size: 1);

/// Đúng bộ asset mà `.github/workflows/release.yml` đang publish. Test này là
/// chốt chặn cho việc đổi tên file trong CI mà quên sửa app — đổi tên xong thì
/// app không tìm thấy bản build nào và im lặng rơi về "mở trang tải".
final List<ReleaseAsset> _realRelease = [
  _asset('BF-StickyTask-macos.zip'),
  _asset('BF-StickyTask-windows.zip'),
  _asset('app-armeabi-v7a-release.apk'),
  _asset('app-arm64-v8a-release.apk'),
  _asset('app-x86_64-release.apk'),
];

void main() {
  group('pickMacosAsset', () {
    test('lấy đúng zip macOS trong bộ asset thật', () {
      expect(pickMacosAsset(_realRelease)?.name, 'BF-StickyTask-macos.zip');
    });

    test('không có thì null, không lấy bừa zip Windows', () {
      expect(
        pickMacosAsset([_asset('BF-StickyTask-windows.zip')]),
        isNull,
      );
    });

    test('không lấy file khác đuôi', () {
      expect(pickMacosAsset([_asset('BF-StickyTask-macos.dmg')]), isNull);
    });
  });

  group('pickWindowsAsset', () {
    test('lấy đúng zip Windows trong bộ asset thật', () {
      expect(pickWindowsAsset(_realRelease)?.name, 'BF-StickyTask-windows.zip');
    });

    test('không có thì null, không lấy bừa zip macOS', () {
      expect(pickWindowsAsset([_asset('BF-StickyTask-macos.zip')]), isNull);
    });
  });

  group('pickAndroidAsset', () {
    test('mỗi ABI lấy đúng APK của nó', () {
      expect(
        pickAndroidAsset(_realRelease, abi: Abi.androidArm64)?.name,
        'app-arm64-v8a-release.apk',
      );
      expect(
        pickAndroidAsset(_realRelease, abi: Abi.androidArm)?.name,
        'app-armeabi-v7a-release.apk',
      );
      expect(
        pickAndroidAsset(_realRelease, abi: Abi.androidX64)?.name,
        'app-x86_64-release.apk',
      );
    });

    test('x86 không ăn lẫn sang x86_64', () {
      // Thứ tự cố ý đặt x86_64 trước: nếu tìm theo chuỗi 'x86' mà không ưu
      // tiên đúng ABI thì bản 32-bit sẽ nhận file 64-bit và cài xong crash.
      final assets = [
        _asset('app-x86_64-release.apk'),
        _asset('app-x86-release.apk'),
      ];
      expect(
        pickAndroidAsset(assets, abi: Abi.androidIA32)?.name,
        'app-x86-release.apk',
      );
      expect(
        pickAndroidAsset(assets, abi: Abi.androidX64)?.name,
        'app-x86_64-release.apk',
      );
    });

    test('không có APK đúng ABI thì rơi về APK duy nhất có', () {
      final assets = [_asset('app-release.apk')];
      expect(
        pickAndroidAsset(assets, abi: Abi.androidArm64)?.name,
        'app-release.apk',
      );
    });

    test('ABI không phải Android thì cũng chỉ còn đường universal', () {
      expect(
        pickAndroidAsset([_asset('app-release.apk')], abi: Abi.androidRiscv64)
            ?.name,
        'app-release.apk',
      );
      expect(pickAndroidAsset(_realRelease, abi: Abi.androidRiscv64), isNotNull);
    });

    test('không có apk nào thì null', () {
      expect(
        pickAndroidAsset(
          [_asset('BF-StickyTask-macos.zip')],
          abi: Abi.androidArm64,
        ),
        isNull,
      );
    });
  });

  group('UpdateInstaller.forCurrentPlatform', () {
    test('máy đang chạy test phải chọn được asset của chính nó', () {
      final installer = UpdateInstaller.forCurrentPlatform();
      // Test chạy trên macOS/Windows/Linux; hai cái đầu phải có installer.
      if (installer == null) return;
      expect(installer.pickAsset(_realRelease), isNotNull);
      expect(installer.handoffMessage, isNotEmpty);
    });
  });

  group('macosInstallScript', () {
    String script({
      String target = '/Applications/BF-StickyTask.app',
      String stage = '/tmp/bfst-update-abc',
    }) =>
        macosInstallScript(
          pid: 4242,
          freshBundle: '$stage/BF-StickyTask.app',
          targetBundle: target,
          stageDir: stage,
        );

    test('cú pháp sh hợp lệ', () async {
      // `sh -n` là chốt chặn thật sự của file này: script chạy SAU khi app đã
      // thoát, nên một lỗi cú pháp ở đây nghĩa là app biến mất và không bao
      // giờ mở lại — không có chỗ nào báo lỗi cho user.
      final dir = await Directory.systemTemp.createTemp('bfst-script-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/install.sh');
      await file.writeAsString(script());

      final res = await Process.run('/bin/sh', ['-n', file.path]);
      expect(res.exitCode, 0, reason: 'sh -n báo: ${res.stderr}');
    }, skip: !Platform.isMacOS && !Platform.isLinux);

    test('chờ đúng PID của app đang chạy', () {
      expect(script(), contains('kill -0 4242'));
    });

    test('đổi chỗ bằng mv, không ditto trực tiếp lên bundle cũ', () {
      final s = script();
      // ditto vào .bfst-new rồi mv — nửa đường mà lỗi thì bundle cũ còn nguyên.
      expect(s, contains(r'NEW="$TARGET.bfst-new"'));
      expect(s, contains(r'/usr/bin/ditto "$FRESH" "$NEW"'));
      expect(s, contains(r'mv "$NEW" "$TARGET"'));
    });

    test('mọi nhánh lỗi đều mở lại app', () {
      // 4 lần gọi open_app: 3 nhánh lỗi + 1 lần thành công. Thiếu một nhánh
      // là user mất app sau khi cập nhật lỗi.
      expect(
        // `$` chứ không phải `\$`: trong raw string thì `\$` là dấu đô-la
        // literal, mất nghĩa end-of-line và regex không khớp gì.
        RegExp(r'^\s*open_app$', multiLine: true)
            .allMatches(script())
            .length,
        4,
      );
    });

    test('chạy dưới root thì mở app lại đúng user, không phải root', () {
      final s = script();
      // `open` của root mở app trong session của root — user không thấy gì.
      expect(s, contains('launchctl asuser'));
      expect(s, contains(r'sudo -u "$OWNER"'));
      // Trả lại quyền sở hữu, không thì lần cập nhật sau lại phải nhập mật khẩu.
      expect(s, contains(r'chown -R "$OWNER" "$TARGET"'));
    });

    test('không còn line-continuation nào (Dart ăn mất dấu chéo cuối dòng)',
        () {
      // Dart bỏ dấu chéo ngược ở cuối dòng trong string literal, nên script
      // sinh ra sẽ vỡ ở đúng chỗ đó. Kiểm thẳng vào output.
      expect(
        RegExp(r'\\\n').hasMatch(script()),
        isFalse,
        reason: 'script không được dựa vào line-continuation của shell',
      );
    });

    test('gỡ quarantine trước khi đổi chỗ', () {
      expect(script(), contains('xattr -dr com.apple.quarantine'));
    });

    test('đường dẫn được nháy đơn, không nội suy thẳng vào shell', () {
      final s = script(target: '/Applications/BF-StickyTask.app');
      expect(s, contains("TARGET='/Applications/BF-StickyTask.app'"));
    });
  });

  group('windowsInstallScript', () {
    String script({String installDir = r'C:\Users\me\BF-StickyTask'}) =>
        windowsInstallScript(
          pid: 4242,
          sourceDir: r'C:\Temp\bfst-update-abc',
          installDir: installDir,
          exeName: 'BF-StickyTask.exe',
          stageDir: r'C:\Temp\bfst-update-abc',
        );

    test('chờ đúng PID rồi mới ghi đè', () {
      final s = script();
      expect(s, contains('Wait-Process -Id 4242'));
      // Thứ tự phải là chờ TRƯỚC, copy SAU: exe/dll đang chạy bị OS lock.
      expect(s.indexOf('Wait-Process'), lessThan(s.indexOf('robocopy')));
    });

    test('KHÔNG dùng /PURGE', () {
      // /PURGE xoá mọi file trong đích không có trong nguồn. Bản phát hành là
      // zip portable, user hay giải nén thẳng vào Desktop — /PURGE ở đó là
      // xoá sạch file của họ.
      expect(script(), isNot(contains('/PURGE')));
      expect(script(), contains('/E /IS /IT'));
    });

    test('robocopy exit 0–7 là thành công', () {
      expect(script(), contains(r'if ($LASTEXITCODE -ge 8)'));
    });

    test('tự nâng quyền khi thư mục cài không ghi được', () {
      final s = script(installDir: r'C:\Program Files\BF-StickyTask');
      expect(s, contains('-Verb RunAs'));
      expect(s, contains(r'$canWrite'));
    });

    test('mở lại app sau khi copy xong', () {
      final s = script();
      expect(s, contains(r'Start-Process -FilePath $exe'));
      expect(
        s.indexOf('robocopy'),
        lessThan(s.indexOf('Start-Process -FilePath')),
      );
    });

    test('chạy elevated thì hạ quyền qua explorer.exe khi mở lại app', () {
      // Start-Process trực tiếp sẽ mở app dưới quyền admin → app ghi prefs
      // vào profile của admin thay vì của user.
      final s = script();
      expect(s, contains(r'if ($isAdmin) {'));
      expect(s, contains('Start-Process explorer.exe'));
    });

    test('đường dẫn script tự nâng quyền được bọc nháy kép', () {
      // -ArgumentList nối bằng dấu cách và không tự quote.
      expect(script(), contains(r'"`"$PSCommandPath`""'));
    });

    test('nháy đơn trong đường dẫn được nhân đôi', () {
      final s = windowsInstallScript(
        pid: 1,
        sourceDir: r"C:\it's\here",
        installDir: r'C:\app',
        exeName: 'a.exe',
        stageDir: r'C:\tmp',
      );
      expect(s, contains(r"'C:\it''s\here'"));
    });
  });
}
