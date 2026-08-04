/// The colour of the bin, for an Abfuhrtermin.
///
/// A waste calendar is a month of entries on one feed, so every one of them
/// would otherwise be the same brown dot — and the only thing a family actually
/// wants from it is *which bin goes out tonight*. Germans know their bins by
/// colour, so the colour is the answer, and the dot in the month grid carries it
/// without anyone reading a word.
///
/// **Classified, not looked up.** The six vendor families in
/// `supabase/functions/_shared/abfall.ts` name the same four fractions a dozen
/// ways — "Restabfall", "Restmüll", "Graue Tonne", "Hausmüll 14-täglich",
/// "Bioabfall", "Biotonne", "Grünabfall", "Altpapier", "Blaue Tonne", "PPK",
/// "Gelber Sack", "Leichtverpackungen", "Wertstofftonne" — and new towns bring
/// new spellings. Matching substrings against the ones we know beats a table
/// that has to be complete, and an unrecognised fraction simply keeps the
/// feed's own colour rather than being coloured wrongly.
library;

import 'package:flutter/material.dart';

/// Bin colours as the German waste system actually paints them, nudged for
/// screen: the real yellow and the real grey are both hard to see as a 9pt dot.
class BinColors {
  /// Restabfall — schwarz/grau.
  static const rest = Color(0xff4b5563);

  /// Bioabfall — braun.
  static const bio = Color(0xff7a5230);

  /// Altpapier — blau.
  static const paper = Color(0xff1d6fd0);

  /// Gelbe Tonne / Gelber Sack — gelb, darkened so it reads on white.
  static const packaging = Color(0xffd9a400);

  /// Glas — grün. Not everywhere kerbside, but several vendors list it.
  static const glass = Color(0xff2e7d4f);

  /// Sperrmüll, Schadstoffmobil, Weihnachtsbäume — the occasional extras.
  static const bulky = Color(0xff8b5cf6);
}

/// Longest-first so "gelber sack" is tested before a bare "sack" would matter,
/// and so "biotonne" cannot be caught by a shorter "tonne" rule. Order within a
/// bin does not matter; order *between* bins does, which is why this is a list
/// and not a map.
const _rules = <(String, Color)>[
  // Bio before Rest: "Bioabfall" contains "abfall".
  ('bioabfall', BinColors.bio),
  ('biotonne', BinColors.bio),
  ('biomüll', BinColors.bio),
  ('grünabfall', BinColors.bio),
  ('grüngut', BinColors.bio),
  ('gartenabfall', BinColors.bio),
  ('braune tonne', BinColors.bio),
  ('bio', BinColors.bio),

  ('altpapier', BinColors.paper),
  ('papier', BinColors.paper),
  ('pappe', BinColors.paper),
  ('blaue tonne', BinColors.paper),
  ('ppk', BinColors.paper),
  ('karton', BinColors.paper),

  ('gelber sack', BinColors.packaging),
  ('gelbe tonne', BinColors.packaging),
  ('gelbe wertstofftonne', BinColors.packaging),
  ('leichtverpackung', BinColors.packaging),
  ('verpackung', BinColors.packaging),
  ('wertstoff', BinColors.packaging),
  ('lvp', BinColors.packaging),
  ('dsd', BinColors.packaging),
  ('gelb', BinColors.packaging),

  ('altglas', BinColors.glass),
  ('glas', BinColors.glass),

  ('sperrmüll', BinColors.bulky),
  ('sperrabfall', BinColors.bulky),
  ('schadstoff', BinColors.bulky),
  ('problemstoff', BinColors.bulky),
  ('elektro', BinColors.bulky),
  ('weihnachtsbaum', BinColors.bulky),
  ('tannenbaum', BinColors.bulky),

  ('restabfall', BinColors.rest),
  ('restmüll', BinColors.rest),
  ('hausmüll', BinColors.rest),
  ('graue tonne', BinColors.rest),
  ('schwarze tonne', BinColors.rest),
  ('rest', BinColors.rest),
];

/// The bin's colour, or null when the fraction isn't one we recognise.
///
/// Null rather than a default, so an unknown fraction falls back to the feed's
/// own colour at the call site — a wrong bin colour is worse than a neutral one,
/// because the whole point is that the colour can be trusted without reading.
Color? binColorFor(String title) {
  // Umlauts are matched literally: every vendor here writes German, and the
  // fold that `grocery_search.dart` needs (users typing "muell") has no place in
  // machine-generated text.
  final name = title.toLowerCase();
  for (final (needle, color) in _rules) {
    if (name.contains(needle)) return color;
  }
  return null;
}
