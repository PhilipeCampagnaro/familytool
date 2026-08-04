library;

import '../l10n/l10n.dart';

/// Calendar reference data: the device's idea of "today", and the month and
/// weekday names the month and week views print, in the interface language.
///
/// Everything that used to live here — the seed `schedule`, the `monthData`
/// holiday/dot table, the `EventSource` enum — is gone, because all three are
/// now real data. Events and calendars come from Supabase via
/// `CalendarRepository`, and holidays arrive as ordinary all-day events on a
/// connected Ferien calendar rather than as a hardcoded list of day numbers.

/// The real current date, midnight-normalised. Used for "is this today"
/// highlighting and for where the calendar opens.
DateTime calToday() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

// These were `const` lists of German names. They are getters now so that
// switching the language in Settings switches the calendar's month and weekday
// names with it — the call sites are unchanged, they just stop being constant.
// Nothing may put one of these in a `const` expression again.

/// 1-based, so `monthNames[DateTime.month]` indexes directly. Index 0 is empty.
List<String> get monthNames => L.s.monthNames;
List<String> get monthShort => L.s.monthShort;

/// Sunday-first, indexed by `DateTime.weekday % 7`.
List<String> get weekdayShort => L.s.weekdayShort;
List<String> get weekdayLong => L.s.weekdayLong;

/// Monday-first single letters under the month grid.
List<String> get dayLetters => L.s.dayLetters;
