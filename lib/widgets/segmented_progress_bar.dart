import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A progress bar drawn the way the Ausgaben donut draws its arcs: **two
/// rounded pieces with daylight between them** — the part that is done, and the
/// part that is left — rather than a fill laid over a track.
///
/// The donut parted its arcs because a band running straight into the next one
/// reads as one shape with a colour change in it; a bar is the same band laid
/// flat, and the Board's day and a spending budget are both drawn with this so
/// the app has one idea of what "this much of it" looks like.
///
/// - **Nothing is drawn under the fill.** A track showing through the gap is
///   exactly the grey seam the donut stopped drawing.
/// - **Empty is all track and full is all fill**, with no gap and no stub: a
///   zero-width piece with a gap beside it would leave a hole at the end.
/// - A value above zero is never thinner than the bar is tall, so a sliver still
///   reads as a rounded mark rather than a smear — the donut floors its thinnest
///   arc for the same reason.
class SegmentedProgressBar extends StatelessWidget {
  /// 0 to 1; anything outside is clamped.
  final double value;
  final Color color;
  final Color track;
  final double height;

  const SegmentedProgressBar({
    super.key,
    required this.value,
    required this.color,
    required this.track,
    this.height = 8,
  });

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0.0, 1.0);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 280);
    // A quarter-stroke of daylight on the donut comes to about this on a bar
    // a few points tall, and never less than the eye can find.
    final gap = math.max(3.0, height * .45);
    final radius = BorderRadius.circular(height);

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, box) {
          final width = box.maxWidth;
          final hasFill = v > 0;
          final hasTrack = v < 1;

          double fill;
          if (!hasFill) {
            fill = 0;
          } else if (!hasTrack) {
            fill = width;
          } else {
            fill = width * v;
            // Room for a round end on both pieces, where there is room at all.
            final max = width - gap - height;
            if (max > height) fill = fill.clamp(height, max);
          }

          return Stack(
            children: [
              AnimatedPositioned(
                duration: duration,
                curve: Curves.easeOutCubic,
                left: hasFill ? fill + gap : 0,
                right: 0,
                top: 0,
                bottom: 0,
                child: hasTrack
                    ? DecoratedBox(
                        decoration: BoxDecoration(color: track, borderRadius: radius),
                      )
                    : const SizedBox.shrink(),
              ),
              AnimatedPositioned(
                duration: duration,
                curve: Curves.easeOutCubic,
                left: 0,
                width: fill,
                top: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: color, borderRadius: radius),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
