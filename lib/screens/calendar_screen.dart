import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter, PointMode;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../data/calendar_data.dart';
import '../data/german_holidays.dart';
import '../models/calendar_event.dart';
import '../models/event_link.dart';
import '../models/shopping_list.dart';
import '../models/task.dart';
import '../models/who.dart';
import '../models/weather.dart';
import '../services/external_links.dart';
import '../services/map_snapshot.dart';
import '../services/local_notifications.dart';
import '../services/native_menu.dart';
import '../state/board_state.dart';
import '../state/calendar_state.dart';
import '../state/family_state.dart';
import '../state/holidays_state.dart';
import '../state/list_state.dart';
import '../state/more_state.dart';
import '../state/nav_state.dart';
import '../state/notification_state.dart';
import '../state/weather_state.dart';
import '../theme/tokens.dart';
import '../widgets/anchored_menu.dart';
import '../widgets/app_sheet.dart';
import '../widgets/avatar.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/check_off.dart';
import '../widgets/day_circle.dart';
import '../widgets/event_dots.dart';
import '../widgets/filter_chip.dart';
import '../widgets/floating_pill.dart';
import '../widgets/more_shelf.dart';
import '../widgets/glass.dart';
import '../widgets/native_glass_buttons.dart';
import '../widgets/icon_picker.dart';
import '../widgets/native_occlusion.dart';
import '../widgets/native_switch.dart';
import '../widgets/settings_chrome.dart';
import '../widgets/toast_chip.dart';
import '../l10n/l10n.dart';
import 'board_screen.dart';
import 'calendar_connect_screen.dart';
import 'list_screen.dart';
import '../theme/app_icons.dart';

part 'calendar/event_form.dart';
part 'calendar/repeat_sheet.dart';
part 'calendar/calendar_filter.dart';
part 'calendar/week_view.dart';
part 'calendar/month_view.dart';
part 'calendar/event_detail_sheet.dart';
part 'calendar/day_timeline.dart';
// Scaffolding for designing the agenda — see [_agendaDemo]. Delete with the file.
part 'calendar/agenda_demo.dart';

/// The forecast for the event the sheet or the row is showing, on the day it is
/// being shown on.
///
/// The day matters and is always the selected one: an all-day event spanning a
/// week is sampled per day, so "which day am I looking at" is half of the
/// lookup key. Null is the ordinary answer for a past event, one beyond the
/// forecast horizon, or a household with no address yet.
WeatherReading? _weatherFor(WidgetRef ref, CalendarEvent event) {
  final sel = ref.watch(calendarProvider.select((s) => s.selected));
  return ref.watch(weatherProvider).forEvent(event, DateTime(sel.y, sel.m, sel.d));
}

/// The reference a list or a task keeps when it is made from this appointment.
///
/// Null for an event with no provider `uid` — nothing in the app has one today,
/// since every event is proxied, but a link with no event on the other end is
/// worse than no link, so the "Liste zum Termin erstellen" row simply creates a
/// plain list in that case.
///
/// The start is copied and **the title is not**: the day is what makes the tap
/// back work months later, when the appointment is far outside the window
/// Kalender has loaded, and the name is content out of somebody's calendar that
/// this app does not keep. See [EventLink].
EventLink? _linkTo(CalendarEvent event) {
  if (event.uid.isEmpty) return null;
  return EventLink(calendarId: event.calendarId, uid: event.uid, startsAt: event.startsAt);
}

/// The household's lists and tasks that were made from this appointment.
///
/// Watched, so a list created from the sheet appears in it without a reload —
/// the notifier has already put the saved row into `listProvider`'s state by the
/// time the create sheet closes.
///
/// **Narrowed to the containers themselves**, not the whole screen state: every
/// agenda row calls both of these, and watching `listProvider` whole would
/// rebuild the entire day each time somebody ticks an article off a shopping
/// list. `copyWith` hands back the same `lists`/`tasks` reference when only the
/// items changed, so the identity comparison behind `select` does the rest.
///
/// Over the tasks rather than `visibleTasks`, deliberately: Board's person chip
/// is about Board, and it must not make a task somebody hung off this
/// appointment vanish from the appointment.
List<ShoppingList> _linkedListsFor(WidgetRef ref, CalendarEvent event) {
  if (event.uid.isEmpty) return const [];
  final lists = ref.watch(listProvider.select((s) => s.lists));
  return [
    for (final l in lists)
      if (l.eventLink?.namesEvent(calendarId: event.calendarId, uid: event.uid) ?? false) l,
  ];
}

List<BoardTask> _linkedTasksFor(WidgetRef ref, CalendarEvent event) {
  if (event.uid.isEmpty) return const [];
  final tasks = ref.watch(boardProvider.select((s) => s.tasks));
  return [
    for (final t in tasks)
      if (t.eventLink?.namesEvent(calendarId: event.calendarId, uid: event.uid) ?? false) t,
  ];
}

/// The Board's to-dos owed on one day — what the "To-dos" chip lays over the
/// agenda.
///
/// **Only a dated to-do, and only on its own day.** The Board shows an overdue
/// row under "Heute", because on the Board a missed to-do is today's problem
/// rather than history. A calendar cannot borrow that: last Tuesday's row drawn
/// on today is the calendar saying the day is something it is not, and the day
/// it *was* owed would then show nothing at all. So it stays on its date, past
/// or not, and the Board goes on being the screen that chases it.
///
/// A ticked to-do stays. A day whose to-dos were all done reading exactly like
/// a day that never had any is the calendar losing the thing worth seeing.
///
/// **Trackers are not here and cannot be.** A rhythm is never owed on a date —
/// `trackers` carries a rule, not a deadline — so there is no day to draw one
/// on. See the tracker note in CLAUDE.md.
///
/// Narrowed to `tasks` the same way [_linkedTasksFor] is, and over `tasks`
/// rather than `visibleTasks` for the same reason: Board's person chip is about
/// Board, and it must not reach across into Kalender's own row of chips.
List<BoardTask> _todosDueOn(WidgetRef ref, int y, int m, int d) {
  final tasks = ref.watch(boardProvider.select((s) => s.tasks));
  final open = <BoardTask>[];
  final done = <BoardTask>[];
  for (final t in tasks) {
    final due = t.dueDate;
    if (due == null || due.year != y || due.month != m || due.day != d) continue;
    (t.done ? done : open).add(t);
  }
  // Done last, so the day reads as what is still owed followed by what is not.
  // Only the untimed ones keep this order — see [_dayPlan], which sorts
  // the ones carrying an hour into the day's own stream instead.
  return [...open, ...done];
}

/// A day split the way the grid draws it.
///
/// **Three piles, and the split is the whole design.** What sits on the clock
/// goes on the clock; what is true of the day as a whole goes in the band above
/// it. Giving an all-day event or an undated to-do a position on a time grid
/// would be inventing one, which is exactly what the old rail did when it
/// printed "Ganztägig" where a clock time belonged.
class _DayPlan {
  /// Context for the day rather than appointments in it — Ferien, the bin, a
  /// birthday. The repository already sorts these to the front.
  final List<CalendarEvent> allDay;

  /// Owed by the end of the day and not at a point in it. Most to-dos.
  final List<BoardTask> untimedTodos;

  /// Appointments and timed to-dos, clipped to this day and in start order.
  final List<_TimedEntry> timed;

  const _DayPlan({required this.allDay, required this.untimedTodos, required this.timed});

  bool get isEmpty => allDay.isEmpty && untimedTodos.isEmpty && timed.isEmpty;
}

/// Splits a day's events and to-dos into the band and the clock.
///
/// Every timed entry is **clipped to the day being drawn**: an overnight shift
/// or a multi-day appointment is one row from the provider covering two dates,
/// and each date draws only its own share. `event.days` already puts the row on
/// both days; this is what stops it running off the bottom of the first one.
///
/// A to-do that names an hour is given [_todoSlotMinutes] on the grid. It has no
/// end — `tasks.due_time` is a moment, not a span — so the block is a nominal
/// size that reads as "around then" rather than a claim about how long it takes.
_DayPlan _dayPlan(List<CalendarEvent> events, List<BoardTask> todos, DateTime day) {
  final allDay = <CalendarEvent>[];
  final untimed = <BoardTask>[];
  final timed = <_TimedEntry>[];

  final dayStart = DateTime(day.year, day.month, day.day);
  final dayEnd = dayStart.add(const Duration(days: 1));

  int minutesInto(DateTime at) {
    if (!at.isAfter(dayStart)) return 0;
    if (!at.isBefore(dayEnd)) return 1440;
    return at.difference(dayStart).inMinutes;
  }

  for (final event in events) {
    if (event.allDay) {
      allDay.add(event);
      continue;
    }
    final from = minutesInto(event.startsAt);
    final to = minutesInto(event.endsAt);
    timed.add(
      _TimedEntry(
        entry: event,
        from: from,
        to: math.max(to, from),
        slotTo: math.min(1440, math.max(to, from + _minSlotMinutes)),
      ),
    );
  }

  for (final task in todos) {
    final at = task.dueTime;
    if (at == null) {
      untimed.add(task);
      continue;
    }
    final from = math.min(1440, at.hour * 60 + at.minute);
    timed.add(
      _TimedEntry(
        entry: task,
        from: from,
        to: math.min(1440, from + _todoSlotMinutes),
        slotTo: math.min(1440, from + _todoSlotMinutes),
      ),
    );
  }

  timed.sort((a, b) {
    final byClock = a.from.compareTo(b.from);
    // An appointment wins a tie, because the day view is a calendar first: at
    // 14:00 the appointment is the fixed thing and the to-do is what has to fit
    // around it. Ordering decides which of them takes the leftmost column.
    if (byClock != 0) return byClock;
    final aEvent = a.entry is CalendarEvent ? 0 : 1;
    final bEvent = b.entry is CalendarEvent ? 0 : 1;
    return aEvent.compareTo(bEvent);
  });

  return _DayPlan(allDay: allDay, untimedTodos: untimed, timed: timed);
}

/// How much of the grid a to-do with an hour on it takes. Half an hour: long
/// enough to read, short enough not to imply the day is booked.
const _todoSlotMinutes = 30;

/// "Heute · 14. Sep" / "Montag · 14. Sep" — the line over a day's agenda, and
/// the one the detail sheet prints under the event's name.
///
/// One function because three callers were computing the same two-branch
/// expression: the week agenda, the month view's details box, and the jump that
/// arrives from a linked task, which has to produce exactly what the row it
/// bypassed would have produced.
String _dayHeading(DateTime day) => _isToday(day.year, day.month, day.day)
    ? L.s.todayWithDate(day.day, day.month)
    : L.s.weekdayWithDate(day.weekday % 7, day.day, day.month);

/// Opens an appointment's own detail sheet **over whatever screen the tap came
/// from**, and answers whether there was one to open.
///
/// The chip on a task or a list used to switch tab and land on the day in
/// Kalender. It worked, and it lost people: the sheet closed onto a calendar
/// they had not asked for, two tabs from the list they had been reading, with
/// no sense of how they got there. The sheet is the entire payload of that link
/// anyway — it is driven by [CalendarScreenState.openEvent] and needs nothing
/// of Kalender to be on screen — so it stacks over Board or Listen instead, and
/// closing it puts the reader back exactly where they were.
///
/// Neither the selected day nor the calendar filter is touched, for the same
/// reason: Kalender is not being shown, and quietly re-selecting its day or
/// clearing its chips would rearrange a screen nobody is looking at.
///
/// False means the appointment is outside the fortnight Kalender holds and
/// there is nothing to show — we do not store the household's calendar, so an
/// appointment eight months out simply is not here. [EventLinkChip] asks the
/// same question of its own state and stays a marker rather than offering a tap
/// that would do nothing.
bool showLinkedEventSheet(BuildContext context, WidgetRef ref, EventLink link) {
  final event = ref
      .read(calendarProvider)
      .eventForLink(calendarId: link.calendarId, uid: link.uid, day: link.day);
  if (event == null) return false;

  ref.read(calendarProvider.notifier).openEvent(event, _dayHeading(event.startsAt));
  _showEventDetailSheet(context, ref);
  return true;
}

bool _sameDay(CalSelectedDay s, int y, int m, int d) => s.y == y && s.m == m && s.d == d;

bool _isToday(int y, int m, int d) {
  final t = calToday();
  return y == t.year && m == t.month && d == t.day;
}

/// A day's dot colours, already narrowed to the active calendar chip.
///
/// The narrowing now happens inside [CalendarScreenState.dayColors], because
/// `eventsFor` applies the filter by calendar id. Matching on colour, as this
/// used to, silently merged two calendars a household had given the same
/// colour.

/// Year/month `monthOffset` months from the real "today", used to anchor the
/// month view's infinite scroll (offset 0 = today's month, negative = past,
/// positive = future) independent of whichever day is currently selected.
(int, int) _monthAt(int monthOffset) {
  final today = calToday();
  final total = today.month - 1 + monthOffset;
  final year = today.year + (total >= 0 ? total ~/ 12 : (total - 11) ~/ 12);
  final month = ((total % 12) + 12) % 12 + 1;
  return (year, month);
}

/// The Kalender tab: the month grid, and only that.
///
/// **The week view moved to Home** ([CalendarWeekScreen]) and the toggle that
/// used to swap the two went with it. The pair were one screen wearing two
/// faces, and the face a household wants nearly every time it opens the app —
/// today, its appointments, its to-dos — was hidden behind a control that had
/// to be found and remembered. Putting it on the tab the app opens on makes it
/// the answer to "what is today" without a tap, and leaves this tab to the
/// question a grid is actually good at: what does the month look like.
///
/// The two still share [calendarProvider] whole, filter chips and selected day
/// included, so narrowing to one person on either is narrowing on both.
class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(calendarProvider);
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: false,
        // The view builds its own header (title + month row + chips) inside a
        // scroll listener so it can shrink as the grid scrolls — see _MonthView.
        child: _CompactNavOnScroll(
          child: _MonthView(state: state, accent: accent),
        ),
      ),
    );
  }
}

/// The week view, as the Home tab — a scrolling day strip over the selected
/// day's agenda.
///
/// A public wrapper rather than a screen of its own, because everything it
/// draws is the calendar library's: the strip cells, the agenda rows, the
/// filter chips and the event sheet are all `part` files here, and moving one
/// of them out to be importable would drag the rest with it. Home mounts this;
/// nothing else does.
///
/// The four slots below are the Home tab's own business rather than the
/// calendar's, and they are slots rather than content so that everything Home
/// knows about — the household's to-dos, its trackers, its setup — stays in
/// `lib/screens/home/` and out of this library. What this file owns is the
/// *shape*: a header, a day, and room above and below it.
class CalendarWeekScreen extends ConsumerWidget {
  /// Shown at the right of the title row, at every stage of the collapse. Null
  /// on any caller that isn't Home.
  final Widget? trailing;

  /// The line above the filter chips — Home's status island. Falls back to the
  /// plain "Dein Tag" label, which is also what a caller with nothing smarter
  /// to say should leave it as.
  final Widget? label;

  /// Below the day card's bottom edge, and therefore **not about the selected
  /// day** — see `HomeSections`. Everything here keeps saying the same thing
  /// while the strip moves, which is only readable because the card between
  /// them visibly ends.
  /// Directly under the label and above the chips: Home's first-steps
  /// checklist. It opens *inside* the header — see [underLabelHeight].
  final Widget? underLabel;

  /// How tall [underLabel] is when open, zero when closed. Arithmetic rather
  /// than a measurement, because the collapsing header's extent has to be known
  /// before the panel is laid out; `firstStepsPanelHeight` is where Home works
  /// it out.
  final double underLabelHeight;

  final Widget? belowDay;

  const CalendarWeekScreen({
    super.key,
    this.trailing,
    this.label,
    this.underLabel,
    this.underLabelHeight = 0,
    this.belowDay,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(calendarProvider);
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: false,
        // No `_CompactNavOnScroll`: Home keeps its bar — see `_compactingTabs`.
        child: _WeekView(
          state: state,
          accent: accent,
          title: L.s.navHome,
          trailing: trailing,
          label: label,
          underLabel: underLabel,
          underLabelHeight: underLabelHeight,
          belowDay: belowDay,
        ),
      ),
    );
  }
}

/// Compacts the bottom nav to a single button as the agenda is scrolled down,
/// and brings the whole bar back at the top of the list.
///
/// Kalender only. It is the one screen where the rows are wide, dense and read
/// for a while, so the bar has the most to gain by getting out of the way —
/// and the least to lose, since nothing here is a step in a flow that needs
/// another tab. The bar itself lives in `AppShell`, which is why this goes
/// through [navBarProvider] rather than a callback: the two are half the
/// widget tree apart.
///
/// Both views scroll vertically over the same listener, so the week and month
/// view behave identically; the day strip and the chip row are horizontal and
/// are filtered out by axis, or a sideways flick through the week would put
/// the bar away.
class _CompactNavOnScroll extends ConsumerWidget {
  final Widget child;

  const _CompactNavOnScroll({required this.child});

  /// How far down the list counts as "reading" rather than as an overscroll
  /// wobble or the first pixels of a bounce.
  static const _threshold = 24.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.axis != Axis.vertical) return false;
        final nav = ref.read(navBarProvider.notifier);
        // Only a drag re-arms collapsing after the button was tapped; the
        // glide left over from the last flick must not undo that tap.
        if (n is ScrollStartNotification) {
          if (n.dragDetails != null) nav.dragStarted();
          return false;
        }
        if (n is! ScrollUpdateNotification) return false;
        final delta = n.scrollDelta ?? 0;
        // Both tests are on the *movement*, never on the resting position.
        // The week view is a `NestedScrollView`, so two positions report here
        // — and the inner list sits at pixels 0 for the whole time the header
        // is collapsing. Read as a position, that reads as "at the top" and
        // the bar would fight the finger all the way down.
        //
        // Scrolling back to the top is the one automatic way out: everywhere
        // else the user taps the button, so the bar can't reappear over a row
        // because a finger drifted the wrong way mid-read.
        if (delta < 0 && n.metrics.pixels <= 0) {
          nav.expand();
        } else if (delta > 0 && n.metrics.pixels > _threshold) {
          nav.compact();
        }
        return false;
      },
      child: child,
    );
  }
}

/// Positions Kalender's "Heute" button, which shares the nav bar's row: it
/// hangs off the bar's own centre line at the right edge once the bar has
/// collapsed to the button on the left, and rises to park above the bar while
/// the bar is still expanded and would otherwise be under it.
///
/// One `right:` for both states, so the button only ever travels vertically —
/// and on the same clock as the bar, so the two read as one movement rather
/// than as two controls that happen to move at once.
class _JumpToTodaySlot extends ConsumerWidget {
  final bool visible;
  final Color accent;
  final VoidCallback onTap;

  const _JumpToTodaySlot({required this.visible, required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.watch(navBarProvider);
    // The Mehr shelf stands on the same side, so while it is up "Heute" rises
    // over its top button and lines up with the column instead of sitting
    // beside it.
    final shelf = nav.compact ? null : ref.watch(moreShelfAnchorProvider);
    return AnimatedPositioned(
      duration: kNavSwapDuration,
      curve: Curves.easeInOutCubic,
      right: shelf != null ? moreShelfRight(context, shelf) : AppSpacing.screenPad,
      bottom: nav.compact
          ? navRowBottom(context, barHeight: nav.barHeight)
          : shelf != null
          ? moreShelfTop(context, barHeight: nav.barHeight) + kMoreShelfSpacing
          : navContentInset(context, pill: 106, gap: 36),
      child: _JumpToTodayButton(visible: visible, accent: accent, onTap: onTap),
    );
  }
}

/// The screen's title, and — on Kalender — its header actions. Always visible. [t] (0 =
/// expanded, 1 = fully collapsed) morphs the title from a large left-aligned
/// heading down to a small centered one, matching an iOS large-title nav bar
/// collapse. Both views drive it continuously from scroll offset (the week
/// view via [CollapsingSliverHeaderDelegate], the month view off its own
/// `ScrollController`).
class _TitleRow extends StatelessWidget {
  final double t;

  /// Optional control pinned to the far left, alongside the title — the
  /// calendar-filter dropdown lives here, and only while collapsed: it stands
  /// in for the [_MonthAndChipsRow] chip row, which has scrolled away by
  /// then. See [_leadingOpacity].
  final Widget? leading;

  /// The screen's own name. The two views are two tabs now, so this is
  /// "Kalender" under the grid and the Home tab's name over the week — a
  /// header that said "Kalender" on the tab the app opens on would be naming
  /// the wrong thing.
  final String title;

  /// What rides at the right, and it is a different thing on each tab:
  /// Kalender's [_CalendarHeaderActions] capsule, Home's profile avatar. Both
  /// are always visible — unlike [leading], which only appears once the chips
  /// it stands in for have gone.
  ///
  /// Home carries no header actions at all. Connecting an account is a setup
  /// action done a handful of times ever, and filing a new appointment is
  /// something you do *to* the calendar rather than something today asks of
  /// you; the empty-day state still offers both where they are the only useful
  /// move ([_EmptyDayActions]).
  final Widget? trailing;

  /// How much room [trailing] needs, gap included. Passed rather than measured
  /// because the title's geometry depends on it — see [_trailingSlot] — and a
  /// layout pass would arrive a frame after the number is wanted.
  final double trailingWidth;

  const _TitleRow({
    required this.t,
    required this.title,
    this.leading,
    this.trailing,
    this.trailingWidth = 0,
  });

  /// The filter dropdown duplicates the chip row, so it stays hidden until
  /// those chips are essentially gone — it fades in over the last 40% of the
  /// collapse rather than cross-fading against the control it replaces.
  double get _leadingOpacity => ((t - 0.6) / 0.4).clamp(0.0, 1.0);

  /// Horizontal breathing room reserved on both sides of the collapsed title.
  /// Both sides get the *same* inset at t == 1 even though the two flanking
  /// controls aren't the same width, because an asymmetric inset is exactly
  /// what knocks a centered title off-center — so this is the widest of them
  /// (Kalender's actions group) plus a gap. It stays that number on Home, where
  /// the avatar is narrower: what matters at t == 1 is that the two sides
  /// match, and a title this short has width to spare either way.
  static const _collapsedSideInset = 108.0;

  /// What the title must clear on the right at rest. Zero where there is
  /// nothing there, so the expanded title runs the full width instead of
  /// stopping short of a space nothing occupies.
  double get _trailingSlot => trailing == null ? 0 : trailingWidth;

  @override
  Widget build(BuildContext context) {
    final leadingOpacity = _leadingOpacity;
    return SizedBox(
      height: 40,
      child: Stack(
        children: [
          // The title is its own full-width layer rather than an `Expanded`
          // sibling of the add button: as a Row child its "center" would be
          // the center of the space the buttons left over, so the collapsed
          // title sat visibly off-center by half the button's width. Spanning
          // the whole row makes centered mean centered, whatever flanks it.
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(
                left: _collapsedSideInset * t,
                right: _trailingSlot + (_collapsedSideInset - _trailingSlot) * t,
              ),
              child: Align(
                alignment: Alignment.lerp(Alignment.centerLeft, Alignment.center, t)!,
                child: Text(
                  title,
                  maxLines: 1,
                  style: AppText.screenTitle.copyWith(
                    fontSize: AppText.headerExpanded + (AppText.headerCollapsed - AppText.headerExpanded) * t,
                  ),
                ),
              ),
            ),
          ),
          if (trailing != null) Positioned(right: 0, top: 0, bottom: 0, child: Center(child: trailing!)),
          // Overlaid rather than laid out inline for the same reason as the
          // title: reserving width for it would drag the expanded, left-aligned
          // title sideways even at t == 0, where this isn't visible at all.
          if (leading != null && leadingOpacity > 0)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                ignoring: leadingOpacity < 1,
                child: Opacity(opacity: leadingOpacity, child: leading!),
              ),
            ),
        ],
      ),
    );
  }
}

/// Kalender's two header actions in one glass capsule, iOS 26-style.
///
/// Connecting a calendar is Kalender's own job, and burying it in Einstellungen
/// made a household walk through three screens to add the school's link. It is
/// a setup action, though, so it rides *beside* the daily one rather than
/// taking a button's worth of header for itself.
///
/// Its own widget since Home stopped showing it: what the header's right-hand
/// side holds is now the tab's business, and [_TitleRow] takes whatever it is
/// handed.
class _CalendarHeaderActions extends StatelessWidget {
  final VoidCallback onAdd;

  const _CalendarHeaderActions({required this.onAdd});

  /// [GlassIconGroup.width] for two actions — 2 × 44 plus the capsule's end
  /// padding — plus the gap the title must keep from it. Handed to
  /// [_TitleRow.trailingWidth]; change the number of actions and this moves.
  static const width = 100.0;

  @override
  Widget build(BuildContext context) {
    return GlassIconGroup(
      actions: [
        GlassIconAction(
          // Not the empty state's `calendarPlus`: beside a bare plus, two
          // plus-bearing glyphs read as two ways to add the same thing. A link
          // is what "verbinden" means anyway.
          icon: AppIcons.link,
          label: L.s.connectCalendars,
          onTap: () =>
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => CalendarConnectionsPage())),
        ),
        GlassIconAction(icon: AppIcons.plus, label: L.s.addEvent, onTap: onAdd),
      ],
    );
  }
}

/// Identifies the filter chip row for tests. The day strip is a horizontal
/// `ListView` too, so "the horizontal list in the header" isn't specific enough
/// to find it by.
const calendarChipRowKey = ValueKey('calendarChipRow');

/// Identifies the week view's scrolling day strip for tests.
const calendarDayStripKey = ValueKey('calendarDayStrip');

/// Month/year label, and the calendar filter chip row — the part of the header
/// that fades/shrinks away entirely as either view collapses, at which point
/// [_CalendarFilterButton] fades into the title row to take the chips' place.
/// Shared by both views so the two behave identically.
class _MonthAndChipsRow extends ConsumerWidget {
  final CalendarScreenState state;
  final Color accent;

  /// A widget rather than a string, because the two tabs put different *kinds*
  /// of thing here now: Kalender a month name, Home a status pill that can
  /// carry a glyph, a count and a disclosure chevron. See [_MonthYearRow].
  final Widget label;

  /// How tall that row is. Kalender keeps [_MonthYearRow.monthHeight], which is
  /// what a month name needs; Home asks for more because its island is two
  /// lines. Passed in rather than measured because both views' collapsing
  /// arithmetic is done against it.
  final double labelHeight;

  /// Home's first-steps checklist, between the label and the chips. Already
  /// sized by the caller — see `_WeekView`, which has to know its height before
  /// it lays the header out at all.
  final Widget? underLabel;

  /// At the right end of the label's row — Home's "Heute" pill. See
  /// [_MonthYearRow.trailing].
  final Widget? labelTrailing;

  const _MonthAndChipsRow({
    required this.state,
    required this.accent,
    required this.label,
    this.labelHeight = _MonthYearRow.monthHeight,
    this.underLabel,
    this.labelTrailing,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MonthYearRow(height: labelHeight, trailing: labelTrailing, child: label),
        ?underLabel,
        const SizedBox(height: 14),
        SizedBox(
          // The shared chip's own row height — see [AppFilterChip.rowHeight].
          // The row is measured by the collapsing header rather than assumed.
          height: AppFilterChip.rowHeight,
          child: ListView(
            key: calendarChipRowKey,
            scrollDirection: Axis.horizontal,
            children: [
              // First, and in front of a rule. Every chip after it is a face
              // that narrows the row to one person; this one adds a second kind
              // of thing on top of them all. Sitting in among the faces it
              // would read as another person, and its first tap would look like
              // it had hidden everybody. It leads because it is the one chip
              // always there — which faces follow depends on what the household
              // has connected, so the row would otherwise open on a different
              // kind of thing from one phone to the next.
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _TodosChip(state: state),
              ),
              _ChipRowDivider(),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _AllCalendarsChip(state: state),
              ),
              for (final group in state.activeGroups)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _CalendarGroupChip(state: state, group: group),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The label above the chips. Shared by the week view's full header
/// ([_MonthAndChipsRow]) and the month view's own collapsing header.
///
/// **The label says two different kinds of thing on the two tabs, on purpose.**
/// Kalender prints the month the grid is showing and crossfades it as that
/// month changes, because a grid of numbered squares needs telling which month
/// it is. Home never names a month — the day strip is already a row of dates and
/// the agenda under it is one day's — and spends the row on its status island
/// instead: the single most pressing thing about today, or "Dein Tag" when
/// there is nothing pressing. See `DayIsland`.
///
/// Which is why this takes a widget. The crossfade below is keyed on whatever
/// it is given, so **every caller must put a `Key` on its child** or the row
/// will swap contents without animating.
///
/// The list-vs-grid toggle used to sit opposite the label and is gone: the two
/// views are two tabs now, so the control that swapped them would be a second,
/// quieter way of doing what the nav bar already does. What is left of that
/// side is [trailing], which only Home fills.
///
/// The label is given the row's full width and aligned left, rather than left
/// to ask for what it wants: a child measured against infinity cannot ellipsise,
/// and Home's island can be holding an appointment's title.
class _MonthYearRow extends StatelessWidget {
  final Widget child;
  final double height;

  /// Rides at the right end of the row, outside the crossfade — Home puts its
  /// "Heute" pill here while the strip is away from today. The label keeps the
  /// rest of the width and ellipsises against it.
  final Widget? trailing;

  const _MonthYearRow({required this.child, this.height = monthHeight, this.trailing});

  /// What the row occupied when it held the view toggle (3 + 34 + 3), kept as a
  /// fixed height rather than let go: both views' `_extraHeaderHeight` are
  /// arithmetic over this row, and a label that set its own height would move
  /// the chips under it on one tab and not the other. It is also the reason
  /// Home's island was nearly free — a glyph beside a heading fits the toggle's
  /// old slot with room to spare.
  ///
  /// It is the *default* rather than the only value: Home's island grew a
  /// second line saying what its count is counting, and its own view pays the
  /// eight points for it. Kalender's month name still sits at 40.
  static const monthHeight = 40.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Row(
        children: [
          // Given the row's whole width rather than left to ask for what it
          // wants: a label that measures itself against infinity cannot
          // ellipsise, and Home's island can hold an appointment's title. The
          // switcher stacks its children centred by default, so the alignment
          // has to be said out loud once the box is wider than the words.
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeIn,
              layoutBuilder: (current, previous) =>
                  Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero).animate(animation),
                  child: child,
                ),
              ),
              child: child,
            ),
          ),
          // Always mounted, so [trailing] animates both ways: it slides in from
          // the right edge while its slot opens, and slides back out while the
          // label takes the width back.
          //
          // The slot's width is what grows (the size transition), and the pill
          // is pinned to its right edge inside it and travels in from the right
          // over the top of that — clipped at the row's edge, so it reads as
          // coming out from the side rather than appearing in place.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 360),
            reverseDuration: const Duration(milliseconds: 240),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            layoutBuilder: (current, previous) =>
                Stack(alignment: Alignment.centerRight, children: [...previous, ?current]),
            transitionBuilder: (child, animation) => SizeTransition(
              sizeFactor: animation,
              axis: Axis.horizontal,
              alignment: Alignment.centerRight,
              child: SlideTransition(
                position: Tween<Offset>(begin: const Offset(0.6, 0), end: Offset.zero).animate(animation),
                child: FadeTransition(opacity: animation, child: child),
              ),
            ),
            child: trailing == null
                ? const SizedBox.shrink(key: ValueKey('noTrailing'))
                : Padding(
                    key: const ValueKey('trailing'),
                    padding: const EdgeInsets.only(left: 12),
                    child: trailing,
                  ),
          ),
        ],
      ),
    );
  }
}

/// A single calendar's filter chip in the shared header — same outline-ring
/// (1.5px inset) as the day circles. Shown above both week and month views.
///
/// The ring and the fill are the **app accent**, never the calendar's own
/// colour: which chip is selected is one piece of state for the whole row, and
/// a selection that changed hue per chip read as a second colour code fighting
/// the dot that is already saying which calendar this is.
/// The hairline between the to-do toggle and the person chips.
///
/// The one mark in the row that says the chip before it answers a different
/// question. Inset top and bottom so it reads as a separator rather than as a
/// very thin chip of its own.
class _ChipRowDivider extends StatelessWidget {
  const _ChipRowDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 10, bottom: 10),
      child: Container(width: 1, color: AppColors.hairline2),
    );
  }
}

/// "To-dos" — lays the Board's dated to-dos over the agenda.
///
/// **A toggle wearing a filter chip's clothes**, which is the one thing to be
/// careful about here. It borrows [_CalendarChip] so the row stays one row, but
/// it neither joins nor clears `calendarFilter`: tapping it turns to-dos on and
/// tapping it again turns them off, and whichever person is selected stays
/// selected throughout. The rule after it is what carries that difference —
/// see [_ChipRowDivider].
///
/// It carries the check the Board's create sheet puts on "To-do", not the Board
/// tab's grid: the chip stands for the things, not for the screen they live on.
class _TodosChip extends ConsumerWidget {
  final CalendarScreenState state;

  const _TodosChip({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _CalendarChip(
      label: L.s.todosChip,
      // Never drawn: a glyph is given, so the dot the colour would paint is not
      // built. Passed because the shell asks for one.
      color: AppColors.muted,
      active: state.showTasks,
      glyph: AppIcons.checkCircle,
      onTap: () => ref.read(calendarProvider.notifier).toggleTasks(),
    );
  }
}

class _CalendarChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool active;
  final VoidCallback onTap;

  /// Whether to draw the "there are calendars inside this one" caret. True on
  /// every group chip, down to one holding a single calendar: the chip names a
  /// person or the household, so the list is the only place that names the
  /// calendar under them. True on "Alle" too, whose list is every calendar in
  /// the row at once — see [_AllCalendarsChip].
  ///
  /// Not a tap target of its own. A caret that opened the list straight from an
  /// unselected chip put one account's calendars on screen while another
  /// account's chip was still the lit one; selecting is the first tap and
  /// opening the second, both of them [onTap]. See [_CalendarGroupChip].
  final bool hasList;

  /// True while some but not all of this account's calendars are showing. The
  /// dot goes hollow, which is the one piece of state the row can carry without
  /// a second line of text: a filled dot means the whole account.
  final bool partial;

  /// The person this chip stands for, drawn in place of the colour dot.
  ///
  /// The row is people now, and a face is what makes six of them scannable
  /// where six names are not — a parent picks their child's chip out of the row
  /// without reading it. Null on "Alle", which stands for nobody.
  final Widget? face;

  /// Drawn in place of the colour dot on a chip that stands for every calendar
  /// at once. "Alle" used to wear a grey dot, and a dot is a promise that
  /// there is a calendar of that colour — there is no "Alle" calendar, so the
  /// grey was the one dot in the row naming nothing. Two people say it instead.
  final IconData? glyph;

  const _CalendarChip({
    required this.label,
    required this.color,
    required this.active,
    required this.onTap,
    this.hasList = false,
    this.partial = false,
    this.face,
    this.glyph,
  });

  @override
  Widget build(BuildContext context) {
    return AppFilterChip(
      label: label,
      tone: active ? ChipTone.lit : ChipTone.muted,
      onTap: onTap,
      // A face sits close to the chip's edge the way an avatar does in a row; a
      // bare colour dot needs the full inset or it reads as debris, and a glyph
      // sits between the two.
      padding: EdgeInsets.only(
        left: face != null ? 5 : (glyph != null ? 11 : 14),
        right: hasList ? 8 : 14,
        top: face == null ? 8 : 5,
        bottom: face == null ? 8 : 5,
      ),
      // A face where the chip stands for somebody, the colour dot where it does
      // not. The two are the same width apart so the row does not jitter as
      // chips come and go.
      leading: switch ((face, glyph)) {
        (final Widget person?, _) => Padding(padding: const EdgeInsets.only(right: 7), child: person),
        (_, final IconData mark?) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: AppIcon(mark, size: 17, color: active ? AppColors.accent : AppColors.muted),
        ),
        _ => Padding(
          padding: const EdgeInsets.only(right: 7),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: partial ? Colors.transparent : color,
              shape: BoxShape.circle,
              border: partial ? Border.all(color: color, width: 1.5) : null,
            ),
          ),
        ),
      },
      // A mark rather than a control: the whole chip is one tap target, and
      // what that tap does depends on whether this chip is the lit one.
      trailing: hasList
          ? Padding(
              padding: const EdgeInsets.only(left: 3),
              child: SizedBox(
                width: 22,
                height: 22,
                child: AppIcon(AppIcons.caretDown, size: 14, color: active ? AppColors.ink : AppColors.muted),
              ),
            )
          : null,
    );
  }
}

/// What a chip is called.
///
/// **Anybody the household knows by a row of its own is named from that row,
/// not from the wire.** `calendar-events` does send a name — `ownerDirectory`
/// reads `families.name` and `profiles.display_name` — but that copy is only as
/// fresh as the last read, and it is written into the offline snapshot on the
/// way past. So somebody who renamed themselves in Settings, or an admin who
/// renamed the household, watched the chip keep the old name until something
/// happened to trigger a full re-read of every connected account: seconds of
/// network work, on somebody else's Google and iCloud, to learn a word the app
/// was already holding. The face beside the name came out of [familyProvider]
/// and changed at once, which made the stale half of the chip look like a bug
/// rather than a delay — because it is one.
///
/// That leaves the wire naming exactly what only it knows: a calendar of the
/// household's own, and a child with no account (`person:<Name>`), whose name
/// is typed on the connection rather than kept in a profile. It is also the
/// fallback for the moment before the household has loaded, which is the only
/// time this can't answer.
String _groupLabel(WidgetRef ref, CalendarGroup group) {
  if (group.isFamily) {
    final name = ref.watch(familyProvider.select((s) => s.household?.name))?.trim();
    return name == null || name.isEmpty ? group.name : name;
  }

  final memberId = group.ownerMemberId;
  if (memberId.isNotEmpty) {
    // `select` rather than a bare watch, so a chip row doesn't rebuild every
    // time an avatar URL is re-signed. Only this member's name is read.
    final name = ref
        .watch(
          familyProvider.select((s) {
            for (final m in s.members) {
              if (m.userId == memberId) return m.name;
            }
            return null;
          }),
        )
        ?.trim();
    if (name != null && name.isNotEmpty) return name;
  }

  return group.name;
}

/// The circle on a person's chip.
///
/// Three cases, in the order the wire spells them: a household member wears
/// their own picture (or their initials on their tone), the family chip wears
/// the household's picture, and a child with no account — most of them, since
/// members join by e-mail invitation — wears their initial on a tone derived
/// from the calendar's own colour, so their chip still reads as a person rather
/// than as the odd one out.
///
/// The hollow ring for a partial selection is kept: it is the one piece of
/// state the row carries without a second line of text, and it works over a
/// face as well as it worked over a dot.
Widget _groupFace(WidgetRef ref, CalendarGroup group, {required bool partial}) {
  final border = partial ? Border.all(color: group.color, width: 1.5) : null;
  // Big enough that a photograph is a face rather than a smudge. A 20pt circle
  // reads as a coloured dot on a phone held at arm's length, which defeats the
  // whole reason the row is people: a parent should pick their child's chip out
  // without reading it.
  const size = 26.0;

  if (group.isFamily) {
    final household = ref.watch(familyProvider).household;
    final tone = AppTones.list[(household?.tone ?? 0) % AppTones.list.length];
    return Avatar(
      size: size,
      bg: tone.bg,
      fg: tone.fg,
      initials: household?.initials ?? '?',
      fontSize: 11,
      border: border,
      imageUrl: household?.avatarUrl,
    );
  }

  if (group.ownerMemberId.isNotEmpty) {
    for (final m in ref.watch(householdMembersProvider)) {
      if (m.id != group.ownerMemberId) continue;
      final tone = AppTones.list[m.tone % AppTones.list.length];
      return Avatar(
        size: size,
        bg: tone.bg,
        fg: tone.fg,
        initials: m.initials,
        fontSize: 11,
        border: border,
        imageUrl: m.imageUrl,
      );
    }
  }

  // Somebody with no account. Their initial over the calendar's own colour,
  // which for a Stundenplan is the school's orange — so the chip is still a
  // face, and still tells you which of two children it is.
  final name = group.name.trim();
  return Avatar(
    size: size,
    bg: tint(group.color, .78),
    fg: group.color,
    initials: name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
    fontSize: 11,
    border: border,
  );
}

/// The "Alle" chip: tap to show everything, tap again to open the list and tick
/// calendars across accounts.
///
/// It wears the same caret every account chip wears, and for a stronger reason.
/// The rest of the row is one person each, so a filter built out of it is one
/// person — two people, or one child's Klausurplan beside the family calendar,
/// was expressible nowhere and the answer was to give up and show everything.
/// This chip stands for nobody in particular, so the selection that belongs to
/// nobody in particular hangs off it.
///
/// Stateful only to hold the [GlobalKey] the popup anchors to, exactly like
/// [_CalendarGroupChip].
class _AllCalendarsChip extends ConsumerStatefulWidget {
  final CalendarScreenState state;

  const _AllCalendarsChip({required this.state});

  @override
  ConsumerState<_AllCalendarsChip> createState() => _AllCalendarsChipState();
}

class _AllCalendarsChipState extends ConsumerState<_AllCalendarsChip> {
  final _anchorKey = GlobalKey();

  /// Every account's calendars at once, ticked one by one. The system's menu
  /// where there is one, the app's panel below — and this is the pair where
  /// the two are furthest apart in machinery and closest in behaviour: the
  /// rows **keep the menu open** (`keepsOpen` / `.keepsMenuPresented`) exactly
  /// as the route stays up, because picking three calendars out of eight is one
  /// gesture, not three. A tick here moves the others — untick one while "Alle"
  /// is lit and every remaining calendar becomes explicitly ticked — so each
  /// tap pushes the whole set back with [updateNativeMenuSelection] rather than
  /// trusting the row that was tapped to be the only one that changed.
  Future<void> _open() async {
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final anchor = box.localToGlobal(Offset.zero) & box.size;
    final notifier = ref.read(calendarProvider.notifier);

    // Index 0 is "Alle", which owns no calendar; every other row is one.
    final ids = <String?>[null];
    List<bool> statesOf() {
      final filter = ref.read(calendarProvider).calendarFilter;
      return [for (final id in ids) filter == null || (id != null && filter.contains(id))];
    }

    final options = <NativeMenuOption>[
      NativeMenuOption(
        L.s.all,
        symbol: 'person.2',
        selected: ref.read(calendarProvider).calendarFilter == null,
        keepsOpen: true,
      ),
    ];
    var section = 0;
    for (final group in ref.read(calendarProvider).activeGroups) {
      section++;
      final title = _groupLabel(ref, group);
      final filter = ref.read(calendarProvider).calendarFilter;
      for (final src in group.calendars) {
        ids.add(src.id);
        options.add(
          NativeMenuOption(
            src.name,
            color: src.color,
            section: section,
            sectionTitle: title,
            selected: filter == null || filter.contains(src.id),
            keepsOpen: true,
          ),
        );
      }
    }

    final picked = await showNativeMenu(
      anchor: anchor,
      options: options,
      cancelLabel: L.s.cancel,
      dark: AppColors.isDark,
      onKeptOpen: (index) {
        final id = ids[index];
        if (id == null) {
          notifier.clearCalendarFilter();
        } else {
          notifier.toggleCalendarAnywhere(id);
        }
        updateNativeMenuSelection(statesOf());
      },
    );
    // Every row keeps the menu up, so the only answer a system menu gives here
    // is "closed" — anything but null means it was the one that ran.
    if (picked != null) return;
    if (!mounted) return;

    pushDropdownRoute(
      context,
      _AllCalendarsPickerRoute(
        anchor: anchor,
        // The route stays open while the rows are ticked: picking three
        // calendars out of eight is one gesture, not three.
        onToggle: (id) => notifier.toggleCalendarAnywhere(id),
        onAll: () => notifier.clearCalendarFilter(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final filter = state.calendarFilter;
    final picked = state.filterGroupId == kPickedCalendarFilterId;
    // Lit while everything is showing *and* while a hand-picked set is, since
    // that set is this chip's own. An account chip owns the filter otherwise.
    final active = filter == null || picked;

    return KeyedSubtree(
      key: _anchorKey,
      child: _CalendarChip(
        // A chip reading "Alle" while three calendars are hidden would be
        // lying, so a hand-picked selection counts itself instead.
        label: picked ? L.s.calendarCount(filter?.length ?? 0) : L.s.all,
        color: AppColors.muted,
        active: active,
        glyph: AppIcons.users,
        // Unlike an account chip's, this list is never empty — the row itself
        // only exists once there are calendars to name.
        hasList: true,
        // Same two-tap shape as every other chip: the first tap selects, the
        // second opens what the caret has just promised. From an account chip
        // that first tap is what clears the filter, which is what "Alle" has
        // always meant.
        onTap: () {
          if (active) {
            _open();
          } else {
            ref.read(calendarProvider.notifier).clearCalendarFilter();
          }
        },
      ),
    );
  }
}

/// One account's chip: tap to show all of it, tap again — or hit the chevron —
/// to open the list and tick individual calendars.
///
/// Stateful only to hold the [GlobalKey] the popup anchors to. Everything it
/// renders comes from the state it is handed.
class _CalendarGroupChip extends ConsumerStatefulWidget {
  final CalendarScreenState state;
  final CalendarGroup group;

  const _CalendarGroupChip({required this.state, required this.group});

  @override
  ConsumerState<_CalendarGroupChip> createState() => _CalendarGroupChipState();
}

class _CalendarGroupChipState extends ConsumerState<_CalendarGroupChip> {
  final _anchorKey = GlobalKey();

  /// Which of this account's calendars are showing: all of them when there is
  /// no filter, and the intersection otherwise.
  Set<String> get _shown {
    final filter = widget.state.calendarFilter;
    return filter == null ? widget.group.ids : filter.intersection(widget.group.ids);
  }

  /// This account's calendars, ticked one by one — the same two-hands split as
  /// [_AllCalendarsChipState._open], and the same reason the rows keep the menu
  /// open: "show two of these three" is one trip.
  Future<void> _open() async {
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final anchor = box.localToGlobal(Offset.zero) & box.size;
    final group = widget.group;
    final notifier = ref.read(calendarProvider.notifier);

    // Read off the provider rather than [_shown], which reads the state this
    // widget was *built* with: a tick is pushed back to the open menu on the
    // same turn it happened, a frame before any rebuild, so the widget's own
    // copy is still the one from before the tap.
    List<bool> statesOf() {
      final filter = ref.read(calendarProvider).calendarFilter;
      final shown = filter == null ? group.ids : filter.intersection(group.ids);
      return [for (final src in group.calendars) shown.contains(src.id)];
    }

    final states = statesOf();
    final picked = await showNativeMenu(
      anchor: anchor,
      // The account's name over its calendars, as the panel prints it.
      title: _groupLabel(ref, group),
      options: [
        for (var i = 0; i < group.calendars.length; i++)
          NativeMenuOption(
            group.calendars[i].name,
            color: group.calendars[i].color,
            selected: states[i],
            keepsOpen: true,
          ),
      ],
      cancelLabel: L.s.cancel,
      dark: AppColors.isDark,
      onKeptOpen: (index) {
        notifier.toggleCalendarInGroup(group, group.calendars[index].id);
        updateNativeMenuSelection(statesOf());
      },
    );
    if (picked != null) return;
    if (!mounted) return;

    pushDropdownRoute(
      context,
      _CalendarPickerRoute(
        anchor: anchor,
        group: group,
        // The route stays open while the rows are ticked — a popup that closed
        // on the first tap would make "show two of these three" two trips.
        onToggle: (id) => notifier.toggleCalendarInGroup(group, id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final shown = _shown;
    // Which chip is lit is tracked rather than inferred: a selection narrowed
    // inside this chip's popup is a subset of its calendars and must keep it
    // lit, which an id-set comparison would not.
    final active = widget.state.filterGroupId == group.id;

    return KeyedSubtree(
      key: _anchorKey,
      child: _CalendarChip(
        label: _groupLabel(ref, group),
        color: group.color,
        active: active,
        partial: active && shown.length < group.calendars.length,
        face: _groupFace(ref, group, partial: active && shown.length < group.calendars.length),
        hasList: group.opensList,
        // The second tap on an already-selected account opens the list rather
        // than clearing the filter — which is what the caret beside it has
        // just promised. Clearing is what the "Alle" chip is for, and it is
        // always the first thing in the row. The caret is part of the same tap
        // target, so it never opens a list belonging to a chip that is not the
        // lit one.
        onTap: () {
          if (active && group.opensList) {
            _open();
          } else {
            ref.read(calendarProvider.notifier).filterToGroup(group);
          }
        },
      ),
    );
  }
}
