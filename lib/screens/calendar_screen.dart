import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../data/calendar_data.dart';
import '../data/german_holidays.dart';
import '../models/calendar_event.dart';
import '../models/event_link.dart';
import '../models/homework.dart';
import '../models/shopping_list.dart';
import '../models/task.dart';
import '../models/weather.dart';
import '../services/action_sheet.dart';
import '../services/external_links.dart';
import '../services/map_snapshot.dart';
import '../state/board_state.dart';
import '../state/calendar_state.dart';
import '../state/family_state.dart';
import '../state/holidays_state.dart';
import '../state/list_state.dart';
import '../state/nav_state.dart';
import '../state/weather_state.dart';
import '../theme/tokens.dart';
import '../widgets/anchored_menu.dart';
import '../widgets/app_sheet.dart';
import '../widgets/avatar.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/day_circle.dart';
import '../widgets/error_note.dart';
import '../widgets/event_dots.dart';
import '../widgets/floating_pill.dart';
import '../widgets/glass.dart';
import '../widgets/icon_picker.dart';
import '../widgets/native_switch.dart';
import '../widgets/settings_chrome.dart';
import '../widgets/swipe_actions.dart';
import '../widgets/toast_chip.dart';
import '../l10n/l10n.dart';
import 'board_screen.dart';
import 'calendar_connect_screen.dart';
import 'list_screen.dart';
import '../theme/app_icons.dart';

part 'calendar/event_form.dart';
part 'calendar/calendar_filter.dart';
part 'calendar/week_view.dart';
part 'calendar/month_view.dart';
part 'calendar/event_detail_sheet.dart';

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

/// The homework due in this lesson, for the badge on its card and the card in
/// its sheet.
///
/// Keyed on the event's provider `uid` rather than on its id: the id carries the
/// start time, and a lesson Untis moves keeps its uid while its id changes. The
/// map holds only lessons that actually carry homework, so this misses for
/// almost every event in the app and costs nothing when it does.
List<Homework> _homeworkFor(WidgetRef ref, CalendarEvent event) {
  if (event.uid.isEmpty) return const [];
  return ref.watch(calendarProvider.select((s) => s.homeworkByEvent))[event.uid] ?? const [];
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

class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(calendarProvider);
    final accent = Theme.of(context).colorScheme.primary;

    // A write that didn't land is reported once and then forgotten, so the same
    // message can appear again if the next attempt fails too. This matters more
    // here than anywhere else in the app: the sheet's save button closes the
    // sheet before the write to Google has finished, so without this a family
    // would walk away believing an appointment is in their calendar when it
    // never arrived.
    ref.listen<String?>(calendarProvider.select((s) => s.error), (_, message) {
      if (message == null) return;
      showErrorSnack(context, message);
      ref.read(calendarProvider.notifier).clearError();
    });

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: false,
        // Both views build their own header (title + month/toggle row) inside
        // a scroll-collapsing sliver-or-listener, so it can shrink as their
        // content scrolls — see _WeekView / _MonthView.
        child: _CompactNavOnScroll(
          child: state.isWeek ? _WeekView(state: state, accent: accent) : _MonthView(state: state, accent: accent),
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
    return NotificationListener<ScrollUpdateNotification>(
      onNotification: (n) {
        if (n.metrics.axis != Axis.vertical) return false;
        final nav = ref.read(navBarProvider.notifier);
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
    return AnimatedPositioned(
      duration: kNavSwapDuration,
      curve: Curves.easeInOutCubic,
      right: AppSpacing.screenPad,
      bottom: nav.compact
          ? navRowBottom(context, barHeight: nav.barHeight)
          : navContentInset(context, pill: 106, gap: 36),
      child: _JumpToTodayButton(visible: visible, accent: accent, onTap: onTap),
    );
  }
}

/// The screen's "Kalender" title + add button — always visible. [t] (0 =
/// expanded, 1 = fully collapsed) morphs the title from a large left-aligned
/// heading down to a small centered one, matching an iOS large-title nav bar
/// collapse. Both views drive it continuously from scroll offset (the week
/// view via [CollapsingSliverHeaderDelegate], the month view off its own
/// `ScrollController`).
class _TitleRow extends StatelessWidget {
  final double t;
  final VoidCallback onAdd;

  /// Optional control pinned to the far left, alongside the title — the
  /// calendar-filter dropdown lives here, and only while collapsed: it stands
  /// in for the [_ToggleAndChipsRow] chip row, which has scrolled away by
  /// then. See [_leadingOpacity].
  final Widget? leading;

  const _TitleRow({required this.t, required this.onAdd, this.leading});

  /// The filter dropdown duplicates the chip row, so it stays hidden until
  /// those chips are essentially gone — it fades in over the last 40% of the
  /// collapse rather than cross-fading against the control it replaces.
  double get _leadingOpacity => ((t - 0.6) / 0.4).clamp(0.0, 1.0);

  /// Horizontal breathing room reserved on both sides of the collapsed title.
  /// Both sides get the *same* inset at t == 1 even though the two flanking
  /// controls aren't the same width, because an asymmetric inset is exactly
  /// what knocks a centered title off-center — so this is the wider of them
  /// (the actions group) plus a gap.
  static const _collapsedSideInset = 108.0;

  /// What the title must clear on the right at rest: the actions group plus a
  /// gap. Kept in step with [GlassIconGroup.width] for the two actions below —
  /// 2 × 44 plus the capsule's end padding.
  static const _actionsSlot = 100.0;

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
                right: _actionsSlot + (_collapsedSideInset - _actionsSlot) * t,
              ),
              child: Align(
                alignment: Alignment.lerp(Alignment.centerLeft, Alignment.center, t)!,
                child: Text(
                  L.s.calendarTitle,
                  maxLines: 1,
                  style: AppText.screenTitle.copyWith(fontSize: 26 - 9 * t),
                ),
              ),
            ),
          ),
          // Both header actions in one glass capsule, iOS 26-style: connecting
          // a calendar is Kalender's own job, and burying it in Einstellungen
          // made a household walk through three screens to add the school's
          // link. It is a setup action, though, so it rides *beside* the daily
          // one rather than taking a button's worth of header for itself.
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: Center(
              child: GlassIconGroup(
                actions: [
                  GlassIconAction(
                    // Not the empty state's `calendarPlus`: beside a bare plus,
                    // two plus-bearing glyphs read as two ways to add the same
                    // thing. A link is what "verbinden" means anyway.
                    icon: AppIcons.link,
                    label: L.s.connectCalendars,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => CalendarConnectionsPage()),
                    ),
                  ),
                  GlassIconAction(icon: AppIcons.plus, label: L.s.addEvent, onTap: onAdd),
                ],
              ),
            ),
          ),
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

/// Identifies the filter chip row for tests. The day strip is a horizontal
/// `ListView` too, so "the horizontal list in the header" isn't specific enough
/// to find it by.
const calendarChipRowKey = ValueKey('calendarChipRow');

/// Identifies the week view's scrolling day strip for tests.
const calendarDayStripKey = ValueKey('calendarDayStrip');

/// Month/year label + list-vs-grid toggle, and the calendar filter chip row —
/// the part of the header that fades/shrinks away entirely as either view
/// collapses, at which point [_CalendarFilterButton] fades into the title row
/// to take the chips' place. Shared by both views so the two behave
/// identically.
class _ToggleAndChipsRow extends ConsumerWidget {
  final CalendarScreenState state;
  final Color accent;
  final String monthLabel;

  const _ToggleAndChipsRow({required this.state, required this.accent, required this.monthLabel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MonthYearToggleRow(state: state, accent: accent, monthLabel: monthLabel),
        const SizedBox(height: 14),
        SizedBox(
          // Tall enough for a 26pt face plus the chip's own padding and its
          // selected ring. The row is measured by the collapsing header rather
          // than assumed, so this is the only place the number lives.
          height: 44,
          child: ListView(
            key: calendarChipRowKey,
            scrollDirection: Axis.horizontal,
            children: [
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

/// Month/year label (crossfading as the visible month changes) + the
/// list-vs-grid view toggle — shared by the week view's full header
/// ([_ToggleAndChipsRow]) and the month view's own collapsing header.
class _MonthYearToggleRow extends StatelessWidget {
  final CalendarScreenState state;
  final Color accent;
  final String monthLabel;

  const _MonthYearToggleRow({required this.state, required this.accent, required this.monthLabel});

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero).animate(animation),
                  child: child,
                ),
              ),
              child: Text(monthLabel, key: ValueKey(monthLabel), style: AppText.sectionHeading),
            ),
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(20)),
              child: Row(
                children: [
                  _ViewToggleButton(icon: AppIcons.list, active: state.isWeek, accent: accent, onTap: () => ref.read(calendarProvider.notifier).setWeekView()),
                  _ViewToggleButton(icon: AppIcons.layout, active: !state.isWeek, accent: accent, onTap: () => ref.read(calendarProvider.notifier).setMonthView()),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ViewToggleButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  const _ViewToggleButton({required this.icon, required this.active, required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 34,
        decoration: BoxDecoration(
          color: active ? AppColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(17),
          boxShadow: active ? AppShadows.thumb : null,
        ),
        alignment: Alignment.center,
        child: AppIcon(icon, size: 17, color: active ? accent : AppColors.muted),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(27),
          border: Border.all(color: active ? AppColors.accent : Colors.transparent, width: 1.5),
        ),
        child: Container(
          // A face sits close to the chip's edge the way an avatar does in a
          // row; a bare colour dot needs the full inset or it reads as debris,
          // and a glyph sits between the two.
          padding: EdgeInsets.only(
            left: face != null ? 5 : (glyph != null ? 11 : 14),
            right: hasList ? 8 : 14,
            top: face == null ? 8 : 5,
            bottom: face == null ? 8 : 5,
          ),
          decoration: BoxDecoration(color: active ? tint(AppColors.accent, .82) : AppColors.surfaceAlt, borderRadius: BorderRadius.circular(24)),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // A face where the chip stands for somebody, the colour dot
              // where it does not. The two are the same width apart so the row
              // does not jitter as chips come and go.
              if (face != null) ...[
                face!,
                const SizedBox(width: 7),
              ] else if (glyph != null) ...[
                AppIcon(glyph!, size: 17, color: active ? AppColors.accent : AppColors.muted),
                const SizedBox(width: 6),
              ] else ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: partial ? Colors.transparent : color,
                    shape: BoxShape.circle,
                    border: partial ? Border.all(color: color, width: 1.5) : null,
                  ),
                ),
                const SizedBox(width: 7),
              ],
              Text(label, style: AppText.caption.copyWith(fontWeight: active ? FontWeight.w600 : FontWeight.w400, color: active ? AppColors.ink : AppColors.muted)),
              if (hasList) ...[
                const SizedBox(width: 3),
                // A mark rather than a control: the whole chip is one tap
                // target, and what that tap does depends on whether this chip
                // is the lit one.
                SizedBox(
                  width: 22,
                  height: 22,
                  child: AppIcon(
                    AppIcons.caretDown,
                    size: 14,
                    color: active ? AppColors.ink : AppColors.muted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
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
    final name = ref.watch(
      familyProvider.select((s) {
        for (final m in s.members) {
          if (m.userId == memberId) return m.name;
        }
        return null;
      }),
    )?.trim();
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

  void _open() {
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    Navigator.of(context).push(
      _AllCalendarsPickerRoute(
        anchor: box.localToGlobal(Offset.zero) & box.size,
        // The route stays open while the rows are ticked: picking three
        // calendars out of eight is one gesture, not three.
        onToggle: (id) => ref.read(calendarProvider.notifier).toggleCalendarAnywhere(id),
        onAll: () => ref.read(calendarProvider.notifier).clearCalendarFilter(),
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

  void _open() {
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    Navigator.of(context).push(
      _CalendarPickerRoute(
        anchor: box.localToGlobal(Offset.zero) & box.size,
        group: widget.group,
        // The route stays open while the rows are ticked — a popup that closed
        // on the first tap would make "show two of these three" two trips.
        onToggle: (id) => ref
            .read(calendarProvider.notifier)
            .toggleCalendarInGroup(widget.group, id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final shown = _shown;
    // Which chip is lit is tracked rather than inferred: filtering to a person
    // also brings the household's shared calendars in, so an id-set comparison
    // would light their chip and the family's together.
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
