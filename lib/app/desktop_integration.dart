import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Mọi thứ "chỉ có trên desktop": cửa sổ nổi trên cùng, frameless, nhớ vị trí,
/// icon tray và global hotkey. Trên Android class này không được dùng.
class DesktopIntegration extends ChangeNotifier with TrayListener, WindowListener {
  DesktopIntegration._();

  static final DesktopIntegration instance = DesktopIntegration._();

  static const String _prefAlwaysOnTop = 'always_on_top';
  static const String _prefBounds = 'window_bounds';

  static const Size defaultSize = Size(340, 520);
  static const Size minSize = Size(280, 340);

  /// Hotkey bật/tắt cửa sổ. macOS: ⌥⇧S — Windows/Linux: Alt+Shift+S.
  static final HotKey toggleHotKey = HotKey(
    key: PhysicalKeyboardKey.keyS,
    modifiers: [HotKeyModifier.alt, HotKeyModifier.shift],
    scope: HotKeyScope.system,
  );

  static bool get isSupported =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  /// tray_manager 0.5.3 không forward mouse event trên macOS và không gắn menu
  /// vào status item, nên icon menu bar của macOS được làm bằng AppKit trong
  /// `macos/Runner/AppDelegate.swift`. Ở đây chỉ dùng nó cho Windows/Linux.
  static bool get _usesTrayManager => isSupported && !Platform.isMacOS;

  bool _alwaysOnTop = true;
  bool _visible = true;
  SharedPreferences? _prefs;
  Timer? _boundsTimer;

  bool get alwaysOnTop => _alwaysOnTop;

  /// Dựng cửa sổ trước `runApp` — kích thước, frameless, always-on-top.
  Future<void> setUpWindow() async {
    if (!isSupported) return;
    await windowManager.ensureInitialized();
    _prefs = await SharedPreferences.getInstance();
    _alwaysOnTop = _prefs?.getBool(_prefAlwaysOnTop) ?? true;

    final options = WindowOptions(
      size: defaultSize,
      minimumSize: minSize,
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      title: 'BF-StickyTask',
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      alwaysOnTop: _alwaysOnTop,
    );

    await windowManager.waitUntilReadyToShow(options, () async {
      await _restoreBounds();
      await windowManager.show();
      await windowManager.setAlwaysOnTop(_alwaysOnTop);
      if (Platform.isMacOS) {
        // Nổi cả khi đổi Space / khi có app đang fullscreen.
        await windowManager.setVisibleOnAllWorkspaces(
          true,
          visibleOnFullScreen: true,
        );
      }
      // Bấm × trên title bar chỉ ẩn đi, thoát thật thì dùng menu tray.
      await windowManager.setPreventClose(true);
    });
  }

  /// Gắn listener + tray + hotkey. Gọi sau khi widget tree dựng xong.
  Future<void> attach() async {
    if (!isSupported) return;
    windowManager.addListener(this);
    if (_usesTrayManager) {
      trayManager.addListener(this);
      await _setUpTray();
    }
    await _setUpHotKey();
  }

  Future<void> setAlwaysOnTop(bool value) async {
    if (!isSupported) return;
    _alwaysOnTop = value;
    await windowManager.setAlwaysOnTop(value);
    await _prefs?.setBool(_prefAlwaysOnTop, value);
    if (_usesTrayManager) await _refreshTrayMenu();
    notifyListeners();
  }

  Future<void> toggleVisibility() async {
    if (!isSupported) return;
    if (await windowManager.isVisible() && _visible) {
      await hideWindow();
    } else {
      await showWindow();
    }
  }

  Future<void> showWindow() async {
    if (!isSupported) return;
    _visible = true;
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> hideWindow() async {
    if (!isSupported) return;
    _visible = false;
    await windowManager.hide();
  }

  Future<void> quit() async {
    if (!isSupported) return;
    if (_usesTrayManager) await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  // region Tray

  Future<void> _setUpTray() async {
    final icon = Platform.isWindows
        ? 'assets/tray/tray_win.ico'
        : 'assets/tray/tray_win.png';
    await trayManager.setIcon(icon);
    if (!Platform.isLinux) await trayManager.setToolTip('BF-StickyTask');
    await _refreshTrayMenu();
  }

  Future<void> _refreshTrayMenu() async {
    if (!_usesTrayManager) return;
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show', label: 'Hiện BF-StickyTask'),
          MenuItem.checkbox(
            key: 'pin',
            label: 'Luôn nổi trên cùng',
            checked: _alwaysOnTop,
          ),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: 'Thoát'),
        ],
      ),
    );
  }

  @override
  void onTrayIconMouseDown() => toggleVisibility();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        showWindow();
      case 'pin':
        setAlwaysOnTop(!_alwaysOnTop);
      case 'quit':
        quit();
    }
  }

  // endregion

  // region Hotkey

  Future<void> _setUpHotKey() async {
    await hotKeyManager.unregisterAll();
    try {
      await hotKeyManager.register(
        toggleHotKey,
        keyDownHandler: (_) => toggleVisibility(),
      );
    } catch (e) {
      debugPrint('Không đăng ký được hotkey: $e');
    }
  }

  // endregion

  // region Window bounds

  Future<void> _restoreBounds() async {
    final raw = _prefs?.getString(_prefBounds);
    if (raw == null) return;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final rect = Rect.fromLTWH(
        (json['x'] as num).toDouble(),
        (json['y'] as num).toDouble(),
        (json['w'] as num).toDouble(),
        (json['h'] as num).toDouble(),
      );
      if (rect.width >= minSize.width && rect.height >= minSize.height) {
        await windowManager.setBounds(rect);
      }
    } catch (_) {
      // Bounds hỏng thì dùng mặc định.
    }
  }

  void _scheduleSaveBounds() {
    _boundsTimer?.cancel();
    _boundsTimer = Timer(const Duration(milliseconds: 500), () async {
      final bounds = await windowManager.getBounds();
      await _prefs?.setString(
        _prefBounds,
        jsonEncode({
          'x': bounds.left,
          'y': bounds.top,
          'w': bounds.width,
          'h': bounds.height,
        }),
      );
    });
  }

  @override
  void onWindowMoved() => _scheduleSaveBounds();

  @override
  void onWindowResized() => _scheduleSaveBounds();

  @override
  void onWindowClose() => hideWindow();

  // endregion

  @override
  void dispose() {
    _boundsTimer?.cancel();
    windowManager.removeListener(this);
    if (_usesTrayManager) trayManager.removeListener(this);
    super.dispose();
  }
}
