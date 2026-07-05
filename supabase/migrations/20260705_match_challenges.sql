-- Friend challenges: send, accept, reject, then play a synced human match.
-- Safe to re-run (uses IF NOT EXISTS / DROP POLICY IF EXISTS).

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

create index if not exists match_challenges_challenger
  on public.match_challenges (challenger_id, status);

alter table public.match_challenges enable row level security;

drop policy if exists "participants read challenges" on public.match_challenges;
create policy "participants read challenges"
  on public.match_challenges for select
  using (auth.uid() = challenger_id or auth.uid() = opponent_id);

drop policy if exists "challenger sends challenge" on public.match_challenges;
create policy "challenger sends challenge"
  on public.match_challenges for insert
  with check (auth.uid() = challenger_id);

drop policy if exists "participants update challenges" on public.match_challenges;
create policy "participants update challenges"
  on public.match_challenges for update
  using (auth.uid() = challenger_id or auth.uid() = opponent_id);

-- Matches: allow participants to create/update a row when accepting a challenge.
drop policy if exists "participants insert matches" on public.matches;
create policy "participants insert matches"
  on public.matches for insert
  with check (auth.uid() = player_a or auth.uid() = player_b);

drop policy if exists "participants update matches" on public.matches;
create policy "participants update matches"
  on public.matches for update
  using (auth.uid() = player_a or auth.uid() = player_b);
