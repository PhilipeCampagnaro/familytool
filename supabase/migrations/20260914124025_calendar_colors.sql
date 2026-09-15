-- Aporah backend — the household's own colour for a calendar.
--
-- **A calendar's colour is the account's until the family says otherwise.**
-- iCloud hands "Familie" over as Apple's system grey `#8E8E93`, which is a fine
-- colour on Apple's white calendar and a grey chip on a grey card in ours. The
-- app deliberately does *not* substitute a legible colour on the household's
-- behalf — the colour is what a family recognises a calendar by, in their own
-- calendar app as much as in this one — so the only honest fix is letting them
-- pick.
--
-- This is the third column of exactly the same shape as `calendar_names` and
-- `calendar_owners`: a map from the provider's own calendar id to the
-- household's choice, merged by the client, copied onto the `calendars` row by
-- `calendar-events` on the next read. The app holds no grant on `calendars` at
-- all, which is why the override lives here rather than there.
--
-- **Ferien and Abfall need nothing.** A feed is one calendar with no sub-ids to
-- key on, so its colour already has a column of its own on `family_feeds`, and
-- `authenticated` already holds UPDATE on it.

alter table public.calendar_connections
  -- Nullable rather than `default '{}'`, exactly like the two columns beside
  -- it: null means "never chosen", which is a different fact from "chosen and
  -- then cleared" and is what the repository's merge reads back.
  add column calendar_colors jsonb;

comment on column public.calendar_connections.calendar_colors is
  'Farbe je Kalender, gewählt vom Haushalt: {"<external_id>": <ARGB int>}. Der '
  'Schlüssel ist die Kalender-ID des Anbieters, genau wie bei calendar_names '
  'und calendar_owners; "*" steht für eine Verbindung, die selbst nur einen '
  'Kalender liefert. Der Wert ist eine vorzeichenbehaftete 32-Bit-ARGB-Zahl, '
  'dieselbe Darstellung wie calendars.color. Fehlt ein Eintrag, gilt die Farbe '
  'des Anbieters (defaultColor in calendar-events).';

-- SELECT and UPDATE on this table are **column-level grants** (see
-- 20260909101500), so a new column is invisible and unwritable until it is
-- named here. Adding it to the existing grant rather than re-granting the whole
-- list: `grant` is additive per column and re-listing the others would silently
-- re-grant anything a later migration had revoked.
grant select (calendar_colors) on public.calendar_connections to authenticated;
grant update (calendar_colors) on public.calendar_connections to authenticated;
