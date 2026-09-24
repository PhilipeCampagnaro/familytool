import 'package:flutter/material.dart';

/// A picture that **ends by dissolving** instead of being cut.
///
/// A hard edge across a photograph, a screenshot or an illustration reads as a
/// rendering fault — the eye takes it for something that failed to draw. The
/// same content faded out over its last stretch reads as a picture continuing
/// past the frame, which is the truth: there is more of it, and the page simply
/// stops showing it. Same reasoning as [PinnedActionBar]'s gradient, one axis
/// down.
///
/// A `ShaderMask` in [BlendMode.dstIn] rather than a coloured gradient laid
/// over the top, because the page behind is not always one colour and a white
/// ramp over a dark palette is a grey smear. This takes the *alpha* away, so
/// whatever is behind comes through — which is also what lets the front door's
/// illustration dissolve into the page and the paywall's screenshot dissolve
/// into a sheet, with one widget.
///
/// Two callers today: the Plus paywall's device shot and the sign-in front
/// door's illustration. They pass different [start]s because they are
/// dissolving different things — a screenshot has content all the way down and
/// wants to keep as much as it can, while an illustration on transparency has
/// a soft edge already and can afford a longer ramp.
class DissolveBottom extends StatelessWidget {
  final Widget child;

  /// Where the fade begins, as a fraction of the height — 1 is the bottom
  /// edge, so a smaller number is a longer dissolve.
  final double start;

  const DissolveBottom({super.key, required this.child, this.start = 0.86});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: ShaderMask(
        shaderCallback: (rect) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          // Opaque down to [start], then out to nothing. The colours are
          // irrelevant under `dstIn` — only the alpha is read.
          colors: const [Colors.white, Colors.white, Colors.transparent],
          stops: [0, start, 1],
        ).createShader(rect),
        blendMode: BlendMode.dstIn,
        child: child,
      ),
    );
  }
}
