import 'package:flutter_test/flutter_test.dart';
import 'package:bf_stickytask/data/local_store.dart';
import 'package:bf_stickytask/data/note_repo.dart';
import 'package:bf_stickytask/models/group.dart';
import 'package:bf_stickytask/models/note.dart';

/// Store giả để test logic repo mà không đụng file thật.
class _MemoryStore extends LocalStore {
  @override
  Future<LocalSnapshot> load() async => const LocalSnapshot(notes: []);

  @override
  Future<void> save(List notes, List groups, {String? lastPull}) async {}
}

void main() {
  late NoteRepo repo;

  setUp(() async {
    repo = NoteRepo(_MemoryStore());
    await repo.load();
  });

  group('group mặc định', () {
    test('mở app lần đầu thì tự có 1 group mặc định', () {
      expect(repo.groups, hasLength(1));
      expect(repo.groups.single.id, Group.defaultId);
      expect(repo.groups.single.name, Group.defaultName);
    });

    test('note thêm không truyền groupId thì rơi vào group mặc định', () {
      final note = repo.add('việc chưa phân loại');
      expect(note.groupId, Group.defaultId);
    });
  });

  group('quản lý group', () {
    test('thêm group mới thì xuất hiện trong danh sách, dirty để chờ sync', () {
      final g = repo.addGroup('Công ty');
      expect(repo.groups.map((g) => g.name), ['Chung', 'Công ty']);
      expect(repo.dirtyGroups().map((g) => g.id), contains(g.id));
    });

    test('đổi tên group', () {
      final g = repo.addGroup('Cty');
      repo.renameGroup(g.id, 'Công ty');
      expect(repo.groups.firstWhere((x) => x.id == g.id).name, 'Công ty');
    });

    test('đổi tên rỗng thì bỏ qua, không xoá group', () {
      final g = repo.addGroup('Cty');
      repo.renameGroup(g.id, '   ');
      expect(repo.groups.firstWhere((x) => x.id == g.id).name, 'Cty');
    });

    test('xoá group thì note của nó chuyển sang group còn lại', () {
      final work = repo.addGroup('Công ty');
      final note = repo.add('họp team', groupId: work.id);

      repo.removeGroup(work.id);

      expect(repo.groups.map((g) => g.id), isNot(contains(work.id)));
      expect(repo.current.firstWhere((n) => n.id == note.id).groupId,
          Group.defaultId);
    });

    test('không cho xoá group cuối cùng', () {
      final onlyGroupId = repo.groups.single.id;
      repo.removeGroup(onlyGroupId);
      expect(repo.groups, hasLength(1));
      expect(repo.groups.single.id, onlyGroupId);
    });
  });

  group('lọc theo group', () {
    test('mỗi group giữ đúng danh sách việc của nó', () {
      final personal = repo.groups.single.id;
      final work = repo.addGroup('Công ty').id;

      repo.add('việc nhà', groupId: personal);
      repo.add('việc công ty 1', groupId: work);
      repo.add('việc công ty 2', groupId: work);

      final workNotes =
          repo.current.where((n) => n.groupId == work).map((n) => n.text);
      final personalNotes = repo.current
          .where((n) => n.groupId == personal)
          .map((n) => n.text);

      expect(workNotes, ['việc công ty 1', 'việc công ty 2']);
      expect(personalNotes, ['việc nhà']);
    });

    test('reorder với groupId chỉ đổi thứ tự trong đúng group đó', () {
      final personal = repo.groups.single.id;
      final work = repo.addGroup('Công ty').id;

      repo.add('p1', groupId: personal);
      repo.add('w1', groupId: work);
      repo.add('p2', groupId: personal);
      repo.add('w2', groupId: work);

      // Trong danh sách lọc theo "work": ['w1', 'w2'] → kéo w2 lên đầu.
      repo.reorder(1, 0, groupId: work);

      final workOrder =
          repo.current.where((n) => n.groupId == work).map((n) => n.text);
      final personalOrder =
          repo.current.where((n) => n.groupId == personal).map((n) => n.text);

      expect(workOrder, ['w2', 'w1']);
      // Group kia không bị đụng tới.
      expect(personalOrder, ['p1', 'p2']);
    });

    test('done trong 1 group không ảnh hưởng group khác', () {
      final personal = repo.groups.single.id;
      final work = repo.addGroup('Công ty').id;
      final w1 = repo.add('w1', groupId: work);
      repo.add('p1', groupId: personal);

      repo.setDone(w1.id, true);

      expect(repo.history.single.groupId, work);
      expect(repo.current.map((n) => n.groupId), [personal]);
    });
  });

  group('trạng thái đang làm', () {
    test('đánh dấu rồi bỏ đánh dấu đang làm', () {
      final note = repo.add('việc A');
      expect(note.isInProgress, isFalse);

      repo.setInProgress(note.id, true);
      expect(repo.current.single.isInProgress, isTrue);
      expect(repo.current.single.isDone, isFalse);

      repo.setInProgress(note.id, false);
      expect(repo.current.single.isInProgress, isFalse);
    });

    test('done xong thì không đổi được sang đang làm nữa', () {
      final note = repo.add('việc A');
      repo.setDone(note.id, true);

      repo.setInProgress(note.id, true);

      expect(repo.history.single.isInProgress, isFalse);
      expect(repo.history.single.isDone, isTrue);
    });

    test('trạng thái được serialize đúng qua toLocalJson/fromLocalJson', () {
      final note = repo.add('việc A');
      repo.setInProgress(note.id, true);

      final restored = Note.fromLocalJson(repo.current.single.toLocalJson());
      expect(restored.isInProgress, isTrue);
      expect(restored.groupId, note.groupId);
    });
  });
}
