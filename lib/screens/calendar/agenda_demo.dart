part of '../calendar_screen.dart';

// ignore_for_file: dead_code

/// **A day full of the cases the real calendar rarely has, for designing the
/// agenda against.**
///
/// Turn [_agendaDemo] on, hot reload, and every day in both the week view and
/// the month view's day panel is replaced by the set below — built to exercise
/// the grid rather than to look like a nice day: two all-day events for the
/// band, three appointments starting at the same minute, a long workday that
/// forces a second column and lets everything beside it spread right, two more
/// colliding in the afternoon, a to-do sharing an hour with an appointment, a
/// title no block can hold, and a five-minute reminder for [_minSlotMinutes].
/// Turn it off and the real calendar comes straight back — nothing here is
/// reachable while it is `false`, and nothing outside this file knows the flag
/// exists beyond the one call in [_demoEvents].
///
/// **This file is scaffolding and is meant to be deleted** once the agenda
/// design has settled. It holds no strings from [AppStrings] on purpose: the
/// titles are stand-ins for a household's own words, not user-facing copy, and
/// putting them through the four languages would make a throwaway file
/// expensive to throw away.
///
/// **Leave this `false` on `main`.**
const bool _agendaDemo = false;

/// The real day, or the fake one while [_agendaDemo] is on.
///
/// Hooked here rather than inside [_dayPlan] because the fake set has to be
/// built *for a date*, and a day with nothing on it hands the two call sites no
/// events to take one from.
List<CalendarEvent> _demoEvents(List<CalendarEvent> real, DateTime day) => _agendaDemo ? _demoDay(day) : real;

/// The same, for the to-dos the agenda merges into the clock.
///
/// Three of them: two owed by the end of the day (one ticked), which is where
/// most to-dos sit and which belong in the band rather than on the clock, and
/// one at 14:00 colliding with two appointments — the case that decides whether
/// an outlined to-do block and a filled appointment can share a column group
/// without reading as the same thing.
List<BoardTask> _demoTodos(List<BoardTask> real, DateTime day) => _agendaDemo ? _demoTaskDay(day) : real;

List<BoardTask> _demoTaskDay(DateTime day) {
  BoardTask task(String id, String text, {DueTime? at, bool done = false}) => BoardTask(
    id: 'demo-$id',
    familyId: 'demo',
    text: text,
    ownerId: 'demo',
    dueDate: DateTime(day.year, day.month, day.day),
    dueTime: at,
    done: done,
  );

  return [
    task('t1', 'Turnbeutel packen'),
    task('t2', 'Müll rausbringen', done: true),
    task('t3', 'Rezept abholen', at: const DueTime(14, 0)),
  ];
}

List<CalendarEvent> _demoDay(DateTime day) {
  CalendarEvent at(
    String id,
    String title,
    int fromHour,
    int fromMin,
    int toHour,
    int toMin,
    String source,
    Color color, {
    String loc = '',
  }) => CalendarEvent(
    id: 'demo-$id',
    calendarId: 'demo-cal',
    title: title,
    startsAt: DateTime(day.year, day.month, day.day, fromHour, fromMin),
    endsAt: DateTime(day.year, day.month, day.day, toHour, toMin),
    source: source,
    srcColor: color,
    loc: loc,
  );

  CalendarEvent allDay(String id, String title, String source, Color color) => CalendarEvent(
    id: 'demo-$id',
    calendarId: 'demo-cal',
    title: title,
    startsAt: DateTime(day.year, day.month, day.day),
    endsAt: DateTime(day.year, day.month, day.day + 1),
    allDay: true,
    source: source,
    srcColor: color,
  );

  return [
    // The band: two things true of the whole day, neither of them at a time.
    allDay('a1', 'Altpapier', 'Abfall', const Color(0xFF3B82F6)),
    allDay('a2', 'Herbstferien', 'Ferien', const Color(0xFFF59E0B)),

    // Three starting on the same minute — three columns, all of them equal.
    at('b1', 'Zahnarzt Lena', 8, 45, 9, 30, 'Familie', const Color(0xFF8B5CF6), loc: 'Berlin'),
    at('b2', 'Elternsprechtag Grundschule', 8, 45, 10, 0, 'Schule', const Color(0xFF10B981)),
    at('b3', 'Standup', 8, 45, 9, 0, 'Arbeit', const Color(0xFFEF4444)),

    // The long one. It holds a second column open all day, which is what makes
    // the spread-right step visible: everything below that doesn't overlap it
    // still widens into the columns the morning needed and it doesn't.
    at('c0', 'Arbeitstag', 9, 0, 17, 0, 'Arbeit', const Color(0xFFEF4444)),

    // Beside the workday, and nothing else — so each of these is one column
    // wide rather than three.
    at('c1', 'Einkaufen Rewe', 10, 30, 11, 15, 'Familie', const Color(0xFF8B5CF6), loc: 'Hamburg'),

    // Five minutes: shorter than [_minSlotMinutes], so the block is drawn at
    // the floor rather than as a coloured hairline.
    at('c2', 'Tabletten', 11, 30, 11, 35, 'Familie', const Color(0xFF8B5CF6)),

    // Two colliding, one with a title no block can hold.
    at('d1', 'Fußballtraining', 14, 0, 15, 30, 'Sport', const Color(0xFF0EA5E9)),
    at(
      'd2',
      'Kinderarzt Vorsorgeuntersuchung U9 Praxis Dr. Müller',
      14,
      0,
      14,
      45,
      'Familie',
      const Color(0xFF8B5CF6),
      loc: 'München',
    ),

    // Late and on its own, so the grid's window has to stretch to the evening.
    at('e1', 'Abendessen mit Oma', 18, 30, 20, 0, 'Familie', const Color(0xFF8B5CF6), loc: 'Köln'),
  ];
}
