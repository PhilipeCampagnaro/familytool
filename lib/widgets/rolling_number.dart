import 'package:flutter/material.dart';

/// A figure that rolls from the old one to the new, one column at a time.
///
/// **Only the digits that changed move.** A number that is replaced outright
/// tells the reader something is different and nothing about what: the euros
/// went up, the cents went down, some of it stayed. Rolling each column
/// separately means the eye sees *where* the change was, and a total that ticks
/// while a finger drags along a chart reads as one quantity being measured
/// rather than as a series of unrelated numbers flashed in the same place.
///
/// **It is the string that is animated, not the amount.** The caller has
/// already formatted the figure — grouping separator, currency symbol, the
/// minus sign the app draws as U+2212 — and re-deriving any of that here would
/// put a second opinion about money formatting in the widget layer. Everything
/// that is not `0`–`9` is simply set.
///
/// Columns are keyed **from the right**, so "989 €" growing into "1.014 €"
/// rolls the hundreds where the hundreds were rather than shunting every digit
/// one place along.
class RollingNumber extends StatelessWidget {
  final String value;

  /// The figure's own style. Nothing here reads a palette: the colour, size and
  /// weight are the caller's, exactly as they would be on a `Text`.
  final TextStyle style;

  final Duration duration;
  final Curve curve;

  const RollingNumber({
    super.key,
    required this.value,
    required this.style,
    this.duration = const Duration(milliseconds: 520),
    this.curve = Curves.easeOutCubic,
  });

  static const _zero = 0x30;
  static const _nine = 0x39;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    // One digit's box, measured once for the whole row. The app's face sets its
    // figures on one width, which is what lets a column be a fixed slot rather
    // than something that resizes as it turns.
    final probe = TextPainter(
      text: TextSpan(text: '0', style: style),
      textDirection: Directionality.of(context),
      textScaler: scaler,
    )..layout();
    final digit = probe.size;
    probe.dispose();

    final units = value.codeUnits;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (final (index, unit) in units.indexed)
          if (unit >= _zero && unit <= _nine)
            _Reel(
              key: ValueKey('digit-${units.length - index}'),
              digit: unit - _zero,
              style: style,
              size: digit,
              duration: duration,
              curve: curve,
            )
          else
            Text(
              String.fromCharCode(unit),
              key: ValueKey('mark-${units.length - index}-$unit'),
              style: style,
              textScaler: scaler,
            ),
      ],
    );
  }
}

/// One column, and the two digits of it that can be on screen at once.
///
/// The tween runs over the digit itself, so 3 → 7 passes through 4, 5 and 6 the
/// way a wheel would. Only the pair either side of the current position is
/// built: at any instant a slot that tall can show no more than two.
class _Reel extends StatelessWidget {
  final int digit;
  final TextStyle style;
  final Size size;
  final Duration duration;
  final Curve curve;

  const _Reel({
    super.key,
    required this.digit,
    required this.style,
    required this.size,
    required this.duration,
    required this.curve,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      // No `begin`: a figure appearing for the first time is set, not rolled.
      // There is nothing for it to have come from.
      tween: Tween(end: digit.toDouble()),
      duration: duration,
      curve: curve,
      builder: (context, at, _) {
        final under = at.floor();
        return ClipRect(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: Stack(
              children: [
                for (final face in [under, under + 1])
                  Positioned(
                    left: 0,
                    width: size.width,
                    top: (face - at) * size.height,
                    child: Text(
                      '${face % 10}',
                      style: style,
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
