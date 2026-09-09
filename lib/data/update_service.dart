import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Repo chứa release. Phải là repo **public**: app gọi `/releases/latest` mà
/// KHÔNG có token — repo private thì GitHub trả 404 và tính năng chết câm.
/// Đừng "sửa" bằng cách nhúng PAT vào đây: `strings` là ra ngay, đúng thứ
/// `tools/scan-secrets.sh` tồn tại để chặn.
const String kUpdateRepo = 'blackf-app/BF-StickyTask';

/// Một file đính kèm release — bản build cho một nền tảng.
@immutable
class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.url,
    required this.size,
    this.sha256,
  });

  /// Tên file: `BF-StickyTask-macos.zip`, `app-arm64-v8a-release.apk`…
  final String name;

  /// `browser_download_url` — tải trực tiếp, không cần token với repo public.
  final String url;

  /// Byte. `0` nếu GitHub không trả (không chặn tải, chỉ mất progress %).
  final int size;

  /// Hex thường, lấy từ field `digest` (`sha256:…`). `null` nếu release được
  /// tạo trước khi GitHub thêm field này.
  final String? sha256;

  static ReleaseAsset? fromJson(Map<String, dynamic> json) {
    final name = (json['name'] as String? ?? '').trim();
    final url = (json['browser_download_url'] as String? ?? '').trim();
    if (name.isEmpty || url.isEmpty) return null;

    // `digest` dạng `sha256:abcd…`. Thuật toán khác thì bỏ, đừng so bằng
    // hàm băm sai — verify sẽ fail oan mọi lần tải.
    final digest = (json['digest'] as String? ?? '').trim().toLowerCase();
    final sha = digest.startsWith('sha256:') ? digest.substring(7) : null;

    return ReleaseAsset(
      name: name,
      url: url,
      size: (json['size'] as num?)?.toInt() ?? 0,
      sha256: (sha != null && sha.isNotEmpty) ? sha : null,
    );
  }
}

/// Một bản release đọc từ GitHub.
@immutable
class AppRelease {
  const AppRelease({
    required this.version,
    required this.tag,
    required this.notes,
    required this.pageUrl,
    this.assets = const [],
  });

  /// Đã bỏ tiền tố `v`: `1.0.1`.
  final String version;

  /// Tag gốc: `v1.0.1`.
  final String tag;

  /// Body của release — có thể rỗng.
  final String notes;

  /// `html_url` — trang release. Vẫn giữ làm đường lùi khi không tự cài được
  /// (không có asset cho nền tảng này, hoặc cài lỗi).
  final String pageUrl;

  /// File đính kèm, để tự tải + tự cài. Rỗng nghĩa là chỉ còn cách mở
  /// [pageUrl].
  final List<ReleaseAsset> assets;

  /// Trả `null` nếu JSON không có `tag_name` (không đủ dữ liệu để so version).
  static AppRelease? fromJson(Map<String, dynamic> json) {
    final tag = (json['tag_name'] as String? ?? '').trim();
    if (tag.isEmpty) return null;
    return AppRelease(
      version: normalizeVersion(tag),
      tag: tag,
      notes: (json['body'] as String? ?? '').trim(),
      pageUrl: (json['html_url'] as String? ?? '').trim().isEmpty
          ? 'https://github.com/$kUpdateRepo/releases/latest'
          : json['html_url'] as String,
      assets: ((json['assets'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ReleaseAsset.fromJson)
          .whereType<ReleaseAsset>()
          .toList(growable: false),
    );
  }
}

/// Lỗi có thông báo tiếng Việt hiện thẳng lên dialog.
class UpdateException implements Exception {
  const UpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Bỏ tiền tố `v`, bỏ build metadata (`+1`) và pre-release (`-beta`).
String normalizeVersion(String raw) {
  var v = raw.trim();
  if (v.startsWith('v') || v.startsWith('V')) v = v.substring(1);
  final cut = v.indexOf(RegExp(r'[+\-]'));
  return cut >= 0 ? v.substring(0, cut) : v;
}

/// So version kiểu `1.2.3`: `<0` a cũ hơn b, `0` bằng, `>0` a mới hơn b.
///
/// Thiếu thành phần thì coi như 0 (`1.1` == `1.1.0`), thành phần không phải số
/// cũng thành 0 — thà so sai một tag rác còn hơn ném lỗi giữa lúc mở app.
int compareVersions(String a, String b) {
  final pa = _versionParts(a);
  final pb = _versionParts(b);
  final len = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < len; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x < y ? -1 : 1;
  }
  return 0;
}

List<int> _versionParts(String raw) => normalizeVersion(raw)
    .split('.')
    .map((p) => int.tryParse(p.trim()) ?? 0)
    .toList(growable: false);

enum UpdateStatus {
  /// Chưa kiểm lần nào trong phiên này.
  idle,
  checking,

  /// Đã kiểm, đang là bản mới nhất.
  upToDate,

  /// Đã kiểm, có bản mới hơn.
  available,
  error,
}

/// Hàm lấy release mới nhất — tách ra để test không cần mạng.
typedef ReleaseFetcher = Future<AppRelease?> Function();

/// Kiểm tra bản mới trên GitHub Releases.
///
/// Chỉ lo phần *biết có bản mới*: so version, giữ trạng thái cho UI, nhớ
/// version user đã bỏ qua. Phần *tải về và cài* nằm ở [Updater]
/// (`lib/data/updater.dart`).
class UpdateService extends ChangeNotifier {
  UpdateService({ReleaseFetcher? fetcher, String? currentVersion})
      : _fetcher = fetcher ?? fetchLatestRelease,
        _currentVersion = currentVersion ?? '';

  static const String _keySkippedVersion = 'update_skipped_version';

  final ReleaseFetcher _fetcher;

  SharedPreferences? _prefs;
  String _currentVersion;
  String _skippedVersion = '';

  UpdateStatus _status = UpdateStatus.idle;
  AppRelease? _latest;
  String? _error;
  DateTime? _lastCheckedAt;

  /// Version đang chạy, dạng `1.0.0`. Rỗng nếu chưa gọi [load].
  String get currentVersion => _currentVersion;

  UpdateStatus get status => _status;

  /// Release mới nhất đã đọc được — có thể chính là bản đang chạy.
  AppRelease? get latest => _latest;

  String? get error => _error;
  DateTime? get lastCheckedAt => _lastCheckedAt;

  /// Có bản mới hơn bản đang chạy.
  bool get updateAvailable => _status == UpdateStatus.available;

  /// Version user đã bấm "Bỏ qua bản này" — chỉ tắt popup tự động, [check]
  /// bằng tay vẫn báo có bản mới.
  String get skippedVersion => _skippedVersion;

  /// Đọc version đang chạy + version đã bỏ qua. Gọi trước [checkOnStartup].
  Future<void> load() async {
    if (_currentVersion.isEmpty) {
      try {
        _currentVersion = (await PackageInfo.fromPlatform()).version;
      } catch (_) {
        // Không đọc được version thì thôi: mọi so sánh sau đó bị bỏ qua chứ
        // không được phép làm chết bootstrap của app.
        _currentVersion = '';
      }
    }
    _prefs = await SharedPreferences.getInstance();
    _skippedVersion = _prefs?.getString(_keySkippedVersion) ?? '';
    notifyListeners();
  }

  /// Kiểm khi mở app. Trả release **chỉ khi** nên bật popup: có bản mới hơn và
  /// user chưa bỏ qua đúng bản đó. Lỗi mạng lúc mở app thì im lặng — không ai
  /// muốn vừa mở app đã ăn một popup báo lỗi.
  Future<AppRelease?> checkOnStartup() async {
    await check();
    if (!updateAvailable) return null;
    final release = _latest;
    if (release == null) return null;
    if (release.version == _skippedVersion) return null;
    return release;
  }

  /// Kiểm bằng tay. Luôn cập nhật [status] / [error] để dialog hiện kết quả.
  Future<void> check() async {
    if (_status == UpdateStatus.checking) return;
    _status = UpdateStatus.checking;
    _error = null;
    notifyListeners();

    try {
      final release = await _fetcher();
      _lastCheckedAt = DateTime.now();
      if (release == null) {
        _latest = null;
        _status = UpdateStatus.upToDate;
        _error = null;
      } else {
        _latest = release;
        // Không đọc được version đang chạy thì đừng đoán là có bản mới —
        // so với chuỗi rỗng sẽ luôn ra "cũ hơn" và popup mỗi lần mở app.
        final newer = _currentVersion.isNotEmpty &&
            compareVersions(_currentVersion, release.version) < 0;
        _status = newer ? UpdateStatus.available : UpdateStatus.upToDate;
      }
    } on UpdateException catch (e) {
      _status = UpdateStatus.error;
      _error = e.message;
    } catch (e) {
      _status = UpdateStatus.error;
      _error = 'Không kiểm được bản mới — $e';
    }
    notifyListeners();
  }

  /// Ghi nhớ "bỏ qua bản này" để lần mở app sau không popup lại.
  Future<void> skipLatest() async {
    final release = _latest;
    if (release == null) return;
    _skippedVersion = release.version;
    notifyListeners();
    await _prefs?.setString(_keySkippedVersion, release.version);
  }

  /// Trang release để mở trên browser — kể cả khi chưa kiểm được gì.
  String get releasePageUrl =>
      _latest?.pageUrl ?? 'https://github.com/$kUpdateRepo/releases/latest';
}

/// Gọi GitHub API. Không token: repo phải public (xem [kUpdateRepo]).
Future<AppRelease?> fetchLatestRelease({http.Client? client}) async {
  final owned = client == null;
  final c = client ?? http.Client();
  try {
    final res = await c
        .get(
          Uri.parse('https://api.github.com/repos/$kUpdateRepo/releases/latest'),
          headers: const {
            'Accept': 'application/vnd.github+json',
            // Thiếu User-Agent là GitHub trả 403.
            'User-Agent': 'BF-StickyTask',
            'X-GitHub-Api-Version': '2022-11-28',
          },
        )
        .timeout(const Duration(seconds: 12));

    switch (res.statusCode) {
      case 200:
        final json = jsonDecode(res.body);
        if (json is! Map<String, dynamic>) {
          throw const UpdateException('GitHub trả dữ liệu lạ.');
        }
        return AppRelease.fromJson(json);
      case 404:
        // /releases/latest bỏ qua draft và pre-release, nên 404 nghĩa là chưa
        // có release chính thức nào — hoặc repo đang private.
        throw const UpdateException(
          'Không thấy release nào (repo private hoặc chưa publish release).',
        );
      case 403:
      case 429:
        throw const UpdateException(
          'GitHub tạm chặn vì gọi quá nhiều — thử lại sau ít phút.',
        );
      default:
        throw UpdateException('GitHub trả HTTP ${res.statusCode}.');
    }
  } on TimeoutException {
    throw const UpdateException('Quá thời gian chờ — kiểm lại mạng.');
  } on http.ClientException catch (e) {
    throw UpdateException('Không kết nối được GitHub — ${e.message}');
  } finally {
    if (owned) c.close();
  }
}
