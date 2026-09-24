import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../theme/tokens.dart';

/// The mark under a day (week strip, month grid) saying what is on it: **one
/// filled stroke, three points longer per event, cut into a slice per event by
/// white dividers.**
///
/// It has been a row of coloured dots twice, and both times the row's own
/// growth is what broke it. Dots answer by repeating, so they need a cap to
/// stop them running out of the cell, and the cap is what stops them answering:
/// four appointments and eleven drew the same three dots, whether the rest was
/// said with a "+" after them or a rule under them. A stroke answers with its
/// *length* instead, and cutting it names the calendars inside that length —
/// so a quiet day is a short mark and a full day is a long one, which is read
/// at a glance rather than counted.
///
/// **The outer ends are round and the inner cuts are straight**, which is the
/// difference between one thing divided and several things in a row. The
/// dividers are the page's own white rather than a gap, because the stroke sits
/// on the grey day tile in the week strip and on the page in the month grid,
/// and a gap would be two different colours in the two places.
///
/// Slice order is the day's order, so the stroke reads left to right like the
/// agenda under it, and each slice carries its calendar's colour — the legend
/// above the grid ("Termine je Kalender") names exactly that.
class EventDots extends StatelessWidget {
  /// One per event, in the day's own order, each its calendar's colour —
  /// **uncapped**. How many slices the stroke is cut into is this widget's
  /// arithmetic rather than the caller's, because only the width knows.
  final List<Color> colors;

  /// Draws an empty ring ahead of the stroke: this day still owes a to-do.
  ///
  /// **A ring rather than a slice of the stroke, and deliberately colourless.**
  /// Every slice is a *calendar* of that colour, so a to-do taking one would
  /// claim to be a calendar the household hasn't got — and it would make the
  /// day look busier by one appointment, which is the one thing the stroke is
  /// for. The ring is the unticked circle the agenda card and the Board row
  /// already use for the same thing, shrunk to this band: it reads as an empty
  /// checkbox, which is what it is.
  ///
  /// First in the row, so a day carrying both starts with the thing that needs
  /// doing rather than ending with it.
  final bool todo;

  /// The ring's colour — the calendar's accent at the call sites that pass
  /// [todo]. Ignored otherwise.
  final Color? todoColor;

  const EventDots({super.key, required this.colors, this.todo = false, this.todoColor});

  /// The slot both cells reserve for this band, and the stroke drawn inside it.
  ///
  /// **The stroke is thinner than the first attempt at it** (4.5 where it was
  /// 6, in a 7-point band where it was 8). At 6 it was a bar under the date
  /// rather than a mark on it — close to the weight of the ink above it, so a
  /// month of busy days read as a grid of stripes with numbers in between. Thin
  /// enough and it goes back to being an annotation, which is all it was ever
  /// meant to be; the width is what carries the information, so nothing is lost
  /// by taking the height down.
  ///
  /// Both cells measure their own heights off [bandHeight] rather than writing
  /// a number down, so the month row's pitch and the strip's tile followed it
  /// without a single arithmetic edit.
  static const bandHeight = 7.0;
  static const barHeight = 4.5;

  /// **The width is the count.** One appointment is [_barMin], and every one
  /// after it adds [_barStep], to [barWidth] at the cap.
  ///
  /// It was one fixed 26-point field on every day, divided more finely as the
  /// day filled up — density carrying the count at a constant width. That reads
  /// beautifully in a column of busy Tuesdays and badly everywhere else, because
  /// **the commonest day in a family calendar has exactly one thing on it**, and
  /// it drew the widest mark the grid can hold. A month of single appointments
  /// was a page of full-length bars saying nothing the eye could sort. Length is
  /// also the easier comparison of the two: it is the one a bar chart makes, and
  /// it survives the glance that a three-way split of 26 points does not.
  ///
  /// The minimum is where a stroke still reads as a stroke — at 4.5 tall, 9
  /// points is twice as wide as it is high, which is a dash rather than either
  /// the to-do ring beside it or a dot. It was 11 first; the whole scale sits
  /// lower than that, because the quiet day is the one that wants the least ink
  /// and the busy day only has to be longer than it, not long.
  static const _barMin = 9.0;
  static const _barStep = 3.0;

  /// The longest the stroke ever gets, at the cap: 24 points, comfortably
  /// inside the ~26 a month cell (and the strip's tile, the narrower of the two)
  /// can hold beside a to-do ring. Derived, so moving [_barMin] or [_barStep]
  /// moves the ceiling with them instead of leaving a number behind.
  static const barWidth = _barMin + (_maxSlices - 1) * _barStep;

  /// The white cut between two slices. Held at 1.5 although the stroke got
  /// shorter: the cut's job is to separate, which is a question about its width
  /// and about how many slices have to fit, not about how tall the stroke is.
  /// Because the stroke grows by [_barStep] per slice, a slice is about 1.5
  /// points of colour plus the cut at every count rather than thinning as the
  /// day fills.
  static const _divider = 1.5;

  /// Where the stroke stops growing, and it is **geometry, not editorial**: the
  /// cell has about 26 points to give beside the to-do ring, and at [_barStep]
  /// each that is six slices with about 1.5 points of colour apiece. Past it the
  /// stroke shows six and says no more — there is no overflow mark, because a
  /// mark hung off the end is exactly what the stroke was for.
  ///
  /// The mark is therefore honest about the first six appointments and vague
  /// past them, which is the right way round: the difference between one and two
  /// is a decision about the day, and the difference between eight and nine is
  /// not.
  static const _maxSlices = 6;

  /// The ring keeps the 6 points it had as a dot, so it still reads as a
  /// circle beside a stroke that no longer is one.
  static const _ringSize = 6.0;
  static const _ringGap = 3.0;

  @override
  Widget build(BuildContext context) {
    final slices = colors.length > _maxSlices ? colors.take(_maxSlices).toList() : colors;
    if (slices.isEmpty && !todo) return const SizedBox.shrink();
    // Clamped as well as capped: the cap is what the count is trimmed to, and
    // this is the promise that nothing longer than [barWidth] ever reaches a
    // cell, whatever the two constants above are set to next.
    final width = (_barMin + (slices.length - 1) * _barStep).clamp(_barMin, barWidth);
    return SizedBox(
      height: bandHeight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (todo)
            Container(
              width: _ringSize,
              height: _ringSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // Thin enough to leave a hole at six points and thick enough to
                // still read as a stroke on a 2x screen.
                border: Border.all(color: todoColor ?? AppColors.ink, width: 1.4),
              ),
            ),
          if (todo && slices.isNotEmpty) const SizedBox(width: _ringGap),
          if (slices.isNotEmpty)
            CustomPaint(
              size: Size(width, barHeight),
              painter: _EventBar(colors: slices, divider: AppColors.surface),
            ),
        ],
      ),
    );
  }
}

/// The stroke itself: a capsule filled left to right, then cut.
///
/// The slices are painted edge to edge under a clip and the dividers laid over
/// the joins, rather than each slice being drawn inset. Inset slices leave the
/// page showing through the gaps, which is a different colour on the strip's
/// grey tile than in the month grid — and at a third of a point of rounding
/// error per slice, six of them stopped meeting the capsule's ends.
class _EventBar extends CustomPainter {
  final List<Color> colors;
  final Color divider;

  const _EventBar({required this.colors, required this.divider});

  @override
  void paint(Canvas canvas, Size size) {
    final capsule = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height / 2));
    canvas.save();
    canvas.clipRRect(capsule);
    final n = colors.length;
    final slice = size.width / n;
    final paint = Paint();
    for (var i = 0; i < n; i++) {
      // A hair of overlap, so neither the clip's edge nor the join between two
      // slices can land on a half pixel and show the page through it.
      canvas.drawRect(Rect.fromLTWH(i * slice - 0.5, 0, slice + 1, size.height), paint..color = colors[i]);
    }
    paint.color = divider;
    for (var i = 1; i < n; i++) {
      canvas.drawRect(
        Rect.fromLTWH(slice * i - EventDots._divider / 2, 0, EventDots._divider, size.height),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EventBar old) => old.divider != divider || !listEquals(old.colors, colors);
}
