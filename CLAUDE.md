# Aporah

A Flutter family-organizer app (Home, Kalender, Listen, Board, Box tabs) built from a Figma
handoff (`design_handoff_aporah_flutter/README.md` — tokens in
[lib/theme/tokens.dart](lib/theme/tokens.dart) come from it). **German and English, switched in
Settings — never hardcode a user-facing string.** See the localization section below.

Scope: **core features only** — Board, Box, Listen, Kalender. Explicitly out of scope: the KAI AI
assistant and Apple Pay/Wallet — don't port them even if the old codebase shows them.

## Deep-dive docs — read on demand, not proactively

Keep this file lean; detail lives in [docs/](docs/) and is only worth loading for the matching
task:

- [docs/kalender.md](docs/kalender.md) — Kalender internals (week/month view, filter chips,
  collapsing headers, persistence, timeline, "Heute" button). **Read before changing calendar
  behavior.**
- [docs/design-system.md](docs/design-system.md) — glass/frosted-header gotchas, shared widget
  index, animation conventions. Read before touching `lib/widgets/` or adding animations.
- [docs/ported-features.md](docs/ported-features.md) — knowledge captured from the old web app
  (grocery lists, onboarding, Settings, weather, calendar connections). Read the one section for
  the feature you're building; each says whether it is built or still groundwork.

## Stack

- Flutter (Dart ^3.12.2), Material app shell. **No `go_router`/named routes** — navigation is a
  single `IndexedStack` of five always-mounted screens switched by index
  ([lib/main.dart](lib/main.dart)).
- State: `flutter_riverpod` (`StateNotifier` + `StateNotifierProvider`), one notifier/state pair
  per screen — `boardProvider`, `boxProvider`, `listProvider`, `calendarProvider`
  ([lib/state/](lib/state/)). Screens are `ConsumerWidget`s; read with `ref.watch`, mutate via
  `ref.read(xProvider.notifier).someMethod()`. Use this pattern for anything new rather than
  introducing another state-management approach.
- **Localization: German + English, and every user-facing string goes through
  [lib/l10n/](lib/l10n/).** `AppStrings` declares them, `StringsDe`/`StringsEn` answer them, and
  `L.s.someString` reads the live one. Because `AppStrings` is abstract, a string you add to one
  language and forget in the other **fails to compile** — that is the point, so don't work around
  it with a map or a `??`.
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
- **We do not store anybody's calendar.** Google, Outlook, iCloud and IServ events are proxied by
  `calendar-events` on every refresh and returned to the app; the offline copy lives on the device
  in [lib/services/calendar_cache.dart](lib/services/calendar_cache.dart). `public.events` holds
  **only** what somebody typed into Aporah itself, and the `external_uid`/`external_href`/
  `external_etag` columns are gone so no code path can quietly start materialising a provider
  again. Don't add one — for a German family app, holding no doctor's appointments is a feature.
- **Writing back is the other half, and it is also storage-free.** `calendar-write` creates,
  updates and deletes events straight in Google, Outlook or the CalDAV server; the change comes
  back on the next `calendar-events` read like any other event of theirs. `CalendarSource.editable`
  is `!readOnly` (so Ferien, Abfall and read-only provider calendars are out), and
  `CalendarSource.isOwn` decides the *route*: own events are `public.events` rows written over
  PostgREST, everything else goes through the function using `CalendarEvent.uid`, the provider's
  own id carried on the wire. Never write a proxied event to `public.events` to "cache" it.
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
  answered, an address that returned real pickup dates), so "verbunden" always means "we reached
  it just now". Abfall's six German waste-vendor families live in
  `supabase/functions/_shared/abfall.ts`; see the Abfall section of
  [docs/ported-features.md](docs/ported-features.md) before touching them, and re-run the live
  end-to-end probe described there afterwards.
- **Weather is per event, comes from Open-Meteo, and is decoration.** `weatherProvider`
  ([lib/state/weather_state.dart](lib/state/weather_state.dart)) resolves each appointment's place
  and hour and hands the agenda row and detail sheet a `WeatherReading`; `CalendarEvent` carries no
  weather, because weather is not a property of an event. This is the **one external service the
  app calls directly** — no key, no personal data on the wire, so an Edge Function in front of it
  would buy nothing. Location is the event's own `loc` with the household's town from
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
  container is inserted with a client-side uuid and read back in a second statement.
- **Three independent axes, never one string.** `assignee_id` is *who does it*; `visibility` +
  the `*_shares` rows are *who in the household may see it*
  ([lib/models/visibility.dart](lib/models/visibility.dart), one enum for all three containers);
  `share_links` + `guest_access` are *who outside may see it*. The old single `who` string
  (`'all' | 'private' | <memberId>`) conflated the first two and is gone — `whoBadge()` in
  [lib/models/who.dart](lib/models/who.dart) renders the badge from the first two together.
  External sharing is its own action ([lib/widgets/share_sheet.dart](lib/widgets/share_sheet.dart)),
  reached from a row menu and **never** from the "Für wen?" picker: mixing outsiders into the
  family avatar row would make a mis-tap leak household data.
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
  Board, Box and Listen share one collapsing-header pattern (`CollapsingHeaderScreen` +
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
  lie), `grocery_search.dart` matches typed articles against **both languages at once, umlauts
  optional** — the interface language decides only what is *shown*, never what can be found — and
  `merchant_logos.dart` names the shop logos (brands, so untranslated). `icon_suggestions.dart`
  sits over all three plus a curated Lucide set, whose symbols carry both labels by hand:
  `suggestIcon(name)` is the pure function behind every list, box and item picking its own icon as
  the name is typed, and `lib/widgets/icon_picker.dart` is the manual override. Adding a grocery
  PNG still means **one** German line — the English side comes off the file name — while a new
  Lucide symbol needs both. See the grocery section of
  [docs/ported-features.md](docs/ported-features.md).
- [lib/theme/](lib/theme/) — `tokens.dart` + `app_theme.dart`. Always use tokens; never hardcode
  a new hex/size.
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
  on the wire, and `openNavigation` in `external_links.dart` hands the route to Waze or Google
  Maps by trying their URL scheme and falling back to their website; `action_sheet.dart` puts up a
  system `UIAlertController` (`aporah/action_sheet`, `ios/Runner/ActionSheet.swift`). **The iOS
  deployment target is 13.0** — new system API needs an `if #available` guard and a fallback, not a
  raised target.
- **A menu opened from inside a sheet that holds native glass buttons has to be a native one.**
  `showAnchoredMenu` is still the app's menu everywhere else, but Flutter content composited after
  a platform view can be dropped whole on device: inside the event-detail sheet the route menu
  opened, swallowed the taps behind it and never painted. `showNativeActionSheet` is the way out
  there — it returns `null` where there is no system sheet to put up (everything but iOS), which is
  the caller's cue to fall back to the dropdown.

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
