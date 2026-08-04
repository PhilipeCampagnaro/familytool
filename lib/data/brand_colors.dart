/// The brand colour behind a shop logo — the wash a Listen detail header wears
/// when the list carries one (`HeaderBrandGlow`).
///
/// **Read off the logo, not tabulated.** `assets/merchants/` holds ~170 marks
/// and grows by a file drop; a hand-written table of hexes would cover the
/// handful somebody got around to and leave every other shop on the generic
/// accent — which is exactly how renaming a list from *REWE* to *Amazon*
/// changed the logo without changing the colour. Decoding the logo once and
/// taking its dominant hue makes a new PNG bring its own colour with it, the
/// same way [merchantNameFor] already derives the shop's name from the file
/// name.
///
/// [AppColors.brandRewe] and its three siblings stay as deliberate overrides:
/// they are design tokens with their own dark-mode variants, so where the
/// palette has an opinion the palette wins.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../theme/tokens.dart';
import 'merchant_logos.dart';

/// Raw dominant colour per logo asset, before the theme is applied. A stored
/// null means "decoded, and there is no brand hue in there" — a black-and-white
/// wordmark like Apple's or Zalando's — and is kept so the decode runs once per
/// logo rather than once per build.
final Map<String, Color?> _dominant = {};

/// Whether [iconKey] can be answered without touching an asset. False only for
/// a shop logo nobody has decoded yet; the caller shows the accent, calls
/// [loadBrandGlow] and rebuilds when it lands.
bool brandGlowKnown(String? iconKey) {
  final asset = _merchantAsset(iconKey);
  return asset == null || _brandToken(asset) != null || _dominant.containsKey(asset);
}

/// The glow for a list carrying [iconKey], right now: the palette's colour for
/// the four shops it names, the logo's own dominant hue for every other shop,
/// and the app accent for a list wearing a symbol, a mark with no colour in it,
/// or a logo that hasn't been decoded yet.
Color brandGlowFor(String? iconKey) {
  final asset = _merchantAsset(iconKey);
  if (asset == null) return AppColors.accent;
  final token = _brandToken(asset);
  if (token != null) return token;
  final dominant = _dominant[asset];
  return dominant == null ? AppColors.accent : _forTheme(dominant);
}

/// Decodes [iconKey]'s logo and caches its dominant hue. Cheap and idempotent —
/// a no-op once [brandGlowKnown] is true — and it never throws: a logo that
/// can't be read is cached as "no colour" and glows in the accent like any
/// other unbranded list.
Future<void> loadBrandGlow(String? iconKey) async {
  final asset = _merchantAsset(iconKey);
  if (asset == null || brandGlowKnown(iconKey)) return;
  try {
    _dominant[asset] = await _extractDominant(asset);
  } catch (_) {
    _dominant[asset] = null;
  }
}

String? _merchantAsset(String? iconKey) =>
    iconKey != null && iconKey.startsWith(merchantAssetDir) ? iconKey : null;

/// The four shops the palette has hand-tuned colours for, in both themes.
Color? _brandToken(String asset) => switch (asset.substring(merchantAssetDir.length)) {
      'rewe_de.png' => AppColors.brandRewe,
      'dm_de.png' => AppColors.brandDm,
      'toom_de.png' => AppColors.brandToom,
      'ikea_com.png' => AppColors.brandIkea,
      _ => null,
    };

/// Pulls a logo's colour into the band the palette's own brand tokens sit in,
/// so a derived colour behaves like a token: deep enough to read as a wash on
/// light, lifted on dark where a saturated brand red turns to mud. Applied at
/// read time rather than baked into the cache, because the theme can change
/// while a list is open.
Color _forTheme(Color raw) {
  final hsl = HSLColor.fromColor(raw);
  return hsl
      .withSaturation(hsl.saturation.clamp(.55, .95))
      .withLightness(AppColors.isDark ? hsl.lightness.clamp(.50, .68) : hsl.lightness.clamp(.36, .58))
      .toColor();
}

/// Twelve hue buckets, so a two-colour mark (Amazon's orange swoosh under a
/// black wordmark, DHL's red on yellow) resolves to one of its colours rather
/// than to the muddy average of both.
const _buckets = 12;

/// Decoded edge length. Big enough that a small accent — the dot on a logo's
/// "i" — survives, small enough that the whole folder costs less than one photo.
const _decodeWidth = 64;

/// The dominant brand hue of a logo, or null if it hasn't got one.
///
/// Grey, black and white pixels are skipped outright: they are the linework and
/// the transparent-turned-white background of nearly every mark, and counting
/// them would make every logo in the folder glow the same near-grey. What is
/// left is bucketed by hue and weighted by how vivid it is, so a large pale
/// field doesn't outvote the small saturated mark that is the actual brand.
Future<Color?> _extractDominant(String asset) async {
  final data = await rootBundle.load(asset);
  final codec = await ui.instantiateImageCodec(
    data.buffer.asUint8List(),
    targetWidth: _decodeWidth,
  );
  final frame = await codec.getNextFrame();
  final bytes = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
  frame.image.dispose();
  codec.dispose();
  if (bytes == null) return null;
  final pixels = bytes.buffer.asUint8List();

  final weight = List.filled(_buckets, 0.0);
  final sumR = List.filled(_buckets, 0.0);
  final sumG = List.filled(_buckets, 0.0);
  final sumB = List.filled(_buckets, 0.0);

  for (var i = 0; i + 3 < pixels.length; i += 4) {
    // Near-opaque only: `rawRgba` is premultiplied, so a half-transparent
    // antialiased edge reads as a darker version of itself and would drag the
    // average toward black.
    if (pixels[i + 3] < 250) continue;
    final r = pixels[i] / 255, g = pixels[i + 1] / 255, b = pixels[i + 2] / 255;
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

  var best = 0;
  for (var i = 1; i < _buckets; i++) {
    if (weight[i] > weight[best]) best = i;
  }
  // A handful of stray coloured pixels is JPEG ringing around black linework,
  // not a brand colour.
  if (weight[best] < 1) return null;
  return Color.from(
    alpha: 1,
    red: sumR[best] / weight[best],
    green: sumG[best] / weight[best],
    blue: sumB[best] / weight[best],
  );
}
