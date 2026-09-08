import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../data/sync_config.dart';
import '../data/sync_service.dart';

/// Popup đồng bộ: nhập Supabase URL + publishable key, xem trạng thái, sync tay.
/// Không có đăng nhập — key là toàn bộ thứ cần để đồng bộ.
Future<void> showSyncDialog(BuildContext context, SyncService sync) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black26,
    builder: (_) => _SyncDialog(sync: sync),
  );
}

class _SyncDialog extends StatefulWidget {
  const _SyncDialog({required this.sync});

  final SyncService sync;

  @override
  State<_SyncDialog> createState() => _SyncDialogState();
}

class _SyncDialogState extends State<_SyncDialog> {
  late final TextEditingController _url;
  late final TextEditingController _key;

  bool _editing = false;
  bool _busy = false;
  bool _showKey = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    // Cấu hình đang dùng; nếu rỗng (lần đầu, hoặc vừa bấm Ngắt) thì mồi form
    // bằng giá trị trong env.dart để đỡ phải đi tìm lại key.
    final config =
        widget.sync.config.isEmpty ? SyncConfig.fromEnv() : widget.sync.config;
    _url = TextEditingController(text: config.url);
    _key = TextEditingController(text: config.publishableKey);
    // Chưa cấu hình thì mở thẳng form, đỡ phải bấm thêm một nút.
    _editing = !widget.sync.configured;
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final config = SyncConfig.sanitized(url: _url.text, key: _key.text);
    final problem = config.problem;
    if (problem != null) {
      setState(() => _message = problem);
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    await widget.sync.applyConfig(config);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _editing = false;
      _message = widget.sync.status == SyncStatus.offline
          ? widget.sync.error
          : null;
    });
  }

  Future<void> _disconnect() async {
    setState(() => _busy = true);
    await widget.sync.applyConfig(null);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _editing = true;
      _message = null;
      _url.text = '';
      _key.text = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.sync,
      builder: (context, _) {
        final sync = widget.sync;
        final paper = context.paper;
        return AlertDialog(
          backgroundColor: paper.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kPaperRadius),
          ),
          insetPadding: const EdgeInsets.all(12),
          contentPadding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
          title: const Text('Đồng bộ', style: TextStyle(fontSize: 15)),
          content: SizedBox(
            width: 320,
            child: SingleChildScrollView(
              child: _editing ? _configForm() : _statusBody(sync),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Đóng'),
            ),
            if (_editing)
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy ? 'Đang kết nối…' : 'Lưu & đồng bộ'),
              ),
          ],
        );
      },
    );
  }

  Widget _configForm() {
    final paper = context.paper;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Nhập Supabase URL + publishable key để đồng bộ giữa các máy. '
          'Máy nào nhập cùng cặp này là thấy cùng một tập note.',
          style: TextStyle(fontSize: 12.5, color: paper.inkSoft),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _url,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Supabase URL',
            hintText: 'https://<project-ref>.supabase.co',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          style: const TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _key,
          obscureText: !_showKey,
          onSubmitted: (_) => _save(),
          decoration: InputDecoration(
            labelText: 'Publishable key',
            hintText: 'sb_publishable_…',
            isDense: true,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(
                _showKey
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 17,
              ),
              tooltip: _showKey ? 'Ẩn key' : 'Hiện key',
              onPressed: () => setState(() => _showKey = !_showKey),
            ),
          ),
          style: const TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 10),
        Text(
          'Dashboard → Project Settings → API keys. Lấy publishable key '
          '(sb_publishable_…), KHÔNG phải secret key.\n'
          'Bảng notes phải được tạo trước bằng supabase/schema.sql.',
          style: TextStyle(fontSize: 11, color: paper.inkFaint),
        ),
        if (_message != null) ...[
          const SizedBox(height: 10),
          Text(
            _message!,
            style: TextStyle(fontSize: 11.5, color: paper.danger),
          ),
        ],
      ],
    );
  }

  Widget _statusBody(SyncService sync) {
    final paper = context.paper;
    final last = sync.lastSyncAt;
    final lastText = last == null
        ? 'chưa đồng bộ lần nào'
        : 'lần cuối ${last.hour.toString().padLeft(2, '0')}:'
            '${last.minute.toString().padLeft(2, '0')}:'
            '${last.second.toString().padLeft(2, '0')}';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.cloud_outlined, size: 15, color: paper.inkSoft),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                sync.config.projectRef.isEmpty ? '—' : sync.config.projectRef,
                style: TextStyle(fontSize: 12.5, color: paper.ink),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // SelectableText để copy được link SQL Editor trong thông báo lỗi.
        SelectableText(
          switch (sync.status) {
            SyncStatus.syncing => 'Đang đồng bộ…',
            SyncStatus.offline => 'Không kết nối được — ${sync.error ?? ''}',
            SyncStatus.notConfigured => 'Chưa cấu hình đồng bộ.',
            SyncStatus.idle => 'Đã đồng bộ ($lastText)',
          },
          style: TextStyle(
            fontSize: 12,
            color: sync.status == SyncStatus.offline
                ? paper.danger
                : paper.inkSoft,
          ),
        ),
        if (sync.hasPendingChanges) ...[
          const SizedBox(height: 4),
          Text(
            'Có thay đổi đang chờ đẩy lên.',
            style: TextStyle(fontSize: 11.5, color: paper.accent),
          ),
        ],
        const SizedBox(height: 12),
        // Wrap chứ không Row: 3 action + dialog rộng 320 là tràn ngang trên
        // text scale lớn. Wrap tự xuống dòng thay vì overflow.
        Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: sync.status == SyncStatus.syncing || _busy
                  ? null
                  : sync.syncNow,
              icon: const Icon(Icons.sync, size: 15),
              label: const Text('Đồng bộ ngay'),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _editing = true;
                        _message = null;
                      }),
              child: const Text('Sửa'),
            ),
            TextButton(
              onPressed: _busy ? null : _disconnect,
              child: Text('Ngắt', style: TextStyle(color: paper.danger)),
            ),
          ],
        ),
      ],
    );
  }
}
