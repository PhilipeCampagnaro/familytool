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
`lucide:<name>` — a key format frozen by the rows already written, kept verbatim when the app's
icon set changed from Lucide to Phosphor Duotone. `resolveIcon(key)` turns it back into a drawable
choice; an unknown key resolves
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
3. **Curated symbols** — the `symbolGroups` list, ~235 icons in 14 German-named sections,
   each with German synonyms plus its English name. These *do* get the compound rule: a term of 4+
   letters sitting inside the query counts as the weakest hit, which is what makes *Wocheneinkauf*
   → Einkauf, *Winterkleidung* → Kleidung, *Umzugskartons* → Umzug. Ties there go to the **longer**
   stem (the more specific one); everywhere else to the shorter term.
4. **The grocery catalog** last, and *strictly* — the "query appears somewhere in the name" hit is
   dropped, or a list called "Mia" comes out as Thymian.

**That weakest hit is anchored to a word end even inside a Lebensmittel list** (`_endsWord`, added
2026-09-16). It is there for German compounds, where the head noun comes last — *Vollmilch* is milk —
and unanchored it also fired on letters buried mid-word: **Mini-Pizzen drew a sanitary towel**,
because "mini" sits inside "feminine pads" and that name is shorter than "aluminiumfolie", which
contains it too. Browsing keeps the loose rule (`_search(anchored: false)`), so typing *pizz* still
offers Tiefkühlpizza halfway through the word. Verified against every German label in the catalog:
all 600 still match themselves.

A plural is not a compound and nothing stems it — *Pizzen* reaches no name that *Pizza* does — so a
plural the household actually types is one more alias on the entry.

**Which catalogs are in play at all is decided by `IconSubject`** — one value per thing being
named, passed to `suggestIcon`, `searchIcons` and `showIconPicker` alike, so the manual override
offers exactly what the automatic match may pick:

| Subject | Catalogs | Why |
| --- | --- | --- |
| `groceryArticle` | shops → **groceries (loose)** → symbols | An article on a Lebensmittel list is a food name outright. |
| `article` | symbols only | Anywhere else: a Sonstige list's articles, a box's contents. The photographs went on 2026-09-16 — see below. |
| `budget` | symbols only | A monthly spending budget. A shop logo would say the household budgets for REWE rather than for groceries. |
| `list` | symbols + shops | A list is a container. A grocery photo is a photograph of *one* article, so a list called "Milch" wore a milk carton as though the list were the carton. Households do name lists after shops ("Rewe"), so the logos stay. |
| `box` | symbols only | A box is a place in the house. A shop logo says where something was bought, which is not what a box is. |

The rule is about meaning, so it lives on the enum rather than in booleans at each call site — the
two bugs it replaced were both a call site quietly getting the wrong policy, including the *stored*
icon in `createList`/`updateList`, which re-runs the match server-side and had to agree with the
preview the sheet showed.

**`article` lost the photographs on 2026-09-16, and the reason generalises.** It had them on the
true observation that a photograph of one thing stands for one thing — but the ~2000 pictures are a
*supermarket's* catalog, so anywhere else they answer the wrong question with great confidence:
"Kerzen" on a Baumarkt list came back as a dinner candle, and the strict grocery match is only
reached once no symbol is even close, which is exactly when a confident picture is least deserved. A
symbol that is merely near reads as a symbol; a photograph that is merely near reads as a mistake,
because a photograph claims to *be* the thing. What made this affordable is that `symbolGroups` was
grown for it in the same pass — Schlafsack, Pinsel, Socken, Dübel, Kinderwagen — so the answer to a
thin match is another symbol rather than the photo catalog. A grocery picture now appears on a
Lebensmittel list and nowhere else.

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
- A **symbol** → one `SymbolIcon('storedName', 'Deutsch', 'English', AppIcons.phosphorName,
  [aliases])` line. The first string is the **stored key's tail** and is still spelled the Lucide
  way on every existing entry — leave those alone; only new ones are free to be named afresh
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

### Card view — **built**, and new rather than ported

The old app had one way to draw a list. A Lebensmittel list can now be read as a **grid of
pictures** instead of rows — Bring's shape, which works there for a reason worth writing down: a
grocery article is one word and one photograph, and `assets/grocery/` already holds the
photograph. Anything else on a list is not.

- **`ListViewMode` on `ListScreenState`** (`list_state.dart`), held as `cardListIds` — the ids that
  are *cards*, since rows are the default and an empty set is the right state for an account that
  has never touched it. It lives in `shared_preferences`, **not on `lists`**: how I like to read
  the shopping list is mine, and a column would redraw the other parent's screen from across town.
  `setViewMode` prunes ids whose list is gone on every write, which is safe because the switch is
  only reachable from inside an open list.
- **Offered on Lebensmittel lists only.** A Sonstige article carries no picture at all — nothing
  picks a symbol for one, see `planItemIconKey` — so the grid would be a wall of empty circles with
  words underneath, strictly worse than the rows. The list that can't have it never sees the menu
  row; a disabled row is a promise with no way to keep it.
- **"Alle Artikel" is always rows.** It has no menu to switch from — it is computed rather than
  stored, so its header carries nothing to act on — and it groups articles under the list each came
  from, which a grid has nowhere to put. `viewModeFor` refuses it by id.
- **It is a reading mode, and that is the trade.** A tile holds the picture, the name, the count
  and tap-to-check; **the whole tile is the check-off**, the way a done row's whole line is.
  Everything the row spread across its width — rename, unit, link, photo, delete — moves to a
  **long press** and the same `_itemMenu`. What the menu does *not* carry is inline rename and the
  quantity, because both are edits the row does in place: composing the list stays a list-mode job
  and ticking it off in the shop is what the grid is for. If that turns out to be too strict, the
  fix is a row in the tile's menu, not a control on the tile — a second target on a 114-point
  square makes the tap a coin toss.
- **The add line stays a line in both views.** It is an input for one article, not one of the
  articles, and a tile shaped like the others that opened a keyboard would be the one tile that
  lies. "Erledigt" stays rows too: a tile is the loudest thing the screen can make, and the
  shopping that is already over should not be shouting.
- Tiles sit on the panel's own ground **below** the add card rather than inside it — a card of
  cards is two surfaces saying the same thing. The grid is sized by `maxCrossAxisExtent: 130`
  rather than a column count, so a phone gets three across and an iPad six rather than three very
  fat ones.

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
- **The address step asks one question and connects two calendars from the answer** — built, and
  no longer the old app's pair of decorative toggles. The household picks its address in the same
  picker the Abfall connect flow uses (`abfall-lookup`'s `search`, then `resolve` on the pick),
  and the two calendars that follow from *where you live* fall out of that one answer: the waste
  vendor serving the street, and — via `bundeslandCodeFor`, which maps the geocoder's state name
  onto the sixteen `bundeslaender` codes — the Schulferien feed for that Bundesland. Both arrive
  already ticked, both are `family_feeds` subscriptions created by `connectLocalCalendars`, and
  either half can come back empty without costing the other one (the row greys out and says so).
  Nobody is asked to pick their own Bundesland off a list of sixteen, which is the whole reason
  the connect sheet's `_RegionStep` is *not* what onboarding reuses.
  - The lookup lives in `OnboardingNotifier`, not in the step widget: the wizard swaps steps
    through an `AnimatedSwitcher`, so a widget's own `State` dies on the way back to the
    invitations, and a resolved address must not have to be found twice.
  - The picked address is also written to `families.address` (`HouseholdNotifier.saveAddress`),
    which is where the weather's fallback town comes from. Before this it was collected and
    thrown away.
  - A feed the household already subscribes to is skipped rather than created again — the tour is
    replayable from Settings, and a second Schulferien row for the same state is not a second
    calendar.
- **The personal accounts are offered on the last step, never as a step of their own.** The
  "Bereit!" screen carries one row into `CalendarConnectionsPage`; taking it finishes onboarding
  *first* and then pushes the page. Google and Outlook consent leaves for Safari and returns
  through a deep link (`_ProviderPageState`'s `WidgetsBindingObserver`), which is the most fragile
  minute in the app — putting it inside a wizard that is itself gating the app shell, with a
  connect sheet's own `StepDots` under the wizard's, is how a family ends up stranded halfway
  through their first five minutes. Ferien and Abfall are different in kind: no login, no round
  trip, and ours to give.
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

## Weather API — **built**

Weather appears in three places. **Per event**: the agenda row shows an icon + temperature beside
the appointment, and the detail sheet a card with icon, temperature and condition — resolved at
the event's own location and its own hour. **Per day**: each cell of Home's week strip carries the
forecast for that day at the household's town, under the date. The old app's hourly strip is still
not ported.

The two are separate maps on `WeatherState` — `readings` keyed by
`(place, instant)` and `daily` keyed by `'y-m-d'` — because they answer different questions. An
event's reading is keyed on a place *and* a moment, since two appointments an hour apart in two
towns genuinely differ; a strip cell asks what a day is like where the family lives, and needs an
answer on the days nothing is planned. `daily` costs no extra request on a household with
appointments: it is sampled out of the home forecast the event pass already fetched, once per day
at `dayForecastHour` (13:00 — early afternoon is when a German day is what it is going to be).
Outside the 16-day horizon there is simply no entry, and the strip reserves the space either way.

| Piece | Where |
|---|---|
| Reading, WMO→condition→icon/skin, hourly parsing, sample time + key | [lib/models/weather.dart](../lib/models/weather.dart) |
| The icons themselves (Meteocons, MIT, **recoloured** — see below) | [assets/weather/](../assets/weather/) |
| `WeatherSkin` / `AppSkies` — the forecast card's wash and ink | [lib/theme/tokens.dart](../lib/theme/tokens.dart) |
| Photon geocode + Bright Sky forecast, in-flight de-dup | [lib/data/repositories/weather_repository.dart](../lib/data/repositories/weather_repository.dart) |
| Device cache (places forever, forecasts 1 h) | [lib/services/weather_cache.dart](../lib/services/weather_cache.dart) |
| `weatherProvider`, resolve pass, forecast window | [lib/state/weather_state.dart](../lib/state/weather_state.dart) |

- **The vendored icons are not upstream's colours, and must not be re-copied from upstream.**
  Meteocons draws its cloud at `#F3F7FE` over `#E6EFFC` with an `#E6EFFC` outline — art meant for a
  coloured card. Against the app's own `screenBg` that is **1.09:1**: on Home's week strip the
  overcast, drizzle, rain, fog and snow icons were invisible, which read as "the icons are too
  small" and is not. Bodies are deepened to `#CBDBF4`/`#A6C0E8`, outlines to `#6E96D0`, fog's lines
  from `#E2E8F0` to `#8FA4C4`. The outline is what carries the shape: 3.03:1 on white, and 5.75:1
  on the dark surface, which is the pair that had to hold at once because one file is drawn on both
  grounds. Sun and moon were already legible and are untouched. MIT permits it; the licence stays in
  the folder. `WeatherReading.iconAsset` says the same thing beside the mapping.
- **Providers: Bright Sky (forecast) and Photon (places), since 2026-09-18.** Open-Meteo served
  both until then and was dropped because its free API is **non-commercial only** — its terms name
  "apps that have subscriptions" as commercial, and Aporah Plus is one; the paid plan was the
  alternative. The replacements are free for commercial use, need no key, and both require a
  credit, which `_WeatherCard` prints ("DWD · OpenStreetMap"):
  - **Bright Sky** (`api.brightsky.dev/weather?lat&lon&date&last_date`) is a free JSON front for
    the **Deutscher Wetterdienst's** open data (MOSMIX forecast, observations for past hours). The
    data is the DWD's under CC BY 4.0 / GeoNutzV — commercial reuse allowed, the DWD named as the
    source. Horizon **10 days** (was 16). Hourly, and it names a sky (`partly-cloudy-night`, `rain`)
    rather than numbering it, so `brightSkyForecast` in `models/weather.dart` maps each icon back to
    a WMO code and the cache, icons and skins are untouched. Its reach is Germany and its
    surroundings — the launch market. **If the app ships abroad, MET Norway's `locationforecast`
    is the worldwide equivalent** on the same terms (CC BY 4.0, free, a User-Agent required, cache
    responses, ≤ 20 req/s per application in total).
  - **Photon** (`photon.komoot.io/api/?q&limit&lang=de`) — OpenStreetMap data (ODbL), free under
    fair use; the Abfall address search already uses it server-side. It knows **addresses**, which
    Open-Meteo's geocoder never did, and it matches names fuzzily and globally, which is the new
    risk: "Kita Sonnenschein" is somewhere in Berlin, "Raum" comes back as "Raumbach". So
    `_fetchPlace` accepts the whole line only if the hit's city/postcode/district/county mentions a
    town the line names, and a town-only query only if Photon calls the hit a `city`/`district`
    *and* its name is in the query. Everything else is a miss, and a miss falls back to the home
    town — a wrong town's weather is worse than the household's own.
  - **What that costs, stated honestly.** A place name or coordinate and an hour leave the phone
    with the **user's IP address**, which the Edge Function route would have hidden behind
    Supabase's. An IP plus a residential place plus a timestamp is personal data under the DSGVO,
    so both providers belong in the Datenschutzerklärung. **Where each is hosted is not yet
    checked** — Open-Meteo's German hosting was part of the old argument, and it has to be
    re-established for these two before the privacy text is written. If the app ever needs to
    shrink its external footprint, this is the one place where moving *behind* an Edge Function
    would improve privacy rather than not.
- **Times are made device-local.** Bright Sky answers with offsets; `date`/`last_date` are sent as
  local midnight *with* the phone's offset (a bare date is read as UTC midnight and drops the first
  two hours of a German day), and each timestamp is `.toLocal()`ed, which is how an event's start is
  held too.
- **Location, per event**: the event's own free-text `loc` — the same string that already opens
  Maps — geocoded, falling back to the household's town when it is empty *or* unplaceable
  ("Turnhalle" is far more often the family's own town than somewhere else). The home town is
  parsed out of `families.address` from onboarding (`homeTownFrom`): the geocoder searches place
  *names*, so the full line with a house number finds nothing. **Never device GPS.**
- **An address is retried town-first**, because of that last point: `_placeQueries` asks for the
  whole string, then narrows each comma-separated part two ways — stripped of its postal code /
  house number, and everything *after its last number* (`placeAfterNumber`). Both spellings are
  ordinary and only the second one handles the comma-less line German families actually type:
  "Amtshof 3, 28857 Syke" and "Amtshof 3 28857 Syke" both reach "Syke", and `"28816 Stuhr"` is as
  much of a miss at the geocoder as the whole line is. A location with no number in it ("Kita
  Sonnenschein") is left alone rather than guessed at from its last word, and country names are
  dropped rather than tried — "Deutschland" geocodes perfectly well to a point in Hesse and would
  put that weather on the row. A town is the right granularity for a forecast anyway. Without all
  this, an event with a *real* address — the ones a family actually types — was the case that got
  no chip.
  **A remembered miss is forever, so widening the resolver means bumping `WeatherCache._version`**,
  which throws the device's file away once; otherwise every address that already failed keeps
  failing on that phone. It has been bumped twice for exactly this (v2 commas, v3 one-line
  addresses).
- **When an event is sampled**: a timed event at its start; an all-day event at 13:00 **on the day
  being rendered**, so each day of a week-long Ferien block carries its own forecast rather than
  all seven sharing Monday's. `eventSampleTime` and `eventWeatherKey` are the contract between the
  fetch and the render — if they ever disagree, every chip silently disappears.
- **Today is forecast whole**, from midnight (`WeatherNotifier._floor`), for timed events as much
  as all-day ones — an 11:00 appointment still shows its weather at 17:00. It was a 2 h grace for
  timed events, which meant the reading quietly left the row halfway through the afternoon while
  the appointment was still on screen. `past_days=1` on the forecast request makes sure the early
  hours are in the series.
- **No chip is the normal answer**: anything before today or past the 16-day horizon, no address
  and no placeable location, or simply offline. Weather is decoration and every failure resolves to a missing icon, never to an error.
- **Icon mapping**: WMO `weather_code` → 8 buckets (clear / partly-cloudy / cloudy / fog / drizzle
  / rain / snow / storm) → a **Meteocons** SVG (`WeatherReading.iconAsset`). Only clear and
  partly-cloudy have a night form — a rain cloud at 22:00 is still a rain cloud. Day vs night comes
  from the provider's per-hour `is_day`, since German sunset moves by two hours across the year.
- **The forecast icons are the one place in the app that is not the icon font**, and the reason is
  that a
  weather glyph in a single flat colour carries no information: tinted with the row's accent,
  drizzle, rain and overcast were three blue clouds a glance apart, and every event looked like the
  same weather. [assets/weather/](../assets/weather/) vendors **10 of Meteocons' 535** (MIT,
  `github.com/basmilius/meteocons`, `fill` style, licence shipped beside them), rendered full-colour
  through `flutter_svg` with **no `colorFilter`** — an amber sun, a grey overcast, a blue rain.
  Adding another bucket needs the file and one line in `iconAsset`, nothing else. They are drawn
  inside a 128 viewBox with generous padding, so a Meteocons file needs roughly 1.4× the size the
  font glyph had (26 on the agenda row, 46 on the sheet card).
- **The forecast card in the event sheet wears the weather; the agenda row does not.** `AppSkies`
  in [tokens.dart](../lib/theme/tokens.dart) holds ten `WeatherSkin`s — a two-stop wash plus the
  ink that reads on it, both palettes — and `WeatherReading.skin` picks one. Two decisions worth
  keeping: the wash is **pale, not the dark sky a weather app would use**, because Meteocons'
  clouds are near-white and a background dark enough for white text is one the icon disappears
  into (the cloudy/fog/drizzle/rain/snow skins are deliberately deeper than they first look like
  they want to be, for the same reason); and the **ink is the wash's own hue deepened** — amber on
  the sunny card, navy on the rainy one — since `AppColors.ink` on all ten flattens back to one
  grey card. Every skin clears 4.5:1 at its darker end. The agenda row stays plain on purpose: ten
  coloured cards down a day would read as a chart of the weather rather than as the family's day.
- **Caching keeps it polite**: forecasts 1 h and keyed to 2 decimal places (≈1 km, the model's own
  resolution), geocoded places forever **including the failures**, at most 8 distinct places
  resolved per pass, and identical requests de-duplicated while in flight. An unchanged calendar
  is not re-resolved at all for an hour.

## Calendar connections

New UI to build. **Must NOT change the existing Kalender screen's week/month view code.**
Provider icons already copied to `assets/calendar_providers/` (`google_calendar.png`,
`icloud_calendar.png`, `outlook.png`, `iserv.jpg`; Ferien and Abfall use plain icons —
`AppIcons.graduationCap` / `AppIcons.recycle`).

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
- **What the connect form became**: **one sheet with steps**, `showCalendarConnectSheet`
  (`calendar_connect_screen.dart`, `StepDots` at the top), the same for all six — the provider's
  own question, then what that answer opened up, then the name, then the confirmation. An
  account's calendars and its name are two of those steps and not one form: they shared a sheet at
  first, and an Apple ID with six calendars pushed the name field two screens down, so the sheet
  asked two questions at once and showed neither. Every provider used to *end* by opening a second
  sheet over its own, which is what the single flow got rid of.
  OAuth needs a second round trip for the list (`calendar-connect?action=calendars`), because the
  account is created by the browser callback and has no way to hand anything back to the app; when
  it comes back empty the picker step is simply dropped and `selected_calendars` stays null,
  which `calendar-events` reads as "all of them".
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
| OAuth-Start / Callback / Kalenderliste (`?action=calendars`) / Trennen | `supabase/functions/calendar-connect/` |
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
  enumeration an IServ connection lists one empty personal calendar. Always read-only. Some
  schools disable external CalDAV or require 2FA.

  **This is no longer how IServ is connected, and there is no longer a way to** — see the section
  below. The login sat on for a while as a second option at the bottom of the IServ page, for the
  school that does publish real collections; the row is gone, because it offered a credential form
  for a route that never finds a plugin calendar and so answered the wrong question next to the one
  that works. The server half stays: `calendar-caldav` still serves iCloud, GMX and WEB.DE, and an
  IServ connection made that way (`auth_type = 'caldav'`) is still read and still enumerates its
  collections. Nothing new can be made.
### School calendars connected by a link — IServ plugins and WebUntis

The thing that took the longest to find, so it is written down first: **an IServ CalDAV
connection returns empty because the calendars a family wants are not CalDAV collections at
all.** IServ's *plugin* calendars — Aufgaben, Klausuren/Klassenarbeiten, Geburtstage, Ferien —
are views generated by the modules that own that data. `PROPFIND` at any depth cannot see them,
because there is no collection there to see. What enumeration does find is the pupil's own
(empty) home and `+public`, the school-wide feed, which for a normal Gymnasium is several
hundred events about every class in the building and none of them filtered to the child's.

What IServ does offer is a per-plugin **link share**: Kalender → Einstellungen → Plugins → "Link
erstellen" mints a tokenised ICS URL of the shape

```
https://<schule>/iserv/public/calendar/ics/feed/plugin/<128-hex token>/calendar.ics
```

which answers `text/calendar` to an anonymous `GET` — no login, no CalDAV, no credential to
store. Verified against a live instance; the four Klassenarbeiten it returned for one class are
exactly what the CalDAV connection could not find.

**There is no API to enumerate or mint those links.** The IServ documentation describes none, and
the token only exists once a human has pressed the button. So the user creates one per calendar
and pastes it, which is why a connection holds a *list* of feeds rather than one.

**Which account a pasted link joins is decided by the name, not by where it was pasted from.**
`external_account` is `<host>/<slug(account)>` — `kgs-sb.de/alice` — and `calendar-link` looks that
pair up before it creates anything: found means append to that connection's feed list, not found
means a new account. There was a "+ Kalender hinzufügen" row on each account's card that sent a
`connection_id` to say the same thing; it is gone, because one Verbinden button and the name the
user types already answer it. The id is still accepted so an older build keeps working. Do not
remove the lookup and leave the upsert to sort it out: it conflicts on that same key and
**replaces** `config.feeds` wholesale, so a second link under a name already in use would drop the
first calendar and orphan its sealed URL.

**WebUntis is the same shape and shares the whole mechanism.** A student activates their own iCal
link under Profil → Freigaben/Datenzugriff → "Kalender publizieren", which mints
`https://<server>.webuntis.com/WebUntis/Ical.do?school=…&id=…&token=…` — again tokenised, again
no login. Three things to know before promising it: it is per student and only they can turn it
on (the button does not appear in admin or secretary profiles), Untis notes that student
subscriptions may need to be ordered and can carry a hosting charge, and a full Stundenplan is
6-8 events per school day — well over a thousand a year — so it wants its own calendar rather
than to be mixed in. Newer WebUntis builds put the same thing behind the timetable's three-dot
menu as "iCal-Abo verwalten" → format "Standard" → "Link erstellen", so the connect steps name
both paths. **The URL format is documented but has not been checked against a live instance** —
the IServ one has.

**This is now WebUntis's only route.** There was a second one, over the app secret behind the QR
code in Profil → Freigaben → "Zugriff über Untis Mobile", and it is deleted: the `calendar-untis`
function, `_shared/untis.ts`, the `auth_type = 'secret'` value, the `app_secret` column, the QR
scanner service and its Swift side, and the homework feature that hung off it (20260910101500).

The reason is proportion rather than function: a feed URL is a capability on one pupil's
timetable, revocable from the page that minted it; the app secret is TOTP seed material for that
pupil's WebUntis account, and this is an app whose users are children. Removing it also retires a
DSGVO question instead of answering it.

What it cost, so that nobody re-adds it without knowing what they are buying back —

| | iCal link (kept) | App secret (deleted) |
| --- | --- | --- |
| Entfall / Vertretung | **absent** — Untis strips cancelled lessons from the feed deliberately, after they broke Google Calendar | was present, as lesson status |
| Horizon | ~1 week back, ~12 weeks forward | was the school year |
| Hausaufgaben | none | was the source of the Board's homework rows |
| What we hold | one sealed feed URL | a sealed TOTP seed for the account |

**Hausaufgaben are gone from the app**, not merely from WebUntis: nothing else produced them, so
`Homework`, `homeworkProvider`, the Board's homework card, the week view's badge and the event
sheet's homework card went with the route. Board's person-filter row survived — it used to be
gated on there being homework to filter, and now narrows the tasks and the trackers, which every
household has, so it is gated on there being more than one person instead.

**`ical` is the same mechanism with the vendor removed.** Any published ICS link — a Verein's
fixtures, a Kita's closing days, a shared work calendar. It is a provider value and a tile and
nothing else: the same `calendar-link`, the same sealing, the same read path. IServ and WebUntis
keep their own tiles because finding the link is the whole difficulty for a parent, and a set of
numbered steps naming real menu items is the only part that cannot be generic. `webcal://` is
rewritten to `https://` on the way in, because that is what half the "subscribe" buttons on the
web put on the clipboard.

How it is built:

- `_shared/ics_feed.ts` fetches, redacts and parses a feed; `calendar-link` is the Edge Function
  that validates a pasted URL and stores it. A connection lists its feeds in
  `calendar_connections.config.feeds` as `[{id, name, host, added_at}]`, with `auth_type =
  'public'` and `is_read_only = true` — a pairing the original migration's check constraint
  (`auth_type <> 'public' or is_read_only`) already required. **The URLs are not there.** Each one
  is an AES-256-GCM envelope in `calendar_connection_secrets.feed_urls` under the feed's `id`,
  opened by `feedUrlOf` one line before the fetch and never held longer than the request. See the
  school-calendar paragraph in [backend.md](backend.md) for why, and 20260910070000 for how the
  feeds that predate it were moved without asking anybody to reconnect.
- **`config` holds a bearer token, so the client cannot read it.** It once could: the original
  `grant select on public.calendar_connections` was table-wide, and the trade was defended as "the
  only people who can read it are the members already looking at the events it returns". That is
  the same argument 20260908155018 rejected for `calendars.external_id`, and it is no better here
  — seeing events is scoped, revocable and ends with the membership, while holding the URL is none
  of those, and on a school connection one member's read returns *every* sibling's feed. 20260909101500
  replaced the grant with a column list that omits `config`. Adding a feed was always a
  `service_role` act behind a fetch that proved it answers; now reading one is too.
- Each feed's opaque `id` is a `RemoteCalendar.externalId`, so `selected_calendars`,
  `calendar_names`, the picker, the naming step and the stale sweep in `calendar-events` all work
  unchanged. It used to be the URL, which is how a bearer token ended up in three
  household-readable columns; a uuid rather than a hash of the URL, so the column cannot answer
  "is this family subscribed to *that* feed?" for someone who guesses one. Removing a feed goes
  through the function (`action: 'remove'`), because `config` is not client-writable; deselecting
  alone would leave the link stored — and removal now deletes the sealed URL too, so dropping a
  link destroys the credential rather than orphaning it.
- `external_account` is `<host>/<slug of the account name>`, which is what makes two children at
  one school two connections rather than an upsert collision.
- **One dead link must not take an account down.** `calendar-events` reads each calendar in its
  own `try`, leaves a failed one out of the response, and only fails the connection when every
  one of them failed.

- **A `TZID` that is a bare UTC offset.** IServ's plugin feeds write
  `DTSTART;TZID="+02:00":20260908T113000` and ship no `VTIMEZONE` at all. ical.js finds no zone by
  that name, falls back to *floating*, and resolves the wall clock in the runtime zone — UTC on
  Edge Functions — so an 11:30 Klassenarbeit lands at 11:30Z and shows at **13:30** in Germany.
  Two hours late in summer, one in winter, on every event. `registerOffsetZones` in `caldav.ts`
  takes the offset in the name at face value and registers it as a fixed-offset zone before any
  VEVENT is read. Sound rather than merely expedient: IServ emits the offset that actually applied
  on the day of the event (`+02:00` in September, `+01:00` in November), so there is no DST rule
  left to get wrong.

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
- **The Bundesland comes off the picked address, and Photon has none for the Stadtstaaten.** Berlin
  and Hamburg are one boundary, so there is no admin level above the city for the geocoder to
  name, and `properties.state` is simply absent (Bremerhaven loses its "Freie Hansestadt Bremen"
  now and then too). Until 2026-09 that meant a Berlin household was told there were no school
  holidays for it — on the capital. `geocode` in `abfall.ts` now fills `state` from the city for
  those three, and `ferienStateOf` in `calendar_connection.dart` does the same on the client from
  the town, as a belt to that suspender. It deliberately does *not* run the town through
  `bundeslandCodeFor`, whose contains-match would put "Sachsenhausen" in Sachsen.

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
day), `jumomind` (~21 authority apps; the nationwide MyMüll host is removed — send `Accept-Encoding: identity`, their
servers mis-serve some compressed responses), `abfallio` (abfall.io legacy widget — not JSON at
all but a multi-step HTML form whose hidden inputs carry accumulating server state; 17 of 44 keys
have since migrated to a v3 app API and 401), `ctrace` (no street enumeration exists, so coverage
is validated by *probing* the ICS export — a 200-with-events is the match).

**All six families are ported and live** (`supabase/functions/_shared/abfall.ts` +
`abfall_providers.ts`, moved across byte-for-byte and then adapted), **and three more were added on
2026-09-17: `bsr` (Berlin), `fes` (Frankfurt am Main) and `awm` (München) — the three largest
cities in the country, none of which any vendor family reached.** `abfall-lookup` serves the
address search, the coverage check and the ICS validation; `_shared/feeds.ts` dispatches on
`config.vendor` when a shared feed is created or refreshed. `mampfes/hacs_waste_collection_schedule` remains the right starting point for
the next platform family — the 2026-09 survey of it is in the coverage artifact (see below).

**Berlin (BSR) plans per house, and the adapter refuses to guess.** Three keyless GETs on
`umnewforms.bsr.de` — street search, `street:::number` → `AddrKey`, pickups by `AddrKey` — and
nothing that lists a street's house numbers. Karl-Marx-Allee 1, 3 and 12 answer three different
calendars, so an address the geocoder returned without a number resolves
`supported: true, needsHouseNumber: true` and the client says "bitte mit Hausnummer eingeben"
where it would otherwise tick the calendar; a number the vendor doesn't know answers the same
way, and a street that runs through several postcodes hands the postcodes over as the house-number
chips. `hnrId` carries the `AddrKey`, which is the whole address as far as BSR is concerned. Its
`BM` category (seen where `BI`/`HM` are not) is read as a combined Biogut/Hausmüll tour; `WS` is
ALBA's and says so in the title. The onboarding placeholder already asks for "Straße Hausnummer,
Ort", which is what makes this workable.

**Frankfurt (FES) is the same shape and was found from a URL a household had already been given.**
`frankfurtplus.de` is a Laravel/Inertia site, and the address box behind its waste calendar is two
keyless JSON GETs that the page's own JS bundle names: `/api/addresses/search?query=<text>` returns
streets, or addresses once the text carries a house number, and `?street_code=<code>` returns every
house number of one street. The `id` on a row is what `/abfallkalender/<id>/ical` hangs off. It
plans per house like Berlin — Frankenallee 2 reads 156 pickups and no. 20 reads 130, because no. 2
also gets the second paper round — so it answers `needsHouseNumber` the same way. Two details are
load-bearing. The site normalises "-straße" to "-str." inside its own search, so the geocoder's
spelling goes in unchanged and Landau's retry dance is not needed. And **the postcode is checked**:
Frankfurt (Oder) is a different city 500 km away in Brandenburg, "Bahnhofstraße" exists in both, and
without the check a Brandenburg household could be handed Hessen's bin days. The registry spells the
town out as "Frankfurt am Main" for the same reason, because `townMatches` would otherwise accept
the prefix. Summaries arrive as "Frankenallee 2 : Restabfall-Abholung", so the address and the
`-Abholung` suffix are stripped before `classifyWaste` sees the bin.

**München (AWM) is a form rather than an API, and it is worth it for 1.5 million people.** The
Abfuhrkalender page carries **every München street** as `<span class="aostrasse">` — 5,834 of them,
which is the site's own autocomplete source — together with the TYPO3/Extbase form and its signed
`__trustedProperties` and `__referrer` fields. POSTing a street and house number with those echoed
back returns a page holding a link with `section=ics` on it, and that link is a full year of
pickups. The walk is **redone on every refresh rather than the URL being stored**, because TYPO3
signs the query with a `cHash` and the link also carries the Stellplatz and Leerungszyklus ids the
form derived; as a side effect a household whose bin rhythm changes is simply right the next day.
The POST needs an `Origin` header or it is refused. Titles arrive as "Restmülltonne, Francestr. 10",
so the trailing address is dropped while the "Achtung:" prefix on the holiday notices is kept —
those days are deliberately `EXDATE`d out of the series and must not read as ordinary collections.
Per house like the other two. Where the form answers with a **Leerungszyklus chooser** (several
emptying rhythms at one bin location, 0 of 24 sampled addresses) the adapter stops rather than
guessing: picking one would pick the household's bin frequency for them and get half the dates
wrong, so they answer it on awm-muenchen.de and paste the calendar in.

**The AWM file also settled a question about all-day events.** Its `DTSTART` is
`;TZID=Europe/Berlin;VALUE=DATE:20260107`, which RFC 5545 forbids — a TZID must not be applied to a
DATE. Read on a machine set to German local time every pickup lands a day early, which looks exactly
like a real bug. It is not: ical.js already resolves a date-valued property as *floating* and
ignores the parameter, and Edge Functions run in UTC, where the dates are right. Worth knowing
before someone "fixes" it: reproduce with `TZ=UTC` before believing a date shift seen locally.

**Köln (AWB) is two keyless JSON GETs with no signature at all** — `/api/streets?street_name=…
&building_number=…` for the address and `…/ics/icscal.php?street_code=…&building_number=…` for the
calendar, one flag per bin. It was found the same way as Frankfurt: reading the page's own Vue
bundle, where the paths sit in a `settings` block. Three things about it are peculiar and each one
is a guard in `probeAwbKoeln` rather than a comment:

- **The search never says "no".** Asked for a street Köln does not have, it returns the
  alphabetically nearest one that it does: "Quatschstraße" comes back as "Quatermarkt", and a house
  number the street lacks comes back as a different house on a different street ("Venloer Str. 2" →
  "Kamekestr. 1z"). Every row is therefore checked against what was asked for and anything else
  discarded — the same discipline the Münchenhof bug taught.
- **A row holds two addresses.** `user_street_name`/`user_building_number` is the household's own;
  `street_name`/`building_number`/`street_code` is the **Stellplatz**, where the bins are actually
  put out, which in Köln is regularly round the corner (Dürener Str. 200 is collected at
  Theresienstr. 70z). The first pair is what a match is judged on, the second is what the calendar
  is fetched with. Judging on the second rejects real addresses; fetching with the first returns
  nothing.
- **The list is Stellplätze, not houses, so it is full of holes.** Sülzburgstr. has 5 and 100 but no
  50, and Olpener Str. does not answer until 200. A street is only written off after a spread of
  numbers has missed; probing house 1 alone would declare a 900-number suburban road unserved.

And because two of six trial addresses turned out to sit in the address list with an **empty
calendar** behind them, `supported` also checks that dates exist (`awbHasDates`, the JSON endpoint
rather than the ICS because it is a tenth of the size). `calendar-feed` would have refused the feed
anyway, but "we know your street, now give us the number" is a better answer than an error after
the household thought it had connected. Köln's one combined event per day — `"Papier (blau), Bio
(braun) AWB Köln"` — is split into two, because `binColorFor` matches the title and a combined one
would be filed under whichever fraction is tested first while the other bin was never drawn.

**Hamburg (Stadtreinigung) is the simplest of the city adapters, and it was built from one link.**
A household handed over the `webcal://backend.stadtreinigung.hamburg/kalender/abholtermine.ics?hnIds=139014`
they were already subscribed to, and `hnIds` is the whole address: one POST to
`/abfuhrkalender?…[action]=addresses` returns every street whose name starts with the query, each
carrying **all** of its houses with their `hnId`, and the ICS hangs off that id alone. The form's
action carries TYPO3's usual `cHash` and the endpoint answers without it — the same framework that
forces a signed form walk in München gives Hamburg away for free. Two things need guarding:

- **The street search folds nothing.** It is a literal, case-insensitive prefix match, so
  "Fränkelstraße" returns nothing where the city writes "Fraenkelstraße", and "Osterstrasse"
  returns nothing where it writes "Osterstraße". Hamburg is inconsistent with itself — both
  spellings appear in the same list — and so is the geocoder. Normalising both sides afterwards,
  which is how every other vendor here is matched, is **too late**: the fold has to happen before
  the request, so `srhSpellings` re-asks the name in each written form (both directions, capped at
  eight) until one answers. It is also capped at five results, so only the full street name is ever
  sent: "Oster" yields Osterbaum … Osterbekweg and never Osterstraße.
- **House spans overlap.** The list is collection points, so a row is regularly a range — "9-11",
  "30-35", "4-4A" — and ranges are consulted only after every exact name has missed, because both
  forms coexist (Fraenkelstraße has "1-3" *and* a separate "2"). The trap is that two spans can
  claim the same number: Winterhuder Weg lists "4-10" **and** "7a-7c". Taking the first match would
  have filed half that street under whichever row came back first. A letter settles it where there
  is one — 7b is in 7a-7c and nothing else — and where nothing settles it the household is asked,
  which costs only a dropdown because this is the only vendor here that enumerates the houses, so
  `probeSrh` returns the whole street as `hausNrList` rather than an empty text field.

An unknown `hnId` returns a **valid, empty calendar** rather than an error, exactly as Köln's does,
so `supported` checks that dates exist. The feed also carries `X-SRH-CONTAINER-TYPE`
(black/blue/green/yellow/leaf) — the only machine-readable bin field in any of these vendors — but
it is deliberately **not** plumbed through: `binColorFor` classifies from the German title on the
Dart side and Hamburg's titles are explicit ("Abfuhr grüne Biotonne"), so a second colour channel
would be a second thing to keep true. Only "Laubsäcke", the autumn leaf collection, needed a rule
adding, and it is spelled out rather than matched as a bare "laub", which "Urlaub" contains.

**Stuttgart (AWS) has no ids at all, and that is exactly what makes it dangerous.** A household
handed over two links —
`service.stuttgart.de/lhs-services/aws/api/ical?street=Wachenheimer%20Str.&streetnr=3` and the same
for `Franckeweg&streetnr=15` — and the address *is* the API: there is no id to look up, so the
whole adapter is one question, "is the calendar that came back about the address we asked for?".
The city's own form names the two endpoints beside it in `data-serviceurl` attributes on its
inputs, `/strassennamen` and `/hausnummern`, and the parameter is `street`, not the jQuery
autocomplete library's default `query` — which is why guessing at the query string finds nothing
and reading the form finds it immediately.

- **The street must be abbreviated the city's way.** "Wachenheimer Straße" is a 404 and the search
  will not find it either; only "Wachenheimer Str." is served. So the street is always resolved
  first and the canonical spelling used from then on. `streetStem` already did the right thing —
  it drops the trailing type word, which is the longest prefix the city is guaranteed to share —
  and `normStreet` already folds "Straße" and "Str." together for the comparison, so this cost no
  new normaliser, only the discipline of looking the street up before fetching anything.
- **The feed answers about a neighbour rather than saying no.** This is the trap, and it is worth
  stating plainly because the result looks perfectly healthy: it prefix-matches on **both** axes.
  `Königstr. 1` returns a full calendar for **Kleine Königstr. 1** — a different street — and
  `Badstr. 1` returns one for **Badstr. 11** — a different house. Both are 200s with a plausible
  three months of pickups, and a household handed them has no way to tell. The only thing that
  gives it away is `X-WR-CALDESC`, which echoes the address the server actually resolved, so every
  fetch is compared against what was asked for and a mismatch is refused.

The second half of that check took a sweep to get right, and the first version was too strict. A
correct hit on a **shared collection point** echoes no address at all — just "Abfallwirtschaft
Stuttgart" — which is how Hohenheimer Str. 11 and Olgastr. 1 legitimately answer, so refusing
every un-echoed calendar rejected 7 of 25 real addresses. The number is confirmed against
`/hausnummern` instead, asked with the **whole** number as the prefix rather than its first digit:
that endpoint is capped at 12 results, so "1" on a long street returns 1, 1A, 1B, 10A … and never
reaches 134, while "134" returns "134". An invented number returns nothing. Probing 30 numbers
that are not on their street produced a 404 or an echoed substitution every single time and never
a silent un-echoed calendar, so the two axes together leave no gap.

Verified live at 25 real addresses — streets and house numbers both taken from the vendor's own
lists, so none of them is invented — across every Bezirk: **23 resolved, 0 matched wrongly, 0
unsupported.** The two that ask are genuine vendor mis-resolutions (Königstr. 1 and Vaihinger
Landstr. 1), where refusing is the only honest answer; those households cannot be served through
this API at all, and a neighbour's bin days would be worse than a question. Both of the links the
household started from reproduce exactly: 33 and 32 events, identical event for event.

Stuttgart's house list is deliberately **not** offered as a dropdown, which is the opposite of the
call made for Hamburg. Hamburg enumerates every house on a street in one response; Stuttgart caps
at 12 and the data behind it is ragged — "23-25", "27,27A" and "25TEILII(ErbbaurFl" are all real
entries on Königstr. A dropdown built from that is missing numbers that do work, and a picker that
cannot offer your address is worse than a field to type it into.

**Düsseldorf (AWISTA Kommunal) is addressed by a uuid, and the lookup is a Next.js Server
Action.** A household handed over `AWISTA_Kommunal_Abfuhrtermine_Askanierstrasse_3.ics`, whose
every event points at
`www.awista-kommunal.de/abfallkalender/54c05220-3535-4231-a85e-5b37397efc1b`. The uuid is the
address, and nothing in the file — no street id, no postcode, no key — says how to obtain one.
Guessing at `/api/…` finds nothing, because there is no REST API at all: the site is a Next.js app
and its address search is a **Server Action**, which on the wire is a POST to an ordinary page URL
with the function's id in a `Next-Action` header and its arguments as a JSON array.

```
POST /abfallkalender     Next-Action: 406d03…
["Askanierstraße 3"]
-> 1:{"items":[{"title":"Askanierstraße 3","id":"54c05220-…"}],
      "isReadyForHouseNumber":false,"addressIdForQuery":"54c05220-…"}
```

That one call is the whole lookup; the calendar is then `/abfallkalender/<uuid>/calendar.ics`. The
reply is an RSC stream rather than JSON — numbered lines, one JSON value each — so the line
carrying `items` is picked out rather than the body parsed whole.

- **The action id is build-specific, so it is discovered rather than trusted.** A stale one answers
  `404 Server action not found.`, which is unambiguous, and the adapter then re-reads the id from
  the page's own JavaScript (`createServerReference("…", …, "searchAddressAction")`). There are
  **two** functions of that name on the site — the home page's teaser search resolves to the city's
  twelve-digit *street* code, not a calendar uuid — so discovery insists on the chunk that also
  mentions `addressIdForQuery`.
- **There are two forms of the same page, and only one of them works.** The no-JS form POST
  resolves a handful of addresses and refuses the rest, because the real form carries a hidden
  `addressId` the search fills in. Chasing that dead end produced a convincing but entirely false
  picture — Bilker Allee 1 resolving and Bilker Allee 53 not, on a street where both exist. If a
  vendor's own site works and the reproduction does not, the difference is a field, not the data.
- **The search never says no.** It is fuzzy in both directions and always answers with something:
  "Quatschstraße 1" comes back as *Kuhstraße 10*, "Kopernikusstraße 6" as *Kopernikusstraße 60*,
  "Königsallee 56" as *Berliner Allee 56*. Every one of those carries a real uuid for a real
  address elsewhere in Düsseldorf. So no row is taken on trust: its own `title` must match what was
  asked for, and then the ICS must agree too — every VEVENT carries
  `LOCATION:Askanierstraße 3\n40547 Düsseldorf`, the vendor stating out loud whose bins these are.
- **It folds `Str.` into `Straße` but not `ae/oe/ue/ss` into umlauts**, the same gap as Hamburg —
  "Koelner Strasse 1" sets no `addressIdForQuery`. Unlike Hamburg it costs nothing: the
  *suggestions* come back in the city's own writing regardless, so the title scan finds the row in
  the same single request and no spelling has to be re-asked.
- **An address can resolve and still have no calendar.** Venloer Str. 1 and Grafenberger Allee 302
  both return a valid uuid, a valid page and an ICS with zero events. Connecting one would give a
  household a bin calendar that stays empty forever, so at least one pickup is required before the
  address counts as supported.
- **The site is behind Vercel's rate limiter** and answers 429 to a burst — which trips at roughly
  ten address lookups however they are spaced. It matters less for what the app does (one lookup per
  household, one feed fetch per address per day) than for how badly it would read if it leaked: a
  429 coming out of the probe is indistinguishable from "no such address", so the UI would offer
  **"Anfragen"** for a city that is already covered. Two retries with `Retry-After` turn a burst
  into a pause; anything past that is a real outage and is reported as one.

Verified live at 49 real addresses taken from OpenStreetMap rather than invented — 25 from the
centre, 24 restricted to buildings tagged residential: **30 resolved with the right address echoed
back, 19 asked for a house number, 0 matched wrongly and 0 came back unsupported.** The split is
the point: 20 of the 24 residential buildings resolved, against 10 of the 25 central ones, most of
which are shops and offices that AWISTA services under a commercial contract with no public
calendar. The residential misses are houses the vendor's **own** address list does not hold —
Zeisigweg has 1, 10, 11, 13, 14 and no 12; Kopernikusstraße has 5, 7, 7A, 10, 12–15 and no 6 —
which is also why no house-number dropdown is offered: a list that cannot be trusted to contain
your address is worse than a field, and offering the neighbour's number instead is exactly the
substitution every other city's trap is about.

**Does next year arrive by itself? Yes, and the evidence is worth keeping.** Most authorities
publish exactly one calendar year — on 2026-09-17, 27 of 130 live providers reached past 31
December. Nothing is stored on our side (no calendar, no link), so whatever the vendor serves on
the next refresh is what the household sees; no reconnect, no re-upload. The shapes:

- **Köln takes `start_year`/`end_year` as free parameters**, so the read asks for this year *and*
  next. `start_year=2027` today is a valid, empty calendar rather than an error, and a span request
  returns whatever exists — so 2027 appears the day AWB publishes it, with no gap.
- **München cannot be asked.** The ICS link is signed with a `cHash` per year: editing `year=2026`
  to `2027` is a 404, and the form ignores a `[year]` or `[jahr]` posted to it. AWM alone decides.
  That it *does* advance is provable rather than assumed: correctly signed links archived in the
  Wayback Machine for **2022 and 2024** still return their ICS today, and the same form emitted
  `year=2024` in January 2024 and emits `year=2026` now. What cannot be settled from here is the
  exact switch-over date — late means a short December horizon, early means the rest of the
  current year disappears — so it wants looking at in December rather than pre-empting.
- **Hamburg has no year at all.** Its feed is a rolling window of roughly four months from the day
  it is asked, so today's request already reaches into January 2027 and there is simply no year-end
  to survive. The cost is the other direction: nobody in Hamburg — including the Stadtreinigung —
  sees further than four months ahead.
- **Stuttgart is the same shape as Hamburg, one month shorter.** A rolling ~3 months from the day
  it is asked, with no year parameter to pass and nothing to roll over.
- **Düsseldorf is a calendar year, and the proof that it rolls is the uuid.** The feed runs from
  the Monday of the current week to 31 December and takes no year parameter, so on its face it is
  München's shape. But the address is a uuid rather than a signed link, and a uuid captured by the
  Wayback Machine in **December 2025** returns the 2026 calendar when fetched today — so the year
  advances underneath a key that does not change, and nobody has to reconnect.
- **Leipzig is a calendar year** (today → the last published pickup, 24 December on 2026-09-18);
  `year`/`date` are ignored, so 2027 appears when the city publishes it. **The Athos portal**
  (Dortmund, Schaumburg, Hameln-Pyrmont, Landkreis Karlsruhe) is the same, read from whichever of
  its two sources reaches further. **AbfallPlus v3 takes a free date range**, so the read asks up
  to the end of next year and there is no rollover at all — Osterholz already shows January 2027.

**Leipzig, Dortmund and Essen (2026-09-18) — three families, and what each one teaches.**

- **Leipzig (`srl.ts`) is Hamburg's shape.** `rest/Navision/Streets?search=` sits in the Alpine.js
  `x-data` of the city's own page and returns every house on the street with its `position_nos`;
  the ICS is those numbers comma-joined. Three traps: without `name` *and* `mode` the ICS answers
  "Curently in Maintenance Mode." with a 200, so that text is not an outage signal; without
  `time_allday=true` every pickup is a 05:30–13:30 "(Abholzeit)" block; and the UIDs are random per
  request, so ours are built from the houses and the day. DTEND equals DTSTART, and is moved to the
  next day.
- **Dortmund (`athos.ts`) is a platform, not a city.** EDG's iframe is an Athos "WasteManagement"
  servlet, and the same product runs Schaumburg, Hameln-Pyrmont and Landkreis Karlsruhe — so the
  one adapter brought four providers. It is a **stateful** form walk (GET → CITYCHANGED →
  STREETCHANGED → forward; skip one and it answers "Bitte wählen Sie eine vollständige Adresse"),
  and it differs per tenant in ways read off the form rather than configured: `Ort` is a
  **first letter** in Dortmund and a town elsewhere, the house number a `<select>` or a text field,
  and the `ApplicationName` itself differs by build (Hameln's wrong one lands on "Willkommen", no
  error). **Its own iCal link is keyless (`AboID` is unchecked) but its horizon is a tenant
  setting** — two pickups per bin in Dortmund, the year in Schaumburg — while the result page is
  the reverse, so the read takes both and keeps whichever reaches further, never merging them.
- **Essen (`abfallplus.ts`) was never missing a vendor, only a protocol.** The page embeds
  `<abfallplus-publisher key=…>` — an abfall.io key — and the same `waction=init` the legacy widget
  posts now answers JSON with an `apiKey` for `widgets.abfall.io/graphql`. That is why keys looked
  dead to `abfallio.ts`. The old `abfallkalender.ebe-essen.de` is NXDOMAIN. **Which bins are the
  household's is `PUB_ABFALLTYPEN.checked`**; asking for everything gives Essen's twenty district
  Schadstoffmobil stops. Duisburg, Reutlingen, Märkisch-Oderland, Nordsachsen and Osterholz came
  with it. **Three that answer are left out on purpose** — Göttingen and Schwarzwald-Baar publish
  every rhythm of one bin side by side for the household to tick, and Calw plans per Ortsteil —
  see the note on `ABFALLPLUS` in `abfall_providers.ts`.
- **The postcode fallback in `resolve.ts` can hand a town somebody else's street.** An address in
  a town nobody serves is retried under each place sharing its postcode, so "Torgauer Straße,
  04838 Eilenburg" (not ASG Nordsachsen's) resolved to *Mockrehna's* Torgauer Straße. AbfallPlus
  now accepts a different city only when the geocoded town is one of its districts (`inCity`).
  **The same hole is open for every other Landkreis family** (regio-iT, AWIDO, Athos, …), whose
  towns carry no postcodes; it is noted here rather than fixed, because narrowing the fallback
  changes resolution for 140 providers and wants its own census.

**Dresden, Hannover, Bielefeld and Wuppertal (2026-09-18, second batch).**

- **Bielefeld is Athos again, one build further on.** The production path is
  `WasteManagementBielefeldTest` (the one without "Test" is a 404), the whole page arrives as
  `var text = '<!DOCTYPE HTML>…'` for an iframe to write, the form carries ticked bin checkboxes and
  a `Zeitraum` radio of **October-to-September years**, and labels are numbered where the dates are
  not (`Label1M` / `TermineDatumM_1`). `athos.ts` now unwraps the script, posts back whatever is
  ticked, and walks every `Zeitraum` and joins them — on 18 September the ticked year starts in a
  fortnight and today's pickups are only in the other.
- **Dresden (`srdd.ts`) is an Apache Wicket app**, so the session is a cookie set inside a 302 (a
  cookieless fetch loops 20 redirects) and each step is an Ajax behaviour: POST the street to set
  the model, GET the house `<select>`, POST "Jetzt finden" for the `STANDORT`. **The select's ids
  are not the STANDORT** (Neumarkt 6: 71676 vs 80542). The ICS then takes any
  `DATUM_VON`/`DATUM_BIS`, so there is no rollover. Incorporated villages repeat street names with a
  tag — "Dorfstraße (CB)" — and only a postcode we can place picks a tagged twin. A house picked
  from the list is stored as `h<app id>` and looked up on every read, because the client connects
  with the chip's id and that id is not the calendar's.
- **Hannover (`aha.ts`) brought the whole Region**: 21 municipalities on one stateless TYPO3 form
  whose last POST *is* the ICS. Street labels carry their district ("Voltastr. / Vahrenwald"), and
  since the geocoder gives none, every same-named candidate is asked for the house number and only
  those that know it survive; two survivors become chips. The **Ladeort** is where the bins are
  emptied — a corner house has two — and the one written as the household's own door wins. A
  calendar year: today to 31 December, `jahr` ignored.
- **Wuppertal (`awgwuppertal.ts`) plans per street**, except where it doesn't: the form's 303 goes
  either to the street's calendar or to a list of houses, each linking its own month view. Every
  link is **cHash-signed and an unsigned one is a 404**, so the read walks the form each time and
  takes every `action=ics` year the page offers — 2026 and 2027 on 18 September, which is the whole
  rollover. "Restmüll-50%" (the fortnightly tariff) is dropped: it only ever shares a day with the
  weekly "Restmüll".
- **Stuttgart reports its own outage as a 404.** `api/ical` answered `{"message":"Failed to
  connect to gis6.stuttgart.de …"}` with a 404 during this batch's probe, which the adapter read as
  a vanished address and turned into `reconnect_required`. It is now an upstream error, so a
  connected household waits out the outage instead of being told to reconnect.
- **Next:** Bonn, Augsburg, Freiburg, Hagen, Oldenburg, Leverkusen and Würzburg all sit on the
  Abfall+ **app** backend — one more platform, seven cities.

**The last cities (2026-09-19): Rostock, Reutlingen — and why not Koblenz.** Reutlingen was never
the Landkreis's to serve: the city collects itself (TBR), and tbr-reutlingen.de embeds its own
AbfallPlus publisher key (`1bf5dd38…`; the `bcb02770…` legacy script in the sidebar answers 401).
It needed one provider row, and asks Restmüll 2-/4-wöchentlich through the existing radiogroup
path. **Rostock** is `vendors/sro.ts`: the Stadtentsorgung's search answers an address key only when
"Ich bin als Eigentümer, Mieter oder Beauftragter zur Abfrage … berechtigt" is ticked. What that box
guards is the result page's container numbers; we tick it once, at connect, for the address the
household is connecting, store the key, and read only the ICS (`(period)/year` plus the
period-less next dates, which cross New Year — `(period)/next` is a 500). If that is ever judged
wrong, the fix is an in-app confirmation rather than dropping the city. **Koblenz** is declined:
Rest- and Biotonne days are given out by phone only, holiday shifts as a JPG, and for 2026 not even
the Wertstoff ICS files are linked. A partial calendar without the grey bin would look complete and
be wrong, so the town stays on "Anfragen".

**The other five rhythm cities (2026-09-19): Mönchengladbach, Siegen, Hildesheim, Heidelberg,
Bremerhaven.** One adapter each; the question already existed. With the Landkreis Hildesheim
coming along whole, 20 more Gemeinden. Three of the five do not print their rhythms side by side
at all, and that is the thing to know before touching them: **the adapter makes the rhythms into
lines**, so the shared mechanism never learns the difference.

- **mags (`mags.ts`)** — `mags.de/proxy/proxy_dates.php` answers JSON per street, number and
  year, and `turnus=1|2|4` changes the grey bin and nothing else. The read asks all three and titles
  the grey bin "Restmüll: Wöchentlich/2-wöchentlich/4-wöchentlich"; six requests (three turnus ×
  this and next year). An unknown number answers the street's plan.
- **Siegen (`citko.ts`)** — a TYPO3 `citko_abfall` form. The ICS link on the answer page is signed
  (`cHash`) and cannot be built by hand, so every read posts the form (three requests, no session).
  The ICS prints "Restmüll - 2-wöchentlich" and "- 4-wöchentlich" itself.
- **ZAH Hildesheim (`zah.ts`)** — ASP.NET postbacks (Gemeinde → Ortsteil "Alle" → street) find the
  street; the ICS (`ICalendar/Index.aspx?year=&streetID=`) is stateless and the street ids are
  unique across the Landkreis. **A day both rhythms share is written once**, as "Restabfall
  (14tägige und vierwöchentliche Abfuhr" (sic, no bracket), so it is read as two lines, one per
  rhythm; "(verschoben)" goes to the notes. Long streets are split into entries named in free German
  ("Bahnhofsallee 1-12 / 38-40", "Goschenstr. ohne Nr. 31-41"): plain ranges pick by number,
  anything with "ohne"/"gerade" becomes chips in the vendor's words, and the same name in two
  Ortsteile gets the Ortsteil from the ICS `LOCATION`.
- **Heidelberg (`heidelberg.ts`) has no dates, only a rule** — per bin a weekday and a week code
  (`U` odd ISO weeks, `G` even, `A` the weeks matching the house number's parity), plus holiday
  shifts and one Christmas-tree day. Its page asks the rhythm of **three** bins — Restabfall,
  Altpapier, Gelbe Tonne — so the read writes out weekly and fortnightly for each and the household
  answers three questions. Bio is not asked: the page offers weekly or "keine Abholung", and
  fortnightly only for the outlying streets flagged `true` in `/streetnames`. **A household with no
  Biotonne still sees Bio** — the question machinery has no "none" option, and inventing one for a
  single city was not worth it. The rule is written out to the year's end or the last published
  shift, never past what the city has planned. Street entries carry their numbers ("Nr. 1-81A,
  4-58"): a range with two odd ends is the odd side.
- **BEG Bremerhaven (`beg.ts`)** — a Rails session: token, two `PATCH`es (street, number), `POST`,
  and two redirects that each set a cookie the next needs, so the chain is followed by hand. The
  "14-tägliche Abfuhr" box is the rhythm; the read walks the session twice. **Only the next 30 days
  are published** in a readable form (the year is a PDF), so the calendar never shows more than a
  month ahead. BEG abbreviates "Bgm.-Smidt-Straße".

**The rhythm question (2026-09-18).** Freiburg, Hagen, Pforzheim, Saarbrücken and Neuss publish
every Restmüll rhythm side by side and leave the household to pick the one on its bin sticker, as
their own pages do. The household now picks it when connecting; 191 providers, 74 of 81.

- **The mechanism is shared and names no vendor.** An adapter that opts in implements
  `rhythm(title)` — which of its titles are one bin in different rhythms; `restRhythm` in
  `abfall/core.ts` covers "Restmüll: 2-wöchentlich", "Restabfalltonne (14-täglich)", "Restmüll rote
  Woche", "Restmüll-Pink". `abfall-lookup`'s `rhythms` action reads the address and returns every
  bin with **two or more options among its own dates** — never the vendor's full menu: Saarbrücken
  offers weekly Restmüll city-wide and Bahnhofstraße 10 has none, so a menu would let a household
  pick a rhythm that yields no Restmüll. Each option carries its measured interval (median gap,
  snapped to 7/14/28), because Neuss's "Grau"/"Pink" name a lid, not a rhythm. The pick is
  `config.rhythm` (`{bin: option}`), part of the feed key; the read keeps that line only, renamed
  to the bin with the rhythm in the notes. A config without a pick keeps every line, which is what a
  connection made before the question has always shown. **`calendar-feed` refuses an unanswered
  question** ("Bitte angeben, wie oft eure Tonne geleert wird."), the same way it refuses an empty
  calendar.
- **The app asks it in both places a bin calendar connects**, with one widget
  (`lib/widgets/rhythm_picker.dart`): the connect sheet's details step (asked after the address,
  or again after the house chip, since another house can have other rhythms) and a row under the
  onboarding's Müllabfuhr line. Only bins that really have a choice appear, so almost every
  address never sees it. The only way to change it later is to reconnect the calendar.
- **abfall.io (Freiburg, Hagen):** a `radiogroup` in `PUB_ABFALLTYPEN` *with a ticked member* is
  the widget pre-selecting one rhythm, so every member is read (Freiburg ticked weekly; every
  Freiburg household would otherwise have got weekly). A group with nothing ticked (Essen's mobile
  stops) stays out. Hagen ticks nothing and is read whole, less `skipTypes` (Umweltmobil,
  Grünschnittsammlung — city-wide stops). **Both publishers' street postcodes are wrong** (every
  Freiburg street claims 79112, every Hagen one 50895), so `wrongPostcodes` turns that check off.
- **Athos (Pforzheim, Saarbrücken):** Saarbrücken asks which containers the household has and
  answers an unticked form with no list; every box is ticked. Pforzheim prints weekly and
  fortnightly under one "Restmüll", told apart only by key (`RM7`, `RM14`), so a label two keys
  share gets the rhythm its key names; its 1,100-litre "Großmüllbehälter" is the third Restmüll
  answer. **Saarbrücken lists one street name once per Ortsteil** (four Bahnhofstraßen). The Athos
  read used to match loosely, which would have read the first in the list for all of them; it now
  matches the stored option exactly. The probe tries each candidate with the house number, and when
  several have it (Bahnhofstraße 31: Hauptbahnhof and Dudweiler) the chips name the Ortsteil and
  carry their street in the id (`"<street>|<nr>"`).
- **Neuss (`meinabfall`)** wraps the bin name in a link where Erlangen prints text; the row regex
  takes both.
- **The regression probe records the question** (`rhythm` in `probe_results.json`, a summary line
  at the end). A provider that starts asking without anybody adding it is a regression: on the run
  that added this, only Freiburg, Hagen and Pforzheim asked, at their probe addresses.

**Göttingen, and the eleven "rhythm" cities checked one by one (2026-09-18).** 186 providers, 69 of
81 (68 on the artifact). The rhythm list had been written from four verified cities and then
copied onto seven that were not; checking each live found one that was wrong and a note that was
false for five.

- **Göttingen (`geb.ts`) never needed the question.** It had been judged by the *Landkreis's*
  abfall.io calendar, which does list every rhythm; the city's GEB runs its own and answers each
  address with an ICS of that house's registered bins. The street list is JSON inside the
  Abfuhrkalender page; there is **no house list**, and an unknown number — or a house whose bins
  are registered under a neighbour's, which GEB's page warns about — answers a calendar with no
  events, so the probe returns `needsHouseNumber` with no chips and the app asks for the number.
  The year is in the path (`/2026/forward.php`); next year 404s until published.
- **The ten that do ask, and what each asks.** Freiburg and Hagen (abfall.io) and Pforzheim and
  Saarbrücken (Athos): Restmüll weekly / 2- / 4-weekly, Hagen as "rote/grüne Woche". Neuss: grey
  lid weekly, pink lid fortnightly — same weekday. Mönchengladbach (mags.de, Vue app over
  `proxy_dates.php`, `turnus` 1/2/4), Siegen (TYPO3 `citko_abfall`, "Restmüll - 2-/4-wöchentlich"),
  Hildesheim (ZAH, an ASP.NET postback app at `hildesheim.abfuhrkalender.de` behind a Borlabs
  blocker), Heidelberg (`garbage.datenplattform.heidelberg.de`) and Bremerhaven (BEG, 30 days
  machine-readable). **Only the first five have an adapter**; the other five need one as well as
  the question. **Heidelberg asks per bin** — Rest, Bio, Gelb and Papier each weekly or
  fortnightly, Bio also "keine Abholung" — so the question has to be per bin with the vendor's own
  labels, not one fixed Restmüll picker.

**Six cities, five new families (2026-09-18, sixth batch).** 185 providers, 68 of 81 big cities
(67 on the artifact, which does not count Reutlingen). What is left needs a decision, not a source:
the rhythm question (eleven cities), Rostock's self-declaration, Koblenz and Reutlingen.

- **hausmuell.info (`hausmuell.ts`, aturis) is two generations of one product**, told apart by the
  provider's `client`. Chemnitz (`proxy`, embedded by ASR) sends everything through `proxy.php` and
  keys the ICS on an *egebiet* id that comes with each house; **leave out `hidden_id_ort=0`,
  `hidden_id_ortsteil=0` or any `showBins*` flag and the ICS is an empty 200**. Erfurt (`direct`,
  linked from erfurt.de) keys it on street + house + **`hidden_id_zusatz`, which is the house id
  again** unless `check_zusatz.php` says the building is split. `hnrId` is `"hnr|egebiet"` or
  `"hnr|zusatz"`.
- **Magdeburg (`sab.ts`) renames its endpoint every season** (`index.2025_2026.php`), so it is found
  on each read: `index.php` names `js/sab2026_2025.js`, which names the endpoint. Dates are HTML
  under one `<h3>` per bin — and the Gelbe Tonne's size picker opens an **empty `<h3>`** in the
  middle of its own section, which first cost it every date. House entries can be ranges
  ("7-9a").
- **Potsdam (`swp.ts`) uses the operator, not the city.** potsdam.de's calendar asks for the
  Leerungsrhythmus; the Stadtwerke's `garbageservice-web` API knows it per address. The dates POST
  wants a JSON body (empty link maps will do) and **answers 406 to `Accept: text/html`**.
- **Osnabrück (`osb.ts`) collects two bins per date** — Restmüll with Altpapier, Gelbe Tonne with
  Biotonne — so each date cell is written out as two events. Years come from the `<h4>` above the
  cells, which read "Di 22.09.".
- **Erlangen (`meinabfall.ts`, krissel.it's Mein-Abfallkalender) is a platform** with a subdomain
  per tenant. Its ICS asks for an e-mail address and DSGVO consent, so the HTML list is read
  instead, always with `column_order=da_wa_we`. Street entries carry free-text ranges and validity
  ("gültig bis 31.12.2025", "(ab 1.01.2021)"); expired ones are dropped and the range picks the
  entry. **Neuss is a tenant of the same platform** but lists grey and pink Restmüll side by side,
  so it waits on the rhythm question, not on code.
- GELSENDIENSTE's street search took 4–15 s during this batch's probe; the city check passed.

**Nineteen cities, twelve new families (2026-09-18, fifth batch).** 179 providers, 62 of 81 big
cities. Every source is the authority's own site or the widget its own page embeds; five research
passes looked each city up there first.

- **Müllmax (`muellmax.ts`) is allowed only where the authority embeds it** — usb (Bochum), ash
  (Hamm), tbr (Remscheid), awm (Münster), ebm (Mainz), each an iframe on the city's own page. It is
  a server-side wizard carried by a hidden `mm_ses`, no cookie; `?abfuhr` starts at the street page
  (Remscheid first asks Remscheid or Wuppertal). **The street search is fuzzy** — Hamm answers
  "Amselweg" with Amselstraße — so the name sent always comes from the page's own `<datalist>`.
  Six requests per refresh. Münster also publishes the plan as open data (a yearly zip); the
  wizard was preferred because it needs no yearly re-index.
- **ABIS (`abis.ts`, flynet)** serves Gelsenkirchen and Bottrop from `<tenant>.abisapp.de`. The
  house number is free text and never checked (9999 gets a calendar), so the street is what
  refuses a made-up address. The ICS already runs to the end of next year. GELSENDIENSTE plans
  2- and 4-weekly Restabfall on paper only; the API shows the weekly bin.
- **A.R.T. (`art.ts`) is Trier plus four Landkreise** — 848 Orte from one Strapi search. A village
  planned as a whole has a row with no street and takes any street, **but only when the geocoder
  names that village**: the town matcher also tries "Konz-Kommlingen" for an address in "Konz".
  The ICS feed never refuses: an unknown key is one "Wichtiger Hinweis!" event.
- **Karlsruhe (`tsk.ts`) never refuses either**: an unknown street is answered with the first street
  in the list and some numbers with a catch-all span, so the calendar is only believed when its
  `X-WR-CALNAME` is the address asked for.
- **Wolfsburg (`waswob.ts`)** answers an unknown address with a 502, so the street list (which
  carries every house number) is asked first. **Heilbronn (`heilbronn.ts`)** is two whole-city
  JSON files: connecting stores the five district codes, and a refresh reads only the dates. The
  `*_big_*` series are 770/1100-litre containers and left out.
- The rest are one plain city source each: **Braunschweig** (`albabs.ts`, ALBA's TYPO3 plugin; two
  bins of one kind are two events a day), **Wiesbaden** (`elw.ts`; its districts include Mainz-
  Kastel/-Kostheim, which are Wiesbaden's), **Fürth** (`fuerth.ts`, the city, not the Landkreis),
  **Moers** (`enni.ts`; the ICS slug is taken from the form's redirect, never built), **Halle**
  (`hws.ts`; one event carries every bin of the day, comma-separated), **Jena** (`ksj.ts`; an
  unknown street answers a Java exception with 200). **Ulm** is the AWIDO client `ebu`, which EBU
  embeds; its feed also carries the Repair Café and events, now filtered out for every AWIDO client.
- `core.ts` gained `icsDays` (a whole-day ICS read by hand — ALBA writes DTEND equal to DTSTART,
  and Siegen-style `T220000Z` midnights are moved to Berlin first) and `dayEvents`.
- **Found and not built yet:** Chemnitz and Erfurt (hausmuell.info, which both authorities embed),
  Magdeburg, Potsdam (the Stadtwerke route needs no rhythm; the city's own does), Osnabrück,
  Erlangen. **Waiting on a decision:** the Restmüll-rhythm question now blocks eleven big cities
  (add Mönchengladbach, Neuss, Siegen, Hildesheim, Heidelberg, Bremerhaven); Rostock's form
  requires the user to declare they are owner or tenant, which the household should tick itself.
  **Koblenz does not publish its Rest/Bio days at all** (by phone only).

**Bonn, Augsburg, Würzburg, Leverkusen and Oldenburg (2026-09-18, fourth batch).**

- **The Abfall+ app backend was not needed, and should not be.** All seven cities it was queued
  for publish on their own sites, and the app route works by impersonating the authority's Android
  app — an emulator user agent, a fresh client uuid per request. Every city was looked up on its
  own page first, and that is the order to keep.
- **Bonn and Augsburg are Athos tenants** (`www5.bonn.de/WasteManagementBonnOrange`,
  `abfall.augsburg.de/WasteManagementAugsburg`). Augsburg's result page is a third layout: a
  `Headinfo<X>` heading per bin over cells named `…DialogComponent.Date<X>`, and the ids disagree
  ("HeadinfoPap" over "DatePapier"), so a date belongs to the heading above it. Its `Zeitraum`
  also offers "the next 4 pickups" and "the next 3 months"; only periods named "Jahres…" are
  walked now, which Bielefeld's Oct–Sep years also are.
- **Würzburg (`wuerzburg.ts`) is open data** — the city's own export on opendatasoft, licensed
  DL-DE-BY-2.0, so every event names the source in its notes. It plans by district (17), and the
  city's Abfallkalender page maps 1,113 streets to the same district ids. The export is a rolling
  today-to-31-December; check in December that 2027 follows (the page's year picker already has it).
- **Leverkusen (`avea.ts`) is AVEA's own site**: street pages by letter and a plain
  `abfuhrkalender-export/ical/<area>/<street id>/<year>/export.ics`. It labels its two Restmüll
  rhythms apart ("Restmülltonne", "Restmülltonne 4-wöchentlich"), so unlike Pforzheim both are
  kept.
- **Oldenburg (`oldenburg.ts`) is the city's TYPO3 "CollectionCalendar" plugin**, whose ICS export
  is a plain GET that ignores its own cHash. It never says no — an unknown number is an empty
  calendar — so empty *is* not-found, and three street names exist twice with one empty twin.
  "Sommerbiotonne" is a booked extra the export returns for everyone and is not asked for.
- **Leverkusen and Würzburg split long streets by number in the street's name** ("Bergische
  Landstraße 1 - 71 und 2 - 88", "Frankenstraße 1-197 ung./2-210 ger. Nr.", "ab 13"). `splitSpans`
  / `inSpans` in `core.ts` read both notations; two spans without "ung."/"ger." are the two sides.
- **Hagen and Freiburg join the rhythm queue.** Both embed the AbfallPlus widget on their own
  pages, and both make the household choose its Restmüll rhythm (Hagen: weekly / rote / grüne
  Woche; Freiburg: weekly / 14-täglich / 4-wöchentlich). Their keys are noted beside Göttingen's in
  `abfall_providers.ts`. Six authorities, two of them big cities, now wait on that one question.

**Mannheim, Kassel, Lübeck, Herne, Offenbach and Kiel (2026-09-18, third batch).**

- **Insert IT (`insertit.ts`) is one ASP.NET app per city** under
  `www.insert-it.de/BmsAbfallkalender<Slug>/`: `GetStreets?text=` → `GetLocations?streetId=` →
  `Calender?bmsLocationId=&year=` (ICS). The page loads Friendly Captcha for its mail form; the
  three calls don't ask for it. The street search is a literal prefix match that folds nothing,
  and each city spells its own way ("Hauptstr." in Mannheim, "Hauptstraße" in Lübeck). **One house
  can sit in several locations and all of them are needed**: Herne's Bahnhofstr. has a "7" carrying
  only the Wertstofftonne and a "7-7c" carrying all three bins. Every location naming the house is
  fetched, and if every bin they share falls on the same days they are merged (`hnrId` =
  `"9980+24462"`); if one bin has two rhythms they are different buildings and the household
  picks. The feed's UIDs are new random uuids on every download. Krefeld runs it too but is already
  served by MüllALARM; Hattingen's 2026 calendar held a handful of dates per bin and was left out.
- **Kiel (`abki.ts`) is three JSON GETs** behind ABK's Leerungstermine page. **The street list is
  Kendo server filtering**: unfiltered it returns the 115 streets under "A" and looks complete. The
  Termine are the containers actually standing at the address, with size and rhythm — not a menu
  of rhythms. House numbers are text with odd/even spans ("1 -11"). **The Gelbe Tonne is not in
  it** (Kiel publishes it on a separate Remondis page), so a Kiel household gets Rest, Papier and
  Bio only.
- **MyMüll only where the authority itself names it.** The nationwide `jumomind-mymuell` host
  re-published ~300 towns' schedules under the app's own brand, and Abfall takes a calendar from
  the authority's own service. It is replaced by `MYMUELL_OFFICIAL`: one row per Bundesland with a
  town allowlist, each checked on the authority's own site — paderborn.de's Abfuhrtermine page
  embeds the MyMüll web module for ASP (`service.mymuell.de/embed.js?m=asp`; the ICS it hands out
  matched ours date for date), A.V.E. runs it for the other nine Kreis municipalities, and
  Salzgitter's "Online-Abfallkalender" *is* the MyMüll web module. Ulm is out: its entry was a shell
  (1,166 streets, `dates` empty in every area). One row per state also closes the state guard's one
  gap. A new MyMüll town needs the same check before it goes on a list — and **app badges on the
  page are not that check.** Darmstadt was allowlisted because EAD shows the MyMüll badges, but the
  calendar beside them is EAD's own (`vendors/ead.ts`, 2026-09-19): 181 of 181 dates matched EAD's
  ICS, and it asks the Restabfall rhythm by lid colour, where the MyMüll copy printed all three
  rhythms at once and never asked. Look for the authority's own calendar first, always.
  **Since 2026-09-19 every MyMüll row is upload-only anyway** — see the next point.
- **Upload-only: a town we recognise and never fetch.** A provider row with `upload` in
  `abfall_providers.ts` is one whose operator either restricts the dates to non-commercial use in
  real terms of use (AWISTA Düsseldorf, SRO Rostock, Dresden — a free feature in an app with a paid
  tier is still commercial) or whose `robots.txt` disallows the path the dates live on (all 22
  `*.jumomind.com` hosts, MyMüll included, answer `Disallow: /`; mags Mönchengladbach, A.R.T. Trier,
  Stuttgart, Siegen). `resolve.ts` takes those towns from the registry (`town`, `cities`, or the
  generated `abfall/upload_towns.ts` — re-run `tool/abfall_census/gen_upload_towns.py` after a
  census), answers `uploadOnly` with the town's own calendar `page` and **no request to the vendor**,
  and refuses a stored config of an upload-only family before the adapter is reached. The app shows
  "Nur als Datei", links the page, and closes the Abfall sheet into the `ical` tile's upload in its
  **bin-file mode** (`binFileTown`): no link field, no account name, **no plan gate** — the file is
  Abfall and free, and `calendar-link` checks it (`abfall/bin_file.ts`, `isUploadOnlyTown`) before
  putting it on the uncounted `abfall:datei` connection. Postcode fallback still runs first, so a
  provider we may read wins. **It is Abfall everywhere the household looks**, although `provider` is
  `ical`: `CalendarConnectionsState.of` lists it on the Müllabfuhr page and not under iCal, and
  `calendar-events` sends its calendars with `feed_kind: 'abfall'`, which is what the bin colours
  and the evening-before reminder key on — without that the bins were an ordinary calendar nobody
  was reminded of.
  **How this was checked, and how to re-check it:** run `probe.ts` with `fetch` wrapped to log every
  URL, then match each against its host's `robots.txt` (Google's longest-match rules, `*` and `$`).
  After the switch the only hit left is Würzburg's opendatasoft `/api/`, kept on purpose: the data is
  DL-DE-BY-2.0, which grants commercial use, and every event carries the source. AWIDO stays live
  because only its `/Customer/` ICS export is disallowed; the adapter's fallback to it is removed and
  `getData` under `/WebServices/` is all it calls. **A new vendor gets the same check before it
  ships**: its terms page, its imprint (the eRecht24 "privat, nicht kommerziell" paragraph alone is
  boilerplate about the site's texts, not a restriction on the dates) and its `robots.txt` against
  the exact paths the adapter requests.
- **On an iPhone the town's page opens inside the app, because Safari would eat the file.** Safari
  hands a `text/calendar` response straight to Apple Calendar's "Add" sheet, so an iPhone never has
  an `.ics` to upload. `CalendarPageBrowser.swift` (channel `aporah/calendarPage`,
  `lib/services/calendar_page_browser.dart`) loads the town's page in a `WKWebView` with a
  non-persistent store; any calendar response, `webcal://` link or `download` link becomes a
  `WKDownload`, is kept only if it opens with `BEGIN:VCALENDAR`, and comes back in the media
  picker's shape. From the Abfall sheet the file is carried to the `ical` bin-file sheet, which
  checks it on open. It is a browser the household drives, not a fetch of ours — the provider is
  still never contacted by the server. Android's browser saves to Downloads, so there the page
  opens outside as before.
- **The census counted towns, and a town is not an address.** A live check of two real addresses
  per covered city (`city_check.ts`, feeding the artifact's Verlässlichkeit column) found
  Reutlingen listed by the Landkreis's AbfallPlus with no streets at all — the city runs its own
  collection — and Krefeld served through Schönmackers' MüllALARM key with half its streets
  missing, where the city's own GSAK calendar is on Insert IT. Krefeld now goes there.
- **Pforzheim and Saarbrücken run Athos but stay out**: both forms make the household tick its own
  Restmüll rhythm (Pforzheim 7- or 14-täglich, Saarbrücken weekly, 2- or 4-weekly) and print every
  rhythm under the one label "Restmüll". With Göttingen and Schwarzwald-Baar that makes four
  authorities waiting on one missing feature — a "which Restmüll rhythm is yours?" question in the
  connect flow. Kiel also has an Athos portal (`abki.de/WasteManagementKiel`), but it is the
  customer login, not the calendar.

**The live probe of every provider (2026-09-17, one real address each) found three that deliver
nothing, and none of them is an adapter fault.** `regioit-gt2` (Gütersloh) still lists 1,100
streets but every `termine` call is `[]` — the city left AbfallNavi and the instance is a shell, so
it is removed rather than left resolving Gütersloh as "verbunden" with an empty calendar. The
abfall.io keys for ASO Osterholz and Landkreis Kitzingen now 401 (both authorities moved to the
v3 widget; Osterholz is reachable again through the v3 GraphQL family `abfallplus`, built
2026-09-18 — the legacy row stays because it still 401s and the probe expects it to). And
Landau's C-Trace instance stores its streets abbreviated — "Königstr." answers, "Königstraße" is a
500 — where the geocoder writes them out, so `probeCtrace` now retries the other spelling
(`streetSpellings`). Re-run `deno run --allow-net census.ts` and the probe after touching the
registry; the artifact is built from their JSON.

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

**That same defect came back twice more, and the second time a real household found it.** Both are
worth knowing before touching `townMatches` again.

- **The prefix test (removed 2026-09-17).** The rewrite kept `candidate.startsWith(target)` beside
  the word-boundary rule, for "Freigericht" / "Freigericht-Bernbach" — and that accepted
  **"München" for "Münchenhof"**, a hamlet in the Landkreis Harz. Münchenhof publishes one schedule
  for the whole place, so it accepts any street, and a München address connected in the app came
  back with Saxony-Anhalt's Hausmüll, Papier and Gelbe Säcke on right-looking days. The reader
  spotted it because München has no Gelber Sack. The prefix test was **redundant**: `containsWord`
  already accepts a prefix that ends on a separator, which is the Freigericht case and not the
  Münchenhof one. Seven of the eighty largest cities were mis-routing this way — Münster to
  Münsterhausen, Hagen to Hage, Hamm to Hammersbach, Siegen to Siegendorf, Gera to Geratskirchen,
  Salzgitter to Salz.
- **The same name in two states (guarded 2026-09-17).** A boundary rule cannot help when the names
  are simply equal, and **37 town names in the registry are served in more than one Bundesland** —
  Kirchheim in three. So each provider carries the state it serves (`PROVIDER_STATES` in
  `abfall_providers.ts`, verified independently against each provider's own town list) and
  `matchTownAndStreet` drops a
  candidate whose state contradicts the geocoded address. That is the postcode's information in the
  form the vendors actually give us: **none of them publishes a PLZ per town, but each serves
  exactly one Bundesland.** The one exception, the nationwide `jumomind-mymuell`, was removed on
  2026-09-18 (see the third-batch note), so there is no gap left. Where a vendor *does*
  return a postcode it is used literally instead — see the FES Frankfurt note above, which is what
  keeps Frankfurt (Oder) out of Hessen.

**The street had the same defect one field over, and it read as "no vendor at all" (fixed
2026-09-17).** `normStreet` folded `Straße`/`Str.` but then threw away every character outside
`[a-z0-9äöü]` — which **deletes** `ß` and every accent instead of folding them. So the first real
München address after the vendor shipped, **Francéstraße 10**, normalised to `francstr` while AWM's
own list says `Francestr.` → `francestr`, and the household was told München has no Entsorger two
minutes after the deploy that added it. The umlauts were safe only by accident: both sides happen
to spell them the same way, so the class kept them and nothing noticed the letters beside them
going missing. `foldGerman` now maps ä/ö/ü/ß to ae/oe/ue/ss and NFD-strips the rest before the
class runs, so `Weissenburger Str.` and `Weißenburger Straße` also meet, which they previously did
not. **Never write a normaliser as a character class of the letters you thought of** — the ones you
did not think of are silently deleted rather than rejected, and a deleted letter makes a shorter
string that still looks like a word. The probe's AWM address is now spelled the geocoder's way
rather than the vendor's, so this specific miss cannot come back unseen.

**The address that is not covered has two answers, and neither is a sixth vendor.** The Abfall
flow's own fallback is a pasted ICS link, which is what a vendor with a "Kalender abonnieren"
button gives you. The other is on the `ical` tile: **upload the `.ics` file**, for the many
municipalities whose site offers a download and nothing else. That route seals the file's bytes
rather than a URL (`calendar_connection_secrets.feed_files`), re-parses them on every refresh, and
matches a re-upload on the file name so next year's plan replaces this year's — see the feed
section of [backend.md](backend.md). Uploading is iOS-only, because the picker is a
`UIDocumentPickerViewController` behind `aporah/media` and there is nothing behind it elsewhere.
Neither fallback is a reason not to add the vendor family properly when one turns up often.

**A town nobody serves goes to its own page (2026-09-19), which replaced "Anfragen".** The
Abfuhrkalender Atlas researched the official calendar page of every unserved Gemeinde;
`tool/abfall_authorities/gen_town_pages.py` compiles it into `abfall/town_pages.ts`, keyed per
Bundesland by `townKey` (the register's "Wörth a.d.Donau, St" and the geocoder's "Wörth an der
Donau" are both `wörth donau`) and by `townHead` where that is unique. `resolveAddress` asks it
last, after every provider and every upload row, and answers `uploadOnly` with `atlas: true`, the
`page`, and `format` — `ics`, `pdf`, `html` or `app`, a researcher's reading of the page that picks
the instructions and never removes a button. A town whose name the atlas shares with a served town,
or whose namesakes in the state have different pages, gets no page and is sent straight to the
upload. `isUploadOnlyTown` knows the atlas too, so the file lands on the free `abfall:datei`
connection. In onboarding a file town is a stage of the address step, like the rhythm questions
(`hasWasteQuestions` includes `uploadOnly`): the page and the upload sit in the same search layout,
and `OnboardingNotifier.useBinFile` checks and connects the file there, no second sheet; "Weiter"
goes on without it. Upload rows are matched the same strict way — "Buch am Erlbach" used to reach
Altötting's MyMüll page through the word "Buch". **The PDF route is built on the client and gated**:
with `pdfUploadAvailable` the page browser keeps a PDF instead of showing it, the upload sends it
base64 in `calendar-link`'s `pdf` field (8 MB cap), and a plan with several Bezirke gets a
`district` step listing each with its next dates before `add` is sent with the `choice`. The parser
behind it is built separately, in `_shared/abfall/pdf/`. The live census of what is covered today
is the coverage artifact linked from [production-plan.md](production-plan.md); rebuild it after
touching `abfall_providers.ts`, and re-run `build_tracker.py` then `gen_town_pages.py` after the
atlas changes.

Verified end to end against the live vendor APIs, one address per family
(`geocode → resolveAddress → readAbfallEvents`, 2026-09-17): Aachen/regioit 157 events,
Waiblingen/awido 131, Darmstadt/jumomind 50, Bremen/ctrace 63, Lienen/abfallio 50,
Stuhr/awgbassum 23, Berlin/bsr 92 (Karl-Marx-Allee 1) and 244 (no. 100), Frankfurt/fes 156
(Frankenallee 2), München/awm 96 (Francestr. 10, byte-for-byte the file that address's own download
produces). Worth re-running after any change to these files — the vendors move.

#### The house number is asked in the picker (2026-09-19)

Both address pickers (onboarding and the Abfall connect sheet) show a suggestion as two lines:
street and number, then postcode and town. A single line cut off before the town, and the town
is what tells two Hauptstraßen apart. **A street picked without a number is not an answer yet**:
the card keeps the street and opens a "Hausnummer" field under it (`HouseNumberField`, iOS's
numbers-and-punctuation keyboard so "12a" can be typed), and only the whole address goes to
`resolve`. On the server, `settleHouseNumber` in `abfall/resolve.ts` takes the entry that *is* the
typed number out of a vendor's house list (abfall.io, AbfallPlus, AWIDO, jumomind), or the only
entry of a one-entry list ("Alle Hausnummern"), and writes it into the config as the chip would
have. So the chip step now appears only where the number matches nothing or more than one entry.
Probe vendors (Heidelberg, Rostock, BEG, …) already used the number. A number the vendor rejects
sends the household back to the field, still filled in, with "Diese Hausnummer kennt die Müllabfuhr
nicht". Tested live: AbfallPlus on 4 streets with 27–199 numbers, AWIDO Waiblingen ("40 /2"),
Lienen, Rostock, Reutlingen, Heidelberg (12 → "Nr. 55, 2-36", the even side).

**Onboarding asks every waste question on its own stage, before the calendars.** After the pick,
the address step stays in its search layout (hero folded, card at the top) through the house-number
field, the lookup, and whatever the vendor still asks: the house off its list, where the typed number
did not settle it (`LocalCalendars.house`, whose rhythms are then asked again), and each bin's
rhythm. "Weiter" puts the answers away (`finishWasteQuestions`), and only then do the hero and the
Müllabfuhr/Ferien switches come back. Before this, onboarding had no house list at all: a
number that matched nothing was a dead end, and a street split into collection areas was connected
without asking.

The rhythm question draws the bin beside its name (`binIconFor` in `abfall_bins.dart`: bin, leaf,
stack of paper, recycling arrows, in the bin's colour), the way the cities' own forms do.

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
| `CALENDAR_SECRET_KEY` | `openssl rand -base64 32` — the active sealing key |
| `CALENDAR_SECRET_KEY_RETIRED` | optional, comma-separated: previously active keys, still used to *open* |
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
