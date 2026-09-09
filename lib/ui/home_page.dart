import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../app/desktop_integration.dart';
import '../app/history_filter.dart';
import '../app/launch_at_startup.dart';
import '../app/settings_controller.dart';
import '../app/theme.dart';
import '../data/note_repo.dart';
import '../data/sync_service.dart';
import '../data/update_service.dart';
import '../data/updater.dart';
import '../models/note.dart';
import 'confirm_dialog.dart';
import 'group_dialog.dart';
import 'note_tile.dart';
import 'sync_dialog.dart';
import 'update_dialog.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.repo,
    required this.sync,
    required this.settings,
    required this.update,
    required this.updater,
  });

  final NoteRepo repo;
  final SyncService sync;
  final SettingsController settings;
  final UpdateService update;
  final Updater updater;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _addController = TextEditingController();
  final FocusNode _addFocus = FocusNode();
  final TextEditingController _searchController = TextEditingController();

  int _tab = 0;
  String? _editingId;

  /// Bộ lọc ngày của tab History. Chỉ sống trong phiên chạy — mở lại app là
  /// về "Tất cả", để không có lần nào mở app ra thấy History trống mà không
  /// hiểu vì sao.
  HistoryFilter _historyFilter = HistoryFilter.all;

  /// Group đang xem — `null` là "Tất cả" (gộp mọi group, hành vi cũ).
  /// Dùng chung cho cả 2 tab, giống cách 2 tab dùng chung 1 bộ khung.
  String? _activeGroupId;

  /// Lọc theo chữ, dùng chung cho cả 2 tab. Chỉ sống trong phiên chạy, giống
  /// [_historyFilter].
  String _searchQuery = '';

  /// Ô tìm việc mặc định ẩn — chỉ hiện khi bấm nút kính lúp, đỡ chiếm chỗ
  /// trong cửa sổ vốn đã hẹp.
  bool _searchVisible = false;

  /// Chế độ chọn nhiều để chuyển hàng loạt sang group khác.
  bool _selecting = false;
  final Set<String> _selectedIds = {};

  bool get _isDesktop => DesktopIntegration.isSupported;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdateOnStartup());
  }

  /// Kiểm bản mới khi mở app. Chỉ bật popup khi thật có bản mới và user chưa
  /// bấm "Bỏ qua bản này" — lỗi mạng thì im lặng, trạng thái vẫn nằm trong
  /// UpdateService để nút trên title bar hiện.
  Future<void> _checkUpdateOnStartup() async {
    final release = await widget.update.checkOnStartup();
    if (release == null || !mounted) return;
    await showUpdateDialog(context, widget.update, widget.updater);
  }

  @override
  void dispose() {
    _addController.dispose();
    _addFocus.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _submitAdd() {
    final text = _addController.text.trim();
    if (text.isEmpty) return;
    widget.repo.add(text, groupId: _activeGroupId);
    _addController.clear();
    _addFocus.requestFocus();
  }

  void _onEscape() {
    if (_editingId != null) {
      setState(() => _editingId = null);
      return;
    }
    if (_selecting) {
      _exitSelection();
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
                _buildGroupBar(),
                if (_searchVisible) _buildSearchBar(),
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
                if (_selecting)
                  _buildSelectionBar()
                else if (_tab == 0)
                  _buildAddBar(),
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
          _buildUpdateButton(),
          _buildSyncButton(),
          if (_isDesktop) ...[
            _buildStartupButton(),
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

  /// Nút kiểm tra cập nhật. Đổi sang màu accent khi đã biết có bản mới, để
  /// user đóng popup rồi vẫn thấy dấu hiệu còn bản mới đang chờ.
  Widget _buildUpdateButton() {
    return ListenableBuilder(
      listenable: widget.update,
      builder: (context, _) {
        final update = widget.update;
        final available = update.updateAvailable;
        return _BarButton(
          icon: available
              ? Icons.system_update_alt_rounded
              : Icons.refresh_rounded,
          color: available ? context.paper.accent : null,
          tooltip: available
              ? 'Có bản mới ${update.latest?.version ?? ''} — bấm để xem'
              : 'Kiểm tra cập nhật',
          onTap: () => showUpdateDialog(
            context,
            update,
            widget.updater,
            checkOnOpen: !available,
          ),
        );
      },
    );
  }

  /// Nút "mở app khi khởi động máy". Tự ẩn khi nền tảng không làm được
  /// (Android, hoặc macOS < 13 — xem [LaunchAtStartup]).
  Widget _buildStartupButton() {
    return ListenableBuilder(
      listenable: LaunchAtStartup.instance,
      builder: (context, _) {
        final paper = context.paper;
        final state = LaunchAtStartup.instance.state;
        if (!state.supported) return const SizedBox.shrink();

        final error = state.error;
        final (Color? color, String tip) = switch (state) {
          LaunchAtStartupState(error: final String e) => (
              paper.danger,
              'Không đổi được: $e'
            ),
          LaunchAtStartupState(enabled: true, requiresApproval: true) => (
              paper.danger,
              'Đã bật nhưng macOS còn chờ duyệt — vào System Settings → '
                  'General → Login Items rồi bật BF-StickyTask'
            ),
          LaunchAtStartupState(enabled: true) => (
              paper.accent,
              'Tự mở khi khởi động máy — bấm để tắt'
            ),
          _ => (null, 'Bật tự mở khi khởi động máy'),
        };

        return _BarButton(
          icon: state.enabled && error == null
              ? Icons.rocket_launch_rounded
              : Icons.rocket_launch_outlined,
          color: color,
          tooltip: tip,
          onTap: LaunchAtStartup.instance.toggle,
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

  // region Group + search bar (dùng chung cho cả 2 tab)

  Widget _buildGroupBar() {
    return ListenableBuilder(
      listenable: widget.repo,
      builder: (context, _) {
        final paper = context.paper;
        final groups = widget.repo.groups;

        // Group đang chọn vừa bị xoá (vd: xoá ở popup quản lý) → về "Tất cả",
        // không thì lọc theo 1 id không còn tồn tại sẽ luôn ra danh sách rỗng.
        if (_activeGroupId != null && !groups.any((g) => g.id == _activeGroupId)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _activeGroupId = null);
          });
        }

        return SizedBox(
          height: 26,
          child: Row(
            children: [
              _BarButton(
                icon: _searchVisible ? Icons.search_off_rounded : Icons.search_rounded,
                color: _searchVisible ? paper.accent : null,
                tooltip: _searchVisible ? 'Ẩn ô tìm việc' : 'Tìm việc',
                onTap: _toggleSearch,
              ),
              Expanded(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  children: [
                    _FilterChip(
                      label: 'Mọi nhóm',
                      selected: _activeGroupId == null,
                      onTap: () => setState(() => _activeGroupId = null),
                    ),
                    for (final g in groups)
                      _FilterChip(
                        label: g.name,
                        selected: _activeGroupId == g.id,
                        onTap: () => setState(() => _activeGroupId = g.id),
                      ),
                  ],
                ),
              ),
              _BarButton(
                icon: _selecting ? Icons.close_rounded : Icons.checklist_rounded,
                color: _selecting ? paper.accent : null,
                tooltip: _selecting ? 'Huỷ chọn' : 'Chọn nhiều để chuyển nhóm',
                onTap: _toggleSelecting,
              ),
              _BarButton(
                icon: Icons.category_outlined,
                tooltip: 'Quản lý nhóm',
                onTap: () => showGroupManagerDialog(context, widget.repo),
              ),
              const SizedBox(width: 4),
            ],
          ),
        );
      },
    );
  }

  void _toggleSearch() {
    setState(() {
      _searchVisible = !_searchVisible;
      if (!_searchVisible) {
        _searchQuery = '';
        _searchController.clear();
      }
    });
  }

  void _toggleSelecting() {
    setState(() {
      _selecting = !_selecting;
      _selectedIds.clear();
      _editingId = null;
    });
  }

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelected(String noteId) {
    setState(() {
      if (!_selectedIds.remove(noteId)) _selectedIds.add(noteId);
    });
  }

  /// Mở popup chọn group cho đúng 1 việc.
  Future<void> _moveNoteToGroup(Note note) async {
    final groupId = await showGroupPickerDialog(
      context,
      widget.repo,
      currentGroupId: note.groupId,
    );
    if (groupId == null) return;
    widget.repo.setGroup(note.id, groupId);
  }

  /// Mở popup chọn group cho mọi việc đang được chọn, rồi thoát chế độ chọn.
  Future<void> _moveSelectedToGroup() async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;
    final groupId = await showGroupPickerDialog(
      context,
      widget.repo,
      title: 'Chuyển ${ids.length} việc vào nhóm',
    );
    if (groupId == null || !mounted) return;
    for (final id in ids) {
      widget.repo.setGroup(id, groupId);
    }
    _exitSelection();
  }

  Widget _buildSelectionBar() {
    final paper = context.paper;
    final count = _selectedIds.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: paper.line, width: 0.8)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              count == 0 ? 'Chọn việc cần chuyển nhóm' : '$count đã chọn',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: paper.inkSoft),
            ),
          ),
          TextButton(
            onPressed: count == 0 ? null : _moveSelectedToGroup,
            child: Text(
              'Chuyển nhóm',
              style: TextStyle(color: count == 0 ? paper.inkFaint : paper.accent),
            ),
          ),
          TextButton(
            onPressed: _exitSelection,
            child: const Text('Huỷ'),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final paper = context.paper;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
      child: SizedBox(
        height: 30,
        child: TextField(
          key: const Key('search-field'),
          controller: _searchController,
          style: TextStyle(fontSize: 12.5, color: paper.ink),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Tìm việc…',
            hintStyle: TextStyle(fontSize: 12, color: paper.inkFaint),
            filled: true,
            fillColor: paper.line.withValues(alpha: 0.35),
            prefixIcon: Icon(Icons.search_rounded, size: 16, color: paper.inkFaint),
            prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 0),
            suffixIcon: _searchQuery.isEmpty
                ? null
                : InkWell(
                    onTap: () => setState(() {
                      _searchController.clear();
                      _searchQuery = '';
                    }),
                    child: Icon(Icons.close_rounded, size: 15, color: paper.inkFaint),
                  ),
            suffixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 0),
            contentPadding: const EdgeInsets.symmetric(vertical: 6),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: (v) => setState(() => _searchQuery = v.trim()),
        ),
      ),
    );
  }

  /// Lọc theo group đang chọn + từ khoá tìm — dùng cho cả Current lẫn History.
  List<Note> _applyFilters(List<Note> notes) {
    Iterable<Note> result = notes;
    if (_activeGroupId != null) {
      result = result.where((n) => n.groupId == _activeGroupId);
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((n) => n.text.toLowerCase().contains(q));
    }
    return result.toList();
  }

  /// Tên group để gắn thêm vào dòng note — chỉ khi đang xem gộp "Tất cả" VÀ
  /// có nhiều hơn 1 group, không thì thừa thông tin.
  String? _groupLabelFor(Note note) {
    if (_activeGroupId != null) return null;
    final groups = widget.repo.groups;
    if (groups.length <= 1) return null;
    for (final g in groups) {
      if (g.id == note.groupId) return g.name;
    }
    return null;
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

    final filtered = _applyFilters(notes);
    if (filtered.isEmpty) {
      return const _EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Không có việc nào khớp',
        subtitle: 'Đổi từ khoá tìm hoặc nhóm đang chọn ở trên.',
      );
    }

    // Đang tìm theo chữ, hoặc đang ở chế độ chọn nhiều, thì danh sách hiện
    // không còn đúng thứ tự kéo-thả thật (hoặc tap dòng nghĩa là chọn chứ
    // không phải kéo) — tắt kéo-thả, không thì vị trí thả bị tính sai.
    if (_searchQuery.isNotEmpty || _selecting) {
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 6),
        itemCount: filtered.length,
        itemBuilder: (context, index) =>
            _currentTile(filtered[index], index, draggable: false),
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.only(bottom: 6),
      buildDefaultDragHandles: false,
      itemCount: filtered.length,
      onReorderItem: (oldIndex, newIndex) {
        setState(() => _editingId = null);
        widget.repo.reorder(oldIndex, newIndex, groupId: _activeGroupId);
      },
      proxyDecorator: (child, index, animation) => Material(
        color: context.paper.surface,
        elevation: 4,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(8),
        child: child,
      ),
      itemBuilder: (context, index) =>
          _currentTile(filtered[index], index, draggable: true),
    );
  }

  Widget _currentTile(Note note, int index, {required bool draggable}) {
    return CurrentNoteTile(
      key: ValueKey(note.id),
      note: note,
      index: index,
      editing: _editingId == note.id,
      showDragHandle: draggable,
      groupLabel: _groupLabelFor(note),
      selecting: _selecting,
      selected: _selectedIds.contains(note.id),
      onToggleSelect: () => _toggleSelected(note.id),
      onToggleDone: () {
        setState(() => _editingId = null);
        widget.repo.setDone(note.id, true);
      },
      onToggleInProgress: () =>
          widget.repo.setInProgress(note.id, !note.isInProgress),
      onStartEdit: () => setState(() => _editingId = note.id),
      onCommitEdit: (text) {
        widget.repo.editText(note.id, text);
        if (mounted && _editingId == note.id) {
          setState(() => _editingId = null);
        }
      },
      onMoveToGroup: () => _moveNoteToGroup(note),
      onDelete: () => _confirmRemove(
        note,
        title: 'Xoá việc này?',
        message: 'Việc sẽ bị xoá trên mọi máy.',
      ),
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
    final filtered = _applyFilters(notes)
        .where((n) => _historyFilter.matches(n.doneAt ?? n.updatedAt))
        .toList();
    final filtering = _historyFilter.isActive ||
        _activeGroupId != null ||
        _searchQuery.isNotEmpty;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 10, 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  filtering
                      ? '${filtered.length}/${notes.length} việc đã xong'
                      : '${notes.length} việc đã xong',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: paper.inkFaint),
                ),
              ),
              TextButton(
                onPressed:
                    filtered.isEmpty ? null : () => _confirmClearHistory(filtered),
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Xoá hết',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: filtered.isEmpty ? paper.inkFaint : paper.danger,
                  ),
                ),
              ),
            ],
          ),
        ),
        _buildHistoryFilterBar(),
        Expanded(
          child: filtered.isEmpty
              ? const _EmptyState(
                  icon: Icons.event_busy_outlined,
                  title: 'Không có việc nào trong khoảng này',
                  subtitle: 'Đổi bộ lọc ở trên để xem việc khác.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 10),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final note = filtered[index];
                    return HistoryNoteTile(
                      key: ValueKey(note.id),
                      note: note,
                      groupLabel: _groupLabelFor(note),
                      selecting: _selecting,
                      selected: _selectedIds.contains(note.id),
                      onToggleSelect: () => _toggleSelected(note.id),
                      onMoveToGroup: () => _moveNoteToGroup(note),
                      onRestore: () => widget.repo.setDone(note.id, false),
                      onDelete: () => _confirmRemove(
                        note,
                        title: 'Xoá hẳn việc này?',
                        message:
                            'Việc sẽ bị xoá trên mọi máy và không lấy lại được.',
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Hàng chip lọc theo ngày. Cuộn ngang được vì cửa sổ chỉ rộng ~340px.
  Widget _buildHistoryFilterBar() {
    const presets = [
      HistoryRange.all,
      HistoryRange.today,
      HistoryRange.last7Days,
      HistoryRange.last30Days,
    ];
    final custom = _historyFilter.range == HistoryRange.custom;

    return SizedBox(
      height: 26,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final range in presets)
            _FilterChip(
              label: range.label,
              selected: _historyFilter.range == range,
              onTap: () => setState(
                () => _historyFilter = HistoryFilter.preset(range),
              ),
            ),
          _FilterChip(
            label: custom ? _historyFilter.label : 'Chọn ngày',
            icon: Icons.calendar_month_outlined,
            selected: custom,
            onTap: _pickHistoryRange,
          ),
        ],
      ),
    );
  }

  Future<void> _pickHistoryRange() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDateRangePicker(
      context: context,
      // Note cũ hơn 5 năm thì không còn ai lọc tới; giới hạn cho picker gọn.
      firstDate: DateTime(now.year - 5),
      lastDate: today,
      initialDateRange: _historyFilter.customRange,
      // Bản lịch chiếm trọn cửa sổ ~340px và vẫn đọc được; bản nhập tay thì
      // chật đến mức nhãn bị cắt (đã thử). Nút bút chì trong popup vẫn đổi
      // sang nhập tay được nếu user muốn.
      helpText: 'Lọc History theo ngày',
      saveText: 'Lọc',
      fieldStartLabelText: 'Từ ngày',
      fieldEndLabelText: 'Đến ngày',
    );
    if (picked == null || !mounted) return;
    setState(() => _historyFilter = HistoryFilter.custom(picked));
  }

  /// Xoá một note, có popup xác nhận. Dùng cho cả Current và History.
  Future<void> _confirmRemove(
    Note note, {
    required String title,
    required String message,
  }) async {
    // Thoát editor trước khi mở dialog. InlineEditor tự commit khi mất focus,
    // mà mở dialog là nó mất focus — để nó sống thì bấm "Thôi" vẫn âm thầm lưu
    // một lần sửa mà user không hề xác nhận.
    if (_editingId != null) setState(() => _editingId = null);
    final ok = await confirmDelete(
      context,
      title: title,
      message: message,
      detail: note.text,
    );
    if (!ok || !mounted) return;
    widget.repo.remove(note.id);
  }

  /// "Xoá hết" chỉ xoá đúng những dòng đang hiện — đang lọc (ngày, nhóm, hay
  /// từ khoá) mà xoá sạch cả tab thì user mất dữ liệu ngoài phần họ đang nhìn.
  Future<void> _confirmClearHistory(List<Note> shown) async {
    final dateFiltering = _historyFilter.isActive;
    final otherFiltering = _activeGroupId != null || _searchQuery.isNotEmpty;

    final String title;
    final String message;
    if (dateFiltering) {
      title = 'Xoá hết trong khoảng đang lọc?';
      message = '${shown.length} việc xong trong "${_historyFilter.label}" sẽ bị '
          'xoá trên mọi máy. Việc ngoài khoảng này giữ nguyên.';
    } else if (otherFiltering) {
      title = 'Xoá hết đang lọc?';
      message = '${shown.length} việc đang hiện sẽ bị xoá trên mọi máy. '
          'Việc bị nhóm/từ khoá đang lọc ẩn đi vẫn giữ nguyên.';
    } else {
      title = 'Xoá hết History?';
      message = '${shown.length} việc đã xong sẽ bị xoá trên mọi máy.';
    }

    final ok = await confirmDelete(
      context,
      title: title,
      message: message,
      confirmLabel: 'Xoá hết',
    );
    if (!ok || !mounted) return;
    widget.repo.removeAll(shown.map((n) => n.id));
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

/// Chip nhỏ của hàng lọc ngày ở tab History.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final paper = context.paper;
    return Padding(
      padding: const EdgeInsets.only(right: 5),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? paper.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: selected ? paper.accent : paper.line,
              width: selected ? 1.1 : 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 12,
                  color: selected ? paper.accent : paper.inkFaint,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? paper.ink : paper.inkSoft,
                ),
              ),
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
