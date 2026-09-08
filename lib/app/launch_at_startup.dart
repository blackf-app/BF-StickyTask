import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:win32_registry/win32_registry.dart';

/// Trạng thái của "mở app khi khởi động máy".
///
/// [supported] = false nghĩa là nền tảng/phiên bản OS này không làm được (xem
/// [LaunchAtStartup]); UI ẩn hẳn nút thay vì hiện một nút bấm không lên.
@immutable
class LaunchAtStartupState {
  const LaunchAtStartupState({
    this.supported = false,
    this.enabled = false,
    this.requiresApproval = false,
    this.error,
  });

  final bool supported;
  final bool enabled;

  /// Chỉ có trên macOS: app đã đăng ký login item nhưng user còn phải bật ở
  /// **System Settings → General → Login Items**. Không nói ra thì user bật
  /// trong app, thấy nút sáng, mà máy khởi động lại vẫn không thấy app.
  final bool requiresApproval;

  /// Lỗi lần thao tác gần nhất, để hiện trong tooltip. null = không có lỗi.
  final String? error;

  LaunchAtStartupState copyWith({String? error}) => LaunchAtStartupState(
        supported: supported,
        enabled: enabled,
        requiresApproval: requiresApproval,
        error: error,
      );
}

/// Bật/tắt "mở app khi khởi động máy" cho macOS và Windows.
///
/// Hai nền tảng đi hai đường hoàn toàn khác nhau:
///
/// - **macOS**: `SMAppService.mainApp` qua method channel (xem
///   `macos/Runner/LaunchAtLogin.swift`). App chạy sandbox nên KHÔNG ghi được
///   `~/Library/LaunchAgents` — cách mà phần lớn plugin Flutter dùng và chết
///   câm ở đây. SMAppService cần **macOS 13+**; macOS 12 (deployment target)
///   không có đường nào khác trong sandbox nên báo `supported = false`.
/// - **Windows**: ghi thẳng registry `…\CurrentVersion\Run` bằng Dart, không
///   cần code C++ trong runner.
///
/// Android/Linux: không hỗ trợ.
class LaunchAtStartup extends ChangeNotifier {
  LaunchAtStartup._();

  static final LaunchAtStartup instance = LaunchAtStartup._();

  /// Cùng tên với hằng trong `macos/Runner/LaunchAtLogin.swift`.
  @visibleForTesting
  static const MethodChannel channel =
      MethodChannel('bf_stickytask/launch_at_startup');

  // region Windows registry

  static const String _runKeyPath =
      r'Software\Microsoft\Windows\CurrentVersion\Run';

  /// Task Manager → tab Startup ghi trạng thái bật/tắt của user vào đây. Bỏ
  /// qua nó là báo "đang bật" trong khi Windows đã chặn.
  static const String _approvedKeyPath =
      r'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';

  static const String _valueName = 'BF-StickyTask';

  /// Đường dẫn exe, bọc ngoặc kép vì đường dẫn Windows hay có dấu cách.
  static String get _runValue => '"${Platform.resolvedExecutable}"';

  // endregion

  static bool get isPlatformSupported =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows);

  LaunchAtStartupState _state = const LaunchAtStartupState();

  LaunchAtStartupState get state => _state;
  bool get supported => _state.supported;
  bool get enabled => _state.enabled;

  /// Đọc trạng thái hiện tại. Gọi lúc bootstrap.
  Future<void> load() async {
    _apply(await _read());
  }

  Future<void> setEnabled(bool value) async {
    if (!_state.supported) return;
    _apply(await _write(value));
  }

  Future<void> toggle() => setEnabled(!_state.enabled);

  void _apply(LaunchAtStartupState next) {
    _state = next;
    notifyListeners();
  }

  // region Đọc/ghi theo nền tảng

  Future<LaunchAtStartupState> _read() async {
    if (!isPlatformSupported) return const LaunchAtStartupState();
    try {
      if (Platform.isWindows) return _readWindows();
      return _stateFrom(await channel.invokeMapMethod<String, Object?>('status'));
    } catch (e) {
      // Đọc lỗi thì coi như không hỗ trợ: nút không hiện, hơn là hiện một nút
      // bấm vào là lỗi.
      debugPrint('Không đọc được trạng thái mở-khi-khởi-động: $e');
      return const LaunchAtStartupState();
    }
  }

  Future<LaunchAtStartupState> _write(bool value) async {
    try {
      if (Platform.isWindows) return _writeWindows(value);
      return _stateFrom(
        await channel.invokeMapMethod<String, Object?>(
          'setEnabled',
          {'enabled': value},
        ),
      );
    } catch (e) {
      final message = e is PlatformException ? (e.message ?? e.code) : '$e';
      // Giữ nguyên trạng thái đã biết, chỉ gắn thêm lỗi để tooltip nói được.
      return _state.copyWith(error: message);
    }
  }

  static LaunchAtStartupState _stateFrom(Map<String, Object?>? map) {
    if (map == null) return const LaunchAtStartupState();
    return LaunchAtStartupState(
      supported: map['supported'] == true,
      enabled: map['enabled'] == true,
      requiresApproval: map['requiresApproval'] == true,
    );
  }

  RegistryKey _openRunKey({required bool write}) => CURRENT_USER.open(
        _runKeyPath,
        config: RegistryOpenConfig(
          access: write ? RegistryAccess.readWrite : RegistryAccess.read,
        ),
      );

  LaunchAtStartupState _readWindows() {
    final key = _openRunKey(write: true);
    try {
      final current = key.getString(_valueName);
      if (current == null) return const LaunchAtStartupState(supported: true);
      // App được cập nhật / chuyển thư mục thì giá trị cũ trỏ vào đường dẫn
      // không còn exe → tự sửa lại, đừng bắt user tắt-bật lại nút.
      if (current != _runValue) {
        key.setValue(_valueName, RegistryValue.string(_runValue));
      }
      return LaunchAtStartupState(supported: true, enabled: _isApproved());
    } finally {
      key.close();
    }
  }

  LaunchAtStartupState _writeWindows(bool value) {
    final key = _openRunKey(write: true);
    try {
      if (value) {
        key.setValue(_valueName, RegistryValue.string(_runValue));
      } else if (key.getValue(_valueName) != null) {
        key.removeValue(_valueName);
      }
    } finally {
      key.close();
    }
    _setApproved(value);
    return LaunchAtStartupState(supported: true, enabled: value);
  }

  /// Byte đầu của value trong `StartupApproved\Run`: số chẵn = cho chạy, số lẻ
  /// = user đã tắt ở Task Manager. Không có key/value = cho chạy.
  bool _isApproved() {
    try {
      final key = CURRENT_USER.open(_approvedKeyPath);
      try {
        final value = key.getBinary(_valueName);
        if (value == null || value.isEmpty) return true;
        return value[0].isEven;
      } finally {
        key.close();
      }
    } catch (_) {
      return true;
    }
  }

  /// Ghi lại quyết định của user vào `StartupApproved\Run`, để lần bật trong
  /// app gỡ luôn cái tắt cũ ở Task Manager. Key này có thể chưa tồn tại trên
  /// profile mới — không sao, thiếu nó nghĩa là "cho chạy".
  void _setApproved(bool approved) {
    try {
      final key = CURRENT_USER.open(
        _approvedKeyPath,
        config: const RegistryOpenConfig(access: RegistryAccess.readWrite),
      );
      try {
        if (!approved) {
          if (key.getValue(_valueName) != null) key.removeValue(_valueName);
          return;
        }
        // 12 byte: 4 byte cờ + 8 byte FILETIME lúc đổi. 2 = đang bật.
        final bytes = Uint8List(12)..[0] = 2;
        key.setValue(_valueName, RegistryValue.binary(bytes));
      } finally {
        key.close();
      }
    } catch (e) {
      debugPrint('Không ghi được StartupApproved: $e');
    }
  }

  // endregion
}
