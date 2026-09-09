import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/group.dart';
import '../models/note.dart';
import 'local_store.dart';

/// Nguồn sự thật duy nhất cho danh sách note + group. Mọi thao tác đều ghi vào
/// bộ nhớ + file local ngay lập tức (offline-first), sync đẩy lên server sau.
class NoteRepo extends ChangeNotifier {
  NoteRepo(this._store);

  static const double _sortStep = 1;
  static const double _minGap = 1e-6;
  static const Duration _saveDebounce = Duration(milliseconds: 200);
  static const Duration _tombstoneTtl = Duration(days: 30);

  final LocalStore _store;
  final Map<String, Note> _byId = {};
  final Map<String, Group> _groupsById = {};

  /// Mốc `updated_at` lớn nhất đã pull về (chung cho cả note lẫn group), dùng
  /// làm con trỏ cho lần pull sau.
  String? lastPull;

  /// Sync service gắn callback này để biết khi nào cần đẩy lên server.
  VoidCallback? onLocalChange;

  Timer? _saveTimer;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  /// Tab Current — sắp theo `sort` tăng dần (thứ tự người dùng tự kéo).
  List<Note> get current {
    final list = _byId.values.where((n) => !n.deleted && !n.isDone).toList()
      ..sort((a, b) => a.sort.compareTo(b.sort));
    return list;
  }

  /// Tab History — việc xong gần nhất lên đầu.
  List<Note> get history {
    final list = _byId.values.where((n) => !n.deleted && n.isDone).toList()
      ..sort((a, b) =>
          (b.doneAt ?? b.updatedAt).compareTo(a.doneAt ?? a.updatedAt));
    return list;
  }

  /// Các group đang hoạt động, sắp theo thứ tự tạo/kéo.
  List<Group> get groups {
    final list = _groupsById.values.where((g) => !g.deleted).toList()
      ..sort((a, b) => a.sort.compareTo(b.sort));
    return list;
  }

  // region Load / Save

  Future<void> load() async {
    final snapshot = await _store.load();
    _byId
      ..clear()
      ..addEntries(snapshot.notes.map((n) => MapEntry(n.id, n)));
    _groupsById
      ..clear()
      ..addEntries(snapshot.groups.map((g) => MapEntry(g.id, g)));
    lastPull = snapshot.lastPull;
    _ensureDefaultGroup();
    _loaded = true;
    _pruneTombstones();
    notifyListeners();
  }

  /// Ghi ngay ra file, dùng khi app bị pause/close.
  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (!_loaded) return;
    await _store.save(
      _byId.values.toList(),
      _groupsById.values.toList(),
      lastPull: lastPull,
    );
  }

  /// Lần đầu mở app (hoặc dữ liệu cũ không có group nào) thì tự tạo group
  /// mặc định — không thì UI không có group nào để hiện.
  ///
  /// Không tự [_scheduleSave] ở đây: `id` cố định nên việc này idempotent —
  /// nếu app bị kill trước khi kịp flush (do mutation khác hoặc lifecycle
  /// pause) thì lần mở sau chỉ tái tạo lại đúng group này, không mất gì. Và
  /// nếu đã cấu hình sync thì `syncNow()` đọc thẳng từ bộ nhớ nên vẫn push
  /// được dù file local chưa kịp ghi.
  void _ensureDefaultGroup() {
    final hasActive = _groupsById.values.any((g) => !g.deleted);
    if (hasActive) return;
    _groupsById[Group.defaultId] = Group.defaultGroup();
  }

  // endregion

  // region Mutations

  /// [groupId] bỏ trống thì rơi vào group mặc định.
  Note add(String text, {String? groupId}) {
    final trimmed = text.trim();
    final note = Note.create(
      text: trimmed,
      sort: _maxCurrentSort(groupId: groupId) + _sortStep,
      groupId: groupId,
    );
    _byId[note.id] = note;
    _afterLocalChange();
    return note;
  }

  void editText(String id, String text) {
    final note = _byId[id];
    if (note == null) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      remove(id);
      return;
    }
    if (trimmed == note.text) return;
    note.text = trimmed;
    _touch(note);
  }

  void remove(String id) {
    final note = _byId[id];
    if (note == null || note.deleted) return;
    note.deleted = true;
    _touch(note);
  }

  /// Tick done → dòng rời tab Current sang tab History (và ngược lại).
  void setDone(String id, bool done) {
    final note = _byId[id];
    if (note == null || note.isDone == done) return;
    if (done) {
      note.status = NoteStatus.done;
      note.doneAt = DateTime.now().toUtc();
    } else {
      note.status = NoteStatus.current;
      note.doneAt = null;
      // Restore thì xếp xuống cuối danh sách Current, trong đúng group của nó.
      note.sort =
          _maxCurrentSort(exceptId: note.id, groupId: note.groupId) +
              _sortStep;
    }
    _touch(note);
  }

  /// Đánh dấu / bỏ đánh dấu "đang làm". Không đụng tới note đã done — phải
  /// restore về Current trước.
  void setInProgress(String id, bool inProgress) {
    final note = _byId[id];
    if (note == null || note.isDone) return;
    final target = inProgress ? NoteStatus.inProgress : NoteStatus.current;
    if (note.status == target) return;
    note.status = target;
    _touch(note);
  }

  /// Chuyển note sang group khác.
  void setGroup(String id, String groupId) {
    final note = _byId[id];
    if (note == null || note.groupId == groupId) return;
    note.groupId = groupId;
    _touch(note);
  }

  void clearHistory() => removeAll(history.map((n) => n.id));

  /// Xoá nhiều note một lần (dùng cho "Xoá hết" ở History, có thể đang lọc
  /// theo ngày nên chỉ xoá đúng những dòng đang hiện).
  void removeAll(Iterable<String> ids) {
    final now = DateTime.now().toUtc();
    var changed = false;
    for (final id in ids) {
      final note = _byId[id];
      if (note == null || note.deleted) continue;
      note.deleted = true;
      note.updatedAt = now;
      note.dirty = true;
      changed = true;
    }
    if (changed) _afterLocalChange();
  }

  /// Kéo thả đổi thứ tự trong tab Current.
  /// [newIndex] là vị trí đích SAU khi đã lấy dòng đó ra khỏi list —
  /// đúng quy ước của `ReorderableListView.onReorderItem`.
  ///
  /// [groupId] khác `null` thì chỉ tính vị trí trong đúng group đang lọc —
  /// PHẢI khớp với danh sách UI đang hiện, không thì index lệch khỏi group.
  void reorder(int oldIndex, int newIndex, {String? groupId}) {
    final list = groupId == null
        ? current
        : current.where((n) => n.groupId == groupId).toList();
    if (oldIndex < 0 || oldIndex >= list.length) return;
    if (oldIndex == newIndex) return;

    final moved = list.removeAt(oldIndex);
    final prev = newIndex > 0 ? list[newIndex - 1] : null;
    final next = newIndex < list.length ? list[newIndex] : null;

    final double target;
    if (prev == null && next == null) {
      target = 0;
    } else if (prev == null) {
      target = next!.sort - _sortStep;
    } else if (next == null) {
      target = prev.sort + _sortStep;
    } else {
      target = (prev.sort + next.sort) / 2;
    }

    final tooTight = (prev != null && (target - prev.sort).abs() < _minGap) ||
        (next != null && (next.sort - target).abs() < _minGap);

    if (tooTight) {
      // Hết chỗ chèn giữa (kéo thả quá nhiều lần) → đánh số lại cả list.
      list.insert(newIndex, moved);
      _renumber(list);
      return;
    }

    moved.sort = target;
    _touch(moved);
  }

  // endregion

  // region Group mutations

  Group addGroup(String name) {
    final trimmed = name.trim();
    final group = Group.create(name: trimmed, sort: _maxGroupSort() + _sortStep);
    _groupsById[group.id] = group;
    _afterLocalChange();
    return group;
  }

  void renameGroup(String id, String name) {
    final group = _groupsById[id];
    if (group == null || group.deleted) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == group.name) return;
    group.name = trimmed;
    _touchGroup(group);
  }

  /// Xoá group — note của nó chuyển sang group còn lại đầu tiên, không mất
  /// dữ liệu. Không cho xoá nếu đây là group cuối cùng.
  void removeGroup(String id) {
    final group = _groupsById[id];
    if (group == null || group.deleted) return;
    final remaining = groups.where((g) => g.id != id).toList();
    if (remaining.isEmpty) return;

    final fallbackId = remaining.first.id;
    final now = DateTime.now().toUtc();
    for (final note in _byId.values) {
      if (note.deleted || note.groupId != id) continue;
      note.groupId = fallbackId;
      note.updatedAt = now;
      note.dirty = true;
    }

    group.deleted = true;
    group.updatedAt = now;
    group.dirty = true;
    _afterLocalChange();
  }

  double _maxGroupSort() {
    final sorts = _groupsById.values.where((g) => !g.deleted).map((g) => g.sort);
    if (sorts.isEmpty) return 0;
    return sorts.reduce(math.max);
  }

  void _touchGroup(Group group) {
    group.updatedAt = DateTime.now().toUtc();
    group.dirty = true;
    _afterLocalChange();
  }

  // endregion

  // region Sync helpers

  bool get hasDirty =>
      _byId.values.any((n) => n.dirty) || _groupsById.values.any((g) => g.dirty);

  List<Note> dirtyNotes() => _byId.values.where((n) => n.dirty).toList();

  List<Group> dirtyGroups() => _groupsById.values.where((g) => g.dirty).toList();

  /// Xoá cờ dirty cho các note đã push xong — nhưng chỉ khi chúng không bị sửa
  /// lại trong lúc request đang bay (so mốc `updatedAt` chụp lúc push).
  void markPushed(Map<String, DateTime> pushedStamps) {
    var changed = false;
    pushedStamps.forEach((id, stamp) {
      final note = _byId[id];
      if (note == null || !note.dirty) return;
      if (!note.updatedAt.isAfter(stamp)) {
        note.dirty = false;
        changed = true;
      }
    });
    if (changed) _scheduleSave();
  }

  /// Tương tự [markPushed] nhưng cho group.
  void markGroupsPushed(Map<String, DateTime> pushedStamps) {
    var changed = false;
    pushedStamps.forEach((id, stamp) {
      final group = _groupsById[id];
      if (group == null || !group.dirty) return;
      if (!group.updatedAt.isAfter(stamp)) {
        group.dirty = false;
        changed = true;
      }
    });
    if (changed) _scheduleSave();
  }

  /// Trộn row từ server theo last-write-wins trên `updatedAt`.
  /// Bằng nhau thì giữ bản local (bản local có thể đang dirty chờ push).
  bool mergeRemote(Iterable<Note> remote) {
    var changed = false;
    for (final incoming in remote) {
      final local = _byId[incoming.id];
      if (local == null || incoming.updatedAt.isAfter(local.updatedAt)) {
        _byId[incoming.id] = incoming;
        changed = true;
      }
    }
    if (changed) {
      _scheduleSave();
      notifyListeners();
    }
    return changed;
  }

  /// Tương tự [mergeRemote] nhưng cho group.
  bool mergeRemoteGroups(Iterable<Group> remote) {
    var changed = false;
    for (final incoming in remote) {
      final local = _groupsById[incoming.id];
      if (local == null || incoming.updatedAt.isAfter(local.updatedAt)) {
        _groupsById[incoming.id] = incoming;
        changed = true;
      }
    }
    if (changed) {
      _scheduleSave();
      notifyListeners();
    }
    return changed;
  }

  /// Cập nhật con trỏ pull — gọi sau khi đã merge xong cả note lẫn group của
  /// đợt pull hiện tại.
  void setLastPull(String cursor) {
    if (cursor == lastPull) return;
    lastPull = cursor;
    _scheduleSave();
  }

  // endregion

  // region Private

  double _maxCurrentSort({String? exceptId, String? groupId}) {
    final sorts = _byId.values
        .where((n) =>
            !n.deleted &&
            !n.isDone &&
            n.id != exceptId &&
            (groupId == null || n.groupId == groupId))
        .map((n) => n.sort);
    if (sorts.isEmpty) return 0;
    return sorts.reduce(math.max);
  }

  void _renumber(List<Note> ordered) {
    final now = DateTime.now().toUtc();
    for (var i = 0; i < ordered.length; i++) {
      ordered[i].sort = i * _sortStep;
      ordered[i].updatedAt = now;
      ordered[i].dirty = true;
    }
    _afterLocalChange();
  }

  /// Dọn tombstone đã sync và quá cũ để file local không phình mãi.
  void _pruneTombstones() {
    final cutoff = DateTime.now().toUtc().subtract(_tombstoneTtl);
    _byId.removeWhere(
      (_, n) => n.deleted && !n.dirty && n.updatedAt.isBefore(cutoff),
    );
    _groupsById.removeWhere(
      (_, g) => g.deleted && !g.dirty && g.updatedAt.isBefore(cutoff),
    );
  }

  void _touch(Note note) {
    note.updatedAt = DateTime.now().toUtc();
    note.dirty = true;
    _afterLocalChange();
  }

  void _afterLocalChange() {
    _scheduleSave();
    notifyListeners();
    onLocalChange?.call();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDebounce, flush);
  }

  // endregion

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
