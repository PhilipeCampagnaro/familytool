# Ported feature knowledge

Captured from the old web app (`Aporah-Family-Hub/`) **before it gets deleted** — these notes are
self-contained and stay useful once the source is gone. Read the section for the feature you're
building; skip the rest. Nothing here is Apple Pay/Wallet or KAI-assistant related; both are out
of scope and were skipped even where the old app had them front and center.

## Grocery / shopping list (→ Listen tab)

`lib/data/list_data.dart` already has a small seed of this.

- **Old data model**: a list (`name`, `icon`, `type: grocery|other`) holding items (`text`,
  `checked`, an icon, optional `photo`, optional `url`) — no quantity or aisle-order field.
- **Icon auto-match**: **built** — see [lib/data/grocery_catalog.dart](../lib/data/grocery_catalog.dart)
  (every file in `assets/grocery/` with its German name, grouped by section) and
  [lib/data/grocery_search.dart](../lib/data/grocery_search.dart) (the matching). German *and*
  English, umlauts optional; the English side is read off the file names rather than listed, so a
  new PNG only needs its German name added. A typed article gets its icon on the way in
  (`ListNotifier.addItem`) and the field offers chips while you type. The old app's version of
  this — a ~250-entry EN/PT/DE keyword table — is superseded; nothing left to port.
- **Shop logos**: `assets/merchants/` (~170 files). Names are *derived* from the file name by
  [lib/data/merchant_logos.dart](../lib/data/merchant_logos.dart), with an overrides map for the
  ones that can't be (`hm_com` → "H&M"), so a list is findable by the shop its logo shows.
- **"Smart list" aggregation**: with 2+ grocery lists, one pooled view grouped every unchecked
  item across lists by source list/store, plus one flat "completed" section; checking an item
  there wrote back to its real list (no duplication).
- **Interaction**: tap-to-check with a 600ms optimistic delay before committing, tap text to
  inline-rename, a "..." menu (photo / URL / delete), delete → ~8s undo toast. No swipe-to-check
  or drag-reorder existed.
- "Cheaper on Amazon" badge on non-perishables — Aporah-specific affiliate feature, low
  priority/optional to port.
- **Backend-later**: realtime multi-device sync, presence avatars and photo upload all ran
  through Supabase (`lists`/`list_items` tables + a storage bucket). Keep this feature's state
  local for now — same "local now, Supabase later" pattern as `CalendarNotifier`.

### Smart icons for lists, boxes and items — **built**

[lib/data/icon_suggestions.dart](../lib/data/icon_suggestions.dart) is one pure function,
`suggestIcon(name)`, behind every "type a name, get a picture" in the app: the new-list sheet, the
new-box sheet, the article field on a list and the item field in a box. It returns an `IconChoice`
or `null`; a `null` means the caller draws its own default (`defaultListIcon` and friends). The
picker ([lib/widgets/icon_picker.dart](../lib/widgets/icon_picker.dart)) is the manual override,
and `IconTile` is the one place any of it is *drawn*.

**One stored string, three kinds of icon.** `iconKey` on `ShoppingList` / `ShoppingListItem` /
`StorageBox` / `BoxItem` is either an `assets/...` path (a shop logo or a grocery picture) or
`lucide:<name>`. `resolveIcon(key)` turns it back into a drawable choice; an unknown key resolves
to `null` and falls back rather than throwing, so an icon can be dropped from a catalog without
taking a list with it.

**Matching rules**, all through `foldTerm`/`rankTerm` from `grocery_search.dart` — German or
English, umlauts optional, punctuation ignored, quantities stripped:

1. A **symbol whose German name the whole line hits exactly** wins first. ("Shop logo beats generic
   icon" is about an ambiguous match — *Baby* shouldn't become BabyOne, *Apotheke* shouldn't become
   the Shop-Apotheke logo.)
2. **Shop logos** (`merchantFiles` × `merchantNameFor`). Exact, whole-name prefix, or prefix of a
   word inside the name — so *Ede* is already Edeka. A two-letter query may only match *exactly*
   (that is what makes "dm" and "Q1" work without every third keystroke flashing a logo).
   Deliberately **no** compound matching here: shop names are short and turn up inside ordinary
   German words (*Akku-schrauber* → Uber, *Geburtstags-party* → Spar).
3. **Lucide symbols** — the curated `symbolGroups` list, ~105 icons in 14 German-named sections,
   each with German synonyms plus its English name. These *do* get the compound rule: a term of 4+
   letters sitting inside the query counts as the weakest hit, which is what makes *Wocheneinkauf*
   → Einkauf, *Winterkleidung* → Kleidung, *Umzugskartons* → Umzug. Ties there go to the **longer**
   stem (the more specific one); everywhere else to the shorter term.
4. **The grocery catalog** last, and *strictly* — the "query appears somewhere in the name" hit is
   dropped, or a list called "Mia" comes out as Thymian.

**Which catalogs are in play at all is decided by `IconSubject`** — one value per thing being
named, passed to `suggestIcon`, `searchIcons` and `showIconPicker` alike, so the manual override
offers exactly what the automatic match may pick:

| Subject | Catalogs | Why |
| --- | --- | --- |
| `groceryArticle` | shops → **groceries (loose)** → symbols | An article on a Lebensmittel list is a food name outright. |
| `article` | symbols → shops → symbols → groceries (strict) | Anywhere else: a Sonstige list's articles, a box's contents. |
| `list` | symbols + shops | A list is a container. A grocery photo is a photograph of *one* article, so a list called "Milch" wore a milk carton as though the list were the carton. Households do name lists after shops ("Rewe"), so the logos stay. |
| `box` | symbols only | A box is a place in the house. A shop logo says where something was bought, which is not what a box is. |

The rule is about meaning, so it lives on the enum rather than in booleans at each call site — the
two bugs it replaced were both a call site quietly getting the wrong policy, including the *stored*
icon in `createList`/`updateList`, which re-runs the match server-side and had to agree with the
preview the sheet showed.

**An edit sheet's `IconDraft` starts empty**, never seeded with the stored icon. Seeding it made
every edit look like a manual pick: the preview stopped following the name *and* the old key went
to `updateList`/`updateBox` as an explicit `iconKey`, which is the one argument that switches the
"icon follows a changed name" rule off — renaming *Rewe* to *Baumarkt* kept the REWE logo. The
sheet body shows the stored icon while the name is untouched and hands back to the matcher the
moment it changes.

**Adding one:**

- A **shop logo** → drop the PNG in `assets/merchants/` *and* add its file name to `merchantFiles`
  in `merchant_logos.dart`. The list is written down (unlike the *names*, which stay derived)
  because matching runs per keystroke and Flutter can only enumerate an asset folder
  asynchronously. Add an entry to `_names` only if the derived name is wrong. Skip `.svg` — the
  picker draws with `Image.asset`.
- A **symbol** → one `SymbolIcon('lucideName', 'Deutsch', LucideIcons.lucideName, [aliases])` line
  in the right `symbolGroups` section. Keep each glyph in exactly one section; the sections *are*
  the picker's layout. Aliases are the tuning knob — a compound that doesn't match usually just
  needs its bare stem listed.
- A **grocery PNG** → unchanged, one line in `grocery_catalog.dart`.

**Not ported: logo.dev.** The old app resolved unknown store names through a `logo-search` edge
function proxying logo.dev's Brand Search API (secret key server-side; results re-ranked toward a
`.de` domain for the German market, scoring exact brand name > `name + " "` prefix > substring, and
domain root == query as the strongest signal). Everything here is offline against local assets, so
that is a **future option only** — it needs a backend, an API key and a network round trip per
keystroke, and would only earn its keep for shops not already in `assets/merchants/`.

## Onboarding flow

Media already copied to `assets/onboarding/` (`hero_welcome.png` / `hero_members.png` /
`hero_address.png` / `logo_light.png` / `logo_dark.png`; the wallet-step hero was intentionally
not copied).

- **Steps, admin path**: welcome → family (invite members) → address (connect trash-pickup +
  school-holiday calendars) → done (summary + confetti). Non-admin/child accounts skip straight
  from welcome to done. Dropped: the iOS "wallet" step (Apple Pay) and the "Meet Kai" card.
- **Auth screens** (sign up / sign in / reset) precede the wizard — only the shape matters for
  now (name/email/password, min-6-char password, a "confirm your email" state after signup),
  since there's no backend to wire.
- **No "create vs. join a family" choice** in onboarding — every signup auto-creates its own
  family; joining an existing family happens later via an emailed invite + accept/decline sheet,
  entirely outside onboarding.
- The address step's calendar toggles (trash pickup + Ferien) are the seed of the calendar
  connections feature below — surfaced early in onboarding, not just buried in Settings.
- Old app had a "replay welcome tour" row in Settings to revisit onboarding without re-triggering
  its completion flag — worth keeping as a pattern once Settings exists.

## Settings

No Figma handoff covers this screen; the old app's `ProfilePage.jsx` is a *structural* reference
only, not a visual one.

- **Sections**: Profile (avatar/name/color/country), Family (member list, role change, remove —
  admin-only), Connections (Calendar / Marketplace / ~~Apple Wallet~~), App settings (currency,
  pay-cycle timing, dark mode), Language (en/de/pt-BR — this app is German-UI-only, so this
  likely shrinks or drops), plus a "Replay welcome tour" row. ~~Kai~~ dropped entirely.
- **Nav shape**: the old app used a full-page takeover, a grouped root list drilling into
  single-purpose sub-pages (hero header + back chevron). This app's `showAppSheet` chrome fits
  the drill-down sub-pages, but the root list is likely better as a real full-page screen.
- **Entry point**: the old app used a profile-avatar tap from its dashboard. This app's Start tab
  has no design yet (`lib/screens/start_screen.dart` is a placeholder) — the natural home for a
  Settings entry point (e.g. a profile row/avatar), to be finalized when Settings gets built.
- Family management and Connections are UI-only for now (no mutations persist) until a backend
  lands.

## Weather API

No feature exists yet in this app; this is pure groundwork.

- **Provider: Open-Meteo** — free, no API key, CORS-enabled, callable directly from the Flutter
  HTTP client with no backend proxy.
- Current conditions:
  `GET https://api.open-meteo.com/v1/forecast?latitude=..&longitude=..&current=temperature_2m,weather_code,is_day`
  Hourly/16-day forecast: same endpoint with
  `hourly=temperature_2m,weather_code,precipitation_probability,is_day&forecast_days=16&timezone=auto`
  Geocoding (place → lat/lon):
  `https://geocoding-api.open-meteo.com/v1/search?name=<query>&count=5&language=de&format=json`
- **Location source**: the family's saved home address (the old app derived it from the
  waste-calendar connection), not device GPS. Per-event weather geocoded the event's own location
  text with a fallback to the home town.
- **Icon mapping**: WMO `weather_code` → ~10 buckets (clear / partly-cloudy / cloudy / fog /
  drizzle / rain / snow / storm, day+night variants) → icon. A simple threshold table, mapping
  directly onto `lucide_icons_flutter`'s `sun` / `moon` / `cloudSun` / `cloudMoon` / `cloud` /
  `cloudFog` / `cloudDrizzle` / `cloudRain` / `cloudSnow` / `cloudLightning` (confirmed present
  in the version this app depends on).
- **Cache aggressively** to stay polite to the free API: current conditions ~30min TTL, forecast
  ~1hr TTL, geocoded places indefinitely (including failed lookups, so a bad address isn't
  retried every render).

## Calendar connections

New UI to build. **Must NOT change the existing Kalender screen's week/month view code.**
Provider icons already copied to `assets/calendar_providers/` (`google_calendar.png`,
`icloud_calendar.png`, `outlook.png`, `iserv.jpg`; Ferien and Abfall use plain icons —
`LucideIcons.graduationCap` / `LucideIcons.recycle`).

- **Providers**: Google (OAuth), Outlook/Microsoft (OAuth, same shape), iCloud (CalDAV,
  app-specific password), IServ/school (CalDAV, read-only), Ferien school holidays (no auth, pick
  a German state, read-only), Abfall waste collection (address-resolved, read-only, with a manual
  "paste ICS URL" fallback for unsupported areas).
- **UI shape to build now** (stub the connect logic — this is pure UX): a Connections screen —
  provider list (logo + label + connected-count badge + chevron) → provider detail (connected
  accounts, each renamable/disconnectable, a sub-calendar checklist choosing which calendars
  sync, a "Reconnect" state for expired tokens) → provider-specific connect form (OAuth =
  external browser/popup handoff; CalDAV = server/username/password form; Ferien = a state
  picker; Abfall = address search with ICS-paste fallback).
- **Entry points**: a "Connections" item in the new Settings screen, plus an empty-state CTA on
  the Kalender screen when there are zero connections — add that as a **new, separate
  widget/banner only; do not touch the existing week/month view, agenda, or event CRUD code**.
- **Backend**: applied and deployed —
  [supabase/migrations/20260803101000_calendar_connections.sql](../supabase/migrations/20260803101000_calendar_connections.sql)
  and [.../20260804090000_public_feeds.sql](../supabase/migrations/20260804090000_public_feeds.sql),
  plus the `calendar-connect`, `calendar-caldav`, `calendar-events` and `calendar-feed` Edge
  Functions. The rest of this section is the provider knowledge behind them.

---

### What the backend looks like

| Stück | Wo |
|---|---|
| `calendar_connections` (ein Konto = eine Zeile) | `…101000_calendar_connections.sql` |
| `calendar_connection_secrets` (nur `service_role`, nur Chiffrat) | dieselbe Migration |
| `calendars.connection_id` / `.sync_token`, `events.external_href` / `.external_etag` | dieselbe Migration |
| `public_feeds` / `family_feeds` (Ferien + Abfall, global geteilt) | `…20260804090000_public_feeds.sql` |
| OAuth-Start / Callback / Trennen | `supabase/functions/calendar-connect/` |
| CalDAV verbinden (iCloud, IServ) | `supabase/functions/calendar-caldav/` |
| Lesen aller Anbieter + Feeds (speichert nichts) | `supabase/functions/calendar-events/` |
| Öffentlichen Feed anlegen / abonnieren | `supabase/functions/calendar-feed/` |
| AES-GCM-Umschlag, Anbieter-Config, CalDAV-Client, Feeds | `supabase/functions/_shared/` |

Three decisions, and the first one was reversed once — the reasoning is worth keeping because the
first version looked right:

1. **Personal events are proxied, not stored — after all.** This was built the other way first:
   `calendar-sync` materialised every connected account into `public.events`, which bought an
   offline calendar and cost nothing visible. What it actually cost was that Aporah's database
   held its users' doctor's appointments, interviews and therapy sessions — a controller
   obligation, a breach surface and a deletion duty, all in exchange for a caching strategy. So
   the events moved to where they were always least dangerous: `calendar-events` reads the
   provider and returns it, and [lib/services/calendar_cache.dart](../lib/services/calendar_cache.dart)
   keeps the offline copy on the user's own phone. The offline calendar survived the reversal;
   the liability did not.

   The old web app also proxied, but *without* a device cache — which is why it had a spinner on
   every cold start and a blank month whenever one provider was down. The cache is the part that
   makes proxying actually work.

2. **Public feeds are stored once, globally.** Ferien and Abfall are the exception to point 1, and
   for the reason that makes point 1 true: they are not personal data. Every household in
   Niedersachsen gets identical Schulferien and every household on one street gets identical
   Abfuhrtermine, so a feed lives once in `public_feeds` under a key derived from the resolved
   config, and households subscribe via `family_feeds`. A hundred Bremen families cost one row and
   one daily fetch instead of a hundred of each — thrift, and politeness toward a municipal server.

3. **One provider vocabulary.** The old app said `outlook` in the UI and `microsoft` in the OAuth
   layer and needed an `isMicrosoft()` helper in five files. `outlook` everywhere. Note that
   `ferien` and `abfall` are *not* in that vocabulary any more: they are feeds, not connections,
   and `calendars.provider` / `calendar_connections.provider` no longer accept them.

`calendar-connect` **must be deployed with `verify_jwt = false`** — the provider's redirect
carries no `Authorization` header, so the gateway would reject the callback before the function
runs. It therefore verifies the caller itself (`callerId()`, which validates against the auth
server) on every action except the callback, and the callback's `state` is an AES-GCM envelope we
sealed at start time: unforgeable, and it expires after ten minutes.

### Google Calendar (OAuth)

- Endpoints: auth `https://accounts.google.com/o/oauth2/v2/auth`, token
  `https://oauth2.googleapis.com/token`, revoke `https://oauth2.googleapis.com/revoke`.
- **Scopes** (exactly these four):
  `.../auth/calendar.events` (read + write events),
  `.../auth/calendar.calendarlist.readonly` (list the account's calendars),
  `.../auth/userinfo.email` (the account label), `openid`.
  The old app shipped with only `calendar.events` at first; `calendarList.list` then 403s, every
  account silently fell back to the primary calendar alone, and everyone had to reconsent. The
  fallback it grew (`if 403 → ['primary']`) is a workaround for a missing scope — ask for the
  scope instead.
- **`access_type=offline` AND `prompt=consent` are both required.** Without them Google returns an
  access token and no refresh token, and the connection dies an hour later with no way back. A
  refresh token is only ever returned on first consent, so on re-connect an absent `refresh_token`
  in the response means *keep the one you have* — overwriting it with null bricks the account.
- Reading: `events.list` with `singleEvents=true&orderBy=startTime` and a `timeMin`/`timeMax`
  window; page via `nextPageToken`. **Use the per-instance `id` as the external uid, not
  `iCalUID`** — `iCalUID` is shared by every occurrence of a recurring series and collapses a
  weekly course into one row.
- `nextSyncToken` (incremental reads) is per calendarId, which is why `sync_token` lives on
  `calendars` and not on the connection. The old schema put it on the connection and consequently
  never used it.
- Skip `status: 'cancelled'` items and calendars where `selected === false` (the user already hid
  them in Google's own UI). Treat a 403/404 on one calendar as "skip this one", not as a failed
  sync.

### Microsoft / Outlook (OAuth, Graph)

- Endpoints: `https://login.microsoftonline.com/common/oauth2/v2.0/{authorize,token}`.
- **Scopes**: `Calendars.ReadWrite`, `offline_access`, `openid`, `email`. Without
  `offline_access` there is no refresh token at all. Microsoft also wants `scope` repeated on the
  refresh request; Google does not.
- **There is no token-revocation endpoint.** Disconnecting removes our copy only; the user revokes
  the app itself at `myaccount.microsoft.com/privacy`. Say so in the Trennen sheet rather than
  implying we revoked something.
- Reading: `/me/calendars/{id}/calendarView?startDateTime=…&endDateTime=…` — `calendarView`
  expands recurring series the way Google's `singleEvents` does. Send
  `Prefer: outlook.timezone="UTC"`, otherwise Graph answers in the mailbox's own zone and does not
  reliably say which. Graph's `dateTime` values come back **without** a `Z` — append one before
  parsing or every event lands offset.
- Graph will not let you set an event's `id` or `iCalUId`. The old app carried its own shared UID
  in a named extended property (`String {00020329-0000-0000-C000-000000000046} Name aporahUid`),
  expanded it back on read, and had to `$filter` on it to find an event again — and some mailboxes
  reject `$expand` on `calendarView` with a 400, needing a retry without it. Only relevant once
  write-back exists.

### CalDAV — iCloud and IServ

One protocol, two configurations. `_shared/caldav.ts` is the client.

- **Discovery**: `PROPFIND Depth:0` for `current-user-principal`, then `PROPFIND` that principal
  for `calendar-home-set`, then `PROPFIND Depth:1` on the home for collections. Try the server
  root *and* `/.well-known/caldav` (RFC 6764) — IServ instances differ by version and nobody
  should have to paste a DAV path.
- **Reading**: `REPORT` with a `calendar-query` filter
  `VCALENDAR > VEVENT > time-range start/end`, requesting `getetag` + `calendar-data`. Recurrence
  is expanded client-side (ical.js) because the server returns the series, not the occurrences.
- **iCloud specifics**: base `https://caldav.icloud.com`; an **app-specific password** from
  appleid.apple.com, never the Apple ID password. Two non-obvious ones, both discovered the hard
  way: iCloud's partition hosts (`pNN-caldav.icloud.com`) mis-handle requests with **no
  User-Agent**, and Deno's `fetch` sends none — set one explicitly on every request. And iCloud
  wraps `calendar-data` in a **CDATA section** while other servers XML-escape it inline; you have
  to handle both or every event silently disappears.
- **IServ specifics**: IServ runs DAViCal. The calendars a school actually cares about — the
  school-wide `+public` feed, class and group calendars — are **not** in the pupil's own
  `calendar-home-set`; they live under sibling principals one path segment up. Without that extra
  enumeration an IServ connection lists one empty personal calendar, which was the most confusing
  thing the old app shipped. Always read-only. Some schools disable external CalDAV or require
  2FA; the fallback is the per-calendar published ICS link.
- **Timezones are the biggest trap.** A VCALENDAR that references `TZID=Europe/Berlin` without
  shipping the matching `VTIMEZONE` makes ical.js resolve the wall-clock components in the
  *runtime* zone — UTC on Edge Functions — so every German event shifts by one hour in winter and
  two in summer. Register the embedded `VTIMEZONE`s per blob, and keep a static Europe/Berlin
  definition as a fallback.
- Parse XML prefix-agnostically (`d:`, `D:`, none). A real XML parser was tried and abandoned: the
  payload is an opaque iCalendar blob in a text node and the DOM added nothing.
- A non-multistatus PROPFIND answer is a **failure**, not "this account has no calendars".
  Reporting it as the latter produced connections that looked fine and synced nothing.

### Ferien (school holidays)

- **OpenHolidays API**, not `ferien-api.de`. The old app started on ferien-api.de and had to move:
  it stopped publishing recent years, and an empty result looks exactly like "no holidays", so the
  failure was silent.
- `GET https://openholidaysapi.org/SchoolHolidays?countryIsoCode=DE&subdivisionCode=DE-{XX}
  &languageIsoCode=DE&validFrom=…&validTo=…`. Free, no key, no account. The stored account is the
  two-letter Bundesland (`NI`); the API wants the ISO subdivision code (`DE-NI`).
- The query range is **capped at 1095 days**, so this provider gets a narrower window than the
  others.
- `endDate` is the **last day inclusive**; an all-day event's end is exclusive, so add one day or
  every holiday renders a day short.
- `name` is an array of `{language, text}` — take `DE`, fall back to the first entry.

### Abfall (waste collection)

The single largest thing in the old codebase (~1,400 lines) and the least portable. What it did:

1. Address-first setup, autocompleted nationwide via **Photon** (free OSM geocoder), never against
   vendor street lists — so uncovered addresses still autocomplete cleanly. A bare postcode
   ("28213") returns prefix suggestions, because PLZ-first typing is normal in Germany.
2. Coverage check: geocoded town matched against every covered town (fetched live from the
   vendors), then the geocoded street fuzzy-matched against that vendor's street list. Two
   fallbacks that mattered a lot in practice — geocoders name the *Ortsteil* ("Bernbach") while
   vendors list the *Gemeinde* ("Freigericht"), so the postcode gets resolved to the canonical
   municipality via zippopotam.us and retried; and some vendors publish one schedule for a whole
   town, whose street list then contains an entry named like the town itself.
3. The winning vendor config was stored as JSON on the connection, and sync dispatched to a
   per-vendor reader.

Vendor families, each one API pattern covering many municipalities: `regioit` (AbfallNavi, 27
regions, JSON `/rest/orte → strassen → termine`), `awido` (Cubefour, ~46 clients / 1,550 towns —
`client=` is a *path* segment on `getPlaces` and a *query* param everywhere else, which cost a
day), `jumomind` (MyMuell, ~22 services / 1,100 towns — send `Accept-Encoding: identity`, their
servers mis-serve some compressed responses), `abfallio` (abfall.io legacy widget — not JSON at
all but a multi-step HTML form whose hidden inputs carry accumulating server state; 17 of 44 keys
have since migrated to a v3 app API and 401), `ctrace` (no street enumeration exists, so coverage
is validated by *probing* the ICS export — a 200-with-events is the match).

**All six families are ported and live** (`supabase/functions/_shared/abfall.ts` +
`abfall_providers.ts`, moved across byte-for-byte and then adapted). `abfall-lookup` serves the
address search, the coverage check and the ICS validation; `_shared/feeds.ts` dispatches on
`config.vendor` when a shared feed is created or refreshed. `mampfes/hacs_waste_collection_schedule` remains the right starting point for
the next platform family (app.abfallplus.de v3 would recover the 17 authorities whose legacy
abfall.io keys now 401).

Two defects came out of the port, neither of which the old app could have caught — its edge
functions were TypeScript but nothing ever typechecked them, and JavaScript did not care at
runtime:

- `ResolveResult.hausNrList` was declared `Array<{id: number}>`, but only regio-iT sends a number.
  AWIDO sends an addon GUID, abfall.io a form option value, jumomind a packed `"nr|areaId"`. A
  client that believed the declaration would drop every house number outside one vendor family.
  It is `number | string` here, and `HouseNumber.id` in Dart is `Object` for the same reason.
- Town matching used a bare `includes` in both directions, so `"Hain"` matched inside
  `"Friedrichshain"`. A Berlin address resolved — via the postcode fallback — to the whole-town
  bin schedule of a village 400 km away, and it looked entirely plausible on the calendar: real
  Restmüll and Biotonne dates, all of them wrong. Substring matches now have to land on a word
  boundary (`townMatches`/`containsWord`), which still accepts "Gießen" in "Landkreis Gießen".

Verified end to end against the live vendor APIs, one address per family plus an uncovered one
(`geocode → resolveAddress → readAbfallEvents`): Aachen/regioit 313 events, Waiblingen/awido 131,
Darmstadt/jumomind 76, Bremen/ctrace 73, Lienen/abfallio 66, Stuhr/awgbassum 30, Berlin
unsupported. Worth re-running after any change to these files — the vendors move.

### Event dedup

- The identity of a pulled event is **(calendar_id, external_uid, starts_at)**, enforced by a
  partial unique index. `starts_at` is part of it because CalDAV expansion yields one row per
  occurrence of a recurring series, all sharing the series UID — without it a weekly Sportkurs
  collapses into a single event. The old app used the same `uid:start` key, in a `Map`, at read
  time.
- Sync is a **full-window reconcile**: insert what is new, update what changed, delete what the
  provider no longer returns. So a moved occurrence is corrected by the delete pass rather than
  left as a duplicate. Only rows *with* an `external_uid` are touched, so an event typed into a
  synced calendar is never collected.
- "Changed" is decided by the etag where there is one (CalDAV), and by comparing the stored fields
  where there is not (Google, Graph). Blindly updating every row on every sync would make any
  future Realtime subscription useless.
- The same event can legitimately arrive twice in one pass — an invitation sitting in two of the
  account's calendars. First one wins.
- **Write-back is not built.** When it is: the old app stamped one shared UID into every copy it
  wrote (Google accepts a caller-supplied event `id`; CalDAV takes the UID; Graph needs the
  extended-property trick), so copies across accounts collapse into one row on read. The
  `events.external_href` / `external_etag` columns exist for the `If-Match` on update and delete.

### Things the old app got wrong, in one place

- Shipped Google with too narrow a scope and had to force a global reconsent.
- Overwrote `refresh_token` with null on re-connect.
- Declared a per-connection `sync_token` that could never be used, because every provider's delta
  cursor is per calendar.
- Two names for one provider (`outlook` / `microsoft`).
- Hardcoded one family's *published* iCloud feed URL as the app default — a live capability leak,
  found and removed in a 2026-07 security review. There is no such thing as a harmless default
  calendar URL.
- Ran an ICS proxy at an origin-relative `/api/calendar` path, which breaks inside a native
  WebView. Every provider call belongs in an Edge Function, both for that and because tokens must
  never reach the client.
- RLS on the calendar tables was `for all to authenticated using (true) with check (true)` until a
  late "phase 3" migration retrofitted `family_id`. Do not repeat that ordering.

### Credentials to obtain before any of this can be deployed

Nothing here is in the repo, and none of it belongs in the repo. All of it goes into the Supabase
**Edge Function secrets** for project `uzhzrwakrtwbpuuupccu`
(`supabase secrets set NAME=value`).

| Secret | Woher |
|---|---|
| `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` | Google Cloud Console |
| `MICROSOFT_CLIENT_ID`, `MICROSOFT_CLIENT_SECRET` | Azure Portal |
| `CALENDAR_OAUTH_REDIRECT` | `https://uzhzrwakrtwbpuuupccu.supabase.co/functions/v1/calendar-connect` |
| `CALENDAR_SECRET_KEY` | `openssl rand -base64 32` — generate once, never rotate casually |
| `APORAH_APP_REDIRECT` | the app's deep link, e.g. `aporah://kalender/verbunden` |

1. **Google** — console.cloud.google.com. Create a project, **enable the Google Calendar API**
   (an OAuth client alone is not enough; a missing API enablement 403s in a way that reads like a
   scope problem). Configure the OAuth consent screen as **External**, add the four scopes listed
   above, and add every tester's Google account under Test users — an unverified app only works
   for those until Google verifies it, and verification is required for the `calendar.events`
   scope because it is *sensitive*. Then create an **OAuth 2.0 Client ID of type Web
   application** — not "iOS", even though the client is an iOS app, because the redirect lands on
   the Edge Function — and register `CALENDAR_OAUTH_REDIRECT` verbatim as an Authorized redirect
   URI.
2. **Microsoft** — portal.azure.com → Microsoft Entra ID → App registrations → New registration.
   Supported account types: **Accounts in any organizational directory and personal Microsoft
   accounts** (personal accounts are the common case for a family). Redirect URI: platform
   **Web**, value `CALENDAR_OAUTH_REDIRECT`. Under API permissions add the delegated Microsoft
   Graph permissions `Calendars.ReadWrite` and `offline_access`. Under Certificates & secrets
   create a **client secret** — copy the *Value*, not the Secret ID, and note the expiry date,
   because Azure caps it at 24 months and the connection dies the day it lapses.
3. **Apple iCloud** — nothing for us to register. Each user generates an **app-specific password**
   at appleid.apple.com → Sign-In and Security → App-Specific Passwords. The connect form should
   link there and say plainly that the Apple ID password will not work.
4. **IServ** — nothing to register either; the user supplies their school's address plus their own
   IServ login. Worth validating against one real school instance before promising it works.
5. **Ferien / Abfall** — no credentials at all. OpenHolidays, Photon and the waste vendors are all
   free and keyless. This is worth remembering: two of the six providers cost nothing to add.

Also needed once, at deploy time: `calendar-connect` must be deployed with **`verify_jwt =
false`** (`supabase functions deploy calendar-connect --no-verify-jwt`), because the provider's
redirect arrives without an `Authorization` header.
