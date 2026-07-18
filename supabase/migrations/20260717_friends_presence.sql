-- Friends UX: presence heartbeat + friendship delete (cancel / deny / unfriend).

alter table public.profiles
  add column if not exists last_seen_at timestamptz;

comment on column public.profiles.last_seen_at is
  'Updated while the app is foregrounded; clients treat ~2 minutes as online.';

-- Participants may cancel a pending request, deny one, or unfriend.
drop policy if exists "participants delete friendships" on public.friendships;
create policy "participants delete friendships"
  on public.friendships for delete
  using (auth.uid() = requester or auth.uid() = addressee);

-- Requester can also cancel their own pending request via update→delete; delete covers it.
-- Keep addressee-only accept update as-is.
