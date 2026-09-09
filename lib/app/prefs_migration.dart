import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// Kéo SharedPreferences từ container sandbox cũ sang chỗ mới (chỉ macOS).
///
/// Anh em của migration trong [LocalStore] (`lib/data/local_store.dart`), cùng
/// một nguyên nhân: app đã bỏ `com.apple.security.app-sandbox` để tự cập nhật
/// được (xem `macos/Runner/Release.entitlements`), nên mọi đường dẫn per-app
/// đổi chỗ. Với prefs thì plist đi từ
///
///   `~/Library/Containers/<id>/Data/Library/Preferences/<id>.plist`
///
/// sang `~/Library/Preferences/<id>.plist`.
///
/// Cái đắt nhất nếu mất: `sync_url` + `sync_publishable_key` — user
/// phải mò lại URL và key Supabase để nhập tay. Kèm theo là theme, always-on-top,
/// vị trí/kích thước cửa sổ.
///
/// **Không copy file plist.** `cfprefsd` cache toàn bộ preferences trong RAM và
/// ghi đè lại file theo cache của nó, nên copy tay là mất trắng ngay lần ghi
/// tiếp theo. Cách đúng: đọc plist cũ ra rồi ghi lại QUA API SharedPreferences.
///
/// Gọi ở đầu `main()`, trước bất kỳ chỗ nào đọc prefs — `DesktopIntegration`
/// đọc vị trí cửa sổ ngay trong `setUpWindow()`.
class PrefsMigration {
  const PrefsMigration._();

  static const String _bundleId = 'com.blackface.bfstickytask';

  /// Đã migrate xong. Không lấy "có sync_url chưa" làm cờ: user chưa
  /// bao giờ cấu hình sync thì mỗi lần mở app lại đi dò container.
  static const String _keyDone = 'prefs_migrated_from_container';

  /// shared_preferences_foundation gắn tiền tố này vào mọi key khi ghi vào
  /// plist, nên đọc ra phải cắt đi trước khi ghi lại qua API (API tự gắn lại).
  static const String _prefix = 'flutter.';

  /// Các key được phép mang sang. Danh sách đóng, không copy bừa cả plist:
  /// trong đó còn khoá nội bộ của macOS (NSWindow…) mà ghi qua
  /// SharedPreferences là rác.
  static const List<String> _keys = [
    'sync_url',
    'sync_publishable_key',
    'theme_mode',
    'always_on_top',
    'window_bounds',
    'update_skipped_version',
  ];

  /// Trả về số key đã mang sang (0 = không có gì để làm). Không bao giờ ném:
  /// đây là việc chạy ở bootstrap, lỗi thì app vẫn phải mở được.
  static Future<int> run() async {
    if (!Platform.isMacOS) return 0;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_keyDone) ?? false) return 0;

      final legacy = await _readLegacyPlist();
      var moved = 0;
      if (legacy != null) {
        for (final key in _keys) {
          final value = legacy[_prefix + key];
          if (value == null) continue;
          // Đã có giá trị ở chỗ mới thì giữ nguyên — bản mới luôn thắng bản cũ.
          if (prefs.containsKey(key)) continue;
          if (await _write(prefs, key, value)) moved++;
        }
      }

      // Đánh dấu xong kể cả khi không có container cũ, để lần sau khỏi dò lại.
      await prefs.setBool(_keyDone, true);
      return moved;
    } catch (_) {
      return 0;
    }
  }

  /// Đọc plist trong container cũ. Dùng `plutil` vì plist là binary — viết
  /// parser riêng cho một lần migration là quá thừa.
  static Future<Map<String, Object?>?> _readLegacyPlist() async {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return null;

    final path = '$home/Library/Containers/$_bundleId/Data/Library'
        '/Preferences/$_bundleId.plist';
    if (!File(path).existsSync()) return null;

    final res = await Process.run(
      '/usr/bin/plutil',
      ['-convert', 'json', '-o', '-', path],
    );
    if (res.exitCode != 0) return null;

    final json = jsonDecode(res.stdout as String);
    return json is Map<String, Object?> ? json : null;
  }

  /// Ghi lại đúng kiểu. Kiểu lạ (List, Map) thì bỏ — không key nào trong
  /// [_keys] có kiểu đó, gặp là plist đã bị thứ khác ghi vào.
  static Future<bool> _write(
    SharedPreferences prefs,
    String key,
    Object value,
  ) async {
    switch (value) {
      case String v:
        await prefs.setString(key, v);
      case bool v:
        await prefs.setBool(key, v);
      case int v:
        await prefs.setInt(key, v);
      case double v:
        await prefs.setDouble(key, v);
      default:
        return false;
    }
    return true;
  }
}
