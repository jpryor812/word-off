-- Peek whether another player is waiting in Quick Match (does not enqueue caller).
create or replace function public.matchmaking_someone_waiting()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.matchmaking_queue
    where status = 'waiting'
      and user_id is distinct from auth.uid()
      and enqueued_at >= now() - interval '20 seconds'
  );
$$;

grant execute on function public.matchmaking_someone_waiting() to authenticated;
