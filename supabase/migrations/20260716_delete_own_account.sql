-- In-app account deletion (App Store 5.1.1(v)).
-- Cleans match rows that lack ON DELETE CASCADE, then removes auth.users
-- (which cascades to public.profiles and related data).

create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  delete from public.matchmaking_queue
  where user_id = uid;

  delete from public.match_submissions
  where user_id = uid
     or match_id in (
       select id from public.matches
       where player_a = uid or player_b = uid
     );

  update public.match_challenges
  set match_id = null
  where match_id in (
    select id from public.matches
    where player_a = uid or player_b = uid
  );

  delete from public.matches
  where player_a = uid or player_b = uid;

  -- Cascades daily_scores, friendships, challenges, queue, etc.
  delete from public.profiles where id = uid;

  delete from auth.users where id = uid;
end;
$$;

revoke all on function public.delete_own_account() from public;
grant execute on function public.delete_own_account() to authenticated;
