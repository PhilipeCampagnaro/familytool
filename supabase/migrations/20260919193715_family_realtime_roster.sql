-- Live updates, part two: the roster, and the calendar's own announcements.
--
-- Two things the first pass (20260911131118_family_realtime) left out, both
-- found on the first two-device test:
--
-- 1. **Somebody joining the household did not appear until a restart.** The
--    broadcast trigger covered the eight content tables and none of the four
--    that make up the household itself — `family_members`, `families`,
--    `profiles` and `family_invites` — so a member accepting an invitation
--    changed nothing any other device was listening for.
--
-- 2. **The calendar's announcements were refused.** A calendar change is the one
--    thing no trigger can announce (we store no events, so there is no row to
--    fire on), so `CalendarNotifier` sends it from the device with
--    `sendBroadcastMessage`. On a private channel Realtime authorizes that send
--    against an INSERT policy on `realtime.messages`, and the first migration
--    deliberately wrote none — so every one was dropped without an error.
--    The worry that stopped it then was a member spamming their own household
--    with fake "something changed" messages. That is still possible and is
--    bounded by what it buys: each message makes the other devices re-read
--    through RLS, which they can already make happen by editing a list.

-- ---------------------------------------------------------------------------
-- Who may send
-- ---------------------------------------------------------------------------

drop policy if exists "aporah members announce on their household channel" on realtime.messages;

create policy "aporah members announce on their household channel"
on realtime.messages
for insert
to authenticated
with check (
  (select realtime.topic()) = 'family:' || (select private.my_family_id())::text
  and extension = 'broadcast'
);

-- ---------------------------------------------------------------------------
-- What gets announced
-- ---------------------------------------------------------------------------

create or replace function private.broadcast_family_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  row_json jsonb;
  fams     uuid[] := '{}';
  fam      uuid;
begin
  row_json := to_jsonb(case when tg_op = 'DELETE' then old else new end);

  -- Most tables carry the household. The rest reach it the way their RLS does,
  -- so there is no second notion of ownership being invented here.
  fam := nullif(row_json ->> 'family_id', '')::uuid;
  if fam is null then
    if tg_table_name = 'list_items' then
      select l.family_id into fam
        from public.lists l where l.id = (row_json ->> 'list_id')::uuid;
    elsif tg_table_name = 'box_items' then
      select b.family_id into fam
        from public.boxes b where b.id = (row_json ->> 'box_id')::uuid;
    elsif tg_table_name = 'families' then
      fam := (row_json ->> 'id')::uuid;
    elsif tg_table_name = 'profiles' then
      -- A new name or face shows on every avatar in the household.
      select m.family_id into fam
        from public.family_members m where m.user_id = (row_json ->> 'id')::uuid
        limit 1;
    end if;
  end if;
  if fam is not null then fams := array[fam]; end if;

  -- Accepting an invitation moves a member row from their own household to the
  -- new one. Both rosters changed, and the old one is the one this would miss.
  -- Nested rather than one `and`: SQL does not promise to short-circuit, and
  -- `old.family_id` on a table without the column would raise — failing the
  -- write this trigger is only meant to describe.
  if tg_table_name = 'family_members' and tg_op = 'UPDATE' then
    if old.family_id is distinct from new.family_id and old.family_id is not null then
      fams := fams || old.family_id;
    end if;
  end if;

  -- **A failed broadcast must never fail the write.** See the first migration.
  foreach fam in array fams loop
    begin
      perform realtime.send(
        jsonb_build_object(
          'table', tg_table_name,
          'actor', coalesce(auth.uid()::text, '')
        ),
        'change',
        'family:' || fam::text,
        true
      );
    exception when others then
      null;
    end;
  end loop;

  return null;
end;
$$;

comment on function private.broadcast_family_change() is
  'AFTER trigger: announces "this table changed" on the row''s household topic. Carries no row content — receivers re-read through RLS.';

revoke all on function private.broadcast_family_change() from public, anon, authenticated;

do $$
declare t text;
begin
  foreach t in array array['family_members', 'families', 'profiles', 'family_invites'] loop
    execute format('drop trigger if exists broadcast_change on public.%I', t);
    execute format(
      'create trigger broadcast_change after insert or update or delete on public.%I '
      'for each row execute function private.broadcast_family_change()', t);
  end loop;
end $$;
