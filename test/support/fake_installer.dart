import 'dart:io';

import 'package:bf_stickytask/data/update_installer.dart';
import 'package:bf_stickytask/data/update_service.dart';

/// [UpdateInstaller] giả cho test.
///
/// Phải có: installer thật đọc `Platform.isMacOS`/`isWindows` và đi ghi file
/// vào thư mục app đang chạy — chạy trong test là vừa phụ thuộc máy chạy test,
/// vừa có nguy cơ thay thật.
class FakeInstaller extends UpdateInstaller {
  FakeInstaller({
    this.assetNeedle = '.zip',
    this.quitsApp = true,
    this.throwOnInstall,
  });

  /// Chuỗi phải có trong tên asset để [pickAsset] nhận. `null` = không nhận
  /// asset nào (giả nền tảng không có bản build trong release).
  final String? assetNeedle;

  @override
  final bool quitsApp;

  /// Đặt để giả cài lỗi.
  final UpdateException? throwOnInstall;

  /// File được đưa vào [install] — test kiểm nội dung đã tải đúng chưa.
  File? installed;
  String? installedVersion;
  int installCalls = 0;

  @override
  String get handoffMessage => 'App sẽ tự đóng rồi mở lại.';

  @override
  ReleaseAsset? pickAsset(List<ReleaseAsset> assets) {
    final needle = assetNeedle;
    if (needle == null) return null;
    for (final asset in assets) {
      if (asset.name.toLowerCase().contains(needle)) return asset;
    }
    return null;
  }

  @override
  Future<void> install(File downloaded, {required String version}) async {
    installCalls++;
    installed = downloaded;
    installedVersion = version;
    final failure = throwOnInstall;
    if (failure != null) throw failure;
  }
}
