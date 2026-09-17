library;

import 'package:flutter/material.dart';

import 'app_strings.dart';
import 'strings_de.dart';
import 'strings_en.dart';
import 'strings_es.dart';
import 'strings_pt.dart';

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

/// Maps `AppLanguage.name` (`'de'` / `'en'` / `'pt'` / `'es'`) onto an
/// implementation. Anything unrecognised falls back to German rather than
/// throwing: a stored preference from a future version must not brick the app
/// on downgrade.
AppStrings stringsFor(String localeCode) => switch (localeCode) {
  'en' => const StringsEn(),
  'pt' => const StringsPt(),
  'es' => const StringsEs(),
  _ => const StringsDe(),
};

/// The locales `MaterialApp` is told about. Order matters — the first is the
/// fallback when the device asks for something we don't have.
///
/// Bare language codes, no country: `Locale('pt')` is **Brazilian** Portuguese
/// here and `Locale('es')` is European Spanish, which is what [StringsPt] and
/// [StringsEs] are written in. A phone set to pt-PT or es-MX still resolves to
/// them rather than falling all the way back to German — a household in Lisbon
/// gets Portuguese that reads as foreign rather than a language they do not
/// speak at all. That is the right call while there is one variant of each, and
/// `stringsFor` is where a second one would slot in.
const appSupportedLocales = [Locale('de'), Locale('en'), Locale('pt'), Locale('es')];

/// Picks one of up to four hand-written labels for the live language.
///
/// This is for the **content catalogs** — `grocery_catalog.dart` and
/// `icon_suggestions.dart` — and deliberately not for the
/// app's own words, which go through [AppStrings] where a forgotten string is a
/// compile error. Content cannot work that way: a grocery PNG dropped into the
/// folder needs one German line to be usable, and holding the whole catalog
/// hostage to four translations would mean nobody ever adds an icon.
///
/// So [pt] and [es] are nullable and fall back to [en] rather than to [de] —
/// English is the one an untranslated row is most likely to be guessed from.
/// One row in the wrong language is a great deal better than a blank row or a
/// build that won't run, and `tool/check_catalog_labels.dart` reports what is
/// still missing.
String pickLabel({required String de, required String en, String? pt, String? es}) =>
    switch (L.s.localeCode) {
      'en' => en,
      'pt' => pt ?? en,
      'es' => es ?? en,
      _ => de,
    };

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
