# Backend (Supabase)

Schema, roles and access rules live in [supabase/migrations/](../supabase/migrations/).

The Flutter app now talks to it for **identity only**: sign-up/sign-in
([lib/state/auth_state.dart](../lib/state/auth_state.dart)), the household and its roster
([lib/state/family_state.dart](../lib/state/family_state.dart)), and the signed-in user's own
`profiles` row — and, since the Listen slice, for **content**:
[lib/data/repositories/list_repository.dart](../lib/data/repositories/list_repository.dart) is the
only file that knows `lists` / `list_items` / `list_shares` exist. Board, Box and Kalender are
still in-memory and copy that shape: a repository with plain methods returning model types, models
with `fromMap`/`toMap` over the real snake_case columns, and a notifier that *owns* its rows
instead of overlaying maps on top of them.

**The executable version of this document is
[supabase/tests/rls.test.sql](../supabase/tests/rls.test.sql).** Every rule below has an assertion
there. Change a policy, change that file in the same commit.

## The three axes

The app's current `who` field (`'all' | 'private' | <memberId>` in
[lib/models/who.dart](../lib/models/who.dart)) conflates two different things — `whoHint()` says so
out loud: *"Zugewiesen an Lea — für alle sichtbar."* The backend splits it into three:

| Konzept | Spalte | Werte |
|---|---|---|
| **Zuweisung** — wer macht das | `assignee_id` | `null` oder ein Mitglied |
| **Sichtbarkeit (intern)** | `visibility` + `*_shares` | `family` \| `private` \| `custom` |
| **Freigabe (extern)** | `guest_access` + `share_links` | Gäste, einzeln eingeladen |

External sharing is deliberately **not** part of the "Für wen?" picker. Mixing outsiders into the
family avatar row would make a mis-tap leak family data; it gets its own "Teilen" sheet.

## Board: To-dos and Tracker are two tables

`public.tasks` is the one-off to-do it always was. `public.trackers` is the rhythm beside it, and
the split exists because the two behave differently in the one place a household notices:

| | To-do | Tracker |
|---|---|---|
| Termin | `due_date` (+ optional `due_time`), or none | a rule: `schedule` + `weekdays` / `target` |
| Verpasst | Überfällig, and it stays | a gap in the record, and nothing else |
| Erledigt | off the list | recorded, and back on the next scheduled day |
| Verlauf | none | `public.tracker_checks`, one row per day kept |
| Extern teilbar | yes | **no** — `shareable_kind` names no value for it |

**`due_time` is an hour, not a deadline.** It is a nullable `time without time zone` beside
`due_date`, which stays a `date`: the pair is a local wall-clock reading, so a to-do due Donnerstag
um acht is due then wherever the phone is. `tasks_due_time_needs_date` refuses an hour with no day.
It does **not** decide when a to-do goes Überfällig — that is still a question about the day
(`boardSectionOf` never reads it), because a board that moved a row into Überfällig at 09:01 of the
day it was planned for would nag inside the one section people open the app to see. What the hour
does is place the to-do among the appointments in the Kalender agenda; see the to-do overlay
section of [kalender.md](kalender.md).

`tracker_schedule` is `('daily','weekdays','weekly_count')`, and `weekdays` against `weekly_count`
is not two spellings of one idea. A `weekdays` tracker makes the **day** the unit and can say
"heute dran"; a `weekly_count` tracker makes the **week** the unit, owes nothing on any particular
day, and can only be missed once Sunday has closed. `trackers_schedule_shape` keeps a row from
carrying both shapes at once.

**The future is never materialised.** There is no row per scheduled day: the rule stays one row and
the app computes which days it covers at read time
([lib/data/tracker_data.dart](../lib/data/tracker_data.dart)). Generating occurrences would need a
job to keep them coming, a rewrite of the whole future whenever somebody edits a rhythm, and it
would strand hundreds of rows on delete. Nor is a tracker a task with a rolling `due_date`:
advancing the date on completion keeps no history at all, which is the one thing a tracker is for.

**A tick is a row and an untick is a delete.** There is no "not done" to store, because a miss is
the absence of a check on a day the rule scheduled, and only the rule knows which days those were.
`done_by` sits in the primary key `(tracker_id, day, done_by)` even though one tick currently
settles the day for the whole household — that is what "Müll rausbringen" wants, and a later
"everybody has to tick" mode then needs a column on `trackers` and no migration of existing rows.

`can_read_tracker` / `can_write_tracker` live in `private` like every other helper, and they have
**no guest branch**: a link handing an outsider a page of the household's habits has no reader worth
the leak. Note the grants — a function *created* in `private` starts with EXECUTE for PUBLIC only,
so the migration grants `authenticated` explicitly. The seventeen helpers next door only kept it
because they were moved into the schema carrying the grants Supabase had given them in `public`.
Revoking PUBLIC without granting it back takes every policy on the table down with a permission
error.

## One household per user, always

`unique (user_id)` on `family_members` makes this a database fact, not a convention:

- Signup runs `handle_new_user()`, which creates a profile, a household, and an admin membership
  in one transaction. **There is no user without a household** — including the stranger who signs
  up only to open a shared shopping list. That is what removes the empty-shell case from the app.
- Accepting an invite **dissolves** your own household (`accept_family_invite`). If it still has
  other members, the join is refused instead — deleting a household your spouse and kids live in
  must never be a side effect of tapping a link in an e-mail.
- Being removed from a household **rehomes** you into a fresh solo one (`rehome_removed_member`),
  so the invariant holds on the way out too.

It also makes `my_family_id()` single-valued, so every content policy compares
`family_id = my_family_id()` instead of running an `EXISTS` per row. Relaxing this later
(separated parents, grandparents across two homes) means dropping one constraint and revisiting
that function — `family_id` is already on every content row.

## Access rules

Four containers — `lists`, `boxes`, `tasks`, `calendars` — share one contract: `family_id`,
`owner_id`, `visibility`, plus a `*_shares` table. So one predicate is reused four times:

```
household branch : family_id = my_family_id()
                   AND (visibility = 'family' OR owner_id = me
                        OR (visibility = 'custom' AND shared with me))
guest branch     : an explicit guest_access grant — household irrelevant
```

`private` needs no clause of its own; it is exactly the case where only `owner_id = me` matches.

**The guest branch sits outside the household gate.** It is the only place in this schema where a
row is readable by someone outside the owning household — the line to re-read whenever these
predicates change. `can_read_calendar` has no such branch, by design.

Child rows (`list_items`, `box_items`, `events`, attachments) never restate any of this. They call
`can_read_list(list_id)` and friends, so a container and its contents cannot drift apart.

### Permission matrix

| Aktion | admin | member | kid | Gast |
|---|:--:|:--:|:--:|:--:|
| Mitglied einladen / Rolle ändern / entfernen | ✅ | ❌ | ❌ | ❌ |
| Haushalt umbenennen, Adresse ändern | ✅ | ❌ | ❌ | ❌ |
| Liste / Box / To-do / Kalender anlegen | ✅ | ✅ | ✅ | ❌ |
| Einträge anlegen / abhaken | ✅ | ✅ | ✅ | ✅ wenn `can_edit` |
| Eigene Einträge bearbeiten/löschen | ✅ | ✅ | ✅ | ✅ |
| Fremde Einträge löschen | ✅ | ❌ | ❌ | ❌ |
| Container löschen | eigene + sichtbare | nur eigene | nur eigene | ❌ |
| `visibility`/`owner_id`/Freigaben ändern | nur Eigentümer | nur Eigentümer | nur Eigentümer | ❌ |
| Externen Link erstellen | ✅ | ✅ | ❌ | ❌ |
| Gast entfernen / Link widerrufen | ✅ (ganzer Haushalt) | eigene Links | ❌ | ❌ |
| Private Einträge anderer sehen | ❌ | ❌ | ❌ | ❌ |
| Kalender extern teilen | ❌ | ❌ | ❌ | ❌ |
| Finanzen (später) | ✅ | ✅ | ❌ | ❌ |

Kids see and participate — a chore board a child cannot tick is not a chore board — but never
administer, never see finances, and never invite outsiders.

**Admins have no backdoor into private items.** A consequence worth knowing: a `private` item whose
owner leaves the household is genuinely unrecoverable, so `reassign_content_on_member_removal`
deletes it rather than orphaning it. That matches what the UI promises.

One deliberate and slightly surprising combination is legal: a `private` list — invisible to your
own household — *can* be shared with an outsider. That is exactly the work-party case.

## What the guest can never reach

A guest is a normal user with their own household who holds one grant into yours. Each of these is
a policy decision with a test, not an emergent property:

1. **Exactly one resource.** Every sibling query fails the household branch and has no grant. The
   Flutter side must therefore stop filtering by `family_id` and let RLS define "my lists".
2. **Profiles**, narrowly. `can_see_profile` allows exactly the names actually rendered on the
   shared resource — its owner, and whoever created, was assigned, or ticked off something in it.
   Not the rest of the household roster.
3. **The internal picker.** The composite FK on `*_shares` → `family_members` makes selecting a
   guest impossible at the database level, not merely unlikely.
4. **Container metadata.** `enforce_container_ownership` keeps `owner_id`, `family_id` and
   `visibility` with the owner, so `can_edit` never becomes "take this list home with me".
5. **Attachments.** Storage policies must key on `can_read_list(...)` / `can_read_box(...)` alone,
   never on household membership, or guests silently lose photos on shared items. Both picture
   buckets do — see "Storage: the picture buckets".
6. **Everything inside a shared container is shared** — `list_items` have no visibility of their
   own. The Teilen sheet's copy should say so.

## Structural guarantees (not just rules)

- `shareable_kind` is `('list','box','task')`. No value names a calendar or a finance record, so no
  future code path can share one outward by accident. Adding a value is a security decision.
- `*_shares` carries two composite foreign keys, so sharing internally with a non-member cannot be
  represented, and removing a member deletes their shares with no cleanup code.
- Tokens exist only as SHA-256 hashes. `token_hash` is revoked from `select` for `authenticated`
  entirely; `share_links` is updatable only in `revoked_at`, `family_invites` only in `status`.
- A token never grants row access — it is exchanged for a durable `guest_access` row. That is why
  every policy is `to authenticated` and nothing is ever readable anonymously.

## Writing containers from the client: no `RETURNING`

**A container row cannot be inserted with `insert … returning`.** PostgREST does exactly that
whenever supabase-dart is asked for the row back (`.insert(…).select()`), and against `lists`,
`boxes`, `tasks` or `calendars` it fails with

```
42501 new row violates row-level security policy for table "lists"
```

which reads like a permission problem and is a visibility one. `RETURNING` makes Postgres apply the
SELECT policy to the new row; that policy is `can_read_list(id)`, a `stable security definer`
function that queries `public.lists` — and a stable function runs against the snapshot the
statement began with, in which the row being inserted does not exist yet. Verified against the
deployed database, `boxes` included.

What does work, all verified the same way:

| Statement | Ergebnis |
|---|---|
| `insert into lists …` (no `returning`) | ✅ |
| `insert into lists … returning` | ❌ 42501 |
| `select` afterwards, own statement | ✅ |
| `update lists … returning` | ✅ (the row pre-existed) |
| `insert into list_items … returning` | ✅ (its policy asks about the *parent*) |

So a repository creates a container by generating the uuid on the device (`newUuidV4()` in
`list_repository.dart` — `id` carries no policy, `gen_random_uuid()` is only a column default) and
inserting without a representation. Child rows and every update keep `.select()`.

**There is no read-back, and the notifier does not wait to draw the row.** There used to be a
second `select` on a fresh snapshot — it works, per the table above — but it cost a full round trip
on the one action the user is watching, and it fetched `created_at` / `updated_at` that no screen
reads. It was also not the proof it looked like: an empty result threw out of `.single()` and the
caller reported "Speichern fehlgeschlagen" for a row that had landed. The insert policy is what
decides whether the write is allowed.

Because the id is the client's, the notifier can put the container on screen *before* the insert
answers and still let the next tap navigate into it — an article typed straight away carries a
`list_id` that is about to exist. `list_state.dart` and `box_state.dart` do that, the way
`board_state.dart` already did for tasks; a failed write takes the row back off and leaves the
detail view. On a phone this is the difference between the list appearing as the sheet closes and
appearing two round trips later, which is long enough that people tap Sichern again.

## Linking a list or a task to an appointment

`lists` and `tasks` each carry three nullable columns — `event_calendar_id`, `event_uid`,
`event_starts_at` — written once when the container is created from an event's detail sheet in
Kalender. `EventLink` ([lib/models/event_link.dart](../lib/models/event_link.dart))
is the Dart side; a `*_event_link_complete` check keeps the first two together, so half a link is
not representable.

Three things about it are load-bearing:

- **The reference is `(calendar, provider uid)`, not a foreign key.** There is nothing to point at:
  every event is proxied from the connected account or the shared feed on each read and none is
  stored. It is the one pair a provider guarantees across a refresh.
- **`event_calendar_id` has no FK either**, because the id is a `public.calendars.id` for a
  connected calendar and a `public.public_feeds.id` for Ferien and Abfall — two tables, on purpose.
  An FK to `calendars` alone would reject the packing list somebody hangs off a Schulferien block.
- **There is no `event_title`, and that is the point.** An earlier draft copied the appointment's
  name onto the row so a task could label its badge months later. That is content out of somebody's
  calendar sitting in our database, which is the one thing this schema refuses to do, and its being
  one short line does not make it a pointer instead of a copy. `EventLinkChip` resolves the live
  name through `CalendarScreenState.eventForLink` while Kalender holds the event — so a renamed
  appointment renames every badge — and prints the date when it does not.
- **`event_starts_at` is the exception, and it is a date rather than content.** It is what makes
  the jump back work for an appointment outside the fortnight Kalender loads, which is most of
  them. On a task the same day is already in `due_date`, so it adds nothing there; on a list it
  adds one day per link. It goes stale if the appointment is moved, which costs a wrong day and
  never a wrong list.

No policy changes came with it. The link is an ordinary column on a container that already has a
complete access story, and `enforce_container_ownership` guards ownership, household and visibility
— none of which this touches. There is no edit path and no unlink: a list belongs to the event it
was made for, and deleting the list is how the link ends. Undo re-creates it with the link intact
(`ListNotifier.restoreList`), which is the one place it would otherwise be dropped silently.

## Privileged paths

RLS is `enable`d but **not** `force`d: forcing would apply policies to the table owner and break
the signup trigger and every service_role function — precisely the paths meant to be privileged.

Four Edge Functions in [supabase/functions/](../supabase/functions/) cover what RLS cannot express:
`invite-member` and `create-share-link` (they mint tokens), `accept-invite` and
`redeem-share-link` (they write rows the client must never write). The multi-statement logic lives
in SQL (`accept_family_invite`, `redeem_share_link` in `20260803100800_rpc.sql`) because
supabase-js cannot open a transaction; those functions take a user id and so are executable by
`service_role` only.

`remove-member`, `set-role`, revoking a link and kicking a guest need no function — plain RLS
writes, protected by triggers.

Two more cover spending. `spend-enroll` mints a **per-device** ingest token (only its SHA-256
reaches the database, same contract as the two above) and is the only way a `spend_ingest_devices`
row can exist — `authenticated` holds no INSERT grant on that table. `spend-ingest` takes one Apple
Pay transaction from the iOS App Intent and files it; it is the **second function pinned to
`verify_jwt = false`**, because the caller is a background automation on a locked phone that has no
session and can never have one. The device token, checked inside the function, is the entire
security boundary. See [docs/spend.md](spend.md).

`public.spends` is **admin-only** — every policy names `private.is_admin()` — and has no
`visibility` column and no `*_shares` table, because a spend row is not a container anybody owns a
private copy of. The permission matrix above pencilled Finanzen in as admin + member; it ships
narrower, and widening it is one `or private.my_role() = 'member'` in four policies.

Six more cover the calendar layer: `calendar-connect` (OAuth start/callback/disconnect — the only
function that must run with `verify_jwt = false`), `calendar-caldav` (iCloud, GMX, WEB.DE, and
IServ's secondary login), `calendar-link` (school calendars connected by a pasted link — IServ plugin feeds and
WebUntis), `calendar-events` (reads every connected account and subscribed feed), `calendar-write`
(creates, updates and deletes an event in a connected account) and `calendar-feed` (creates or joins
a public feed). They exist because a provider credential must be captured, stored and used somewhere the
client cannot see, which is the same reason `invite-member` exists. See the Calendar-connections
section of [docs/ported-features.md](ported-features.md) for the provider details and the
credentials to obtain.

**No calendar event is ever stored — from a connected account or from anywhere else.**
`calendar-events` proxies Google, Outlook, iCloud, IServ and WebUntis on every refresh and returns
them; the
offline copy lives in [lib/services/calendar_cache.dart](../lib/services/calendar_cache.dart) on the
device. The `external_uid` / `external_href` / `external_etag` columns are gone — there is no column
left in which to record which provider a stored event came from, which is what keeps this true
rather than merely intended.

`public.events` used to hold what somebody typed into Aporah itself, on a `provider = 'aporah'`
calendar. **That calendar no longer exists and cannot be created**: the leftover row is deleted, the
`provider` default is dropped and the check constraint now accepts only
`('google','icloud','outlook','iserv','webuntis')` — see migrations
`20260805182949_drop_own_calendar.sql` and `20260908130000_calendar_link_feeds.sql`. The
table is left standing but is empty and unreachable; the client never reads or writes it. Dropping
it is a separate decision nobody has made yet.

**Every write therefore goes out.** `calendar-write` takes one `calendars` row, resolves it to its
connection, and issues the create/update/delete against the provider — Google's
`calendars/{id}/events`, Graph's `/me/events`, or a CalDAV `PUT`/`DELETE` on the resource href. The
change appears in Aporah on the next `calendar-events` read, from the account, like any other event
of theirs.

Three details worth knowing before touching it:

- **Targeting is per calendar, not per connection.** We keep a `calendars` row per remote calendar
  with its `external_id`, so the function knows exactly which calendar to write to. The old web app
  had to try each of an account's calendars until one stopped returning 404 — that loop is gone,
  and with it the Graph extended-property trick it needed to carry a shared UID.
- **The family filter is the tenant boundary.** `service_role` sees every calendar, so
  `.eq('family_id', membership.familyId)` on both the calendar and the connection lookup is the
  only thing stopping one household writing into another's Google account. Do not remove it in the
  belief that RLS covers it — this client bypasses RLS.
- **Times travel as wall clock plus `Europe/Berlin`, never as instants.** A family types "14:00"
  and means 14:00; normalising to UTC in the app would freeze whichever offset applied on the day
  they typed it, and an event created in August would move an hour in November. All-day events use
  an **exclusive** end date throughout — model, wire, `DTEND;VALUE=DATE` and Google's `end.date`
  all agree on it.

### Recurrence, and the one occurrence in the middle of it

A `repeat` on the wire (`freq`, `interval`, `until`, `weekday`) becomes a rule in whatever shape the
provider takes. Google and CalDAV get an `RRULE`; **Graph does not accept one** and wants a
`pattern` + `range` object instead, and unlike iCalendar it infers nothing from the start — a weekly
pattern needs `daysOfWeek` spelled out and a monthly one needs `dayOfMonth`, which is what `weekday`
rides along for. `UNTIL` is inclusive and has to match `DTSTART`'s value type: a bare `DATE` for an
all-day series, and for a timed one the end of that day **in Berlin, expressed in UTC**
(`20261109T225959Z` in winter, `…T215959Z` in summer). Graph's `range.endDate` is a plain date and
needs none of that.

On an update, `recurrence` is included **only when there is a rule to state**. Both Google and Graph
take a PATCH as a merge, so omitting the key keeps the rule the event already has — sending a null
would strip it and turn a whole series into one appointment.

Then the part that bit us. **Google and Graph address an occurrence and its series by two different
ids** (`recurringEventId`, `seriesMasterId`), so "nur dieser Termin" and "ganze Serie" are the same
call on one id or the other. **iCalendar gives them the same UID.** `writeCalDav` used to look the
event up by UID and `PUT` a freshly built single VEVENT over whatever it found — which on a
repeating appointment replaced the series with one date: changing the time of one football training
silently deleted the rest of the term.

So nothing is written blind there any more. The resource is read first (`readEventIcs`), and if it
holds an RRULE the change is *amended into* it rather than replacing it, through `ical.js` rather
than through the text — the value that has to match is not a string but a moment in a particular
shape, whichever the master itself uses:

- **cancel one occurrence** → an `EXDATE`, plus the removal of any override already written for that
  day (`excludeOccurrence`);
- **change one occurrence** → a second VEVENT under the same UID carrying a `RECURRENCE-ID`, written
  fresh so editing the same Monday twice leaves one override rather than two (`overrideOccurrence`);
- **change the series** → the master edited in place (`editSeries`), keeping its rule, its EXDATEs
  and its overrides. **Exceptions are shifted by the same delta as DTSTART**, because an EXDATE names
  a slot the rule generates: move the series an hour and every one of them points at a moment that
  no longer exists, so the cancelled Monday comes back and the moved one detaches into a stray
  VEVENT. An override's own times are left alone — they were typed for that day.

`parseIcs` has the matching half: it relates overrides to their master (`relateException`) instead of
parsing them beside it. Without that, every single-occurrence edit Aporah writes would show **twice**
— once at the new time from the override, once at the old one from the rule.

One environment invariant the read path depends on: `parseIcs` resolves a floating `VALUE=DATE`
in the *runtime's* zone, and Edge Functions run in UTC. That is what makes all-day events land on
the right day. Round-tripping `buildVEvent` → `parseIcs` on a machine in CEST shifts them by one
day — the code is right, the laptop isn't. Run such a check with `TZ=UTC`.

Ferien and Abfall are the deliberate exception, in `public_feeds` + `family_feeds`. They are
municipal data, identical for everyone in a Bundesland or on a street, so one row serves every
household that subscribes to it. `public_feeds` is readable only where a `family_feeds` row exists
— the *contents* are public, but the list of feed keys names real street addresses, so an
enumerable table would enumerate where Aporah's households live. Neither table grants `insert` to
`authenticated`: a subscription is only ever created by `calendar-feed`, which first proved the
feed answers with real dates.

Everything a household decides about a feed is written on **its own `family_feeds` row**, never on
the shared one: the name, the colour, and `owner_member_id` / `owner_label` — the same owner pair
`calendars` carries, so a Schulferien feed can sit under the schoolchild it belongs to and the bins
under whoever puts them out. Both null is the household, which is what every subscription starts
as and what a feed used to be pinned to in code. The grants on this table are **column-level**, so
a new column is invisible until it is named in a `grant`; the row's policies (read: the household,
write: the household minus the kids) already decide who may touch it at all.

**A school calendar's link is a credential, and is stored like every other one.** IServ plugin
feeds and WebUntis subscriptions have no username or password — the tokenised URL *is* the whole
capability — so it is sealed under `CALENDAR_SECRET_KEY` and kept in
`calendar_connection_secrets.feed_urls`, one AES-256-GCM envelope per feed, keyed by the feed's
opaque id. What stays in `calendar_connections.config.feeds` is `[{id, name, host, added_at}]`,
and a check constraint refuses a `url` key there at all.

It was not always so. The URL sat in `config` in plain text, and the trade was written down twice:
"the only people who can read it are the household members already looking at the events it
returns". Two things were wrong with that. The smaller one is that the argument was already
rejected next door — 20260908155018 revoked every grant on `calendars` for the same reason, and
20260909101500 took `config` off the client's select list — so it survived only where nobody
re-read it. The larger one is that closing grants was never the whole job: the feed's id was the
URL, so the token was also sitting in `calendars.external_id` and in `selected_calendars` and
`calendar_names`, and those last two are **granted `SELECT` and `UPDATE` to `authenticated`**. Any
member could read every sibling's school feed out of the connection row with one PostgREST call,
the `kid` role included. 20260910070000 moved the URL and made the id a uuid; 20260910071500
removes anything the backfill did not reach and adds the constraint.

Adding a feed is still a `service_role` act in `calendar-link`, which fetches the URL first — an
unchecked URL written straight to `config` would be an outbound request this server then makes on
a schedule.

**A calendar can also arrive as a file, and that is the one place this app holds calendar bytes.**
A German waste vendor outside the six families in `_shared/abfall.ts` typically publishes
`abfuhr2027.ics` as a *download* and offers nothing to subscribe to; so does many a Verein. There
is no server on the other end to proxy to, so the file itself is kept — sealed, in
`calendar_connection_secrets.feed_files`, shaped exactly like `feed_urls` and opened for the length
of one parse. `config.feeds` says which of the two a feed is, in `kind`; an entry with no `kind` is
a URL feed, which is every entry written before 20260910120000.

Everything else about the arrangement survives, and the distinction is worth keeping straight. The
file is the **source**, not a cache of one: `calendar-events` re-parses it on every refresh and
writes no VEVENT to any row, so `public.events` is still empty and unreachable and there is still
no in-app calendar. It is `auth_type = 'public'` with `is_read_only`, so `calendar-write` has
nothing to target. It is not externally shareable, because `shareable_kind` names no calendar. And
it is encrypted for the reason the URLs are, only more so: a tokenised link is a pointer at a
calendar, and the file *is* the calendar.

Two behaviours follow from a file being a snapshot. A re-upload is matched on the **file name** and
replaces the bytes in place, keeping the feed's id, its name, its tick and its owner — which is how
a household moves to next year's Abfuhrplan without acquiring a second calendar with the same
title. And `covers_to` on the entry records the last event in the file, so the connect flow can say
how far it reaches; that is the only warning a household gets before a snapshot runs dry, and the
obvious next move is for `calendar-events` to put an expired one into `status_detail`, which is
client-readable where `config` is not.

Uploads are offered on the vendorless `ical` tile only. IServ and WebUntis both mint subscription
links, and a timetable frozen on its export date is worse than no timetable — `calendar-link`
refuses `ics` for any other provider.

**GMX and WEB.DE are one CalDAV provider wearing two brands.** Both are 1&1 Mail & Media, both run
the same server (`caldav.gmx.net` / `caldav.web.de`, path `/begenda/dav/<address>/calendar`), and
both answer RFC 6764 discovery — `/.well-known/caldav` redirects with a 307, which preserves the
PROPFIND method, and the endpoint offers Basic auth. So they are two rows in `PROVIDER_BASE` and
share every line of `discover` / `collections` / `writeCalDav` with iCloud. No OAuth registration,
no vendor approval, no typed-in server address. They are **writable**, unlike everything connected
by a link: an appointment made in Aporah reaches the household's real GMX calendar and therefore
the other parent's phone, which is the whole reason to connect an account instead of subscribing to
a feed.

Connecting one means **holding the user's password**, and there is no version of CalDAV where it
does not: every request authenticates with it, so there is no token to exchange it for. It goes
where iCloud's and IServ's already go — `calendar_connection_secrets.caldav_password`, sealed
AES-256-GCM under `CALENDAR_SECRET_KEY`. What the app does about it beyond that is ask for an
*application-specific* password, which both brands mint under Sicherheit →
Zwei-Faktor-Authentifizierung: it is revocable on its own, and it is the difference between holding
a key to a calendar and a key to somebody's mailbox.

**Provider credentials are stored twice-protected.** `calendar_connection_secrets` has no policy at
all and every privilege revoked from `authenticated`, *and* every value in it is an AES-256-GCM
envelope under `CALENDAR_SECRET_KEY`, a function secret that never reaches the database. The
stricter treatment compared to `token_hash` is deliberate: a share token hash is useless if it
leaks, an OAuth refresh token is a standing capability on someone's real Google account.

**Rotating `CALENDAR_SECRET_KEY` is a deploy, not a migration.** `seal` always uses the active key;
`open` tries it and then each key in `CALENDAR_SECRET_KEY_RETIRED` (comma-separated). So a
compromised key is replaced by moving it to the retired list and putting a fresh one in
`CALENDAR_SECRET_KEY` — every stored credential keeps opening, and new writes seal under the new
key. Trial decryption is sound because AES-GCM authenticates: a wrong key fails the tag check
rather than returning garbage. Drop a retired key once every connection sealed under it has been
written again; anything still on it degrades to `reconnect_required`, which `open` returning null
already produces.

**`calendar_connections.config` is not readable by the client.** For a link-connected school
calendar it holds the tokenised ICS URL — a bearer capability — so `authenticated` gets a column
list that omits it, exactly as `calendars` and `events` were revoked wholesale. The Flutter side
never wanted it: the repository selects a fixed list, and the `config` field on the Dart model is
filled from the Abfall coverage function's response, not from PostgREST.

**The `service_role` key never ships in the app.** Only the publishable (anon) key, via
`--dart-define`.

## Status

Applied to project **`uzhzrwakrtwbpuuupccu`** (eu-central-1). Migrations ran clean and the security
advisor reports **zero WARN- and ERROR-level findings** in the database.

### The policy helpers live in `private`, and the reason is worth keeping

All 17 predicates behind the policies (`can_read_list`, `my_family_id`, `is_admin`, …) were
`security definer` functions in `public`, which meant PostgREST published every one of them as
`/rest/v1/rpc/<name>`. None takes an "act as somebody else" argument — `can_read_list(uuid)`
answers about the caller — so the exposure was an oracle rather than a hole, but not one anybody
asked for.

**Revoking `EXECUTE` is not the fix.** An RLS policy expression is evaluated as the *querying*
role, so taking `EXECUTE` away from `authenticated` would take every policy in the database down
with it. Moving them out of the exposed schema is what keeps the policies working and removes the
URL.

The migration order is the whole trick, and it is worth repeating if another helper is ever added:

1. `alter function public.X(…) set schema private` — **preserves the OID**, and `pg_policy` stores
   parsed expressions by OID, so all 56 policies that reference these keep working *without being
   touched*. They simply start printing as `private.X(…)`.
2. `create or replace function private.X(…)` — also preserves the OID, which is what lets the
   bodies be repointed (they call each other by qualified name, since `search_path` is empty)
   without any policy noticing.

Recreating the functions under new OIDs instead would have meant rewriting every policy by hand.
That is the version of this change that goes wrong.

`may_share_externally` and `accept_family_invite` / `redeem_share_link` stay in `public` on
purpose — Edge Functions call them by name over `db.rpc()`, which only resolves in an exposed
schema. They are already granted to `service_role` only, which is why the advisor never flagged
them.

Two advisor findings remain and both are deliberate or dashboard-only:

- `calendar_connection_secrets` has RLS enabled and **no policies**. That is the design: zero
  policies is deny-all, and only `service_role` inside an Edge Function may ever touch a sealed
  credential.
- Leaked-password protection is off. Dashboard toggle, listed below.

**All 77 pgTAP assertions pass** against the deployed schema — 39 of them covering the
calendar-connection layer. They were run twice on purpose: once with the migration created inside
the same transaction, and again after it was applied permanently. Those are not the same test, and
only the second one proves the suite works against a schema it did not build itself.

Docker is not needed to run them. `supabase test db` wants a local stack, but the suite is just
SQL and runs fine against the remote database — wrap it in `begin; … rollback;`, create a temp
table for the TAP output, and `grant all` on that table to `authenticated` (the tests switch roles,
and a temp table owned by `postgres` is otherwise not writable once they do). Two details that cost
time: pgTAP 1.3.3 keeps **no** results table of its own, so each assertion has to be captured as it
returns (`insert into tap_out(line) select is(…)`); and if the temp table takes its ordering from a
sequence, `authenticated` needs `grant usage` on that sequence too. Verified afterwards that the
rollback left zero users, households, lists, grants and connections behind.

**Assertions that mutate must not read back in the same statement.** A subquery sees the
pre-statement snapshot, so `select ok(<mutate> and (select … ) = 'expected')` reports on stale data
— it manufactures both false failures and, worse, assertions that pass for the wrong reason. Do the
mutation in one statement and assert in the next. Where the point is that RLS *filtered* something,
use `public.test_rows_affected(...)` and assert zero rows, rather than inferring it from the absence
of an error.

**All seven Edge Functions are deployed and ACTIVE.** Six run with `verify_jwt` on and resolve a
caller before doing anything.

`calendar-connect` is the one exception: it runs with **`verify_jwt = false`**, because an OAuth
provider's redirect is a plain browser navigation and cannot carry an `Authorization` header — the
gateway would reject the callback before the function ever saw it. It therefore authenticates
callers itself: every path except the callback goes through `callerId()` (which validates against
the auth server, not merely decodes) and then a household lookup, and the callback is gated by an
AES-GCM `state` sealed at start time, which binds the household and expires after ten minutes.

The three calendar functions are deployed but **not yet functional** — they need the credentials
listed in the Calendar-connections section of [docs/ported-features.md](ported-features.md)
(`GOOGLE_*`, `MICROSOFT_*`, `CALENDAR_SECRET_KEY`, `CALENDAR_OAUTH_REDIRECT`,
`APORAH_APP_REDIRECT`). Deploying them early was the point: Supabase bundles server-side, so a
successful deploy is the only typecheck this project currently has for Edge Function TypeScript.
It is what proved `npm:ical.js@2` resolves in the edge runtime.

**Signup is verified against the real database.** Inserting an `auth.users` row (inside a
rolled-back transaction) produces the profile, a household named `Familie <Name>`, and an admin
membership, and `my_family_id()` / `my_role()` / `is_admin()` all answer correctly for that user
afterwards. So the trigger chain works end to end, not just in the pgTAP fixtures.

Not yet done, and all of it is dashboard-only — the MCP has no tool for any of it:

- **Custom SMTP.** `mailer_autoconfirm` is `false`, so confirmation is required, and Supabase's
  built-in mailer only delivers to project team addresses and is rate-limited to a couple per
  hour. Point Authentication → Emails → SMTP at Resend (`info@aporah.io`, the sender the old web
  app already used).
- **Function secrets:** `RESEND_API_KEY`, `APORAH_MAIL_FROM`, `APORAH_WEB_URL`. Without them
  `sendMail` reports `sent: false` rather than lying, and the invite UI falls back to
  "Link kopieren" — the raw token is returned once for exactly this reason.
- Leaked-password protection, OTP expiry ≤ 1 h, minimum password length. The
  HaveIBeenPwned check behind the first one is gated behind the Pro plan, so it lands with
  that upgrade rather than now.
- Redirect allowlist: `aporah://login-callback`, `aporah://invite/*`, `aporah://share/*`.
- Storage buckets.

**The 17 policy helpers no longer warn.** They were an accepted warning class for as long as they
sat in `public`, where PostgREST published each one at `/rest/v1/rpc/<name>`; moving them to
`private` (above) took the whole class off the advisor. Nothing was revoked to achieve it —
`authenticated` still holds `EXECUTE`, because a policy expression is evaluated as the querying
role and revoking would take every policy in the database down with it.

**The advisor baseline**, so a real regression is visible against it. Re-checked 2026-09-10.
Security: 0 ERROR; 1 WARN, leaked-password protection, the dashboard toggle listed above; 1 INFO,
`rls_enabled_no_policy` on `calendar_connection_secrets`, which is the design working rather than
a gap. That one was verified against the live database rather than assumed: RLS on, zero policies,
and the table's ACL names `postgres` and `service_role` only, so `anon` and `authenticated` are
refused with `42501` before row security is ever consulted. No view and no function in `public` or
`private` references the table, so there is no `security definer` path to it either, and every
value in it is sealed besides.

**Don't clear that INFO with a `using (false)` policy.** It changes nothing about access and gives
the table an access story that somebody could later widen; zero policies plus zero grants is the
stronger and more legible shape. Moving the table to `private` is not worth it either: the Edge
Functions reach it over PostgREST, which does not serve `private`, so it would cost a
`security definer` wrapper in `public` — new surface — to remove nothing but the table's name from
the schema cache.

Performance: 0 ERROR, 0 WARN, and INFO only — 27 `unindexed_foreign_keys` and 25 `unused_index`.

The unindexed-FK count rose from 19 to 27 when the trackers tables landed, and the new entries are
the same shape as the old ones. `calendars_connection_same_family (connection_id, family_check_id)`
is covered by `calendars_connection_idx` on its leading column only, exactly like the `*_shares`
composite FKs beside it. Left as is for now — it is a decision to take with real data,
not an oversight. The `unused_index` entries move around on their own: they come from
`pg_stat_user_indexes`, so an index drops off the list the moment anything touches it.

Note the local migration filenames use their own timestamps; the remote history was written by
`apply_migration`, so the two version tables differ. Reconcile before the first `supabase db push`.
The applied `calendar_connections` SQL is statement-for-statement the file in
[supabase/migrations/](../supabase/migrations/), with a few comment blocks trimmed.

See the migration list for what exists:

| Migration | Inhalt |
|---|---|
| `…100000_types` | Enums |
| `…100100_identity_tables` | families, profiles, family_members, family_invites |
| `…100200_identity_functions` | Policy-Helfer, `handle_new_user`, Escalation-Guards |
| `…100300_identity_rls` | Policies + Spaltenrechte für Identität |
| `…100400_content_tables` | lists/boxes/tasks/calendars + Items + interne Freigaben |
| `…100500_content_functions` | `can_read_*` / `can_write_*`, Ownership- und Removal-Guards |
| `…100600_content_rls` | Policies für alle Inhalte |
| `…100700_external_sharing` | share_links, guest_access, echte Gast-Prädikate |
| `…100800_rpc` | Transaktionale RPCs (nur `service_role`) |
| `…101000_calendar_connections` | Kalender-Verbindungen + verschlüsselte Secrets |
| `…20260805174643_avatar_pictures` | `avatars` Storage-Bucket + Policies |
| `…20260909170000_item_photos` | `boxes.photo_path`, `box_items.photo_path`, `box-photos` + `list-attachments` Buckets |
| `…20260910111610_fix_item_photo_storage_policies` | `objects.name` statt `boxes.name` in den sechs Storage-Policies — beide Buckets waren dicht |
| `…20260910112624_item_link` | `list_items.link_url` — die Produktseite, auf die ein Artikel zeigt |

Still to build: Realtime, the web landing page for share links, and the finance module.

## Storage: the `avatars` bucket

The first bucket, and the shape the two picture buckets copied.

- **Private, and `profiles.avatar_url` holds an object path — not a URL.** A public bucket would
  have been less code and would have put a photo of somebody's kid on an unauthenticated CDN URL
  that outlives the account. The client signs a URL per member at load
  ([`HouseholdNotifier._signAvatars`](../lib/state/family_state.dart)), one batched call for the
  whole roster, valid a week and re-signed on every load.
- **Layout is `<user_id>/<uuid>.<ext>`.** The owner is the first path segment, which is what all
  four policies key on: read is `private.can_see_profile(<owner>)` — household members plus the
  guest who may resolve a name on a list shared with them — and insert/update/delete are "your own
  folder", narrower on purpose than the admin checks everywhere else. Nobody, not even an admin,
  replaces another member's face.
- **The bucket's `allowed_mime_types` and `file_size_limit` (5 MB) are the real validation**, which
  is why the upload names its content type explicitly: the SDK's default
  `application/octet-stream` is not on the list and would be rejected.
- Each upload gets a fresh object name and the old one is deleted after the new one lands.
  Overwriting a fixed name would leave every signed URL already handed out — and every image cache
  holding one — serving the previous face until it expired.

## Storage: the picture buckets

Two more, added by `…20260909170000_item_photos`, and both follow the `avatars` shape above:
private, an object path in a column rather than a URL, one batched signing per load, a fresh object
name on every write. What is worth reading before touching them is the part that is *different*.

| Bucket | Holds | Named by | Layout |
|---|---|---|---|
| `box-photos` | one picture per box and per box item, images only, 10 MB | `boxes.photo_path`, `box_items.photo_path` | `<box_id>/<uuid>.<ext>` |
| `list-attachments` | the files on a list article, images + PDF + text, 20 MB | `list_item_attachments.storage_path` | `<list_id>/<uuid>.<ext>` |

- **The layout is the access rule, and the container is what it names.** An item photo is filed
  under its **box**, not under itself, and a list attachment under its **list**. That is not
  tidiness: an item inside a container has no visibility of its own — it inherits the container's —
  so the container is the only thing a storage policy can usefully ask about, and asking it takes
  one predicate instead of a join per row. Change the layout and the policies stop matching,
  silently and only for the people who are not the owner.
- **Read is `can_read_box` / `can_read_list`; write and delete are `can_write_*`.** Never household
  membership — a guest holding a share link on one box can read that box's rows, and a policy that
  asked "same household?" would hand them the words and keep the pictures back. Delete is
  `can_write_*` rather than "your own upload", because replacing a picture deletes the one it
  replaces and a box whose photo only its first photographer could change is a box with a wrong
  photo on it forever.
- **The subquery joins through the table on text, never casting the path segment to uuid.** A cast
  raises on a malformed object name, and an object nobody may read has to fail closed rather than
  error the whole listing. Same reason `avatars_read_visible_profiles` does it.
- **Inside that subquery the column is `objects.name`, qualified — always.** This is the bug that
  kept both buckets shut for a day. `…20260909170000_item_photos` wrote
  `where b.id::text = (storage.foldername(name))[1]`, and in a subquery over `public.boxes` the
  bare `name` is **`boxes.name`**: the predicate asked whether a box's uuid equalled the first path
  segment of the box's own name ("Keller"), which is false for every row there will ever be.
  Postgres resolved it silently, so all six policies were syntactically fine and semantically
  closed — nothing could be uploaded to either bucket and nothing could be read back, and the
  only symptom was "Foto konnte nicht hochgeladen werden". Fixed in
  `…20260910111610_fix_item_photo_storage_policies`. A storage policy that joins another table
  must write `storage.foldername(objects.name)`, the way `avatars_read_visible_profiles` always
  did.
- **Undo copies, it does not re-key.** Restoring a deleted box or list re-inserts under a fresh
  uuid, so the old `photo_path` names an object no container owns any more. `PhotoRepository.copyTo`
  puts a copy under the new id and the row is pointed at that; the original is left as litter.
  Best-effort per picture — a box that comes back missing one photo beats a box that does not come
  back.
- **`list_item_attachments` was in the schema from the first migration and had no bucket until
  now.** Until this migration the Listen attach menu wrote to a `Map` on `ListState` and the photos
  died with the process. They are stored, signed and shared with the household now; anything still
  saying otherwise is out of date.
- **What loads before the screen, and what arrives after.** The household read is the gate every
  screen waits behind (`HouseholdNotifier.load`), so it holds exactly three round trips —
  membership, then `families` and the roster together, then the profiles — and publishes. The
  **signed avatar URLs and the pending invitations come after** it, and Listen and Boxen do the
  same with their pictures: one read for the containers, then their shares/items/grants together,
  then the attachment rows and their signed URLs once the articles are already on screen. Photos
  are what makes this worth writing down — every picture in the app costs a *second* round trip to
  sign a private object, and a signing call on the critical path is a screen that stays blank to
  show a thumbnail a moment earlier. **Put a new picture behind the rows it decorates**, and let
  the circle show its initials or its symbol in the meantime.
- **A link is a column, not an attachment row.** `list_items.link_url` holds the shop page an
  article is about — the one thing the attach menu was missing, and the thing a family most often
  agrees on before somebody goes shopping. It is deliberately not a row in
  `list_item_attachments`: every path through that table signs, copies or deletes a storage object,
  so a row with no object would be a row whose `storage_path` lies. One link per article rather
  than a list, for the same reason a box has one photograph. **Nothing server-side ever fetches
  it** — no preview, no title, no picture scraped off it; it goes to `UIApplication.open` and no
  further, so no third party learns what a household is shopping for.
  `list_items_link_url_shape` is the only validation: an `http(s)` scheme and a sane length, with
  the client normalising a pasted `amazon.de/…` to `https://` before it gets here.
- **Orphans are accepted.** Deleting a box or a list leaves its objects behind (undo needs them),
  and nothing sweeps them up. They are unreachable — the read policy has no row left to match — so
  the cost is bytes, not exposure. A cleanup job is a backend task nobody has needed yet.
