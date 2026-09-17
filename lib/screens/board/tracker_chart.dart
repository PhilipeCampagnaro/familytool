import 'package:flutter/material.dart';

import '../../data/board_data.dart';
import '../../data/calendar_data.dart';
import '../../data/tracker_data.dart';
import '../../models/tracker.dart';
import '../../theme/app_icons.dart';
import '../../theme/tokens.dart';
import '../../l10n/l10n.dart';

// The two charts on a tracker's own screen — one per kind of rhythm.
//
// Read the way the Board header's `BoardTrackerStrip` reads — left to right,
// then down, oldest at the top and today in the last row — so the two grids are
// one gesture. Where it differs is weekday alignment: that grid is an aggregate
// of every tracker and runs days straight through, while one tracker's rhythm
// *is* weekdays, so each row here is one or more whole weeks under Mo–So
// letters. A Montag/Donnerstag tracker draws two lit columns, and nothing else
// says that as quickly. A part week at the end of the last row is fine, because
// the letters above explain why it is short.
//
// A weekly count gets bars instead, one per week. It owes nothing on any
// particular day, so a day grid of one would be a field of "nicht geplant" with
// ticks scattered through it — a picture of the wrong promise.

/// Squares and the space between them. The square is measured from what the
/// card leaves over, so the grid always lands flush against both edges; this is
/// only the size it aims for and the ceiling it will not grow past.
/// Close to the Board header's 10pt squares and 3pt gaps, so the chart is a
/// compact record — three weeks a row on a phone — rather than a board of
/// tiles. The seven-day circles above it are the thumb-sized way to back-fill.
const double _gap = 3;
const double _targetCell = 10;
// Room to grow past the target, so the squares stretch to fill the card rather
// than stopping short of it and leaving the air all on the right.
const double _maxCell = 18;

/// The weekday letters across the top, and the air between them and the grid.
const double _labelGap = 6;

/// One tracker's days, in rows of whole weeks read left to right.
///
/// Each row holds as many weeks as fit the card at a readable square — two on a
/// phone — with a little extra air between them so the week boundary shows. The
/// last row ends with the week today is in, so today is always in the bottom
/// row. Days after it, and days before the tracker started, are faint
/// placeholders, so the grid is always a full rectangle.
///
/// [onToggleDay] makes the squares pressable, which is the reason this chart
/// exists rather than a picture: forgetting to tick on the evening is the
/// ordinary failure, and a record nobody can correct stops being one anybody
/// trusts. Only days [canToggleTrackerOn] allows respond — see there for the
/// three bounds.
class TrackerDayChart extends StatelessWidget {
  final Tracker tracker;
  final Set<DateTime> checkedDays;
  final DateTime today;
  final Color accent;
  final ValueChanged<DateTime>? onToggleDay;

  /// Names the card. The tally beside it is the chart's own business: how many
  /// weeks fit is a layout answer, and a summary computed anywhere else would
  /// count days the grid is not drawing.
  final String title;

  const TrackerDayChart({
    super.key,
    required this.tracker,
    required this.checkedDays,
    required this.today,
    required this.accent,
    required this.title,
    this.onToggleDay,
  });

  /// The most weeks the loaded checks can honestly cover. A row older than the
  /// window would draw every day unticked whatever the database holds.
  static const _maxWeeks = trackerHistoryDays ~/ 7;

  /// Rows of weeks, always — the Board header's five, so the chart has the same
  /// shape from a tracker's first day as from its hundredth. Sizing it to the
  /// tracker's age drew a week-old one as a single strip, which read as a
  /// broken chart rather than as a young record.
  static const _rows = 5;

  @override
  Widget build(BuildContext context) {
    final thisWeek = trackerWeekStart(today);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // Whole weeks per row, from how many squares fit at the size the chart
        // aims for. Never a part week: a row that broke mid-week would put
        // Montag under Freitag in the row below it.
        final fits = ((width + _gap) / (_targetCell + _gap)).floor();
        final weeksPerRow = (fits ~/ 7).clamp(1, _maxWeeks);
        final perRow = weeksPerRow * 7;
        // One extra gap between neighbouring weeks, so the boundary reads.
        final gaps = (perRow - 1) * _gap + (weeksPerRow - 1) * _gap;
        final cell = (((width - gaps) / perRow).clamp(6.0, _maxCell)).toDouble();
        // Never more rows than the loaded window covers — an older day would
        // look unticked whatever the database holds.
        final rows = (_maxWeeks ~/ weeksPerRow).clamp(1, _rows);
        // The last row ends on this week, so a young tracker's earlier rows
        // start before it existed and draw those days as faint placeholders.
        final first = boardDaysAfter(thisWeek, -(rows * weeksPerRow - 1) * 7);

        Widget spacer(int column) => SizedBox(width: column % 7 == 0 ? _gap * 2 : _gap);

        var kept = 0, due = 0;
        for (var i = 0; i < rows * perRow; i++) {
          switch (trackerDayMark(tracker, checkedDays, boardDaysAfter(first, i), today)) {
            case TrackerDayMark.kept:
              kept++;
              due++;
            case TrackerDayMark.missed:
              due++;
            case TrackerDayMark.notDue:
            case TrackerDayMark.blank:
              break;
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ChartHeading(title: title, summary: L.s.trackerDaysDone(kept, due)),
            const SizedBox(height: 14),
            // Mo–So over each week of a row, so every column says which
            // weekday it is.
            Row(
              // Centred, like the rows under it: should a wide card hit the
              // square's ceiling, the leftover air splits evenly on both sides.
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var column = 0; column < perRow; column++) ...[
                  if (column > 0) spacer(column),
                  SizedBox(
                    width: cell,
                    child: Text(
                      dayLetters[column % 7],
                      textAlign: TextAlign.center,
                      style: AppText.microLabel.copyWith(color: AppColors.mutedLight),
                    ),
                  ),
                ],
              ],
            ),
            SizedBox(height: _labelGap),
            for (var row = 0; row < rows; row++) ...[
              if (row > 0) SizedBox(height: _gap),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var column = 0; column < perRow; column++) ...[
                    if (column > 0) spacer(column),
                    _DaySquare(
                      day: boardDaysAfter(first, row * perRow + column),
                      tracker: tracker,
                      checkedDays: checkedDays,
                      today: today,
                      accent: accent,
                      size: cell,
                      onToggleDay: onToggleDay,
                    ),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

/// One day. Four readings, on the same colour scale the Board header uses:
/// nothing at all outside the tracker's life, a neutral hairline for a day the
/// rhythm never asked for, the palest accent for one it asked for and did not
/// get, and the flat accent for one it got.
///
/// **"Nicht geplant" is neutral, never a pale accent.** A day off is not a day
/// failed, and a Montag/Donnerstag tracker would otherwise report five failures
/// every week of a perfect record.
class _DaySquare extends StatelessWidget {
  final DateTime day;
  final Tracker tracker;
  final Set<DateTime> checkedDays;
  final DateTime today;
  final Color accent;
  final double size;
  final ValueChanged<DateTime>? onToggleDay;

  const _DaySquare({
    required this.day,
    required this.tracker,
    required this.checkedDays,
    required this.today,
    required this.accent,
    required this.size,
    required this.onToggleDay,
  });

  @override
  Widget build(BuildContext context) {
    final mark = trackerDayMark(tracker, checkedDays, day, today);
    final tappable = onToggleDay != null && canToggleTrackerOn(tracker, day, today);

    final square = SizedBox(
      width: size,
      height: size,
      child: mark == TrackerDayMark.blank
          // Before the tracker started or after today: a faint square, so the
          // grid is always a full rectangle — a hole at the end of the last
          // row read as squares gone missing. Fainter than "nicht geplant",
          // because it is not a day of the rhythm at all, and today's outline
          // still says where the record stops.
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.hairline.withValues(alpha: .4),
                borderRadius: BorderRadius.circular(size * 0.3),
              ),
            )
          : AnimatedContainer(
              // The same 280ms the Board's progress bar slides in, so a day
              // filled here lands with the same weight as one ticked there.
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: switch (mark) {
                  TrackerDayMark.kept => accent,
                  TrackerDayMark.missed => tint(accent, .82),
                  _ => AppColors.hairline,
                },
                borderRadius: BorderRadius.circular(size * 0.3),
                // Today is outlined rather than recoloured or enlarged, so it
                // stays legible whether it is kept or still open and never
                // nudges the grid around it.
                border: day == boardDay(today) ? Border.all(color: AppColors.ink, width: 1) : null,
              ),
            ),
    );

    // Only the days that can be corrected are reachable by VoiceOver, and each
    // says its own date and state. Labelling all seven rows would mean stepping
    // through months of squares to find one; excluding the pressable ones would
    // put back-filling out of reach entirely, which is the one thing this chart
    // does that the Board's cannot.
    if (!tappable) return ExcludeSemantics(child: square);
    return Semantics(
      button: true,
      label:
          '${L.s.weekdayWithDateShort(day.weekday % 7, day.day, day.month)}: '
          '${mark == TrackerDayMark.kept ? L.s.trackerLegendKept : L.s.trackerLegendMissed}',
      child: GestureDetector(
        onTap: () => onToggleDay!(day),
        // Opaque so the whole square answers, including the transparent corners
        // the rounding leaves behind.
        behavior: HitTestBehavior.opaque,
        child: square,
      ),
    );
  }
}

/// A weekly-count tracker's record: one row per week, newest at the top.
///
/// Newest first because the top row is the week you can still do something
/// about — and it is the one the label names in words rather than by date.
///
/// Each row draws exactly [TrackerSchedule.target] segments and fills the ones
/// that were done, so "3 von 4" is legible before the number beside it is read.
/// A week that beat its target overfills the last segment rather than growing a
/// new one: the promise was four, and a bar longer than the others would read
/// as a different week rather than a better one.
class TrackerWeekChart extends StatelessWidget {
  final Tracker tracker;
  final Set<DateTime> checkedDays;
  final DateTime today;
  final Color accent;

  /// See [TrackerDayChart.title].
  final String title;

  /// How far back the rows go. A quarter: long enough to show a rhythm slipping,
  /// short enough that the card does not become the screen.
  static const weeks = 12;

  const TrackerWeekChart({
    super.key,
    required this.tracker,
    required this.checkedDays,
    required this.today,
    required this.accent,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final records = trackerWeekRecords(tracker, checkedDays, today, weeks: weeks);
    final target = tracker.schedule.target;
    final thisWeek = trackerWeekStart(today);
    // The live week is left out of the tally: it can still be finished, and
    // counting it as a miss on a Dienstag would make every current record look
    // one week worse than it is — the same rule [trackerStreak] follows.
    final closed = [
      for (final r in records)
        if (r.monday != thisWeek) r,
    ];
    final hit = [
      for (final r in closed)
        if (r.done >= target) r,
    ].length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ChartHeading(
          title: title,
          // A tracker made this week has no closed week to report on, and "0
          // von 0 Wochen" is not a fact about anything. It says how the week it
          // is in is going instead.
          summary: closed.isEmpty
              ? L.s.weekProgressLabel(records.isEmpty ? 0 : records.first.done, target)
              : L.s.trackerWeeksDone(hit, closed.length),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < records.length; i++) ...[
          if (i > 0) const SizedBox(height: 9),
          _WeekRow(
            record: records[i],
            target: target,
            accent: accent,
            isCurrent: records[i].monday == thisWeek,
          ),
        ],
      ],
    );
  }
}

class _WeekRow extends StatelessWidget {
  final TrackerWeekRecord record;
  final int target;
  final Color accent;
  final bool isCurrent;

  const _WeekRow({required this.record, required this.target, required this.accent, required this.isCurrent});

  @override
  Widget build(BuildContext context) {
    final label = isCurrent ? L.s.sectionThisWeek : L.s.dayMonthShort(record.monday.day, record.monday.month);
    final count = L.s.weekDoneOfTarget(record.done, target);

    return Semantics(
      label: '$label: $count',
      excludeSemantics: true,
      child: Row(
        children: [
          SizedBox(
            width: 74,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.label.copyWith(
                // The live week is the only one still able to change, so it is
                // the only one drawn in full ink.
                color: isCurrent ? AppColors.ink : AppColors.muted,
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                for (var i = 0; i < target; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOut,
                      height: 10,
                      decoration: BoxDecoration(
                        color: i < record.done ? accent : AppColors.hairline,
                        borderRadius: BorderRadius.circular(AppRadii.bar),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 48,
            child: Text(
              count,
              textAlign: TextAlign.right,
              maxLines: 1,
              style: AppText.microLabel.copyWith(color: record.done >= target ? accent : AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the three colours mean, spelled out under a day chart.
///
/// Colour on its own cannot separate "verpasst" from "nicht geplant" for
/// everybody who has to read it, and those two are exactly the pair a household
/// must not confuse — one is a gap in the record, the other is a day the rhythm
/// never asked about.
class TrackerChartLegend extends StatelessWidget {
  final Color accent;

  const TrackerChartLegend({super.key, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        _LegendItem(color: accent, label: L.s.trackerLegendKept),
        _LegendItem(color: tint(accent, .82), label: L.s.trackerLegendMissed),
        _LegendItem(color: AppColors.hairline, label: L.s.trackerLegendNotDue),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 5),
        Text(label, style: AppText.microLabel.copyWith(color: AppColors.mutedLight)),
      ],
    );
  }
}

/// A chart card's top line: what it is, and how it went. The tally sits on the
/// right in caption ink rather than under the chart, so the answer is readable
/// without reading the squares.
class _ChartHeading extends StatelessWidget {
  final String title;
  final String summary;

  const _ChartHeading({required this.title, required this.summary});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: AppText.groupHeading),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            summary,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption.copyWith(color: AppColors.muted),
          ),
        ),
      ],
    );
  }
}

/// The last seven days of one rhythm as small squares, oldest on the left and
/// today on the right — the strip beside a tracker's name on Home and on the
/// Board's tracker card. One widget for both, so a row reads as a tracker the
/// same way wherever it is: the squares, not just the title, say "rhythm".
///
/// **A week is as much history as a row can carry and still be read at a
/// glance**, and it is the span somebody actually asks about: whether the thing
/// is going well this week. The months of record live on the tracker's own
/// screen, where the chart is tall enough to be read rather than glanced at.
///
/// The three marks are the detail chart's, colour for colour, because they mean
/// exactly what they mean there — kept, asked for and missed, and a day the
/// rhythm never named. **The last of those is never drawn as a miss**: a
/// Montag/Donnerstag tracker with a perfect record would otherwise report five
/// failures a week. Days before the tracker existed leave their space empty
/// rather than filling it, so the strip starts where the tracker did without the
/// squares shifting under the ones beside them.
///
/// Not tappable. The row's own circle already ticks today, and back-filling a
/// day somebody forgot is the detail chart's job — a 9-point square on a
/// summary row is a mis-tap waiting to write a day nobody meant.
class TrackerWeekStrip extends StatelessWidget {
  final Tracker tracker;

  /// Every day this tracker was ticked. The whole set rather than the seven
  /// days it draws: the caller holds it already, and slicing it there would be
  /// a loop to save a loop.
  final Set<DateTime> checkedDays;
  final DateTime today;
  final Color accent;

  const TrackerWeekStrip({
    super.key,
    required this.tracker,
    required this.checkedDays,
    required this.today,
    required this.accent,
  });

  static const _days = 7;
  static const _size = 9.0;
  static const _gap = 4.0;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var back = _days - 1; back >= 0; back--) ...[
          if (back < _days - 1) const SizedBox(width: _gap),
          _mark(boardDaysAfter(today, -back)),
        ],
      ],
    );
  }

  Widget _mark(DateTime day) {
    final mark = trackerDayMark(tracker, checkedDays, day, today);
    if (mark == TrackerDayMark.blank) return const SizedBox(width: _size, height: _size);
    return AnimatedContainer(
      // The same 280ms the detail chart fills a square in, so today's square
      // lands with the same weight wherever it is ticked.
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        color: switch (mark) {
          TrackerDayMark.kept => accent,
          TrackerDayMark.missed => tint(accent, .82),
          _ => AppColors.hairline,
        },
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

/// The last seven days, one circle each, big enough to hit.
///
/// The quarter grid above it can already be back-filled, but its squares are
/// fifteen points wide in a field of a hundred: finding the right one is a
/// guess, and the neighbouring day is a wrong write. This is the same action at
/// a size a thumb can aim at, over the span people actually forget in — the
/// evening they ticked nothing, the weekend they only remember on Monday.
/// Anything older is what the grid is for.
///
/// It also carries **today's tick**, which is why there is no separate "Heute"
/// row on the screen any more: today is simply the last circle, outlined the way
/// the grid outlines it. Two controls writing the same day is one more than a
/// household needs.
///
/// Unlike the grid this is drawn for **both kinds of rhythm**. A weekly count
/// owes no particular day, so every day of its week is tappable here and none of
/// them is ever "verpasst" — which is exactly [canToggleTrackerOn] and
/// [trackerDayMark] answering as they already do, not a second rule.
class TrackerRecentDays extends StatelessWidget {
  final Tracker tracker;
  final Set<DateTime> checkedDays;
  final DateTime today;
  final Color accent;
  final ValueChanged<DateTime> onToggleDay;

  /// A week, ending today. Long enough to cover an ordinary lapse, short enough
  /// that seven circles still fit across a card at a real touch size.
  static const days = 7;

  const TrackerRecentDays({
    super.key,
    required this.tracker,
    required this.checkedDays,
    required this.today,
    required this.accent,
    required this.onToggleDay,
  });

  /// The circle aims for the width it is given and stops there — past it the
  /// seven days start to read as buttons rather than as a week.
  static const double _gapMin = 6;
  static const double _maxDiameter = 44;

  @override
  Widget build(BuildContext context) {
    final first = boardDaysAfter(today, -(days - 1));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(L.s.trackerBackfillTitle, style: AppText.groupHeading),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final size = (((constraints.maxWidth - (days - 1) * _gapMin) / days).clamp(
              24.0,
              _maxDiameter,
            )).toDouble();
            return Row(
              // Spread rather than gapped: once the circle hits its ceiling the
              // leftover width becomes air between the days, so the strip stays
              // flush with the card on a wide screen.
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < days; i++)
                  _DayChip(
                    day: boardDaysAfter(first, i),
                    tracker: tracker,
                    checkedDays: checkedDays,
                    today: today,
                    accent: accent,
                    size: size,
                    onToggleDay: onToggleDay,
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        Text(L.s.trackerBackfillHint, style: AppText.microLabel.copyWith(color: AppColors.mutedLight)),
      ],
    );
  }
}

/// One day of the strip: its weekday letter, and its date in a circle that
/// carries the state.
///
/// The four readings are [_DaySquare]'s, in the same colours — a day is not
/// allowed to mean one thing in the grid and another six inches above it.
class _DayChip extends StatelessWidget {
  final DateTime day;
  final Tracker tracker;
  final Set<DateTime> checkedDays;
  final DateTime today;
  final Color accent;
  final double size;
  final ValueChanged<DateTime> onToggleDay;

  const _DayChip({
    required this.day,
    required this.tracker,
    required this.checkedDays,
    required this.today,
    required this.accent,
    required this.size,
    required this.onToggleDay,
  });

  @override
  Widget build(BuildContext context) {
    final mark = trackerDayMark(tracker, checkedDays, day, today);
    final tappable = canToggleTrackerOn(tracker, day, today);
    final isToday = day == boardDay(today);
    final kept = mark == TrackerDayMark.kept;

    // Drawn as the Board's check circles rather than as the grid's squares,
    // because this strip is the control and the grid is the record. Filled
    // solid circles read as a finished picture — nothing about them said "tap".
    // So: a day that can still be ticked is an **empty accent ring**, the same
    // promise every unticked circle in the app makes; a ticked one is filled;
    // a day that cannot be ticked has no ring at all and steps back, so the
    // pressable ones are the only thing that looks pressable.
    final Color fill = kept ? accent : Colors.transparent;
    final Color? ring = kept
        ? (isToday ? AppColors.ink : null)
        : tappable
        ? accent
        : (mark == TrackerDayMark.blank ? null : AppColors.hairline);

    final circle = AnimatedContainer(
      // The grid's 280ms, so a day filled in here and a day filled in there
      // land with the same weight.
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        // Today's ring is the heavier one, whichever colour it is.
        border: ring == null ? null : Border.all(color: ring, width: isToday ? 2.5 : 1.5),
      ),
      child: kept
          ? AppIcon(AppIcons.check, flat: true, size: size * 0.42, color: Colors.white)
          : Text(
              '${day.day}',
              style: AppText.microLabel.copyWith(
                fontWeight: FontWeight.w600,
                color: tappable ? accent : AppColors.mutedLight,
              ),
            ),
    );

    final labelled = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(dayLetters[day.weekday - 1], style: AppText.microLabel.copyWith(color: AppColors.mutedLight)),
        const SizedBox(height: 6),
        circle,
      ],
    );

    // Seven days is few enough that every one of them is worth reading out,
    // pressable or not — unlike the grid, where labelling all seven rows would
    // mean stepping through months of squares to reach one.
    final spoken =
        '${L.s.weekdayWithDateShort(day.weekday % 7, day.day, day.month)}: '
        '${switch (mark) {
          TrackerDayMark.kept => L.s.trackerLegendKept,
          TrackerDayMark.missed => L.s.trackerLegendMissed,
          _ => L.s.trackerLegendNotDue,
        }}';

    if (!tappable) {
      return Semantics(label: spoken, excludeSemantics: true, child: labelled);
    }
    return Semantics(
      button: true,
      label: spoken,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => onToggleDay(day),
        behavior: HitTestBehavior.opaque,
        child: labelled,
      ),
    );
  }
}
