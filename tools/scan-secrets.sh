#!/usr/bin/env bash
# Soi các file nhị phân xem có nhúng cấu hình Supabase THẬT không.
#
#   bash tools/scan-secrets.sh <file>...        # file không tồn tại thì bỏ qua
#   exit 0 = sạch, exit 1 = có dấu vết
#
# Dùng bởi tools/build-release.sh và .github/workflows/release.yml. Để ở một chỗ
# vì trước đây regex bị copy ra 3 nơi rồi lệch nhau — CI fail còn script local
# báo "sạch" trên đúng cùng một binary.
#
# ── Hai bug đã sửa, đừng làm lại ─────────────────────────────────────────────
# 1. `strings f | grep -q PAT` dưới `set -o pipefail`: grep -q thoát ngay khi
#    khớp → strings ăn SIGPIPE (141) → pipefail cho cả pipeline = fail → nhánh
#    if không chạy → LUÔN báo sạch. Ở đây dùng `grep -oE` (đọc hết input) rồi
#    xét chuỗi kết quả, không dùng -q sau pipe.
# 2. Regex `\.supabase\.co` khớp cả placeholder trong UI
#    ('https://<project-ref>.supabase.co' là hintText + text lỗi validate) →
#    false positive, fail mọi bản build. Project ref thật là 20 ký tự
#    [a-z0-9], nên đòi tối thiểu 16 ký tự liền trước '.supabase.co'.
set -uo pipefail

# Chỉ khớp GIÁ TRỊ THẬT, không khớp placeholder/ví dụ trong tài liệu:
#   sb_publishable_<>=10 ký tự   key thật (docs dùng dấu … nên không khớp)
#   sb_secret_<>=10 ký tự        secret key lỡ nhúng vào
#   <>=16 ký tự>.supabase.co     host thật ('<project-ref>' không khớp vì có '<'
#                                và 'abcdefgh' trong doc chỉ 8 ký tự)
PATTERN='sb_publishable_[A-Za-z0-9_-]{10,}|sb_secret_[A-Za-z0-9_-]{10,}|[a-z0-9]{16,}\.supabase\.co'

if [[ $# -eq 0 ]]; then
  echo "Dùng: bash tools/scan-secrets.sh <file>..." >&2
  exit 2
fi

found=0
checked=0

for f in "$@"; do
  [[ -f "$f" ]] || continue
  checked=$((checked + 1))
  hits="$(strings "$f" 2>/dev/null | grep -oE "$PATTERN" | sort -u || true)"
  if [[ -n "$hits" ]]; then
    found=1
    printf '   \033[31mRÒ\033[0m    %s\n' "$f"
    while IFS= read -r h; do
      [[ -n "$h" ]] || continue
      # Che bớt: đừng in nguyên key ra log CI.
      if [[ ${#h} -gt 20 ]]; then
        printf '           %s… (%d ký tự)\n' "${h:0:20}" "${#h}"
      else
        printf '           %s\n' "$h"
      fi
    done <<<"$hits"
  else
    printf '   \033[32msạch\033[0m  %s\n' "$f"
  fi
done

if [[ "$checked" -eq 0 ]]; then
  echo "   không có file nào để soi (đường dẫn sai?)" >&2
  exit 2
fi

exit "$found"
