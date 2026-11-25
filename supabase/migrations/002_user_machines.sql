-- のう筋（Noukin） User Available Machines Schema & RLS
-- ユーザーアカウント単位で利用可能なマシン（ジム設置機材）を保存する。
-- 将来的なジム単位の機材自動補完への拡張を見据え、user_id と machine_id で正規化して管理する。

create table if not exists public.user_machines (
  user_id uuid not null references auth.users(id) on delete cascade,
  machine_id text not null,
  is_available boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (user_id, machine_id)
);

create index if not exists idx_user_machines_user_id
  on public.user_machines (user_id);

alter table public.user_machines enable row level security;

create policy "user_machines_select_own"
  on public.user_machines for select
  using (auth.uid() = user_id);

create policy "user_machines_insert_own"
  on public.user_machines for insert
  with check (auth.uid() = user_id);

create policy "user_machines_update_own"
  on public.user_machines for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "user_machines_delete_own"
  on public.user_machines for delete
  using (auth.uid() = user_id);
