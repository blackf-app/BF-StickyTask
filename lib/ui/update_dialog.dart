import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/theme.dart';
import '../data/update_service.dart';

/// Popup cập nhật: version đang dùng, version mới nhất, release notes, và nút
/// mở trang release trên browser.
///
/// [checkOnOpen] = true khi user tự bấm nút "Kiểm tra cập nhật" (kiểm lại ngay
/// lúc mở), = false khi popup bật tự động lúc mở app (vừa kiểm xong rồi).
Future<void> showUpdateDialog(
  BuildContext context,
  UpdateService update, {
  bool checkOnOpen = false,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black26,
    builder: (_) => _UpdateDialog(update: update, checkOnOpen: checkOnOpen),
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.update, required this.checkOnOpen});

  final UpdateService update;
  final bool checkOnOpen;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  String? _launchError;

  @override
  void initState() {
    super.initState();
    if (widget.checkOnOpen) {
      // Sau frame đầu: check() gọi notifyListeners() ngay, setState trong lúc
      // build là ném lỗi.
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.update.check());
    }
  }

  Future<void> _openReleasePage() async {
    setState(() => _launchError = null);
    final url = Uri.parse(widget.update.releasePageUrl);
    try {
      final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!ok) throw Exception('browser không mở');
    } catch (_) {
      if (!mounted) return;
      // Mở không được thì đưa link ra để copy tay — SelectableText bên dưới.
      setState(() => _launchError = widget.update.releasePageUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.update,
      builder: (context, _) {
        final update = widget.update;
        final paper = context.paper;
        final busy = update.status == UpdateStatus.checking;

        return AlertDialog(
          backgroundColor: paper.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kPaperRadius),
          ),
          insetPadding: const EdgeInsets.all(12),
          contentPadding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
          title: const Text('Cập nhật', style: TextStyle(fontSize: 15)),
          content: SizedBox(
            width: 320,
            child: SingleChildScrollView(child: _body(update)),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Đóng'),
            ),
            if (update.updateAvailable)
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        await update.skipLatest();
                        if (context.mounted) Navigator.of(context).pop();
                      },
                child: Text(
                  'Bỏ qua bản này',
                  style: TextStyle(fontSize: 12.5, color: paper.inkFaint),
                ),
              ),
            if (update.updateAvailable)
              FilledButton(
                onPressed: busy ? null : _openReleasePage,
                child: const Text('Tải bản mới'),
              )
            else
              OutlinedButton.icon(
                onPressed: busy ? null : update.check,
                icon: const Icon(Icons.refresh_rounded, size: 15),
                label: Text(busy ? 'Đang kiểm…' : 'Kiểm tra cập nhật'),
              ),
          ],
        );
      },
    );
  }

  Widget _body(UpdateService update) {
    final paper = context.paper;
    final latest = update.latest;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.sticky_note_2_outlined, size: 15, color: paper.inkSoft),
            const SizedBox(width: 6),
            Text(
              'Đang dùng: '
              '${update.currentVersion.isEmpty ? '—' : update.currentVersion}',
              style: TextStyle(fontSize: 12.5, color: paper.ink),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          switch (update.status) {
            UpdateStatus.idle => 'Chưa kiểm lần nào.',
            UpdateStatus.checking => 'Đang kiểm bản mới…',
            UpdateStatus.upToDate => 'Đang là bản mới nhất.',
            UpdateStatus.available => 'Có bản mới: ${latest?.version ?? ''}',
            UpdateStatus.error => update.error ?? 'Không kiểm được bản mới.',
          },
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: update.updateAvailable
                ? FontWeight.w600
                : FontWeight.normal,
            color: switch (update.status) {
              UpdateStatus.error => paper.danger,
              UpdateStatus.available => paper.accent,
              _ => paper.inkSoft,
            },
          ),
        ),
        if (update.updateAvailable &&
            latest != null &&
            latest.notes.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Có gì mới',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: paper.inkSoft,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 160),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: paper.line.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              child: Text(
                latest.notes,
                style: TextStyle(fontSize: 12, height: 1.35, color: paper.ink),
              ),
            ),
          ),
        ],
        if (update.updateAvailable) ...[
          const SizedBox(height: 10),
          Text(
            'Bấm "Tải bản mới" để mở trang release trên browser rồi tải bản '
            'đúng máy của bạn. App không tự cài đè.',
            style: TextStyle(fontSize: 11, color: paper.inkFaint),
          ),
        ],
        if (_launchError != null) ...[
          const SizedBox(height: 10),
          Text(
            'Không mở được browser. Link tải:',
            style: TextStyle(fontSize: 11.5, color: paper.danger),
          ),
          const SizedBox(height: 2),
          SelectableText(
            _launchError!,
            style: TextStyle(fontSize: 11.5, color: paper.inkSoft),
          ),
        ],
      ],
    );
  }
}
