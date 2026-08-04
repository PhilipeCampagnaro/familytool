import 'calendar_data.dart' show monthNames, weekdayLong;

/// Strips the time off a [DateTime] so it can be compared and used as a map
/// key. Board's state maps depend on this — two `DateTime`s are only equal if
/// their microseconds match exactly.
DateTime boardDay(DateTime d) => DateTime(d.year, d.month, d.day);

/// The Monday-based week containing [now], as seven midnight-normalised dates.
///
/// Board keys everything by date rather than by day-of-month: a real week
/// regularly straddles two months (31. Juli – 6. August), and a bare `int` day
/// would collide the moment it did.
List<DateTime> boardWeekOf(DateTime now) {
  final monday = boardDay(now).subtract(Duration(days: now.weekday - 1));
  return [for (var i = 0; i < 7; i++) monday.add(Duration(days: i))];
}

bool boardIsSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Mo–So, indexed by `DateTime.weekday - 1` (1 = Monday).
const _dayLetters = ['M', 'D', 'M', 'D', 'F', 'S', 'S'];

String boardDayLetter(DateTime d) => _dayLetters[d.weekday - 1];

/// 'August 2026' — taken from the week's Thursday, which is the ISO rule for
/// which month and year a week belongs to when it spans two.
String boardMonthLabel(List<DateTime> week) {
  final thursday = week[3];
  return '${monthNames[thursday.month]} ${thursday.year}';
}

/// '10. – 16. August', or '31. Juli – 6. August' across a month boundary.
String boardWeekRange(List<DateTime> week) {
  final first = week.first;
  final last = week.last;
  if (first.month == last.month) {
    return '${first.day}. – ${last.day}. ${monthNames[last.month]}';
  }
  return '${first.day}. ${monthNames[first.month]} – ${last.day}. ${monthNames[last.month]}';
}

/// 'Donnerstag, 13. Aug'. [weekdayLong] is Sunday-first, hence the `% 7`.
String boardLongDayName(DateTime d) =>
    '${weekdayLong[d.weekday % 7]}, ${d.day}. ${monthNames[d.month].substring(0, 3)}';

// The empty `boardTasksByDay` seed map is gone: tasks are `public.tasks` rows
// now, loaded by `BoardRepository.fetchRange` into `BoardState.tasksByDay`.
// Only the date helpers above are still shared — they are what keys that map.
