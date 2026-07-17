-- Allow The Ladder daily (rack_size = 0) alongside standard 5–10 letter boards.
alter table public.daily_scores
  drop constraint if exists daily_scores_rack_size_check;

alter table public.daily_scores
  add constraint daily_scores_rack_size_check
  check (rack_size = 0 or rack_size between 5 and 10);
