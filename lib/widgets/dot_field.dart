import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Something happening, and how far its light reaches. A [ring] turns it from
/// a glow around a point into an expanding circle *of* light — the press.
class DotSpark {
  final Offset at;
  final double strength;

  /// How far the light falls off over, measured from the edge of [core].
  final double radius;

  /// How much wider than tall the light is. 1 is a circle, which is every
  /// spark that comes off a point.
  ///
  /// The two things on the welcome page are not points and are not round: a
  /// picture at 3:2 and a sentence set three times wider than it is tall. A
  /// circle sized to cover either of them covers a great deal else besides, so
  /// the horizontal distance is divided by this before it is measured — which
  /// turns every circle below into the ellipse of the thing it belongs to,
  /// without a second falloff to keep in step with the first.
  final double aspect;

  /// A disc of **undimmed** light before the falloff begins. Zero for
  /// everything that happens — a pointer, a press, a card landing — because
  /// those are points and a point's light is brightest at the point.
  ///
  /// The welcome page is the one thing in the piece that is not a point: it is
  /// a picture 348 wide, and a squared falloff from its middle lights the
  /// middle and leaves the ends of it grey, which reads as a lamp behind the
  /// picture rather than as the picture being lit. A core the size of the thing
  /// makes the whole of it sit on blue paper and the blue run out somewhere
  /// past its edges.
  final double core;

  final double? ring;

  const DotSpark({
    required this.at,
    required this.strength,
    required this.radius,
    this.core = 0,
    this.aspect = 1,
    this.ring,
  });

  /// The composition is laid out in canvas points and the dots are painted in
  /// the band's, so a spark has to cross over. Its reach scales with the
  /// drawing; the *dots* deliberately do not, because they are the paper rather
  /// than part of it.
  DotSpark toBand({required Offset origin, required double scale}) => DotSpark(
    at: origin + at * scale,
    strength: strength,
    radius: radius * scale,
    core: core * scale,
    // Not scaled: it is a ratio, and a ratio that shrank with the drawing
    // would make the ellipse rounder on a small phone.
    aspect: aspect,
    ring: ring == null ? null : ring! * scale,
  );
}

/// The paper the sign-in pages are drawn on: a grid of dots that **lights up
/// where something is happening**.
///
/// What it buys is legible motion. A pointer crossing an empty white band is a
/// small arrow moving through nothing; the same arrow dragging a patch of
/// accent-coloured dots behind it reads as something being *done* to a surface.
/// The press throws a ring out from under the finger for the same reason —
/// there is no click to hear, so the surface answers instead — and a card
/// landing blooms the dots it lands on.
///
/// The grid's spacing and dot size are in **band** points and do not scale with
/// the composition: it is the paper, not part of the drawing, and paper whose
/// texture grew on a larger phone would read as a zoom rather than a
/// background.
///
/// **Shared by both of the front door's pictures**, which is why it sits here
/// rather than beside either of them: the landing's card story lights it under
/// four pointers, and the form's greeting lights it under a word being
/// written. One paper, two things happening on it — two painters would have
/// drifted into two different dot grids on two pages of one flow.
class DotField extends CustomPainter {
  final List<DotSpark> sparks;

  /// Where the light is asked to **step back out of the way**, and by how much:
  /// each one is an ordinary [DotSpark] read as a subtraction, so a shade has the
  /// same soft edge a glow has and is written the same way.
  ///
  /// There is one, and it is under the sentence. Thickening the type was the
  /// first answer and it was the wrong shape of answer: the problem is not that
  /// the words are thin, it is that they are set on a patch of coloured
  /// texture, and a heavier face over the same texture is a heavier thing that
  /// is still hard to read. Taking the colour back out from under them leaves
  /// the words on the same quiet paper as the rest of the page, and leaves the
  /// blue where it was wanted — behind the picture.
  final List<DotSpark> shades;

  /// The unlit dot. `AppColors.hairline` on both palettes — the tone every
  /// divider in the app is drawn in, which puts the grid at the very bottom of
  /// the visual stack where it belongs.
  final Color base;

  final Color accent;

  static const _spacing = 15.0;
  static const _dot = 1.5;

  /// How wide the press ring's band of light is.
  static const _ringWidth = 16.0;

  const DotField({required this.sparks, required this.shades, required this.base, required this.accent});

  /// How far [at] is from [spark], with the horizontal squashed by its aspect —
  /// which is what makes a round falloff describe an ellipse.
  static double _reachOf(DotSpark spark, double x, double y) {
    final dx = (x - spark.at.dx) / spark.aspect;
    final dy = y - spark.at.dy;
    final distance = math.sqrt(dx * dx + dy * dy);

    if (spark.ring case final r?) {
      // A band of light at the ring's current radius, not a disc.
      final off = (distance - r).abs();
      return off >= _ringWidth ? 0 : 1 - off / _ringWidth;
    }
    // Full strength inside the core, and the falloff measured from its edge
    // rather than from the middle — see [DotSpark.core].
    final out = distance - spark.core;
    if (out <= 0) return 1;
    if (out >= spark.radius) return 0;
    // Squared falloff: a linear one lights a visibly circular patch, and the
    // edge of that circle is the thing you end up looking at.
    final f = 1 - out / spark.radius;
    return f * f;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = true;
    // Centred, so the grid is symmetrical in the band rather than starting at
    // the top-left corner and running out unevenly on the other side.
    final startX = (size.width % _spacing) / 2;
    final startY = (size.height % _spacing) / 2;

    for (var y = startY; y <= size.height; y += _spacing) {
      for (var x = startX; x <= size.width; x += _spacing) {
        var lit = 0.0;
        for (final spark in sparks) {
          if (spark.strength <= 0) continue;
          final value = _reachOf(spark, x, y) * spark.strength;
          if (value > lit) lit = value;
        }

        // …and then the shades take it back off, strongest one wins, exactly
        // as the sparks put it on.
        var dimmed = 0.0;
        for (final shade in shades) {
          if (shade.strength <= 0) continue;
          final value = _reachOf(shade, x, y) * shade.strength;
          if (value > dimmed) dimmed = value;
        }
        lit *= 1 - dimmed;

        paint.color = Color.lerp(base, accent, lit)!.withValues(alpha: 0.55 + 0.45 * lit);
        canvas.drawCircle(Offset(x, y), _dot + 1.3 * lit, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant DotField old) => true;
}
