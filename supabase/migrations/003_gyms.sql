-- のう筋（Noukin） Gyms & Gym Machines Schema & RLS
-- 店舗（gyms）と店舗別の共有機材リスト（gym_machines）を管理し、
-- ユーザープロファイル（user_profiles.selected_gym_id）と紐づける。

create table if not exists public.gyms (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.gym_machines (
  gym_id uuid not null references public.gyms(id) on delete cascade,
  machine_id text not null,
  is_available boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (gym_id, machine_id)
);

alter table public.user_profiles
  add column if not exists selected_gym_id uuid references public.gyms(id) on delete set null;

create index if not exists idx_gyms_name
  on public.gyms (name);

create index if not exists idx_gym_machines_gym_id
  on public.gym_machines (gym_id);

alter table public.gyms enable row level security;
alter table public.gym_machines enable row level security;

-- gyms: 認証済みユーザーは店舗の検索・登録・更新が可能
create policy "gyms_select_authenticated"
  on public.gyms for select
  to authenticated
  using (true);

create policy "gyms_insert_authenticated"
  on public.gyms for insert
  to authenticated
  with check (auth.uid() is not null);

create policy "gyms_update_authenticated"
  on public.gyms for update
  to authenticated
  using (auth.uid() is not null)
  with check (auth.uid() is not null);

-- gym_machines: 認証済みユーザーは店舗別機材リストの閲覧・登録・更新が可能
create policy "gym_machines_select_authenticated"
  on public.gym_machines for select
  to authenticated
  using (true);

create policy "gym_machines_insert_authenticated"
  on public.gym_machines for insert
  to authenticated
  with check (auth.uid() is not null);

create policy "gym_machines_update_authenticated"
  on public.gym_machines for update
  to authenticated
  using (auth.uid() is not null)
  with check (auth.uid() is not null);
