-- Badge stats + daily rack size fix
-- Run this in the Supabase SQL editor on your existing project.

-- Store cumulative badge counters on each profile (synced from the app).
alter table public.profiles
  add column if not exists badge_stats jsonb not null default '{}'::jsonb;

comment on column public.profiles.badge_stats is
  'Cumulative badge counters: daily_max_word, pvp_max_word, speed_bonus, pvp_wins, daily_percentile_best, etc.';

-- Daily challenges are now 5–10 letters (was 6–12).
alter table public.daily_scores
  drop constraint if exists daily_scores_rack_size_check;

alter table public.daily_scores
  add constraint daily_scores_rack_size_check
  check (rack_size between 5 and 10);
