import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'tokens.dart';

/// Builds the Material theme for one [AppPalette].
///
/// Note this reads its colours from the `palette` argument rather than from the
/// [AppColors] getters: `MaterialApp` builds *both* the light and the dark
/// `ThemeData` up front, so at the moment the dark one is built the installed
/// palette is usually still the light one.
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

  final poppinsTextTheme = GoogleFonts.poppinsTextTheme(base.textTheme);

  return base.copyWith(
    textTheme: poppinsTextTheme,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    dividerColor: palette.divider,
  );
}
