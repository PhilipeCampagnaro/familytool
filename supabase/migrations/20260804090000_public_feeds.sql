-- ---------------------------------------------------------------------------
-- Public feeds, and the end of storing anybody's calendar
--
-- Two changes that pull in opposite directions on purpose, because calendar data
-- is two different kinds of thing:
--
--   * A **personal** calendar (Google, Outlook, iCloud, IServ) is personal data
--     in the strict sense — a therapy appointment, a lawyer, a job interview.
--     Aporah now proxies those live and keeps a copy only in the device's own
--     cache. Nothing lands here. public.events holds exactly what somebody typed
--     into Aporah itself, and nothing that was pulled from an account.
--
--   * A **public feed** (Schulferien, Abfuhrkalender) is municipal data. It is
--     identical for every household in the same Bundesland or at the same
--     address, and no one's privacy is at stake in it. So it is stored exactly
--     once, globally, and every household subscribes to the same row. A hundred
--     Bremen families now share one feed and one upstream fetch instead of
--     creating a hundred connections, a hundred calendars and three thousand
--     event rows.
-- ---------------------------------------------------------------------------

create table public.public_feeds (
  id            uuid primary key default gen_random_uuid(),
  kind          text not null check (kind in ('ferien', 'abfall')),

  -- Deterministic identity derived from `config` by the calendar-feed function,
  -- so the second household at an address resolves to this row instead of
  -- making a copy of it. That dedup is the whole point of the table, and a
  -- unique constraint is what makes it true rather than merely intended.
  feed_key      text not null unique check (length(feed_key) between 1 and 200),

  name          text not null check (length(trim(name)) between 1 and 120),
  color         integer not null default 0,

  -- What the reader needs to fetch this feed again: a Bundesland code, or a
  -- resolved waste-vendor address.
  config        jsonb not null,

  -- The cached feed itself. One jsonb document rather than a child table
  -- because it is bounded and always used whole: a Bundesland has ~24 holiday
  -- blocks a year and an address ~30 pickups, it is read in full and replaced
  -- in full. A child table would buy range queries nobody makes.
  events        jsonb not null default '[]'::jsonb,

  synced_at     timestamptz,
  status        text not null default 'ok' check (status in ('ok', 'error')),
  status_detail text,
  created_at    timestamptz not null default now()
);

create table public.family_feeds (
  family_id    uuid not null references public.families (id) on delete cascade,
  feed_id      uuid not null references public.public_feeds (id) on delete cascade,

  -- The household's own name and colour for a shared feed. Null means "use the
  -- feed's". Renaming your bin calendar must not rename it for the rest of the
  -- city, which is exactly why these live on the subscription and not the feed.
  display_name text check (display_name is null or length(trim(display_name)) between 1 and 120),
  color        integer,

  position     integer not null default 0,
  created_by   uuid references auth.users (id) on delete set null,
  created_at   timestamptz not null default now(),

  primary key (family_id, feed_id)
);

create index family_feeds_feed_idx on public.family_feeds (feed_id);

alter table public.public_feeds enable row level security;
alter table public.public_feeds force row level security;
alter table public.family_feeds enable row level security;
alter table public.family_feeds force row level security;

-- The contents of a feed are public information. The *list* of feeds is not: an
-- Abfall feed_key names a street address, so a readable table would enumerate
-- the streets Aporah's households live on. Readable only where subscribed.
create policy "public_feeds_select" on public.public_feeds
  for select to authenticated
  using (exists (
    select 1
      from public.family_feeds f
     where f.feed_id = public_feeds.id
       and f.family_id = public.my_family_id()
  ));

create policy "family_feeds_select" on public.family_feeds
  for select to authenticated
  using (family_id = public.my_family_id());

-- Naming and colouring is the household's. Subscribing is not: a subscription
-- is only ever created by the calendar-feed function, which first proved the
-- feed answers with real dates. Same rule calendar_connections follows, for the
-- same reason — "verbunden" has to mean "we reached it just now".
create policy "family_feeds_update" on public.family_feeds
  for update to authenticated
  using (family_id = public.my_family_id() and public.my_role() <> 'kid')
  with check (family_id = public.my_family_id());

create policy "family_feeds_delete" on public.family_feeds
  for delete to authenticated
  using (family_id = public.my_family_id() and public.my_role() <> 'kid');

-- No insert grant anywhere, and no write grant at all on public_feeds: only
-- service_role, i.e. only an Edge Function, may create or refresh one.
grant select on public.public_feeds to authenticated;
grant select on public.family_feeds to authenticated;
grant update (display_name, color, position) on public.family_feeds to authenticated;
grant delete on public.family_feeds to authenticated;

-- ---------------------------------------------------------------------------
-- Stop materialising provider events
-- ---------------------------------------------------------------------------

-- Everything ever pulled from an account or a feed goes. The calendars rows for
-- personal accounts stay: a calendar's name, colour, position and selection are
-- the household's own settings and have to survive, and none of that is the
-- sensitive part.
delete from public.events
 where calendar_id in (select id from public.calendars where provider <> 'aporah');

-- Ferien and Abfall are not per-household connections any more.
delete from public.calendars           where provider in ('ferien', 'abfall');
delete from public.calendar_connections where provider in ('ferien', 'abfall');

alter table public.calendars drop constraint calendars_provider_check;
alter table public.calendars add constraint calendars_provider_check
  check (provider in ('aporah', 'google', 'icloud', 'outlook', 'iserv'));

alter table public.calendar_connections drop constraint calendar_connections_provider_check;
alter table public.calendar_connections add constraint calendar_connections_provider_check
  check (provider in ('google', 'outlook', 'icloud', 'iserv'));

-- The sync columns are what made a stored event a *pulled* event. Dropping them
-- is the structural half of the promise: there is no longer a column in which to
-- record which provider an event came from, so no future code path can quietly
-- start materialising one again.
drop index if exists public.events_external_identity_idx;
alter table public.events
  drop column if exists external_uid,
  drop column if exists external_href,
  drop column if exists external_etag;
