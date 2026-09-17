import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/board_data.dart';
import '../../data/calendar_data.dart';
import '../../l10n/l10n.dart';
import '../../models/calendar_event.dart';
import '../../state/board_state.dart';
import '../../state/calendar_state.dart';
import '../../state/nav_state.dart';
import '../../state/tracker_state.dart';
import '../../theme/app_icons.dart';
import '../../theme/tokens.dart';
import '../../widgets/status_island.dart';
import 'first_steps.dart';

/// Home's one-line status, in the slot above the filter chips that Kalender
/// fills with the month name.
///
/// **It says one thing, and it is always the most pressing thing about today.**
/// A row of counters would be a dashboard, and a dashboard is what the four
/// other tabs already are; what somebody wants from the top of Home is the
/// sentence they would have gone looking for. So the cases are a ladder and the
/// first match wins: setup, then overdue, then open, then unticked trackers,
/// then the next appointment, then the fact that there is nothing left.
///
/// **It is a heading with a glyph, not a badge.** The row of filter chips
/// directly under it is already a row of tinted capsules, and a tinted capsule
/// above them turned the top of the screen into three stacked badges with no
/// hierarchy left between them. The line reads as the title it replaced, and
/// the one thing it adds is the glyph — which is why the glyph has to name what
/// the sentence is about (a clock for the next appointment, a warning for
/// something overdue) rather than announce that the app is being clever.
///
/// **Every glyph here is ink, and [IslandLine] takes no colour at all.** It was
/// the accent on five of the seven states, which put a blue mark above a row of
/// blue chips saying nothing the words were not already saying — and the two
/// that kept a tone were worse than that. A red warning triangle at the top of
/// Home is the shape an app uses to report a fault, so one to-do past its date
/// read as something broken; the green beside it then made the pair look like a
/// status light for the household. The sentence says which of the seven this
/// is, and the sentence is what is being read.
///
/// **The ladder is about today, and only today.** A count of what is overdue
/// *now* printed above next Thursday's agenda is a sentence about a different
/// screen, so selecting another day drops all of it. What it does **not** do is
/// fall back to the generic "Dein Tag". **Nor does it name the date and count
/// the appointments** — it did, until the day card got a title that says
/// exactly that, and two lines a few centimetres apart then printed the same
/// sentence. What the island adds instead is the one thing the card cannot: how
/// far the selected day is from today ("In 3 Tagen"), and a tap back to it.
class DayIsland extends ConsumerWidget {
  const DayIsland({super.key});

  /// The fallback, and what every non-today selection shows.
  static Widget _plain() => Text(L.s.yourDay, key: const ValueKey('plain'), style: AppText.sectionHeading);

  /// The ladder, wrapped in the crossfade every island shares — see
  /// [StatusIsland], which is also why the keys below are on what `_line`
  /// builds rather than on this widget.
  @override
  Widget build(BuildContext context, WidgetRef ref) => StatusIsland(child: _line(context, ref));

  Widget _line(BuildContext context, WidgetRef ref) {
    final today = calToday();
    final sel = ref.watch(calendarProvider.select((s) => s.selected));
    if (sel.y != today.year || sel.m != today.month || sel.d != today.day) {
      // In UTC, so a clock change between the two days cannot make 3 days read
      // as 2 days and 23 hours.
      final offset = DateTime.utc(
        sel.y,
        sel.m,
        sel.d,
      ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
      return IslandLine(
        // One key for every date, so tapping along the strip changes the words
        // in place instead of playing a 400ms swap on each tap.
        key: const ValueKey('day'),
        // The same glyph Settings puts on "Kalender" — one mark for the
        // calendar wherever the app names it.
        icon: AppIcons.calendarDots,
        label: L.s.homeDayOffset(offset),
        hint: L.s.homeHintBackToToday,
        // The week view scrolls the strip to a selection it did not make.
        onTap: () => ref.read(calendarProvider.notifier).selectDayToday(),
        // No wave: the reader just tapped the day, so nothing here changed on
        // its own and there is nothing to point out.
        sweep: IslandSweep.none,
      );
    }

    // **Before it can say anything it says that it is working it out.**
    // Everything below reads three screens' worth of state that arrives over
    // the network, and the honest answer while they are out is not "Dein Tag"
    // — the app printing the old title and then quietly replacing it a second
    // later is a change nobody sees happen, which is exactly what made the
    // island feel like it was not doing anything. It is also the one line here
    // that is about the app rather than the household, which is why it is the
    // one place a brain belongs.
    final loading =
        !ref.watch(calendarProvider.select((s) => s.loaded)) ||
        ref.watch(boardProvider.select((s) => s.loading)) ||
        ref.watch(trackerProvider.select((s) => s.loading));
    if (loading) {
      return IslandLine(
        key: const ValueKey('thinking'),
        icon: AppIcons.brain,
        label: L.s.homeThinking,
        hint: L.s.homeHintThinking,
        // The one state that shimmers over and over: here the wave *is* the
        // spinner, and it stops the moment there is something to say.
        sweep: IslandSweep.loop,
      );
    }

    // Setup outranks everything below it. A household with no calendar
    // connected has nothing true to say about its day anyway, and the ladder
    // under this would print "Alles erledigt" over an empty app.
    final steps = ref.watch(firstStepsProvider);
    if (steps.isNotEmpty) {
      final open = ref.watch(firstStepsOpenProvider);
      return IslandLine(
        key: const ValueKey('setup'),
        // Footprints, because the thing being named is first steps. The
        // sparkle that was here first said "AI feature" and nothing else.
        icon: AppIcons.footprints,
        label: L.s.firstStepsTitle,
        hint: L.s.homeHintSetup,
        trailingLabel: L.s.firstStepsProgress(firstStepCount - steps.length, firstStepCount),
        expanded: open,
        onTap: () => ref.read(firstStepsOpenProvider.notifier).state = !open,
      );
    }

    final board = ref.watch(boardProvider);
    final onDeck = board.onDeck(today);
    var overdue = 0;
    var openToday = 0;
    for (final task in onDeck) {
      if (task.done) continue;
      if (task.dueDate case final due?) {
        if (boardDay(due).isBefore(today)) {
          overdue++;
        } else {
          openToday++;
        }
      }
    }

    void toBoard() => ref.read(tabJumpProvider.notifier).toTab(boardTabIndex);

    if (overdue > 0) {
      return IslandLine(
        key: const ValueKey('overdue'),
        icon: AppIcons.warning,
        label: L.s.homeOverdue(overdue),
        hint: L.s.homeHintOverdue,
        onTap: toBoard,
      );
    }
    if (openToday > 0) {
      return IslandLine(
        key: const ValueKey('open'),
        icon: AppIcons.checkCircle,
        label: L.s.homeOpenToday(openToday),
        hint: L.s.homeHintOpen,
        onTap: toBoard,
      );
    }

    final trackers = ref.watch(trackerProvider);
    final trackersLeft = [
      for (final t in trackers.dueOn(today))
        if (!trackers.isCheckedOn(t.id, today)) t,
    ].length;
    if (trackersLeft > 0) {
      return IslandLine(
        key: const ValueKey('trackers'),
        icon: AppIcons.circleDashed,
        label: L.s.homeTrackersLeft(trackersLeft),
        hint: L.s.homeHintTrackers,
        onTap: toBoard,
      );
    }

    // The next appointment still ahead. Not tappable: it is the first card in
    // the agenda four centimetres below, and a second way to reach the same
    // sheet from the same screen is a coin toss rather than a shortcut.
    //
    // Read off `DateTime.now()` with no clock of its own, so it settles on the
    // next rebuild rather than on a timer. The alternative is a ticker in the
    // header for a line that is only ever a few minutes stale.
    final next = _nextUp(ref.watch(calendarProvider), today);
    if (next != null) {
      return IslandLine(
        key: const ValueKey('next'),
        icon: AppIcons.clock,
        label: L.s.homeNextUp(formatTimeOfDay(next.startsAt.hour, next.startsAt.minute), next.title),
        hint: L.s.homeHintNext,
      );
    }

    // "Nothing left" is only worth saying where there was something. A day that
    // never had a to-do on it is not a day you finished.
    if (onDeck.isNotEmpty || trackers.dueOn(today).isNotEmpty) {
      return IslandLine(
        key: const ValueKey('done'),
        icon: AppIcons.checkCircle,
        label: L.s.homeAllDone,
        hint: L.s.homeHintDone,
      );
    }
    return _plain();
  }

  static CalendarEvent? _nextUp(CalendarScreenState state, DateTime today) {
    final now = DateTime.now();
    CalendarEvent? best;
    for (final event in state.eventsFor(today.year, today.month, today.day)) {
      if (event.allDay) continue;
      if (!event.startsAt.isAfter(now)) continue;
      if (best == null || event.startsAt.isBefore(best.startsAt)) best = event;
    }
    return best;
  }
}
