import 'package:uuid/uuid.dart';

/// Một nhóm việc (vd: "Cá nhân", "Công ty"). Mỗi note thuộc đúng 1 group.
///
/// Đồng bộ theo đúng pattern của [Note]: `dirty` cho biết có thay đổi chưa đẩy
/// lên server, `deleted` là tombstone để lệnh xoá lan sang máy khác.
class Group {
  Group({
    required this.id,
    required this.name,
    required this.sort,
    required this.createdAt,
    required this.updatedAt,
    this.deleted = false,
    this.dirty = false,
  });

  /// Id cố định (không phải uuid) cho group mặc định — để mọi máy tự bootstrap
  /// ra CÙNG MỘT group khi migrate note cũ, không tạo trùng lúc merge qua sync.
  static const String defaultId = 'default';
  static const String defaultName = 'Chung';

  factory Group.create({required String name, required double sort}) {
    final now = DateTime.now().toUtc();
    return Group(
      id: const Uuid().v4(),
      name: name,
      sort: sort,
      createdAt: now,
      updatedAt: now,
      dirty: true,
    );
  }

  factory Group.defaultGroup() {
    final now = DateTime.now().toUtc();
    return Group(
      id: defaultId,
      name: defaultName,
      sort: 0,
      createdAt: now,
      updatedAt: now,
      dirty: true,
    );
  }

  factory Group.fromLocalJson(Map<String, dynamic> j) => Group(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        sort: (j['sort'] as num?)?.toDouble() ?? 0,
        createdAt: _timeFrom(j['created_at']) ?? DateTime.now().toUtc(),
        updatedAt: _timeFrom(j['updated_at']) ?? DateTime.now().toUtc(),
        deleted: j['deleted'] == true,
        dirty: j['dirty'] == true,
      );

  /// Row lấy từ Supabase luôn là bản đã đồng bộ nên `dirty = false`.
  factory Group.fromRow(Map<String, dynamic> row) =>
      Group.fromLocalJson({...row, 'dirty': false});

  final String id;
  String name;
  double sort;
  DateTime createdAt;
  DateTime updatedAt;
  bool deleted;
  bool dirty;

  Map<String, dynamic> toLocalJson() => {
        'id': id,
        'name': name,
        'sort': sort,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'deleted': deleted,
        'dirty': dirty,
      };

  Map<String, dynamic> toRow() => {
        'id': id,
        'name': name,
        'sort': sort,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'deleted': deleted,
      };

  static DateTime? _timeFrom(Object? v) {
    if (v is! String || v.isEmpty) return null;
    return DateTime.tryParse(v)?.toUtc();
  }
}
