import Cocoa
import FlutterMacOS
import ServiceManagement

/// "Mở app khi khởi động máy" cho macOS — phía native của
/// `lib/app/launch_at_startup.dart`.
///
/// App chạy **sandbox** (xem Release.entitlements) nên KHÔNG ghi được vào
/// `~/Library/LaunchAgents` — đó là cách phần lớn plugin Flutter làm, và trong
/// sandbox nó chết câm: ghi file báo thành công vào container ảo, máy khởi
/// động lại thì không có gì chạy. Đường hợp lệ duy nhất là `SMAppService`,
/// Apple làm riêng cho login item của app sandbox.
///
/// `SMAppService` cần **macOS 13+**. Deployment target của project là 12.0 và
/// trong sandbox không còn API nào khác cho macOS 12, nên ở đó trả
/// `supported = false` và UI tự ẩn nút thay vì hiện một nút bấm không lên.
enum LaunchAtLogin {
  /// Trùng với `LaunchAtStartup.channel` bên Dart.
  static let channelName = "bf_stickytask/launch_at_startup"

  /// Gắn channel vào engine. Gọi trong `MainFlutterWindow.awakeFromNib`.
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "status":
        result(status())
      case "setEnabled":
        let arguments = call.arguments as? [String: Any]
        setEnabled(arguments?["enabled"] as? Bool ?? false, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func status() -> [String: Any] {
    guard #available(macOS 13.0, *) else {
      return ["supported": false, "enabled": false, "requiresApproval": false]
    }
    let status = SMAppService.mainApp.status
    // `.requiresApproval`: đã đăng ký nhưng user còn phải bật ở System Settings
    // → General → Login Items. Vẫn tính là "đang bật" để nút không nhảy ngược
    // về tắt, nhưng có cờ riêng để UI nói cho user biết còn thiếu bước đó.
    return [
      "supported": true,
      "enabled": status == .enabled || status == .requiresApproval,
      "requiresApproval": status == .requiresApproval,
    ]
  }

  private static func setEnabled(_ enabled: Bool, result: @escaping FlutterResult) {
    guard #available(macOS 13.0, *) else {
      result(
        FlutterError(
          code: "unsupported",
          message: "Tính năng này cần macOS 13 trở lên.",
          details: nil))
      return
    }

    let service = SMAppService.mainApp
    do {
      switch (enabled, service.status) {
      // Gọi register khi đã đăng ký, hoặc unregister khi chưa, đều throw —
      // trạng thái đã đúng rồi thì không đụng vào.
      case (true, .enabled), (true, .requiresApproval), (false, .notRegistered),
        (false, .notFound):
        break
      case (true, _):
        try service.register()
      case (false, _):
        try service.unregister()
      }
      result(status())
    } catch {
      result(
        FlutterError(
          code: "smAppService",
          message: error.localizedDescription,
          details: "status = \(service.status.rawValue)"))
    }
  }
}
