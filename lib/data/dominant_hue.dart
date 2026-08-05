/// Reading a colour off artwork instead of tabulating it: the hue-bucket pass
/// behind the Listen header's brand wash (`brandGlowFor`) and the celebration
/// screen's party-coloured light (`emojiGlowFor`).
///
/// Shared because the two want the same thing off different pixels — a shop
/// logo's one brand colour, a party popper's three — and because a second copy
/// of the bucketing would drift from this one the first time either was tuned.
/// Everything about the *pixels* lives here; what a caller does with the colour
/// afterwards stays with the caller.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Twelve hue buckets, so a two-colour mark (Amazon's orange swoosh under a
/// black wordmark, DHL's red on yellow) resolves to one of its colours rather
/// than to the muddy average of both.
const _buckets = 12;

/// A handful of stray coloured pixels is JPEG ringing around black linework,
/// not a colour anything should be washed in.
const _noise = 1.0;

/// The strongest hues in [rgba] — raw premultiplied RGBA, as
/// `Image.toByteData(format: rawRgba)` hands it over — most present first, at
/// most [take] of them.
///
/// Grey, black and white pixels are skipped outright: they are the linework and
/// the transparent-turned-white background of nearly every mark, and counting
/// them would make every logo in the folder come out the same near-grey. What
/// is left is bucketed by hue and weighted by how vivid it is, so a large pale
/// field doesn't outvote the small saturated mark that is the actual brand.
///
/// [minShare] is how much of the strongest bucket's weight a *further* colour
/// has to carry to count — for a caller taking several, which otherwise fills
/// the tail of its list with the two dozen pixels where a red streamer is
/// antialiased against a yellow cone.
List<Color> dominantHues(Uint8List rgba, {int take = 1, double minShare = 0}) {
  final weight = List.filled(_buckets, 0.0);
  final sumR = List.filled(_buckets, 0.0);
  final sumG = List.filled(_buckets, 0.0);
  final sumB = List.filled(_buckets, 0.0);

  for (var i = 0; i + 3 < rgba.length; i += 4) {
    // Near-opaque only: `rawRgba` is premultiplied, so a half-transparent
    // antialiased edge reads as a darker version of itself and would drag the
    // average toward black.
    if (rgba[i + 3] < 250) continue;
    final r = rgba[i] / 255, g = rgba[i + 1] / 255, b = rgba[i + 2] / 255;
    final max = [r, g, b].reduce((a, b) => a > b ? a : b);
    final min = [r, g, b].reduce((a, b) => a < b ? a : b);
    final saturation = max == 0 ? 0.0 : (max - min) / max;
    if (saturation < .3 || max < .15) continue;

    final delta = max - min;
    var hue = 0.0;
    if (max == r) {
      hue = 60 * (((g - b) / delta) % 6);
    } else if (max == g) {
      hue = 60 * ((b - r) / delta + 2);
    } else {
      hue = 60 * ((r - g) / delta + 4);
    }
    final bucket = (hue / (360 / _buckets)).floor() % _buckets;
    final w = saturation * max;
    weight[bucket] += w;
    sumR[bucket] += r * w;
    sumG[bucket] += g * w;
    sumB[bucket] += b * w;
  }

  final ranked = [for (var i = 0; i < _buckets; i++) i]
    ..sort((a, b) => weight[b].compareTo(weight[a]));
  if (weight[ranked.first] < _noise) return const [];

  final floor = [_noise, weight[ranked.first] * minShare].reduce((a, b) => a > b ? a : b);
  return [
    for (final bucket in ranked.take(take))
      if (weight[bucket] >= floor)
        Color.from(
          alpha: 1,
          red: sumR[bucket] / weight[bucket],
          green: sumG[bucket] / weight[bucket],
          blue: sumB[bucket] / weight[bucket],
        ),
  ];
}

/// Pulls a colour read off artwork into the band the palette's own brand tokens
/// sit in, so a derived colour behaves like a token: deep enough to read as a
/// wash on light, lifted on dark where a saturated brand red turns to mud.
/// Applied at read time rather than baked into a cache, because the theme can
/// change while the thing wearing it is on screen.
Color washTone(Color raw) {
  final hsl = HSLColor.fromColor(raw);
  return hsl
      .withSaturation(hsl.saturation.clamp(.55, .95))
      .withLightness(AppColors.isDark ? hsl.lightness.clamp(.50, .68) : hsl.lightness.clamp(.36, .58))
      .toColor();
}
