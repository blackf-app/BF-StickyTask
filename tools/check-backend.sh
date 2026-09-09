#!/usr/bin/env bash
# Soi backend Supabase và nói CHÍNH XÁC đang thiếu bước nào.
#
# Dùng khi app báo "Không kết nối được" mà không rõ vì sao:
#   bash tools/check-backend.sh                      # lấy URL+key đang dùng
#   bash tools/check-backend.sh <url> <publishable>  # chỉ định tay
#
# Thứ tự lấy cấu hình: tham số → prefs của app (macOS) → lib/env.dart
set -uo pipefail

BUNDLE_ID="${BUNDLE_ID:-com.blackface.bfstickytask}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROBE_ID="00000000-0000-4000-8000-00000000c0de"

url="${1:-}"
key="${2:-}"
source_desc="tham số dòng lệnh"

# ── prefs của app ─────────────────────────────────────────────────────────────
# App đã bỏ app-sandbox để tự cập nhật được (xem macos/Runner/Release.entitlements),
# nên prefs nằm ở ~/Library/Preferences. Vẫn thử container cũ để script này
# chạy được với bản app cài từ trước.
plist="$HOME/Library/Preferences/$BUNDLE_ID.plist"
if [[ ! -f "$plist" ]]; then
  plist="$HOME/Library/Containers/$BUNDLE_ID/Data/Library/Preferences/$BUNDLE_ID.plist"
fi
if [[ -z "$url" || -z "$key" ]] && [[ -f "$plist" ]]; then
  p_url=$(/usr/libexec/PlistBuddy -c "Print :flutter.sync_url" "$plist" 2>/dev/null || true)
  p_key=$(/usr/libexec/PlistBuddy -c "Print :flutter.sync_publishable_key" "$plist" 2>/dev/null || true)
  if [[ -n "$p_url" && -n "$p_key" ]]; then
    url="$p_url"; key="$p_key"; source_desc="prefs của app (đã Lưu trong app)"
  fi
fi

# ── lib/env.dart (giá trị điền sẵn) ───────────────────────────────────────────
if [[ -z "$url" || -z "$key" ]] && [[ -f "$ROOT/lib/env.dart" ]]; then
  e_url=$(python3 -c "
import re,sys
t=open('$ROOT/lib/env.dart').read()
m=re.search(r\"supabaseUrl\s*=\s*'([^']*)'\",t); print(m.group(1) if m else '')" 2>/dev/null || true)
  e_key=$(python3 -c "
import re,sys
t=open('$ROOT/lib/env.dart').read()
m=re.search(r\"supabasePublishableKey\s*=\s*'([^']*)'\",t); print(m.group(1) if m else '')" 2>/dev/null || true)
  if [[ -n "$e_url" && -n "$e_key" ]]; then
    url="$e_url"; key="$e_key"; source_desc="lib/env.dart"
  fi
fi

if [[ -z "$url" || -z "$key" ]]; then
  echo "Không tìm được URL + publishable key."
  echo "Chạy: bash tools/check-backend.sh <url> <publishable-key>"
  exit 2
fi

url="${url%/}"
ref="${url#https://}"; ref="${ref%%.*}"

echo "Cấu hình lấy từ : $source_desc"
echo "Project         : $ref"
echo "Key             : ${key:0:22}… (${#key} ký tự)"
echo

fail=0
say_ok()   { printf '  \033[32mOK\033[0m    %s\n' "$1"; }
say_bad()  { printf '  \033[31mLỖI\033[0m   %s\n' "$1"; fail=1; }
say_warn() { printf '  \033[33mCHÚ Ý\033[0m %s\n' "$1"; }

req() { # method path [body] -> "<http_code>\n<body>"
  local m="$1" p="$2" b="${3:-}"
  if [[ -n "$b" ]]; then
    curl -sS -m 25 -o /tmp/cb_body -w '%{http_code}' -X "$m" "$url$p" \
      -H "apikey: $key" -H "Authorization: Bearer $key" \
      -H 'Content-Type: application/json' \
      -H 'Prefer: resolution=merge-duplicates' -d "$b" 2>/dev/null
  else
    curl -sS -m 25 -o /tmp/cb_body -w '%{http_code}' -X "$m" "$url$p" \
      -H "apikey: $key" -H "Authorization: Bearer $key" 2>/dev/null
  fi
}

# 1) key + mạng
echo "1. Key và kết nối"
code=$(req GET "/rest/v1/")
if [[ "$code" == "000" ]]; then
  say_bad "không gọi được $url — kiểm tra mạng hoặc URL."
  exit 1
elif [[ "$code" == "401" || "$code" == "403" ]]; then
  # root cần quyền, nhưng 401 ở đây chưa chắc là key sai → thử tiếp ở bước 2
  say_warn "endpoint gốc trả $code (bình thường, nó cần quyền cao hơn)."
else
  say_ok "gọi được REST API (HTTP $code)."
fi

# 2) bảng notes
echo "2. Bảng public.notes"
code=$(req GET "/rest/v1/notes?select=id&limit=1")
body=$(cat /tmp/cb_body)
if [[ "$code" == "200" ]]; then
  say_ok "bảng tồn tại và đọc được."
elif grep -q "PGRST205\|does not exist" <<<"$body"; then
  say_bad "chưa có bảng notes → chạy supabase/schema.sql trong SQL Editor."
  echo
  echo "  https://supabase.com/dashboard/project/$ref/sql/new"
  exit 1
elif [[ "$code" == "401" ]]; then
  say_bad "key bị từ chối (HTTP 401): $body"
  say_warn "kiểm tra lại publishable key ở Project Settings → API keys."
  exit 1
else
  say_bad "HTTP $code: $body"
fi

# 3) schema đã migrate chưa (cột user_id của bản cũ)
echo "3. Schema đã migrate chưa"
code=$(req GET "/rest/v1/notes?select=user_id&limit=1")
body=$(cat /tmp/cb_body)
if grep -q "42703\|user_id.*does not exist\|does not exist.*user_id" <<<"$body"; then
  say_ok "cột user_id đã bị bỏ → schema.sql bản mới đã chạy."
elif [[ "$code" == "200" ]]; then
  say_bad "cột user_id VẪN CÒN → đang là schema cũ (RLS theo auth.uid())."
  say_warn "app không đăng nhập nên auth.uid() là NULL ⇒ mọi lệnh ghi bị chặn."
  echo
  echo "  Mở SQL Editor rồi dán toàn bộ nội dung supabase/schema.sql:"
  echo "  https://supabase.com/dashboard/project/$ref/sql/new"
  echo
else
  say_warn "không kết luận được (HTTP $code): $body"
fi

# 4) quyền ghi — thứ app thực sự cần
echo "4. Quyền ghi (RLS)"
now=$(python3 -c "import datetime;print(datetime.datetime.now(datetime.timezone.utc).isoformat())")
code=$(req POST "/rest/v1/notes?on_conflict=id" \
  "[{\"id\":\"$PROBE_ID\",\"text\":\"__probe__\",\"status\":\"current\",\"sort\":0,\"updated_at\":\"$now\",\"deleted\":true}]")
body=$(cat /tmp/cb_body)
if [[ "$code" == "200" || "$code" == "201" || "$code" == "204" ]]; then
  say_ok "ghi được → đồng bộ sẽ chạy."
  req DELETE "/rest/v1/notes?id=eq.$PROBE_ID" >/dev/null
  say_ok "đã dọn row probe."
elif grep -q "42501\|row-level security" <<<"$body"; then
  say_bad "RLS chặn ghi (42501) → schema.sql chưa chạy, hoặc policy chưa mở cho anon."
  echo
  echo "  https://supabase.com/dashboard/project/$ref/sql/new"
elif grep -q "23503\|foreign key" <<<"$body"; then
  say_bad "vướng foreign key user_id → auth.users (schema cũ). Chạy schema.sql bản mới."
else
  say_bad "HTTP $code: $body"
fi

echo
if [[ "$fail" == "0" ]]; then
  echo "→ Backend sẵn sàng. Trong app bấm 'Đồng bộ ngay'."
else
  echo "→ Còn việc phải làm ở trên. Chạy lại script này sau khi sửa."
fi
exit "$fail"
