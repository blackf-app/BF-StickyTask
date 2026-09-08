import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase/supabase.dart';

import '../models/note.dart';
import 'note_repo.dart';
import 'sync_config.dart';

enum SyncStatus {
  /// Chưa nhập URL + publishable key → app chạy thuần local.
  notConfigured,

  /// Đã đồng bộ xong, đang nghe realtime.
  idle,

  syncing,

  /// Không gọi được server (mất mạng / sai key / RLS chặn) — thay đổi vẫn
  /// nằm trong hàng chờ và sẽ tự đẩy lại.
  offline,
}

/// Đồng bộ 2 chiều với Supabase: push các note dirty, pull theo con trỏ
/// `updated_at`, và nghe realtime để máy khác vừa tick là máy này đổi theo.
///
/// KHÔNG có đăng nhập. Client dùng publishable key và bảng `notes` mở cho role
/// `anon` (xem `supabase/schema.sql`), nên mọi máy nhập cùng URL + key là thấy
/// cùng một tập note.
class SyncService extends ChangeNotifier {
  SyncService(this._repo, {SyncConfigStore? store})
      : _store = store ?? SyncConfigStore() {
    _repo.onLocalChange = _onLocalChange;
  }

  static const String _table = 'notes';
  static const Duration _pullInterval = Duration(seconds: 60);
  static const Duration _pushDebounce = Duration(milliseconds: 800);

  final NoteRepo _repo;
  final SyncConfigStore _store;

  SyncStatus _status = SyncStatus.notConfigured;
  String? _error;
  DateTime? _lastSyncAt;
  SyncConfig _config = SyncConfig.empty;

  SupabaseClient? _client;
  Timer? _pushTimer;
  Timer? _pullTimer;
  RealtimeChannel? _channel;
  bool _busy = false;
  bool _disposed = false;

  SyncStatus get status => _status;
  String? get error => _error;
  DateTime? get lastSyncAt => _lastSyncAt;
  SyncConfig get config => _config;
  bool get configured => _client != null;
  bool get hasPendingChanges => _repo.hasDirty;

  /// Nạp cấu hình đã lưu rồi kết nối. Gọi một lần lúc app khởi động.
  Future<void> start() async {
    await _apply(await _store.load(), persist: false);
  }

  /// Lưu cấu hình mới rồi kết nối lại ngay. `null` = xoá cấu hình, về local-only.
  Future<void> applyConfig(SyncConfig? config) async {
    if (config == null) {
      await _store.clear();
      await _apply(SyncConfig.empty, persist: false);
      return;
    }
    await _apply(config, persist: true);
  }

  /// Push rồi pull. Gọi được thoải mái — có cờ chống chạy trùng.
  Future<void> syncNow() async {
    final db = _client;
    if (db == null || _busy) return;
    _busy = true;
    _set(SyncStatus.syncing);
    var ok = false;
    try {
      await _push(db);
      await _pull(db);
      _lastSyncAt = DateTime.now();
      _error = null;
      ok = true;
      _set(SyncStatus.idle);
    } catch (e) {
      _error = _shortError(e);
      _set(SyncStatus.offline);
    } finally {
      _busy = false;
    }

    // Realtime tự phục hồi: lần sync đầu mà fail (mất mạng, hoặc chưa chạy
    // schema.sql) thì channel không được mở. Mở ngay khi sync thông trở lại,
    // thay vì để realtime tắt đến khi khởi động lại app.
    if (ok && _channel == null && !_disposed && _client == db) {
      await _openChannel();
    }
  }

  Future<void> _apply(SyncConfig config, {required bool persist}) async {
    _config = config;
    if (persist) await _store.save(config);

    await _teardown();
    if (config.isEmpty || config.problem != null) {
      _error = config.isEmpty ? null : config.problem;
      _set(SyncStatus.notConfigured);
      return;
    }

    try {
      _client = SupabaseClient(
        config.url,
        config.publishableKey,
        // App không đăng nhập nên GoTrue chẳng có gì để refresh. Mặc định
        // `autoRefreshToken: true` dựng một periodic timer 10s sống suốt đời
        // client — tắt đi cho đỡ tốn.
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
    } catch (e) {
      _error = _shortError(e);
      _set(SyncStatus.offline);
      return;
    }

    _pullTimer = Timer.periodic(_pullInterval, (_) => syncNow());
    // Realtime do syncNow mở sau khi lần sync đầu thông — sai key thì khỏi
    // dựng socket vô ích.
    await syncNow();
  }

  Future<void> _teardown() async {
    _pullTimer?.cancel();
    _pullTimer = null;
    _pushTimer?.cancel();
    _pushTimer = null;
    await _closeChannel();
    final old = _client;
    _client = null;
    if (old != null) {
      try {
        await old.dispose();
      } catch (_) {
        // Client chưa mở kết nối nào thì dispose có thể ném — không quan trọng.
      }
    }
  }

  Future<void> _push(SupabaseClient db) async {
    final dirty = _repo.dirtyNotes();
    if (dirty.isEmpty) return;

    // Chụp mốc thời gian trước khi gửi để biết note nào bị sửa lại giữa đường.
    final stamps = {for (final n in dirty) n.id: n.updatedAt};
    await db.from(_table).upsert(
          dirty.map((n) => n.toRow()).toList(),
          onConflict: 'id',
        );
    _repo.markPushed(stamps);
  }

  Future<void> _pull(SupabaseClient db) async {
    final since = _repo.lastPull;
    final builder = db.from(_table).select();
    final rows = since == null
        ? await builder
        : await builder.gte('updated_at', since);

    final notes = rows.map(Note.fromRow).toList();
    if (notes.isEmpty) return;

    var cursor = _repo.lastPull;
    for (final note in notes) {
      final iso = note.updatedAt.toIso8601String();
      if (cursor == null || iso.compareTo(cursor) > 0) cursor = iso;
    }
    _repo.mergeRemote(notes, newLastPull: cursor);
  }

  Future<void> _openChannel() async {
    final db = _client;
    if (db == null) return;
    await _closeChannel();
    _channel = db.channel('public:$_table')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: _table,
        callback: (payload) {
          final record = payload.newRecord;
          if (record.isEmpty) return;
          try {
            _repo.mergeRemote([Note.fromRow(record)]);
          } catch (_) {
            // Row lạ/thiếu field thì bỏ qua, lần pull sau sẽ lấy lại.
          }
        },
      )
      ..subscribe();
  }

  Future<void> _closeChannel() async {
    final channel = _channel;
    final db = _client;
    _channel = null;
    if (channel != null && db != null) {
      try {
        await db.removeChannel(channel);
      } catch (_) {
        // Socket đã đóng sẵn.
      }
    }
  }

  void _onLocalChange() {
    if (_client == null) return;
    _pushTimer?.cancel();
    _pushTimer = Timer(_pushDebounce, syncNow);
  }

  void _set(SyncStatus status) {
    _status = status;
    if (!_disposed) notifyListeners();
  }

  /// Link SQL Editor của đúng project đang cấu hình — để thông báo lỗi bấm được
  /// ngay chứ không phải tự đi mò trong dashboard.
  String get _sqlEditorUrl =>
      'https://supabase.com/dashboard/project/${_config.projectRef}/sql/new';

  String _shortError(Object e) {
    if (e is PostgrestException) {
      // RLS chặn / thiếu bảng thì message của Postgres khá tối nghĩa — nói rõ
      // phải làm gì, kèm link SQL Editor của đúng project đang cấu hình.
      if (e.code == '42501' || e.message.contains('row-level security')) {
        return 'Bảng notes chặn ghi (RLS) — schema chưa được migrate.\n'
            'Dán supabase/schema.sql vào SQL Editor rồi Run:\n'
            '$_sqlEditorUrl';
      }
      if (e.code == '23503' || e.message.contains('foreign key')) {
        return 'Bảng notes còn ràng buộc user_id → auth.users (schema cũ).\n'
            'Dán supabase/schema.sql vào SQL Editor rồi Run:\n'
            '$_sqlEditorUrl';
      }
      if (e.code == 'PGRST205' || e.message.contains('does not exist')) {
        return 'Project ${_config.projectRef} chưa có bảng notes.\n'
            'Dán supabase/schema.sql vào SQL Editor rồi Run:\n'
            '$_sqlEditorUrl';
      }
      return e.message;
    }
    final text = e.toString();
    return text.length > 160 ? '${text.substring(0, 160)}…' : text;
  }

  @override
  void dispose() {
    if (_disposed) return; // idempotent: gọi 2 lần không nổ
    _disposed = true;
    _repo.onLocalChange = null;
    _teardown();
    super.dispose();
  }
}
