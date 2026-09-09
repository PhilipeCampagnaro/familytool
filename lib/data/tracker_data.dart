import '../models/tracker.dart';
import 'board_data.dart';

/// How much history the Board keeps in view — the window the checks are loaded
/// over and the furthest back the header grid can reach.
///
/// It replaces `BoardStreakCache.retentionDays`, which measured the same span on
/// the device. The record is `public.tracker_checks` now, so both parents see
/// one grid instead of whatever their own phone happened to witness.
const int trackerHistoryDays = 180;

/// The Monday of [day]'s week, midnight-normalised.
///
/// Monday because the household is German and the rest of the Board already
/// closes its week on Sunday — `boardSectionForDate` builds "Diese Woche" from
/// `7 - today.weekday`, which is only the rest of the week if the week runs
/// Mo–So. A weekly target resets here.
DateTime trackerWeekStart(DateTime day) => boardDaysAfter(day, 1 - day.weekday);

/// Whether [tracker] is due on [day] — the whole of what "scheduled" means.
///
/// **False for every weekly-count tracker, always.** "Vier Tage pro Woche" names
/// no day, so there is no honest answer; asking is the caller's mistake and
/// [TrackerSchedule.isDayBased] is how they avoid making it. Callers that need
/// to know how a weekly tracker is doing want [trackerWeekDone] instead.
bool isTrackerDueOn(Tracker tracker, DateTime day) {
  final at = boardDay(day);
  if (at.isBefore(tracker.startsOn)) return false;
  if (tracker.archivedAt case final archived?) {
    if (!at.isBefore(boardDay(archived))) return false;
  }
  return switch (tracker.schedule.kind) {
    TrackerScheduleKind.daily => true,
    TrackerScheduleKind.weekdays => tracker.schedule.weekdays.contains(at.weekday),
    TrackerScheduleKind.weeklyCount => false,
  };
}

/// The trackers the Board puts on today's card, in a stable order.
///
/// Day-based ones only when they fall on [today]; weekly-count ones every day,
/// because any day is a fine day to knock one off. A weekly tracker whose week
/// is already full stays on the card rather than disappearing — vanishing on
/// Thursday would read as somebody having deleted it.
List<Tracker> trackersOn(List<Tracker> trackers, DateTime today) => _ordered([
  for (final t in trackers)
    if (!t.isArchived)
      if (t.schedule.isDayBased ? isTrackerDueOn(t, today) : !boardDay(today).isBefore(t.startsOn)) t,
]);

/// Everything else the household keeps — the trackers today's rhythms say
/// nothing about.
///
/// The card folds these in behind one row rather than dropping them, because a
/// tracker now has a screen of its own and a Montag/Donnerstag rhythm that
/// vanishes from Dienstag to Mittwoch is a record nobody can look at for five
/// days a week. They are not owed today, so they carry no check circle; being
/// listed is not the same as being due, and only the circle says the second
/// thing.
List<Tracker> trackersOffToday(List<Tracker> trackers, DateTime today) {
  final due = {for (final t in trackersOn(trackers, today)) t.id};
  return _ordered([
    for (final t in trackers)
      if (!t.isArchived && !due.contains(t.id)) t,
  ]);
}

/// Day-based first — those are the ones a day can actually owe — then oldest
/// first, so a card does not reshuffle itself as trackers are ticked.
List<Tracker> _ordered(List<Tracker> trackers) {
  final sorted = [...trackers];
  sorted.sort((a, b) {
    final byKind = (a.schedule.isDayBased ? 0 : 1).compareTo(b.schedule.isDayBased ? 0 : 1);
    if (byKind != 0) return byKind;
    final aMade = a.createdAt;
    final bMade = b.createdAt;
    if (aMade != null && bMade != null && aMade != bMade) return aMade.compareTo(bMade);
    return a.text.compareTo(b.text);
  });
  return sorted;
}

/// How many days of [tracker]'s week containing [day] are already ticked.
///
/// Counts every check in the week, whatever the rhythm: a daily tracker can
/// report "5 von 7" with the same call. Days outside the loaded window simply
/// are not in [checkedDays] and so do not count, which is why the window is a
/// good deal longer than any week.
int trackerWeekDone(Set<DateTime> checkedDays, DateTime day) {
  final monday = trackerWeekStart(day);
  var done = 0;
  for (var i = 0; i < 7; i++) {
    if (checkedDays.contains(boardDaysAfter(monday, i))) done++;
  }
  return done;
}

/// The current streak: consecutive **scheduled periods** kept, days for a
/// day-based rhythm and weeks for a weekly count.
///
/// Two rules make it read the way a household expects:
///
/// * **Unscheduled days are skipped, not broken.** A Donnerstag tracker keeps
///   its streak over the six days in between; counting those as misses would
///   make every non-daily rhythm permanently zero.
/// * **Today is never a miss while it is still today.** An unticked Donnerstag
///   at nine in the morning would otherwise wipe out eleven weeks, and the
///   number would only be right after bedtime. The same goes for the current
///   week of a weekly count.
int trackerStreak(Tracker tracker, Set<DateTime> checkedDays, DateTime today) =>
    tracker.schedule.isDayBased
        ? _dayStreak(tracker, checkedDays, boardDay(today))
        : _weekStreak(tracker, checkedDays, boardDay(today));

int _dayStreak(Tracker tracker, Set<DateTime> checkedDays, DateTime today) {
  var day = today;
  if (isTrackerDueOn(tracker, today) && !checkedDays.contains(today)) {
    day = boardDaysAfter(today, -1);
  }

  var streak = 0;
  // Bounded by the window the checks were loaded over: past it every day would
  // look unticked and the walk would report a break that is really just the
  // edge of what we asked for.
  for (var i = 0; i < trackerHistoryDays; i++) {
    if (day.isBefore(tracker.startsOn)) break;
    if (isTrackerDueOn(tracker, day)) {
      if (!checkedDays.contains(day)) break;
      streak++;
    }
    day = boardDaysAfter(day, -1);
  }
  return streak;
}

int _weekStreak(Tracker tracker, Set<DateTime> checkedDays, DateTime today) {
  final target = tracker.schedule.target;
  if (target <= 0) return 0;

  var monday = trackerWeekStart(today);
  // This week is not a miss until Sunday has closed, so it only ever adds.
  if (trackerWeekDone(checkedDays, monday) < target) monday = boardDaysAfter(monday, -7);

  final firstWeek = trackerWeekStart(tracker.startsOn);
  var streak = 0;
  for (var i = 0; i < trackerHistoryDays ~/ 7; i++) {
    if (monday.isBefore(firstWeek)) break;
    // The week the tracker started in is usually a part week — a Thursday start
    // cannot have four days in it — so the walk stops there rather than calling
    // it a miss and capping every streak at the age of the tracker.
    if (monday == firstWeek && tracker.startsOn != firstWeek) break;
    if (trackerWeekDone(checkedDays, monday) < target) break;
    streak++;
    monday = boardDaysAfter(monday, -7);
  }
  return streak;
}

/// What the header grid draws: for every past day, how many trackers were due
/// and how many of those were kept.
///
/// **Day-based trackers only.** A weekly count owes nothing on any given day, so
/// counting its checks here would produce days with more done than planned — a
/// square darker than full, off a plan that never existed. Those report on their
/// own row instead, as "2 von 4 diese Woche".
///
/// This replaces `boardDayTallies`, which counted whatever tasks happened to
/// fall on a day. That is the whole reason a one-off to-do read as a habit: the
/// grid was measuring the wrong thing, not labelling it badly.
Map<DateTime, BoardDayTally> trackerDayTallies(
  List<Tracker> trackers,
  Map<String, Set<DateTime>> checksByTracker,
  DateTime today,
) {
  final tallies = <DateTime, BoardDayTally>{};
  final from = boardDay(today);

  for (final tracker in trackers) {
    if (!tracker.schedule.isDayBased) continue;
    final checks = checksByTracker[tracker.id] ?? const <DateTime>{};

    for (var i = 0; i < trackerHistoryDays; i++) {
      final day = boardDaysAfter(from, -i);
      if (day.isBefore(tracker.startsOn)) break;
      if (!isTrackerDueOn(tracker, day)) continue;

      final seen = tallies[day] ?? const BoardDayTally();
      tallies[day] = BoardDayTally(
        done: seen.done + (checks.contains(day) ? 1 : 0),
        planned: seen.planned + 1,
      );
    }
  }
  return tallies;
}

// -----------------------------------------------------------------------------
// One tracker's own record — what the detail screen's chart is drawn from.
// -----------------------------------------------------------------------------

/// How one day reads on a single tracker's chart.
///
/// The Board header's grid has no equivalent because it is an aggregate: there
/// "nothing planned" covers a day off, a day before the household kept anything
/// and a day whose trackers all started later. On one tracker those are
/// different facts, and a day the rhythm never asked for must not be drawn like
/// a day it asked for and did not get — five grey squares a week is what a
/// Montag/Donnerstag tracker would otherwise report, and it reads as failure.
enum TrackerDayMark {
  /// Outside the tracker's life — before it started, or still to come. Drawn as
  /// nothing at all rather than as an empty square, so the chart starts where
  /// the tracker did.
  blank,

  /// The rhythm asked nothing of this day.
  notDue,

  /// Asked for, and not kept.
  missed,

  /// Kept.
  kept,
}

/// What [day] looks like for [tracker], given the days it was ticked.
///
/// **The rhythm is read as it is now, not as it was then** — the same property
/// [trackerStreak] has, and for the same reason: which days were due is computed
/// from the rule and nothing stores the old one. Widening a tracker from two
/// weekdays to daily therefore repaints the past as missed days. That is a
/// consequence of not materialising the future, and the trade is deliberate; the
/// alternative is a table of dated rows nobody ever asked for.
///
/// [TrackerDayMark.kept] is decided before the rhythm is consulted, so a check
/// on a day the rule no longer names still shows as kept rather than
/// disappearing. A day somebody did the thing is not something an edit should be
/// able to erase.
TrackerDayMark trackerDayMark(Tracker tracker, Set<DateTime> checkedDays, DateTime day, DateTime today) {
  final at = boardDay(day);
  if (at.isAfter(boardDay(today))) return TrackerDayMark.blank;
  if (at.isBefore(tracker.startsOn)) return TrackerDayMark.blank;
  if (checkedDays.contains(at)) return TrackerDayMark.kept;
  // A weekly count owes no particular day, so no day of one can be missed —
  // see [isTrackerDueOn], which says the same thing by returning false.
  if (!tracker.schedule.isDayBased) return TrackerDayMark.notDue;
  return isTrackerDueOn(tracker, at) ? TrackerDayMark.missed : TrackerDayMark.notDue;
}

/// Whether [day] may be ticked or un-ticked on [tracker] — what makes the
/// detail chart's squares pressable.
///
/// Back-filling is the whole point of the chart being tappable: forgetting to
/// tick on the evening is the ordinary failure, and a record that cannot be
/// corrected stops being one people trust. It is bounded on three sides —
/// nothing in the future, nothing before the tracker existed, nothing past the
/// window the checks were loaded over (a day outside it looks unticked whatever
/// the database holds, so a tap there would silently write a duplicate).
///
/// A day-based tracker takes ticks **only on days its rhythm names**. Allowing
/// any day would let a Montag tracker collect Sonntag checks that count towards
/// no streak and appear on no plan.
bool canToggleTrackerOn(Tracker tracker, DateTime day, DateTime today) {
  final at = boardDay(day);
  final now = boardDay(today);
  if (at.isAfter(now)) return false;
  if (at.isBefore(tracker.startsOn)) return false;
  if (now.difference(at).inDays >= trackerHistoryDays) return false;
  return tracker.schedule.isDayBased ? isTrackerDueOn(tracker, at) : true;
}

/// One week of a weekly-count tracker, for the bar chart on its detail screen.
class TrackerWeekRecord {
  /// Midnight-normalised Monday — see [trackerWeekStart].
  final DateTime monday;

  /// Days ticked in that week. Can exceed the target: a household that manages
  /// five days on a four-day rhythm did five, and rounding that down to the
  /// promise would be the app marking its own homework.
  final int done;

  const TrackerWeekRecord({required this.monday, required this.done});
}

/// The last [weeks] weeks of [tracker], newest first.
///
/// Weeks rather than days because a weekly count names no day: a day grid of one
/// would be a field of "not due" with ticks scattered through it, which says
/// nothing about the only promise the tracker made. Stops at the week the
/// tracker started in — a part week before it existed is not a week it missed.
List<TrackerWeekRecord> trackerWeekRecords(
  Tracker tracker,
  Set<DateTime> checkedDays,
  DateTime today, {
  int weeks = 12,
}) {
  final firstWeek = trackerWeekStart(tracker.startsOn);
  final limit = weeks.clamp(1, trackerHistoryDays ~/ 7);
  final records = <TrackerWeekRecord>[];

  var monday = trackerWeekStart(today);
  for (var i = 0; i < limit; i++) {
    if (monday.isBefore(firstWeek)) break;
    records.add(TrackerWeekRecord(monday: monday, done: trackerWeekDone(checkedDays, monday)));
    monday = boardDaysAfter(monday, -7);
  }
  return records;
}
