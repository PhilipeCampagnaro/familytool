import 'package:flutter/material.dart';

import '../../data/board_data.dart';
import '../../services/board_streak_cache.dart';
import '../../theme/tokens.dart';
import '../../l10n/l10n.dart';

/// The Board header's habit grid: one small square per day, wrapping row by row,
/// darkening as more of that day's tasks were ticked off.
///
/// The progress bar under it reports on today; this reports on the months behind
/// it, which is the thing a single percentage can never show — whether the Board
/// is a habit or something the household remembers on Sundays. It reads like
/// text, left to right and then down, so the oldest day is the top left and
/// today is the last square of the last row.
///
/// **The caption sits in the grid's first row, not above it.** "Tracker" on a
/// line of its own put a second title under "Board" and cost the header a whole
/// row of height to say one word; run into the squares it names, it costs only
/// the handful of days it displaces — the grid starts where the word ends and
/// wraps underneath it. That is also why the days run in rows rather than down
/// columns: a column-major grid with a short first column would break the
/// reading order the caption sets up.
///
/// **Consecutive days, not weekday-aligned columns.** A week grid has a ragged
/// last column — on a Tuesday it draws two squares and five holes, which reads
/// as a chart that stopped working rather than as a week still in progress.
/// Running the days straight through means the grid is always a full rectangle
/// and today is always its last square, at the cost of a row standing for one
/// weekday. That pattern is worth less on this screen than a grid that always
/// looks finished — the Board's dates come from whenever a task happened to be
/// scheduled, not from a weekly rhythm.
///
/// Deliberately not a Kalender month view and deliberately not tappable: there
/// is no day to select on a Board whose dates live on the tasks, and a square
/// that looked pressable but did nothing would be worse than one that plainly
/// doesn't. The grid carries its meaning in colour and in nothing else, so it is
/// summarised for VoiceOver as a whole — see [AppStrings.trackerDaysDone] for
/// why not one label per square.
class BoardTrackerStrip extends StatelessWidget {
  final Map<DateTime, BoardDayTally> days;
  final DateTime today;
  final Color accent;

  /// Rows of days. Five rather than seven because the grid no longer stands for
  /// weeks — it is the height that keeps it a chart rather than a strip, and two
  /// rows of header are worth more to the screen than two more weeks of history.
  static const _rows = 5;

  /// Never more columns than [BoardStreakCache.retentionDays] keeps. A day older
  /// than the ledger could only ever be blank, and a wall of empty squares would
  /// read as months of failure rather than as no record.
  static const _maxColumns = BoardStreakCache.retentionDays ~/ _rows;

  /// The least clear air between the caption and the first square of the row it
  /// runs into. The slot is rounded up to a whole column from here, so the real
  /// distance is this or more, anywhere up to a column further — where exactly
  /// it lands depends on how close the word ends to a column boundary, which is
  /// a translation and a font scale away from being a different answer. Both
  /// ends of that range read as a caption with a grid after it; that is the
  /// property worth holding, not an exact gap.
  static const _captionGap = 6.0;

  /// The square, and the gap the column count is worked out from. Both are the
  /// smallest that still read as a grid rather than as noise; the real gap is
  /// measured from the width left over, so the columns always land flush.
  static const _cell = 10.0;
  static const _gap = 3.0;

  /// Roughly the whole grid's height: the rows, plus the few points the caption
  /// is taller than a square. The real gap is measured, so this is within a
  /// couple of points either way — good enough for the header's first-frame
  /// estimate, which is re-measured anyway, and not something to lay anything
  /// out against.
  static const height = _rows * _cell + (_rows - 1) * _gap + 6;

  const BoardTrackerStrip({
    super.key,
    required this.days,
    required this.today,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final caption = L.s.trackerTitle;

    // Tracked out from the token's own 0.3. Two things at once: it is the usual
    // treatment for a caption sitting on top of something rather than above it,
    // and it lets the word take up more of the column it has to round up to —
    // the leftover air in front of the first square was the whole of that
    // column, and is now about half of it.
    final captionStyle = AppText.groupHeading.copyWith(letterSpacing: 1);

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = ((constraints.maxWidth + _gap) / (_cell + _gap)).floor().clamp(1, _maxColumns);

        // Measured from what the squares leave behind, so a phone gets a tight
        // grid and an iPad-width header a slightly airier one — but bounded, or
        // a wide header would space the columns out into a dot pattern.
        final gap = columns > 1
            ? ((constraints.maxWidth - columns * _cell) / (columns - 1)).clamp(2.0, 5.0)
            : 0.0;

        // How many columns the caption eats out of the first row. Measured
        // rather than guessed: "Tracker" is a different width in every font
        // scale, and a translation is a different width again — a hardcoded
        // indent would either overlap the squares or leave a gap in the row.
        final painter = TextPainter(
          text: TextSpan(text: caption, style: captionStyle),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        // [_captionGap] before the round-up, so the square after the caption is
        // always at least that far from it. Rounding up the bare word instead
        // wins the row one more day and is not worth it: "Tracker" ends about a
        // point short of a column boundary, so the square it buys lands against
        // the "r".
        final lead = ((painter.width + _captionGap) / (_cell + gap)).ceil().clamp(0, columns);

        // The first row is as tall as the caption; the squares in it are centred
        // against the word. The gap under that row gives back what the extra
        // height added, so square-to-square spacing stays even down the grid.
        final firstRow = painter.height > _cell ? painter.height : _cell;
        final underFirst = (gap - (firstRow - _cell) / 2).clamp(0.0, gap);

        // Today is the last square drawn, so the grid ends in the corner however
        // many columns fit and however wide the caption turned out.
        final span = columns * _rows - lead;
        final first = boardDaysAfter(today, -(span - 1));

        var done = 0, tracked = 0;
        for (var i = 0; i < span; i++) {
          final tally = days[boardDaysAfter(first, i)] ?? const BoardDayTally();
          if (tally.isEmpty) continue;
          tracked++;
          if (tally.complete) done++;
        }

        // Row 0 runs from the caption's last column; every row after it is full.
        Widget row(int r) {
          final from = r == 0 ? lead : 0;
          final before = r == 0 ? (columns - lead) : (columns - lead) + (r - 1) * columns;
          final cells = <Widget>[
            if (r == 0)
              SizedBox(
                // The caption's slot is a whole number of columns wide, so the
                // squares beside it land on the same grid as the rows below.
                width: lead * (_cell + gap),
                child: Text(caption, style: captionStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
          ];
          for (var c = from; c < columns; c++) {
            if (c > from) cells.add(SizedBox(width: gap));
            final day = boardDaysAfter(first, r == 0 ? c - lead : before + c);
            cells.add(
              _TrackerCell(
                tally: days[day] ?? const BoardDayTally(),
                isToday: day == today,
                accent: accent,
              ),
            );
          }
          return Row(mainAxisSize: MainAxisSize.min, children: cells);
        }

        return Semantics(
          label: '$caption: ${L.s.trackerDaysDone(done, tracked)}',
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var r = 0; r < _rows; r++) ...[
                if (r == 1) SizedBox(height: underFirst) else if (r > 1) SizedBox(height: gap),
                r == 0 ? SizedBox(height: firstRow, child: row(0)) : row(r),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _TrackerCell extends StatelessWidget {
  final BoardDayTally tally;
  final bool isToday;
  final Color accent;

  const _TrackerCell({required this.tally, required this.isToday, required this.accent});

  @override
  Widget build(BuildContext context) {
    final square = BoxDecoration(
      color: _fill,
      borderRadius: BorderRadius.circular(BoardTrackerStrip._cell * 0.3),
      // Today is outlined rather than enlarged or recoloured, so it stays
      // legible whether the day is finished (accent under an ink hairline) or
      // untouched (an empty outlined box), and never nudges the grid around it.
      border: isToday ? Border.all(color: AppColors.ink, width: 1) : null,
    );

    // Only today's square is animated: it is the one that changes while the
    // Board is on screen, and a couple of hundred implicit animations to fade in
    // a history that never moves would cost a frame for nothing.
    if (!isToday) {
      return Container(
        width: BoardTrackerStrip._cell,
        height: BoardTrackerStrip._cell,
        decoration: square,
      );
    }
    return AnimatedContainer(
      // The same 280ms the progress bar slides in, so ticking off the last task
      // of the day fills the square and the bar together.
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      width: BoardTrackerStrip._cell,
      height: BoardTrackerStrip._cell,
      decoration: square,
    );
  }

  /// Four readings, in one colour scale:
  ///
  /// * nothing planned — a neutral hairline square. **Not the palest accent**: a
  ///   day off is not a day failed, and a family that plans nothing at the
  ///   weekend should not see two red-ish gaps in every row.
  /// * planned, none done — the palest accent, so the day is visibly *on* the
  ///   grid and visibly empty.
  /// * partly done — the wash lerped toward the accent by the ratio.
  /// * all done — the accent, flat, the same colour the progress bar fills with.
  Color get _fill {
    if (tally.isEmpty) return AppColors.hairline;
    if (tally.complete) return accent;
    return Color.lerp(tint(accent, .82), accent, tally.ratio * 0.85)!;
  }
}
