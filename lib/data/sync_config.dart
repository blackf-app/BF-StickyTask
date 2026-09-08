import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:shared_preferences/shared_preferences.dart';

import '../env.dart';

/// Cấu hình đồng bộ do user tự nhập trong app: Supabase URL + publishable key.
/// Không có đăng nhập — publishable key là toàn bộ thứ client cần.
class SyncConfig {
  const SyncConfig({required this.url, required this.publishableKey});

  static const SyncConfig empty = SyncConfig(url: '', publishableKey: '');

  /// Giá trị gợi ý từ `lib/env.dart` — **chỉ ở debug build**.
  ///
  /// Dùng để ĐIỀN SẴN form, không phải để tự kết nối: bấm "Ngắt" xong thì
  /// cấu hình đã lưu là rỗng và phải rỗng cho tới khi user bấm Lưu lại — nhưng
  /// bắt user đi tìm lại key thì vô lý, nên form vẫn mồi sẵn từ đây.
  ///
  /// Chặn ở release là có lý do thật: `Env` là `const` nên nó bị compile vào
  /// binary. Bản release đưa cho người khác mà vẫn đọc `Env` thì app của họ tự
  /// nối vào project của DEV ngay lần mở đầu — họ thấy note của dev, note của
  /// họ chảy vào project dev. Xem `tools/build-release.sh`.
  ///
  /// [allowed] chỉ để test ép cả hai nhánh; code thật đừng truyền.
  static SyncConfig fromEnv({bool? allowed}) =>
      (allowed ?? kDebugMode) && Env.isConfigured
          ? SyncConfig.sanitized(
              url: Env.supabaseUrl,
              key: Env.supabasePublishableKey,
            )
          : empty;

  final String url;
  final String publishableKey;

  bool get isEmpty => url.isEmpty || publishableKey.isEmpty;
  bool get isNotEmpty => !isEmpty;

  /// Project ref (`abcdefgh` trong `https://abcdefgh.supabase.co`) — hiện lên UI
  /// để nhìn là biết đang trỏ vào project nào.
  String get projectRef {
    final host = Uri.tryParse(url)?.host ?? '';
    final dot = host.indexOf('.');
    return dot > 0 ? host.substring(0, dot) : host;
  }

  SyncConfig copyWith({String? url, String? publishableKey}) => SyncConfig(
        url: url ?? this.url,
        publishableKey: publishableKey ?? this.publishableKey,
      );

  @override
  bool operator ==(Object other) =>
      other is SyncConfig &&
      other.url == url &&
      other.publishableKey == publishableKey;

  @override
  int get hashCode => Object.hash(url, publishableKey);

  /// Chuẩn hoá input người dùng dán vào: bỏ khoảng trắng hai đầu và dấu `/` cuối
  /// URL. Dán từ dashboard rất hay lẫn hai thứ này.
  static SyncConfig sanitized({required String url, required String key}) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return SyncConfig(url: u, publishableKey: key.trim());
  }

  /// Lý do cấu hình không dùng được, hoặc `null` nếu hợp lệ.
  /// Chặn luôn mấy loại key dán sai chỗ — đây là footgun thật, không phải
  /// validation cho đẹp: secret key mở toàn bộ database.
  String? get problem {
    if (url.isEmpty) return 'Chưa nhập Supabase URL.';
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.isAbsolute || uri.host.isEmpty) {
      return 'URL không hợp lệ. Dạng đúng: https://<project-ref>.supabase.co';
    }
    if (uri.scheme != 'https') {
      return 'URL phải là https://';
    }
    if (publishableKey.isEmpty) return 'Chưa nhập publishable key.';
    if (publishableKey.startsWith('sbp_')) {
      return 'Đây là personal access token (sbp_…), chỉ dùng cho Management API '
          '— không đọc được bảng notes.\n'
          'Lấy publishable key ở Dashboard → Project Settings → API keys.';
    }
    if (publishableKey.startsWith('sb_secret_')) {
      return 'Đây là SECRET key — nó mở toàn bộ database và không nên nằm trong '
          'app.\nDùng publishable key (sb_publishable_…) ở cùng trang API keys.';
    }
    if (_isServiceRoleJwt(publishableKey)) {
      return 'Đây là service_role key — nó bypass mọi RLS và không nên nằm trong '
          'app.\nDùng publishable key (sb_publishable_…) thay vào.';
    }
    return null;
  }

  /// Legacy service_role key là JWT có `"role":"service_role"` ở payload.
  /// Chỉ soi chuỗi, không verify chữ ký — mục đích là cảnh báo, không phải auth.
  static bool _isServiceRoleJwt(String key) {
    final parts = key.split('.');
    if (parts.length != 3) return false;
    try {
      return utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))
          .contains('service_role');
    } catch (_) {
      return false;
    }
  }
}

/// Đọc/ghi [SyncConfig] vào SharedPreferences (cùng nơi lưu theme + window bounds).
///
/// `lib/env.dart` chỉ còn là **giá trị điền sẵn cho lần đầu, ở debug build**:
/// chưa có gì trong prefs thì lấy từ đó để máy dev không phải nhập lại. Sau khi
/// user bấm Lưu thì prefs là nguồn sự thật.
///
/// Ở **release** thì fallback này TẮT — xem [SyncConfig.fromEnv] để biết vì sao.
class SyncConfigStore {
  /// [allowEnvFallback] mặc định theo [kDebugMode]. Chỉ truyền tay trong test.
  SyncConfigStore({bool? allowEnvFallback})
      : allowEnvFallback = allowEnvFallback ?? kDebugMode;

  static const String _kUrl = 'sync_url';
  static const String _kKey = 'sync_publishable_key';

  final bool allowEnvFallback;

  Future<SyncConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_kUrl);
    final key = prefs.getString(_kKey);
    if (url != null && key != null) {
      return SyncConfig(url: url, publishableKey: key);
    }
    return SyncConfig.fromEnv(allowed: allowEnvFallback);
  }

  Future<void> save(SyncConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUrl, config.url);
    await prefs.setString(_kKey, config.publishableKey);
  }

  /// Ghi chuỗi rỗng chứ KHÔNG remove key: `load()` chỉ fallback về `Env` khi
  /// prefs chưa từng được ghi. Remove hẳn thì lần mở app sau sẽ lôi lại cấu
  /// hình trong `env.dart` — tức bấm "Ngắt" xong khởi động lại là nó tự nối lại.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUrl, '');
    await prefs.setString(_kKey, '');
  }
}
