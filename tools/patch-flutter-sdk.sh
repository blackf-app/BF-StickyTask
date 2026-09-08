#!/usr/bin/env bash
# Vá Flutter SDK để build được Android.
#
# Flutter 3.47.2 không compile được `flutter.groovy` của chính nó: file Groovy đó
# import class Kotlin cùng included-build (com.flutter.gradle.BaseApplicationNameHandler)
# nhưng Gradle không đưa output của compileKotlin vào classpath của compileGroovy,
# nên MỌI bản Android build fail ở task `:gradle:compileGroovy` — kể cả project
# `flutter create` trắng. Upstream: flutter/flutter#173943, #176077.
#
# Patch nằm trong SDK nên `flutter upgrade` sẽ xoá → chạy lại script này sau khi upgrade.
# Idempotent, chạy lại nhiều lần vẫn an toàn.
#
#   bash tools/patch-flutter-sdk.sh
#
# Bỏ patch:
#   cd "$(dirname "$(dirname "$(command -v flutter)")")" && git checkout -- packages/flutter_tools/gradle/build.gradle.kts

set -euo pipefail

PATCH_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/flutter-sdk-groovy-classpath.patch"
TARGET="packages/flutter_tools/gradle/build.gradle.kts"

# Thứ tự dò SDK: $FLUTTER_ROOT → flutter trong PATH → ~/development/flutter
if [[ -n "${FLUTTER_ROOT:-}" && -d "$FLUTTER_ROOT" ]]; then
  FLUTTER_ROOT="$(cd "$FLUTTER_ROOT" && pwd)"
elif FLUTTER_BIN="$(command -v flutter 2>/dev/null)"; then
  FLUTTER_ROOT="$(cd "$(dirname "$(dirname "$FLUTTER_BIN")")" && pwd)"
elif [[ -d "$HOME/development/flutter" ]]; then
  FLUTTER_ROOT="$HOME/development/flutter"
else
  echo "Không tìm thấy Flutter SDK. Set FLUTTER_ROOT rồi chạy lại." >&2
  exit 1
fi

if [[ ! -f "$FLUTTER_ROOT/$TARGET" ]]; then
  echo "Không thấy $TARGET trong $FLUTTER_ROOT — Flutter SDK đã đổi layout?" >&2
  exit 1
fi

cd "$FLUTTER_ROOT"

if grep -q "PATCH (local)" "$TARGET"; then
  echo "SDK đã được vá rồi ($FLUTTER_ROOT) — không làm gì."
  exit 0
fi

git apply --check "$PATCH_FILE" 2>/dev/null || {
  echo "Patch không áp được vào bản Flutter này ($(git rev-parse --short HEAD))." >&2
  echo "Có thể upstream đã sửa — thử 'flutter build apk' trước khi vá tay." >&2
  exit 1
}

git apply "$PATCH_FILE"
echo "Đã vá $FLUTTER_ROOT/$TARGET"
