import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bf_stickytask/app/settings_controller.dart';
import 'package:bf_stickytask/data/local_store.dart';
import 'package:bf_stickytask/data/note_repo.dart';
import 'package:bf_stickytask/models/note.dart';

/// Store giả để test logic repo mà không đụng file thật.
class _MemoryStore extends LocalStore {
  List<dynamic> saved = [];

  @override
  Future<LocalSnapshot> load() async => const LocalSnapshot(notes: []);

  @override
  Future<void> save(List notes, {String? lastPull}) async => saved = notes;
}

void main() {
  late NoteRepo repo;

  setUp(() async {
    repo = NoteRepo(_MemoryStore());
    await repo.load();
  });

  test('thêm note thì nằm ở tab Current theo đúng thứ tự thêm', () {
    repo.add('một');
    repo.add('hai');
    repo.add('ba');
    expect(repo.current.map((n) => n.text), ['một', 'hai', 'ba']);
    expect(repo.history, isEmpty);
  });

  test('tick done thì dòng chuyển sang History và có doneAt', () {
    final note = repo.add('việc A');
    repo.setDone(note.id, true);

    expect(repo.current, isEmpty);
    expect(repo.history.single.text, 'việc A');
    expect(repo.history.single.doneAt, isNotNull);
  });

  test('restore từ History thì về cuối danh sách Current', () {
    final a = repo.add('a');
    repo.add('b');
    repo.setDone(a.id, true);
    repo.setDone(a.id, false);

    expect(repo.current.map((n) => n.text), ['b', 'a']);
  });

  test('reorder kéo dòng cuối lên đầu', () {
    repo.add('1');
    repo.add('2');
    repo.add('3');

    // onReorderItem: newIndex là vị trí đích sau khi đã lấy item ra.
    repo.reorder(2, 0);
    expect(repo.current.map((n) => n.text), ['3', '1', '2']);

    repo.reorder(0, 1);
    expect(repo.current.map((n) => n.text), ['1', '3', '2']);
  });

  test('xoá là tombstone, không lộ ra 2 tab', () {
    final note = repo.add('xoá tôi');
    repo.remove(note.id);

    expect(repo.current, isEmpty);
    expect(repo.history, isEmpty);
    expect(repo.dirtyNotes().single.deleted, isTrue);
  });

  test('mergeRemote lấy bản mới hơn theo updatedAt', () {
    final note = repo.add('bản local');
    final remote = Note.fromRow({
      'id': note.id,
      'text': 'bản server mới hơn',
      'status': 'current',
      'sort': note.sort,
      'created_at': note.createdAt.toIso8601String(),
      'updated_at':
          note.updatedAt.add(const Duration(seconds: 5)).toIso8601String(),
      'deleted': false,
    });

    expect(repo.mergeRemote([remote]), isTrue);
    expect(repo.current.single.text, 'bản server mới hơn');
  });

  test('cycleThemeMode xoay vòng system → light → dark → system', () async {
    final settings = SettingsController();
    expect(settings.themeMode, ThemeMode.system);

    await settings.cycleThemeMode();
    expect(settings.themeMode, ThemeMode.light);

    await settings.cycleThemeMode();
    expect(settings.themeMode, ThemeMode.dark);

    await settings.cycleThemeMode();
    expect(settings.themeMode, ThemeMode.system);
  });
}
