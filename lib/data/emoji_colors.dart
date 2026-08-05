/// The colours *inside* an emoji — the party popper's gold, red and blue,
/// which is what the celebration screen's wash is lit with
/// (`CelebrationGlow`).
///
/// Read off the glyph, exactly like a shop logo's colour is read off its PNG
/// (`brandGlowFor`), and for the same reason: an emoji is artwork the app does
/// not own. Apple, Google and the emoji font on a desktop all draw 🎉
/// differently, and they redraw it between OS releases — a hand-typed `0xFFD9A0`
/// would be a guess at somebody else's asset that quietly stops matching the
/// picture right above it. Painting the glyph and looking at it can't.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'dominant_hue.dart';

/// Resolved glyphs, by emoji. An entry is only written once its colours are
/// known, so the render runs once per emoji per launch; an empty list is a
/// glyph that came out monochrome (or a platform that drew nothing) and is
/// cached like any other answer.
final Map<String, List<Color>> _hues = {};

/// How many colours a wash is built from. The popper is a gold cone, a red
/// streamer and a blue one; a fourth is the pale confetti dots, which at wash
/// alpha is a grey smudge between the three that matter.
const _take = 3;

/// A colour has to carry a fifth of the strongest one's weight to join them,
/// which is what keeps the antialiased seam between two streamers out of the
/// list.
const _minShare = .2;

/// Rendered size. Large enough that the streamers — a few percent of the glyph
/// each — survive as their own hue buckets rather than blending into the cone.
const _renderSize = 128.0;

/// Whether [emoji] can be answered without painting anything.
bool emojiGlowKnown(String emoji) => _hues.containsKey(emoji);

/// [emoji]'s colours, strongest first, themed to read as a wash in the live
/// palette. Empty until [loadEmojiGlow] has run, and empty forever for a glyph
/// with no colour in it — the caller decides what "no colours" looks like.
List<Color> emojiGlowFor(String emoji) => [for (final hue in _hues[emoji] ?? const []) washTone(hue)];

/// Paints [emoji] offscreen and caches the colours in it. Idempotent, and it
/// never throws: a glyph that can't be drawn is cached as "no colours", which
/// the caller renders as nothing at all.
Future<void> loadEmojiGlow(String emoji) async {
  if (emojiGlowKnown(emoji)) return;
  try {
    _hues[emoji] = await _extractHues(emoji);
  } catch (_) {
    _hues[emoji] = const [];
  }
}

Future<List<Color>> _extractHues(String emoji) async {
  final painter = TextPainter(
    text: TextSpan(text: emoji, style: const TextStyle(fontSize: _renderSize)),
    textDirection: TextDirection.ltr,
  )..layout();

  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), Offset.zero);
  final picture = recorder.endRecording();
  // Ceil, and never zero: `toImage` on an empty box throws, and a glyph the
  // platform has no font for lays out to nothing.
  final image = await picture.toImage(
    painter.width.ceil().clamp(1, _renderSize.ceil() * 2),
    painter.height.ceil().clamp(1, _renderSize.ceil() * 2),
  );
  picture.dispose();

  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  painter.dispose();
  if (bytes == null) return const [];
  return dominantHues(bytes.buffer.asUint8List(), take: _take, minShare: _minShare);
}
