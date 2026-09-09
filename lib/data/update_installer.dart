import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'update_service.dart';

/// Cài bản mới đã tải về — phần "tự động hoá" của cơ chế cập nhật.
///
/// Ba nền tảng đi ba đường hoàn toàn khác nhau, và mức tự động cũng khác nhau:
///
/// - **macOS / Windows**: tự động hoàn toàn. Không thay được file của app đang
///   chạy (macOS thì `.app` đang được mmap, Windows thì exe/dll bị OS lock),
///   nên cả hai đều theo cùng một khuôn: giải nén ra thư mục tạm → sinh một
///   script → chạy **detached** → app tự thoát → script chờ process chết, ghi
///   đè, rồi mở lại app. Xem [_MacosInstaller], [_WindowsInstaller].
/// - **Android**: KHÔNG thể tự động hoàn toàn. Android bắt buộc hiện dialog hệ
///   thống xác nhận cho mọi lần cài ngoài store — chỉ device-owner (MDM) hoặc
///   app hệ thống mới bỏ được. Tối đa: tải xong → 1 dialog → 1 lần bấm
///   "Cập nhật" → tự mở lại. Xem [_AndroidInstaller].
abstract class UpdateInstaller {
  const UpdateInstaller();

  /// `null` = nền tảng này không tự cài được (Linux, hoặc web/mobile khác) →
  /// UI rơi về nút mở trang release.
  static UpdateInstaller? forCurrentPlatform() {
    if (Platform.isMacOS) return const _MacosInstaller();
    if (Platform.isWindows) return const _WindowsInstaller();
    if (Platform.isAndroid) return const _AndroidInstaller();
    return null;
  }

  /// Asset đúng máy này, `null` nếu release không có.
  ReleaseAsset? pickAsset(List<ReleaseAsset> assets);

  /// Sau [install] app có phải tự thoát không.
  ///
  /// `true` trên desktop: script bên ngoài đang chờ process này chết mới ghi
  /// đè được. `false` trên Android: dialog hệ thống cần app còn sống để hiện.
  bool get quitsApp;

  /// Việc user sẽ thấy sau khi bấm cập nhật — hiện trong dialog trước khi
  /// app thoát, để không ai tưởng app tự crash.
  String get handoffMessage;

  /// Chạy phần cài. Ném [UpdateException] với thông báo tiếng Việt nếu không
  /// làm được — lúc này app CHƯA thoát nên vẫn hiện lỗi lên dialog được.
  ///
  /// Trả về bình thường nghĩa là đã bàn giao xong (script đã chạy / dialog hệ
  /// thống đã được gọi). Từ đây trở đi [quitsApp] quyết định app có exit không.
  Future<void> install(File downloaded, {required String version});
}

/// Tìm asset đầu tiên có tên chứa đủ mọi từ khoá trong [needles].
ReleaseAsset? _findAsset(List<ReleaseAsset> assets, List<String> needles) {
  for (final asset in assets) {
    final name = asset.name.toLowerCase();
    if (needles.every(name.contains)) return asset;
  }
  return null;
}

// Ba hàm chọn asset dưới đây là hàm thuần, tách khỏi installer có lý do: đây
// là chỗ dễ sai nhất (khớp tên file do CI đặt), mà installer thì gắn với
// nền tảng đang chạy nên test trên máy nào chỉ kiểm được nền tảng đó. Tách ra
// thì `update_installer_test.dart` kiểm được cả ba trên cùng một máy.

/// `BF-StickyTask-macos.zip` — xem job `macos` trong `.github/workflows/release.yml`.
ReleaseAsset? pickMacosAsset(List<ReleaseAsset> assets) =>
    _findAsset(assets, const ['macos', '.zip']);

/// `BF-StickyTask-windows.zip` — xem job `windows` trong release.yml.
ReleaseAsset? pickWindowsAsset(List<ReleaseAsset> assets) =>
    _findAsset(assets, const ['windows', '.zip']);

/// APK đúng [abi], rơi về bản universal nếu không có.
///
/// `flutter build apk --split-per-abi` ra `app-arm64-v8a-release.apk` &co.,
/// mỗi bản ~20MB thay vì ~53MB của bản universal. Tên ABI trong file là tên
/// của Android NDK, không phải tên của Dart — đây là chỗ map giữa hai bên.
ReleaseAsset? pickAndroidAsset(List<ReleaseAsset> assets, {required Abi abi}) {
  final tag = switch (abi) {
    Abi.androidArm64 => 'arm64-v8a',
    Abi.androidArm => 'armeabi-v7a',
    Abi.androidX64 => 'x86_64',
    Abi.androidIA32 => 'x86',
    // ABI lạ (riscv…): chỉ còn đường universal.
    _ => null,
  };
  if (tag != null) {
    for (final asset in assets) {
      final name = asset.name.toLowerCase();
      if (name.endsWith('.apk') && _hasAbiTag(name, tag)) return asset;
    }
  }
  // Không có APK đúng ABI thì thử bản universal — release cũ chỉ có một APK.
  return _findAsset(assets, const ['.apk']);
}

/// [tag] có xuất hiện trong [name] như một thành phần riêng, không phải một
/// khúc của thành phần khác.
///
/// Cần thiết vì `contains` là sai ở đúng một chỗ nhưng chỗ đó nguy hiểm:
/// `'app-x86_64-release.apk'.contains('x86')` là `true`, nên máy 32-bit sẽ
/// nhận APK 64-bit rồi cài xong crash ngay lúc mở. Ranh giới ở đây là ký tự
/// không thuộc `[a-z0-9_]` — dấu `-` là ranh giới, `_` thì không (tên ABI
/// `x86_64` có `_` bên trong).
bool _hasAbiTag(String name, String tag) {
  const wordChars = 'abcdefghijklmnopqrstuvwxyz0123456789_';
  bool isWord(String c) => c.isNotEmpty && wordChars.contains(c);

  var from = 0;
  while (true) {
    final at = name.indexOf(tag, from);
    if (at < 0) return false;
    final before = at == 0 ? '' : name[at - 1];
    final afterAt = at + tag.length;
    final after = afterAt >= name.length ? '' : name[afterAt];
    if (!isWord(before) && !isWord(after)) return true;
    from = at + 1;
  }
}

// ─── macOS ───────────────────────────────────────────────────────────────────

/// Thay `.app` đang chạy bằng bản mới.
///
/// **Chỉ chạy được vì app đã bỏ app-sandbox** (xem
/// `macos/Runner/Release.entitlements`). Trong sandbox thì bất khả: app chỉ
/// ghi được trong container của nó, và process con thừa hưởng sandbox của cha
/// nên script cũng không ghi được ra ngoài.
class _MacosInstaller extends UpdateInstaller {
  const _MacosInstaller();

  @override
  ReleaseAsset? pickAsset(List<ReleaseAsset> assets) => pickMacosAsset(assets);

  @override
  bool get quitsApp => true;

  @override
  String get handoffMessage =>
      'App sẽ tự đóng, ghi đè bản mới rồi tự mở lại. Đừng tắt máy.';

  @override
  Future<void> install(File downloaded, {required String version}) async {
    final stage = await Directory.systemTemp.createTemp('bfst-update-');
    try {
      await _install(downloaded, stage);
    } catch (_) {
      // Bàn giao được thì script tự dọn; ném ra đây là chưa bàn giao, mà
      // stage lúc này đang giữ một bản `.app` giải nén ~50MB.
      try {
        await stage.delete(recursive: true);
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> _install(File downloaded, Directory stage) async {
    final current = _currentBundle();

    // `ditto -x -k` chứ không dùng package:archive: zip của .app có symlink
    // (Frameworks/…/Current) và bit exec, `archive` làm mất cả hai → bản mới
    // không mở được.
    final unzip = await Process.run(
      '/usr/bin/ditto',
      ['-x', '-k', downloaded.path, stage.path],
    );
    if (unzip.exitCode != 0) {
      throw UpdateException('Không giải nén được bản mới — ${unzip.stderr}');
    }

    final fresh = _findBundle(stage);
    if (fresh == null) {
      throw const UpdateException('File tải về không chứa BF-StickyTask.app.');
    }

    // App Translocation: bundle chưa ký/quarantine chạy từ ~/Downloads bị macOS
    // gắn vào một mount chỉ-đọc ở /private/var/folders/…/AppTranslocation/.
    // Ghi đè chỗ đó là vô nghĩa (mount biến mất khi app thoát), nên cài hẳn
    // vào /Applications rồi mở bản đó.
    final target = current.path.contains('/AppTranslocation/')
        ? '/Applications/${_bundleName(fresh)}'
        : current.path;

    final script = File('${stage.path}/install.sh');
    await script.writeAsString(macosInstallScript(
      pid: pid,
      freshBundle: fresh.path,
      targetBundle: target,
      stageDir: stage.path,
    ));

    final parent = File(target).parent.path;
    if (await _writable(parent)) {
      await Process.start(
        '/bin/sh',
        [script.path],
        mode: ProcessStartMode.detached,
      );
      return;
    }

    // Thư mục cài không ghi được (thường là app do người khác/root đặt vào
    // /Applications). Xin quyền admin NGAY BÂY GIỜ, lúc app còn sống để hiện
    // được cửa sổ nhập mật khẩu; `do shell script` nhả ngay vì script được
    // đẩy xuống nền, phần chờ-app-thoát nằm trong chính script đó.
    final command = 'nohup /bin/sh ${_shQuote(script.path)} >/dev/null 2>&1 &';
    final elevated = await Process.run('/usr/bin/osascript', [
      '-e',
      'do shell script "${_appleScriptQuote(command)}" '
          'with administrator privileges',
    ]);
    if (elevated.exitCode != 0) {
      final err = (elevated.stderr as String).trim();
      throw UpdateException(
        err.contains('-128')
            ? 'Đã huỷ nhập mật khẩu — chưa cập nhật gì.'
            : 'Cần quyền admin để ghi vào $parent — $err',
      );
    }
  }

  /// `/Applications/X.app/Contents/MacOS/X` → `/Applications/X.app`.
  Directory _currentBundle() =>
      File(Platform.resolvedExecutable).parent.parent.parent;

  String _bundleName(Directory bundle) => bundle.path.split('/').last;

  Directory? _findBundle(Directory stage) {
    for (final entry in stage.listSync()) {
      if (entry is Directory && entry.path.endsWith('.app')) return entry;
    }
    return null;
  }

  Future<bool> _writable(String dir) async {
    try {
      final probe = File('$dir/.bfst-write-probe-$pid');
      await probe.writeAsString('', flush: true);
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Hai lớp escape khác nhau, đừng gộp: chuỗi đi qua AppleScript rồi mới
  /// tới `sh`, mỗi lớp có luật riêng. Thực tế đường dẫn temp không có ký tự
  /// lạ nào, nhưng đây là chỗ duy nhất trong app dụng tới quyền admin —
  /// không để nó phụ thuộc vào may mắn.

  /// Lớp trong: một argv của `sh`. Nháy đơn giữ nguyên mọi thứ trừ chính nó.
  String _shQuote(String s) {
    final escaped = s.replaceAll("'", r"'\''");
    return "'$escaped'";
  }

  /// Lớp ngoài: string literal của AppleScript.
  String _appleScriptQuote(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
}

/// Script thay bundle. Viết theo kiểu "hỏng ở bước nào cũng mở lại được app":
/// app đã thoát rồi, để user không còn app nào để mở là tệ nhất.
String macosInstallScript({
  required int pid,
  required String freshBundle,
  required String targetBundle,
  required String stageDir,
}) =>
    '''
#!/bin/sh
# Sinh tự động bởi lib/data/update_installer.dart. Xoá được.
FRESH='$freshBundle'
TARGET='$targetBundle'
STAGE='$stageDir'
LOG="\$STAGE/install.log"
exec >>"\$LOG" 2>&1
set -x

# Chủ của bundle cũ — cần cho hai việc ở cuối: trả quyền sở hữu, và mở app
# lại đúng user. Phải đọc TRƯỚC khi bundle bị dọn đi.
OWNER="\$(stat -f '%Su' "\$TARGET" 2>/dev/null)"

# Mở lại app. Nhánh xin-quyền-admin chạy script này dưới root, mà `open` của
# root thì mở app trong session của root — user không thấy gì. `launchctl
# asuser` đưa nó về đúng session GUI đang đăng nhập.
open_app() {
  if [ "\$(id -u)" = "0" ] && [ -n "\$OWNER" ] && [ "\$OWNER" != "root" ]; then
    uid="\$(id -u "\$OWNER" 2>/dev/null)"
    # Một dòng, không dùng line-continuation: dấu chéo ngược cuối dòng nằm
    # trong string
    # literal của Dart sẽ bị chính Dart ăn mất, script ra sẽ vỡ.
    if [ -n "\$uid" ] && /bin/launchctl asuser "\$uid" /usr/bin/sudo -u "\$OWNER" /usr/bin/open -n "\$TARGET"; then
      return 0
    fi
  fi
  /usr/bin/open -n "\$TARGET"
}

# Chờ app thoát — ditto lên bundle đang chạy là hỏng cả bản cũ lẫn bản mới.
# Tối đa 30s rồi làm tới: app treo thì thà thay file còn hơn bỏ cuộc im lặng.
i=0
while kill -0 $pid 2>/dev/null; do
  i=\$((i + 1))
  [ "\$i" -gt 300 ] && break
  sleep 0.1
done

# Dựng bản mới cạnh bản cũ rồi ĐỔI CHỖ bằng mv (rename cùng volume là atomic),
# thay vì ditto trực tiếp lên bundle cũ — nửa đường mà lỗi thì bundle cũ đã bị
# trộn file của hai version, không mở được mà cũng không rollback được.
NEW="\$TARGET.bfst-new"
OLD="\$TARGET.bfst-old"
rm -rf "\$NEW" "\$OLD"

if ! /usr/bin/ditto "\$FRESH" "\$NEW"; then
  rm -rf "\$NEW"
  open_app
  exit 1
fi

# Tải bằng HTTP trong app nên không có cờ com.apple.quarantine (khác hẳn tải
# bằng browser). Gỡ cho chắc — sót lại là Gatekeeper báo "app bị hỏng".
/usr/bin/xattr -dr com.apple.quarantine "\$NEW" 2>/dev/null

if [ -e "\$TARGET" ] && ! mv "\$TARGET" "\$OLD"; then
  rm -rf "\$NEW"
  open_app
  exit 1
fi

if ! mv "\$NEW" "\$TARGET"; then
  # Trường hợp xấu nhất: bản cũ đã dọn đi mà bản mới chưa vào chỗ. Trả bản cũ
  # về rồi mở nó — user mất bản cập nhật, không mất app.
  [ -d "\$OLD" ] && mv "\$OLD" "\$TARGET"
  open_app
  exit 1
fi

# Chạy dưới quyền admin thì bundle mới thuộc về root, lần cập nhật sau lại
# phải xin mật khẩu. Trả về chủ cũ để lần sau chạy trơn.
if [ -n "\$OWNER" ]; then
  chown -R "\$OWNER" "\$TARGET" 2>/dev/null
fi

open_app
rm -rf "\$OLD" "\$FRESH"
''';

// ─── Windows ─────────────────────────────────────────────────────────────────

/// Ghi đè thư mục cài bằng bản mới.
///
/// Bản phát hành Windows là **zip portable** (`release.yml` nén cả
/// `build/windows/x64/runner/Release/`), không phải installer — nên "cài" ở
/// đây đúng nghĩa là copy đè lên thư mục đang chạy.
class _WindowsInstaller extends UpdateInstaller {
  const _WindowsInstaller();

  @override
  ReleaseAsset? pickAsset(List<ReleaseAsset> assets) =>
      pickWindowsAsset(assets);

  @override
  bool get quitsApp => true;

  @override
  String get handoffMessage =>
      'App sẽ tự đóng, ghi đè bản mới rồi tự mở lại. Đừng tắt máy.';

  @override
  Future<void> install(File downloaded, {required String version}) async {
    final stage = await Directory.systemTemp.createTemp('bfst-update-');
    try {
      await _install(downloaded, stage);
    } catch (_) {
      // Xem comment cùng chỗ ở _MacosInstaller.install.
      try {
        await stage.delete(recursive: true);
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> _install(File downloaded, Directory stage) async {
    final exe = File(Platform.resolvedExecutable);
    final installDir = exe.parent.path;

    // Ở đây dùng package:archive được: bundle Windows chỉ có file thường,
    // không symlink, không bit exec cần giữ.
    try {
      await extractFileToDisk(downloaded.path, stage.path);
    } catch (e) {
      throw UpdateException('Không giải nén được bản mới — $e');
    }

    // Zip có thể có hoặc không có một thư mục bọc ngoài. Lấy thư mục nào chứa
    // đúng file exe làm nguồn.
    final source = _sourceDir(stage, exe.uri.pathSegments.last);
    if (source == null) {
      throw const UpdateException(
        'File tải về không chứa BF-StickyTask.exe.',
      );
    }

    final script = File('${stage.parent.path}\\bfst-install-$pid.ps1');
    await script.writeAsString(windowsInstallScript(
      pid: pid,
      sourceDir: source.path,
      installDir: installDir,
      exeName: exe.uri.pathSegments.last,
      stageDir: stage.path,
    ));

    // -WindowStyle Hidden để không nháy cửa sổ xanh giữa lúc app đang đóng.
    await Process.start(
      'powershell',
      [
        '-NoProfile',
        '-NonInteractive',
        '-WindowStyle',
        'Hidden',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        script.path,
      ],
      mode: ProcessStartMode.detached,
    );
  }

  Directory? _sourceDir(Directory stage, String exeName) {
    if (File('${stage.path}\\$exeName').existsSync()) return stage;
    for (final entry in stage.listSync()) {
      if (entry is Directory && File('${entry.path}\\$exeName').existsSync()) {
        return entry;
      }
    }
    return null;
  }
}

/// Script ghi đè. Cố ý **không** dùng `robocopy /PURGE`: bản phát hành là zip
/// portable, user hay giải nén thẳng vào Desktop hoặc gốc ổ đĩa, và /PURGE ở
/// đó sẽ xoá sạch file không liên quan của họ. File cũ còn sót lại là vô hại
/// — runner Flutter nạp `data\` và các DLL theo đúng tên.
String windowsInstallScript({
  required int pid,
  required String sourceDir,
  required String installDir,
  required String exeName,
  required String stageDir,
}) =>
    '''
# Sinh tự động bởi lib/data/update_installer.dart. Xoá được.
\$ErrorActionPreference = 'Continue'
\$source    = '${_psQuote(sourceDir)}'
\$installDir= '${_psQuote(installDir)}'
\$exe       = Join-Path \$installDir '${_psQuote(exeName)}'
\$stage     = '${_psQuote(stageDir)}'
Start-Transcript -Path (Join-Path \$stage 'install.log') -Force | Out-Null

# Chờ app thoát: exe/dll đang chạy bị OS lock, copy đè là "Access denied".
try { Wait-Process -Id $pid -Timeout 30 -ErrorAction Stop } catch { }

# Thư mục cài không ghi được (C:\\Program Files…) thì tự nâng quyền — user sẽ
# thấy một cửa sổ UAC. Không tránh được, Windows không cho ghi vào đó mà
# không có quyền admin.
\$probe = Join-Path \$installDir '.bfst-write-probe'
\$canWrite = \$true
try { New-Item -Path \$probe -ItemType File -Force -ErrorAction Stop | Out-Null
      Remove-Item \$probe -Force -ErrorAction SilentlyContinue }
catch { \$canWrite = \$false }

\$id = [Security.Principal.WindowsIdentity]::GetCurrent()
\$isAdmin = (New-Object Security.Principal.WindowsPrincipal(\$id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not \$canWrite -and -not \$isAdmin) {
  Stop-Transcript | Out-Null
  # Nháy kép quanh đường dẫn: -ArgumentList nối các phần tử bằng dấu cách mà
  # không tự quote, nên đường dẫn có dấu cách sẽ bị cắt làm hai.
  Start-Process powershell -Verb RunAs -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"\$PSCommandPath`""
  exit
}

# /IS /IT: copy cả file trùng tên và file "tweaked", nếu không robocopy bỏ qua
# file cùng kích thước + timestamp và bản mới có thể không được ghi.
robocopy \$source \$installDir /E /IS /IT /R:3 /W:1 /NFL /NDL /NJH /NJS | Out-Null
# robocopy trả 0–7 là thành công, ≥8 mới là lỗi thật.
if (\$LASTEXITCODE -ge 8) { Stop-Transcript | Out-Null; exit 1 }

# Chạy dưới quyền admin (nhánh RunAs ở trên) thì Start-Process sẽ mở app CŨNG
# dưới quyền admin — app ghi prefs vào profile của admin, không phải của user.
# explorer.exe chạy sẵn dưới quyền user đang đăng nhập, nhờ nó mở là hạ quyền
# về đúng chỗ.
if (\$isAdmin) {
  Start-Process explorer.exe -ArgumentList "`"\$exe`""
} else {
  Start-Process -FilePath \$exe -WorkingDirectory \$installDir
}
Stop-Transcript | Out-Null
Remove-Item -Recurse -Force \$stage -ErrorAction SilentlyContinue
''';

/// Chuỗi PowerShell nháy đơn: chỉ cần nhân đôi dấu nháy đơn.
String _psQuote(String s) => s.replaceAll("'", "''");

// ─── Android ─────────────────────────────────────────────────────────────────

/// Cài APK qua `PackageInstaller` (native ở `ApkInstaller.kt`).
///
/// **Không thể tự động hoàn toàn** — và đây là giới hạn của Android, không phải
/// thiếu sót của code này. Mọi lần cài ngoài store đều phải qua dialog xác nhận
/// của hệ thống; chỉ device-owner (MDM) hoặc app có chữ ký hệ thống mới bỏ được.
/// Nên luồng tối đa là: app tải APK → gọi PackageInstaller → hệ thống hiện
/// "Cập nhật ứng dụng?" → user bấm 1 lần → cài xong app tự mở lại.
///
/// Ăn theo đó là hai điều kiện, cả hai đã được xử lý:
/// - Quyền "cài ứng dụng không rõ nguồn" cho riêng app này. Native tự mở đúng
///   trang cài đặt nếu chưa có; chỉ phải bật **một lần**.
/// - APK mới phải ký **cùng key** với bản đang cài, không thì hệ thống từ chối
///   (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`). Vì thế release đã chuyển sang
///   keystore cố định — xem `android/app/build.gradle.kts` và
///   `.github/workflows/release.yml`.
class _AndroidInstaller extends UpdateInstaller {
  const _AndroidInstaller();

  /// Trùng với `ApkInstaller.CHANNEL` bên Kotlin.
  static const MethodChannel _channel =
      MethodChannel('bf_stickytask/apk_installer');

  /// `Abi.current()` là API của dart:ffi — không phải thêm plugin chỉ để đọc
  /// `Build.SUPPORTED_ABIS`.
  @override
  ReleaseAsset? pickAsset(List<ReleaseAsset> assets) =>
      pickAndroidAsset(assets, abi: Abi.current());

  /// Dialog của hệ thống cần app còn sống để hiện lên.
  @override
  bool get quitsApp => false;

  @override
  String get handoffMessage =>
      'Android sẽ hỏi xác nhận cài đặt — bấm "Cập nhật" là xong.';

  @override
  Future<void> install(File downloaded, {required String version}) async {
    try {
      await _channel.invokeMethod<void>('install', {'path': downloaded.path});
    } on PlatformException catch (e) {
      throw UpdateException(e.message ?? 'Không cài được APK.');
    } on MissingPluginException {
      throw const UpdateException(
        'Bản Android này chưa có phần cài đặt tự động.',
      );
    }
  }
}

/// Kiểm tra file tải về đúng như GitHub công bố.
///
/// Đây là chống **tải lỗi/thiếu**, KHÔNG phải chống repo bị chiếm: `digest`
/// cũng đến từ chính GitHub API. Muốn chống cái sau thì phải ký asset bằng key
/// riêng (kiểu Sparkle) và nhúng public key vào app — chưa làm.
Future<void> verifyDownload(
  File file,
  ReleaseAsset asset, {
  @visibleForTesting Future<String> Function(File)? hasher,
}) async {
  final actualSize = await file.length();
  if (asset.size > 0 && actualSize != asset.size) {
    throw UpdateException(
      'File tải về sai kích thước ($actualSize/${asset.size} byte) — tải lại.',
    );
  }

  final want = asset.sha256;
  if (want == null) return;

  final got = await (hasher ?? _sha256OfFile)(file);
  if (got != want) {
    throw const UpdateException('File tải về bị lỗi (sha256 không khớp).');
  }
}

/// Băm theo stream: file cài có thể 40–100MB, đọc cả file vào RAM là vô ích.
Future<String> _sha256OfFile(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}
