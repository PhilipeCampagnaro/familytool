-- ---------------------------------------------------------------------------
-- A list or a task can hang off an appointment
--
-- "Liste zum Termin erstellen" already existed; what it produced was an
-- ordinary list with no memory of where it came from, so reopening the event
-- offered to create it a second time. These three columns are that memory.
--
-- **The link points at an event we do not store, and never will.** Aporah has
-- no calendar of its own (see docs/backend.md): every event is proxied from
-- Google, Outlook, iCloud, IServ or a shared Ferien/Abfall feed on each read.
-- So the reference is the pair the provider itself guarantees — the calendar
-- and the event's own `uid`, exactly the pair `untis_homework.event_uid`
-- already uses to name the lesson a homework is due in.
--
-- **No foreign key on event_calendar_id, deliberately.** It holds a
-- `public.calendars.id` for a connected calendar and a `public.public_feeds.id`
-- for Ferien and Abfall, which are two different tables by design — a hundred
-- households on one street share one waste feed rather than owning a calendar
-- row each. A single FK cannot span both, and an FK to `calendars` alone would
-- reject the packing list somebody hangs off a Schulferien block.
--
-- **No event_title, and that is the whole point.** An earlier draft of this
-- copied the appointment's name onto the row so that a task could label its
-- badge "Zahnarzt Dr. Müller" months later. That is content out of somebody's
-- calendar, sitting in our database — exactly what "we do not store anybody's
-- calendar" exists to prevent, and no amount of it being one short line makes
-- it a pointer instead of a copy. The badge resolves the live title from the
-- proxied event when Kalender has it, and shows the date when it does not.
--
-- **event_starts_at is the one thing kept, and it is a date, not content.** It
-- is what makes the jump back work for an appointment outside the fortnight
-- Kalender holds, which is most of them: without it the tap has nowhere to go.
-- On a task it is already there under another name — a task made from an event
-- takes the event's day as its `due_date` — so what it adds over the existing
-- row is nothing at all; on a list it adds one day per link. It goes stale if
-- the appointment is moved, and that is accepted: a wrong day is a wrong day,
-- and the alternative is keeping a copy in step, which means keeping a copy.
-- ---------------------------------------------------------------------------

alter table public.lists
  add column event_calendar_id uuid,
  add column event_uid         text,
  add column event_starts_at   timestamptz;

alter table public.tasks
  add column event_calendar_id uuid,
  add column event_uid         text,
  add column event_starts_at   timestamptz;

-- Half a link is not a link: without this, a row could name a calendar and no
-- event and the app would have to invent a meaning for it.
alter table public.lists
  add constraint lists_event_link_complete
  check ((event_calendar_id is null) = (event_uid is null));

alter table public.tasks
  add constraint tasks_event_link_complete
  check ((event_calendar_id is null) = (event_uid is null));

-- The event detail sheet asks "what hangs off this appointment?" every time it
-- opens. Partial, because the overwhelming majority of lists and tasks are not
-- hung off anything.
create index lists_event_uid_idx on public.lists (event_calendar_id, event_uid)
  where event_uid is not null;

create index tasks_event_uid_idx on public.tasks (event_calendar_id, event_uid)
  where event_uid is not null;

-- No policy changes. The link is an ordinary column on a container that already
-- has a complete access story: whoever may read the list may read where it came
-- from, and enforce_container_ownership guards only ownership, household and
-- visibility — none of which this touches.
