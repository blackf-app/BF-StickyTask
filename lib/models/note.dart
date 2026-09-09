import 'package:uuid/uuid.dart';

import 'group.dart';

/// Trạng thái của một note: chưa bắt đầu, đang làm, hoặc đã xong (tab History).
enum NoteStatus { current, inProgress, done }

/// Một dòng note. Mọi mốc thời gian đều lưu ở UTC để so sánh được giữa các máy.
class Note {
  Note({
    required this.id,
    required this.text,
    required this.status,
    required this.sort,
    required this.createdAt,
    required this.updatedAt,
    required this.groupId,
    this.doneAt,
    this.deleted = false,
    this.dirty = false,
  });

  /// Tạo note mới ở tab Current. `dirty = true` để sync đẩy lên server.
  /// [groupId] bỏ trống thì rơi vào group mặc định.
  factory Note.create({
    required String text,
    required double sort,
    String? groupId,
  }) {
    final now = DateTime.now().toUtc();
    return Note(
      id: const Uuid().v4(),
      text: text,
      status: NoteStatus.current,
      sort: sort,
      createdAt: now,
      updatedAt: now,
      groupId: groupId ?? Group.defaultId,
      dirty: true,
    );
  }

  factory Note.fromLocalJson(Map<String, dynamic> j) => Note(
        id: j['id'] as String,
        text: (j['text'] as String?) ?? '',
        status: _statusFrom(j['status']),
        sort: (j['sort'] as num?)?.toDouble() ?? 0,
        createdAt: _timeFrom(j['created_at']) ?? DateTime.now().toUtc(),
        doneAt: _timeFrom(j['done_at']),
        updatedAt: _timeFrom(j['updated_at']) ?? DateTime.now().toUtc(),
        groupId: (j['group_id'] as String?) ?? Group.defaultId,
        deleted: j['deleted'] == true,
        dirty: j['dirty'] == true,
      );

  /// Row lấy từ Supabase luôn là bản đã đồng bộ nên `dirty = false`.
  factory Note.fromRow(Map<String, dynamic> row) =>
      Note.fromLocalJson({...row, 'dirty': false});

  final String id;
  String text;
  NoteStatus status;

  /// Fractional index: chèn giữa hai dòng = trung bình cộng, nên mỗi lần kéo
  /// thả chỉ phải update đúng 1 row thay vì viết lại cả danh sách.
  double sort;

  DateTime createdAt;
  DateTime? doneAt;

  /// Mốc last-write-wins khi trộn dữ liệu giữa các máy.
  DateTime updatedAt;

  /// Group chứa note này — xem [Group].
  String groupId;

  /// Tombstone — xoá mềm để lệnh xoá lan được sang máy khác.
  bool deleted;

  /// Chỉ tồn tại ở local: có thay đổi chưa đẩy lên server.
  bool dirty;

  bool get isDone => status == NoteStatus.done;
  bool get isInProgress => status == NoteStatus.inProgress;

  Map<String, dynamic> toLocalJson() => {
        'id': id,
        'text': text,
        'status': _statusToName(status),
        'sort': sort,
        'created_at': createdAt.toIso8601String(),
        'done_at': doneAt?.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'group_id': groupId,
        'deleted': deleted,
        'dirty': dirty,
      };

  /// Row gửi lên Supabase — không mang theo cờ `dirty` (thuần local).
  /// Không có `user_id`: app không đăng nhập, bảng là một tập note dùng chung
  /// cho mọi máy nhập cùng URL + publishable key.
  Map<String, dynamic> toRow() => {
        'id': id,
        'text': text,
        'status': _statusToName(status),
        'sort': sort,
        'created_at': createdAt.toIso8601String(),
        'done_at': doneAt?.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'group_id': groupId,
        'deleted': deleted,
      };

  static NoteStatus _statusFrom(Object? v) => switch (v) {
        'done' => NoteStatus.done,
        'in_progress' => NoteStatus.inProgress,
        _ => NoteStatus.current,
      };

  static String _statusToName(NoteStatus s) => switch (s) {
        NoteStatus.current => 'current',
        NoteStatus.inProgress => 'in_progress',
        NoteStatus.done => 'done',
      };

  static DateTime? _timeFrom(Object? v) {
    if (v is! String || v.isEmpty) return null;
    return DateTime.tryParse(v)?.toUtc();
  }
}
