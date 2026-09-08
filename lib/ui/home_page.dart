import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../app/desktop_integration.dart';
import '../app/settings_controller.dart';
import '../app/theme.dart';
import '../data/note_repo.dart';
import '../data/sync_service.dart';
import '../models/note.dart';
import 'note_tile.dart';
import 'sync_dialog.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.repo,
    required this.sync,
    required this.settings,
  });

  final NoteRepo repo;
  final SyncService sync;
  final SettingsController settings;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _addController = TextEditingController();
  final FocusNode _addFocus = FocusNode();

  int _tab = 0;
  String? _editingId;

  bool get _isDesktop => DesktopIntegration.isSupported;

  @override
  void dispose() {
    _addController.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  void _submitAdd() {
    final text = _addController.text.trim();
    if (text.isEmpty) return;
    widget.repo.add(text);
    _addController.clear();
    _addFocus.requestFocus();
  }

  void _onEscape() {
    if (_editingId != null) {
      setState(() => _editingId = null);
      return;
    }
    if (_isDesktop) DesktopIntegration.instance.hideWindow();
  }

  @override
  Widget build(BuildContext context) {
    final paper = context.paper;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _onEscape,
      },
      child: Focus(
        autofocus: true,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [paper.bgTop, paper.bg],
            ),
            borderRadius:
                _isDesktop ? BorderRadius.circular(kPaperRadius) : null,
            border:
                _isDesktop ? Border.all(color: paper.line, width: 0.8) : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            child: Column(
              children: [
                _buildTitleBar(),
                _buildTabs(),
                Expanded(
                  child: ListenableBuilder(
                    listenable: widget.repo,
                    builder: (context, _) => IndexedStack(
                      index: _tab,
                      sizing: StackFit.expand,
                      children: [
                        _buildCurrentTab(widget.repo.current),
                        _buildHistoryTab(widget.repo.history),
                      ],
                    ),
                  ),
                ),
                if (_tab == 0) _buildAddBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // region Title bar

  Widget _buildTitleBar() {
    final paper = context.paper;

    // Phần nhãn bên trái + khoảng trống: đây mới là vùng kéo cửa sổ.
    final label = Row(
      children: [
        const SizedBox(width: 12),
        Icon(Icons.sticky_note_2_outlined, size: 15, color: paper.accent),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'BF-StickyTask',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: paper.inkSoft,
              letterSpacing: 0.2,
            ),
          ),
        ),
        const SizedBox(width: 8),
      ],
    );

    // Các nút PHẢI nằm ngoài DragToMoveArea: widget đó có onDoubleTap nên nút
    // đặt bên trong sẽ phải chờ hết double-tap timer (~300ms) mới ăn tap.
    return SizedBox(
      height: kTitleBarHeight,
      child: Row(
        children: [
          Expanded(
            child: _isDesktop ? DragToMoveArea(child: label) : label,
          ),
          _buildThemeButton(),
          _buildSyncButton(),
          if (_isDesktop) ...[
            ListenableBuilder(
              listenable: DesktopIntegration.instance,
              builder: (context, _) {
                final pinned = DesktopIntegration.instance.alwaysOnTop;
                return _BarButton(
                  icon: pinned
                      ? Icons.push_pin_rounded
                      : Icons.push_pin_outlined,
                  color: pinned ? paper.accent : null,
                  tooltip: pinned
                      ? 'Đang nổi trên cùng — bấm để tắt'
                      : 'Bật nổi trên cùng',
                  onTap: () =>
                      DesktopIntegration.instance.setAlwaysOnTop(!pinned),
                );
              },
            ),
            _BarButton(
              icon: Icons.remove_rounded,
              tooltip: 'Ẩn (⌥⇧S để hiện lại)',
              onTap: DesktopIntegration.instance.hideWindow,
            ),
          ],
          const SizedBox(width: 6),
        ],
      ),
    );
  }

  /// Nút xoay vòng giao diện: tự động theo hệ thống → sáng → tối.
  Widget _buildThemeButton() {
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) {
        final (IconData icon, String label) = switch (widget.settings.themeMode) {
          ThemeMode.system => (
              Icons.brightness_auto_outlined,
              'tự động theo hệ thống'
            ),
          ThemeMode.light => (Icons.light_mode_outlined, 'sáng'),
          ThemeMode.dark => (Icons.dark_mode_outlined, 'tối'),
        };
        return _BarButton(
          icon: icon,
          tooltip: 'Giao diện: $label — bấm để đổi',
          onTap: widget.settings.cycleThemeMode,
        );
      },
    );
  }

  Widget _buildSyncButton() {
    return ListenableBuilder(
      listenable: widget.sync,
      builder: (context, _) {
        final paper = context.paper;
        final sync = widget.sync;
        final (IconData icon, Color color, String tip) = switch (sync.status) {
          SyncStatus.notConfigured => (
              Icons.cloud_off_rounded,
              paper.inkFaint,
              'Chưa cấu hình đồng bộ — bấm để nhập URL + key'
            ),
          SyncStatus.syncing => (
              Icons.sync_rounded,
              paper.accent,
              'Đang đồng bộ…'
            ),
          SyncStatus.offline => (
              Icons.cloud_off_rounded,
              paper.danger,
              'Mất kết nối — thay đổi đang chờ'
            ),
          SyncStatus.idle => (
              sync.hasPendingChanges
                  ? Icons.cloud_upload_outlined
                  : Icons.cloud_done_outlined,
              sync.hasPendingChanges ? paper.accent : paper.done,
              sync.hasPendingChanges ? 'Đang chờ đẩy lên' : 'Đã đồng bộ'
            ),
        };

        return _BarButton(
          icon: icon,
          color: color,
          tooltip: tip,
          onTap: () => showSyncDialog(context, sync),
        );
      },
    );
  }

  // endregion

  // region Tabs

  Widget _buildTabs() {
    return ListenableBuilder(
      listenable: widget.repo,
      builder: (context, _) {
        final currentCount = widget.repo.current.length;
        final historyCount = widget.repo.history.length;
        return Container(
          margin: const EdgeInsets.fromLTRB(10, 2, 10, 8),
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: context.paper.line.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              _TabButton(
                label: 'Current',
                count: currentCount,
                selected: _tab == 0,
                onTap: () => setState(() => _tab = 0),
              ),
              _TabButton(
                label: 'History',
                count: historyCount,
                selected: _tab == 1,
                onTap: () => setState(() {
                  _tab = 1;
                  _editingId = null;
                }),
              ),
            ],
          ),
        );
      },
    );
  }

  // endregion

  // region Current tab

  Widget _buildCurrentTab(List<Note> notes) {
    if (notes.isEmpty) {
      return const _EmptyState(
        icon: Icons.check_circle_outline_rounded,
        title: 'Không còn việc nào',
        subtitle: 'Thêm việc ở ô bên dưới.',
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.only(bottom: 6),
      buildDefaultDragHandles: false,
      itemCount: notes.length,
      onReorderItem: (oldIndex, newIndex) {
        setState(() => _editingId = null);
        widget.repo.reorder(oldIndex, newIndex);
      },
      proxyDecorator: (child, index, animation) => Material(
        color: context.paper.surface,
        elevation: 4,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(8),
        child: child,
      ),
      itemBuilder: (context, index) {
        final note = notes[index];
        return CurrentNoteTile(
          key: ValueKey(note.id),
          note: note,
          index: index,
          editing: _editingId == note.id,
          onToggleDone: () {
            setState(() => _editingId = null);
            widget.repo.setDone(note.id, true);
          },
          onStartEdit: () => setState(() => _editingId = note.id),
          onCommitEdit: (text) {
            widget.repo.editText(note.id, text);
            if (mounted && _editingId == note.id) {
              setState(() => _editingId = null);
            }
          },
          onDelete: () {
            setState(() => _editingId = null);
            widget.repo.remove(note.id);
          },
        );
      },
    );
  }

  Widget _buildAddBar() {
    final paper = context.paper;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: paper.line, width: 0.8)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _addController,
              focusNode: _addFocus,
              textInputAction: TextInputAction.done,
              cursorColor: paper.accent,
              cursorHeight: 14,
              style: TextStyle(fontSize: 13.5, color: paper.ink),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Thêm việc cần làm…',
                hintStyle: TextStyle(fontSize: 13, color: paper.inkFaint),
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              onSubmitted: (_) => _submitAdd(),
            ),
          ),
          _BarButton(
            icon: Icons.add_rounded,
            color: paper.accent,
            tooltip: 'Thêm',
            size: 20,
            onTap: _submitAdd,
          ),
        ],
      ),
    );
  }

  // endregion

  // region History tab

  Widget _buildHistoryTab(List<Note> notes) {
    if (notes.isEmpty) {
      return const _EmptyState(
        icon: Icons.history_rounded,
        title: 'Chưa có việc nào xong',
        subtitle: 'Tick một dòng ở tab Current để nó chuyển sang đây.',
      );
    }

    final paper = context.paper;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 10, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${notes.length} việc đã xong',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: paper.inkFaint),
                ),
              ),
              TextButton(
                onPressed: () => _confirmClearHistory(notes.length),
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Xoá hết',
                  style: TextStyle(fontSize: 11.5, color: paper.danger),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 10),
            itemCount: notes.length,
            itemBuilder: (context, index) {
              final note = notes[index];
              return HistoryNoteTile(
                key: ValueKey(note.id),
                note: note,
                onRestore: () => widget.repo.setDone(note.id, false),
                onDelete: () => widget.repo.remove(note.id),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _confirmClearHistory(int count) async {
    final paper = context.paper;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: paper.surface,
        title: const Text('Xoá hết History?', style: TextStyle(fontSize: 15)),
        content: Text(
          '$count việc đã xong sẽ bị xoá trên mọi máy.',
          style: TextStyle(fontSize: 12.5, color: paper.inkSoft),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Thôi'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: paper.danger),
            child: const Text('Xoá hết'),
          ),
        ],
      ),
    );
    if (ok == true) widget.repo.clearHistory();
  }

  // endregion
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final paper = context.paper;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: selected ? paper.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 3,
                      offset: Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? paper.ink : paper.inkSoft,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 5),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    color: selected ? paper.accent : paper.inkFaint,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
    this.size = 16,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  /// Bỏ trống thì dùng màu chữ mờ của bảng màu hiện tại.
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: size, color: color ?? context.paper.inkFaint),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final paper = context.paper;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 26, color: paper.line),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(fontSize: 12.5, color: paper.inkFaint),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: paper.inkFaint),
            ),
          ],
        ),
      ),
    );
  }
}
