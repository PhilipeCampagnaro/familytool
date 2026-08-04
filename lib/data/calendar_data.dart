library;

/// Calendar reference data: the device's idea of "today", and the German names
/// the month and week views print.
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

const monthNames = ['', 'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'];
const monthShort = ['', 'Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'];
const weekdayShort = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'];
const weekdayLong = ['Sonntag', 'Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag'];
const dayLetters = ['M', 'D', 'M', 'D', 'F', 'S', 'S'];
