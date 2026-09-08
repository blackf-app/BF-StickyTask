-- BF-StickyTask — dọn tombstone tự động bằng pg_cron.
--
-- Chạy 1 lần trong Supabase Dashboard → SQL Editor. Idempotent, chạy lại được.
-- TÁCH RIÊNG khỏi schema.sql có lý do: `create extension pg_cron` cần quyền cao
-- và có thể fail; nếu nhét chung thì nó làm hỏng luôn bước tạo bảng — mà tạo
-- bảng là thứ bắt buộc để app chạy, còn dọn rác thì không.
--
-- ── Vì sao xoá mềm rồi mới xoá cứng ──────────────────────────────────────────
-- Xoá note = `deleted = true` (tombstone), không DELETE ngay. Tombstone là thứ
-- mang lệnh xoá sang các máy khác: máy B còn note đó trong notes.json và nếu
-- không thấy tombstone thì lần push sau nó ĐẨY NOTE ĐÓ LÊN LẠI (nó không phân
-- biệt được "row đã bị xoá" với "row mình chưa sync bao giờ").
--
-- Vậy nên KHÔNG xoá cứng tombstone ngay trong ngày. Cửa sổ giữ phải dài hơn
-- thời gian một máy có thể offline. Mặc định 30 ngày, khớp với `_tombstoneTtl`
-- trong lib/data/note_repo.dart (client cũng dọn local sau 30 ngày).
--
-- Muốn đổi: sửa `default interval '30 days'` bên dưới rồi chạy lại file này.
-- Muốn xoá sạch NGAY (chấp nhận rủi ro note sống lại từ máy đang offline):
--   select public.purge_deleted_notes(interval '0');

-- ── Hàm dọn ──────────────────────────────────────────────────────────────────
-- Trả về số row đã xoá, để chạy tay cũng thấy được kết quả.
create or replace function public.purge_deleted_notes(
  retain interval default interval '30 days'
)
returns integer
language plpgsql
as $$
declare
  removed integer;
begin
  delete from public.notes
  where deleted
    and updated_at < now() - retain;
  get diagnostics removed = row_count;
  return removed;
end;
$$;

-- RLS đang mở cho anon (xem schema.sql), và Postgres mặc định grant EXECUTE cho
-- role `public` trên hàm mới → phải thu lại, đừng để client gọi được hàm dọn.
-- (Lưu ý: với policy `using (true)`, anon vốn đã DELETE được row qua REST —
-- đó là hệ quả của mô hình không đăng nhập, không phải do hàm này.)
revoke all on function public.purge_deleted_notes(interval) from public;
revoke all on function public.purge_deleted_notes(interval) from anon, authenticated;

-- ── pg_cron ──────────────────────────────────────────────────────────────────
-- Nếu câu này lỗi quyền: Dashboard → Database → Extensions → bật `pg_cron`.
create extension if not exists pg_cron;

-- Xoá job cũ trước cho idempotent. Bọc trong DO vì cron.unschedule ném lỗi khi
-- job chưa tồn tại (lần chạy đầu).
do $$
begin
  perform cron.unschedule('purge-deleted-notes');
exception
  when others then null;
end;
$$;

-- pg_cron trên Supabase chạy theo **UTC**.
-- 17:00 UTC = 00:00 giờ Việt Nam (UTC+7)  ← đang dùng
-- Muốn đúng 00:00 UTC thì đổi thành '0 0 * * *'.
select cron.schedule(
  'purge-deleted-notes',
  '0 17 * * *',
  $$select public.purge_deleted_notes()$$
);

-- ── Kiểm tra ─────────────────────────────────────────────────────────────────
-- Job đã đăng ký chưa:
--   select jobid, jobname, schedule, command, active from cron.job
--    where jobname = 'purge-deleted-notes';
--
-- Lịch sử chạy (mới nhất trước):
--   select status, start_time, end_time, return_message
--     from cron.job_run_details
--    where jobid = (select jobid from cron.job where jobname = 'purge-deleted-notes')
--    order by start_time desc limit 10;
--
-- Còn bao nhiêu tombstone, cũ nhất/mới nhất bao giờ:
--   select count(*) filter (where deleted)                       as tombstones,
--          count(*) filter (where not deleted)                   as con_song,
--          min(updated_at) filter (where deleted)                as tombstone_cu_nhat
--     from public.notes;
