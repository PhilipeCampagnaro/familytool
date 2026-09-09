import 'package:flutter/material.dart';

import '../../data/board_data.dart';
import '../../data/calendar_data.dart';
import '../../data/tracker_data.dart';
import '../../models/tracker.dart';
import '../../theme/tokens.dart';
import '../../l10n/l10n.dart';

// The two charts on a tracker's own screen — one per kind of rhythm.
//
// Deliberately not the Board header's `BoardTrackerStrip`. That grid runs
// consecutive days in five rows with no weekday alignment, because it is an
// aggregate of every tracker the household keeps and a ragged last column would
// read as a chart that had stopped working. One tracker is a different picture:
// its rhythm *is* weekdays, so laying the days out in weekday rows is the whole
// point — a Montag/Donnerstag tracker draws two lit rows, and nothing else says
// that as quickly. A part week at the right-hand edge is fine here, because the
// weekday letters down the left explain why it is short.
//
// A weekly count gets bars instead, one per week. It owes nothing on any
// particular day, so a day grid of one would be a field of "nicht geplant" with
// ticks scattered through it — a picture of the wrong promise.

/// Squares and the space between them. The square is measured from what the
/// card leaves over, so the grid always lands flush against both edges; this is
/// only the size it aims for and the ceiling it will not grow past.
const double _gap = 4;
const double _targetCell = 15;
const double _maxCell = 20;

/// The weekday letters down the left, and the air between them and the grid.
const double _labelWidth = 14;
const double _labelGap = 7;

/// One tracker's days, in weekday rows with one column per week.
///
/// The right-hand column is the week today is in, so today is always the last
/// square drawn; the days after it in that column are simply absent, as are the
/// days before the tracker started in the first.
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

  /// The most weeks the loaded checks can honestly cover. A column older than
  /// the window would draw every day unticked whatever the database holds.
  static const _maxWeeks = trackerHistoryDays ~/ 7;

  @override
  Widget build(BuildContext context) {
    final thisWeek = trackerWeekStart(today);
    final firstWeek = trackerWeekStart(tracker.startsOn);
    // The tracker's own age, in whole weeks including the part one it started
    // in — there is nothing before it to draw.
    final lived = thisWeek.difference(firstWeek).inDays ~/ 7 + 1;

    return LayoutBuilder(
      builder: (context, constraints) {
        final grid = constraints.maxWidth - _labelWidth - _labelGap;
        // The cell is sized from however many columns *fit*, then the chart is
        // narrowed to however many it *has*. Sizing it from the second number
        // would blow a one-week-old tracker up into a row of tiles.
        final fits = ((grid + _gap) / (_targetCell + _gap)).floor().clamp(1, _maxWeeks);
        final cell = (((grid - (fits - 1) * _gap) / fits).clamp(6.0, _maxCell)).toDouble();
        final columns = fits < lived ? fits : lived;
        final first = boardDaysAfter(thisWeek, -(columns - 1) * 7);

        var kept = 0, due = 0;
        for (var i = 0; i < columns * 7; i++) {
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
            for (var row = 0; row < 7; row++) ...[
              if (row > 0) SizedBox(height: _gap),
              Row(
                children: [
                  SizedBox(
                    width: _labelWidth,
                    child: Text(
                      dayLetters[row],
                      textAlign: TextAlign.center,
                      style: AppText.microLabel.copyWith(color: AppColors.mutedLight),
                    ),
                  ),
                  SizedBox(width: _labelGap),
                  for (var column = 0; column < columns; column++) ...[
                    if (column > 0) SizedBox(width: _gap),
                    _DaySquare(
                      day: boardDaysAfter(first, column * 7 + row),
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
          ? null
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
      label: '${L.s.weekdayWithDateShort(day.weekday % 7, day.day, day.month)}: '
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
    final closed = [for (final r in records) if (r.monday != thisWeek) r];
    final hit = [for (final r in closed) if (r.done >= target) r].length;

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

  const _WeekRow({
    required this.record,
    required this.target,
    required this.accent,
    required this.isCurrent,
  });

  @override
  Widget build(BuildContext context) {
    final label = isCurrent
        ? L.s.sectionThisWeek
        : L.s.dayMonthShort(record.monday.day, record.monday.month);
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
              style: AppText.microLabel.copyWith(
                color: record.done >= target ? accent : AppColors.muted,
              ),
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
            final size = (((constraints.maxWidth - (days - 1) * _gapMin) / days)
                    .clamp(24.0, _maxDiameter))
                .toDouble();
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
        Text(
          L.s.trackerBackfillHint,
          style: AppText.microLabel.copyWith(color: AppColors.mutedLight),
        ),
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
        color: switch (mark) {
          TrackerDayMark.kept => accent,
          TrackerDayMark.missed => tint(accent, .82),
          TrackerDayMark.notDue => AppColors.hairline,
          // Before the tracker existed: no fill at all, the way the grid draws
          // nothing there. The date stays, or the week would lose its shape.
          TrackerDayMark.blank => Colors.transparent,
        },
        border: isToday ? Border.all(color: AppColors.ink, width: 1) : null,
      ),
      child: Text(
        '${day.day}',
        style: AppText.microLabel.copyWith(
          fontWeight: FontWeight.w600,
          color: switch (mark) {
            TrackerDayMark.kept => Colors.white,
            TrackerDayMark.missed => AppColors.ink,
            _ => AppColors.mutedLight,
          },
        ),
      ),
    );

    final labelled = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          dayLetters[day.weekday - 1],
          style: AppText.microLabel.copyWith(color: AppColors.mutedLight),
        ),
        const SizedBox(height: 6),
        circle,
      ],
    );

    // Seven days is few enough that every one of them is worth reading out,
    // pressable or not — unlike the grid, where labelling all seven rows would
    // mean stepping through months of squares to reach one.
    final spoken = '${L.s.weekdayWithDateShort(day.weekday % 7, day.day, day.month)}: '
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
