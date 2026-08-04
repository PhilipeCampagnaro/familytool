library;

import 'package:flutter/material.dart';

import 'app_strings.dart';
import 'strings_de.dart';
import 'strings_en.dart';

export 'app_strings.dart';

/// The live language.
///
/// Assigned in `AporahApp.build` before anything below it builds, exactly like
/// `AppColors.palette`. Reading [s] does **not** subscribe a widget to changes:
/// the rebuild comes from `AporahApp` watching `settingsProvider` and rebuilding
/// its whole subtree, which is the mechanism the dark-mode switch already rides
/// on. Anything that caches a string across that rebuild (a `TextEditingController`
/// seeded once, a `const` widget) would keep the old language — so don't.
class L {
  L._();

  /// German until `AporahApp` says otherwise. Defaulting to German rather than
  /// to a throwing stub keeps a widget built in a test or a `main()` that never
  /// reached `AporahApp` rendering real copy.
  static AppStrings s = const StringsDe();

  /// Swap the language. Cheap and idempotent — both implementations are `const`
  /// singletons, so calling this on every build costs nothing.
  static void use(String localeCode) {
    s = stringsFor(localeCode);
  }
}

/// Maps `AppLanguage.name` (`'de'` / `'en'`) onto an implementation. Anything
/// unrecognised falls back to German rather than throwing: a stored preference
/// from a future version must not brick the app on downgrade.
AppStrings stringsFor(String localeCode) => switch (localeCode) {
      'en' => const StringsEn(),
      _ => const StringsDe(),
    };

/// The locales `MaterialApp` is told about. Order matters — the first is the
/// fallback when the device asks for something we don't have.
const appSupportedLocales = [Locale('de'), Locale('en')];

// ---------------------------------------------------------------------------
// Formatting that depends on the language but isn't itself a string.
// ---------------------------------------------------------------------------

/// `14:30` in German, `2:30 PM` in English.
///
/// Deliberately not `intl`'s `DateFormat.jm()`: the app has no `intl`
/// dependency of its own and this is the only clock format it needs.
String formatTimeOfDay(int hour, int minute) {
  final mm = minute.toString().padLeft(2, '0');
  if (L.s.use24HourClock) return '${hour.toString().padLeft(2, '0')}:$mm';
  final suffix = hour < 12 ? 'AM' : 'PM';
  final h12 = hour % 12 == 0 ? 12 : hour % 12;
  return '$h12:$mm $suffix';
}

/// Same, from a [DateTime].
String formatTime(DateTime at) => formatTimeOfDay(at.hour, at.minute);

/// Same, from a [TimeOfDay] — what the pickers hand back.
String formatTimeOf(TimeOfDay t) => formatTimeOfDay(t.hour, t.minute);

/// Whether `showTimePicker` should come up as a 24-hour dial.
bool get alwaysUse24HourFormat => L.s.use24HourClock;
