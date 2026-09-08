import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cài đặt hiển thị của app, lưu vào SharedPreferences.
class SettingsController extends ChangeNotifier {
  static const String _keyThemeMode = 'theme_mode';

  /// Thứ tự xoay vòng khi bấm nút giao diện trên title bar.
  static const List<ThemeMode> cycleOrder = [
    ThemeMode.system,
    ThemeMode.light,
    ThemeMode.dark,
  ];

  SharedPreferences? _prefs;
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final saved = _prefs?.getString(_keyThemeMode);
    _themeMode = ThemeMode.values.firstWhere(
      (mode) => mode.name == saved,
      orElse: () => ThemeMode.system,
    );
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    await _prefs?.setString(_keyThemeMode, mode.name);
  }

  Future<void> cycleThemeMode() {
    final next = cycleOrder[(cycleOrder.indexOf(_themeMode) + 1) % cycleOrder.length];
    return setThemeMode(next);
  }
}
