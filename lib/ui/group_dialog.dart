import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../data/note_repo.dart';
import '../models/group.dart';
import 'confirm_dialog.dart';
import 'note_tile.dart';

/// Popup quản lý group: thêm, đổi tên, xoá. Đổi tên/xoá dùng chung
/// [InlineEditor]/[confirmDelete] cho khớp phong cách phần còn lại của app.
Future<void> showGroupManagerDialog(BuildContext context, NoteRepo repo) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black26,
    builder: (_) => _GroupManagerDialog(repo: repo),
  );
}

/// Popup chọn 1 group để chuyển việc vào — dùng cho cả chuyển 1 việc lẫn
/// chuyển nhiều việc cùng lúc (chọn nhiều). Trả về id group đã chọn, hoặc
/// `null` nếu bấm "Thôi" / bấm ra ngoài.
Future<String?> showGroupPickerDialog(
  BuildContext context,
  NoteRepo repo, {
  String? currentGroupId,
  String title = 'Chuyển vào nhóm',
}) {
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black26,
    builder: (context) {
      final paper = context.paper;
      final groups = repo.groups;
      return AlertDialog(
        backgroundColor: paper.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kPaperRadius),
        ),
        insetPadding: const EdgeInsets.all(12),
        title: Text(title, style: const TextStyle(fontSize: 15)),
        content: SizedBox(
          width: 280,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final g in groups)
                  InkWell(
                    onTap: () => Navigator.of(context).pop(g.id),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              g.name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13.5, color: paper.ink),
                            ),
                          ),
                          if (g.id == currentGroupId)
                            Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: paper.accent,
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Thôi'),
          ),
        ],
      );
    },
  );
}

class _GroupManagerDialog extends StatefulWidget {
  const _GroupManagerDialog({required this.repo});

  final NoteRepo repo;

  @override
  State<_GroupManagerDialog> createState() => _GroupManagerDialogState();
}

class _GroupManagerDialogState extends State<_GroupManagerDialog> {
  final _addController = TextEditingController();
  final _addFocus = FocusNode();
  String? _renamingId;

  @override
  void dispose() {
    _addController.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  void _submitAdd() {
    final text = _addController.text.trim();
    if (text.isEmpty) return;
    widget.repo.addGroup(text);
    _addController.clear();
    _addFocus.requestFocus();
  }

  Future<void> _confirmRemove(Group group) async {
    final ok = await confirmDelete(
      context,
      title: 'Xoá nhóm "${group.name}"?',
      message:
          'Việc trong nhóm này sẽ chuyển sang một nhóm còn lại, không bị mất.',
      confirmLabel: 'Xoá nhóm',
    );
    if (!ok || !mounted) return;
    widget.repo.removeGroup(group.id);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.repo,
      builder: (context, _) {
        final paper = context.paper;
        final groups = widget.repo.groups;
        return AlertDialog(
          backgroundColor: paper.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kPaperRadius),
          ),
          insetPadding: const EdgeInsets.all(12),
          title: const Text('Quản lý nhóm', style: TextStyle(fontSize: 15)),
          content: SizedBox(
            width: 300,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final g in groups) _groupRow(g, groups.length),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _addController,
                          focusNode: _addFocus,
                          style: const TextStyle(fontSize: 13),
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'Tên nhóm mới',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _submitAdd(),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        onPressed: _submitAdd,
                        icon: Icon(Icons.add_rounded, color: paper.accent),
                        tooltip: 'Thêm nhóm',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Đóng'),
            ),
          ],
        );
      },
    );
  }

  Widget _groupRow(Group group, int total) {
    final paper = context.paper;
    final canDelete = total > 1;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: _renamingId == group.id
                ? InlineEditor(
                    initial: group.name,
                    onCommit: (text) {
                      widget.repo.renameGroup(group.id, text);
                      if (mounted) setState(() => _renamingId = null);
                    },
                  )
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _renamingId = group.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        group.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: paper.ink),
                      ),
                    ),
                  ),
          ),
          IconButton(
            onPressed: canDelete ? () => _confirmRemove(group) : null,
            icon: Icon(
              Icons.delete_outline_rounded,
              size: 18,
              color: canDelete ? paper.danger : paper.line,
            ),
            tooltip: canDelete ? 'Xoá nhóm' : 'Phải còn ít nhất 1 nhóm',
          ),
        ],
      ),
    );
  }
}
