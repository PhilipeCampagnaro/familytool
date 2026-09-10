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

A horizontal row of filter chips. The first chip is **"Alle"** — clears `calendarFilter` (`null`),
the default showing every calendar. Don't remove this default; a user who wants "everything"
shouldn't have to pick every source individually.

**"Alle" also carries the chevron, and its list is the only one that crosses accounts**
(`_AllCalendarsChip` → `_AllCalendarsPickerRoute`). Every other chip is one person, so a filter
built from the row was one person: two children at once, or a child's Klausurplan beside the
family calendar, could not be expressed and the only way to see both was to give up and show
everything. "Alle" is the chip that stands for nobody in particular, so the selection belonging to
nobody in particular hangs off it. The panel lists every calendar under its account's caption,
plus an "Alle" row at the top as the way back; `toggleCalendarAnywhere` adds to and removes from
whatever is showing rather than replacing it, which is exactly what an account's own popup must
not do. Ticking every calendar back on returns to `null` rather than to a hand-picked set holding
all of them today, so an account connected tomorrow joins it instead of arriving hidden.

A hand-picked selection wears `filterGroupId == kPickedCalendarFilterId`, which is no group's id:
it lights the "Alle" chip, and that chip **counts itself** (`L.s.calendarCount`) rather than
keeping the word "Alle" over three hidden calendars. The collapsed stand-in prints the same count
for the same reason — a set spanning two accounts has no one colour, so its single dot would claim
a filter on that one calendar.

**A chip is a *person*, not a calendar** (`CalendarGroup`, built by `state.activeGroups` from
`CalendarSource.groupId`/`groupName`, which `calendar-events` resolves from the calendar's owner).
One IServ account holding a child's Aufgaben, Klausurplan and Klassenkalender is a single "Alice"
chip, not three chips saying the same two words; a parent's work and private Google calendars are
one face rather than two rows. Everything the household shares, Ferien and Abfall included, sits
under the family chip.

`groupId` is `member:<uuid>`, `person:<name>` or `family`, and `CalendarGroup.isPerson` is the
first two. A group holding a single calendar is renamed after that calendar by `asSingle()` —
**except a person's**, who keeps their name however few calendars they own. Papa's iCloud is one
calendar and it is still Papa's; a chip reading "iCloud" under his photograph is the account
leaking back into a row that stopped being about accounts, and it is what a household sees
immediately after assigning that calendar to themselves, so the assignment reads as having done
nothing.

The owner is read from `calendars.owner_member_id` / `owner_label`, and the member's *name* comes
from `profiles` in a **second query**. `family_members.user_id` and `profiles.id` both reference
`auth.users` and have no foreign key between them, so a PostgREST embed cannot join them and fails
the whole select — quietly, since the client returns that error rather than raising it. When it
did, the roster came back empty, no `member:` calendar could be put a name to, and every one of
them fell back to the family chip. `HouseholdNotifier.load` splits the same read for the same
reason.

A chip that opens into a list draws a **chevron** and opens `_CalendarPickerRoute` — any group of
more than one calendar, plus **every person, even one holding a single calendar**
(`CalendarGroup.opensList`). A person's chip says the person, so on its own it never says which
calendar is behind the face, and a list of one is how you find out. Tap the chip to show the whole
account, tap it again or hit the chevron
for a list with a checkbox per calendar. The popup **stays open** while rows are ticked —
narrowing three calendars to two should be one gesture — so `_CalendarPickerSurface` is a
`ConsumerWidget` that re-reads the filter it is changing. Its dot goes hollow while only some of
the account is showing.

`calendarFilter` is therefore a `Set<String>?`, and null is still "Alle". The empty set **does**
occur — unticking the last row in either picker leaves it empty on purpose, since unticking a box
must never tick the others back on; the way out is the "Alle" chip, or the "Alle" row at the top of
the cross-account panel. Use
`state.calendarFilterKey` in a `ValueKey` — a `Set` is identity-compared, so the key would never
notice a filter change.

`_CalendarPickerRoute` borrows `_FilterMenuSurface`'s material rather than a `GlassSurface`, for
the reason recorded below: UIKit's own menus are a near-opaque vibrant material, and real glass
over the month grid let the day numbers read straight through the rows.

**Both** views show the chip row at rest and collapse it into the same compact glass dropdown
(`_CalendarFilterButton`, opening `_FilterMenuRoute`) as the header scrolls away — the dropdown
is *only* a collapsed-state stand-in, never shown alongside the chips. It lists the same accounts
and indents each one's calendars underneath, so the one place a single calendar can be picked
survives the header scrolling away. It's overlaid in
`_TitleRow` via a `Stack` (not a `Row` child) so it can't push the expanded left-aligned title
sideways, and fades in over the last 40% of the collapse (`_TitleRow._leadingOpacity`). Keep the
two views' behaviour identical here.

The menu panel (`_FilterMenuSurface`) is deliberately **not** a `GlassSurface` — UIKit's own
menus are a near-opaque vibrant material, not liquid glass, and a glass panel let the month grid
read straight through the rows.

## The to-do overlay ("To-dos" chip)

The last chip in the filter row lays the Board's dated to-dos over the agenda.
`CalendarScreenState.showTasks` + `CalendarNotifier.toggleTasks`; `_todosDueOn` in
`calendar_screen.dart` picks the rows, `_TodoAgendaRow`/`_TodoCard` in `week_view.dart` draw them,
and both views use them (the month view in its day detail box, `compact: true`).

**It is the one chip in that row that adds instead of narrowing**, so it sits behind a hairline
(`_ChipRowDivider`) at the end of the row and never touches `calendarFilter`. Don't fold it into
the filter: tapping a person hides the other people, and one chip in the row doing the opposite
without a mark to say so reads as a bug.

**It is deliberately not narrowed by the calendar filter either.** A calendar group is a person's
*calendars*; a to-do's `assignee_id` is who is meant to do it. Filtering to Papa and silently
dropping the to-do he is not assigned to would make the row mean something different depending on
which other chip is lit. Every to-do the reader may see is either shown or not.

**Only dated to-dos, only on their own day, and never a tracker.** The Board files an overdue row
under "Heute" because there a missed to-do is today's problem; a calendar cannot borrow that
without drawing last Tuesday on today *and* leaving Tuesday empty. A tracker has no due date at
all — `trackers` holds a rule, not a deadline — so there is no day to put one on.

A ticked to-do **stays on its day**, muted and struck through. That is also why the card does not
use `CheckOffRow`: that widget collapses the row away after the strike, which is right on the
Board (the row travels to "Erledigt") and wrong here. The strike is driven off `task.done` through
a `TweenAnimationBuilder` instead.

`_agendaEntries` puts the day in reading order as one heterogeneous list — a `CalendarEvent` or a
`BoardTask` per entry — in three bands: all-day events (context for the day, not appointments in
it), then to-dos with **no** hour, then everything with a clock time, events and to-dos merged. An
event wins a tie, because the agenda is a calendar first. The rail's line runs on through the whole
column, `isFirst` is simply the first entry, and the empty state waits for events *and* to-dos to be
empty.

An untimed to-do is owed by the end of the day rather than at a point in it, which is why it sits
above the clock instead of being given a slot. One that names an hour (`tasks.due_time`, optional —
see [backend.md](backend.md)) is sorted in at that hour and its rail prints the time instead of
"Fällig". Left in a block at the top, an 08:00 school run read as happening before the 07:30 train.

The card carries the Board's own 26pt `CheckOffButton`, which is both the thing that keeps it from
reading as an appointment and the one deliberate exception to "a card is one tap target" — a to-do
you can see and cannot tick sends the reader two tabs away to change one thing. Tapping the card
opens the Board's edit sheet **over Kalender** via `openTaskSheet(context, ref, task: …)`, so
closing it lands back on the day; it does not cross tabs.

**A day that still owes something wears a ring**, in the week strip and the month grid alike:
`EventDots.todo` draws an empty accent circle ahead of the colour dots, and `openTodoDaysProvider`
(beside `boardProvider`) is the shared set of `'y-m-d'` keys behind it. A ring rather than another
dot because every filled dot in that row is a *calendar* of that colour — a to-do drawn as one
would claim to be a calendar the household hasn't got. It is the unticked circle the agenda card
and the Board row already use, shrunk to the size of a dot.

Two rules on it. It shows **only while the chip is lit**, so it never points at something the day
would not show; and it counts **open** to-dos only, because the mark is a scan for what still needs
doing and a day whose to-dos are all ticked needs nothing. The finished row is still in the agenda
when the day is opened.

This is not the Board day-grid mistake CLAUDE.md warns about. That was about *counting* to-dos into
a strip that measures trackers, which made a one-off read as a habit. This says only that a day has
something on it, which is what every other mark in the grid says.

The detail box's header count stays `eventCount`, since it says "N Termine".

The toggle survives the header collapsing: `_FilterMenuSurface` carries the same row at the bottom,
behind the same rule, and it toggles in place rather than popping the route (`_FilterMenuRow.onTap`).

Session state, like `isWeek` and `calendarFilter` — nothing on this screen is persisted, and one
flag surviving a restart while the filter beside it did not would read as a bug.

## Header actions

The right of `_TitleRow` is a single `GlassIconGroup` (`glass.dart`) holding **two** segments:
"Kalender verbinden" (a link glyph, pushing `CalendarConnectionsPage`) and "neuer Termin" (the
plus). One capsule, iOS 26-style, not two glass buttons touching.

- Connecting belongs here rather than only in Einstellungen — it is Kalender's own job, and a
  household adding the school's ICS link should not walk through three screens for it. It rides
  *beside* the daily action instead of taking a button of its own, because it is a setup action
  done a handful of times ever.
- The connect segment deliberately does **not** use the empty state's `calendarPlus`: beside a
  bare plus, two plus-bearing glyphs read as two ways to add the same thing.
- `_TitleRow._actionsSlot` and `_collapsedSideInset` are sized off the group's width. Change the
  number of segments and both have to move, or the collapsed title stops being centered.

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
`showAppSheet(header:)` row — the word "Termin" small (`AppText.sheetTitle`) and centered, the
close button on the left and the accent pencil on the right, the same sides `_defaultHeader` puts
its close and save on — and the source/owner chips live in the body, over the first card. It was
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
grow past four dots' width however busy the day is. The to-do ring rides ahead of them and is not
part of that budget; see the to-do overlay section above.

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
menu drops towards the foot of the sheet, and a Flutter-painted menu inside a sheet carrying
native glass platform views composites into a layer iOS can drop; from the row it opens over the
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

## Lists and tasks hung off an appointment

The sheet's "Liste zum Termin erstellen" / "To-do zum Termin erstellen" rows now file the new
container against the event (`EventLink`, see [backend.md](backend.md)), and a `_LinkedCard` above
them shows what is already there. Before, the sheet offered to create the list it had just been
used to create, and the only place that knew about it was the Listen tab.

Three surfaces, one fact:

- **The agenda card** grows a chip per kind — the clipboard for lists, the panel for tasks — in the
  same row and the same shape as the homework badge, and for the same reason: a marker, not a
  button. Two chips rather than a summed count, because "2" over a clipboard means two lists.
- **The detail sheet** lists them by name, with each list's own symbol. Tapping one closes the
  sheet and leaves Kalender. Rendering the list's contents here instead would be a second, smaller
  Listen inside a calendar sheet with none of its gestures.
- **Board and Listen** carry the return chip (`EventLinkChip`) on the row's **subtitle line**,
  ahead of the count or the date already there — it says what the container is *for*, which is read
  before how it is going. **On a row it is a marker, not a button**, exactly like the homework
  badge: the row's own tap opens the task or the list, and a second target a few millimetres away
  in the same line turned that tap into a coin toss — people aiming at the list landed in Kalender.
  Give it an `onOpen` only where the chip is the only thing to tap: under the list's name in
  the opened list, and as a field row in the task's own sheet. **`onOpen` shows the appointment, it
  does not go to it** — `showLinkedEventSheet` stacks the event's own detail sheet over Board or
  Listen, so closing it lands back on the row it was opened from. Switching tab instead worked and
  lost people: the sheet closed onto a calendar nobody had asked for, two tabs from what they had
  been reading, which is why `TabJump` no longer names Kalender as a destination at all. The sheet
  is driven entirely by `openEvent`, so it needs nothing of Kalender to be on screen, and neither
  the selected day nor the calendar filter is touched. An appointment outside the loaded fortnight
  has nothing to show, so the chip stays a marker there rather than offering a dead tap.
  **Its label is never stored**: the appointment's name is read off the live
  event through `eventForLink`, so a renamed appointment renames every badge, and a link pointing
  outside the loaded fortnight shows the date instead.

Crossing tabs goes through `tabJumpProvider`: the shell switches tab, the destination screen opens
the thing. Arriving at Kalender selects the day, **widens the calendar filter if it would have
hidden the event**, and opens the sheet — an event outside the loaded fortnight selects the day and
stops there, which is everything the link knows.

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

**The detail sheet reads, the edit sheet writes, and each has its own buttons.** The detail sheet
ends at its last card: no action row, no pill. Its header carries the close on the left and an
accent-tinted pencil (`GlassConfirmButton`) on the right, and that pencil is the only way from
reading an appointment to changing one. It is absent when `CalendarSource.editable` is false —
Ferien, Abfall and read-only provider calendars are somebody else's to change, so the header is
then just a close button and a label.

"Löschen" lives at the **foot of the edit sheet** (`OutlinedSheetAction`, the same widget and the
same place as the task sheet's "To-do löschen"), not beside the pencil. One destructive control,
one sheet behind the deliberate act of opening the editor, and the sheet people open dozens of
times a week to read a time off has none.

`_confirmDeleteEvent` puts up the confirm dialog and takes an `onDeleted` callback that fires when
the removal *starts*, not when it lands — a sheet that waited for the provider would hang over a
row the calendar has already dropped. The edit sheet passes `Navigator.pop(true)`, and
`_openEditEventSheet` answers `true`, which is how the detail sheet underneath knows to close too
rather than sit there describing an event that is gone. Swiping an agenda card straight into the
edit sheet ignores that answer, since there is nothing behind it; the swipe's own trash action
passes no callback at all.

One form serves create and edit (`_EventFormBody`), and `event` is null only for a new one — which
is exactly what hides the delete row before the first save.

## Recurrence

**The form sets a rule; nothing ever reads one back.** Every provider hands Aporah *expanded
occurrences* — Google with `singleEvents=true`, Graph's `calendarView` by construction, CalDAV
through `parseIcs` — so the RRULE behind them never reaches the app. That single fact shapes the
whole feature:

- `EventDraft.repeat` (`EventRepeat`: never / daily / weekly / biweekly / monthly / yearly) plus
  `repeatUntil` are set in the repeat card, and go out under a `repeat` key on the wire.
  **`toWire` omits the key rather than sending a null**, because on an update a null would read as
  "stop repeating" and a missing key reads as "leave the rule alone" — which is the only thing the
  app is in a position to say.
- The rule carries **no day of its own**. iCalendar, Google and Graph all anchor a rule to its
  start, so "jeden Montag" is a Monday start plus `weekly`; there is no second control to leave
  contradicting the first, and the label is regenerated from `_draft.start` on every rebuild.
- Editing an occurrence of an existing series shows **no repeat picker at all** — there is nothing
  truthful to put in it. `CalendarEvent.seriesUid` (`repeats`) is all that survives the expansion,
  and the card asks the one answerable question instead: `EventScope.single` or
  `EventScope.series`. Changing how often something comes round means doing it in the calendar the
  appointment lives in.
- Deleting a repeating appointment asks the same question, as two destructive actions in
  `_confirmDeleteEvent` rather than one. **"Ganze Serie" is offered no undo**: `restoreEvent` writes
  one occurrence back out as a fresh appointment, which after a series delete would put a single
  Monday where a term of them used to be and call it restored.
- **A series cannot move to another calendar** and `saveEvent` says so. A move is a create on the
  far side and a delete on this one, and the create has no rule to carry — so "ganze Serie" plus a
  new calendar could only produce one appointment over there and an entire term deleted over here.
  Moving a single occurrence still works.

How the three providers take it, and why one of them needed surgery, is the recurrence part of
[backend.md](backend.md).

## "Heute" jump button (`_JumpToTodayButton`)

A liquid-glass capsule at the **right end of the nav bar's row**, the same height as the compacted
nav button at the left end, shown only when today isn't on screen. **The word only, no icon** —
it stands a finger's width from the bar's calendar icon, so a calendar glyph on it reads as a
duplicate of that icon rather than as a different offer. `_JumpToTodaySlot` places it
and is the only thing that moves: while the bar is expanded the button would be under it, so it
rides up to park above the bar (`navContentInset(context, pill: 106, gap: 36)`) and drops back
onto the bar's centre line (`navRowBottom`) as the bar collapses — on `kNavSwapDuration`, the
same clock the bar collapses on, so the two read as one movement. The horizontal position never
changes. Fades/slides via `AnimatedOpacity`/`AnimatedSlide`, wrapped in `IgnorePointer` while
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
