-- Aporah has no calendar of its own.
--
-- The event form used to offer "Aporah" as a destination alongside the connected
-- ones, and an appointment filed there became a `public.events` row that only
-- this app could ever see. That is the wrong shape for a family organiser: the
-- point of connecting iCloud or Google is that the appointment is *in* the
-- family's calendar — on the phone's own calendar app, on the other parent's
-- watch, in the notification they get on the way to the dentist. A destination
-- reachable only from inside Aporah looks like the others in the picker and
-- behaves nothing like them.
--
-- So every calendar is now external, and every write goes out through
-- `calendar-write` to the account that owns it. The client stopped reading
-- `provider = 'aporah'` at all, which is what makes this true in the app; this
-- migration is what makes it true in the database.
--
-- Three parts, and the *default* is the important one:
--
--   1. The one leftover row. It was created by an earlier version of the app
--      and carried no events (checked before writing this: 0 rows in
--      `public.events`, and `public.events` was empty overall), so nothing is
--      stranded by removing it.
--   2. The default. `provider` defaulted to `'aporah'`, so any insert that
--      forgot the column silently produced an own calendar — which is exactly
--      how the leftover row appeared. `calendar-events` is the only thing that
--      inserts here and it always names the provider explicitly, so requiring
--      it costs nothing and closes the hole.
--   3. The check constraint, so `'aporah'` is not a value this column accepts
--      any more. Without this the other two are a cleanup that the next stray
--      insert undoes.
--
-- `public.events` itself is deliberately left in place: it is empty and now
-- unreachable, and dropping a table is not something to do on the way past.
-- Decide that separately.

delete from public.calendars where provider = 'aporah';

alter table public.calendars
  alter column provider drop default;

alter table public.calendars
  drop constraint calendars_provider_check;

alter table public.calendars
  add constraint calendars_provider_check
  check (provider in ('google', 'icloud', 'outlook', 'iserv'));
