-- Aporah backend — Kalender-Verbindungen (external calendar providers).
--
-- The content migration already gave every calendar a `provider` and an
-- `external_id`. What was missing is the thing those two point *at*: the account
-- the calendar was pulled from, and the credential that lets a server read it.
-- This migration adds exactly that layer and nothing else — no new visibility
-- concept, no new sharing path. A synced calendar is a normal `calendars` row
-- with the same family/owner/visibility contract as a hand-made one.
--
-- Three things get added:
--
--   1. public.calendar_connections         — one row per connected ACCOUNT.
--   2. public.calendar_connection_secrets  — the OAuth refresh token / CalDAV
--                                            password. Unreadable by anyone but
--                                            service_role, and ciphertext even
--                                            for them.
--   3. columns on calendars / events       — the link from a provider's
--                                            sub-calendar and its events back to
--                                            the connection.
--
-- The security rule that shapes all of it: a refresh token is a standing
-- capability on someone's real Google account. It is strictly more dangerous
-- than any row in this database, so it gets stricter handling than `token_hash`
-- in share_links — that one is a hash and useless if leaked; these are live
-- credentials and must never be stored in a form a database dump can use.

-- ---------------------------------------------------------------------------
-- Connections
--
-- Scoped to the household, not to a person: a connected school calendar is the
-- family's, and it must keep working while the parent who set it up is away.
-- `created_by` records who attached it, for the "Wer hat das verbunden?" line
-- and for the permission checks further down.
--
-- `provider` uses the SAME vocabulary as calendars.provider, deliberately —
-- including 'outlook' rather than 'microsoft'. The old web app carried both
-- spellings (display layer said outlook, OAuth layer said microsoft) and needed
-- an isMicrosoft() helper in five files to paper over it. One word, one meaning.
-- ---------------------------------------------------------------------------

create table public.calendar_connections (
  id           uuid primary key default gen_random_uuid(),
  family_id    uuid not null references public.families (id) on delete cascade,

  provider     text not null
                 check (provider in ('google', 'outlook', 'icloud',
                                     'iserv', 'ferien', 'abfall')),
  -- How the server talks to it. Derivable from `provider` today, stored anyway
  -- because it is what the sync function branches on, and because a provider
  -- can change transport — Apple shipping an OAuth calendar API would flip
  -- icloud from caldav to oauth without needing a new provider value.
  auth_type    text not null
                 check (auth_type in ('oauth', 'caldav', 'public')),

  -- The stable identity of the account, used for dedup on re-connect: the
  -- e-mail (google/outlook), the CalDAV username (icloud/iserv), the two-letter
  -- Bundesland (ferien) or the resolved area key (abfall).
  external_account text not null check (length(trim(external_account)) between 1 and 400),

  -- What the user sees and may rename — e.g. "Google (lea@example.com)".
  -- Renaming it must never touch external_account.
  display_name text not null check (length(trim(display_name)) between 1 and 120),

  -- Non-secret provider settings: the discovered CalDAV calendar-home URL, the
  -- IServ server base, the resolved Abfall vendor/town/street config, a pasted
  -- ICS fallback URL. Everything in here is readable by the household — so a
  -- password or a token must never be put here. That is what the secrets table
  -- is for, and the reason it is a separate table rather than a jsonb key.
  config       jsonb not null default '{}'::jsonb,

  -- Which of the account's sub-calendars to sync. null = all of them (the state
  -- before the user has ever opened the checklist); an empty array = none.
  selected_calendars jsonb,

  -- Feeds we can never write back to: Ferien, Abfall, school calendars. Copied
  -- onto every calendars row the connection creates, where can_write_calendar()
  -- already refuses writes.
  is_read_only boolean not null default false,

  -- Sync state. `status` is what the UI turns into the "Erneut verbinden"
  -- banner; it is written by the sync function and never by the client.
  status        text not null default 'active'
                  check (status in ('active', 'reconnect_required', 'error')),
  status_detail text,
  last_synced_at timestamptz,

  created_by   uuid references auth.users (id) on delete set null,
  position     integer not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),

  -- Connecting the same account twice is an update, not a second row.
  unique (family_id, provider, external_account),
  -- The target of the composite foreign key from calendars, the same trick the
  -- *_shares tables use: it makes "a calendar pointing at another household's
  -- connection" unrepresentable rather than merely checked.
  unique (id, family_id),

  -- Public feeds have nothing to authenticate with and nothing to write to.
  check (auth_type <> 'public' or is_read_only)
);

-- ---------------------------------------------------------------------------
-- Secrets
--
-- Two independent barriers, because either one alone has a known failure mode:
--
--   1. No RLS policy exists on this table, for any command, and every privilege
--      is revoked from `authenticated` and `anon`. PostgREST therefore cannot
--      read it at all — not one column, not through a view, not through a join.
--      (A missing policy is already a denial; the explicit revoke is what
--      survives a future migration that adds a policy by mistake.)
--
--   2. The values are ciphertext. Every credential column below holds an
--      AES-256-GCM envelope produced by the Edge Functions —
--      "v1.<iv>.<ciphertext>", base64url — under CALENDAR_SECRET_KEY, which
--      lives in the function secrets and never in the database. So a database
--      dump, a leaked service_role key or a mis-scoped backup yields no usable
--      credential.
--
-- Barrier 1 protects against a policy mistake; barrier 2 protects against
-- everything that happens once the database is out of our hands. Rotating
-- CALENDAR_SECRET_KEY invalidates every stored credential, which degrades to
-- "all connections must be reconnected" — annoying, never dangerous.
--
-- token_expires_at is not itself a secret, but it lives here so the refresh path
-- reads exactly one row and so nothing about the token's lifecycle is visible to
-- the client. The client learns the same fact from calendar_connections.status.
-- ---------------------------------------------------------------------------

create table public.calendar_connection_secrets (
  connection_id    uuid primary key
                     references public.calendar_connections (id) on delete cascade,
  access_token     text,
  refresh_token    text,
  caldav_password  text,
  token_expires_at timestamptz,
  updated_at       timestamptz not null default now()
);

comment on table public.calendar_connection_secrets is
  'OAuth-Refresh-Tokens und CalDAV-Passwörter. Nur service_role, nur verschlüsselt (AES-256-GCM, Schlüssel CALENDAR_SECRET_KEY in den Function-Secrets).';

-- ---------------------------------------------------------------------------
-- The link from calendars and events back to a connection
--
-- `calendars.external_id` already existed; it just had nothing to be unique
-- against. With connection_id it does: one provider sub-calendar maps to exactly
-- one Aporah calendar row, which is what makes the sync an upsert instead of an
-- ever-growing pile of duplicates.
--
-- sync_token sits on the CALENDAR, not the connection, because that is the
-- granularity every provider actually uses: Google's nextSyncToken is per
-- calendarId, Graph's deltaLink per calendar, CalDAV's ctag per collection. The
-- old web app declared one sync_token per connection and consequently never
-- managed to use it — every read stayed a full-window fetch.
-- ---------------------------------------------------------------------------

alter table public.calendars
  add column connection_id   uuid,
  -- Mirrors family_id so the composite foreign key below can prove the
  -- connection belongs to the same household. Maintained by a trigger, never by
  -- the client; null whenever connection_id is null, which is what makes the FK
  -- (MATCH SIMPLE) skip local calendars entirely.
  add column family_check_id uuid,
  add column sync_token      text,
  add column last_synced_at  timestamptz;

alter table public.calendars
  add constraint calendars_connection_same_family
    foreign key (connection_id, family_check_id)
    references public.calendar_connections (id, family_id) on delete cascade;

-- One Aporah calendar per provider sub-calendar. Partial, because a hand-made
-- calendar has neither of the two columns.
create unique index calendars_connection_external_idx
  on public.calendars (connection_id, external_id)
  where connection_id is not null and external_id is not null;

alter table public.events
  -- The CalDAV resource href / Graph event id needed to update or delete this
  -- exact occurrence upstream, and the etag that makes that safe under
  -- concurrency (If-Match / If-None-Match).
  add column external_href text,
  add column external_etag text;

-- Dedup key for a pulled event. `starts_at` is part of it on purpose: CalDAV
-- expansion yields one row per occurrence of a recurring series, all sharing the
-- series UID, so (calendar_id, external_uid) alone would collapse a weekly
-- Sportkurs into a single event. The sync is a full-window reconcile — it
-- deletes what the provider no longer returns — so a moved occurrence is
-- corrected by the delete pass rather than left behind as a duplicate.
create unique index events_external_identity_idx
  on public.events (calendar_id, external_uid, starts_at)
  where external_uid is not null;

-- ---------------------------------------------------------------------------
-- Guards
-- ---------------------------------------------------------------------------

create or replace function public.sync_calendar_family_check()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.family_check_id := case when new.connection_id is null then null else new.family_id end;
  return new;
end;
$$;

-- Trigger order on calendars is alphabetical and already meaningful:
-- calendars_enforce_ownership -> calendars_sync_family_check ->
-- calendars_touch_updated_at. Ownership is settled before the FK column is
-- derived from family_id.
create trigger calendars_sync_family_check
  before insert or update on public.calendars
  for each row execute function public.sync_calendar_family_check();

-- The sync columns belong to the sync function. Without this a member could
-- detach a calendar from its connection (orphaning it while it keeps showing
-- provider events) or clear sync_token to force a full refetch on every open.
-- Same shape as enforce_container_ownership: a null JWT means a trigger, a
-- migration or a service_role function, which are the privileged paths.
create or replace function public.enforce_calendar_sync_fields()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.connection_id is not null or new.sync_token is not null then
      raise exception 'Verbundene Kalender werden nur beim Synchronisieren angelegt.'
        using errcode = 'check_violation';
    end if;
    return new;
  end if;

  if new.connection_id  is distinct from old.connection_id
     or new.external_id is distinct from old.external_id
     or new.sync_token  is distinct from old.sync_token
     or new.provider    is distinct from old.provider
  then
    raise exception 'Synchronisationsdaten eines Kalenders können nicht geändert werden.'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger calendars_enforce_sync_fields
  before insert or update on public.calendars
  for each row execute function public.enforce_calendar_sync_fields();

-- A connection carries a live credential for someone's personal account. When
-- that person leaves the household the credential must leave with them —
-- otherwise "removed from the family" quietly leaves your Google refresh token
-- in their calendar list. Content reassignment (which hands shared items to an
-- admin) is deliberately NOT the model here.
create or replace function public.drop_connections_on_member_removal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Dissolution: the household and everything in it is cascading away already.
  if not exists (select 1 from public.families f where f.id = old.family_id) then
    return old;
  end if;

  delete from public.calendar_connections
   where family_id = old.family_id
     and created_by = old.user_id;

  return old;
end;
$$;

-- Note the firing order, which is alphabetical and NOT what you would pick:
--   family_members_drop_connections
--     -> family_members_enforce_last_admin
--       -> family_members_reassign_content
--
-- So this runs BEFORE the last-admin guard has had its say. That is safe, but
-- for a reason worth writing down rather than assuming: the guard raises, and an
-- exception unwinds the whole statement including every trigger effect already
-- applied. A refused removal therefore leaves connections untouched. If this
-- ever becomes a `return null` instead of a `raise`, that stops being true.
create trigger family_members_drop_connections
  before delete on public.family_members
  for each row execute function public.drop_connections_on_member_removal();

create trigger calendar_connections_touch_updated_at
  before update on public.calendar_connections
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

create index calendar_connections_family_idx     on public.calendar_connections (family_id);
create index calendar_connections_created_by_idx on public.calendar_connections (created_by);
-- The sync scheduler's query: "which feed is most overdue?" — cheap even once
-- every household has a handful of them.
create index calendar_connections_due_idx
  on public.calendar_connections (last_synced_at nulls first)
  where status = 'active';

create index calendars_connection_idx on public.calendars (connection_id);

-- ---------------------------------------------------------------------------
-- RLS
--
-- Same conventions as everything before it: `to authenticated`, never a bare
-- auth.uid(), one policy per command.
-- ---------------------------------------------------------------------------

alter table public.calendar_connections        enable row level security;
alter table public.calendar_connection_secrets enable row level security;

-- The whole household sees the connection list. It is the answer to "warum
-- steht das in meinem Kalender?", so hiding it from members would make synced
-- events unexplainable. It contains no credential — see the secrets table.
create policy "calendar_connections_select" on public.calendar_connections
  for select to authenticated
  using (family_id = public.my_family_id());

-- No insert policy. A connection only ever exists together with a credential,
-- and a credential can only be captured server-side — so calendar-connect and
-- calendar-caldav create these rows with service_role, exactly as
-- create-share-link mints tokens. A client insert would produce a connection
-- with no secret: a row that looks connected and syncs nothing.

-- Renaming, and choosing which sub-calendars sync. Restricted to the person who
-- attached the account or to an admin, because "which calendars sync" decides
-- what the whole household sees.
create policy "calendar_connections_update" on public.calendar_connections
  for update to authenticated
  using (
    family_id = public.my_family_id()
    and (created_by = (select auth.uid()) or public.is_admin())
  )
  with check (
    family_id = public.my_family_id()
    and (created_by = (select auth.uid()) or public.is_admin())
  );

-- "Trennen". Cascades the secrets row and every calendar (and therefore every
-- event) the connection produced.
--
-- Note what this does NOT do: revoke the token at Google. That needs an outbound
-- HTTPS call, so the app should disconnect via the calendar-connect function,
-- which revokes first and then deletes. This policy is the honest fallback — a
-- user who cannot reach the function still gets the credential out of our
-- database, which is the part we are responsible for.
create policy "calendar_connections_delete" on public.calendar_connections
  for delete to authenticated
  using (
    family_id = public.my_family_id()
    and (created_by = (select auth.uid()) or public.is_admin())
  );

-- Column privileges. Sync state is written by the server and only by the server:
-- a client that could set `status = 'active'` could hide a broken connection
-- from the household, and one that could set `family_id` could hand a live
-- Google token to another account.
revoke all on public.calendar_connections from authenticated, anon;

grant select on public.calendar_connections to authenticated;
grant update (display_name, selected_calendars, position) on public.calendar_connections to authenticated;
grant delete on public.calendar_connections to authenticated;

-- No policy of any kind on the secrets table, for any command, for any role. The
-- revoke is what makes that structural rather than incidental.
revoke all on public.calendar_connection_secrets from authenticated, anon;

-- Helper functions get the same treatment as the rest of the schema: they are
-- trigger bodies, not an API.
revoke all on function public.sync_calendar_family_check() from public, anon, authenticated;
revoke all on function public.enforce_calendar_sync_fields() from public, anon, authenticated;
revoke all on function public.drop_connections_on_member_removal() from public, anon, authenticated;
