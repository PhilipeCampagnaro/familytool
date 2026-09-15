# Aporah

A Flutter family-organizer app (Home, Kalender, Listen, Board, Box tabs) built from a Figma
handoff (`design_handoff_aporah_flutter/README.md` — tokens in
[lib/theme/tokens.dart](lib/theme/tokens.dart) come from it). **German, English, Portuguese and
Spanish, switched in Settings — never hardcode a user-facing string.** See the localization section
below.

Scope: **core features only** — Board, Box, Listen, Kalender, plus Ausgaben (Apple Pay spend
tracking, rebuilt rather than ported — see [docs/spend.md](docs/spend.md)). Explicitly out of scope:
the KAI AI assistant — don't port it even if the old codebase shows it, including the DeepSeek
merchant fallback Ausgaben deliberately leaves out.

## Deep-dive docs — read on demand, not proactively

Keep this file lean; detail lives in [docs/](docs/) and is only worth loading for the matching
task:

- [docs/kalender.md](docs/kalender.md) — Kalender internals (week/month view, filter chips,
  collapsing headers, persistence, timeline, "Heute" button) **and Home**, which is the week view
  plus four slots it fills. **Read before changing calendar or Home
  behavior.**
- [docs/design-system.md](docs/design-system.md) — glass/frosted-header gotchas, shared widget
  index, animation conventions. Read before touching `lib/widgets/` or adding animations.
- [docs/spend.md](docs/spend.md) — Ausgaben: the Apple Pay App Intent, the device token, the SQL
  merchant classifier, and the notification listener Android captures with instead. **Read before
  touching spend tracking, the Shortcuts integration or the Android allowlist.**
- [docs/ported-features.md](docs/ported-features.md) — knowledge captured from the old web app
  (grocery lists, onboarding, Settings, weather, calendar connections). Read the one section for
  the feature you're building; each says whether it is built or still groundwork.
- [docs/notifications.md](docs/notifications.md) — what the app notifies about and why the list is
  short, the local scheduler and its 64-request ceiling, the rating prompt's rules. **Read before
  adding a notification of any kind.**
- [docs/production-plan.md](docs/production-plan.md) — **the road to both stores, and the record of
  where we stopped.** The free/Plus split and the €4.99 price, the four iOS-only method channels
  Android still needs, the three separate mechanisms behind a live calendar, and the two legal
  items with months of lead time. **Read it before starting a session of plan work, and tick the
  box in it when a task is done** — it is the only place that says what is finished.

## Stack

- Flutter (Dart ^3.12.2), Material app shell. **No `go_router`/named routes** — navigation is a
  single `IndexedStack` of five always-mounted screens switched by index
  ([lib/main.dart](lib/main.dart)).
- State: `flutter_riverpod` (`StateNotifier` + `StateNotifierProvider`), one notifier/state pair
  per screen — `boardProvider`, `boxProvider`, `listProvider`, `calendarProvider`, plus
  `trackerProvider` beside `boardProvider` ([lib/state/](lib/state/)). Screens are
  `ConsumerWidget`s; read with `ref.watch`, mutate via
  `ref.read(xProvider.notifier).someMethod()`. Use this pattern for anything new rather than
  introducing another state-management approach.
- **The Board holds two different objects, and the create sheet asks which.** A **To-do** is
  one-off: it has a due date or none, it goes Überfällig when it is missed, and finishing it takes
  it off the list. A **Tracker** is a rhythm the household keeps — daily, on chosen weekdays, or a
  number of days per week — and it is **never overdue**: a day it was not kept is a gap in the
  record, not a row that follows anybody around. `public.trackers` stores the rule and
  `public.tracker_checks` one row per day it was met; which days were *due* is computed from the
  rule ([lib/data/tracker_data.dart](lib/data/tracker_data.dart)), never materialised, for the same
  reason `german_holidays.dart` computes the Feiertage. **The header's day grid counts trackers
  only** — counting whatever tasks happened to fall on a day is exactly what made a to-do read as a
  habit. Don't put a tracker in a dated section, don't give one an `is_done` column, and don't make
  one externally shareable: `shareable_kind` names no value for it on purpose. **The card lists what
  today's rhythms ask for; everything else folds in behind one counted row** (`trackersOffToday`) and
  those rows carry **no check circle** — being listed is not being due. Tapping a row opens
  **that tracker's own screen** ([lib/screens/board/tracker_detail.dart](lib/screens/board/tracker_detail.dart)),
  a mode of Board keyed on `TrackerState.openId` the way Listen opens a list — not a route. Its chart
  reads like the Board header's — left to right, then down, today in the last row — in rows of whole
  weeks under Mo–So letters, and its squares are **tappable, to back-fill a day somebody forgot
  to tick**; a weekly count gets bars per week instead, because it owes no particular day. Keep the
  three states apart there: a day the rhythm never asked for is neutral, never a pale "missed", or a
  Mo/Do tracker reports five failures a week of a perfect record.
- **Localization: German, English, Portuguese and Spanish, and every user-facing string goes
  through [lib/l10n/](lib/l10n/).** `AppStrings` declares them and `StringsDe`/`StringsEn`/
  `StringsPt`/`StringsEs` answer them — 866 members each — and `L.s.someString` reads the live one.
  Because `AppStrings` is abstract, a string you add to one language and forget in another **fails
  to compile** — that is the point, so don't work around it with a map or a `??`. Portuguese is
  **Brazilian (pt-BR)** and Spanish is peninsular (es-ES); `appSupportedLocales` carries bare
  language codes, so a pt-PT or es-MX phone resolves to them rather than falling back to German.
  Brazilian is a decision, not a default — *senha*, *celular*, *ônibus*, and **"Carregando…"** where
  Portugal says *"A carregar…"*. Money follows it: `money()` puts the symbol **before** the number
  (`R$ 1.234,56`), which is the one place pt-BR does not simply inherit the German shape.
  - **Content catalogs are the deliberate exception, and they use `pickLabel` instead.** The
    grocery icons and the curated symbol set carry their own labels rather than
    going through `AppStrings`: content has to stay cheap to add, and a PNG that needs four
    translations before it compiles is a PNG nobody adds. `pickLabel(de:en:pt:es:)` in
    [lib/l10n/l10n.dart](lib/l10n/l10n.dart) falls back to **English**, and
    `dart tool/check_catalog_labels.dart` reports what is still missing — run it after touching
    `grocery_catalog.dart`, and leave it saying `OK`.
  - **What is German market data rather than German text, and is therefore still German-only:**
    the Feiertage (`german_holidays.dart`; a Portuguese or Spanish household sees **no public
    holidays at all** — see the note in [lib/state/holidays_state.dart](lib/state/holidays_state.dart)),
    the Ferien Bundesland picker, the six waste-vendor families in `abfall.ts`, and IServ/WebUntis.
    Translating the UI did not port any of it, and that is written down rather than hidden.
  - `L.s` is a global swapped in `AporahApp.build`, exactly like `AppColors.palette`, so it works
    in notifiers, models and repositories where there is no `BuildContext` — which is most of the
    error copy. There is no `AppLocalizations.of(context)`.
  - Nothing that reads `L.s` may be `const`, and a `const` default parameter value can't hold one
    either — make the parameter nullable and resolve it with `?? L.s.x` in the body
    (`showRenameSheet`, `SettingsDetailPage.parentTitle` are the precedents).
  - Dates and the 12/24-hour clock follow the language too: month and weekday names come from
    `L.s` via [lib/data/calendar_data.dart](lib/data/calendar_data.dart), times through
    `formatTime`, and `main.dart` overrides `MediaQuery.alwaysUse24HourFormat` so the system
    pickers agree with the app rather than with the phone.
  - **A UIKit platform view is told its text once, in `creationParams`.** The native tab bar and
    search field therefore push updates over their method channel (`setLabels`,
    `setPlaceholder`) the same way they already push `setBrightness`. Any new native view showing
    text needs the same, or it will keep the language it was created in.
  - What stays German on purpose: the Bundesland names, the waste-bin keywords in
    `abfall_bins.dart` (they match German vendor feeds, not the UI), shop names in
    `merchant_logos.dart`, and the unit words in `grocery_search.dart`'s quantity regex.
- Backend: **Supabase, live.** Schema, roles, RLS and the Edge Functions in
  `supabase/functions/` are deployed with the Supabase CLI (`supabase functions deploy`); see
  [docs/backend.md](docs/backend.md) before touching them or before building anything that
  depends on roles, per-item visibility or sharing. `supabase_flutter` is wired up:
  [lib/services/supabase.dart](lib/services/supabase.dart) holds the client (publishable key
  only — **never the `service_role` key**), [lib/state/auth_state.dart](lib/state/auth_state.dart)
  the session, and [lib/state/family_state.dart](lib/state/family_state.dart) the household,
  its members and `myRoleProvider`. `main.dart`'s `_RootGate` gates on auth → household →
  `families.onboarding_done`.
- **We do not store anybody's calendar, and we do not have one of our own.** Google, Outlook,
  iCloud and IServ events are proxied by `calendar-events` on every refresh and returned to the
  app; the offline copy lives on the device in
  [lib/services/calendar_cache.dart](lib/services/calendar_cache.dart). Nothing is read out of
  `public.events` at all — that table is empty and unreachable, `provider = 'aporah'` is no longer
  an accepted value on `calendars`, and `calendars.provider` has no default so an insert can't
  produce an own calendar by omission. The `external_uid`/`external_href`/`external_etag` columns
  are gone too, so no code path can quietly start materialising a provider. Don't add one — for a
  German family app, holding no doctor's appointments is a feature.
- **The one exception is a calendar handed over as a file, and it is not a hole in the rule.** A
  waste vendor outside `abfall.ts` publishes `abfuhr2027.ics` as a download and nothing to
  subscribe to, so there is no server to proxy to and the bytes are kept — sealed in
  `calendar_connection_secrets.feed_files`, re-parsed on every refresh, never materialised into a
  row. The file is a *source* we happen to hold, exactly as a feed URL is a source we fetch; what
  is still refused is a calendar of our own that the app writes events into. A file is
  `is_read_only`, unshareable, and matched on its file name so that re-uploading next year's
  replaces last year's rather than sitting beside it. Offered on the `ical` tile only, and off iOS
  there is no picker so there is no upload.
- **There is exactly one write route, and it leaves the building.** `calendar-write` creates,
  updates and deletes events straight in Google, Outlook or the CalDAV server, addressed by
  `CalendarEvent.uid` (the provider's own id, carried on the wire); the change comes back on the
  next `calendar-events` read like any other event of theirs. `CalendarSource.editable` is
  `!readOnly`, which is the only question left — Ferien, Abfall and read-only provider calendars
  are out, everything else is a destination. There is no `isOwn`, no `CalendarEvent.toMap()` and no
  PostgREST branch beside it. **Don't reintroduce an in-app calendar.** It looked identical to the
  real ones in the picker and behaved nothing like them: an appointment filed there never reached
  the phone's calendar app, the other parent's watch or the reminder on the way to the dentist,
  which is the entire reason a family connects an account.
- **Ferien and Abfall are one shared feed per Bundesland/address, not a per-household connection.**
  `public_feeds` (global, keyed by a hash of the resolved config) + `family_feeds` (subscriptions).
  A hundred families on one street read one row and cause one daily fetch. They are *not* valid
  `calendars.provider` / `calendar_connections.provider` values any more. Read the feeds section of
  [docs/backend.md](docs/backend.md) before touching them.
- **Calendars are never private and never shared outward.** A connected calendar belongs to the
  whole household, full stop. This is structural, not a convention: `shareable_kind` is
  `('list','box','task')` and names no calendar, the calendar read policy has no guest branch, and
  every calendar is written `visibility: 'family'`. Don't add a visibility picker to a calendar —
  someone who wants a private calendar keeps it in their own calendar app.
- Calendar connections: [lib/screens/calendar_connect_screen.dart](lib/screens/calendar_connect_screen.dart)
  over `calendar_connection_repository.dart`. **`authenticated` holds no INSERT grant on
  `calendar_connections`, `public_feeds` or `family_feeds`** — every one is created by an Edge
  Function that first proved the thing works (an OAuth code exchanged, a CalDAV password that
  answered, a pasted link that returned a calendar, an address that returned real pickup dates),
  so "verbunden" always means "we reached it just now".
- **School calendars are connected by a pasted link, not a login.** IServ's plugin calendars —
  Aufgaben, Klausuren, Geburtstage — are module-generated views, *not* CalDAV collections, so
  PROPFIND enumeration cannot see them at any depth: it finds the pupil's empty home and the
  school-wide `+public` feed of several hundred events about every class but theirs. The user
  creates a tokenised ICS link in the school platform and pastes one per calendar (there is no API
  to mint or list them), and one account holds a list of them — `auth_type = 'public'`,
  `is_read_only`, added and removed only by `calendar-link`. **A pasted link is a credential and is
  sealed like one** — `config.feeds` holds `[{id, name, host, added_at}]` and the URLs live
  encrypted in `calendar_connection_secrets.feed_urls`, opened server-side for the length of one
  fetch. The `id` is an opaque uuid, which is what `calendars.external_id`, `selected_calendars`
  and `calendar_names` carry; don't put the URL back into any of them. **WebUntis is connected the
  same way** — "Kalender publizieren" mints `…/WebUntis/Ical.do?school=…&id=…&token=…` — and
  **`ical` is that mechanism with the vendor taken out**, for any feed a household can already
  subscribe to — and the one tile that also takes a **file**, for the calendar that is published as
  a download. The three differ only in the tile and the instructions. **Don't reinstate CalDAV
  as IServ's main route** — still reachable from a row at the bottom of its page, and it still
  finds nothing a family wants. **And don't bring back WebUntis's app secret.** It was the QR-code
  route, it is deleted (function, shared module, `auth_type = 'secret'`, `app_secret`, the QR
  scanner and its Swift side), and it went because it was TOTP seed material for the pupil's whole
  WebUntis account where a feed URL is one timetable. It took Entfall/Vertretung as lesson status,
  the whole school year rather than the feed's twelve weeks, and **Hausaufgaben, which the Board
  no longer shows**, with it. That is the trade; it was made deliberately.
  Read the school-calendar section of [docs/ported-features.md](docs/ported-features.md) before
  touching any of it, in particular the `TZID="+02:00"` trap. Abfall's six German waste-vendor families live in
  `supabase/functions/_shared/abfall.ts`; see the Abfall section of
  [docs/ported-features.md](docs/ported-features.md) before touching them, and re-run the live
  end-to-end probe described there afterwards.
- **Weather is per event, comes from Open-Meteo, and is decoration.** `weatherProvider`
  ([lib/state/weather_state.dart](lib/state/weather_state.dart)) resolves each appointment's place
  and hour and hands the agenda row and detail sheet a `WeatherReading`; `CalendarEvent` carries no
  weather, because weather is not a property of an event. This is the **one external service the
  app calls directly** — no key, and nothing that names the household. It is *not* "no personal
  data on the wire": the request carries a coordinate and an hour, and because it leaves the phone
  rather than an Edge Function, Open-Meteo also sees the **user's IP**, which with a residential
  coordinate is personal data under the DSGVO. That is a defensible trade rather than a free one —
  Open-Meteo is German-hosted, so no third-country transfer, and a proxy would buy privacy at the
  cost of a hop, a deploy and a place where household addresses could be logged. It belongs in the
  Datenschutzerklärung either way. Location is the event's own `loc` with the household's town from
  `families.address` as fallback, **never device GPS**, and every failure resolves to "no icon on
  that row" rather than an error. See the weather section of
  [docs/ported-features.md](docs/ported-features.md) before changing any of it.
- **All four screens are on Supabase.** One repository each in
  [lib/data/repositories/](lib/data/repositories/), and they are deliberately the same shape: the
  repository is the only file that knows about PostgREST, the models carry `fromMap`/`toMap` over
  the real snake_case columns, and the notifier owns the rows rather than overlaying maps on seed
  data. Read the "Writing containers from the client" section of
  [docs/backend.md](docs/backend.md) **before** writing another one: `insert … returning` is
  rejected on `lists`/`boxes`/`tasks`/`calendars` (the SELECT policy is a `stable` function that
  cannot see the row being inserted), so `.insert(…).select()` does not work there — every
  container is inserted with a **client-side uuid** and no read-back at all. **Because the id is
  the client's, a new container goes on screen before the insert answers** and the next tap can
  navigate into it; the write reconciles or rolls the row back off. A read-back would only fetch
  `created_at`/`updated_at`, which nothing draws, at the cost of a round trip on the one action
  the user is watching.
- **A picture of the thing beats a symbol of it, and it is stored.** A box and a box item each
  carry one photograph (`photo_path`) that *replaces* the `icon_asset` symbol wherever it is drawn;
  a list article keeps its list of attachments. Both live in private Storage buckets keyed on
  `can_read_box` / `can_read_list` — **never on household membership**, or a guest loses the
  pictures on the box shared with them. `PhotoRepository`
  ([lib/data/repositories/photo_repository.dart](lib/data/repositories/photo_repository.dart)) is
  the only file that knows about Storage, and the object layout (`<container_id>/<uuid>.<ext>`) *is*
  the access rule — read the picture-buckets section of [docs/backend.md](docs/backend.md) before
  changing it. Off iOS there is no picker, so there is no photo. **The shop page an article points
  at is a column beside all that** — `list_items.link_url`, one `http(s)` URL, set from the item
  menu and opened by the device. Not a row in `list_item_attachments`: that table is a storage
  object all the way down, and a link has none. **Nothing ever fetches it**, so there is no
  preview, no scraped title and nobody outside learning what the household is shopping for.
- **Three independent axes, never one string.** `assignee_id` is *who does it*; `visibility` +
  the `*_shares` rows are *who in the household may see it*
  ([lib/models/visibility.dart](lib/models/visibility.dart), one enum for all three containers);
  `share_links` + `guest_access` are *who outside may see it*. The old single `who` string
  (`'all' | 'private' | <memberId>`) conflated the first two and is gone — `whoBadge()` in
  [lib/models/who.dart](lib/models/who.dart) renders the badge from the first two together.
  External sharing is its own action ([lib/widgets/share_sheet.dart](lib/widgets/share_sheet.dart)),
  reached from a row menu and **never** from the "Für wen?" picker: mixing outsiders into the
  family avatar row would make a mis-tap leak household data. **A share always may edit and the
  sheet does not ask** — `can_edit` survives on the rows and in the policies, defaulted `true`,
  but read-only was a mode the database enforced and no screen ever drew, so the guest saw every
  control and had every tap refused. Bringing it back means building the read-only UI, not
  restoring a switch.
- **A list or a task can point at an event, and the pointer carries no event in it.** Three columns
  on `lists`/`tasks` — `event_calendar_id`, `event_uid`, `event_starts_at` — read as
  [lib/models/event_link.dart](lib/models/event_link.dart). The reference is the
  `(calendar, provider uid)` pair the providers themselves guarantee, because **we store no
  events to hold a foreign key to**; there is no FK for that reason and one more, that the id is a
  `calendars.id` for a connected calendar and a `public_feeds.id` for Ferien/Abfall. **No
  `event_title`** — the appointment's name would be a copy of somebody's calendar sitting in our
  database, so `EventLinkChip` reads it off the live proxied event and prints the date when
  Kalender isn't holding it. `event_starts_at` is the one thing kept, is a date rather than
  content, and on a task duplicates the `due_date` already there; without it the tap back has
  nowhere to go for an appointment outside the loaded fortnight. Set once, on create, from the
  event sheet's "Liste/To-do zum Termin erstellen" — no edit path, no unlink, and undo re-creates
  it with the link. The appointment's sheet reaches its lists and tasks through `tabJumpProvider`
  ([lib/state/nav_state.dart](lib/state/nav_state.dart)): the shell switches tab, the destination
  screen opens the thing. **The way back does not cross tabs** — the chip on a task or a list calls
  `showLinkedEventSheet`, which stacks the event's own sheet over Board or Listen, so closing it
  lands where the reader already was. On a *row* the chip is a marker with no tap at all: the row
  itself opens the thing, and a second target beside it made that a coin toss.
- **Spending is captured by an iOS App Intent, and the user never handles a credential.** An Apple
  Pay **Personal Automation** runs an action Aporah donates on install
  ([ios/Runner/SpendAppIntent.swift](ios/Runner/SpendAppIntent.swift)), which posts to
  `spend-ingest` from Swift on a locked phone with no Flutter engine and no session — so the
  function is the second one pinned to `verify_jwt = false`, and a **per-device token** in the
  Keychain is the whole security boundary. **No app can install a Personal Automation**; there is
  no API and never has been, so the trigger stays the user's to create and what the rebuild deleted
  is the old web app's copy-a-token-and-paste-it dance. Apple's trigger is known to hand a custom
  intent an empty merchant or a zero amount, so a row that arrives that way is **kept and flagged**
  (`needs_review`), never dropped — the payment happened and a locked phone cannot be told
  otherwise. **Which category a merchant falls into is decided in SQL** by
  `private.classify_merchant` in a trigger, because the ingest function and the app's own form both
  write spends and two copies of those rules would drift into putting one shop in two slices of the
  same ring. **Admin only**, enforced in the policies; money is **integer cents**, never a double or
  the old app's text column; and a wallet sees no cash, card, browser checkout or transfer, which
  is why **manual entry is half the feature rather than a fallback**. Read
  [docs/spend.md](docs/spend.md) before touching any of it.
- **Android captures the same payment by reading the wallet's own notification, and the allowlist is
  the whole privacy promise.** There is no payment trigger and no transaction API on Android —
  Google's Wallet API issues passes — so `SpendNotificationListener` reads the notification Google
  Wallet or Samsung Wallet posts the instant a tap goes through, and posts to the *same*
  `spend-ingest` with the same per-device token. Nothing else is duplicated: no second backend, no
  second classifier, no second table. Two things about it are not negotiable. **The grant is
  all-or-nothing, so the cost is disclosed on the page before the ask** (`_DisclosureCard`, which is
  also what Google Play's prominent-disclosure rule requires) **and paid without being used** —
  `onNotificationPosted` returns on its first line for any package outside
  `WalletNotifications.sourcePackages`, before it reads a single extra. **Adding a package to that
  set is not a small change**, and Google Play services is deliberately not in it: it is not a
  payments app, and allowing it would mean parsing most of what Google sends a phone. And **the
  parse is a guess** — Apple hands over typed fields, Android hands over a sentence written for a
  human in whatever language the phone is set to — so no amount means no row, a refund or a decline
  is refused by name, and a merchant that had to be inferred is filed `needs_review` rather than
  dropped. Setup is **two switches** that fail differently, our token and the OS grant, which is why
  `SpendState` carries `notificationAccess` beside `thisDeviceEnrolled` instead of one boolean. The
  token is **not** in `EncryptedSharedPreferences` — that library was deprecated in 2025 — but in an
  AndroidKeystore AES-GCM wrapper over an app-private file, which is
  `kSecAttrAccessibleAfterFirstUnlock`'s promise made twice. **Open banking would catch the card, the
  transfer and the direct debit that no wallet notification ever will; it was considered and declined
  on cost** (a licensed AISP contract, KYB, 90-day consent re-auth). Read
  [docs/spend.md](docs/spend.md) before touching any of it.
- **Notifications are local and derived, not added.** Everything the app says today — a reminder
  on an appointment, the bins at 19:00 the evening before, a to-do's hour, the morning brief — is
  scheduled on the device by `composeNotices`
  ([lib/state/notification_scheduler.dart](lib/state/notification_scheduler.dart)), which rebuilds
  the whole pending set from what is on screen and swaps it in over `aporah/notifications`. Never
  schedule a single notice from a screen. **A notification needs a deadline or somebody's name on
  it; creating a list or a box has neither**, and iOS silently drops everything past the 64 soonest
  requests. An appointment reminder is this person's, on this device, and has no table. The rating
  prompt is `ReviewPrompt` and is never wired to a button. Read
  [docs/notifications.md](docs/notifications.md) first.
- Don't filter content by `family_id` in Dart. RLS already decides what "my lists" means, and a
  client-side family filter would hide exactly the rows a guest is meant to see. (Edge Functions
  are the exception and must filter — `service_role` bypasses RLS, so there the family filter *is*
  the tenant boundary.)
- **The RLS helper predicates live in the `private` schema, not `public`.** `can_read_list`,
  `my_family_id`, `is_admin` and the other 14 were reachable as `/rest/v1/rpc/<name>` while they
  sat in `public`. Don't move one back, and don't add a new one to `public`. Policies reference
  them by OID, so `alter function … set schema` moves one without touching a single policy.

## Structure

- [lib/screens/](lib/screens/) — one file per tab. Calendar is by far the largest/most complex.
  **Box and Ausgaben share the fifth tab, `Mehr`** ([lib/screens/more_screen.dart](lib/screens/more_screen.dart))
  — which switches between them on `moreProvider`, the way Listen opens a list, not a route; five is
  the ceiling on both nav bars. **`Mehr` is two buttons, not a page**: tapping it stands
  [`MoreShelf`](lib/widgets/more_shelf.dart) on the bar item — a column of two labelled glass
  buttons, one per place, each circle the size and material of the compacted nav button and wearing
  the bar's own muted/accent tints — and the shell changes tab only once one is pressed, so
  neither screen needs a way back and a dismissed shelf leaves the reader where they were. That
  means the one nav item whose tap is not a tab change — `AppShell._navigateTo` splits it off, and
  `NativeTabBar` awaits the answer so UIKit's own selection can be put back when nothing was picked.
  It was a `UIMenu` first, which was right about the layer and wrong about the control: **Mehr**
  names two *places* where every other menu in the app lists verbs for a row, and a list of two
  labelled lines put a flat text list where the other four tabs answer with a glyph. Glass beside
  the bar is
  not the compromise that reasoning assumed — `GlassSurface` embeds the real `UIGlassEffect`, so
  the buttons are the same material as the bar, not an approximation of it. **Still don't draw a
  second *bar*** — a five-slot capsule with two items in it is a different control wearing the nav
  bar's clothes. **Where Ausgaben does not ship the slot is plain
  Boxen** — label, icon and ordinary tap — because a "Mehr" naming one place is a promise the shelf
  cannot keep; one getter decides, `spendAvailable` in
  [lib/services/spend_intent.dart](lib/services/spend_intent.dart), and it also keeps `SpendScreen`
  from being built at all and takes the Apple Pay row out of Settings. Board, Box and Listen share one collapsing-header pattern (`CollapsingHeaderScreen` +
  `CollapsingScreenTitle` + `ScreenBodyPanel`); Kalender has its own copy on purpose. Read the
  collapsing-headers section of [docs/design-system.md](docs/design-system.md) before changing one
  — in particular, never hardcode the header's collapsing-block height.
- [lib/state/](lib/state/) — per-screen notifier + immutable state class (`copyWith`-style).
- [lib/models/](lib/models/) — plain data classes (`CalendarEvent`, `Task`, `BoxItem`,
  `ShoppingList`, `Who`).
- [lib/data/](lib/data/) — reference data. The seed lists/boxes/tasks/events are all empty now
  that there is a backend; `calToday()` follows the real device clock (the old mock "today" pinned
  to 2026-08-13 is gone). `german_holidays.dart` **computes** the Feiertage — they are fixed in law,
  so a Bundesland and a year are enough, and the striped day circles in Kalender come from it. Don't
  turn them into a feed. The real, non-mock data behind Listen lives here:
  `grocery_catalog.dart` names every `assets/grocery/` icon in German and derives the English name
  from the file name (`englishGroceryLabel`; `_englishLabelOverrides` covers the files whose names
  lie), and `_ptLabels`/`_esLabels` tabulate the other two because a file name yields no
  Portuguese; `grocery_search.dart` matches typed articles against **all four languages at once,
  umlauts and Portuguese nasals optional** — the interface language decides only what is *shown*, never what can be found — and
  `merchant_logos.dart` names the shop logos (brands, so untranslated). `icon_suggestions.dart`
  sits over all three plus a curated symbol set, whose entries carry both labels by hand:
  `suggestIcon(name)` is the pure function behind every list, box and item picking its own icon as
  the name is typed, and `lib/widgets/icon_picker.dart` is the manual override. Adding a grocery
  PNG still means **one** German line — the English side comes off the file name — while a new
  symbol needs both. **A stored icon key still reads `lucide:<name>`** and always will: those
  strings are on rows families wrote before the icon set changed, so `symbolIconPrefix` is a wire
  format rather than a name (see the swap note below). See the grocery section of
  [docs/ported-features.md](docs/ported-features.md).
- [lib/theme/](lib/theme/) — `tokens.dart` + `app_theme.dart` + `app_icons.dart`. Always use
  tokens; never hardcode a new hex/size.
- **The icons are Phosphor Duotone, and you draw one with `AppIcon`, never `Icon`.** A duotone
  glyph is *two* codepoints — an under-layer and an over-layer stacked with the lower one faded —
  so a bare `Icon` renders half of it, which looks thin and hollow rather than broken. Both
  codepoints are named in [lib/theme/app_icons.dart](lib/theme/app_icons.dart) and both must be
  `const`, or `--tree-shake-icons` fails the release build. **A glyph that names a thing is
  duotone; a glyph that *is* a control is flat, and flat means the set's Regular weight from a
  second vendored font** — not the duotone minus its under-layer, which for a caret is a hollow
  triangle rather than a chevron. Every Phosphor weight shares one codepoint per glyph, so
  `_flatFamily` picks the weight for all of them at once. Pass `flat: true`, which the glass
  buttons, the segmented control, the check-off, the swipe actions and the nav pill already do for
  their callers.
  **A control's *size* comes from `AppGlyph` in [lib/theme/tokens.dart](lib/theme/tokens.dart), and
  the numbers in it are measured rather than chosen** — four tiers calibrated against the ink of
  the SF Symbol the system would draw in the same place. Two facts drive them: a Phosphor glyph
  fills only 57–86% of its em (Lucide filled 88%, so the swap shrank every control without a number
  changing), and `UIBarButtonItem` applies `.large` on top of 17pt, so its symbol is 21pt of ink
  rather than the ~14 the bare number suggests. **This is also why the flat weight is Regular and
  was Bold**: the glyph was drawn too small and Bold was a heavier stroke compensating for it, two
  errors that cancelled into "small, and the weight is off". Don't write a size at a call site. Fourteen bare marks (`check`, `x`, `plus`, `minus`, the three-dot menu, the arrows and
  the carets) are flat everywhere regardless, because Phosphor gives them a placeholder box or a
  hollow outline instead of a real second layer. Lucide is **gone**: it is one monoline
  stroke weight by design and has no duotone, and `phosphor_flutter` could not be used either
  because its `PhosphorIconData extends IconData` and Flutter has made `IconData` final — so the
  font is vendored in `assets/icons/`. Note that `flutter analyze` passes on that package and only
  the compiler catches it: **a green analyze is not a build.**
- [lib/widgets/](lib/widgets/) — shared building blocks. **Check here before writing a new
  one-off widget**; see [docs/design-system.md](docs/design-system.md) for what exists and the
  non-obvious rules (especially: leave `GlassSurface.tint` null, use `fallbackTint`).
- [lib/services/](lib/services/) — the little that talks to the OS rather than to state, each one
  a method channel registered in `ios/Runner/AppDelegate.swift` and a no-op off iOS. Same trade as
  the native tab bar/switch: a bit of UIKit instead of a plugin. `external_links.dart` opens a URL
  (`aporah/links`); `media_picker.dart` puts up the photo library, camera or Files picker
  (`aporah/media`, implemented in `ios/Runner/MediaPicker.swift`) and copies what was picked into
  `Documents/attachments/`; `map_snapshot.dart` geocodes an event's location with CoreLocation and
  renders a still map of it with MapKit (`aporah/map`, `ios/Runner/MapSnapshot.swift`) — **the map
  in the event sheet is the device's own, not a tile service**, so no key and no household address
  on the wire, and **off iOS there is deliberately no map at all** (`deviceMapsAvailable`, which
  holds the reasoning): the Android twin would put an API key in the build and send every place the
  family goes to Google, so the card is its address row and its route button there, and `openNavigation` in `external_links.dart` hands the route to Waze or Google
  Maps by trying their URL scheme and falling back to their website; `native_menu.dart` puts up
  the system's own menu beside the control that opened it (`aporah/menu`,
  `ios/Runner/NativeMenu.swift`). **The iOS
  deployment target is 15.0** — new system API needs an `if #available` guard and a fallback, not a
  raised target.
- **Every menu in the app is the system's own where the system has one.** `showAnchoredMenu` is
  still the one function every "..." goes through, but it now asks `showNativeMenu` first and only
  paints its own panel when that answers `null` — everything but iOS, and on iOS before 17.4. Both
  take the same anchor rect, so the app's dropdown and UIKit's bubble are one gesture drawn by two
  hands. **It is a `UIMenu` beside the tap, not a sheet at the bottom of the screen**: the
  `UIAlertController` this started as was right about the layer and wrong about the shape — you
  pressed a row halfway up a sheet and the answer appeared at the far end of the display. What
  crossing over costs is the icons: a `UIMenu` takes SF Symbols, so a row carries a
  `symbol:` beside its Phosphor `icon:`, and Amazon's mark — an SVG — can't come at all. Validate
  a symbol name against the runtime's own list before using one; `arrow.triangle.turn.up.right.circle`
  is not in iOS 26 and rendered as no glyph at all.
  **The layer is the reason this exists, and it is still the reason.** Flutter content composited
  after a platform view can be dropped whole on device: inside the event-detail sheet the route
  menu opened, swallowed the taps behind it and never painted. UIKit presents its own above
  everything.
  **`null` means "there was no menu to put up", and nothing else may answer with
  it.** It is the one word that sends a caller off to draw the app's own panel,
  so a menu that was superseded, abandoned or dismissed answers `cancelled`
  instead — a superseding `show` that answered `nil` put the old dropdown on
  screen *underneath* the system menu that replaced it, which is what "sometimes
  both open" was. Dart drops a second request inside 500ms for the same reason.
  There is no public call that simply shows a menu: it hangs off a transparent `UIButton` whose
  primary action *is* the menu, fired with `performPrimaryAction()` (iOS 17.4). **A plain
  `UIControl` will not do** — a control offers its menu on a *touch-down* of the user's own, and
  there is no finger here, so it presented nothing and reported a cancel. The action sheet stays as
  the fallback below 17.4 and for a menu that was asked for and never appeared.
  A row may also carry a colour instead of a symbol (a filled dot, for a calendar), sit in a
  numbered `section` (a hairline above it — UIKit has no indent), or `keepsOpen` and toggle without
  closing, which is what Kalender's filter menu needs; the last of those reports itself over the
  channel while the request goes on waiting.

## Verifying changes

The user tests every change **in the running UI themselves** — that's the source of truth.

- Run `flutter analyze` and make it clean before considering a change done.
- **Touched anything in `lib/widgets/` or `lib/screens/`? Also run
  `dart tool/check_const_palette.dart`, and leave it saying `OK`.** It catches the one failure
  mode the compiler can't see: a `const`-constructed widget that reads a design token inside its
  `build` keeps painting the palette it was born with, so it stays dark in a light app until a
  hot reload. It is fast, it has no baseline to triage, and its whole value is that an empty
  report stays empty — never wave a new offender through.
- **Don't run `flutter test` or regenerate screenshots by default, and don't add new tests
  unless asked.** `test/` has some widget + golden-style screenshot tests; treat them as
  optional and only touch them on request.

## Reference codebase: `Aporah-Family-Hub/`

A clone of the **old Aporah web app** (React + Vite + Supabase) nested in this directory, with
its own git repo. Not part of this Flutter app, no build/lint relationship to it.

- **Never scan, index, or read it proactively** — its size and unrelated stack make that wasted
  context. Open files inside it only when a task explicitly calls for porting/referencing
  something ("how did the old app do X"), and check
  [docs/ported-features.md](docs/ported-features.md) first — it may already have the answer.
- **It will be deleted once the rebuild is done.** Never leave a hard dependency on it: copy
  assets into this project's `assets/`, rewrite logic in Dart rather than importing it, and don't
  leave doc-comments citing paths inside it. Anything worth remembering goes into
  [docs/ported-features.md](docs/ported-features.md).
