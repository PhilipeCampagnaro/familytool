# Kalender internals

Read this before changing calendar behavior. Files: `lib/screens/calendar_screen.dart`,
`lib/state/calendar_state.dart`, `lib/data/calendar_data.dart` — read all three together.

## Week view (`_WeekView` / `_WeekViewState`)

Scrolling day strip + selected day's agenda list.

- The strip is a **plain continuously-scrolling horizontal `ListView.builder`**
  (`calendarDayStripKey`). It used to page a whole week per swipe off a drag-velocity threshold,
  which the user disliked — **don't reintroduce week-at-a-time paging or snapping.**
- Cells are sized so exactly seven fill the usable width (a week still lines up) but the list
  runs to the right screen edge, unpadded, so days visibly continue off-screen.
- Finite-but-deep (`_stripDayCount` days centred on `_stripEpoch` = today − `_stripDaysBefore`)
  rather than a bidirectional `center:` sliver; days addressed by index via `_stripDate` /
  `_stripIndexOf`. `_stripItemExtent` is captured from the strip's `LayoutBuilder` and is what
  the offset↔index conversions depend on, so it must be set before `_revealDate` can work.
- `_revealDate` scrolls a day into view **only** when the selection changed from outside the
  strip (the "Heute" button) — never in reaction to the user's own scrolling.
- The month/year header (`monthLabel`) follows `_stripAnchor`, the leftmost visible day, *not*
  the selected day: on a freely-scrollable strip a header pinned to the selection would name a
  month that's nowhere on screen. Wrapped in an `AnimatedSwitcher` keyed on its own text so it
  crossfades as the visible month changes (same in the month view).
- "Heute" button visibility here tracks whether today is in the strip's visible range
  (`_todayVisible`), not whether the selected week contains it.

## Month view (`_MonthView` → `_MonthBlock` → `_MonthCell`)

Infinite bidirectional `CustomScrollView` anchored on the real "today" month via a `center`
sliver key, so scrolling never runs out in either direction. Tapping a day toggles an inline
expand/collapse detail card (`state.monthDetailExpanded`) showing that day's agenda, compact.

## Calendar filter chips

A horizontal row of per-source filter chips (`_CalendarChip`). The first chip is **"Alle"** —
clears `calendarFilter` (`null`), the default showing every calendar. Don't remove this default;
a user who wants "everything" shouldn't have to pick every source individually.

**Both** views show the chip row at rest and collapse it into the same compact glass dropdown
(`_CalendarFilterButton`, opening `_FilterMenuRoute`) as the header scrolls away — the dropdown
is *only* a collapsed-state stand-in, never shown alongside the chips. It's overlaid in
`_TitleRow` via a `Stack` (not a `Row` child) so it can't push the expanded left-aligned title
sideways, and fades in over the last 40% of the collapse (`_TitleRow._leadingOpacity`). Keep the
two views' behaviour identical here.

The menu panel (`_FilterMenuSurface`) is deliberately **not** a `GlassSurface` — UIKit's own
menus are a near-opaque vibrant material, not liquid glass, and a glass panel let the month grid
read straight through the rows.

## Collapsing headers

**Centered title.** In `_TitleRow` (both views) and in `_buildEventDetailHeader`, the title is a
full-width `Positioned.fill` layer in a `Stack` with the flanking buttons positioned over it —
*not* an `Expanded` sibling of them. As a Row child its centered state lands off-center by half
the button's width. Clearance from the buttons comes from horizontal padding that is **symmetric**;
an asymmetric inset silently reintroduces the same offset. The title is also painted **before**
any button: `GlassIconButton` is a native platform view on iOS, and Flutter content painted after
one lands in a composited overlay layer that can be dropped — invisible on device, fine in a
widget test, which is why no test catches it.

**A collapsing header needs a frosted background of its own.** `NestedScrollView` does *not* clip
its body to below a pinned header: the gray body keeps sliding up until its top reaches the top of
the screen, so a bare header has the agenda rendering sharply behind the title and glass buttons.
`_WeekViewState._buildHeader` lays a `FrostedHeaderBackground` (`lib/widgets/glass.dart`) in as a
`Positioned.fill` first layer of a `Stack`. A solid fill was tried first and the user asked for
see-through instead: content should still read as *there*, blurred, passing underneath. See
[design-system.md](design-system.md) for the two load-bearing details of that widget (progressive
blur, low tint alpha).

How far below the buttons the sharp gray starts is the header's collapsed height: a small gap
(`_WeekViewState._collapsedGap`) survives at t == 1 as a band of pure material. The month view's
header does *not* get this — it's a plain `Column` sibling above the grid, so nothing scrolls
under it.

**The event-detail sheet's header is deliberately not one of these.** It is a plain
`showAppSheet(header:)` row — the event's title small (`AppText.sheetTitle`) and centered, the
close button beside it — and the source/owner chips live in the body, over the first card. It was
a collapsing header with a 23pt title that shrank as the body scrolled, and that was wrong twice
over: a heading that size belongs to a screen, so over the first card of a sheet it read as a
second screen title; and its `FrostedHeaderBackground`, i.e. a `BackdropFilter`, under a native
glass button *inside a modal route* left the title and the chips not painting at all on device.
Don't reinstate it. `SheetCollapsingHeader` still exists for a sheet whose header is genuinely
more than a title, and its doc comment says the same.

## All-day events are dates, not instants

Every source writes an all-day event as **midnight UTC** — Google's `start.date`, OpenHolidays'
Ferien block, all six Abfall vendors, a DATE-valued `DTSTART` over CalDAV. `CalendarEvent._readAt`
therefore reads the UTC calendar date and rebuilds it as a *local* midnight; `_writeAt` is its
inverse for our own rows. **Don't `.toLocal()` an all-day timestamp.** East of UTC it shifts the
exclusive end onto the next day, `days` then lists that day too, and every waste pickup rendered on
its day *and* the day after — which is what "Abfall on the wrong dates" was. `durationLabel`
restates both ends in UTC for the same reason: a Ferien block spanning a clock change is 42 days
minus an hour, and `inDays` calls that 41.

## Day dots

`dayColors` returns **one dot per event**, not per calendar. It used to de-duplicate by
`calendarId`, so four appointments in one Google calendar drew a single dot and a full day read as
an empty one. Both cells (`_DayStripCell`, `_MonthCell`) `take(3)` and hand the remainder to
`EventDots.overflowCount`, which turns the fourth slot into a gray "+" badge — so the row can't
grow past four dots' width however busy the day is.

## The two day-off washes — Feiertag and Ferien

`DayHighlight` (in [day_circle.dart](../lib/widgets/day_circle.dart)) is the one enum behind both,
and `DaySelectorCircle` works the two shades out from the accent itself so the week strip and the
month grid can't drift apart:

| | fill | texture | source |
|---|---|---|---|
| **Feiertag** | `tint(accent, .86)` | diagonal hatch | computed, see below |
| **Ferien** | `tint(accent, .93)` | none | the subscribed Ferien feed |

Both mean "nobody has to be anywhere", but they are not the same size of fact — one day and rare
against six weeks in a row — so they don't get the same weight. Getting this wrong in *either*
direction has already happened once each: Ferien alone striped half of August and said nothing,
and dropping Ferien entirely lost the thing families actually plan around. Keep the texture on the
rare one. Where both are true (Karfreitag inside the Osterferien, the 25th inside the
Weihnachtsferien) the Feiertag wins — `_dayHighlight` in `month_view.dart` is the only place that
is decided, and `_DayStripCell` calls it too.

The Ferien side reads the **Ferien feed only** (`CalendarScreenState.isSchoolHoliday`,
`feedKind == 'ferien'`), via `eventsFor` so it follows the filter chips. It used to mean "all-day
event on a read-only calendar", which is equally true of every bin pickup and every subscribed
Google calendar — a household with Abfall connected saw a third of the month washed.

Each legend key appears only once its wash can: Feiertage need `germanHolidaysProvider.enabled`,
Ferien need `state.hasFerienFeed`. The legend is a `Wrap`, not a `Row` — three keys fit on one
line in German and don't in English. The Feiertag swatch is painted with the same
`DiagonalStripePainter` as the day circles, so it doesn't become the one place the two are
indistinguishable.

### Where the Feiertage come from

Not a feed. [lib/data/german_holidays.dart](../lib/data/german_holidays.dart)
computes them from the year and the Bundesland — nine nationwide plus the state-specific ones,
each either a fixed date or an offset from Easter Sunday (anonymous Gregorian algorithm). No feed,
no `public_feeds` row, no network, right offline. Only holidays statutory in a *whole* Bundesland
are in: Mariä Himmelfahrt in Bayern and Fronleichnam in parts of Sachsen/Thüringen are decided per
municipality, and Aporah only ever learns the state.

`germanHolidaysProvider` ([lib/state/holidays_state.dart](../lib/state/holidays_state.dart))
decides which set:

1. The **Ferien subscription's Bundesland** if there is one — `CalendarConnection.ferienBundesland`
   parses it out of the feed key (`ferien:NI`), and it is the only place the app has ever asked a
   household where it lives. Full state list.
2. Otherwise **German interface language** → the nine nationwide ones. Incomplete but never wrong.
3. Otherwise **nothing at all**, legend included. A Feiertag is a German fact; tinting the 3rd of
   October for a family in Dublin is noise. Device GPS and `families.address` are deliberately not
   consulted.

Nothing is behind a Feiertag on the wire, so the day-detail card (month) and the agenda (week)
print its name in a `_HolidayChip` above the events — otherwise a striped day is a texture the
family has to guess at. It sits *above* the timeline rather than in it: a Feiertag is a property
of the day, and an agenda row would give it a time it doesn't have and a swipe-to-edit it can't
honour. Ferien need no such chip — the feed's own all-day event is already in the list.

## Agenda cards

- **Every card is white** (`_EventCard`). The live event used to take an accent fill; since an
  all-day event is "live" for its whole span, a normal day read blue/white/blue. The rail beside
  the card already carries the phase (filled dot, accent line, accent time) — don't put it back on
  the card.
- No body text means **no subtitle line at all**. An empty `Text` still occupies a line, which is
  where the gap between a bare title and its chips came from.
- The rail is `_railWidth` wide with the time label in a `FittedBox(scaleDown)`. A clock time fits
  at full size; "Ganztägig" doesn't and used to wrap to two lines, which pushed that row's dot out
  of line with its neighbours'.
- **Weather sits where the avatar used to**, on the chip row: icon + temperature, and nothing at
  all when there is no forecast (a past event, one past the 16-day horizon, or a household with no
  address). The detail sheet shows the fuller card — icon, temperature, condition — beside the
  date, and the date card takes the full width when there is none. Both go through `_weatherFor`
  in [../lib/screens/calendar_screen.dart](../lib/screens/calendar_screen.dart), which keys the
  lookup on the event **and the selected day** — that second half matters, because an all-day
  event spanning a week is forecast per day. `_EventCard` itself stays a `StatelessWidget` and is
  handed the reading by `_EventAgendaRow`, which has the `ref`. The service behind it is described
  in the weather section of [ported-features.md](ported-features.md).

## The event sheet's location card

`_EventLocationCard` (`../lib/screens/calendar/event_detail_sheet.dart`) draws the place, a **real
map of it**, and the "Route" button. Three things about it are load-bearing:

- **The map is a MapKit still, rendered on the device** by `../lib/services/map_snapshot.dart` over
  the `aporah/map` channel — CoreLocation geocodes the event's free text, MapKit renders the image,
  and it is cached per (place, width, theme). No key, no tile server, and no family's address
  leaving the phone. It follows the app's own light/dark setting, not the system's.
- **The request needs the card's width, so it is started from a `LayoutBuilder`, not `initState`** —
  legal only because nothing is set synchronously: the `await` in `_load` puts its `setState` after
  the frame. Don't "tidy" that into a synchronous call.
- **A place that can't be found gets no map at all**, and an event with no location gets no card
  at all. The row stays tappable either way, and the navigation app is handed the words instead of
  a point — Waze and Google Maps both search on it.

"Route" (and a tap on the row) opens the standard `showAnchoredMenu` with two items, **Waze and
Google Maps** — both anchored to the **address row**, never to the "Route" pill. From the pill the
menu drops straight into the sheet's action row, and "Bearbeiten" and the trash button are native
glass platform views that composite over anything Flutter paints; from the row it opens over the
map, which is ours. `openNavigation` (`../lib/services/external_links.dart`) tries the app's URL scheme
first and falls back to its website, which is why this needs no `LSApplicationQueriesSchemes` entry:
`UIApplication.open` reports whether anything claimed the scheme. The two labels are brand names and
are deliberately **not** in `lib/l10n/`.

## The detail sheet shows what the event has, and nothing else

The body is a `CrossAxisAlignment.stretch` column — under `start` each card is only as wide as its
own content, which is invisible while the cards hold full-width rows and then ships the notes card
as a stub beside them.

**No location, no location card** — an address row over a map of nowhere is worse than nothing.
**Notes are the opposite and show empty on purpose**, with the form's own "Notizen hinzufügen" as
the placeholder line: every event has that card, so the sheet keeps one shape and "nothing written
here" is readable off it. The two rules differ because the cards do — one is a thing the event
either has or hasn't, the other is a field you fill in.

The **Erinnerung card is gone entirely**, on the user's call. `CalendarEvent.reminder` is
real — it comes from `reminder_minutes` on the row — but nothing in the app writes that column yet
(the editor is title-only), so in practice every event showed a bell over a blank line. Bring the
card back when something sets a reminder, and give it the same empty rule as the rest.

## The event form's "Ort" field searches, and its calendar is a card

Two things in `lib/screens/calendar/event_form.dart` that used to be neither:

**`_LocationField` completes what is typed, using the device.** `searchPlaces` in
`lib/services/map_snapshot.dart` rides the existing `aporah/map` channel — `MKLocalSearchCompleter`
on the Swift side, so it answers with **points of interest as well as addresses**. That is the
point: an appointment is at Rossmann or at the Zahnarzt far more often than it is at a street the
family types out, and the geocoder behind the detail sheet's map can't find either from a shop
name alone. Results are biased to the household's town (`families.address`, **never device GPS** —
the same rule the weather follows), debounced 250 ms, and only asked for from three characters.
Picking one writes `"Name, Straße, PLZ Ort"` into the field, which is what the map snapshot and the
route menu will later be handed. **Free text still wins**: nothing forces a choice, so "Turnhalle"
is typed and saved exactly as before, and off iOS (no handler) the field is the plain field it
always was.

**The destination is a card of every writable calendar, not a row that opens a second sheet.** And
**"Aporah" is not one of them** — the app has no calendar of its own at any level. `writableCalendars`
returns the household's connected calendars and nothing else, `defaultTarget` is nullable and simply
takes the first of them, and the whole own-calendar path is gone: no `_own()` read, no
`ownCalendar()`, no `isOwn`, no `createEvent`/`updateEvent`/`deleteEvent` on the repository, and
`provider = 'aporah'` is rejected by a check constraint (migration
`20260805182949_drop_own_calendar.sql`). A household with no writable calendar sees
`L.s.noWritableCalendar` in the card and is pointed at the connections page.

Don't restore it. A destination that only Aporah can see sits in the picker looking exactly like
iCloud and Google and then fails to do the one thing the family connected an account for — put the
appointment on their own phones.

## Empty day

`_EmptyDayActions` (shared by both views) offers **"Kalender verbinden"** instead of "Termin
hinzufügen" when the household has no calendars at all (`state.calendars.isNotEmpty` is false —
every calendar comes from a connection or a feed, so that is the same question as being connected),
pushing `CalendarConnectionsPage` directly. Somebody who skipped onboarding lands on Kalender first
and otherwise has nowhere to put an event. Guarded on `state.loaded` so the button doesn't flip a
moment after paint.

## Events + persistence

`CalendarScreenState.eventsFor(y, m, d)` merges three layers: seed `schedule` from
`data/calendar_data.dart` (matched to a day only by which source-color dot that day has — a
mock-data shortcut, not a real per-day store), user-`added` events, minus `deletedKeys`, with
`edits` overlaid on top. Each event has a stable `id` (seed: `seed-*`; user-added:
`user-<timestamp>`). Edits/deletes are keyed by `"$y-$m-$d::$id"`
(`CalendarScreenState.instanceKey`) since an event is always opened in the context of
`state.selected`. `CalendarNotifier` persists `added`/`edits`/`deletedKeys` to
`shared_preferences` as JSON (`CalendarEvent.toJson`/`.fromJson`) on every mutation and loads
them back on startup — the "local storage now, Supabase later" layer.

## Real-time timeline

The agenda's left-hand rail (time / dot / connecting line, in `_EventAgendaRow`) is driven by
`phaseFor(y, m, d, start, end, now)` (`lib/data/calendar_data.dart`), which compares against the
*actual* wall clock — not the static mock `CalendarEvent.phase` field (still on the model/seed
data but no longer read by the UI). `CalendarNotifier` ticks `state.now` every 30s via an
internal `Timer.periodic` so the rail advances (done → live → upcoming) on its own. Because of
this, a day that hasn't happened yet in real time always renders fully unfilled, even if the mock
seed data hardcodes it as "done"/"now".

Note the split: mock "today" is pinned to **2026-08-13** (`calTodayY/M/D`) and is for
"is this today" badges/highlighting only — never reuse it for time-sensitive logic.

## Edit / delete

The event-detail sheet's "Bearbeiten" button opens a small title-only edit sheet
(`_openEditEventSheet`, reuses `showAppSheet`) → `updateOpenEventTitle`. The trash button shows a
confirm dialog (`_confirmDeleteEvent`) → `deleteOpenEvent`. Both only support editing/deleting
**title**, matching the "Neuer Termin" form's current scope — that form's location / time /
reminder / notes fields are still static placeholders, not wired to state. If you wire those up
for creation, extend edit to match at the same time so the two don't drift.

## "Heute" jump button (`_JumpToTodayButton`)

A small floating liquid-glass pill centered above the bottom nav (`bottom: 106` = the nav's
`bottom: 22` + 70px height + a 14px gap), shown only when mock today (`calTodayY/M/D`) isn't on
screen. Fades/slides via `AnimatedOpacity`/`AnimatedSlide`, wrapped in `IgnorePointer` while
hidden. Condition differs per view:

- **Week view**: purely derived from `state.selected` each build — visible whenever the selected
  day's week doesn't contain today; no scroll tracking needed.
- **Month view** (`_MonthViewState`): tracks real scroll position. A `GlobalKey` is attached to
  the `_MonthCell` matching today (only in the `monthOffset == 0` block, via `todayCellKey`
  threaded through `_MonthBlock`); a second `GlobalKey` marks the scroll viewport. On every
  `ScrollController` listener tick the check is deferred one frame via
  `WidgetsBinding.instance.addPostFrameCallback` — the listener fires the instant `.offset`
  changes, *before* that frame's layout/paint runs, so reading render-box positions immediately
  would see stale (pre-scroll) geometry. Then visibility comes from comparing the today-cell's
  `RenderBox` position (`localToGlobal(ancestor: viewportBox)`) against the viewport's bounds.
  Tapping calls `selectDay(calTodayY, calTodayM, calTodayD)` plus
  `_scrollController.animateTo(0, ...)`.
