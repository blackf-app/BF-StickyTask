import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/group.dart';
import '../models/note.dart';

/// Ảnh chụp dữ liệu đọc lên từ file local.
class LocalSnapshot {
  const LocalSnapshot({required this.notes, this.groups = const [], this.lastPull});

  final List<Note> notes;
  final List<Group> groups;
  final String? lastPull;
}

/// Lưu toàn bộ note vào 1 file JSON trong Application Support của app.
/// Quy mô vài nghìn dòng nên đọc/ghi cả file là đủ, không cần SQLite.
class LocalStore {
  static const String _fileName = 'notes.json';
  static const int _schemaVersion = 1;

  /// Bundle id — dùng để dò container sandbox cũ trên macOS.
  static const String _bundleId = 'com.blackface.bfstickytask';

  File? _cachedFile;

  Future<File> _file() async {
    final cached = _cachedFile;
    if (cached != null) return cached;
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    final file = File('${dir.path}${Platform.pathSeparator}$_fileName');
    // Phải chạy TRƯỚC lần đọc đầu tiên, không thì app mở ra trống rỗng.
    await _migrateFromSandboxContainer(file);
    return _cachedFile = file;
  }

  /// macOS: kéo `notes.json` từ container sandbox cũ sang chỗ mới.
  ///
  /// App từng bật `com.apple.security.app-sandbox`, khi đó
  /// `getApplicationSupportDirectory()` trả về đường dẫn TRONG container:
  ///
  ///   `~/Library/Containers/<id>/Data/Library/Application Support/<id>`
  ///
  /// Sandbox đã bị bỏ để app tự cập nhật được (xem
  /// `macos/Runner/Release.entitlements`), nên hàm đó giờ trả về
  /// `~/Library/Application Support/<id>` — chỗ khác hẳn. Không copy sang là
  /// user nâng cấp xong mở app thấy sạch note.
  ///
  /// Idempotent: đích đã có `notes.json` thì không làm gì. Container cũ để
  /// nguyên làm backup, không xoá. Lỗi thì im lặng bỏ qua — thà mở app ra
  /// trống (dữ liệu vẫn còn trong container cũ, `tools/migrate-container.sh`
  /// vớt lại được) còn hơn chết ở bootstrap.
  Future<void> _migrateFromSandboxContainer(File target) async {
    if (!Platform.isMacOS) return;
    if (target.existsSync()) return;

    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return;

    try {
      final legacy = File(
        '$home/Library/Containers/$_bundleId/Data/Library'
        '/Application Support/$_bundleId/$_fileName',
      );
      if (!legacy.existsSync()) return;
      // copy() ghi trực tiếp ra đích; đích vừa kiểm là chưa tồn tại nên không
      // có nguy cơ đè lên dữ liệu mới hơn.
      await legacy.copy(target.path);
    } catch (_) {
      // Đọc container cũ có thể bị TCC chặn trên macOS mới. Không cứu được thì
      // thôi — save() sau đó vẫn ghi bình thường vào chỗ mới.
    }
  }

  Future<String> filePath() async => (await _file()).path;

  Future<LocalSnapshot> load() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return const LocalSnapshot(notes: []);
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return const LocalSnapshot(notes: []);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final notes = ((json['notes'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Note.fromLocalJson)
          .toList();
      final groups = ((json['groups'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Group.fromLocalJson)
          .toList();
      return LocalSnapshot(
        notes: notes,
        groups: groups,
        lastPull: json['last_pull'] as String?,
      );
    } catch (_) {
      // File hỏng thì coi như chưa có dữ liệu — server sẽ pull lại.
      return const LocalSnapshot(notes: []);
    }
  }

  Future<void> save(
    List<Note> notes,
    List<Group> groups, {
    String? lastPull,
  }) async {
    final file = await _file();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({
        'version': _schemaVersion,
        'last_pull': lastPull,
        'notes': notes.map((n) => n.toLocalJson()).toList(),
        'groups': groups.map((g) => g.toLocalJson()).toList(),
      }),
      flush: true,
    );
    // Ghi kiểu atomic: app bị kill giữa lúc ghi cũng không mất file cũ.
    await tmp.rename(file.path);
  }
}
