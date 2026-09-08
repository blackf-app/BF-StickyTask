import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/note.dart';

/// Ảnh chụp dữ liệu đọc lên từ file local.
class LocalSnapshot {
  const LocalSnapshot({required this.notes, this.lastPull});

  final List<Note> notes;
  final String? lastPull;
}

/// Lưu toàn bộ note vào 1 file JSON trong Application Support của app.
/// Quy mô vài nghìn dòng nên đọc/ghi cả file là đủ, không cần SQLite.
class LocalStore {
  static const String _fileName = 'notes.json';
  static const int _schemaVersion = 1;

  File? _cachedFile;

  Future<File> _file() async {
    final cached = _cachedFile;
    if (cached != null) return cached;
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return _cachedFile = File('${dir.path}${Platform.pathSeparator}$_fileName');
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
      return LocalSnapshot(notes: notes, lastPull: json['last_pull'] as String?);
    } catch (_) {
      // File hỏng thì coi như chưa có dữ liệu — server sẽ pull lại.
      return const LocalSnapshot(notes: []);
    }
  }

  Future<void> save(List<Note> notes, {String? lastPull}) async {
    final file = await _file();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({
        'version': _schemaVersion,
        'last_pull': lastPull,
        'notes': notes.map((n) => n.toLocalJson()).toList(),
      }),
      flush: true,
    );
    // Ghi kiểu atomic: app bị kill giữa lúc ghi cũng không mất file cũ.
    await tmp.rename(file.path);
  }
}
