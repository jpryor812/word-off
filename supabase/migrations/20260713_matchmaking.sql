-- Random matchmaking queue: pair concurrent searchers within 20 seconds, else AI fallback client-side.
-- Safe to re-run.

alter table public.matchmaking_queue
  add column if not exists status text not null default 'waiting'
    check (status in ('waiting', 'matched', 'cancelled')),
  add column if not exists match_id uuid references public.matches (id) on delete set null;

drop policy if exists "queue readable by authed users" on public.matchmaking_queue;

drop policy if exists "users read own queue entry" on public.matchmaking_queue;
create policy "users read own queue entry"
  on public.matchmaking_queue for select
  using (auth.uid() = user_id);

create index if not exists matchmaking_queue_waiting_fifo
  on public.matchmaking_queue (enqueued_at asc)
  where status = 'waiting';

-- Pair the caller with the oldest waiting opponent, or enqueue and wait.
create or replace function public.enqueue_matchmaking()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_opponent uuid;
  v_match_id uuid;
  v_seed text;
  v_player_a uuid;
  v_player_b uuid;
  v_existing record;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  delete from public.matchmaking_queue
  where user_id = v_uid and status = 'matched';

  delete from public.matchmaking_queue
  where status = 'waiting'
    and enqueued_at < now() - interval '20 seconds';

  select status, match_id into v_existing
  from public.matchmaking_queue
  where user_id = v_uid;

  if found and v_existing.status = 'matched' and v_existing.match_id is not null then
    return public.matchmaking_status_payload(v_uid, v_existing.match_id);
  end if;

  select user_id into v_opponent
  from public.matchmaking_queue
  where status = 'waiting'
    and user_id <> v_uid
  order by enqueued_at asc
  limit 1
  for update skip locked;

  if v_opponent is not null then
    v_seed := gen_random_uuid()::text;
    v_player_a := least(v_uid, v_opponent);
    v_player_b := greatest(v_uid, v_opponent);

    insert into public.matches (player_a, player_b, seed, state)
    values (v_player_a, v_player_b, v_seed, 'active')
    returning id into v_match_id;

    update public.matchmaking_queue
    set status = 'matched', match_id = v_match_id, enqueued_at = now()
    where user_id = v_opponent;

    insert into public.matchmaking_queue (user_id, status, match_id, enqueued_at)
    values (v_uid, 'matched', v_match_id, now())
    on conflict (user_id) do update
      set status = 'matched', match_id = excluded.match_id, enqueued_at = excluded.enqueued_at;

    return public.matchmaking_status_payload(v_uid, v_match_id);
  end if;

  insert into public.matchmaking_queue (user_id, status, match_id, enqueued_at)
  values (v_uid, 'waiting', null, now())
  on conflict (user_id) do update
    set status = 'waiting', match_id = null, enqueued_at = now();

  return jsonb_build_object('status', 'waiting');
end;
$$;

create or replace function public.matchmaking_status_payload(p_user_id uuid, p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match record;
  v_opponent uuid;
begin
  select id, seed, player_a, player_b into v_match
  from public.matches
  where id = p_match_id;

  if not found then
    return jsonb_build_object('status', 'waiting');
  end if;

  if p_user_id = v_match.player_a then
    v_opponent := v_match.player_b;
  else
    v_opponent := v_match.player_a;
  end if;

  return jsonb_build_object(
    'status', 'matched',
    'match_id', v_match.id,
    'seed', v_match.seed,
    'opponent_id', v_opponent,
    'is_player_a', (p_user_id = v_match.player_a)
  );
end;
$$;

create or replace function public.get_matchmaking_status()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_row record;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  delete from public.matchmaking_queue
  where status = 'waiting'
    and enqueued_at < now() - interval '20 seconds';

  select status, match_id into v_row
  from public.matchmaking_queue
  where user_id = v_uid;

  if not found then
    return jsonb_build_object('status', 'idle');
  end if;

  if v_row.status = 'matched' and v_row.match_id is not null then
    return public.matchmaking_status_payload(v_uid, v_row.match_id);
  end if;

  return jsonb_build_object('status', v_row.status);
end;
$$;

create or replace function public.cancel_matchmaking()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.matchmaking_queue
  where user_id = auth.uid()
    and status = 'waiting';
end;
$$;

grant execute on function public.enqueue_matchmaking() to authenticated;
grant execute on function public.get_matchmaking_status() to authenticated;
grant execute on function public.cancel_matchmaking() to authenticated;
