import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/spend_analysis.dart';
import '../../l10n/l10n.dart';
import '../../models/spend.dart';
import '../../theme/tokens.dart';

/// The three drawings on the Spend page, hand-painted.
///
/// **Still no chart package, and now for a stronger reason than "two shapes".**
/// The design these follow is specific down to the dashed average line, the
/// rounded arc gaps, the comparison line that runs past where this year has got
/// to and the callout that labels the point it stopped at. Bending a package's
/// axes, tooltips and type scale into that is more code than painting it, and
/// every default that leaked through would be the one part of the app that came
/// from somewhere else. `CustomPainter` draws exactly what the design asks for
/// and nothing else.
///
/// **Nothing here may be `const`-constructed.** Every widget reads `AppColors`
/// or `AppSpendColors` inside `build`, so a `const` instance would keep painting
/// the palette it was born with and stay dark in a light app until a hot reload
/// — see `tool/check_const_palette.dart`.

/// Which of the three is on screen.
///
/// Three views of one range rather than three cards down a page: they answer
/// different questions about the same money — where it is heading, what the
/// rhythm is, and what it went on — and stacking all three made the page a
/// scroll nobody reached the bottom of. They are swiped between, under a row of
/// dots; see `_AnalysisBlock`.
enum SpendChart {
  trend,
  bars,
  ring;

  /// Never drawn: a drawing is its own label to anybody who can see it. This is
  /// what VoiceOver reads instead, where the page is otherwise three unnamed
  /// pictures with a row of dots under them.
  String get label => switch (this) {
    SpendChart.trend => L.s.spendChartTrend,
    SpendChart.bars => L.s.spendChartBars,
    SpendChart.ring => L.s.spendChartRing,
  };
}

/// How tall every chart on the page is. One number, so switching between them
/// does not move the slicer underneath.
const double spendChartHeight = 188;

/// Draws a chart **on**, from nothing, whenever the data behind it is replaced.
///
/// **A chart that is swapped out is a chart nobody watched change.** The range
/// slicer sits directly under the drawing, so every tap on it is a reader
/// asking "and what does that look like" — and the old picture blinking into a
/// new one answers without ever showing the two as the same quantity measured
/// over a different stretch. Sweeping the new one on from the left says which
/// way time runs in it, which is the one thing all three drawings have in
/// common.
///
/// It fires on the subtree being **built**, not on a value changing: the caller
/// keys the chart on the range and the metric, so a new key is a new state and
/// a new state starts at nothing. Scrubbing, turning the pager and the head
/// pulse all rebuild the same element and leave it where it was — a reveal that
/// replayed every time a finger moved would be a chart that never settles.
class ChartReveal extends StatelessWidget {
  final Widget Function(BuildContext context, double t) builder;

  const ChartReveal({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    // "Bewegung reduzieren" gets the finished drawing, immediately.
    if (MediaQuery.disableAnimationsOf(context)) return builder(context, 1);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => builder(context, t),
    );
  }
}

/// Room under the plot for the axis labels, and to the right of it for the
/// value callouts.
const double _axisStrip = 20;
const double _labelGap = 8;

// ---------------------------------------------------------------------------
// The trend line
// ---------------------------------------------------------------------------

/// The money spent so far, climbing, with the stretch before it behind in grey.
///
/// **Cumulative rather than per-bucket**, which is the whole point of having it
/// beside the bars: the question this answers is "are we ahead of last month",
/// and that is a race between two lines rather than a comparison of thirty pairs
/// of bars. The grey line runs the full width because last month is over; the
/// red one stops where the month has got to, and the callout names the figure it
/// stopped at.
class SpendTrendChart extends StatefulWidget {
  final SpendSummary summary;
  final double height;

  /// Which bucket the finger is on, and how it says so. See [ChartScrub].
  final int? scrub;
  final ValueChanged<int?> onScrub;

  /// A monthly budget drawn across the plot, or null. Only meaningful when the
  /// line is one calendar month climbing towards it; the card decides.
  final int? budgetCents;

  const SpendTrendChart({
    super.key,
    required this.summary,
    required this.onScrub,
    this.scrub,
    this.height = spendChartHeight,
    this.budgetCents,
  });

  @override
  State<SpendTrendChart> createState() => _SpendTrendChartState();
}

class _SpendTrendChartState extends State<SpendTrendChart> with SingleTickerProviderStateMixin {
  /// **The head of the line pulses, and it is the only thing on the page that
  /// moves on its own.** The point it stops at is "now" — the money as it
  /// stands this second, with the rest of the stretch still to come — and a
  /// ring breathing out of it says that where a static dot said "the data ends
  /// here". Slow, because it is a heartbeat and not a spinner: anything quicker
  /// reads as something loading.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Off where the phone asks for it. A ring expanding for ever at the top of
    // a page is exactly what "Bewegung reduzieren" is for, and the chart says
    // everything it has to say without it.
    final still = MediaQuery.disableAnimationsOf(context);
    final summary = widget.summary;
    final current = summary.cumulative;
    final previous = summary.previousCumulative;
    final currency = spendCurrency(summary.rows);

    // Measured here rather than inside the painter so the gesture and the
    // drawing agree on where the plot ends: a finger halfway along a plot the
    // painter thinks is forty points wider lands on the wrong day.
    final gutter = math.max(_endLabelWidth(current, currency), _endLabelWidth(previous, currency));

    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, box) {
          final plot = _plotWidth(box.maxWidth, gutter);
          return ChartScrub(
            // The line's points are its *edges*, evenly spaced across the whole
            // plot, so the nearest one is a rounding rather than a division —
            // and it never reaches past where the line itself stops.
            indexAt: (dx) => current.length < 2
                ? null
                : ((dx / plot) * (summary.buckets.length - 1)).round().clamp(0, current.length - 1),
            // The same two ways in as the bars — see [ChartScrub]. A point is
            // smaller than a bar, but the tap picks the nearest one rather than
            // the ink under the finger, so there is nothing to miss.
            tapToSelect: true,
            scrub: widget.scrub,
            onScrub: widget.onScrub,
            child: ChartReveal(
              builder: (context, reveal) => AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) => CustomPaint(
                  size: Size.infinite,
                  painter: _TrendPainter(
                    reveal: reveal,
                    current: current,
                    previous: previous,
                    buckets: summary.buckets,
                    gutter: gutter,
                    line: AppColors.accent,
                    past: AppColors.mutedLight,
                    pastInk: AppColors.muted,
                    axisInk: AppColors.muted,
                    surface: AppColors.surface,
                    currency: currency,
                    budget: widget.budgetCents,
                    budgetInk: AppColors.danger,
                    scrub: widget.scrub,
                    // The ring is noise beside a finger that is already
                    // pointing at something.
                    pulse: still || widget.scrub != null ? null : _pulse.value,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  /// How much of the drawing to show, 0 to 1 — see [ChartReveal]. It is a clip
  /// across the width rather than a scale on the values: the numbers a chart
  /// prints are never half-true on the way in, they are simply not there yet.
  final double reveal;

  final List<int> current;
  final List<int> previous;
  final List<SpendBucket> buckets;
  final double gutter;
  final Color line;
  final Color past;
  final Color pastInk;
  final Color axisInk;

  /// The card behind the chart, for the ring that lifts the scrub dot off the
  /// line it is sitting on.
  final Color surface;

  final String currency;

  /// Which bucket the finger is on, if one is.
  final int? scrub;

  /// Where the ring around the head of the line is in its cycle, 0 to 1. Null
  /// when the phone has asked for less movement, or when a finger is on the
  /// chart and the ring would be noise beside it.
  final double? pulse;

  /// The budget, if one is drawn — see [SpendTrendChart.budgetCents].
  final int? budget;
  final Color budgetInk;

  const _TrendPainter({
    required this.budget,
    required this.budgetInk,
    required this.reveal,
    required this.current,
    required this.previous,
    required this.buckets,
    required this.gutter,
    required this.line,
    required this.past,
    required this.pastInk,
    required this.axisInk,
    required this.surface,
    required this.currency,
    required this.scrub,
    required this.pulse,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (reveal >= 1) return _paint(canvas, size);
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * reveal, size.height));
    _paint(canvas, size);
    canvas.restore();
  }

  void _paint(Canvas canvas, Size size) {
    if (buckets.isEmpty) return;

    final currentEnd = current.isEmpty ? 0 : current.last;
    final previousEnd = previous.isEmpty ? 0 : previous.last;

    final currentLabel = currentEnd == 0
        ? null
        : _text(formatMoneyCompact(currentEnd, currency: currency), line);
    final previousLabel = previousEnd == 0
        ? null
        : _text(formatMoneyCompact(previousEnd, currency: currency), pastInk);

    final plot = Rect.fromLTWH(
      0,
      6,
      _plotWidth(size.width, gutter),
      math.max(size.height - _axisStrip - 6, 20),
    );

    // Both lines share one scale or the race between them is a lie. Nothing is
    // added on top: the taller line ending exactly at the plot's ceiling is
    // what makes the two figures beside it readable as a pair.
    // The budget shares the scale too, or a line well under it would be drawn
    // as if it had already blown through it.
    final peak = math.max(math.max(currentEnd, previousEnd), budget ?? 0);
    double y(int cents) => peak == 0 ? plot.bottom : plot.bottom - plot.height * (cents / peak);

    // The x of bucket [i], with the *whole* range across the plot — so the
    // shorter of the two stretches (February against January) still finishes at
    // the right-hand edge rather than stopping short of it.
    double xOf(int index, int count) =>
        count <= 1 ? plot.right : plot.left + plot.width * (index / (count - 1));

    _axis(canvas, plot, size);

    if (budget case final goal? when goal > 0) {
      _paintBudgetLine(canvas, plot, y(goal), goal, budgetInk, currency);
    }

    if (previous.length > 1) {
      final path = Path();
      for (var i = 0; i < previous.length; i++) {
        final point = Offset(xOf(i, previous.length), y(previous[i]));
        i == 0 ? path.moveTo(point.dx, point.dy) : path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = past,
      );
    }

    Offset? head;
    if (current.isNotEmpty) {
      final points = [for (var i = 0; i < current.length; i++) Offset(xOf(i, buckets.length), y(current[i]))];
      head = points.last;

      // A single elapsed bucket is a dot and no line — a month on its first day
      // has one reading, and a horizontal stub would claim a trend it has not
      // got yet.
      if (points.length > 1) {
        final path = Path()..moveTo(points.first.dx, points.first.dy);
        for (final point in points.skip(1)) {
          path.lineTo(point.dx, point.dy);
        }

        // The wash under the line stops where the line does, so the shape reads
        // as "this much so far" rather than as a filled area that ran out.
        final fill = Path.from(path)
          ..lineTo(points.last.dx, plot.bottom)
          ..lineTo(points.first.dx, plot.bottom)
          ..close();
        canvas.drawPath(
          fill,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [line.withValues(alpha: .22), line.withValues(alpha: 0)],
            ).createShader(Rect.fromLTRB(plot.left, plot.top, plot.right, plot.bottom)),
        );

        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = line,
        );
      }

      // The finger's own point: a rule down the plot so the eye can drop to the
      // date under it, and a dot ringed in the card's colour so it reads as
      // sitting *on* the line rather than as a kink in it. The figure it names
      // is in the headline above — a bubble here would cover the very stretch
      // of line the reader is dragging along.
      if (scrub case final at? when at < points.length) {
        final point = points[at];
        canvas.drawLine(
          Offset(point.dx, plot.top),
          Offset(point.dx, plot.bottom),
          Paint()
            ..color = line.withValues(alpha: .3)
            ..strokeWidth = 1.5,
        );
        canvas.drawCircle(point, 7, Paint()..color = surface);
        canvas.drawCircle(point, 5, Paint()..color = line);
      }
    }

    // The callout: a dotted rule from the head of the line to its own figure,
    // because the head is rarely at the right-hand edge and a number floating
    // there with nothing joining it to the line is a number about nothing.
    if (head != null && currentEnd > 0 && scrub == null) {
      _dashed(
        canvas,
        Offset(head.dx + 10, head.dy),
        Offset(plot.right, head.dy),
        line.withValues(alpha: .45),
      );
      if (pulse case final at?) {
        // Out and gone: the ring grows on an ease-out so it leaves quickly and
        // arrives slowly, and it fades to nothing by the end of the cycle so
        // the restart is invisible rather than a blink.
        final t = Curves.easeOut.transform(at);
        canvas.drawCircle(head, 5 + 13 * t, Paint()..color = line.withValues(alpha: .28 * (1 - t)));
      }
      canvas.drawCircle(head, 9, Paint()..color = line.withValues(alpha: .18));
      canvas.drawCircle(head, 4.5, Paint()..color = line);
    }

    _labels(
      canvas,
      plot,
      size,
      // While a finger is down the headline is saying what that point is worth,
      // and this label would be a second, different figure beside it.
      scrub == null ? currentLabel : null,
      head?.dy,
      previousLabel,
      previous.isEmpty ? null : y(previousEnd),
    );
  }

  /// The two figures at the right-hand edge, pushed apart when the stretches
  /// finished close enough together to overprint each other.
  void _labels(
    Canvas canvas,
    Rect plot,
    Size size,
    TextPainter? current,
    double? currentY,
    TextPainter? previous,
    double? previousY,
  ) {
    var top = currentY;
    var bottom = previousY;
    if (top != null && bottom != null && current != null && (top - bottom).abs() < 15) {
      // Whichever is the higher line keeps the higher label, so the pair never
      // reads as the smaller figure belonging to the taller line.
      final apart = (15 - (top - bottom).abs()) / 2;
      final currentIsAbove = top <= bottom;
      top += currentIsAbove ? -apart : apart;
      bottom += currentIsAbove ? apart : -apart;
    }

    void draw(TextPainter? painter, double? at) {
      if (painter == null || at == null) return;
      final y = (at - painter.height / 2).clamp(0.0, size.height - _axisStrip - painter.height);
      painter.paint(canvas, Offset(size.width - painter.width, y));
    }

    draw(current, top);
    draw(previous, bottom);
  }

  /// Six labels at most, first and last always among them, so the axis says
  /// where the line starts and where it ends without printing thirty days.
  void _axis(Canvas canvas, Rect plot, Size size) {
    for (final (index, text) in axisTicks(buckets)) {
      final painter = _text(text, axisInk, size: 11);
      final centre = buckets.length <= 1
          ? plot.center.dx
          : plot.left + plot.width * (index / (buckets.length - 1));
      final x = (centre - painter.width / 2).clamp(0.0, size.width - painter.width);
      painter.paint(canvas, Offset(x, size.height - _axisStrip + 4));
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.reveal != reveal ||
      old.current != current ||
      old.previous != previous ||
      old.buckets != buckets ||
      old.line != line ||
      old.gutter != gutter ||
      old.scrub != scrub ||
      old.pulse != pulse ||
      old.budget != budget;
}

// ---------------------------------------------------------------------------
// The bars
// ---------------------------------------------------------------------------

/// Every bucket of the range as a bar, including the ones nothing was spent in,
/// with the average across them drawn through.
///
/// The empty buckets are the point. A chart that squeezes them out shows a tidy
/// row of similar bars and hides the thing worth seeing — that a household
/// spends on Saturdays, or that the month front-loaded and went quiet. The
/// buckets that have not happened yet are a different thing again and are drawn
/// as nothing at all: an empty December in September is not a December nobody
/// spent anything in.
class SpendBarsChart extends StatelessWidget {
  final SpendSummary summary;
  final double height;

  /// Which bucket the finger is on, and how it says so. See [ChartScrub].
  final int? scrub;
  final ValueChanged<int?> onScrub;

  /// A monthly budget drawn across the plot, or null. Only meaningful when every
  /// bar is a month; the card decides.
  final int? budgetCents;

  const SpendBarsChart({
    super.key,
    required this.summary,
    required this.onScrub,
    this.scrub,
    this.height = spendChartHeight,
    this.budgetCents,
  });

  @override
  Widget build(BuildContext context) {
    final currency = spendCurrency(summary.rows);
    final peak = summary.peakBucketCents;
    final average = summary.averagePerUnitCents;
    final empty = peak <= 1;

    // Measured here rather than inside the painter so the gesture and the
    // drawing agree on where the plot ends — see [SpendTrendChart].
    final gutter = math.max(
      empty ? 0.0 : _text(formatMoneyCompact(peak, currency: currency), AppColors.muted, size: 11).width,
      average == 0
          ? 0.0
          : _text(formatMoneyCompact(average, currency: currency), AppColors.ink, size: 11).width,
    );

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, box) {
          final plot = _plotWidth(box.maxWidth, gutter);
          final slot = plot / math.max(summary.buckets.length, 1);
          return ChartScrub(
            // A bar owns a *slot*, not a point, so this divides rather than
            // rounds: the finger is on whichever bar it is over.
            indexAt: (dx) =>
                summary.buckets.isEmpty ? null : (dx / slot).floor().clamp(0, summary.buckets.length - 1),
            // A bar is a target the finger can hit, so it is tapped rather than
            // held — see [ChartScrub].
            tapToSelect: true,
            scrub: scrub,
            onScrub: onScrub,
            child: ChartReveal(
              builder: (context, reveal) => CustomPaint(
                size: Size.infinite,
                painter: _BarsPainter(
                  reveal: reveal,
                  buckets: summary.buckets,
                  peak: peak,
                  average: average,
                  gutter: gutter,
                  // The same accent the trend line is drawn in: one colour for
                  // "this is the money", whichever way it is being drawn.
                  bar: AppColors.accent,
                  // And the app's ink for the average through them, because the
                  // line has to be legible *over* the bars — a dashed accent
                  // rule across accent bars is a rule nobody can see. It is the
                  // colour the bars themselves used to be, so the chart still
                  // has the same two marks in it, the other way round.
                  averageInk: AppColors.ink,
                  grid: AppColors.hairline,
                  gridInk: AppColors.muted,
                  axisInk: AppColors.muted,
                  currency: currency,
                  scrub: scrub,
                  budget: budgetCents,
                  budgetInk: AppColors.danger,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  /// How much of the drawing to show, 0 to 1 — see [ChartReveal]. It is a clip
  /// across the width rather than a scale on the values: the numbers a chart
  /// prints are never half-true on the way in, they are simply not there yet.
  final double reveal;

  final List<SpendBucket> buckets;
  final int peak;
  final int average;
  final double gutter;
  final Color bar;
  final Color averageInk;
  final Color grid;
  final Color gridInk;
  final Color axisInk;
  final String currency;
  final int? scrub;

  const _BarsPainter({
    required this.reveal,
    required this.buckets,
    required this.peak,
    required this.average,
    required this.gutter,
    required this.bar,
    required this.averageInk,
    required this.grid,
    required this.gridInk,
    required this.axisInk,
    required this.currency,
    required this.scrub,
    required this.budget,
    required this.budgetInk,
  });

  /// The budget, if one is drawn — see [SpendBarsChart.budgetCents].
  final int? budget;
  final Color budgetInk;

  @override
  void paint(Canvas canvas, Size size) {
    if (reveal >= 1) return _paint(canvas, size);
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * reveal, size.height));
    _paint(canvas, size);
    canvas.restore();
  }

  void _paint(Canvas canvas, Size size) {
    if (buckets.isEmpty) return;

    // A range with nothing in it gets the baseline and its dates and no
    // ceiling: `peakBucketCents` floors at one cent so callers can divide by
    // it, and a gridline labelled "0" is that guard leaking onto the screen.
    final empty = peak <= 1;
    final peakLabel = empty ? null : _text(formatMoneyCompact(peak, currency: currency), gridInk, size: 11);
    final averageLabel = average == 0
        ? null
        : _text(formatMoneyCompact(average, currency: currency), averageInk, size: 11);

    final plot = Rect.fromLTWH(
      0,
      6,
      _plotWidth(size.width, gutter),
      math.max(size.height - _axisStrip - 6, 20),
    );

    // A budget above every bar raises the scale to it, so the bars stand where
    // they really are against it; the ceiling label still names the tallest bar.
    final scale = math.max(peak, budget ?? 0);
    double y(int cents) => scale == 0 ? plot.bottom : plot.bottom - plot.height * (cents / scale);

    // The ceiling is the tallest bar itself rather than a rounded-up axis
    // maximum: the gridline then labels a figure the household actually spent
    // in one month instead of a number picked to make the arithmetic tidy.
    if (peakLabel != null) {
      final top = y(peak);
      _dashed(canvas, Offset(plot.left, top), Offset(plot.right, top), grid, dash: 4, gap: 4);
      peakLabel.paint(canvas, Offset(size.width - peakLabel.width, top - peakLabel.height / 2));
    }

    canvas.drawRect(Rect.fromLTWH(plot.left, plot.bottom, plot.width, 1), Paint()..color = grid);

    final slot = plot.width / buckets.length;
    final width = math.min(slot * .62, 18.0);
    final radius = Radius.circular(math.min(width / 2, 5));

    for (var i = 0; i < buckets.length; i++) {
      final bucket = buckets[i];
      if (bucket.isFuture || bucket.cents == 0) continue;

      final left = plot.left + i * slot + (slot - width) / 2;
      // Floored at the bar's own width so the smallest real bucket is still a
      // rounded mark rather than a smear.
      final top = math.min(y(bucket.cents), plot.bottom - width);
      canvas.drawRRect(
        RRect.fromLTRBAndCorners(left, top, left + width, plot.bottom, topLeft: radius, topRight: radius),
        // The bar under the finger goes to ink and the rest stay accent.
        // Dimming the others was the alternative and it made the chart flinch
        // every time somebody put a finger on it; one bar changing colour is
        // the smallest thing that can say "this one".
        Paint()..color = i == scrub ? averageInk : bar,
      );
    }

    if (budget case final goal? when goal > 0) {
      _paintBudgetLine(canvas, plot, y(goal), goal, budgetInk, currency);
    }

    if (averageLabel != null && !empty && average < peak) {
      final at = y(average);
      _dashed(canvas, Offset(plot.left, at), Offset(plot.right, at), averageInk, dash: 5, gap: 4);
      averageLabel.paint(canvas, Offset(size.width - averageLabel.width, at - averageLabel.height / 2));
    }

    for (final (index, text) in axisTicks(buckets, everyBar: true)) {
      final painter = _text(text, index == scrub ? averageInk : axisInk, size: 11);
      final centre = plot.left + index * slot + slot / 2;
      final x = (centre - painter.width / 2).clamp(0.0, size.width - painter.width);
      painter.paint(canvas, Offset(x, size.height - _axisStrip + 4));
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.reveal != reveal ||
      old.buckets != buckets ||
      old.peak != peak ||
      old.average != average ||
      old.gutter != gutter ||
      old.bar != bar ||
      old.scrub != scrub ||
      old.budget != budget;
}

// ---------------------------------------------------------------------------
// The ring
// ---------------------------------------------------------------------------

/// How many categories get a colour of their own before the rest fold into one
/// grey slice — so five arcs at most, the last of them "Sonstige".
///
/// It was seven, which is what the palette has coloured slots for, and seven is
/// past where a ring stops being read as a picture and starts being read as a
/// table with extra steps: the eye matches four colours to four names and gives
/// up somewhere after that. The ones that folded away are not lost — the card
/// below has an "alle anzeigen" that lists every last one.
const _maxSlices = 4;

/// The range's categories as a ring, with whatever the caller puts in the hole.
///
/// A donut rather than a pie: the hole is where the number goes, and the one
/// question everybody asks first is "how much altogether". A pie would need that
/// number somewhere else and make the reader's eye do the joining. The centre is
/// a [child] rather than drawn here because on this page it holds the control
/// that changes what is being counted.
class SpendCategoryRing extends StatelessWidget {
  final SpendSummary summary;

  /// Diameter. The stroke scales with it, so one number sizes the whole thing.
  final double size;

  final Widget? center;

  /// Which arc has been tapped, if one has, and how it says so. The selected
  /// arc keeps its colour and the rest stand back, because the question a tap
  /// asks is "what is *that* one" and every answer that keeps all eight arcs at
  /// full strength makes the reader find it again themselves.
  final int? selected;
  final ValueChanged<int?> onTapSlice;

  const SpendCategoryRing({
    super.key,
    required this.summary,
    required this.onTapSlice,
    this.size = 220,
    this.center,
    this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final slices = ringSlices(summary);
    final stroke = size * _strokeRatio;

    return SizedBox(
      width: size,
      height: size,
      child: GestureDetector(
        // Only the band itself, not the hole and not the corners of the box:
        // the hole holds the answer, and a tap there that changed the answer
        // would be a tap nobody aimed.
        onTapUp: (details) => onTapSlice(_sliceAt(details.localPosition, slices, stroke)),
        child: ChartReveal(
          builder: (context, reveal) => CustomPaint(
            painter: _RingPainter(
              reveal: reveal,
              slices: slices,
              track: AppColors.hairline,
              stroke: stroke,
              selected: selected,
            ),
            child: Center(
              child: Padding(
                // The hole, not the square it fits in: text run to the edge of
                // the box would sit under the arcs at the corners.
                padding: EdgeInsets.symmetric(horizontal: size * .21),
                child: center,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Which arc a tap landed on, or null for a tap that missed the band.
  ///
  /// Answering null for the arc already selected is deliberate: a second tap on
  /// the same slice puts the ring back the way it was, which is the only way
  /// out that does not need a control of its own.
  int? _sliceAt(Offset at, List<RingSlice> slices, double stroke) {
    if (slices.isEmpty) return null;

    final centre = Offset(size / 2, size / 2);
    final offset = at - centre;
    final radius = offset.distance;
    // The band, with a few points of slack either side — a ring is a thin
    // target and a finger is not a pixel.
    if (radius < size / 2 - stroke - 9 || radius > size / 2 + 9) return null;

    // Clockwise from twelve, which is where the first arc starts.
    var angle = math.atan2(offset.dy, offset.dx) + math.pi / 2;
    if (angle < 0) angle += math.pi * 2;
    final turn = angle / (math.pi * 2);

    var walked = 0.0;
    for (var i = 0; i < slices.length; i++) {
      walked += slices[i].share;
      if (turn <= walked) return i == selected ? null : i;
    }
    // Rounding can leave a sliver past the last arc's end.
    return slices.length - 1 == selected ? null : slices.length - 1;
  }
}

/// How thick the band is, as a fraction of the diameter. Thin enough that the
/// hole is a place to put an answer rather than a gap left over, thick enough
/// that a rounded end reads as a rounded end.
const _strokeRatio = 0.086;

/// One arc, and one row of the card under it: a colour, a glyph, a name, what
/// it came to and how many payments it took.
class RingSlice {
  final String label;
  final Color color;
  final IconData icon;
  final int cents;
  final int count;
  final double share;

  const RingSlice({
    required this.label,
    required this.color,
    required this.icon,
    required this.cents,
    required this.count,
    required this.share,
  });
}

/// The ring's arcs **and** the card's rows — one list, so the drawing and the
/// list under it can never disagree about what folded into "Sonstige".
List<RingSlice> ringSlices(SpendSummary summary) {
  final byCategory = summary.byCategory;
  if (byCategory.isEmpty) return const [];

  // **One left over is named, not folded.** Folding a single category into
  // "Sonstige" hides a name to save nothing: the row is there either way, and
  // the reader loses the one thing it was for. So the fold starts at two.
  final keep = byCategory.length <= _maxSlices + 1 ? byCategory.length : _maxSlices;
  final shown = byCategory.take(keep).toList();
  final rest = byCategory.skip(keep);

  final slices = [
    for (final slice in shown)
      RingSlice(
        label: slice.key.label,
        // By the category's own position in the enum, never by its rank this
        // month — so a category keeps its colour when two stretches are
        // compared.
        color: AppSpendColors.forCategory(slice.key.index),
        icon: slice.key.icon,
        cents: slice.cents,
        count: slice.count,
        share: slice.share,
      ),
  ];

  if (rest.isNotEmpty) {
    var cents = 0;
    var count = 0;
    var share = 0.0;
    for (final slice in rest) {
      cents += slice.cents;
      count += slice.count;
      share += slice.share;
    }
    slices.add(
      RingSlice(
        label: L.s.spendOtherCategories,
        color: AppSpendColors.rest,
        // The `other` category's own glyph: whatever folded in here, this row
        // means the same thing that one does.
        icon: SpendCategory.other.icon,
        cents: cents,
        count: count,
        share: share,
      ),
    );
  }

  return slices;
}

class _RingPainter extends CustomPainter {
  /// How far round the ring has been drawn, 0 to 1 — see [ChartReveal]. The
  /// arcs grow clockwise out of twelve o'clock in the order they are listed,
  /// which is the order of the card underneath: the biggest one is what appears
  /// first, and the reader is reading the answer before the drawing has
  /// finished.
  final double reveal;

  final List<RingSlice> slices;
  final Color track;
  final double stroke;
  final int? selected;

  const _RingPainter({
    required this.reveal,
    required this.slices,
    required this.track,
    required this.stroke,
    required this.selected,
  });

  /// How much daylight is left between two arcs once their caps are accounted
  /// for, as a fraction of the stroke. A quarter of a thin band is a few points
  /// — enough that the parting reads as deliberate, small enough that the ring
  /// still reads as one ring cut up rather than as five separate strokes.
  static const _parting = 0.25;

  /// The gap between two arcs, in radians.
  ///
  /// **A fixed number could not do this, because the thing being cleared is not
  /// fixed.** A round cap sticks out past the arc's own end by half the stroke,
  /// which at this radius is about a seventh of a radian — so any constant
  /// small enough to read as a small gap had the two caps either side of a join
  /// growing into each other, and the join came out as a bulge rather than as a
  /// parting. Taking the cap's own angle off the geometry is what puts the two
  /// caps exactly touching; [_parting] is the daylight added on top of that, so
  /// the gap on screen is the gap that was asked for at every size the ring is
  /// ever drawn at.
  double _gapFor(double radius) => radius <= 0 ? 0 : stroke * (1 + _parting) / radius;

  @override
  void paint(Canvas canvas, Size size) {
    // Inset by the cap as well as by half the stroke: a round cap sticks out
    // beyond the arc's own end, and without the room the first and last arcs
    // were clipped flat against the edge of the box.
    final inset = stroke / 2;
    final rect = Rect.fromLTWH(inset, inset, size.width - stroke, size.height - stroke);
    final gap = _gapFor(math.min(rect.width, rect.height) / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    // **The track is only ever drawn when there is nothing to draw over it.**
    // The arcs always add up to the whole circle, so a ring underneath them was
    // a grey line showing through the partings — which read as a fifth
    // colourless slice laid across all of them rather than as the gaps it was
    // filling. What it is still for is an empty range: a ring with no arcs has
    // to be a ring, not a blank square.
    if (slices.isEmpty) {
      canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
      return;
    }

    // Twelve o'clock, clockwise — where a reader expects a total to start.
    var angle = -math.pi / 2;
    for (var i = 0; i < slices.length; i++) {
      final slice = slices[i];
      final sweep = math.pi * 2 * slice.share * reveal;
      // A slice thinner than its own gaps would render as nothing, or worse as
      // a backwards arc. Floor it at a visible tick instead of dropping it:
      // "€2 on Elektronik" is a true thing the ring should still show. **Not
      // while the ring is growing**, though: a floor applied to five arcs that
      // are all still at nothing is five dots stacked at twelve o'clock.
      final drawn = reveal >= 1 ? math.max(sweep - gap, 0.02) : sweep - gap;
      if (drawn <= 0) {
        angle += sweep;
        continue;
      }
      final dim = selected != null && selected != i;
      canvas.drawArc(
        rect,
        angle + gap / 2,
        drawn,
        false,
        paint..color = dim ? slice.color.withValues(alpha: .22) : slice.color,
      );
      angle += sweep;
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.reveal != reveal ||
      old.slices != slices ||
      old.track != track ||
      old.stroke != stroke ||
      old.selected != selected;
}

// ---------------------------------------------------------------------------
// A horizontal share bar
// ---------------------------------------------------------------------------

/// For the merchant and member breakdowns.
///
/// Bars rather than a second ring: these lists are ranked, and length down a
/// column is the one encoding a reader compares accurately without a legend.
class SpendShareBar extends StatelessWidget {
  final double share;
  final Color color;
  final double height;

  const SpendShareBar({super.key, required this.share, required this.color, this.height = 6});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: LinearProgressIndicator(
          // Never fully zero: a merchant on the list spent *something*, and an
          // empty track beside their name reads as a rendering failure.
          value: share.clamp(0.02, 1.0),
          backgroundColor: AppColors.hairline,
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reading a value off a chart
// ---------------------------------------------------------------------------

/// Read a value off a chart: the bucket that is picked is reported up and the
/// headline says what it is worth.
///
/// **A bar is tapped and a line is held, because a bar is a thing and a line is
/// a stretch.** Bars stand apart with air between them, so one of them is a
/// target the finger can hit — asking for a press and a wait to hit it is a
/// toll on the obvious gesture. A line has no targets on it at all: every point
/// of it is as good as the one beside it, so the only way to read a day off it
/// is to put a finger down and slide until the callout says the day you wanted.
///
/// **Press and hold, not touch and drag, and that is not a compromise.** The
/// charts live in a pager — a horizontal drag on one of them is the gesture
/// that turns to the next chart, and a scrubber that stole it would leave the
/// pager unusable. A long press is what iOS's own charts take for the same
/// reason, and it is the only gesture here that cannot be started by accident
/// while scrolling the page. A tap can't be either, so both charts take both:
/// tap a bucket to pick it, or hold and slide across them.
///
/// **The line took only the hold once, and that was the wrong half of it.** A
/// reader who taps a day on it got nothing back and read that as a chart that
/// does not answer, rather than as one asking to be held — so the two drawings
/// of the same figures now take the same two gestures.
///
/// **A picked reading stays until it is picked away**, held or tapped: a tap is
/// a choice rather than a finger passing through, and a slide that ends on a
/// bucket is the same choice made the other way. It goes on a second tap of the
/// bucket already picked. The pager clears it when the page turns: a reading
/// belongs to the drawing it was taken off.
class ChartScrub extends StatelessWidget {
  /// The bucket at a local x inside the plot, or null where there is nothing to
  /// read. Each chart answers this differently — a line has points and bars
  /// have slots — which is why it is the caller's function and not a number.
  final int? Function(double dx) indexAt;

  /// Whether a plain tap picks a bucket and leaves it picked. Off, the only way
  /// in is the long press and the reading goes on release. Both spend charts
  /// pass it; it stays an option because a chart with nothing to pick out of it
  /// would want the other half.
  final bool tapToSelect;

  /// Which bucket is currently being read, as the parent holds it. This is the
  /// only copy: keeping a second one here would go stale the moment the pager
  /// cleared the reading out from under it.
  final int? scrub;

  final ValueChanged<int?> onScrub;
  final Widget child;

  const ChartScrub({
    super.key,
    required this.indexAt,
    required this.onScrub,
    required this.child,
    this.scrub,
    this.tapToSelect = false,
  });

  /// **A tick each time the finger crosses into the next bucket**, the same
  /// `lightImpact` the swipe actions and the undo chip use. Sliding along a
  /// line the eye is not on is the whole of what the held gesture is for, and
  /// the tick is what tells the finger it has moved a day — without it the
  /// reader has to watch the headline to know anything is happening.
  void _report(double dx) {
    final at = indexAt(dx);
    if (at == scrub) return;
    if (at != null) HapticFeedback.lightImpact();
    onScrub(at);
  }

  /// A tap on the bucket that is already picked lets it go, which is the way
  /// back out of a reading that stays put.
  void _tap(double dx) {
    final at = indexAt(dx);
    if (at == null) return;
    if (at == scrub) return onScrub(null);
    HapticFeedback.lightImpact();
    onScrub(at);
  }

  void _release() {
    if (scrub == null) return;
    onScrub(null);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Opaque so the whole chart is the target, including the empty air above
      // a short bar: a scrubber you have to hit the ink of is a scrubber that
      // misses.
      behavior: HitTestBehavior.opaque,
      onTapUp: tapToSelect ? (details) => _tap(details.localPosition.dx) : null,
      onLongPressStart: (details) => _report(details.localPosition.dx),
      onLongPressMoveUpdate: (details) => _report(details.localPosition.dx),
      // Where a tap picks, a slide leaves its last bucket picked for the same
      // reason — and the release handlers have to go entirely rather than be
      // made conditional, because `onLongPressCancel` also fires on the way to
      // a tap and would clear the reading the tap is about to toggle.
      onLongPressEnd: tapToSelect ? null : (_) => _release(),
      onLongPressCancel: tapToSelect ? null : _release,
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Shared painting
// ---------------------------------------------------------------------------

/// How wide the plot is once the value labels have taken their gutter.
///
/// The widget and its painter both need this and must not disagree: a finger
/// halfway along a plot the painter thinks is forty points wider lands on the
/// wrong day.
double _plotWidth(double width, double gutter) =>
    math.max(width - (gutter == 0 ? 0 : gutter + _labelGap), 40);

/// How much room the figure at the end of a cumulative line takes, or none at
/// all where the stretch is empty and there is no figure to print.
double _endLabelWidth(List<int> cumulative, String currency) => cumulative.isEmpty || cumulative.last == 0
    ? 0
    : _text(formatMoneyCompact(cumulative.last, currency: currency), AppColors.ink).width;

/// Which buckets get a label under them, and what it says.
///
/// Six at most on a line, first and last always among them; a bar chart labels
/// every bar it can and falls back to the label's first letter at twelve, which
/// is where a row of month names stops fitting and a row of initials still
/// reads. Past that it labels one bar in six, like the line.
List<(int, String)> axisTicks(List<SpendBucket> buckets, {bool everyBar = false}) {
  final n = buckets.length;
  if (n == 0) return const [];
  if (n <= 7) return [for (var i = 0; i < n; i++) (i, buckets[i].label)];
  if (everyBar && n <= 12) {
    return [for (var i = 0; i < n; i++) (i, buckets[i].label.substring(0, 1))];
  }

  const wanted = 6;
  final step = (n - 1) / (wanted - 1);
  final taken = <int>{};
  return [
    for (var k = 0; k < wanted; k++)
      if (taken.add((k * step).round())) ((k * step).round(), buckets[(k * step).round()].label),
  ];
}

/// The currency the rows are in, for a label that has no room to say so twice.
///
/// The first row's, because a household's rows are all in one currency in
/// practice and the alternative — a chart axis that mixes two — is not a thing
/// this page could draw honestly anyway.
/// A budget, dashed across the plot in the danger colour.
///
/// Labelled at the **left** edge, because the right-hand gutter already holds
/// the figures both charts print there and a third label would land on one of
/// them.
void _paintBudgetLine(Canvas canvas, Rect plot, double y, int budget, Color ink, String currency) {
  _dashed(canvas, Offset(plot.left, y), Offset(plot.right, y), ink.withValues(alpha: .6), dash: 3, gap: 3);
  final label = _text(L.s.spendBudgetLine(formatMoneyCompact(budget, currency: currency)), ink, size: 11);
  final above = y - label.height - 2;
  label.paint(canvas, Offset(plot.left, above < 0 ? y + 2 : above));
}

String spendCurrency(List<Spend> rows) => rows.isEmpty ? 'EUR' : rows.first.currency;

TextPainter _text(String value, Color color, {double size = 12}) => TextPainter(
  text: TextSpan(
    text: value,
    style: AppText.body.copyWith(color: color, fontSize: size, height: 1.1),
  ),
  textDirection: TextDirection.ltr,
)..layout();

/// A dashed rule between two points on the same horizontal.
void _dashed(Canvas canvas, Offset from, Offset to, Color color, {double dash = 3, double gap = 4}) {
  if (to.dx <= from.dx) return;
  final paint = Paint()
    ..color = color
    ..strokeWidth = 1.2
    ..strokeCap = StrokeCap.round;
  for (var x = from.dx; x < to.dx; x += dash + gap) {
    canvas.drawLine(Offset(x, from.dy), Offset(math.min(x + dash, to.dx), to.dy), paint);
  }
}
