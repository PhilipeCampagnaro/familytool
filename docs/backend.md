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
| Liste / Box / Aufgabe / Kalender anlegen | ✅ | ✅ | ✅ | ❌ |
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
5. **Attachments.** Storage policies must key on `can_read_list(...)` alone, never on household
   membership, or guests silently lose photos on shared items.
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
`list_repository.dart` — `id` carries no policy, `gen_random_uuid()` is only a column default),
inserting without a representation, and reading the row back in a second statement. The read-back
earns its round trip: it is what proves the creator can actually see what they just made. Child
rows and every update keep `.select()`.

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

Five more cover the calendar layer: `calendar-connect` (OAuth start/callback/disconnect — the only
function that must run with `verify_jwt = false`), `calendar-caldav` (iCloud and IServ),
`calendar-events` (reads every connected account and subscribed feed), `calendar-write` (creates,
updates and deletes an event in a connected account) and `calendar-feed` (creates or joins a public
feed). They exist because a provider credential must be captured, stored and used somewhere the
client cannot see, which is the same reason `invite-member` exists. See the Calendar-connections
section of [docs/ported-features.md](ported-features.md) for the provider details and the
credentials to obtain.

**No calendar event is ever stored — from a connected account or from anywhere else.**
`calendar-events` proxies Google, Outlook, iCloud and IServ on every refresh and returns them; the
offline copy lives in [lib/services/calendar_cache.dart](../lib/services/calendar_cache.dart) on the
device. The `external_uid` / `external_href` / `external_etag` columns are gone — there is no column
left in which to record which provider a stored event came from, which is what keeps this true
rather than merely intended.

`public.events` used to hold what somebody typed into Aporah itself, on a `provider = 'aporah'`
calendar. **That calendar no longer exists and cannot be created**: the leftover row is deleted, the
`provider` default is dropped and the check constraint now accepts only
`('google','icloud','outlook','iserv')` — see migration `20260805182949_drop_own_calendar.sql`. The
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

**Provider credentials are stored twice-protected.** `calendar_connection_secrets` has no policy at
all and every privilege revoked from `authenticated`, *and* every value in it is an AES-256-GCM
envelope under `CALENDAR_SECRET_KEY`, a function secret that never reaches the database. The
stricter treatment compared to `token_hash` is deliberate: a share token hash is useless if it
leaks, an OAuth refresh token is a standing capability on someone's real Google account.

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
- Leaked-password protection, OTP expiry ≤ 1 h, minimum password length.
- Redirect allowlist: `aporah://login-callback`, `aporah://invite/*`, `aporah://share/*`.
- Storage buckets.

**One accepted warning class.** The advisor flags 17 policy helpers (`my_family_id`,
`can_read_list`, …) as callable by signed-in users at `/rest/v1/rpc/<name>`. They need `EXECUTE`
for `authenticated` or RLS cannot evaluate them, so revoking is not an option. Each only answers
about the caller's own access, which bounds the disclosure to an existence oracle on ids the caller
already holds. The proper fix is relocating them to a schema PostgREST does not expose — that
requires rewriting every body, since `LANGUAGE sql` bodies are stored as text and their
`public.`-qualified calls would not follow the move. Worth doing before launch.

**The advisor baseline**, so a real regression is visible against it. Security: 0 ERROR, the 17
WARN above, and 1 INFO — `rls_enabled_no_policy` on `calendar_connection_secrets`, which is the
design working, not a gap: RLS on, no policy for anyone, every privilege revoked. Performance:
0 ERROR, 0 WARN, and INFO only — 19 `unindexed_foreign_keys` and a handful of `unused_index`.

The 19th unindexed FK is `calendars_connection_same_family (connection_id, family_check_id)`;
`calendars_connection_idx` covers only the leading column, exactly like the four `*_shares`
composite FKs already on that list. Left as is for now — it is a decision to take with real data,
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

Still to build: Realtime, the web landing page for share links, and the finance module.

## Storage: the `avatars` bucket

The one bucket there is, and the shape any later one should copy.

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
