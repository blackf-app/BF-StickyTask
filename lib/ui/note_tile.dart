import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../app/time_ago.dart';
import '../models/note.dart';

bool get _isTouch => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Một dòng trong tab Current: tick done, sửa inline, xoá, kéo đổi thứ tự.
class CurrentNoteTile extends StatefulWidget {
  const CurrentNoteTile({
    super.key,
    required this.note,
    required this.index,
    required this.editing,
    required this.onToggleDone,
    required this.onStartEdit,
    required this.onCommitEdit,
    required this.onDelete,
  });

  final Note note;
  final int index;
  final bool editing;
  final VoidCallback onToggleDone;
  final VoidCallback onStartEdit;
  final ValueChanged<String> onCommitEdit;
  final VoidCallback onDelete;

  @override
  State<CurrentNoteTile> createState() => _CurrentNoteTileState();
}

class _CurrentNoteTileState extends State<CurrentNoteTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final paper = context.paper;
    final showActions = _hover || _isTouch || widget.editing;
    final raised = _hover || widget.editing;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: raised ? paper.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            _Checkbox(done: false, onTap: widget.onToggleDone),
            const SizedBox(width: 10),
            Expanded(
              child: widget.editing
                  ? InlineEditor(
                      initial: widget.note.text,
                      onCommit: widget.onCommitEdit,
                    )
                  : GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onStartEdit,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text(
                          widget.note.text,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.3,
                            color: paper.ink,
                          ),
                        ),
                      ),
                    ),
            ),
            _TileAction(
              icon: Icons.close_rounded,
              tooltip: 'Xoá',
              visible: showActions,
              onTap: widget.onDelete,
            ),
            ReorderableDragStartListener(
              index: widget.index,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Icon(
                  Icons.drag_indicator_rounded,
                  size: 16,
                  color: showActions ? paper.inkFaint : paper.line,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Một dòng trong tab History: xem lại, restore về Current, hoặc xoá hẳn.
class HistoryNoteTile extends StatefulWidget {
  const HistoryNoteTile({
    super.key,
    required this.note,
    required this.onRestore,
    required this.onDelete,
  });

  final Note note;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  State<HistoryNoteTile> createState() => _HistoryNoteTileState();
}

class _HistoryNoteTileState extends State<HistoryNoteTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final paper = context.paper;
    final showActions = _hover || _isTouch;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: _hover ? paper.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            _Checkbox(done: true, onTap: widget.onRestore),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.note.text,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.3,
                      color: paper.inkSoft,
                      decoration: TextDecoration.lineThrough,
                      decorationColor: paper.inkFaint,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    timeAgoVi(widget.note.doneAt ?? widget.note.updatedAt),
                    style: TextStyle(fontSize: 10.5, color: paper.inkFaint),
                  ),
                ],
              ),
            ),
            _TileAction(
              icon: Icons.undo_rounded,
              tooltip: 'Đưa lại Current',
              visible: showActions,
              onTap: widget.onRestore,
            ),
            _TileAction(
              icon: Icons.close_rounded,
              tooltip: 'Xoá hẳn',
              visible: showActions,
              onTap: widget.onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

/// TextField sửa inline: Enter hoặc click ra ngoài là lưu.
class InlineEditor extends StatefulWidget {
  const InlineEditor({super.key, required this.initial, required this.onCommit});

  final String initial;
  final ValueChanged<String> onCommit;

  @override
  State<InlineEditor> createState() => _InlineEditorState();
}

class _InlineEditorState extends State<InlineEditor> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);
  final FocusNode _focus = FocusNode();
  bool _committed = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  void _commit() {
    if (_committed) return;
    _committed = true;
    widget.onCommit(_controller.text);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paper = context.paper;
    return TextField(
      controller: _controller,
      focusNode: _focus,
      autofocus: true,
      maxLines: null,
      cursorColor: paper.accent,
      cursorHeight: 14,
      style: TextStyle(fontSize: 13.5, height: 1.3, color: paper.ink),
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(vertical: 3),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
      ),
      onSubmitted: (_) => _commit(),
    );
  }
}

class _Checkbox extends StatelessWidget {
  const _Checkbox({required this.done, required this.onTap});

  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final paper = context.paper;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? paper.done : Colors.transparent,
            border: Border.all(
              color: done ? paper.done : paper.inkFaint,
              width: 1.6,
            ),
          ),
          child: done
              ? const Icon(Icons.check_rounded, size: 12, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}

class _TileAction extends StatelessWidget {
  const _TileAction({
    required this.icon,
    required this.tooltip,
    required this.visible,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 120),
      opacity: visible ? 1 : 0,
      child: IgnorePointer(
        ignoring: !visible,
        child: Tooltip(
          message: tooltip,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Icon(icon, size: 15, color: context.paper.inkFaint),
            ),
          ),
        ),
      ),
    );
  }
}
