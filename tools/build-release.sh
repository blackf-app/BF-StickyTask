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
# Logic soi nằm ở tools/scan-secrets.sh (một chỗ duy nhất) — xem comment trong
# file đó về bug pipefail/SIGPIPE và bug false-positive placeholder.
echo "→ Soi binary vừa build:"
targets=()

case "$target" in
  macos)
    app=$(ls -d build/macos/Build/Products/Release/*.app 2>/dev/null | head -1)
    if [[ -n "$app" ]]; then
      # Release là AOT: code Dart nằm trong App.framework/App, không có
      # kernel_blob.bin (đó là bản debug/JIT). Truyền cả hai, thiếu thì bỏ qua.
      targets+=("$app/Contents/Frameworks/App.framework/App")
      targets+=("$app/Contents/Frameworks/App.framework/Resources/flutter_assets/kernel_blob.bin")
    fi ;;
  windows)
    while IFS= read -r f; do targets+=("$f"); done \
      < <(find build/windows -type f \( -name 'app.so' -o -name '*.exe' -o -name 'kernel_blob.bin' \) 2>/dev/null)
    ;;
  apk|appbundle)
    outdir=build/app/outputs
    while IFS= read -r pkg; do
      tmp=$(mktemp -d)
      unzip -o -q "$pkg" -d "$tmp" \
        'assets/flutter_assets/kernel_blob.bin' 'lib/*/libapp.so' \
        'base/assets/flutter_assets/kernel_blob.bin' 'base/lib/*/libapp.so' 2>/dev/null || true
      # Giải nén ra rồi soi từng file, kèm tên gói cho dễ đọc.
      if [[ -n "$(find "$tmp" -type f 2>/dev/null)" ]]; then
        printf '   gói %s\n' "$(basename "$pkg")"
        while IFS= read -r g; do targets+=("$g"); done < <(find "$tmp" -type f)
      fi
    done < <(find "$outdir" -type f \( -name '*-release.apk' -o -name '*.aab' \) 2>/dev/null)
    ;;
  *)
    echo "   (chưa có bước soi tự động cho '$target')" ;;
esac

leaked=0
if [[ ${#targets[@]} -gt 0 ]]; then
  bash "$ROOT/tools/scan-secrets.sh" "${targets[@]}" || leaked=1
fi

echo
if [[ "$leaked" == "1" ]]; then
  echo "CẢNH BÁO: binary còn dấu vết Supabase URL/key — ĐỪNG phát hành bản này." >&2
  exit 1
fi
echo "Bản build không chứa URL/key. Người nhận tự nhập cấu hình của họ trong app."
