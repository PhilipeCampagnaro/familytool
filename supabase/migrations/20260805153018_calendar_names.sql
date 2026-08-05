-- Per-calendar names for a connected account.
--
-- A connection is an *account*, but what a household actually thinks it has
-- connected is the calendars inside it: "Familie" and "Arbeit", not
-- "iCloud (name@example.com)". Naming those was impossible, because the moment
-- the user picks them — in the setup sheet, right after the credentials proved
-- out — no `calendars` row exists yet. They are created by the first
-- `calendar-events` read, which happens afterwards and asynchronously.
--
-- So the household's choice of name is kept next to its choice of calendar, on
-- the connection, keyed by the same provider id `selected_calendars` uses:
--
--   {"<external_id>": "Familie", "<external_id>": "Arbeit"}
--
-- and `calendar-events` copies it onto `calendars.name` as it upserts each one.
-- One direction only: this column is what the user typed, `calendars.name` is
-- what the calendar is called, and the function is the only thing that carries
-- one into the other. An external_id with no entry keeps the provider's own
-- name, which is what every connection made before this had.
alter table public.calendar_connections
  add column if not exists calendar_names jsonb;

comment on column public.calendar_connections.calendar_names is
  'external_id -> the name this household gave that calendar. Absent = keep the provider''s.';

-- Same grant as `selected_calendars`, and for the same reason: the two are
-- written together by the setup sheet, and both are household settings rather
-- than anything the provider owns. Everything else on this table stays
-- server-only — `status`, `last_synced_at` and the credentials are written by
-- the functions and must not be forgeable from a client.
grant update (calendar_names) on public.calendar_connections to authenticated;

-- Households that already picked their calendars, before there was anywhere to
-- name them, keep the names they have: the `calendars` rows the first sync
-- created hold the provider's own, which is exactly what an unnamed pick means.
-- Without this their settings list shows one row per picked calendar, all
-- carrying the account's name.
update public.calendar_connections c
set calendar_names = synced.names
from (
  select connection_id, jsonb_object_agg(external_id, name) as names
  from public.calendars
  where connection_id is not null and external_id is not null
  group by connection_id
) synced
where synced.connection_id = c.id
  and c.calendar_names is null
  and c.selected_calendars is not null;
