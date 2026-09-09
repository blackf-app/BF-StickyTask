#!/usr/bin/env bash
# Chuyển dữ liệu local giữa hai container sandbox (macOS) — CHỈ dùng khi ĐỔI
# BUNDLE ID.
#
# ĐỌC TRƯỚC: app **không còn chạy sandbox** (bỏ đi để tự cập nhật được, xem
# macos/Runner/Release.entitlements), nên đường dẫn dữ liệu bây giờ là
# ~/Library/Application Support/<id> chứ không nằm trong container nữa.
# Việc kéo dữ liệu từ container cũ sang chỗ mới đã làm TRONG APP, tự động và
# idempotent — xem `LocalStore._migrateFromSandboxContainer`
# (lib/data/local_store.dart) và `PrefsMigration` (lib/app/prefs_migration.dart).
#
# Script này còn giữ cho đúng một việc: bundle id đổi (vn.easygoing.stickytask →
# com.blackface.bfstickytask) từ thời còn sandbox, khi đó dữ liệu nằm trong
# container của id CŨ mà app không tự dò. Chạy nó TRƯỚC khi mở bản app mới, rồi
# app sẽ tự kéo tiếp sang ~/Library/Application Support.
#
# Idempotent: đã có notes.json ở đích thì không ghi đè (trừ khi --force).
set -euo pipefail

OLD_ID="${OLD_ID:-vn.easygoing.stickytask}"
NEW_ID="${NEW_ID:-com.blackface.bfstickytask}"
FORCE="${1:-}"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "Chỉ cần trên macOS (Windows/Android không đổi path theo bundle id)." >&2
  exit 0
fi

old_root="$HOME/Library/Containers/$OLD_ID/Data/Library"
new_root="$HOME/Library/Containers/$NEW_ID/Data/Library"
old_support="$old_root/Application Support/$OLD_ID"
new_support="$new_root/Application Support/$NEW_ID"

if [[ ! -d "$old_support" ]]; then
  echo "Không thấy dữ liệu cũ ở: $old_support"
  echo "→ Không có gì phải migrate."
  exit 0
fi

if pgrep -f "$OLD_ID|BF-StickyTask|StickyTask" >/dev/null 2>&1; then
  echo "App đang chạy — thoát app trước khi migrate để không mất thay đổi cuối." >&2
  exit 1
fi

mkdir -p "$new_support" "$new_root/Preferences"

# notes.json — nguồn sự thật của dữ liệu local
if [[ -f "$old_support/notes.json" ]]; then
  if [[ -f "$new_support/notes.json" && "$FORCE" != "--force" ]]; then
    echo "Đã có notes.json ở đích, bỏ qua (dùng --force để ghi đè):"
    echo "  $new_support/notes.json"
  else
    cp -p "$old_support/notes.json" "$new_support/notes.json"
    n=$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1])).get('notes',[])))" "$new_support/notes.json" 2>/dev/null || echo '?')
    echo "notes.json → $n note đã chuyển sang container mới."
  fi
fi

# SharedPreferences: window bounds, theme mode, always-on-top
old_plist="$old_root/Preferences/$OLD_ID.plist"
new_plist="$new_root/Preferences/$NEW_ID.plist"
if [[ -f "$old_plist" ]]; then
  if [[ -f "$new_plist" && "$FORCE" != "--force" ]]; then
    echo "Đã có prefs ở đích, bỏ qua."
  else
    cp -p "$old_plist" "$new_plist"
    echo "prefs → window bounds / theme / always-on-top đã chuyển."
  fi
fi

echo
echo "Xong. Container cũ vẫn còn nguyên làm backup:"
echo "  $HOME/Library/Containers/$OLD_ID"
echo "Chắc chắn app mới chạy đúng rồi thì xoá tay thư mục đó."
