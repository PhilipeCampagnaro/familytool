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
import 'dominant_hue.dart';
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
  return dominant == null ? AppColors.accent : washTone(dominant);
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

/// Decoded edge length. Big enough that a small accent — the dot on a logo's
/// "i" — survives, small enough that the whole folder costs less than one photo.
const _decodeWidth = 64;

/// The dominant brand hue of a logo, or null if it hasn't got one — a
/// black-and-white wordmark like Apple's. The reading itself is
/// [dominantHues]; all that is left here is getting the logo decoded.
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
  return dominantHues(bytes.buffer.asUint8List()).firstOrNull;
}
