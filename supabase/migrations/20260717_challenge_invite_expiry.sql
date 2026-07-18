-- Friend challenges expire after 6 hours; helpers for cleanup.

create or replace function public.expire_stale_match_challenges()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  n integer;
begin
  update public.match_challenges
  set status = 'expired',
      updated_at = now()
  where status = 'pending'
    and created_at < now() - interval '6 hours';
  get diagnostics n = row_count;
  return n;
end;
$$;

revoke all on function public.expire_stale_match_challenges() from public;
grant execute on function public.expire_stale_match_challenges() to authenticated;

-- Index to find stale pending invites quickly.
create index if not exists match_challenges_pending_created
  on public.match_challenges (created_at)
  where status = 'pending';
