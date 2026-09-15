# Kalender internals

Read this before changing calendar behavior. Files: `lib/screens/calendar_screen.dart`,
`lib/state/calendar_state.dart`, `lib/data/calendar_data.dart` — read all three together.

## The two views are two tabs

**The week view is the Home tab and the month grid is the Kalender tab**, and there is no toggle
between them any more. They were one screen wearing two faces behind a segmented control in the
month/year row; the face a household wants nearly every time it opens the app — today, its
appointments, its to-dos — was the one hidden behind a control that had to be found and
remembered. `CalendarScreenState.isWeek`, `setWeekView` and `setMonthView` are gone with it, and so
is `_ViewToggleButton`.

Both still live in this library and both still read `calendarProvider` whole, so the filter chips,
the selected day and the to-do overlay are **one piece of state across two tabs**: narrowing to one
person on Home narrows the month grid too. That is deliberate — a filter that meant two different
things on two screens showing the same calendars is the thing worth avoiding.

`StartScreen` mounts `CalendarWeekScreen`, the one public entry point, and fills its **four slots**
— `trailing`, `label`, `underLabel` (with the height it needs) and `belowDay`. They are slots rather
than content so that everything Home knows about lives in `lib/screens/home/` and this library never
learns what a tracker or a shopping list is; what it owns is the *shape*. See "Home's four slots"
below. `_MonthYearRow` keeps the row
above the chips at a fixed 40 so both views' `_extraHeaderHeight` arithmetic still holds and the
label doesn't sit at two different heights on two tabs — which is also what made Home's island free,
since a glyph beside a heading fits the old toggle's slot with room to spare. That row's label is
given the full width (`Expanded`, with the switcher's own `layoutBuilder` aligned left) rather than
left to measure itself against infinity, or the island could not ellipsise an appointment's title.

Three more things differ per tab, all of them parameters rather than a flag on the state:

- **The title.** `_TitleRow.title` — "Kalender" over the grid, the Home tab's name over the week.
- **The header's right-hand slot.** `_TitleRow.trailing` + `trailingWidth`, and it holds a
  different thing on each: Kalender's `_CalendarHeaderActions` capsule (100 wide), Home's profile
  avatar (52). Home carries **no header actions at all** — "Kalender verbinden" is a setup action
  done a handful of times ever and does not belong in the header. Adding an appointment from Home
  is a glass '+' in the day card's top-right corner (`_DayBody`), opening Kalender's own create
  sheet dated to the selected day, so nobody has to leave Home to add one. It hangs on `_DayBody`
  rather than in `_DayAgenda`'s title row because the day is an `AnimatedSwitcher` child that slides
  on every change of day, and a platform view smears under a Flutter transform; the title leaves
  `_DayBody.headingTrailingInset` clear for it. Kalender's day card closes with the same 32pt glass
  control, an X. `_trailingSlot` is what the title clears at rest and is zero when the slot is
  empty, while `_collapsedSideInset` stays 108 on both tabs — at t == 1 what matters is that the
  two sides match, not that they are tight. Unlike `leading`, the slot is filled at every stage of
  the collapse, which is what keeps the one way into Settings on screen while the header is
  scrolled away.
- **The label above the chips.** `_MonthYearRow` takes a **widget**, not a string, because the two
  tabs put different kinds of thing there: Kalender the visible month, crossfaded as that month
  changes; Home its status island (`DayIsland`). A grid of numbered squares needs telling which
  month it is; a day strip is already a row of dates. The `_stripAnchor` that used to drive that
  label — the leftmost visible day, deliberately not the selected one — is gone with it, and the
  strip's scroll position now feeds only `_todayVisible`. **A household scrolling the strip weeks
  out therefore has no month named anywhere on Home**; that was the trade. The crossfade is keyed
  on whatever widget it is handed, so **every caller must put a `Key` on its child** or the row
  swaps contents without animating.

`CalendarWeekScreen` is a wrapper rather than its own screen because everything the week view draws
— the strip cells, the agenda rows, the chips, the event sheet — is a `part` of this library, and
moving one out to be importable would drag the rest with it.

**Only Kalender compacts the nav bar** (`_compactingTabs` in `main.dart`) — Home did too, and stopped
once it held too little to scroll for a collapse to buy any room. The calendar's
write-error listener now sits on `AppShell`: two always-mounted screens each running the same
`ref.listen` would have shown every failed write twice.

## Week view (`_WeekView` / `_WeekViewState`) — the Home tab

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
  strip (the "Heute" button, and the first layout) — never in reaction to the user's own scrolling.
  **It lands the day leftmost**, so today is the first cell and the six beside it are the days
  still to come. It used to land third-from-left for context on both sides, which spent two of
  seven cells on days that had already happened.
- **A cell is the forecast, loose above, then the rounded tile holding the weekday letter, the day
  number and the dots.** `_DayStripCell` carries the whole arithmetic as a comment; the bands
  (`_weatherBand`, `_letterBand`, `_dotBand`) are fixed heights reserved whether or not there is
  anything to put in them, because a strip whose cells changed height as the 16-day forecast
  horizon ran out would ripple every time it was scrolled.
- **The forecast and the weekday letter swapped places, and that swap is why the icon is legible.**
  A Meteocon is a full-colour drawing with soft edges and several are pale — an overcast cloud, a
  snow cloud — so on a near-white tile they stop reading long before they stop being drawn: at 20,
  and worse at 16, they are smudges. A cell is a seventh of the screen, about 45 points, so an icon
  *beside* a two-digit temperature can never exceed 24. Stacked it is bounded by height instead,
  and height outside the tile costs the tile nothing. The letter is one glyph and fits the narrow
  band the forecast left. The dots stay with the number: they are what is *in* the day, where the
  forecast is about the day as a whole.
- **`_weatherBand` is the sum of `_weatherIcon` and `_weatherTemp`, and `_DayWeather` puts the
  temperature in a box of exactly `_weatherTemp`** rather than letting its column size itself.
  `AppText.microLabel` sets no `height`, so its line box is whatever Poppins' metrics make it —
  about 16 at 11.5pt — and a band guessed at the sum of two natural heights overflowed by two
  pixels on every visible cell at once. Any new content in a band gets a slot in the same sum.
- That reading is **the day's weather at home** (`WeatherState.daily` / `forDay`), not any
  appointment's. A cell has to answer on a day with nothing planned, which is most of them. The
  agenda rows underneath still carry each appointment's own reading at its own hour in its own
  town, and the two disagreeing is correct. See the weather section of
  [ported-features.md](ported-features.md).
- **A day with no forecast draws a dash, not a skeleton.** There is no reading past the 16-day
  horizon, on a past day, or in a household with no address, and on a strip four years deep that is
  nearly every cell. A skeleton promises something is on its way; on a day in 2029 nothing is, and
  seven shimmering blocks across the top of Home would be the app claiming to load for ever on the
  one piece of chrome always in front of the reader. `_DayWeather` draws a 10 × 2 bar in
  `AppColors.mutedLight` instead — a table's convention for a cell with no value — which also
  covers the past and the no-address cases without a second treatment.
- The month/year label the strip used to carry is gone — see the island above — and `_stripAnchor`,
  the leftmost-visible-day tracker that fed it, went with it. The strip's scroll position now
  drives only `_todayVisible`.
- **The body is one scroll, and the day card ends.** The agenda used to be its own scroller filling
  the viewport under a gray panel that never moved, which is precisely why nothing could sit below
  it. `_AgendaGrayBody` is now a row in a `ListView` with a radius on *all four* corners, sized to
  the day by `_DayAgenda`, with `belowDay` under it. It stays a `NestedScrollView`
  on purpose: its body is laid out at the viewport's full height, so there is always enough travel
  to collapse the header even on a day with one appointment. A plain `CustomScrollView` would leave
  the header stuck open whenever the content was shorter than the display.
- `_DayAgenda` **grows with the day and folds at `_maxEntries` (8)**. A cap is not the instinct to
  reach for here — this screen exists so you can open the app and see everything happening today —
  so the number is high enough that no real family day reaches it, and exists only so a badly
  connected calendar cannot push the sections a thousand points down the page. Past it the rest
  unfolds in place; there is nowhere else to send anybody, because this *is* the day view. The fold
  resets with the day, because the `AnimatedSwitcher` key already changes.
- "Heute" button visibility here tracks whether today is in the strip's visible range
  (`_todayVisible`), not whether the selected week contains it.

## Home's four slots

Files: `lib/screens/home/day_island.dart`, `first_steps.dart`, `home_sections.dart`, and
`lib/screens/start_screen.dart`, which is the assembly and nothing else.

**The divider under the day is a boundary in meaning, not only in paint.** Home's grey (`_DayBody`)
runs from the day down to the bottom of the screen, rounded only at the top, and `belowDay` sits
inside it under a hairline divider, inset 14/16 like the day itself so the section headings and cards
share the calendar's margins. Above the divider is whichever date the strip is on. Below it is the
household as it stands right now. Tap a Thursday three weeks out and the top changes while the bottom
does not — which is correct, and only readable because the day visibly ends there. So **nothing in `belowDay` may be day-scoped**: an open to-do is open whatever
date is selected, a tracker is owed today, a shopping list has no date at all. A "tomorrow" block
would read as belonging to the strip and be wrong on every day but one.

`DayIsland` — the `label` slot. It says **one** thing and always the most pressing thing about
today. **It is a heading with a glyph, not a badge**: the filter chips directly beneath it are
already a row of tinted capsules, and a capsule above them left three stacked badges with no
hierarchy between them. The glyph carries the tone and the words stay in ink — a red sentence among
black headings shouts across the page for what is one overdue to-do — and the glyph always names
what the line is about (a clock for the next appointment, a warning for something overdue, and
footprints for the first steps), never that the app is being clever. **It is ink wherever the colour
would not mean anything** — the accent on five of seven states put a blue mark above a row of blue
chips saying nothing the words were not; what is left in colour is the pair that is about the
household rather than the app, red for overdue and green for a day that is finished. Same reasoning
inside the checklist, where five accent glyphs read as five things wanting attention rather than one
list. **Under the sentence is a
second line naming what it counts** (`homeHint*`): "Noch 1 offen" is a number and an adjective, and
the island is the one place in the app with no row, no section heading and no list around the count
to say which of four kinds of thing it means. That line is what makes the row 48 rather than the 40
a month name takes — `_MonthYearRow.monthHeight` is now a default, and `_WeekView._labelHeight`
pays the eight points in its own `_extraHeaderHeight`.

**The line, its crossfade and its sweep now live in `lib/widgets/status_island.dart`**, lifted out
of here the moment Ausgaben wanted the same thing about money; `DayIsland` is the ladder and nothing
else. What follows is why that widget is shaped the way it is.

**The island runs its own `AnimatedSwitcher`, and it has to.** `_MonthYearRow` has one, but it
compares the widget it is handed — always a keyless `DayIsland` — so it never saw one state become
another and every change to the sentence landed as an instant swap; the keys are a level down, on
what `DayIsland` builds. Its two halves deliberately **do not overlap** (interval curves, old out in
the first half, new in over the second): two different sentences crossfading at the same left edge
are two sentences printed over each other. `_Sweep` then runs one pale wave across the words, once.
The sentence changes while nobody is watching — a to-do is ticked on another phone and the words are
simply different next time — and the wave is what says *this changed* without the header moving. It
is the page's own colour rather than white, so the letters dissolve towards the paper behind them
and the dark palette gets the same effect instead of a flashbulb; `BlendMode.srcATop` keeps it
inside the glyphs; and the `ShaderMask` is dropped the moment the wave finishes rather than leaving
a save-layer under the header all day. A row of counters would be a dashboard, and the four other tabs already are one; what
somebody wants from the top of Home is the sentence they would otherwise go looking for. The cases
are a ladder, first match wins: **still loading**, setup, overdue, open today, unticked trackers,
the next appointment, then "alles erledigt". The first rung is the only one about the app rather
than the household, and it is why the island now visibly resolves into what it says: everything
under it reads state that arrives over the network, and printing "Dein Tag" and quietly replacing it
a second later is a change nobody ever sees happen. It is also the one place a brain glyph belongs,
and the one state whose wave repeats — there the sweep *is* the spinner. **The ladder is about today and only today** — a count of what is overdue *now* printed above next
Thursday's agenda is a sentence about a different screen. Selecting another day drops all of it, but
it does **not** fall back to the generic "Dein Tag". **Nor does it name the date and count the
appointments any more**: the day card now carries that as its own title (`_DayAgenda`, the same
`_dayHeading` + `eventCount` Kalender's day box prints, the count hidden at zero), and the island
saying it too put one sentence twice a few centimetres apart. What the island says instead is the one
thing the card cannot — how far the day is from today (`homeDayOffset`: "Morgen", "In 3 Tagen",
"Vor 2 Tagen") — and a tap on it selects today, which the week view scrolls the strip back to. That
line carries no wave
(`_SweepMode.none`) and one stable key: the reader tapped the day themselves, so nothing changed on
its own, and a 400ms swap plus a shimmer on every tap along the strip would be noise. "Next up" is deliberately not tappable: the appointment is the
first card four centimetres below, and a second route to the same sheet from the same screen is a
coin toss rather than a shortcut. It reads `DateTime.now()` with no ticker of its own, so the line
settles on the next rebuild rather than driving a clock in the header.

`FirstStepsCard` — the `underLabel` slot, between the island and the chips, **inside the collapsing
header**. It opens in place and pushes the day down; the header's extent grows by exactly its
height. Two earlier shapes were wrong: a card in the scroll body put the chips and the entire day
strip between the chevron and what the chevron opened, and a floating `CompositedTransformFollower`
panel sat in the right place but hovered over the day instead of belonging to the header its control
is in.

**Its height is arithmetic, not a measurement** (`firstStepsPanelHeight`, over a fixed
`firstStepRowHeight`). A `SliverPersistentHeader` is laid out against one extent, so the header has
to know the panel's height before the panel is built; a child that sized itself would be a frame
ahead of the header containing it and the chips would jump. `StartScreen` computes it,
`CalendarWeekScreen` passes it as `underLabelHeight`, and `_WeekView` animates its own controller
between 0 and that number so the extent and the space the panel occupies are the same number on the
same frame. The panel is `null` while shut rather than zero-height, or the rows would lay themselves
out against a tight zero and overflow. `firstStepsOpenProvider` holds the flag because three widgets
need it and none contains the others. Setup outranks every status the ladder could print, since a
household with no calendar connected has nothing true to say about its day.

**Every step is derived from live state and none of it is stored.** A stored checkbox drifts the
moment somebody deletes their only list, does not travel to the other parent's phone, and needs a
column, a migration and a policy of its own; asking the providers costs nothing, since the screen
watches all five anyway, and answers correctly on a second device and for the household that set
everything up before the card existed. **The family step is done when the invitation is sent**, not
when it is accepted (`members.length > 1 || invites.isNotEmpty`): a household that has just invited
somebody has done everything this list can ask of them, and a row still standing there reads as the
invitation having failed. `invites` being admin-only costs nothing, since only an admin can invite.
`firstStepsProvider` returns the **remaining** steps and is empty while `familyProvider` and
`calendarProvider` are still loading, so an established family never sees a checklist flash up
telling them to connect the calendar they already have.

There is **no address step**, even though the address is what Abfall, Ferien and the weather all
hang off: `FamilyNotifier.saveAddress` has exactly one caller, in onboarding, so the step would have
nowhere to send anybody. Connecting Abfall asks for the address on the way, which is the door that
does exist. Two steps (tracker, list) can only offer a tab, because neither create flow has a public
door the way `openTaskSheet` does, and inventing one would mean a second entrance to keep in step
with the first.

`HomeSections` — the `belowDay` slot: **Heute dran** and **Listen**, each hidden entirely when it
has nothing. **There is no open-to-do section.** There was one (**Offen**, four rows, oldest
deadline first), and it went because the week view above already draws every to-do on its due day —
a second card of them was the strip repeated in another shape. Tracker rows keep their circle
because a tracker you have to navigate to in order to tick is a tracker that stops being ticked, and
ticked ones stay on the card rather than emptying it as the day goes on. Beside each tracker's name —
on the same line, where it reads as the answer to the name rather than as a second fact about it —
is `TrackerWeekStrip` ([lib/screens/board/tracker_chart.dart](../lib/screens/board/tracker_chart.dart), the same
widget the Board's tracker card draws beside each name), **the last seven days and nothing more** — as much history as a summary row can
carry and still be glanced at, and the span somebody actually asks about; the months of record live
on the tracker's own screen where the chart is tall enough to read. Its three marks are the detail
chart's colour for colour, so a day the rhythm never named stays neutral rather than pale-missed (a
Mo/Do tracker would otherwise report five failures a week of a perfect record), and days before the
tracker existed leave their space empty so the squares beside them don't shift. It is not tappable:
the row's circle already ticks today, back-filling is the detail chart's job, and a 9-point square
on a summary row is a mis-tap waiting to write a day nobody meant. Lists show counts, not
articles.

**Boxen is deliberately absent.** A box answers "where did we put the winter coats", which is a
question you already know you have when you go looking. It would be on Home because it is a tab, and
that is not a reason.

`TabJumpNotifier.toTab` exists for the section headers — a jump with no payload, which the shell
clears itself since no destination screen's listener will.

## Month view (`_MonthView` → `_MonthBlock` → `_MonthCell`) — the Kalender tab

Infinite bidirectional `CustomScrollView` anchored on the real "today" month via a `center`
sliver key, so scrolling never runs out in either direction. Tapping a day toggles an inline
expand/collapse detail card (`state.monthDetailExpanded`) showing that day's agenda, compact.

**The card opens below the whole month, so opening it can lift the grid** (`_MonthViewState._selectDay`).
A day in the last week of a month near the bottom of the display opened its card entirely off
screen, and the tap looked like it did nothing. When the card's top would land below 55% of the
viewport, the grid scrolls it up to about 40% — never further than keeps the tapped day on screen,
and never down. If another month's card was open, the scroll waits for it to close first, because a
closing card above pulls this one up as it goes.

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

**A chip shows its own calendars and nothing else.** `filterToGroup` used to union a person's chip
with the family group, so that a shared dentist appointment stayed on Alice's Thursday. It is gone:
the extras were invisible (her popup lists only her calendars, so they could be neither seen nor
unticked there), unticking one of her own calendars silently dropped them again, and "family" is
also where an **unassigned** calendar lands — so the union quietly pulled in every calendar nobody
had got round to assigning. A filter showing more than it was asked for reads as broken however
good the reason. Alice *plus* the family is still expressible in the one place that means it: the
"Alle" chip's cross-account picker.

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

`_CalendarPickerRoute` and `_AllCalendarsPickerRoute` use a near-opaque material rather than a
`GlassSurface`: UIKit's own menus are a near-opaque vibrant material, not liquid glass, and real
glass over the month grid let the day numbers read straight through the rows.

**Both** tabs show the chip row at rest and collapse it into the same compact glass dropdown
(`_CalendarFilterButton`) as the header scrolls away — the dropdown is *only* a collapsed-state
stand-in, never shown alongside the chips. It's overlaid in `_TitleRow` via a `Stack` (not a `Row`
child) so it can't push the expanded left-aligned title sideways, and fades in over the last 40% of
the collapse (`_TitleRow._leadingOpacity`). Keep the two tabs' behaviour identical here. Its label
("Alle", "3 Kalender") is set in `AppText.rowTitle`, the Heute pill's type, so the two floating
glass controls on the screen read at one size.

**Its menu is multi-select, and is the "Alle" chip's own list plus the to-do row.** It used to
*replace* the filter with one row's worth and close, which made the only control left once the
header had collapsed a single-choice picker standing in for a row of chips that can build any set.
Every row now keeps the menu open and toggles (`toggleCalendarAnywhere`, `clearCalendarFilter`,
`toggleTasks`) and pushes the whole tick set back with `updateNativeMenuSelection`, because one tick
can move the others. On iOS 17.4+ that is UIKit's menu (`showNativeMenu`, `keepsOpen` →
`.keepsMenuPresented`), each account a titled section with its calendars as coloured dots; everywhere
else it is `_AllCalendarsPickerRoute` with `onToggleTasks` set, which adds the to-do row on top.

## The to-do overlay ("To-dos" chip)

The last chip in the filter row lays the Board's dated to-dos over the agenda.
`CalendarScreenState.showTasks` + `CalendarNotifier.toggleTasks`; `_todosDueOn` in
`calendar_screen.dart` picks the rows, `_TodoBlock` in `day_timeline.dart` draws them, and both
views use them (the month view in its day detail box, `compact: true`).

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

A ticked to-do **stays on its day**, muted and struck through. That is also why the block does not
use `CheckOffRow`: that widget collapses the row away after the strike, which is right on the
Board (the row travels to "Erledigt") and wrong here. The strike is driven off `task.done` through
a `TweenAnimationBuilder` instead.

An untimed to-do is owed by the end of the day rather than at a point in it, which is why it sits
in the band above the clock rather than being given an hour on the grid. One that names an hour
(`tasks.due_time`, optional — see [backend.md](backend.md)) stands at that hour among the
appointments and takes part in the same column layout. Left in a block at the top, an 08:00 school
run read as happening before the 07:30 train. See the day-view section above for how the two are
drawn apart.

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

The toggle survives the header collapsing: the collapsed dropdown carries the same row at the top,
behind a rule, and it toggles in place like every other row there.
The system menu keeps that promise with `keepsOpen` — see above.

Session state, like `calendarFilter` — nothing on this screen is persisted, and one flag surviving
a restart while the filter beside it did not would read as a bug.

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

## The day view — a time grid

**The day is a clock, not a list.** It was a rail of rounded cards in reading
order, which said what was on but never what the day *looked* like: a morning
packed solid and a free afternoon drew as six identical rows. It is now the grid
every calendar the household already uses has — Apple's, Google's, Outlook's,
Teams'. `calendar/day_timeline.dart` holds all of it; the rail, the agenda cards
and the carousel that briefly replaced them are gone.

- **`_dayPlan` splits the day into three piles** (`calendar_screen.dart`):
  `allDay`, `untimedTodos`, and `timed` as `_TimedEntry`s. What sits on the clock
  goes on the clock; what is true of the day as a whole goes in `_DayBand` above
  it. Giving an all-day event or an undated to-do a position on a time grid would
  be inventing one — which is what the old rail did when it printed "Ganztägig"
  where a clock time belonged.
- **Every timed entry is clipped to the day being drawn.** A 22:00–07:00 shift is
  one provider row across two dates; `event.days` puts it on both and the clip is
  what stops it running off the bottom of the first and never appearing on the
  second. `_TimedEntry` carries minutes from that day's midnight, not `DateTime`s,
  because every question the layout asks is "does this overlap that".
- **`_placeBlocks` is the overlap layout, and it has three steps** — the third is
  the one people leave out:
  1. **Collision groups** in start order, closing when an entry begins after the
     group's furthest end. Two groups never interact, so a quiet afternoon is not
     made narrow by a crowded morning.
  2. **Greedy columns** inside a group: first column whose last entry has
     finished, else a new one. Entries are in start order, so a column's last
     entry is always its latest-ending one and the check is exact.
  3. **Spread right** into every column to the right that holds nothing
     overlapping. Without it the layout is correct and unreadable — an 11:00
     half-hour meeting would be a third of the width because the 08:45 pile-up
     needed three columns.

  Deliberately **not** Apple's own behaviour, which is undocumented and which its
  own users describe as arbitrary. This is the deterministic version Google
  Calendar, Outlook and Teams draw: no two blocks ever cover each other, and the
  same day always lays out the same way.
- **The day stands on a dot lattice, not on rules** (`_DotCanvas`). A full-width
  hairline every hour drew twelve horizontal lines across the day and each one
  asked to be read; the appointments then competed with the paper they were
  printed on. A dot grid is what every tool that puts objects on a plane uses —
  Figma, Power Automate, n8n — precisely because it says "this is a surface with
  a scale" and then gets out of the way. It is still a *calendar's* lattice: the
  rows land on the quarter hour (`_rowsPerHour`) and the hour's own row is drawn
  at full strength while the three between it are faded, so the hour is findable
  without a line being drawn through the day to find it. The lattice is square —
  columns at the same step as rows — which is what keeps it reading as a canvas
  rather than as a dashed rule. It runs the **whole grey card**, under the hour
  labels, under the heading and under the all-day band as much as under the
  blocks — stopping it where the blocks start drew a second left edge a finger
  in from the card's own, and stopping it at the first and last hour drew two
  more, which is exactly what a canvas is not supposed to have. One painter and
  one `drawPoints` per strength, so fourteen hours cost two draw calls rather
  than six hundred widgets.
  - **Sized by the hour grid, clipped by the card**, which is the only
    arrangement that gets both halves. The lattice has to be *phased* on the
    grid, because only the grid knows where an hour falls and the hour's row is
    the strong one; but it has to *reach* the card's edges or the dots stop
    halfway up a grey panel and read as a texture somebody forgot to finish. So
    `_DotCanvas` overdraws by `_dotBleed` in every direction and `_DayBody`
    clips the day part on its own (`ClipRRect`, top corners rounded) so the
    lattice stops at the divider rather than running on under Home's sections —
    the month panel, which is still a whole card, carries `Clip.antiAlias` to
    cut it at the corner. The bleed is comfortably more than anything standing
    between the grid and that edge rather than measured from it, because a
    canvas told the height of the heading above it goes wrong the day somebody
    adds a chip; but not arbitrarily more, since every point of it is computed
    on each paint and then thrown away.
  - Nothing else in either card paints outside its box, so the clip costs
    nothing: the blocks carry no shadow, by request.
- **The gutter is sized to the widest label and not a point more.** It was 42,
  which is what a gutter needs if it is going to hold "Ganztägig"; the band took
  that word away and the number stayed behind, so nine points of every block's
  width were being spent on empty gutter. `_gutter` is 34 — "12 PM", wider than
  "12:00", at `AppText.microLabel` — and the label is in a scale-down `FittedBox`
  so an accessibility scale shrinks it rather than clipping it. The labels stay
  **right-aligned**, hugging the rules the way every calendar draws them, which
  is also what lands them on the screen title's own left edge: right-aligned in
  34 from the card's 14, "15:00" starts at about 24, and so does the title.
- **`_dayWindow` draws the hours the day uses, not all twenty-four.** Apple shows
  the whole day and scrolls it, which works when the day view *is* the screen;
  here it sits under a collapsing day strip inside a page that already scrolls,
  and a household opening the app would be looking at four empty hours before
  breakfast. So: what the day uses, an hour of air either side, never less than
  `_minWindowHours`, and today's own hour always inside it or the "now" line
  would point at a strip that isn't drawn.
- **The block stacks full width, in reading order, and cuts to what fits**
  (`_EventBlock._detailLines`): title, then the note, the location and the
  duration — each on its own line, each dropped from the bottom when the clock
  did not give the block room. A half-hour appointment is its title and nothing
  else, which is all a half-hour appointment has room to be.
  - The line count is **measured against the room the block has**, not chosen
    from a list of height thresholds: one number changing (`_hourHeight`, the
    padding, the text scale) must not leave four `if`s disagreeing about what
    fits. The scale comes from the context, because lines are taller for a
    household that asked for larger type and fewer of them fit.
  - **The duration is last on purpose.** It used to be pinned top-right, where it
    competed with the name for the one line every block has. A block's *height*
    is already the duration; the figure only names it exactly, so it is the last
    to arrive and the first to go.
  - That last line is the **time range** ("16:00 – 17:30 Uhr") wherever the block
    is at least `_rangeWidth` wide, and the duration where it is not. A block only
    gets narrow because something else starts inside it, and at that moment the
    reader needs to know which of the two is which — not two clock times fighting
    an ellipsis in half a column. The range wins whenever it fits, because the
    block's *position* already gives the start and only the end has to be read off
    the height.
- **The band is one row of chips, and the Feiertag is the first of them**
  (`_DayBand`). Each all-day event and untimed to-do used to take a full-width
  row at `AppText.itemTitle`, so a day with Ferien and a bin pickup spent two
  appointments' worth of height before the clock started — sitting directly under
  a Feiertag chip drawn at half the size, which made two things of exactly the
  same kind look like two different kinds of thing. They are all `_HolidayChip`'s
  shape and scale now, and the row **scrolls sideways rather than wrapping**. A
  `Wrap` was tried and it is not the same thing: on a day with a Feiertag, Ferien
  and a bin pickup the chips fell onto a second and third line and the band went
  back to costing an appointment's worth of height, which is the whole reason the
  pills became chips. What scrolling costs is a chip off the right edge on a very
  full day; what it buys is a band that is the same height on every day of the
  year, which is what lets the day below it sit still as you move between days.
  - **A hairline closes the band**, and it is the one rule on the card. The hour
    lines came off the day because a hairline drawn twelve times is paper the
    appointments have to compete with; a single one saying "above this is the
    whole day, below it is the clock" is the opposite — read once, then quiet.
    **Home needs it most**: it shares this view without the heading that names
    the section on the calendar screen, so there the rule is the only thing
    telling the two apart. It is inset to the card's content although the chips
    above it scroll past both edges — a rule is a statement about the column it
    divides, and a full-bleed one would be a statement about the card. Not drawn
    at all when there is no grid under it (`divided`), or it would underline a
    row rather than divide two.
  - An **empty day** has no band, so there the Feiertag still stands alone — a day
    off with nothing planned is worth saying. Both day views carry that one
    conditional.
  - **The band shares the grid's gutter.** The row starts with a calendar page
    with the date on it (`_DayPageMark`), right-aligned in `_gutter` where an
    hour label would stand, so the chips start on the blocks' own left edge
    instead of a gutter's width left of them. The page used to sit inside every
    all-day chip; there it put the band and the grid on two different edges.
    An all-day chip now carries the timeline block's **accent bar** instead, at
    the block's radius rather than a capsule's (a capsule's corners cut a bar to
    a sliver). The scroller is clipped on its left edge only
    (`_ClipLeftEdge`), so a chip scrolled back doesn't slide over the page but
    the row still runs off the right. The page is **drawn rather than taken from the icon font**, which is the one place
    in the app where that is right — every glyph in `AppIcons` is a shape that
    means something, and this has to *say* something, the date, which no font
    ships thirty-one of. Its number does not scale with the system text size: it
    is a glyph, and at an accessibility scale it would break out of a 17-point
    page long before it helped anybody read it. Standing in the gutter where the
    hours are named, it is what says the row beside it is the whole day rather
    than appointments that lost their times. A single-day
    all-day event prints no duration at all — a chip in this band already says it
    is all day, and "Ganztägig" beside the name was the band's own heading
    repeated once per chip.
- **A block's title is set in the all-day chip's own type** — `AppText.label` at
  w600, 12.5 points, where it used to be `AppText.itemTitle`'s 15. The band and
  the grid are one surface read in one glance, and a name two points larger down
  there made the band look like a caption over the real thing. Smaller also buys
  the blocks what they are always short of: at 15 a half-hour block had room for
  its name and nothing else, and its location and time never appeared. The timed
  to-do block follows it for the same reason — the two stand on one grid.
  - `_titleLine` came down with it (21 → 18), and `_titleRow` takes the **taller
    of the title and the mark beside it**. The page mark is a drawing and does
    not scale with the system text size, so at an accessibility scale the text
    wins again and the mark stops mattering, which is right.
  - **A name wraps into whatever height is left over, up to three lines**
    (`_titleLines`). The order matters: `_detailLines` runs first on a one-line
    title, because where the appointment is and when it ends are facts a name's
    third line is not — a block too small for both spends its second line on the
    place. Only what is *still* unspent comes back to the title. A half-hour
    block therefore ellipses exactly as it did; a four-hour one stops reading
    "Festakt 50 Ja…" over four centimetres of empty green. Three is the ceiling
    because past a third line a name is a paragraph rather than something read
    at a glance, and the air under a long appointment is not waste — it *is* the
    appointment being long, which the grid says better than any label could.
- **A repeating appointment carries a calendar page with *several* dates on
  it** — six dots where the all-day chip's page carries the day's number. The
  band above the grid and the blocks below it are one surface, so their two
  marks are one drawing: `_CalendarPageMark` is the page, `_DayPageMark` writes
  the date on it and `_RepeatPageMark` scatters them (`_RepeatDots`). It says
  "this appointment has more days than the one you are looking at" with no
  symbol anybody has to have learned.
  - **The recurrence arrows could not be drawn heavily enough at this size**,
    which is the other half of why they went. Phosphor's are one Regular
    stroke — about 1.5% of the em, two thirds of a point inside a 17-point page,
    a hairline beside the w700 number on the other page. Every fix was a
    compromise: the duotone's filled layer welded on with `secondaryOpacity: 1`,
    a third font vendored for one glyph, or the arrows drawn by hand. A filled
    dot is as bold as its radius and nothing else.
  - It stands on the **floor of the block**, bottom right, with the link badges
    and the forecast — not at the end of the last line, where on a four-hour
    appointment the text stops near the top and the marks stopped with it,
    halfway up a block of empty colour. `_markRow` is reserved out of the height
    *before* the detail lines are counted, which is what keeps the text off it:
    the column is top-aligned and now ends above the row rather than under it.
    On a tall block that reservation costs nothing — there are only three
    candidate lines and they all fit anyway — and on a one-hour block it costs
    the time range, which is the line the block's own geometry says best.
  - On a block too short to hold that row at all the mark drops back into the
    title, where it is a **`WidgetSpan` inside the text, not a widget beside
    it** — which is why `_title` is a `Text.rich`. In a `Row` the mark takes a
    column of its own and every wrapped line is indented under the first, a
    hanging indent that is right for a bullet and wrong for a name that happens
    to open with a symbol.
  - **`AppIcons.repeat` is nobody's mark now.** It named recurrence here and a
    Board Tracker over there — one symbol for two different promises, "this
    comes back every Tuesday" and "this is a rhythm we keep". The Tracker had
    already moved to `AppIcons.circleDashed`, the honest counterpart to the
    to-do's `checkCircle` it sits beside; Kalender has since stopped using the
    arrows too. Ausgaben's *recurring budget* still wears them, and should.
  - The Tracker's own swap to `circleDashed` covers the create sheet, Home's
    first steps, the day island and the paywall — a ring you tick shut beside a
    ring that never closes, wherever the two stand together.
- **A block says what is hung off it** — `_LinkBadges`, the glyph for a linked
  shopping list and the one for a linked to-do. It is the only thing on a block
  that is not already somewhere else on the grid: the name is in the calendar,
  the hour is the block's position and the length is its height, but that the
  Elternabend has a list against it existed nowhere, and finding out meant
  opening the sheet to see whether there was anything to open it for.
  - **It stands in `_markRow` with the forecast and the repeat mark**, pinned to
    the block's floor. It shared the last line of text first, which cost no
    height at all but put the marks wherever the text happened to stop — near
    the top of anything longer than an hour.
  - **Wide enough and it spells itself out** ("1 Liste"), because the count is
    the useful half and a glyph cannot say *two*; narrower and the glyph stands
    alone, which still answers what a glance is asking. `_badgeLabelWidth` is
    measured the way `_rangeWidth` is and for the same reason — what decides the
    form is the room left on the line it shares, not the block's height — and an
    appointment carrying both a list and a to-do asks for `_badgeLabelStep` more
    before *either* is spelled out, because two half-labels is the one outcome
    worth avoiding.
  - **Flat, not a pill.** The block is already a chip in its calendar's colour
    and a second chip inside it is a card pretending to be a row — the same
    reason the all-day pills carry no accent bar. It takes the ink and weight of
    the line it shares. `linkedListCount`/`linkedTaskCount` already existed for
    the detail sheet, so it needed no new string in any of the four languages.
- **The forecast is back on the block** (`_BlockWeather`), in that same corner,
  after the badges and before the repeat mark. It had been sent to the detail
  sheet when the grid replaced the agenda, on the grounds that a half-hour block
  is 34 points tall and a forecast icon alone is 26 of them — true, and the
  answer is that it does not get its own line and does not get 26 points.
  - **The drawing is rendered half again as large as the space it occupies**,
    which is what makes it legible, and it is not a trick. A Meteocon is a
    128-square with the weather in the middle: every cloud in the set spans
    about 65 of those units, half its square, so a plain 18-point render put a
    *nine-point* cloud on the block and the rest was transparent margin.
    Rendering at `_art` (27) inside a box of `_box` (19) spends that margin
    instead of the row's height — the ink roughly doubles and the mark still
    stands exactly `_markRow` tall. 27 is bounded by the widest art rather than
    by the box: `clear-day`'s rays span 93 units, which lands at 19.6 points and
    just fills the row.
  - Growing `_markRow` instead was the other way, and it costs more than it
    looks: a one-hour block has about 38 points under its title, so five more
    points of mark row is the difference between one detail line and none. The
    place the appointment is at should not come off the block to make a cloud
    bigger.
  - **The temperature still carries the answer.** Several of these drawings are
    pale by design — an overcast cloud, a snow cloud — and no size fixes a pale
    grey cloud on a pale chip the way two digits do. The day strip stacks the
    two and can afford 30 points.
  - **It is the one mark down there that is decoration**, so it is the first to
    yield: under `_weatherWidth` it comes off the block entirely, where the
    list, the to-do and the repeat all stay.
  - **It stands at the block's top edge, not in the bottom corner, because that
    edge is the appointment's start.** The reading is one hour of forecast keyed
    on where and *when* the appointment begins — that is what `eventWeatherKey`
    keys on — so at the foot of a four-hour block it read as a claim about the
    whole afternoon, an 18° honest at five and wrong by nine. Up there the
    grid's own axis says which hour it means, since everything on a block is
    drawn against time running down it. Capping it by duration instead was tried
    and was worse: at two hours it vanished from the Kochnachmittag and the
    Festakt, which is most of what a family weekend is made of.
  - It is **the exception to the corner, and the only one.** The list, the to-do
    and the repeat are facts about the appointment entire and have no hour to
    stand at; this has nothing else. It costs the title the corner its longest
    line would reach into — short names pay nothing, long ones wrap a word
    earlier — which is a price the old duration chip was not worth paying and
    this is: the duration was already the block's own height, and the forecast
    is on the grid nowhere else.
  - **Putting it in the hour gutter instead does not work today, and would be
    misleading in a different way.** `WeatherState.readings` is keyed on a place
    *and* an instant precisely because two appointments an hour apart in two
    towns genuinely differ, and `daily` holds one reading per *day* at the
    household's town — there is no hourly series for home. A mark in the gutter
    would therefore have to borrow some event's reading and print it in a column
    that is not that event's, so two 17:00 appointments in two towns would share
    one icon that is right for one of them. Doing it honestly means fetching and
    caching an hourly home series and drawing it as the *day's* weather rather
    than any appointment's — a real feature, not a move. A past appointment, one beyond the
    16-day horizon and a household with no address all resolve to no mark at
    all, which is how every weather failure in this app resolves.
- **A timeline block carries a `_accentBar` stripe in its calendar's undiluted
  colour.** The fill is the same hue lightened, which is what makes a pale
  calendar legible and also what makes two pale calendars take a second look to
  tell apart; the bar is the colour at full strength, in the one place on a block
  that is the same size whatever the clock gave it — a five-minute reminder and a
  whole afternoon carry the same three points of it. **Timeline blocks only**:
  the all-day pills above have no bar, because they are chips sitting in a band
  of their own and a stripe down the side of a pill is a card pretending to be a
  row.
- **Two chips came off the card and neither is missed.** The duration chip became
  that last line. The calendar chip is the **fill**: a dot beside "Familie" on a
  block painted in Familie's colour was saying it twice. Weather and the
  linked-list markers moved to the detail sheet; a half-hour block is 34 points
  tall and a forecast icon alone is 26 of them.
- **The day sits on grey** (`_DayBody`, and the month view's own panel). Both
  calendar screens are `AppColors.surface`, so the grey is what gives the day an
  edge instead of letting it run into the white. On Home it is a surface to the
  bottom of the screen that also holds the sections, not a card that ends. It is only
  safe because the chips are **opaque** — see below.
- **A block is the same flat chip every other chip in the app is** (`_blockChip`):
  the calendar's colour lightened, nothing around it, the colour itself carrying
  the text — `_HolidayChip`'s treatment, in the calendar's colour instead of the
  accent. In the all-day band it takes `_chipRadius` and is literally a pill,
  because there a row really is a chip; a block standing on the clock keeps a
  modest radius, since a capsule as tall as an afternoon is a lozenge whose
  corners eat the title. `_TodoBlock` is the same chip on the neutral surface,
  told apart by its check.
  - **Lightened in HSL, never mixed with white** (`_blockFill`). This is the
    whole difference between a vivid chip and a beige one: `tint` lerps toward
    white, which raises lightness *and* drags saturation to zero, so a blue at
    86% of the way to white is a grey-blue and a day of them reads as a set of
    envelopes. `_fillLightness` is the one dial — down is more vivid, up is more
    paper — and its ceiling is the text, since `_blockInk` draws the title in the
    same hue. The title is deliberately not darkened to buy room: that trades the
    colour of the type for the colour of the chip, and the type is what you are
    reading.
  - **Opaque, and that is what lets the day keep its grey card.** An alpha of the
    colour was the other way to stay vivid, and it takes whatever is behind it
    into its own colour — over grey every calendar drifted toward one dusty
    register. Removing the card was tried as the fix for that (Apple's day view
    is on white, which is the whole of its advantage) and the card won: opaque
    means the chip looks the same whatever it stands on, which is the cheaper
    half of the same bargain.
  - **Saturation is scaled, never floored.** A small lift makes a colour that has
    a hue read more strongly; a floor would invent one for a calendar that has
    none, and the app does not pick colours on a household's behalf.
  - **Three richer treatments were tried and each was louder than what it was
    holding.** A coloured outline, at a full point and again at a tenth of one,
    put a line around every hour of the day. A translucent fill could not keep a
    shadow — a shadow paints *behind* the box, so a chip you can see through is a
    chip you see the shadow through, and every block went muddy grey. The shadow
    on its own lifted twenty chips off a card that is a background rather than a
    surface. What separates a chip from the card is the dot lattice running under
    it, not anything drawn on the chip.
  - **The cost is named rather than designed around.** A calendar whose account
    gave it a grey — iCloud does, for "Familie" — is a pale grey chip on a grey
    card, and nothing here rescues it: the saturation lift is a scale, so it
    lifts nothing. Substituting a legible colour was tried and rejected, because
    a calendar's colour is what a household recognises it by in their own
    calendar app as much as in ours. **The household picking its own colour is
    what fixes it**, and that now ships — the swatch in "Kalender bearbeiten",
    `calendar_connections.calendar_colors`, copied onto `calendars.color` by
    `calendar-events` on the next read (`family_feeds.color` for Ferien and
    Abfall, which already had a column of its own).
- `_blockInk` clamps the calendar's colour to a lightness that reads as ink on
  its own tinted fill, keeping the hue. A provider hands over whatever the
  account picked, including pale yellows that vanish on a pale yellow ground, so
  the colour is not trusted to survive being text.
- **A timed to-do is an outline, not a fill** (`_TodoBlock`). Every appointment is
  a filled rectangle in its calendar's colour, so a to-do drawn the same way
  would be an appointment as far as a glance is concerned. It keeps the Board's
  own check and the assignee's face — the one thing from the old card small
  enough to survive the move. It takes `_todoSlotMinutes` of the grid because
  `tasks.due_time` is a moment, not a span.
- **Nothing shorter than `_minSlotMinutes` and nothing thinner than
  `_minBlockHeight`.** The first keeps the *layout* honest (two five-minute
  reminders at one moment still get two columns), the second keeps the block
  readable and hittable. A block's height comes from the clock, so at a large
  accessibility text scale the title is simply taller than the twenty minutes it
  stands for — `_Unbounded` clips that instead of letting Flutter paint an
  overflow stripe over the day.
- **There is no cap and no fold.** `_maxEntries` and `homeMoreEntries` are gone: a
  grid's height comes from the hours it covers, not from how many things stand on
  them, so a day with forty appointments is exactly as tall as a day with four.
- **Long-press, not swipe.** A block half a column wide has nowhere to swipe, so
  Bearbeiten/Löschen come from the system menu through `_openEventCardMenu`. Tap
  still opens the detail sheet.
- The blocks fade and rise in on a staggered entrance keyed on the day
  (`_HourGridState._stagger`), so changing day assembles the grid down the page
  rather than snapping it into place. The day panel's own size animation carries
  the rest.
- **`calendar/agenda_demo.dart` is scaffolding and is meant to be deleted.** Flip
  `_agendaDemo` to `true` and every day is replaced by a fixed set built to
  exercise the grid rather than to look like a nice day: two all-day events,
  three appointments on the same minute, a long workday that forces a second
  column and lets the rest spread right, a five-minute reminder, and a title no
  block can hold. Hooked at the two call sites (`_demoEvents`/`_demoTodos`)
  rather than inside `_dayPlan`, which is handed no date on an empty day. **Leave
  it `false` on `main`.**

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

Where the day has got to is now **one mark instead of one per appointment**: `_NowLine`, a dot on
the gutter's edge and a line across the hours, drawn only on today and only when the hour is inside
`_dayWindow`. A finished appointment steps back to 55% opacity rather than leaving
(`CalendarEvent.phaseAt`, against the *actual* wall clock — not the static mock
`CalendarEvent.phase` field, which is still on the model but no longer read by the UI).
`CalendarNotifier` ticks `state.now` every 30s via an internal `Timer.periodic` so the line
advances on its own; `_HourGrid` watches `calendarProvider.select((s) => s.now)` rather than the
whole notifier, so that tick moves a line instead of rebuilding a grid of blocks.

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
  `repeatUntil` are set from the "Wiederholen" row at the foot of the form's time card, and go out under a `repeat` key on the wire.
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

**On Home (week view) it is not on the nav row at all**: `_WeekViewState._buildJumpToToday` hangs
the small pill **at the right end of the status island's row** (`_MonthYearRow.trailing`, passed
through `_MonthAndChipsRow.labelTrailing`). It is built only while the strip is away from today, so
the island has the whole row otherwise and ellipsises against the pill when it is there. The row's
`AnimatedSwitcher` slides it in from the right edge while its slot widens (360ms in, 240ms out), and
reverses that on the way out so the island takes its width back smoothly. Being in the header's collapsing block, it fades out with the strip it
refers to. Home no longer
collapses the nav bar, so there is no row for it to drop onto. Everything below describes Kalender.

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
