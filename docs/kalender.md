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
  done a handful of times ever, and "neuer Termin" is something you do *to* the calendar rather
  than something today asks of you; the only way to add an appointment from Home is the empty-day
  state's own button. `_trailingSlot` is what the title clears at rest and is zero when the slot is
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

**Both tabs compact the nav bar** (`_compactingTabs` in `main.dart`), and the calendar's
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

**The day card's bottom edge is a boundary in meaning, not only in paint.** Above it is whichever
date the strip is on. Below it is the household as it stands right now. Tap a Thursday three weeks
out and the top changes while the bottom does not — which is correct, and only readable because the
card visibly ends. So **nothing in `belowDay` may be day-scoped**: an open to-do is open whatever
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
it does **not** fall back to the generic "Dein Tag": the header then said nothing about the day
underneath it, and the strip is the only other place the date appears. The island names the selected
day and how much is on it instead, counted through the same filtered `eventsFor` the card below
uses, which is exactly what Kalender's label does on its own tab. That line carries no wave
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

`HomeSections` — the `belowDay` slot: **Offen**, **Heute dran**, **Listen**, each hidden entirely
when it has nothing. The to-do rows use `CheckOffRow` — the Board's strike-hold-collapse — unlike
the agenda row above them, which does not: there a ticked to-do stays put, because a day whose
to-dos all vanished as they were done would read as a day that never had any, while here the
section *is* the open list and the row's whole job is to leave it. Tracker rows keep their circle
because a tracker you have to navigate to in order to tick is a tracker that stops being ticked, and
ticked ones stay on the card rather than emptying it as the day goes on. Beside each tracker's name —
on the same line, where it reads as the answer to the name rather than as a second fact about it —
is `_WeekStrip`, **the last seven days and nothing more** — as much history as a summary row can
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

**Both** tabs show the chip row at rest and collapse it into the same compact glass dropdown
(`_CalendarFilterButton`, opening `_FilterMenuRoute`) as the header scrolls away — the dropdown
is *only* a collapsed-state stand-in, never shown alongside the chips. It lists the same accounts
and indents each one's calendars underneath, so the one place a single calendar can be picked
survives the header scrolling away. It's overlaid in
`_TitleRow` via a `Stack` (not a `Row` child) so it can't push the expanded left-aligned title
sideways, and fades in over the last 40% of the collapse (`_TitleRow._leadingOpacity`). Keep the
two tabs' behaviour identical here.

**On iOS the list is UIKit's own menu, not that panel.** `_openMenu` builds the rows once and
hands them to `showNativeMenu` (`lib/services/native_menu.dart`); `_FilterMenuRoute` below is what
everything else gets, and what iOS gets before 17.4. Three things carry across that the rows would
be meaningless without: each calendar's colour as a filled dot (UIKit takes an SF Symbol or an
image, and there is no symbol for "green"), the tick on the filter in force, and a "To-dos" row
that toggles the overlay **without closing the menu** (`keepsOpen`, i.e. `.keepsMenuPresented`) —
it flips its own checkmark natively, because the presented menu is a snapshot UIKit never re-asks
for. What is lost is the indent: a UIKit menu has no margin, so an account and its calendars share
a *section* — a hairline above the group — rather than a step into it.

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
