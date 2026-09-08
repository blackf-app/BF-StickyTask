#!/usr/bin/env bash
# Build bản phát hành mà KHÔNG nhúng lib/env.dart vào binary.
#
#   bash tools/build-release.sh macos
#   bash tools/build-release.sh apk [--split-per-abi]
#   bash tools/build-release.sh windows      # chỉ chạy được trên máy Windows
#
# Vì sao cần script này: `Env` là `const String` nên giá trị trong lib/env.dart
# bị compile thẳng vào snapshot Dart. Đã kiểm chứng — cả
# `App.framework/.../kernel_blob.bin` (macOS) lẫn `assets/flutter_assets/
# kernel_blob.bin` (APK) đều chứa project ref + publishable key nếu build khi
# env.dart còn giá trị. Người khác cầm bản build đó là:
#   - app của họ tự nối vào project Supabase CỦA BẠN,
#   - và key của bạn nằm trong file, `strings` là ra.
#
# Code đã chặn ĐỌC env.dart ở release (SyncConfig.fromEnv → kDebugMode), nhưng
# chuỗi const vẫn có thể nằm lại trong snapshot. Nên cách chắc chắn là build khi
# env.dart đang rỗng — đó là việc script này làm, rồi trả file về nguyên trạng.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

target="${1:-}"
shift || true
case "$target" in
  macos|apk|appbundle|windows|linux) ;;
  *)
    echo "Dùng: bash tools/build-release.sh <macos|apk|appbundle|windows|linux> [flag build...]" >&2
    exit 2 ;;
esac

ENV_FILE="lib/env.dart"
STASH="$(mktemp -t bfst-env)"
restored=0

restore() {
  [[ "$restored" == "1" ]] && return
  restored=1
  if [[ -s "$STASH" ]]; then
    cp "$STASH" "$ENV_FILE"
    echo "→ đã trả lib/env.dart về nguyên trạng."
  fi
  rm -f "$STASH"
}
# Trả file về kể cả khi build fail hoặc bị Ctrl-C.
trap restore EXIT INT TERM

if [[ -f "$ENV_FILE" ]]; then
  cp "$ENV_FILE" "$STASH"
  cp lib/env.example.dart "$ENV_FILE"
  echo "→ lib/env.dart tạm thay bằng bản rỗng (env.example.dart) để không nhúng key."
else
  echo "→ không có lib/env.dart, build sạch sẵn."
fi

echo "→ flutter build $target --release $*"
echo
flutter build "$target" --release "$@"
echo

restore

# ── Kiểm chứng: soi binary xem còn dấu vết cấu hình không ─────────────────────
echo "→ Soi binary vừa build:"
leaked=0
check() { # <mô tả> <file>
  [[ -f "$2" ]] || return 0
  if strings "$2" 2>/dev/null | grep -qE 'sb_publishable_[A-Za-z0-9]|\.supabase\.co'; then
    printf '   \033[31mRÒ\033[0m   %s\n' "$1"
    leaked=1
  else
    printf '   \033[32msạch\033[0m %s\n' "$1"
  fi
}

case "$target" in
  macos)
    app=$(ls -d build/macos/Build/Products/Release/*.app 2>/dev/null | head -1)
    if [[ -n "$app" ]]; then
      check "$app/Contents/Frameworks/App.framework/App" \
            "$app/Contents/Frameworks/App.framework/App"
      check "$app (flutter_assets)" \
            "$app/Contents/Frameworks/App.framework/Resources/flutter_assets/kernel_blob.bin"
      echo "   → $app"
    fi ;;
  apk)
    for f in build/app/outputs/flutter-apk/*.apk; do
      [[ -f "$f" ]] || continue
      tmp=$(mktemp -d)
      unzip -o -q "$f" -d "$tmp" 'assets/flutter_assets/kernel_blob.bin' 'lib/*/libapp.so' 2>/dev/null || true
      hit=0
      while IFS= read -r g; do
        strings "$g" 2>/dev/null | grep -qE 'sb_publishable_[A-Za-z0-9]|\.supabase\.co' && hit=1
      done < <(find "$tmp" -type f 2>/dev/null)
      if [[ "$hit" == "1" ]]; then
        printf '   \033[31mRÒ\033[0m   %s\n' "$(basename "$f")"; leaked=1
      else
        printf '   \033[32msạch\033[0m %s\n' "$(basename "$f")"
      fi
      rm -rf "$tmp"
    done ;;
  *)
    echo "   (chưa có bước soi tự động cho '$target')" ;;
esac

echo
if [[ "$leaked" == "1" ]]; then
  echo "CẢNH BÁO: binary còn dấu vết Supabase URL/key — ĐỪNG phát hành bản này." >&2
  exit 1
fi
echo "Bản build không chứa URL/key. Người nhận tự nhập cấu hình của họ trong app."
