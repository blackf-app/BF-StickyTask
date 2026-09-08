import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/note.dart';
import 'local_store.dart';

/// Nguồn sự thật duy nhất cho danh sách note. Mọi thao tác đều ghi vào bộ nhớ
/// + file local ngay lập tức (offline-first), sync đẩy lên server sau.
class NoteRepo extends ChangeNotifier {
  NoteRepo(this._store);

  static const double _sortStep = 1;
  static const double _minGap = 1e-6;
  static const Duration _saveDebounce = Duration(milliseconds: 200);
  static const Duration _tombstoneTtl = Duration(days: 30);

  final LocalStore _store;
  final Map<String, Note> _byId = {};

  /// Mốc `updated_at` lớn nhất đã pull về, dùng làm con trỏ cho lần pull sau.
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

  // region Load / Save

  Future<void> load() async {
    final snapshot = await _store.load();
    _byId
      ..clear()
      ..addEntries(snapshot.notes.map((n) => MapEntry(n.id, n)));
    lastPull = snapshot.lastPull;
    _loaded = true;
    _pruneTombstones();
    notifyListeners();
  }

  /// Ghi ngay ra file, dùng khi app bị pause/close.
  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (!_loaded) return;
    await _store.save(_byId.values.toList(), lastPull: lastPull);
  }

  // endregion

  // region Mutations

  Note add(String text) {
    final trimmed = text.trim();
    final note = Note.create(text: trimmed, sort: _maxCurrentSort() + _sortStep);
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
      // Restore thì xếp xuống cuối danh sách Current.
      note.sort = _maxCurrentSort(exceptId: note.id) + _sortStep;
    }
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
  void reorder(int oldIndex, int newIndex) {
    final list = current;
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

  // region Sync helpers

  bool get hasDirty => _byId.values.any((n) => n.dirty);

  List<Note> dirtyNotes() => _byId.values.where((n) => n.dirty).toList();

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

  /// Trộn row từ server theo last-write-wins trên `updatedAt`.
  /// Bằng nhau thì giữ bản local (bản local có thể đang dirty chờ push).
  bool mergeRemote(Iterable<Note> remote, {String? newLastPull}) {
    var changed = false;
    for (final incoming in remote) {
      final local = _byId[incoming.id];
      if (local == null || incoming.updatedAt.isAfter(local.updatedAt)) {
        _byId[incoming.id] = incoming;
        changed = true;
      }
    }
    if (newLastPull != null && newLastPull != lastPull) {
      lastPull = newLastPull;
      _scheduleSave();
    }
    if (changed) {
      _scheduleSave();
      notifyListeners();
    }
    return changed;
  }

  // endregion

  // region Private

  double _maxCurrentSort({String? exceptId}) {
    final sorts = _byId.values
        .where((n) => !n.deleted && !n.isDone && n.id != exceptId)
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
