/// Giá trị ĐIỀN SẴN cho lần chạy đầu (tuỳ chọn).
///
/// App không còn cần file này: cấu hình đồng bộ nhập trực tiếp trong app
/// (icon mây trên title bar → Supabase URL + publishable key) và được lưu vào
/// SharedPreferences. File này chỉ để máy dev không phải nhập tay lần đầu —
/// chưa có gì trong prefs thì `SyncConfigStore` lấy từ đây.
///
/// Copy thành `lib/env.dart` (đã gitignore) rồi điền, hoặc bỏ qua hoàn toàn.
class Env {
  Env._();

  static const String supabaseUrl = '';

  /// Publishable key (`sb_publishable_...`) — key CÔNG KHAI, bản thay thế cho
  /// anon key legacy. Nó không mang danh tính user, nên bảng `notes` mở cho
  /// role `anon` (xem `supabase/schema.sql`): ai có project ref + key này đều
  /// đọc/ghi được toàn bộ note. Đừng đặt secret key (`sb_secret_...`) vào đây.
  static const String supabasePublishableKey = '';

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
