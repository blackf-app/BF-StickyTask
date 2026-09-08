import 'package:uuid/uuid.dart';

/// Trạng thái của một note: đang cần làm, hoặc đã xong (nằm ở tab History).
enum NoteStatus { current, done }

/// Một dòng note. Mọi mốc thời gian đều lưu ở UTC để so sánh được giữa các máy.
class Note {
  Note({
    required this.id,
    required this.text,
    required this.status,
    required this.sort,
    required this.createdAt,
    required this.updatedAt,
    this.doneAt,
    this.deleted = false,
    this.dirty = false,
  });

  /// Tạo note mới ở tab Current. `dirty = true` để sync đẩy lên server.
  factory Note.create({required String text, required double sort}) {
    final now = DateTime.now().toUtc();
    return Note(
      id: const Uuid().v4(),
      text: text,
      status: NoteStatus.current,
      sort: sort,
      createdAt: now,
      updatedAt: now,
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

  /// Tombstone — xoá mềm để lệnh xoá lan được sang máy khác.
  bool deleted;

  /// Chỉ tồn tại ở local: có thay đổi chưa đẩy lên server.
  bool dirty;

  bool get isDone => status == NoteStatus.done;

  Map<String, dynamic> toLocalJson() => {
        'id': id,
        'text': text,
        'status': status.name,
        'sort': sort,
        'created_at': createdAt.toIso8601String(),
        'done_at': doneAt?.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'deleted': deleted,
        'dirty': dirty,
      };

  /// Row gửi lên Supabase — không mang theo cờ `dirty` (thuần local).
  /// Không có `user_id`: app không đăng nhập, bảng là một tập note dùng chung
  /// cho mọi máy nhập cùng URL + publishable key.
  Map<String, dynamic> toRow() => {
        'id': id,
        'text': text,
        'status': status.name,
        'sort': sort,
        'created_at': createdAt.toIso8601String(),
        'done_at': doneAt?.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'deleted': deleted,
      };

  static NoteStatus _statusFrom(Object? v) =>
      v == 'done' ? NoteStatus.done : NoteStatus.current;

  static DateTime? _timeFrom(Object? v) {
    if (v is! String || v.isEmpty) return null;
    return DateTime.tryParse(v)?.toUtc();
  }
}
