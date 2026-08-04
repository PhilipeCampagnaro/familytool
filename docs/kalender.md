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

**Centered title.** In `_TitleRow` (both views) and the event-detail sheet header, the title is a
full-width `Positioned.fill` layer in a `Stack` with the flanking buttons positioned over it —
*not* an `Expanded` sibling of them. As a Row child its centered state lands off-center by half
the button's width. Clearance from the buttons comes from horizontal padding that is **symmetric
at t == 1**; an asymmetric inset silently reintroduces the same offset.

**They need a frosted background of their own.** `NestedScrollView` does *not* clip its body to
below a pinned header: the gray body keeps sliding up until its top reaches the top of the
screen, so a bare header has the agenda rendering sharply behind the title and glass buttons.
Both `_WeekViewState._buildHeader` and `_buildEventDetailHeader` lay a `FrostedHeaderBackground`
(`lib/widgets/glass.dart`) in as a `Positioned.fill` first layer of a `Stack`. A solid fill was
tried first and the user asked for see-through instead: content should still read as *there*,
blurred, passing underneath. See [design-system.md](design-system.md) for the two load-bearing
details of that widget (progressive blur, low tint alpha).

How far below the buttons the sharp gray starts is the header's collapsed height: a small gap
(`_WeekViewState._collapsedGap`, `_eventDetailCollapsedGap`) survives at t == 1 as a band of pure
material. The month view's header does *not* get this — it's a plain `Column` sibling above the
grid, so nothing scrolls under it.

**Event-detail sheet header order**: title + close button on the first row, source/owner chips on
a second row *below* them — the chips are the part that collapses, so putting them first pushed
the title down a line and stranded the close button beside the chips. The whole header is
absolutely positioned against its expanded geometry (`_eventDetailTopPad` /
`_eventDetailTitleRowHeight` / `_eventDetailChipsRowHeight` / `_eventDetailCollapsedGap`, which
also derive the sliver's two heights) and the `Stack`'s default `Clip.hardEdge` is what removes
the chips as it shrinks — the rows never re-lay-out, so the title can't shift as the chips go.
The close button is the Stack's *last* child on purpose: `GlassIconButton` is a native platform
view on iOS, which composites above anything Flutter paints after it. The chips vanished on
device (but not in widget tests) while they were painted after it.

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
