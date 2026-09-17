import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../models/calendar_event.dart';
import '../models/task.dart';
import '../services/local_notifications.dart';
import 'auth_state.dart';
import 'board_state.dart';
import 'calendar_state.dart';
import 'notification_state.dart';
import 'settings_state.dart';

/// Below iOS's 64, which silently drops everything past the soonest 64 pending
/// requests. The margin is not for safety: it is so nothing we send is ever the
/// one that gets dropped.
const kNoticeBudget = 60;

/// How far ahead anything is scheduled. Every foreground re-derives the set, so
/// this only has to outlast the longest stretch a phone goes without Aporah
/// being opened — and the further ahead a notice is written, the likelier the
/// appointment under it has moved.
const kNoticeHorizon = Duration(days: 14);

/// **Every notification this device should post, derived from scratch.**
///
/// A pure function of what is on screen, so the scheduler never "adds" a
/// notification and never has to find one to take back: an appointment that
/// moved simply produces a different set, and `replaceAll` swaps it in. Soonest
/// first, capped at [kNoticeBudget].
///
/// Four kinds, and the principle behind all of them is in docs/notifications.md
/// — **a deadline or somebody's name on it, never a creation**:
///
/// * a reminder the user set on an appointment;
/// * the evening before a waste pickup;
/// * the morning brief — skipped on a day with nothing in it, rather than
///   saying so;
/// * a to-do that names an hour, for whoever it is assigned to or anybody when
///   it is nobody's.
List<ScheduledNotice> composeNotices({
  required DateTime now,
  required NotificationSettings settings,
  required CalendarScreenState calendar,
  required List<BoardTask> tasks,
  required String? userId,
}) {
  final out = <ScheduledNotice>[];
  final until = now.add(kNoticeHorizon);
  bool inWindow(DateTime at) => at.isAfter(now) && at.isBefore(until);

  final feedKinds = {for (final c in calendar.calendars) c.id: c.feedKind};

  // Each appointment once. A multi-day event sits in the list of every day it
  // covers, and the day map spans far more than the horizon.
  final events = <String, CalendarEvent>{};
  final earliest = now.subtract(const Duration(days: 2));
  final latest = until.add(const Duration(days: 2));
  for (final day in calendar.eventsByDay.values) {
    for (final e in day) {
      if (e.startsAt.isBefore(earliest) || e.startsAt.isAfter(latest)) continue;
      events.putIfAbsent(e.id, () => e);
    }
  }

  bool mine(BoardTask t) => t.assigneeId == null || t.assigneeId == userId;

  // -- Reminders on appointments ---------------------------------------------
  for (final r in settings.reminders) {
    for (final e in events.values) {
      if (!r.matches(e)) continue;
      final at = e.startsAt.subtract(Duration(minutes: r.minutesBefore));
      if (!inWindow(at)) continue;
      final day =
          '${L.s.weekdayShort[e.startsAt.weekday % 7]}, '
          '${L.s.dayMonthShort(e.startsAt.day, e.startsAt.month)}';
      out.add(
        ScheduledNotice(
          id: 'event:${e.id}:${r.minutesBefore}',
          at: at,
          title: e.title,
          body: ['$day · ${e.timeRangeLabel}', if (e.loc.trim().isNotEmpty) e.loc.trim()].join(' · '),
          thread: 'events',
        ),
      );
    }
  }

  // -- The bins, the evening before -------------------------------------------
  if (settings.abfall) {
    final bins = <DateTime, List<String>>{};
    for (final e in events.values) {
      if (feedKinds[e.calendarId] != 'abfall') continue;
      final day = DateTime(e.startsAt.year, e.startsAt.month, e.startsAt.day);
      final names = bins[day] ??= [];
      if (!names.contains(e.title)) names.add(e.title);
    }
    for (final MapEntry(key: day, value: names) in bins.entries) {
      // The calendar day before, not 24 hours before: across a clock change
      // those are an hour apart.
      final at = DateTime(
        day.year,
        day.month,
        day.day - 1,
        settings.abfallMinutes ~/ 60,
        settings.abfallMinutes % 60,
      );
      if (!inWindow(at)) continue;
      out.add(
        ScheduledNotice(
          id: 'abfall:${day.year}-${day.month}-${day.day}',
          at: at,
          // The vendor's own word for the bin — "Bioabfall", "Gelber Sack" —
          // because that is what is written on the calendar the family reads.
          title: L.s.noticeAbfallTitle(L.s.joinAnd(names)),
          body: L.s.noticeAbfallBody,
          thread: 'abfall',
        ),
      );
    }
  }

  // -- The morning brief -------------------------------------------------------
  //
  // Today's and tomorrow's only. It is composed from what the phone holds now,
  // so a brief written further ahead would be a guess, and a household that has
  // not opened the app in three days is better served by no brief than by a
  // wrong one.
  if (settings.brief) {
    for (var offset = 0; offset < 2; offset++) {
      final day = DateTime(now.year, now.month, now.day + offset);
      final at = DateTime(
        day.year,
        day.month,
        day.day,
        settings.briefMinutes ~/ 60,
        settings.briefMinutes % 60,
      );
      if (!inWindow(at)) continue;

      // Ferien and Abfall are context, not appointments. The bins have gone by
      // seven anyway; that reminder was last night's.
      final dayEvents = [
        for (final e
            in calendar.eventsByDay[CalendarScreenState.key(day.year, day.month, day.day)] ??
                const <CalendarEvent>[])
          if ((feedKinds[e.calendarId] ?? '').isEmpty) e,
      ];
      final timed = [
        for (final e in dayEvents)
          if (!e.allDay && _sameDay(e.startsAt, day)) e.startsAt,
      ]..sort();
      final due = tasks
          .where((t) => !t.done && t.dueDate != null && _sameDay(t.dueDate!, day) && mine(t))
          .length;
      if (dayEvents.isEmpty && due == 0) continue;

      out.add(
        ScheduledNotice(
          id: 'brief:${day.year}-${day.month}-${day.day}',
          at: at,
          title: L.s.noticeBriefTitle,
          body: [
            if (dayEvents.isNotEmpty)
              timed.isEmpty
                  ? L.s.briefEvents(dayEvents.length)
                  : '${L.s.briefEvents(dayEvents.length)} ${L.s.briefFirstAt(formatTime(timed.first))}',
            if (due > 0) L.s.briefTasks(due),
          ].join(' · '),
          thread: 'brief',
        ),
      );
    }
  }

  // -- To-dos that name an hour ------------------------------------------------
  if (settings.taskTimes) {
    for (final t in tasks) {
      final date = t.dueDate;
      final time = t.dueTime;
      if (t.done || date == null || time == null || !mine(t)) continue;
      final at = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      if (!inWindow(at)) continue;
      out.add(
        ScheduledNotice(
          id: 'task:${t.id}',
          at: at,
          title: t.text,
          body: L.s.noticeTaskDue(formatTimeOfDay(time.hour, time.minute)),
          thread: 'tasks',
        ),
      );
    }
  }

  out.sort((a, b) => a.at.compareTo(b.at));
  return out.length > kNoticeBudget ? out.sublist(0, kNoticeBudget) : out;
}

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Keeps the device's pending notifications equal to [composeNotices].
///
/// Poked by anything that could change the answer — the calendar, the to-dos,
/// the settings, the language, the account — and by every return to the app.
/// Pokes are coalesced, and a derivation identical to the last one sent never
/// crosses the channel, so the calendar's 30-second clock costs nothing.
class NoticeScheduler {
  NoticeScheduler(this._ref);

  final Ref _ref;
  final _os = const LocalNotifications();

  Timer? _debounce;
  String? _lastSignature;
  bool _disposed = false;

  void poke() {
    if (_disposed || !localNotificationsAvailable) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () => unawaited(_run()));
  }

  Future<void> _run() async {
    if (_disposed) return;
    final settings = _ref.read(notificationSettingsProvider);
    if (!settings.loaded) return;

    final userId = _ref.read(currentUserIdProvider);
    final calendar = _ref.read(calendarProvider);
    final board = _ref.read(boardProvider);

    // **Wait for real data rather than scheduling from none.** Composing before
    // the calendar or the to-dos have loaded would replace last session's
    // reminders with an empty set, and a phone locked in that second would miss
    // them. Signed out is the exception: there, empty is the right answer.
    if (userId != null && ((!calendar.loaded && calendar.eventsByDay.isEmpty) || board.loading)) return;

    final notices = userId == null || !settings.access.delivers
        ? const <ScheduledNotice>[]
        : composeNotices(
            now: DateTime.now(),
            settings: settings,
            calendar: calendar,
            tasks: board.tasks,
            userId: userId,
          );

    final signature = '${L.s.localeCode}\n${notices.map((n) => n.signature).join('\n')}';
    if (signature == _lastSignature) return;
    _lastSignature = signature;
    await _os.replaceAll(notices, channelName: L.s.notificationsTitle);

    if (userId != null && calendar.loaded) {
      _ref
          .read(notificationSettingsProvider.notifier)
          .pruneReminders(DateTime.now().subtract(const Duration(days: 1)));
    }
  }

  void dispose() {
    _disposed = true;
    _debounce?.cancel();
  }
}

/// Watched by the app shell, which is what keeps it alive for the session.
final noticeSchedulerProvider = Provider<NoticeScheduler>((ref) {
  final scheduler = NoticeScheduler(ref);
  ref.onDispose(scheduler.dispose);
  if (!localNotificationsAvailable) return scheduler;

  ref.listen(calendarProvider.select((s) => s.eventsByDay), (_, _) => scheduler.poke());
  ref.listen(calendarProvider.select((s) => s.calendars), (_, _) => scheduler.poke());
  ref.listen(boardProvider.select((s) => s.tasks), (_, _) => scheduler.poke());
  ref.listen(notificationSettingsProvider, (_, _) => scheduler.poke());
  ref.listen(settingsProvider.select((s) => s.language), (_, _) => scheduler.poke());
  ref.listen(currentUserIdProvider, (_, _) => scheduler.poke());
  scheduler.poke();
  return scheduler;
});
