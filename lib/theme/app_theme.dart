import 'package:flutter/material.dart';
import 'tokens.dart';

/// Builds the Material theme for one [AppPalette].
///
/// Note this reads its colours from the `palette` argument rather than from the
/// [AppColors] getters: `MaterialApp` builds *both* the light and the dark
/// `ThemeData` up front, so at the moment the dark one is built the installed
/// palette is usually still the light one.
///
/// The typeface comes from `ThemeData.fontFamily` alone, resolving against the
/// `Poppins` family declared in pubspec.yaml. There used to be a second source —
/// `GoogleFonts.poppinsTextTheme(base.textTheme)` layered on top — and the two
/// disagreed: `google_fonts` registers weights under `Poppins_regular` /
/// `Poppins_600`, so unstyled text got real Poppins while everything carrying an
/// [AppText] token asked for the then-unregistered `'Poppins'` and fell back to
/// the system font. One bundled family, one name, no fallback.
ThemeData buildAppTheme(AppPalette palette) {
  final base = ThemeData(
    useMaterial3: true,
    brightness: palette.brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: palette.accent,
      brightness: palette.brightness,
      primary: palette.accent,
      surface: palette.surface,
    ),
    scaffoldBackgroundColor: palette.surface,
    fontFamily: 'Poppins',
  );

  return base.copyWith(
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    dividerColor: palette.divider,
  );
}
