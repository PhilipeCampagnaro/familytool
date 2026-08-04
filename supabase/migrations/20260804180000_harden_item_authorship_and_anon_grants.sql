-- Three hardening changes found in the pre-launch security review. None of them
-- changes what the app is allowed to do; each closes a gap between what the
-- policies intend and what the grants actually permit.

-- ---------------------------------------------------------------------------
-- 1. `created_by` is immutable on the three item tables.
-- ---------------------------------------------------------------------------
--
-- The delete policies on list_items, box_items and events gate on
-- `created_by = auth.uid()` (plus an admin branch), which is what implements
-- "Fremde Einträge löschen: member ❌, kid ❌, Gast ❌" in docs/backend.md. The
-- update policies only ask `can_write_*(parent_id)` and never mention
-- `created_by`, and `authenticated` holds an UPDATE grant on that column. So
-- the rule was two statements away from being bypassed:
--
--   update public.list_items set created_by = <me> where id = <someone else's>;
--   delete from public.list_items where id = <same row>;
--
-- Anyone who can write the list could take ownership of every other member's
-- items and delete them — including an external guest holding a can_edit share
-- link, who is not in the household at all.
--
-- A trigger rather than a narrower column grant: revoking UPDATE(created_by)
-- would also block the FK's `on delete set null`, which is how an account
-- deletion tidies up. The `auth.uid() is not null` guard is what lets that FK
-- action, and any service_role Edge Function, through — those are the
-- privileged paths, and neither has a JWT.
create or replace function public.enforce_item_author()
returns trigger language plpgsql set search_path = '' as $$
begin
  if (select auth.uid()) is not null
     and new.created_by is distinct from old.created_by then
    raise exception 'Der Ersteller eines Eintrags ist unveränderlich.'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

comment on function public.enforce_item_author() is
  'Pins list_items/box_items/events.created_by against a client UPDATE, so the '
  'delete policies that gate on it cannot be sidestepped by first reassigning '
  'authorship. Skipped when auth.uid() is null (FK cascade, service_role).';

revoke all on function public.enforce_item_author() from public, anon, authenticated;

drop trigger if exists list_items_enforce_author on public.list_items;
create trigger list_items_enforce_author
  before update on public.list_items
  for each row execute function public.enforce_item_author();

drop trigger if exists box_items_enforce_author on public.box_items;
create trigger box_items_enforce_author
  before update on public.box_items
  for each row execute function public.enforce_item_author();

drop trigger if exists events_enforce_author on public.events;
create trigger events_enforce_author
  before update on public.events
  for each row execute function public.enforce_item_author();

-- ---------------------------------------------------------------------------
-- 2. `anon` keeps no table privileges anywhere in `public`.
-- ---------------------------------------------------------------------------
--
-- Supabase bootstraps `alter default privileges in schema public grant all on
-- tables to anon, authenticated, service_role`, so every table in this schema
-- was born with full INSERT/UPDATE/DELETE for `anon`. Only calendar_connections
-- and calendar_connection_secrets ever revoked it (20260803101000:373,381).
--
-- Nothing is exploitable today, because no policy in this schema is `to anon`
-- and RLS denies what no policy allows. That is exactly the problem: the only
-- thing standing between an anonymous caller holding the publishable key — which
-- ships inside every installed copy of the app — and `guest_access` is the
-- continued absence of a policy. One `create policy ... to anon` written by
-- mistake, on any table, turns a missing grant revoke into a data breach.
--
-- The revoke costs nothing: `anon` has no legitimate read or write in this app.
-- Sign-up and sign-in go through GoTrue, and public.handle_new_user runs as
-- `security definer` on auth.users, not as `anon` over PostgREST.
revoke all on all tables in schema public from anon;
alter default privileges in schema public revoke all on tables from anon;

-- ---------------------------------------------------------------------------
-- 3. The feed tables actually get the grants their comment claims.
-- ---------------------------------------------------------------------------
--
-- 20260804090000_public_feeds.sql:104-109 says "No insert grant anywhere, and no
-- write grant at all on public_feeds", then only issues `grant` statements.
-- Column-level grants are additive — they cannot narrow the table-level `grant
-- all` the default privileges already handed out — so `authenticated` in fact
-- held INSERT/UPDATE/DELETE on public_feeds and UPDATE on every column of
-- family_feeds, `feed_id` and `created_by` included.
--
-- The three sibling tables did this correctly by revoking first
-- (20260803100300:115, 20260803100700:359, 20260803101000:373). This is the same
-- pattern, applied where it was missed. Feeds stay server-created: only an Edge
-- Function that has already fetched the source may write one.
revoke all on public.public_feeds from authenticated, anon;
revoke all on public.family_feeds from authenticated, anon;

grant select on public.public_feeds to authenticated;
grant select on public.family_feeds to authenticated;
grant update (display_name, color, position) on public.family_feeds to authenticated;
grant delete on public.family_feeds to authenticated;

-- `family_feeds.feed_id` is now unwritable by any client, which is what the
-- family_feeds_update policy assumed. Repointing a household's subscription at
-- another feed row — and thereby reading the resolved street address in its
-- config — is no longer expressible.
