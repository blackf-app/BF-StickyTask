import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// Template Flutter mặc định trả về `true`. Với app kiểu sticky note thì đó là
  /// bug: `windowManager.hide()` trên macOS là `orderOut`, nên cửa sổ vừa ẩn đi
  /// là AppKit coi như không còn window nào và tự terminate app — đúng hiện
  /// tượng "ẩn app xong là app chết".
  override func applicationShouldTerminateAfterLastWindowClosed(
    _ sender: NSApplication
  ) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(
    _ app: NSApplication
  ) -> Bool {
    return true
  }

  /// Cửa sổ đang ẩn mà bấm icon ở Dock thì hiện lại. Đây là đường lấy lại cửa
  /// sổ không phụ thuộc global hotkey (macOS không tự làm việc này cho một
  /// window bị `orderOut`).
  override func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag {
      if let window = NSApp.windows.first {
        window.setIsVisible(true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
      }
    }
    return true
  }
}
