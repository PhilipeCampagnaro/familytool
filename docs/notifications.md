# Notifications, and asking for five stars

**Status (2026-09-14): local notifications and the rating prompt are built, analyze-clean and
untested on a device. Push is not started.** What exists: the `aporah/notifications` and
`aporah/review` channels on both platforms, the scheduler
([lib/state/notification_scheduler.dart](../lib/state/notification_scheduler.dart)), Settings →
Mitteilungen, the reminder row on an appointment, and the provider's own alarm on the wire.
**Nothing Android has been compiled** (no SDK on the machine), and the `calendar-events` change is
**written, not deployed** (no `deno` or Supabase CLI here). Tick the boxes at the bottom as they
become true.

### What was built differently from the plan below, and why

- **No Flutter plugins, on either platform.** The iOS app builds through Swift Package Manager with
  no Podfile, and `flutter_local_notifications` / `in_app_review` both ship an iOS half — the first
  also installs its own notification-centre delegate. So both channels are hand-written in Swift
  *and* Kotlin, the `aporah/spend` precedent: `LocalNotifications.swift`, `AppReview.swift`,
  `LocalNotifications.kt`, `NoticeReceiver.kt`, `AppReviewChannel.kt`, plus
  `com.google.android.play:review` as a Gradle dependency, which does not reach iOS.
- **Abfall is 19:00 the evening before, and says so as a question** — *"Bioabfall schon
  rausgestellt?"* — because pickup is around 06:00 and only the night before can still get a bin to
  the kerb. The bin is named with the vendor's own word, the one printed on the calendar.
- **No quiet hours.** Every notice that exists has a time the user chose (a reminder, the brief,
  the bins, a to-do's hour), so there is nothing for quiet hours to silence. It returns with push
  (N5), where somebody else's action picks the time.
- **Defaults:** brief on where iOS can deliver it provisionally, off on Android (no quiet grant
  there); Abfall on; to-dos with a time on. The real prompt is asked when a reminder is set, a
  switch is turned on, or an Abfall calendar is connected — never at launch.
- **A CalDAV occurrence that is moved loses its reminder.** A one-off follows its appointment
  anywhere (keyed on calendar + uid); an occurrence of a series is also keyed on its start, because
  CalDAV gives the whole series one UID.
- **A tap opens the app and nothing more.** Opening the appointment itself is not built.
- **The Settings "Aporah bewerten" row is absent on iOS until `_appStoreId`** in
  [lib/services/app_review.dart](../lib/services/app_review.dart) is filled in — there is no listing
  to link to yet.
- **The rating triggers are two, not three**: a list of three or more articles fully ticked, and a
  tracker reaching exactly seven. "A calendar connected" was dropped — it happens in week one, which
  the 14-day floor refuses anyway.
---

## The principle, before any list of triggers

**A notification is for something with a deadline or somebody's name on it.** Creation is neither.

This is the whole design and it is worth more than any feature below, because a family app's
notification budget is spent once. If a new box in the cellar inventory buzzes four phones, the
household turns notifications off inside a week — and then the one that mattered, *"Zahnarzt in 30
Minuten"*, is off too. Every trigger in this document has to answer one question: **would a
reasonable parent be annoyed to be interrupted for this?** If the answer is anything but a flat no,
it goes in the morning brief instead of on the lock screen.

Two corollaries that decide real cases:

- **Assignment, not creation.** A to-do with `assignee_id` pointing at you is your problem and
  earns a notification. A to-do created with no assignee is a note on a shared fridge and earns
  nothing. The axis already exists — see the three-axes rule in CLAUDE.md — and this is the second
  thing it is good for.
- **Bursts are the failure mode.** Boxen are created ten at a time during onboarding, lists three
  at a time on a Sunday. Any trigger that fires per-row created must be either dropped or
  coalesced, and coalescing a creation notification produces "3 neue Listen", which is a sentence
  nobody needs at 21:40.

---

## Two mechanisms, and most of the value is in the cheap one

### Local notifications — scheduled on the device

`UNUserNotificationCenter` on iOS, `AlarmManager` + `NotificationManager` on Android. No server,
no token, no Apple push key, no Firebase project, works with the phone in flight mode.

Right for everything where **the device already knows when**: an appointment's reminder, a to-do
due at 17:00, the Bio-Tonne going out tomorrow, the morning brief. That is the majority of what
this app should ever say.

### Remote push — APNs and FCM

Needs an Apple push key (`.p8`), an FCM project, a `device_push_tokens` table and a fan-out Edge
Function. Right for exactly one class of thing: **somebody else did something you need to know
about**, which a sleeping device cannot work out for itself.

**Build local first, and completely, before touching push.** Local covers the calendar reminder
this was started for, it covers Abfall, it covers to-dos, and it ships without an Apple push key,
a Firebase account or a single new table. Push is a week of infrastructure for a smaller set of
notifications, and it is the half that can wait.

### The third option, named so it is not rediscovered later: a VALARM on the provider's event

`calendar-write` could put the reminder into the Google/Outlook/CalDAV event itself, and the
phone's own calendar app would fire it — on the watch and the Mac too, which is better than
anything we can do. It is rejected as the *default* for three reasons and kept as a possible
extra later:

1. **It cannot cover the read-only calendars, which is where the best reminder lives.** Abfall is
   `is_read_only` by nature; so are Ferien and every pasted school feed. "Bio-Tonne morgen früh"
   is arguably the single most useful thing this app could say to a German household, and the
   VALARM route cannot say it.
2. It edits somebody's real calendar entry for a preference that is one person's.
3. It arrives wearing the calendar app's name, not ours.

But the *reading* half of it matters immediately — see the next point.

### `CalendarEvent.reminder` is dead, and is the right field pointed at the wrong source

[lib/models/calendar_event.dart](../lib/models/calendar_event.dart) parses `reminder_minutes` and
renders `L.s.reminderMinutesBefore`. The only `reminder_minutes` in the repository is a column on
`public.events` — the table that is empty and unreachable — and `calendar-events` never emits it.
The field is always `''`.

**Repurpose it rather than delete it.** `providers.ts` should extract the provider's *own* alarm
(Google `reminders.overrides` / `reminders.useDefault`, Graph `reminderMinutesBeforeStart` +
`isReminderOn`, iCal `VALARM` `TRIGGER`) and put it on the wire. Without it the reminder sheet
cannot tell a user that Google is already going to buzz them 10 minutes before, and the feature's
first impression is **two notifications for one appointment**.

---

## What each feature actually justifies

### Kalender — event reminders (the ask, and it is the right one)

A row in the event detail sheet: **Erinnerung** — Keine / 10 / 30 Minuten / 1 Stunde / 1 Tag
vorher, plus a custom picker. Below it, greyed, the provider's own alarm when there is one
("Google erinnert bereits 10 Minuten vorher"), so nobody sets a duplicate by accident.

**The reminder is personal and lives on the device.** An appointment belongs to the household;
"remind *me*" does not. That means no table, no RLS, no sync, no push — a local store of
`{calendar_id, uid, starts_at, minutes_before}` rows, keyed on the same `(calendar, provider uid)`
pair [event_link.dart](../lib/models/event_link.dart) already uses, because **we store no events
to hold a foreign key to**. The cost is honest and should be written in the UI nowhere and in this
file here: a reinstall loses them and the iPad does not have them. That is the correct trade for
v1; making it sync means a table and a push, and is Phase N4 at the earliest.

**Rescheduling is the whole implementation.** An external event can move, be cancelled, or be one
occurrence of a series, and we find out on the next `calendar-events` read. So the device never
"schedules a notification" as a one-off action — it **re-derives the whole pending set from the
stored rows plus the freshly-loaded events**, on every calendar refresh and every foreground. An
event that moved gets a new time, one that vanished gets cancelled, a series gets its next few
occurrences and no more.

> **The 64 limit is a hard constraint, not a detail.** iOS keeps only the **64 soonest pending**
> local notifications per app and silently drops the rest — no error, no warning, the notification
> simply never arrives. Every category in this document draws from the same 64. So the rolling
> window is mandatory: schedule the soonest ~50 across all categories, reserve the rest, and
> re-derive on every foreground. Anything that "schedules everything" is a feature that works in
> testing and fails in a household with four children.

### Kalender — Abfall

Opt-in per household, **evening before, default 19:00**: "Morgen: Biotonne, Papiertonne." A bin
put out at 07:00 was put out the night before. This is local, it is one notification, it is the
reason half of a German family app's users would keep notifications on at all, and `feedKind ==
'abfall'` plus `binColorFor` already give it everything it needs.

### Home — the morning brief (build this first; it is the highest-value notification in the app)

**One notification a day, 07:00, off by default and offered once.**

> *Heute: 3 Termine · Bio-Tonne raus · 2 To-dos fällig*

Home already computes precisely this — `day_island.dart`, `home_sections.dart`. It is local, it
cannot spam by construction, and it is the notification that makes somebody open the app rather
than the one that makes them close it.

**It is composed ahead of time from cached data**, because a local notification needs its text at
scheduling time, not at firing time. `calendar_cache.dart` plus the loaded tasks give tomorrow's
brief tonight. **Schedule at most two days ahead and let it lapse**: if the app has not been
opened in three days, the brief would be a lie, and no notification beats a wrong one.

### Board — to-dos

- **Due today**, folded into the morning brief. Not its own notification.
- **`due_time` reached** — its own local notification, and only for a to-do that has one.
  `due_time` is nullable and most rows will never have it, which is exactly what makes it a good
  trigger: setting an hour on "Kita abholen" is the user *asking* to be reminded.
- **Assigned to you by somebody else** — push, Phase N4. `assignee_id != auth.uid()` on the writer
  side, and never for a self-assignment.
- **Never "overdue".** CLAUDE.md is explicit that Überfällig is a section, not a nag, and the
  `due_time` migration says the same in its own words. A phone that buzzes about a to-do somebody
  already feels bad about is the thing that gets an app deleted.

### Board — Tracker

**Nothing by default, and think hard before adding anything.** A tracker is *never overdue* by
design — "a day it was not kept is a gap in the record, not a row that follows anybody around" —
and a notification is the most literal way to make it follow somebody around. If a nudge is ever
built it is **per-tracker, opt-in on that tracker's own screen**, phrased as a time of day the
household chose, and it never mentions a streak being broken.

The one tracker-adjacent notification that is unambiguously good is the **rating trigger** (below):
a 7-day streak is a small win the user just caused.

### Listen

- **List completed** — no notification. It is a nice moment and it is the rating trigger, not a
  buzz.
- **New list created** — **no.** This was asked for and it should not be built as asked. Lists are
  created in bursts, the creation carries no deadline and no name, and the household sees it live
  already through the realtime channel the next time anyone opens the app.
- **A list shared with you outside the household was opened / a guest added something** — push,
  Phase N4, and worth it: that is somebody outside the family touching the household's data.

### Box

**No notification for a new box, and none for a new item.** Same reasoning as Listen, more so: Boxen
is an inventory, inventories are filled in sittings, and nothing in a box has a deadline. If the
household wants to know what changed, the app is where that lives.

### Ausgaben

The strongest push case in the app, and the only one where **the app acted on its own**:

- **A spend was filed while the phone was locked** — the Apple Pay intent or the Android wallet
  listener wrote a row nobody typed. The payer's own device should say so. Quietly: one line,
  merchant and amount.
- **`needs_review`** — Apple's trigger handed over an empty merchant or a zero amount, or Android
  had to guess from a sentence. This one needs a human and should say so plainly.
- **Admin only**, matching the policies. `spend-ingest` runs `service_role` on a locked phone with
  no client to announce for it, so this is the one trigger that **must** be server-side — exactly
  the split `realtime_state.dart` already describes for its two senders.

### Household and sharing

All push, all Phase N4, all low-volume and all genuinely wanted:

- An invite was accepted / somebody joined the household
- A share link you minted was redeemed for the first time
- Your role changed

### Never

Anything on a `list_items` tick, anything on a photo upload, anything on a calendar refresh,
anything about the app itself except a release note the stores already deliver, and **anything at
all between 22:00 and 07:00** except an appointment reminder the user set with their own hands.

---

## Asking for a rating

### The correction first: **neither platform will tell you whether somebody has rated.**

This was the requirement — "only ask users who have not rated yet" — and it cannot be satisfied
directly, on either store. `SKStoreReviewController` has no callback and no return value. Google's
`ReviewManager.launchReviewFlow` completes identically whether the user left five stars or swiped
the sheet away. Both are deliberate: Apple and Google do not want apps behaving differently toward
people who did not rate them.

**What actually protects the user is that the OS already does most of this job.** iOS shows the
prompt at most **three times per app per 365 days**, and suppresses it entirely for a user who has
already rated the current version — the call simply does nothing, with no sign that it did nothing.
Play applies its own undocumented quota the same way. So the requirement is met by the platform for
the case that matters, and our job is the other half: **not burning the three attempts the system
allows us.**

### The rules we enforce ourselves

Stored locally in `shared_preferences` — `askCount`, `lastAskedAt`, `lastAskedVersion`,
`firstLaunchAt`:

- Never before **14 days** of use and never during onboarding.
- Never more than **once per app version**, never within **120 days** of the last ask, at most
  **twice ever per year** — one below the platform's three, so there is always one left for a
  version that deserves it.
- **Never from a button.** Apple's HIG forbids prompting in response to a user action, and the
  system may ignore it. A "Aporah bewerten" row in Settings therefore opens the store page
  directly (`https://apps.apple.com/app/id<ID>?action=write-review`,
  `market://details?id=com.aporah.aporah`) — that path is unlimited, costs no quota, and is where
  a willing user goes.
- **Never after a failure**, never while an error toast is up, and **never in the minutes after the
  paywall was dismissed without a purchase.** Someone who just declined to pay €4.99 is not the
  person to ask for five stars.

### The happy moment

Ask on a small win the user has just caused, never on a timer:

1. **A shopping list has just been fully ticked off** — the best of the three: it is frequent,
   it is unambiguous, and the app just helped with the errand.
2. **A tracker reached a 7-day streak** — open the tracker's screen, see the record, then ask.
3. **A calendar account connected and its events appeared** — the app's "it works" moment, but it
   happens in week one, so it collides with the 14-day floor for most people. Keep it third.

Fire on the **next frame after the celebratory UI settles**, not during an animation.

### Implementation

Following the project's own split — UIKit on iOS, plugin on Android:

- **iOS: a method channel, `aporah/review`**, registered in `AppDelegate.swift` beside
  `aporah/menu`. `AppStore.requestReview(in: scene)` on iOS 16+, falling back to
  `SKStoreReviewController.requestReview(in: scene)`.
  > **The deployment target is 15.0, not 13.0.** `IPHONEOS_DEPLOYMENT_TARGET = 15.0` in all three
  > build configurations; CLAUDE.md line 399 still says 13.0 and is stale. It matters here: at 15.0
  > the scene-based `requestReview(in:)` needs no availability guard at all, and only the
  > StoreKit 2 call does. **Fix that line in CLAUDE.md** — an availability ladder written against
  > the wrong floor is how a `#available` branch that can never run gets shipped and never tested.
- **Android: `in_app_review`**, or a thin `ReviewManager` channel. The Play flow only works in a
  build **installed from Play** (internal testing counts) — on a sideloaded debug build it fails
  silently, which reads as "the code is broken" and is not.
- **One Dart service** over both — `lib/services/app_review.dart`, `reviewAvailable` mirroring
  `spendAvailable`, a no-op everywhere else — and **one place that decides**, so the eligibility
  rules exist once rather than at each of the three trigger sites.

---

## Push infrastructure, when we get there

### `public.device_push_tokens`

Shaped deliberately like `spend_ingest_devices`: `family_id`, `user_id`, `device_uid` (iOS
`identifierForVendor`), `platform`, `token`, `locale`, `created_at`, `last_seen_at`, `revoked_at`,
`unique (user_id, device_uid)` so a reinstall **replaces** rather than accumulates, and the same
composite FK onto `family_members` so enrolment dies with the membership and there is no cleanup
code.

> **The token is stored raw, and that is not an oversight.** `spend_ingest_devices` stores a
> SHA-256 because the token is a *credential that writes*. A push token is an *address we send to*
> — hashing it makes it useless. Written down here so nobody "fixes" it later.

**`authenticated` may INSERT this one**, which diverges from the rule that containers are created
only by Edge Functions. The reason that rule exists is that a connection has to be *proved* before
it counts; a push token has nothing to prove. An own-row insert policy is correct and cheaper.

### `push-send`, one function with two callers

Exactly the split `realtime_state.dart` already documents for its broadcast channel:

- **The client announces its own writes** — the same moment it calls `announce()`. CLAUDE.md's
  own note (commit `fbeacc0`) is that we send from the client *because the trigger cannot*.
- **The server sends what no client made** — `spend-ingest` on a locked phone, and only that.

### **The text is rendered per recipient, not per sender**

The household speaks four languages and a Brazilian mother and a German father can be in the same
family. So `push-send` **must not accept a rendered string**. It takes a **key plus parameters**
and renders from the `locale` on each recipient's token row. That means a small TypeScript string
table for the ten or so push strings — a fifth copy, deliberately, and kept to ten strings by the
principle at the top of this file.

### APNs without Firebase

Talk to APNs directly with token-based auth — a `.p8` key and an ES256 JWT, about sixty lines of
Deno. Android needs FCM HTTP v1 and there is no way around it, but **iOS does not have to route
through Google**, and keeping it out matches the app's stance on the Maps key and on Open-Meteo.

### Permission, and a trap specific to this app

- Ask **at the moment of first value** — when the user sets their first reminder, or from a Home
  first-step row — never at launch.
- **Provisional authorization (`.provisional`) is worth using for the morning brief**: it delivers
  quietly to Notification Centre with *no prompt at all*, and the user promotes it if they like it.
  For a brief that is trying to earn its place, that is a better first contact than a permission
  dialog on day one.
- Android 13+ needs the `POST_NOTIFICATIONS` runtime permission.
- **The Android trap.** That phone is already being asked for
  `BIND_NOTIFICATION_LISTENER_SERVICE` so Ausgaben can *read* the wallet's notification — the
  heaviest grant in the app, with its own prominent-disclosure card. Adding a *post* permission
  means the user now sees two notification-shaped asks. They must be explained in separate places
  with separate copy, or the read-grant — the one that genuinely needs the user's trust — starts
  looking like the innocuous one and the disclosure stops doing its job.

---

## Order of work

- [x] **N1 — Local, no server.** Permission flow (provisional on iOS), the scheduler with the
      60-slot window re-derived on every change and every foreground, the event reminder row, Abfall
      the evening before, `due_time` to-dos, the morning brief. *Analyze-clean; not yet run on a
      device; Android never compiled.*
- [ ] **N1a — Carry the provider's own alarm on the wire.** Google popup reminders (including the
      calendar's defaults), Graph `reminderMinutesBeforeStart`, CalDAV `VALARM`; never for a pasted
      feed. `CalendarEvent.providerReminderMinutes` replaced the dead string and the row reads it.
      **Written, not type-checked, not deployed** — `supabase functions deploy calendar-events`.
- [x] **N2 — Settings: Mitteilungen.** Grant state with the action that fits it, three switches,
      two times, four languages. Quiet hours dropped — see above.
- [x] **N3 — Rating.** `ReviewPrompt` plus both channels. Fixed the 13.0/15.0 line in CLAUDE.md.
      Still needs the App Store id before the iOS Settings row appears.
- [ ] **N4 — Push infrastructure.** Table, `push-send`, APNs `.p8`, FCM project, per-recipient
      localisation. Needs an Apple push key and a Firebase project from you.
- [ ] **N5 — Family triggers over push.** Assignment, invite accepted, share redeemed, spend filed
      and `needs_review`. Quiet hours land here.
