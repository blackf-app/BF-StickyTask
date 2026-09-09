import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../app/time_ago.dart';
import '../models/note.dart';

bool get _isTouch => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Một dòng trong tab Current: tick done, đánh dấu đang làm, sửa inline, xoá,
/// kéo đổi thứ tự.
class CurrentNoteTile extends StatefulWidget {
  const CurrentNoteTile({
    super.key,
    required this.note,
    required this.index,
    required this.editing,
    required this.onToggleDone,
    required this.onToggleInProgress,
    required this.onStartEdit,
    required this.onCommitEdit,
    required this.onDelete,
    required this.onMoveToGroup,
    this.showDragHandle = true,
    this.groupLabel,
    this.selecting = false,
    this.selected = false,
    this.onToggleSelect,
  });

  final Note note;
  final int index;
  final bool editing;
  final VoidCallback onToggleDone;
  final VoidCallback onToggleInProgress;
  final VoidCallback onStartEdit;
  final ValueChanged<String> onCommitEdit;
  final VoidCallback onDelete;

  /// Mở popup chọn group để chuyển đúng dòng này vào.
  final VoidCallback onMoveToGroup;

  /// Tắt khi danh sách đang hiện không phải thứ tự kéo-thả thật (vd: đang lọc
  /// theo từ khoá) — kéo lúc đó sẽ tính sai vị trí.
  final bool showDragHandle;

  /// Tên group — chỉ truyền khi đang xem gộp nhiều group ("Tất cả"), để phân
  /// biệt dòng nào thuộc group nào.
  final String? groupLabel;

  /// Đang ở chế độ chọn nhiều để chuyển nhóm hàng loạt — tap dòng thì
  /// chọn/bỏ chọn thay vì sửa/tick, các action khác tạm ẩn để tránh bấm nhầm.
  final bool selecting;
  final bool selected;
  final VoidCallback? onToggleSelect;

  @override
  State<CurrentNoteTile> createState() => _CurrentNoteTileState();
}

class _CurrentNoteTileState extends State<CurrentNoteTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final paper = context.paper;
    final selecting = widget.selecting;
    final showActions = !selecting && (_hover || _isTouch || widget.editing);
    final raised = _hover || widget.editing;
    final inProgress = widget.note.isInProgress;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selecting && widget.selected
              ? paper.accent.withValues(alpha: 0.14)
              : raised
                  ? paper.surface
                  : inProgress
                      ? paper.accent.withValues(alpha: 0.08)
                      : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            selecting
                ? _Checkbox(
                    done: widget.selected,
                    onTap: widget.onToggleSelect ?? () {},
                    activeColor: paper.accent,
                  )
                : _Checkbox(done: false, onTap: widget.onToggleDone),
            const SizedBox(width: 6),
            if (!selecting) ...[
              _ProgressToggle(active: inProgress, onTap: widget.onToggleInProgress),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: (!selecting && widget.editing)
                  ? InlineEditor(
                      initial: widget.note.text,
                      onCommit: widget.onCommitEdit,
                    )
                  : GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: selecting ? widget.onToggleSelect : widget.onStartEdit,
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
            if (widget.groupLabel != null) ...[
              const SizedBox(width: 4),
              _GroupTag(label: widget.groupLabel!),
            ],
            if (!selecting) ...[
              _TileAction(
                icon: Icons.drive_file_move_outline,
                tooltip: 'Chuyển nhóm',
                visible: showActions,
                onTap: widget.onMoveToGroup,
              ),
              _TileAction(
                icon: Icons.close_rounded,
                tooltip: 'Xoá',
                visible: showActions,
                onTap: widget.onDelete,
              ),
              if (widget.showDragHandle)
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
    required this.onMoveToGroup,
    this.groupLabel,
    this.selecting = false,
    this.selected = false,
    this.onToggleSelect,
  });

  final Note note;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  /// Mở popup chọn group để chuyển đúng dòng này vào.
  final VoidCallback onMoveToGroup;

  /// Tên group — chỉ truyền khi đang xem gộp nhiều group ("Tất cả").
  final String? groupLabel;

  final bool selecting;
  final bool selected;
  final VoidCallback? onToggleSelect;

  @override
  State<HistoryNoteTile> createState() => _HistoryNoteTileState();
}

class _HistoryNoteTileState extends State<HistoryNoteTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final paper = context.paper;
    final selecting = widget.selecting;
    final showActions = !selecting && (_hover || _isTouch);

    final container = Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: selecting && widget.selected
            ? paper.accent.withValues(alpha: 0.14)
            : _hover
                ? paper.surface
                : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          selecting
              ? _Checkbox(
                  done: widget.selected,
                  onTap: widget.onToggleSelect ?? () {},
                  activeColor: paper.accent,
                )
              : _Checkbox(done: true, onTap: widget.onRestore),
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
                Row(
                  children: [
                    Text(
                      timeAgoVi(widget.note.doneAt ?? widget.note.updatedAt),
                      style: TextStyle(fontSize: 10.5, color: paper.inkFaint),
                    ),
                    if (widget.groupLabel != null) ...[
                      const SizedBox(width: 6),
                      _GroupTag(label: widget.groupLabel!),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (!selecting) ...[
            _TileAction(
              icon: Icons.drive_file_move_outline,
              tooltip: 'Chuyển nhóm',
              visible: showActions,
              onTap: widget.onMoveToGroup,
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
        ],
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: selecting
          ? GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onToggleSelect,
              child: container,
            )
          : container,
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

/// Nút đánh dấu "đang làm" — luôn hiện (không chỉ lúc hover) để nhìn cả danh
/// sách là biết ngay việc nào đang được làm dở.
class _ProgressToggle extends StatelessWidget {
  const _ProgressToggle({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final paper = context.paper;
    return Tooltip(
      message: active ? 'Đang làm — bấm để bỏ đánh dấu' : 'Đánh dấu đang làm',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(
            active ? Icons.bolt_rounded : Icons.bolt_outlined,
            size: 15,
            color: active ? paper.accent : paper.line,
          ),
        ),
      ),
    );
  }
}

/// Nhãn nhỏ hiện tên group — chỉ dùng khi đang xem gộp nhiều group.
class _GroupTag extends StatelessWidget {
  const _GroupTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final paper = context.paper;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: paper.line.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 10, color: paper.inkSoft),
      ),
    );
  }
}

class _Checkbox extends StatelessWidget {
  const _Checkbox({required this.done, required this.onTap, this.activeColor});

  final bool done;
  final VoidCallback onTap;

  /// Màu khi `done`. Bỏ trống thì dùng màu "đã xong" mặc định — truyền tay
  /// (vd màu accent) khi tái dùng widget này cho việc khác, như tick chọn.
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final paper = context.paper;
    final color = activeColor ?? paper.done;
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
            color: done ? color : Colors.transparent,
            border: Border.all(
              color: done ? color : paper.inkFaint,
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
