import '../l10n/l10n.dart';
import '../models/task.dart';

/// Strips the time off a [DateTime] so two dates can be compared for "same
/// day" — `DateTime`s are only equal if their microseconds match exactly.
DateTime boardDay(DateTime d) => DateTime(d.year, d.month, d.day);

/// [days] calendar days after [day], normalised to midnight.
///
/// **Not `day.add(Duration(days: days))`.** A `Duration` is a fixed number of
/// hours, and the two days Germany changes clocks are 23 and 25 hours long — so
/// on the last Sunday in October "tomorrow" computed that way lands at 23:00
/// *today*, and every `==` comparison against a midnight-normalised date fails.
/// `DateTime`'s constructor rolls an out-of-range day into the next month by
/// itself, so this stays correct across month and year ends too.
DateTime boardDaysAfter(DateTime day, int days) => DateTime(day.year, day.month, day.day + days);

bool boardIsSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// 'Donnerstag, 13. Aug'. The weekday list is Sunday-first, hence the `% 7`.
String boardLongDayName(DateTime d) => L.s.weekdayWithDateShort(d.weekday % 7, d.day, d.month);

/// The buckets the Board renders open tasks in, in the order it renders them.
///
/// The Board used to *be* a day — a week strip picked one and its tasks hung
/// underneath — which is why `due_date` was `not null`. It is a grouped list
/// now, so a date is a property of a task rather than the axis of the screen,
/// and [undated] is an ordinary section rather than a hole in the model.
///
/// Chronological, with [undated] last: the list reads forwards in time, and the
/// two triage buckets ([overdue] at the top, [undated] at the bottom) sit at the
/// ends where they don't push "Heute" off the first screen.
enum BoardSection { overdue, today, tomorrow, thisWeek, later, undated }

/// Which bucket [task] falls in, relative to [today] (pass a midnight-normalised
/// date — [boardDay] of the device clock in production).
///
/// "Diese Woche" is the rest of the *calendar* week, not the next seven days:
/// the section is labelled "Diese Woche", and a Saturday that swept in the
/// following Thursday would be lying. Late in the week the section is simply
/// empty and everything falls through to [BoardSection.later].
BoardSection boardSectionOf(BoardTask task, DateTime today) {
  final due = task.dueDate;
  if (due == null) return BoardSection.undated;

  final day = boardDay(due);
  if (day.isBefore(today)) return BoardSection.overdue;
  if (day == today) return BoardSection.today;

  if (day == boardDaysAfter(today, 1)) return BoardSection.tomorrow;

  // The Sunday closing the week `today` is in. Built off `today` rather than off
  // the task so a task in a later week can never be mistaken for this one.
  final sunday = boardDaysAfter(today, 7 - today.weekday);
  if (!day.isAfter(sunday)) return BoardSection.thisWeek;

  return BoardSection.later;
}

/// One rendered section: the bucket, and the open tasks in it.
class BoardGroup {
  final BoardSection section;
  final List<BoardTask> tasks;

  const BoardGroup({required this.section, required this.tasks});
}

/// The open tasks, bucketed and sorted, with empty sections dropped.
///
/// Within a section tasks run by date and then by creation, so a section
/// spanning several days ("Später", "Überfällig") still reads forwards in time.
/// Done tasks are not here — they have their own card at the foot of the screen,
/// where the date they were due stops mattering.
List<BoardGroup> boardGroups(List<BoardTask> tasks, DateTime today) {
  final bySection = <BoardSection, List<BoardTask>>{};
  for (final task in tasks) {
    if (task.done) continue;
    (bySection[boardSectionOf(task, today)] ??= []).add(task);
  }

  final groups = <BoardGroup>[];
  for (final section in BoardSection.values) {
    final found = bySection[section];
    if (found == null || found.isEmpty) continue;
    found.sort(_byDueThenCreated);
    groups.add(BoardGroup(section: section, tasks: found));
  }
  return groups;
}

/// Undated tasks sort among themselves by creation alone — they are all equally
/// "whenever", and inventing an order between them would only make the list
/// jump around.
int _byDueThenCreated(BoardTask a, BoardTask b) {
  final aDue = a.dueDate;
  final bDue = b.dueDate;
  if (aDue != null && bDue != null && aDue != bDue) return aDue.compareTo(bDue);
  final aMade = a.createdAt;
  final bMade = b.createdAt;
  if (aMade == null || bMade == null) return 0;
  return aMade.compareTo(bMade);
}

/// One day's square in the header's tracker strip: how many tasks were due on
/// that day, and how many of them are ticked off.
///
/// Two counts rather than one ratio, because the strip has to tell a day nobody
/// planned anything on apart from a day nothing got done on — the first is a
/// blank, the second is a miss, and a bare `0.0` cannot say which.
class BoardDayTally {
  final int done;
  final int planned;

  const BoardDayTally({this.done = 0, this.planned = 0});

  bool get isEmpty => planned == 0;

  bool get complete => planned > 0 && done >= planned;

  /// 0..1, and 0 for an empty day — callers must check [isEmpty] first rather
  /// than read this as "nothing done".
  double get ratio => planned == 0 ? 0 : (done / planned).clamp(0.0, 1.0);
}

/// What the loaded tasks say about every day up to and including [today].
///
/// Keyed by the **due** date, not by when a task was ticked off: the strip
/// answers the same question the progress bar above it answers for today — did
/// this day's plan get finished — so a task done three days late still counts
/// for the day it was due. Keying by `done_at` would instead credit a Sunday
/// spent clearing out old tasks as the best day of the month.
///
/// Days with a future due date are left out. They have not happened, and a
/// tracker that draws tomorrow as a miss would never show a full row.
Map<DateTime, BoardDayTally> boardDayTallies(List<BoardTask> tasks, DateTime today) {
  final tallies = <DateTime, BoardDayTally>{};
  for (final task in tasks) {
    final due = task.dueDate;
    if (due == null) continue;
    final day = boardDay(due);
    if (day.isAfter(today)) continue;
    final seen = tallies[day] ?? const BoardDayTally();
    tallies[day] = BoardDayTally(
      done: seen.done + (task.done ? 1 : 0),
      planned: seen.planned + 1,
    );
  }
  return tallies;
}

// `boardSectionDefaultDate` went with the per-section `+` buttons: nothing asks
// what date a section would pre-fill any more, because no header adds into
// itself. The empty `boardTasksByDay` seed map is gone: tasks are `public.tasks` rows
// now, loaded by `BoardRepository.fetchBoard` into `BoardState.tasks`.
// `boardMonthLabel`/`boardWeekRange` went with the week strip — the header
// names one day (today) now, not a week.
