-- Device tokens for APNs remote push (challenges, friend requests).

create table if not exists public.device_tokens (
  user_id uuid not null references public.profiles (id) on delete cascade,
  token text not null,
  platform text not null default 'ios',
  environment text not null default 'production'
    check (environment in ('sandbox', 'production')),
  updated_at timestamptz not null default now(),
  primary key (user_id, token)
);

create index if not exists device_tokens_user
  on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;

drop policy if exists "users manage own device tokens" on public.device_tokens;
create policy "users manage own device tokens"
  on public.device_tokens for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
