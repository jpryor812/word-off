-- Worded Supabase schema
-- Run in the Supabase SQL editor (or `supabase db push`) on a fresh project.

-- =========================================================================
-- Profiles
-- =========================================================================
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text not null unique check (char_length(username) between 3 and 20),
  country text,
  is_premium boolean not null default false,
  badge_stats jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "profiles are readable by everyone"
  on public.profiles for select using (true);

create policy "users insert own profile"
  on public.profiles for insert with check (auth.uid() = id);

create policy "users update own profile"
  on public.profiles for update using (auth.uid() = id);

-- =========================================================================
-- Daily leaderboard scores (one row per user/day/rack size)
-- =========================================================================
create table if not exists public.daily_scores (
  user_id uuid not null references public.profiles (id) on delete cascade,
  day date not null,
  rack_size int not null check (rack_size between 5 and 10),
  score int not null check (score >= 0),
  best_word text,
  best_word_score int,
  created_at timestamptz not null default now(),
  primary key (user_id, day, rack_size)
);

create index if not exists daily_scores_board
  on public.daily_scores (day, rack_size, score desc);

alter table public.daily_scores enable row level security;

create policy "daily scores readable by everyone"
  on public.daily_scores for select using (true);

create policy "users insert own scores"
  on public.daily_scores for insert with check (auth.uid() = user_id);

create policy "users upsert own scores"
  on public.daily_scores for update using (auth.uid() = user_id);

-- =========================================================================
-- Friends (mutual accept)
-- =========================================================================
create table if not exists public.friendships (
  requester uuid not null references public.profiles (id) on delete cascade,
  addressee uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  primary key (requester, addressee),
  check (requester <> addressee)
);

alter table public.friendships enable row level security;

create policy "participants read friendships"
  on public.friendships for select
  using (auth.uid() = requester or auth.uid() = addressee);

create policy "users send requests"
  on public.friendships for insert with check (auth.uid() = requester);

create policy "addressee accepts"
  on public.friendships for update using (auth.uid() = addressee);

-- =========================================================================
-- Matchmaking queue + matches (for human PvP; v1 client falls back to AI)
-- =========================================================================
create table if not exists public.matchmaking_queue (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  enqueued_at timestamptz not null default now(),
  status text not null default 'waiting'
    check (status in ('waiting', 'matched', 'cancelled')),
  match_id uuid references public.matches (id) on delete set null
);

alter table public.matchmaking_queue enable row level security;

create policy "users read own queue entry"
  on public.matchmaking_queue for select using (auth.uid() = user_id);

create policy "users manage own queue entry"
  on public.matchmaking_queue for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

create index if not exists matchmaking_queue_waiting_fifo
  on public.matchmaking_queue (enqueued_at asc)
  where status = 'waiting';

create table if not exists public.matches (
  id uuid primary key default gen_random_uuid(),
  player_a uuid not null references public.profiles (id),
  player_b uuid not null references public.profiles (id),
  seed text not null,                     -- both clients derive identical racks
  state text not null default 'active' check (state in ('active', 'complete', 'abandoned')),
  winner uuid,
  created_at timestamptz not null default now()
);

alter table public.matches enable row level security;

create policy "participants read matches"
  on public.matches for select
  using (auth.uid() = player_a or auth.uid() = player_b);

create table if not exists public.match_submissions (
  match_id uuid not null references public.matches (id) on delete cascade,
  round int not null,
  user_id uuid not null references public.profiles (id),
  word text,
  submitted_ms int,                        -- ms into the round
  created_at timestamptz not null default now(),
  primary key (match_id, round, user_id)
);

alter table public.match_submissions enable row level security;

create policy "participants read submissions"
  on public.match_submissions for select
  using (exists (
    select 1 from public.matches m
    where m.id = match_id and (auth.uid() = m.player_a or auth.uid() = m.player_b)
  ));

create policy "participants write own submissions"
  on public.match_submissions for insert
  with check (auth.uid() = user_id and exists (
    select 1 from public.matches m
    where m.id = match_id and (auth.uid() = m.player_a or auth.uid() = m.player_b)
  ));

-- =========================================================================
-- Friend challenges (username → accept/reject → human match)
-- =========================================================================
create table if not exists public.match_challenges (
  id uuid primary key default gen_random_uuid(),
  challenger_id uuid not null references public.profiles (id) on delete cascade,
  opponent_id uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'rejected', 'cancelled', 'expired')),
  seed text not null,
  match_id uuid references public.matches (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (challenger_id <> opponent_id)
);

create index if not exists match_challenges_opponent_pending
  on public.match_challenges (opponent_id, status)
  where status = 'pending';

alter table public.match_challenges enable row level security;

create policy "participants read challenges"
  on public.match_challenges for select
  using (auth.uid() = challenger_id or auth.uid() = opponent_id);

create policy "challenger sends challenge"
  on public.match_challenges for insert
  with check (auth.uid() = challenger_id);

create policy "participants update challenges"
  on public.match_challenges for update
  using (auth.uid() = challenger_id or auth.uid() = opponent_id);

create policy "participants insert matches"
  on public.matches for insert
  with check (auth.uid() = player_a or auth.uid() = player_b);

create policy "participants update matches"
  on public.matches for update
  using (auth.uid() = player_a or auth.uid() = player_b);
