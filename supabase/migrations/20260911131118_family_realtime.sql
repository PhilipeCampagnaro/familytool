-- Live updates across a household's devices.
--
-- **Broadcast, not Postgres Changes, and the difference is the whole design.**
-- Supabase's `postgres_changes` re-runs every subscriber's RLS against every
-- changed row, so one shopping-list tick costs a policy evaluation per connected
-- device. That is affordable for one family and is the documented reason not to
-- build a product on it. `realtime.send` writes one message to one topic and the
-- authorization happens once, when a device joins.
--
-- **The message carries no row.** It names the table that changed and who
-- changed it, and nothing else. The receiving device re-reads through the same
-- repository it always uses, which goes through RLS — so a member who may not
-- see a private list learns that "lists changed" and still cannot read it. That
-- is deliberate: a payload with the row in it would be a second, parallel read
-- path with its own access rules to get wrong, and we would get it wrong.
--
-- What a member does learn is that *something* in the household changed and who
-- did it. Inside one family that is not a disclosure — the roster is already
-- visible and every row carries `created_by`.
--
-- **Guests are not covered.** Somebody outside the household with a share link
-- reads through `guest_access` and has a different `my_family_id()`, so they
-- never join this topic and their view of a shared list stays pull-only. Giving
-- them live updates means a per-shareable topic; see docs/production-plan.md.

-- ---------------------------------------------------------------------------
-- Who may listen
-- ---------------------------------------------------------------------------

-- One topic per household, `family:<uuid>`, private. `realtime.messages` already
-- has RLS on; without a policy the channel simply never authorizes, which is why
-- this is the piece that makes the whole thing work rather than a hardening pass
-- bolted on afterwards.
drop policy if exists "aporah members read their household channel" on realtime.messages;

create policy "aporah members read their household channel"
on realtime.messages
for select
to authenticated
using (
  (select realtime.topic()) = 'family:' || (select private.my_family_id())::text
);

-- No insert policy on purpose. Every message on this topic is written by the
-- trigger below, as postgres; a client that could broadcast could tell every
-- other device in the household that a list changed when it had not, which is at
-- best a wasted read storm and at worst a way to keep other people's apps busy.

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
  fam      uuid;
begin
  row_json := to_jsonb(case when tg_op = 'DELETE' then old else new end);

  -- Most content tables carry the household. The two item tables inherit it
  -- from the container they hang off — which is also exactly how their RLS
  -- reads, so there is no second notion of ownership being invented here.
  fam := nullif(row_json ->> 'family_id', '')::uuid;
  if fam is null then
    if tg_table_name = 'list_items' then
      select l.family_id into fam
        from public.lists l where l.id = (row_json ->> 'list_id')::uuid;
    elsif tg_table_name = 'box_items' then
      select b.family_id into fam
        from public.boxes b where b.id = (row_json ->> 'box_id')::uuid;
    end if;
  end if;

  if fam is null then return null; end if;

  -- **A failed broadcast must never fail the write.** The user's tick on a
  -- shopping list is the real work; telling the other phone about it is a
  -- courtesy, and a courtesy that can roll back a transaction is a bug waiting
  -- for the day Realtime has an outage.
  begin
    perform realtime.send(
      jsonb_build_object(
        'table', tg_table_name,
        -- So a device can ignore the echo of its own write. It already has the
        -- change on screen, and re-reading would fight the optimistic update
        -- that put it there.
        'actor', coalesce(auth.uid()::text, '')
      ),
      'change',
      'family:' || fam::text,
      true
    );
  exception when others then
    null;
  end;

  return null;
end;
$$;

comment on function private.broadcast_family_change() is
  'AFTER trigger: announces "this table changed" on the row''s household topic. Carries no row content — receivers re-read through RLS.';

revoke all on function private.broadcast_family_change() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Where it is attached
-- ---------------------------------------------------------------------------

-- Row-level rather than statement-level: a statement trigger cannot see the
-- rows, and without a row there is no household to address. Deleting a list with
-- fifty articles therefore fires fifty times; the client coalesces them, which is
-- the right place for it — one debounce there beats fifty different opinions here.
do $$
declare t text;
begin
  foreach t in array array[
    'lists', 'list_items', 'boxes', 'box_items', 'tasks', 'trackers',
    'tracker_checks', 'spends'
  ] loop
    execute format('drop trigger if exists broadcast_change on public.%I', t);
    execute format(
      'create trigger broadcast_change after insert or update or delete on public.%I '
      'for each row execute function private.broadcast_family_change()', t);
  end loop;
end $$;
