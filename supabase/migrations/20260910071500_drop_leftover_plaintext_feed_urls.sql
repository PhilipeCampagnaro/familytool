-- Aporah backend — the second half of 20260910070000: nothing plaintext left.
--
-- That migration added `calendar_connection_secrets.feed_urls` and explained why
-- the backfill cannot live in SQL — CALENDAR_SECRET_KEY is a function secret and
-- handing it to Postgres to run an UPDATE would undo the protection in the act
-- of applying it. `migrateLegacyFeeds` does the sealing on the first
-- `calendar-events` read after the deploy, which is the same read the app makes
-- every time somebody opens Kalender.
--
-- This runs afterwards and answers the case that read never reaches: a
-- connection on a household that has not opened the app since. There is exactly
-- one thing to do with a plaintext token that has outlived its migration
-- window, and it is not to leave it there.
--
-- Dropping the entry rather than the connection: a link account can hold up to
-- twenty feeds and the sealed ones are fine. What goes is the un-migrated entry
-- and, with it, the token. The account survives, flips to reconnect_required,
-- and the settings screen already knows how to say "Bitte erneut verbinden" —
-- the user pastes the link again, which takes the ten seconds it took the first
-- time and is the only honest offer: we cannot seal what we have just deleted.

with leftover as (
  select id,
         (select jsonb_agg(e)
            from jsonb_array_elements(config->'feeds') e
           where not (e ? 'url')) as kept
    from public.calendar_connections
   where jsonb_path_exists(config, '$.feeds[*].url')
)
update public.calendar_connections c
   set config = jsonb_set(c.config, '{feeds}', coalesce(l.kept, '[]'::jsonb)),
       status = 'reconnect_required',
       status_detail = 'Bitte erneut verbinden.'
  from leftover l
 where c.id = l.id;

-- ---------------------------------------------------------------------------
-- And it cannot come back
-- ---------------------------------------------------------------------------
--
-- The constraint is the point of this migration more than the UPDATE above is.
-- Two earlier migrations argued this URL out of one column at a time while it
-- stayed in another; a check is what turns "we moved it" into "it cannot be
-- written here". `jsonb_path_exists` is immutable, so no helper function is
-- needed — and a check constraint would not be allowed a subquery anyway.
--
-- It bites on every UPDATE of the row, not only on INSERT, which is what makes
-- a future `config` write carrying a `url` fail loudly in `calendar-link`
-- rather than quietly reinstating the exposure.

alter table public.calendar_connections
  add constraint calendar_connections_no_plaintext_feed_url
  check (config is null or not jsonb_path_exists(config, '$.feeds[*].url'));

comment on constraint calendar_connections_no_plaintext_feed_url
  on public.calendar_connections is
  'Eine ICS-URL gehört verschlüsselt in calendar_connection_secrets.feed_urls, '
  'nie in config.feeds. Siehe 20260910070000.';
