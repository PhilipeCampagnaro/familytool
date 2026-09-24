import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../widgets/dot_field.dart';

/// The form's picture: **the greeting, alone in the middle of the front door's
/// own paper**.
///
/// It is the landing's hero with the story taken out — the same dot grid, lit
/// the same way, in the same place on the page and at the same sort of size,
/// under the same 'aporah' — so stepping from "Konto erstellen" into the form
/// is one page carrying on rather than two designs meeting. The greeting is the
/// one thing that changes between the two ways in.
///
/// **It is a band, not a line.** Set to the height of its own text the picture
/// was a caption with dots behind it; given a share of the display it is what
/// the landing's picture is — the top third of the page, with one thing
/// standing in the middle of it. That is also what makes the light read as a
/// glow around the word rather than as a stripe across the page.
///
/// **'aporah' is not in here**, for the same reason it is not inside the
/// landing's canvas: on both pages the name stands above the dots rather than
/// on them, and a name drawn *on* the paper sits a nav row lower than the one
/// on the page before it.
///
/// **Nothing moves, and it is set in the app's own face.** The greeting wrote
/// itself out in a cursive for a while, in the hand a phone greets you with the
/// first time it is switched on. It was a wipe travelling along the letters
/// rather than a real stroke, and a second typeface on the one page a stranger
/// sees was a lot to ask of one word.
class GreetingHero extends StatelessWidget {
  /// The word itself, already picked for the direction the visitor is going.
  final String greeting;

  const GreetingHero({super.key, required this.greeting});

  /// The share of the display the band takes, and the floor and ceiling on it —
  /// the same arrangement [StepHero] makes for the tour's illustrations, so the
  /// picture gives way on a small phone rather than pushing the first field
  /// below the fold.
  ///
  /// The floor holds two lines of [AppText.greeting] with room around them,
  /// because the longest greeting wraps.
  static const _fraction = 0.27;
  static const _minHeight = 180.0;
  static const _maxHeight = 250.0;

  static const _sidePad = AppSpacing.screenPad;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final scaler = MediaQuery.textScalerOf(context);
    final height = (MediaQuery.sizeOf(context).height * _fraction).clamp(_minHeight, _maxHeight);

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;

          // **The light is fitted to the word, not guessed at.** The greeting is
          // one line in English and two in German, so how tall it is is a
          // question only a layout can answer — and on a page with no animation
          // on it, that layout happens once per build rather than once per
          // frame.
          final measured = TextPainter(
            text: TextSpan(text: greeting, style: AppText.greeting),
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            textScaler: scaler,
          )..layout(maxWidth: width - _sidePad * 2);

          // A floor on the width so a short greeting — Spanish's "Hola" is 94pt
          // — gets a pool of light the size of the band rather than a bright
          // spot the size of the word.
          final block = Size(math.max(measured.width, width * 0.5), measured.height);
          final middle = Offset(width / 2, height / 2);
          // A circle sized to cover a line three times wider than it is tall
          // covers a great deal else besides; the horizontal distance is divided
          // by this instead — see [DotSpark.aspect].
          final aspect = block.width / block.height;

          return Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: DotField(
                    sparks: [
                      DotSpark(
                        at: middle,
                        strength: 0.52,
                        core: block.height * 0.62,
                        radius: 92,
                        aspect: aspect,
                      ),
                    ],
                    // **The blue steps out from under the letters**, for the
                    // reason the landing's sentence does: a headline set on
                    // coloured texture is a headline you read twice. The core is
                    // the word's own ellipse, so what is left is a halo around
                    // it rather than a wash behind it.
                    shades: [
                      DotSpark(
                        at: middle,
                        strength: 0.88,
                        core: block.height * 0.5,
                        radius: 26,
                        aspect: aspect,
                      ),
                    ],
                    base: AppColors.hairline,
                    accent: accent,
                  ),
                ),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _sidePad),
                  child: Text(greeting, style: AppText.greeting, textAlign: TextAlign.center),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
