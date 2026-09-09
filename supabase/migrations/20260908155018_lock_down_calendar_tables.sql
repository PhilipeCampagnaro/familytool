-- Aporah backend — make "we hold no calendar" true at the grant level, and stop
-- keeping an address after the last household that used it has gone.
--
-- Both halves close the same kind of gap: something the architecture already
-- says out loud, that the database was not actually enforcing.
--
-- ---------------------------------------------------------------------------
-- 1. public.calendars and public.events were never locked down
-- ---------------------------------------------------------------------------
--
-- 20260803101000 was careful with `calendar_connections`: `revoke all`, then a
-- narrow `grant select` and a four-column `grant update`. `calendars` and
-- `events` never got the same treatment, so they still carried Supabase's
-- default `grant all to anon, authenticated`. RLS kept other households out —
-- that part worked — but within a household every column was readable, and that
-- turned out to matter for exactly one of them.
--
-- `calendars.external_id` is not an opaque identifier for a link connection.
-- `linkedFeeds` in _shared/providers.ts sets `externalId: f.url`, so for an
-- IServ or WebUntis calendar connected by a pasted link the column holds the
-- **tokenised ICS URL itself** — a bearer capability that needs no login, works
-- from anywhere, and is revoked only by the pupil regenerating it in the school
-- platform. Any household member could read it out with one PostgREST call and
-- carry it off; the `kid` role included, whose own timetable it may be.
--
-- 20260908132737 argued the column was safe to expose because "the only people
-- who can read it are the household members who are already looking at the
-- events it returns". That conflates two different things. Seeing events inside
-- the app is scoped, revocable and ends when someone leaves the household.
-- Holding the URL is none of those.
--
-- The fix is not a narrower column list, because the client does not need this
-- table at all: **no Flutter code path reads `calendars` or `events` over
-- PostgREST.** Calendars reach the app as `WireCalendar` from `calendar-events`,
-- which deliberately does not carry `external_id`; names, colours and selection
-- are written on `calendar_connections` and `family_feeds`. So the grant that
-- matches reality is none.
--
-- What still works, and why:
--
--   * Edge Functions use `service_role`, which keeps every grant here.
--   * `private.can_read_calendar`, `private.can_write_calendar` and
--     `public.reassign_content_on_member_removal` are `security definer` and run
--     as the owner, so they are unaffected.
--   * The RLS policies stay exactly as they are. They are now belt to this
--     braces rather than the only barrier, and leaving them costs nothing.
--
-- For `events` this is the structural half of a promise the docs already make.
-- The table is empty, nothing reads it and `provider = 'aporah'` stopped being a
-- legal calendar in 20260805182949 — but `authenticated` still held INSERT and
-- UPDATE on it, so "unreachable" was a convention rather than a fact. Now a
-- client that tried to materialise an event in our database would be refused by
-- Postgres rather than by a code review.

revoke all on public.calendars from authenticated, anon;
revoke all on public.events     from authenticated, anon;

comment on column public.calendars.external_id is
  'Die Kennung des Kalenders beim Anbieter. Bei per Link verbundenen '
  'Schulkalendern ist das die tokenisierte ICS-URL selbst — also ein '
  'Zugangsschlüssel. Deshalb hat `authenticated` auf dieser Tabelle keinerlei '
  'Rechte mehr: die App liest Kalender ausschließlich über die Edge Function '
  '`calendar-events`, die `external_id` bewusst nicht mitschickt.';

-- ---------------------------------------------------------------------------
-- 2. A feed nobody subscribes to keeps somebody's address
-- ---------------------------------------------------------------------------
--
-- `public_feeds` is shared on purpose: a hundred families on one street read one
-- row and cause one daily fetch. The subscription in `family_feeds` cascades
-- away with the household — but the feed row it pointed at was never deleted.
-- 20260804090000 said as much ("An unsubscribed feed simply stops being
-- refreshed") and treated that as harmless, which holds for Ferien and does not
-- hold for Abfall: an Abfall feed's `config` carries the resolved street
-- address, and `feed_key` is a hash of it.
--
-- So a household that unsubscribed — or deleted their account outright — left a
-- row behind naming the street they live on, with no subscriber, refreshed by
-- nobody, retained forever. Under Art. 17 DSGVO there is no answer to "löschen
-- Sie meine Daten" that leaves that row standing, and under Art. 5 Abs. 1 lit. e
-- (Speicherbegrenzung) there is no purpose left to justify keeping it.
--
-- The rule is the same for both kinds, deliberately. Special-casing Abfall would
-- mean a later feed kind quietly inheriting the wrong default, and the cost of
-- including Ferien is one OpenHolidays fetch the next time somebody in that
-- Bundesland subscribes — which only happens when the count reaches zero, i.e.
-- when the *last* family in Berlin leaves.
--
-- `security definer` because `authenticated` holds no delete on `public_feeds`
-- and must not: unsubscribing is allowed to drop a feed, choosing to drop one is
-- not.

create or replace function public.drop_unsubscribed_feed()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Only when this was the last subscription. The `not exists` runs after the
  -- row is gone, so the household deleting its own single subscription sees a
  -- count of zero and the feed goes with it.
  delete from public.public_feeds pf
   where pf.id = old.feed_id
     and not exists (
       select 1 from public.family_feeds ff where ff.feed_id = pf.id
     );

  return old;
end;
$$;

comment on function public.drop_unsubscribed_feed() is
  'Löscht einen öffentlichen Feed, sobald ihn kein Haushalt mehr abonniert. '
  'Ein Abfall-Feed enthält die aufgelöste Adresse — er darf einen Haushalt '
  'nicht überleben (Art. 17 DSGVO).';

-- Trigger bodies are not an API, same as everywhere else in this schema.
revoke all on function public.drop_unsubscribed_feed() from public, anon, authenticated;

create trigger family_feeds_drop_unsubscribed
  after delete on public.family_feeds
  for each row execute function public.drop_unsubscribed_feed();

-- The rows that are already orphaned. At the time of writing that is four feeds
-- with no subscriber, one of them an Abfall config naming a street and postcode
-- for a household that is no longer here.
delete from public.public_feeds pf
 where not exists (
   select 1 from public.family_feeds ff where ff.feed_id = pf.id
 );
