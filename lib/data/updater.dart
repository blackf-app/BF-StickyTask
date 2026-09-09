import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'update_installer.dart';
import 'update_service.dart';

/// Giai đoạn của một lần cập nhật. Dialog đọc cái này để hiện progress.
enum UpdatePhase {
  idle,
  downloading,

  /// Đối chiếu kích thước + sha256 với thứ GitHub công bố.
  verifying,

  /// Đang giải nén / bàn giao cho script hoặc dialog hệ thống.
  installing,

  /// Đã bàn giao xong. Desktop: app sắp tự thoát. Android: dialog hệ thống
  /// đang chờ user bấm.
  handedOff,
  error,
}

/// Tải bản mới về rồi cài — nửa còn lại của [UpdateService].
///
/// Chia đôi có chủ ý: [UpdateService] chỉ gọi GitHub API và so version (chạy
/// mỗi lần mở app, phải nhẹ và im lặng khi lỗi), còn class này mới là phần
/// động tới file trên máy và chỉ chạy khi user bấm.
///
/// Phần thực sự cài nằm ở [UpdateInstaller] — mỗi nền tảng một cách, xem
/// `lib/data/update_installer.dart`.
class Updater extends ChangeNotifier {
  /// [installer] tường minh, kể cả khi là `null` — KHÔNG rơi về
  /// `UpdateInstaller.forCurrentPlatform()` ở đây: làm vậy thì test truyền
  /// `null` để giả "nền tảng không tự cài được" lại âm thầm nhận installer
  /// thật của máy đang chạy test, và test đó kiểm sai thứ nó tưởng.
  /// Chỗ dựng thật là `main()`.
  Updater({
    required UpdateInstaller? installer,
    http.Client Function()? clientFactory,
    Future<void> Function()? onQuit,
  })  :
        // Tham số phải nhận null tường minh nên không đặt tên private được.
        // ignore: prefer_initializing_formals
        _installer = installer,
        _clientFactory = clientFactory ?? http.Client.new,
        _onQuit = onQuit ?? _defaultQuit;

  /// Thoát app để script bên ngoài ghi đè được. Đường thật đi qua `onQuit` mà
  /// `main()` truyền vào (nó còn phải flush note trước khi chết).
  static Future<void> _defaultQuit() async => exit(0);

  final UpdateInstaller? _installer;
  final http.Client Function() _clientFactory;
  final Future<void> Function() _onQuit;

  UpdatePhase _phase = UpdatePhase.idle;
  int _received = 0;
  int _total = 0;
  String? _error;
  bool _cancelled = false;

  UpdatePhase get phase => _phase;

  /// `false` = nền tảng này chưa có đường tự cài (Linux) → UI hiện nút mở
  /// trang release như trước.
  bool get supported => _installer != null;

  /// Đang làm việc gì đó không nên bị cắt ngang.
  bool get busy =>
      _phase == UpdatePhase.downloading ||
      _phase == UpdatePhase.verifying ||
      _phase == UpdatePhase.installing;

  int get received => _received;
  int get total => _total;

  /// `null` khi chưa biết tổng dung lượng (server không trả Content-Length) —
  /// UI hiện progress bar vô định thay vì phần trăm sai.
  double? get progress {
    if (_total <= 0) return null;
    return (_received / _total).clamp(0.0, 1.0);
  }

  String? get error => _error;

  /// Câu mô tả việc sắp xảy ra, khác nhau giữa desktop và Android.
  String get handoffMessage => _installer?.handoffMessage ?? '';

  /// Có asset dùng được cho máy này trong [release] không.
  bool canInstall(AppRelease release) =>
      _installer?.pickAsset(release.assets) != null;

  /// Tải rồi cài [release]. Không ném — mọi lỗi rơi vào [error] để dialog hiện.
  ///
  /// Desktop: hàm này chỉ trả về nếu **lỗi**; thành công thì app đã thoát.
  Future<void> run(AppRelease release) async {
    final installer = _installer;
    if (installer == null) {
      _fail('Nền tảng này chưa tự cài được — mở trang release để tải tay.');
      return;
    }
    if (busy) return;

    final asset = installer.pickAsset(release.assets);
    if (asset == null) {
      _fail(
        'Release ${release.tag} không có bản build cho máy này — '
        'mở trang release để xem có gì.',
      );
      return;
    }

    _cancelled = false;
    _error = null;
    _received = 0;
    _total = asset.size;
    _phase = UpdatePhase.downloading;
    notifyListeners();

    File? file;
    try {
      file = await _download(asset);
      if (_cancelled) return _reset();

      _phase = UpdatePhase.verifying;
      notifyListeners();
      await verifyDownload(file, asset);
      if (_cancelled) return _reset();

      _phase = UpdatePhase.installing;
      notifyListeners();
      await installer.install(file, version: release.version);

      _phase = UpdatePhase.handedOff;
      notifyListeners();

      if (installer.quitsApp) {
        // Cho UI kịp vẽ frame "đang khởi động lại" trước khi process chết —
        // không thì app biến mất đột ngột, ai cũng nghĩ là crash.
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await _onQuit();
      }
    } on UpdateException catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail('Không cài được bản mới — $e');
    } finally {
      // Desktop thành công thì không tới đây (app đã exit). Tới đây là lỗi
      // hoặc Android — cả hai đều không cần giữ file cài lại.
      //
      // Xoá cả thư mục tạm chứa nó, không chỉ file: mỗi lần tải tạo một
      // `bfst-download-*` riêng, xoá lẻ file thì mỗi lần cập nhật lỗi để lại
      // một thư mục rỗng trong temp.
      if (_phase != UpdatePhase.handedOff && file != null) {
        try {
          await file.parent.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  /// Huỷ giữa lúc tải. Sau khi đã bàn giao cho installer thì không huỷ được
  /// nữa — script/dialog hệ thống đã chạy.
  void cancel() {
    if (_phase == UpdatePhase.downloading ||
        _phase == UpdatePhase.verifying) {
      _cancelled = true;
    }
  }

  /// Về trạng thái ban đầu để bấm lại được sau khi lỗi.
  void reset() => _reset();

  Future<File> _download(ReleaseAsset asset) async {
    final client = _clientFactory();
    // Tải vào file tạm rồi mới cài: 40–100MB, giữ trong RAM là vô nghĩa.
    final dir = await Directory.systemTemp.createTemp('bfst-download-');
    final file = File('${dir.path}${Platform.pathSeparator}${asset.name}');

    var handedOver = false;
    try {
      final request = http.Request('GET', Uri.parse(asset.url))
        ..headers['User-Agent'] = 'BF-StickyTask';
      // GitHub trả 302 sang CDN; http tự theo redirect nhưng phải cho phép.
      request.followRedirects = true;

      final response = await client.send(request).timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw const UpdateException(
              'Quá thời gian chờ khi bắt đầu tải — kiểm lại mạng.',
            ),
          );
      if (response.statusCode != 200) {
        throw UpdateException(
          'Không tải được file cài (HTTP ${response.statusCode}).',
        );
      }

      // Content-Length của CDN đáng tin hơn `size` của API (asset có thể được
      // upload lại), nên có thì lấy.
      final declared = response.contentLength;
      if (declared != null && declared > 0) _total = declared;

      final sink = file.openWrite();
      try {
        await for (final chunk in response.stream) {
          if (_cancelled) break;
          sink.add(chunk);
          _received += chunk.length;
          notifyListeners();
        }
      } finally {
        await sink.close();
      }
      handedOver = true;
      return file;
    } finally {
      client.close();
      // Ném trước khi trả file ra (HTTP lỗi, timeout) thì `run()` không có gì
      // để dọn — tự dọn ở đây.
      if (!handedOver) {
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  void _fail(String message) {
    _error = message;
    _phase = UpdatePhase.error;
    notifyListeners();
  }

  void _reset() {
    _phase = UpdatePhase.idle;
    _received = 0;
    _total = 0;
    _error = null;
    _cancelled = false;
    notifyListeners();
  }
}

/// `12,4 MB` — đủ cho một dòng progress, không cần intl.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[unit]}';
}
