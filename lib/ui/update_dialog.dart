import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/theme.dart';
import '../data/update_service.dart';
import '../data/updater.dart';

/// Popup cập nhật: version đang dùng, version mới nhất, release notes, và nút
/// **Cập nhật ngay** — tải về rồi cài luôn, không mở browser.
///
/// Mở trang release chỉ còn là đường lùi: nền tảng không tự cài được (Linux),
/// release không có asset cho máy này, hoặc cài lỗi.
///
/// [checkOnOpen] = true khi user tự bấm nút "Kiểm tra cập nhật" (kiểm lại ngay
/// lúc mở), = false khi popup bật tự động lúc mở app (vừa kiểm xong rồi).
Future<void> showUpdateDialog(
  BuildContext context,
  UpdateService update,
  Updater updater, {
  bool checkOnOpen = false,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black26,
    // Đang tải/đang cài thì bấm ra ngoài không đóng được: đóng giữa lúc cài là
    // user không còn chỗ nào thấy tiến trình hay lỗi.
    barrierDismissible: !updater.busy,
    builder: (_) => _UpdateDialog(
      update: update,
      updater: updater,
      checkOnOpen: checkOnOpen,
    ),
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({
    required this.update,
    required this.updater,
    required this.checkOnOpen,
  });

  final UpdateService update;
  final Updater updater;
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

  /// Có thể tự cài bản mới này không. `false` → chỉ còn nút mở trang release.
  bool get _canAutoInstall {
    final latest = widget.update.latest;
    return latest != null &&
        widget.updater.supported &&
        widget.updater.canInstall(latest);
  }

  Future<void> _install() async {
    final latest = widget.update.latest;
    if (latest == null) return;
    await widget.updater.run(latest);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // Một listenable cho mỗi nửa: UpdateService đổi khi kiểm xong, Updater
      // đổi mỗi chunk tải về.
      listenable: Listenable.merge([widget.update, widget.updater]),
      builder: (context, _) {
        final update = widget.update;
        final updater = widget.updater;
        final paper = context.paper;
        final checking = update.status == UpdateStatus.checking;
        final busy = checking || updater.busy;

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
            child: SingleChildScrollView(child: _body(update, updater)),
          ),
          actions: _actions(update, updater, busy),
        );
      },
    );
  }

  List<Widget> _actions(UpdateService update, Updater updater, bool busy) {
    final paper = context.paper;

    // Đang tải: chỉ còn nút Huỷ. Đã bàn giao cho script/hệ thống: không còn
    // nút nào có nghĩa nữa.
    if (updater.phase == UpdatePhase.downloading ||
        updater.phase == UpdatePhase.verifying) {
      return [
        TextButton(
          onPressed: () {
            updater.cancel();
            Navigator.of(context).pop();
          },
          child: const Text('Huỷ'),
        ),
      ];
    }
    if (updater.phase == UpdatePhase.installing ||
        updater.phase == UpdatePhase.handedOff) {
      return const [SizedBox.shrink()];
    }

    return [
      TextButton(
        onPressed: busy ? null : () => Navigator.of(context).pop(),
        child: const Text('Đóng'),
      ),
      if (updater.phase == UpdatePhase.error)
        // Lỗi tự cài thì vẫn còn đường tải tay — đừng để user tắc ở đây.
        TextButton(
          onPressed: _openReleasePage,
          child: Text(
            'Mở trang tải',
            style: TextStyle(fontSize: 12.5, color: paper.inkFaint),
          ),
        )
      else if (update.updateAvailable)
        TextButton(
          onPressed: busy
              ? null
              : () async {
                  await update.skipLatest();
                  if (mounted) Navigator.of(context).pop();
                },
          child: Text(
            'Bỏ qua bản này',
            style: TextStyle(fontSize: 12.5, color: paper.inkFaint),
          ),
        ),
      if (update.updateAvailable && updater.phase == UpdatePhase.error)
        FilledButton(
          onPressed: () {
            updater.reset();
            _install();
          },
          child: const Text('Thử lại'),
        )
      else if (update.updateAvailable && _canAutoInstall)
        FilledButton(
          onPressed: busy ? null : _install,
          child: const Text('Cập nhật ngay'),
        )
      else if (update.updateAvailable)
        // Không tự cài được nền tảng/asset này.
        FilledButton(
          onPressed: busy ? null : _openReleasePage,
          child: const Text('Mở trang tải'),
        )
      else
        OutlinedButton.icon(
          onPressed: busy ? null : update.check,
          icon: const Icon(Icons.refresh_rounded, size: 15),
          label: Text(busy ? 'Đang kiểm…' : 'Kiểm tra cập nhật'),
        ),
    ];
  }

  Widget _body(UpdateService update, Updater updater) {
    final paper = context.paper;
    final latest = update.latest;
    final installing = updater.phase != UpdatePhase.idle;

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

        // Release notes: nhường chỗ khi đã bắt đầu cài, lúc đó chỉ progress mới
        // đáng đọc.
        if (!installing &&
            update.updateAvailable &&
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

        if (installing) _progress(updater),

        if (!installing && update.updateAvailable) ...[
          const SizedBox(height: 10),
          Text(
            _canAutoInstall
                ? 'Bấm "Cập nhật ngay": app tự tải và tự cài. '
                    '${updater.handoffMessage}'
                : 'Nền tảng này chưa tự cài được — mở trang release để tải '
                    'bản đúng máy của bạn.',
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

  Widget _progress(Updater updater) {
    final paper = context.paper;
    final error = updater.phase == UpdatePhase.error;

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            switch (updater.phase) {
              UpdatePhase.downloading => updater.total > 0
                  ? 'Đang tải… ${formatBytes(updater.received)}'
                      ' / ${formatBytes(updater.total)}'
                  : 'Đang tải… ${formatBytes(updater.received)}',
              UpdatePhase.verifying => 'Đang kiểm file tải về…',
              UpdatePhase.installing => 'Đang cài…',
              UpdatePhase.handedOff => updater.handoffMessage,
              UpdatePhase.error => updater.error ?? 'Không cài được bản mới.',
              UpdatePhase.idle => '',
            },
            style: TextStyle(
              fontSize: 12,
              color: error ? paper.danger : paper.inkSoft,
            ),
          ),
          if (!error) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                // null = thanh chạy vô định: giai đoạn cài không đo được tiến
                // trình, và có server không trả Content-Length.
                value: updater.phase == UpdatePhase.downloading
                    ? updater.progress
                    : null,
                minHeight: 5,
                backgroundColor: paper.line,
                color: paper.accent,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
