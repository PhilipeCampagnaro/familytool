-- Which person each *calendar* of an account belongs to.
--
-- 20260908180000 gave `calendars` and `calendar_connections` an owner, seeded
-- from the account: a WebUntis key scanned for Alice makes Alice's timetable
-- hers without anybody opening a settings screen. That covers the school case
-- completely and the household case not at all.
--
-- The household case is one Apple ID carrying "Familie", "Arbeit" and
-- "Privat". Those are three calendars belonging to three different people —
-- everybody, one parent, that same parent — and no default taken from the
-- account can be right for all three. The owner has to be settable per
-- calendar, from the row the household already renames and removes.
--
-- Which leaves *where*. `calendars` is the natural home, and is where the value
-- ends up — but `authenticated` holds no grant on that table at all
-- (20260908155018, and for a good reason: `external_id` is a bearer URL for a
-- school link). So the household's choice is written where every other
-- per-calendar choice already lives: a small map on the connection, keyed by the
-- provider's own id, applied to the `calendars` row by `calendar-events` on the
-- next read.
--
-- That is exactly how `calendar_names` works (20260805153018), deliberately.
-- One mechanism for "what the household decided about one calendar inside an
-- account", one grant, one code path in the function — rather than a second
-- Edge Function whose only job is a two-column update.

alter table public.calendar_connections
  add column if not exists calendar_owners jsonb;

comment on column public.calendar_connections.calendar_owners is
  'Kalender-Kennung des Anbieters -> wem dieser Kalender gehört: "family", '
  '"member:<user_id>" oder "person:<Name>". Der Schlüssel "*" gilt für alle '
  'Kalender des Kontos. Fehlt ein Eintrag, gilt die Vorgabe des Kontos '
  '(owner_member_id / owner_label). Das ist KEINE Sichtbarkeit — jeder im '
  'Haushalt sieht jeden Kalender.';

-- Same shape of grant as `calendar_names`: the client may set it, and RLS
-- (`calendar_connections_update`) decides whose connection it may set it on.
--
-- A malicious client could write a member id that is not in the household, or a
-- 4 KB name. Neither reaches anybody: `calendar-events` resolves a member id
-- through the household's own roster and treats an unknown one as no member at
-- all (see `groupFor`), and the label is trimmed to the 60 characters
-- `calendars.owner_label` accepts before it is stored. The blast radius is a
-- chip in the writer's own household — the same one `calendar_names` already
-- has.
grant update (calendar_owners) on public.calendar_connections to authenticated;
