-- BF-StickyTask — schema Supabase.
-- Chạy trong Supabase Dashboard → SQL Editor. Idempotent, chạy lại được,
-- và tự migrate bảng `notes` bản cũ (bản có `user_id` + RLS theo `auth.uid()`).
--
-- MÔ HÌNH TRUY CẬP: app KHÔNG đăng nhập. Client chỉ nhập Supabase URL +
-- publishable key rồi đồng bộ. Publishable key là key CÔNG KHAI (bản thay thế
-- cho anon key legacy) và không mang danh tính user, nên `auth.uid()` luôn NULL
-- ⇒ policy không thể scope theo user. Bảng này vì thế mở cho role `anon`.
--
-- Hệ quả phải biết: ai có project ref + publishable key đều đọc/ghi được TOÀN BỘ
-- note trong bảng. Ranh giới bảo mật duy nhất là giữ kín 2 thứ đó. Không dùng
-- project này cho dữ liệu cần riêng tư thật, và đừng đưa bảng khác vào project.

create table if not exists public.notes (
  id         uuid primary key,
  text       text not null default '',
  status     text not null default 'current' check (status in ('current', 'done')),
  -- fractional index: chèn giữa 2 dòng = trung bình cộng, kéo thả chỉ update 1 row
  sort       double precision not null default 0,
  created_at timestamptz not null default now(),
  done_at    timestamptz,
  -- mốc last-write-wins, do CLIENT ghi (không dùng trigger now() để LWW đúng)
  updated_at timestamptz not null default now(),
  -- tombstone: xoá mềm để lệnh xoá lan được sang máy khác
  deleted    boolean not null default false
);

-- ── Migration từ bản cũ (bảng đã tồn tại với user_id + FK auth.users) ─────────
-- Bỏ policy cũ trước, vì nó tham chiếu user_id nên không drop được cột khi còn.
drop policy if exists notes_own_rows on public.notes;
drop index if exists public.notes_user_updated_idx;
alter table public.notes drop column if exists user_id;

-- ── Migration: thêm trạng thái "in_progress" + group cho note ─────────────────
-- Constraint cũ chỉ cho 'current'/'done' — drop rồi tạo lại mới thêm được giá
-- trị. Tên constraint là tên Postgres tự sinh cho `check` khai báo inline ở
-- trên (dạng `<table>_<column>_check`).
alter table public.notes drop constraint if exists notes_status_check;
alter table public.notes add constraint notes_status_check
  check (status in ('current', 'in_progress', 'done'));

alter table public.notes add column if not exists group_id text not null default 'default';

-- ── Group (danh sách việc riêng, vd "Cá nhân" / "Công ty") ────────────────────
-- `id` là text chứ không phải uuid: group mặc định dùng id cố định 'default' để
-- mọi máy tự bootstrap ra cùng một group khi migrate note cũ.
create table if not exists public.groups (
  id         text primary key,
  name       text not null default '',
  sort       double precision not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted    boolean not null default false
);

-- ── RLS ───────────────────────────────────────────────────────────────────────
alter table public.notes enable row level security;
alter table public.groups enable row level security;

-- Mở cho anon: app không đăng nhập nên không có auth.uid() để scope theo.
drop policy if exists notes_public_access on public.notes;
create policy notes_public_access on public.notes
  for all
  to anon, authenticated
  using (true)
  with check (true);

drop policy if exists groups_public_access on public.groups;
create policy groups_public_access on public.groups
  for all
  to anon, authenticated
  using (true)
  with check (true);

grant select, insert, update, delete on public.notes to anon, authenticated;
grant select, insert, update, delete on public.groups to anon, authenticated;

-- Con trỏ pull incremental của client.
create index if not exists notes_updated_idx
  on public.notes (updated_at desc);
create index if not exists groups_updated_idx
  on public.groups (updated_at desc);

-- Realtime: cần cả publication (đẩy thay đổi) lẫn full replica identity
-- (để client nhận đủ field ở event UPDATE/DELETE).
alter table public.notes replica identity full;
alter table public.groups replica identity full;
do $$
begin
  alter publication supabase_realtime add table public.notes;
exception
  when duplicate_object then null;  -- đã add rồi
end $$;
do $$
begin
  alter publication supabase_realtime add table public.groups;
exception
  when duplicate_object then null;  -- đã add rồi
end $$;
