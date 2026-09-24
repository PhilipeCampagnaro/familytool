import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';
import '../models/calendar_event.dart';
import '../models/spend.dart';
import '../models/spend_budget.dart';
import '../services/local_notifications.dart';

/// "Remind me before this appointment" — **on this device, for this person.**
///
/// The appointment is the household's; the reminder is not. So it is a local
/// preference with no table, no policy and no sync, and a reinstall or a second
/// phone does not have it. That is the trade, and docs/notifications.md is where
/// it is written down.
///
/// **Keyed on the provider's own identity**, the `(calendar, uid)` pair
/// `EventLink` uses, because we store no events to hold a foreign key to. For a
/// one-off that is the whole key, which is what lets a reminder follow an
/// appointment somebody moved in Google. An occurrence of a series is also told
/// apart by its start: CalDAV gives every occurrence of a series one UID, so
/// without the start, a reminder on one Monday would ring before all of them.
class EventReminder {
  final String calendarId;
  final String uid;
  final DateTime startsAt;

  /// Negative for an all-day event's "on the day" choice, which rings *after*
  /// the midnight the event starts at.
  final int minutesBefore;

  const EventReminder({
    required this.calendarId,
    required this.uid,
    required this.startsAt,
    required this.minutesBefore,
  });

  bool matches(CalendarEvent e) =>
      e.calendarId == calendarId && e.uid == uid && (!e.repeats || e.startsAt == startsAt);

  Map<String, Object> toJson() => {
    'c': calendarId,
    'u': uid,
    's': startsAt.millisecondsSinceEpoch,
    'm': minutesBefore,
  };

  static EventReminder? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final c = raw['c'], u = raw['u'], s = raw['s'], m = raw['m'];
    if (c is! String || u is! String || s is! int || m is! int) return null;
    return EventReminder(
      calendarId: c,
      uid: u,
      startsAt: DateTime.fromMillisecondsSinceEpoch(s),
      minutesBefore: m,
    );
  }
}

/// 19:00 the day before an all-day event, counted back from its midnight.
const kAllDayDayBefore = 5 * 60;

/// 07:00 on the day itself.
const kAllDayMorningOf = -7 * 60;

/// What the reminder menu offers. An all-day event has no start time to count
/// back from, so "30 minutes before" would mean 23:30 the night before; it gets
/// two wall-clock choices instead.
List<int> reminderChoicesFor(CalendarEvent e) =>
    e.allDay ? const [kAllDayDayBefore, kAllDayMorningOf] : const [0, 10, 30, 60, 120, 1440];

String reminderLabel(int minutes, {required bool allDay}) {
  if (allDay && minutes < 1440) {
    final at = DateTime(2000, 1, 2).subtract(Duration(minutes: minutes));
    final time = formatTimeOfDay(at.hour, at.minute);
    return minutes > 0 ? L.s.reminderDayBefore(time) : L.s.reminderMorningOf(time);
  }
  if (minutes == 0) return L.s.reminderAtStart;
  if (minutes % 1440 == 0) return L.s.reminderDaysBefore(minutes ~/ 1440);
  if (minutes % 60 == 0) return L.s.reminderHoursBefore(minutes ~/ 60);
  return L.s.reminderMinutesBefore(minutes);
}

/// What a budget has already been told about, for one category, one calendar
/// month and one [SpendBudgetStatus].
///
/// **The month is in the key, which is what makes the whole thing self-expiring
/// rather than something that has to be reset.** A budget that was blown in
/// March says nothing in April because April's key has never been seen, and
/// there is no first-of-the-month job anywhere that has to remember to run.
String budgetNoticeKey(SpendCategory category, DateTime month, SpendBudgetStatus level) =>
    '${category.wire}|${month.year}-${month.month}|${level.name}';

/// 19:00 the evening before — the hour that can still get a bin to the kerb for
/// a six o'clock pickup, and the one a household starts with.
const kAbfallEveningDefault = 19 * 60;

/// 06:00 on the day itself, for a street collected at noon or a household whose
/// bins go out at dawn.
const kAbfallMorningDefault = 6 * 60;

/// **How many reminders one pickup may carry.**
///
/// Not a taste limit: every category in this app draws from iOS's 64 pending
/// requests, and a bin reminder multiplies by every pickup in the fortnight —
/// four bins a week at four reminders each is the whole budget spent on the
/// rubbish, with the dentist dropped silently. Four is enough for "the evening
/// before, at bedtime, at dawn, and before the lorry" and still leaves room.
const kAbfallReminderLimit = 4;

/// One bin reminder: which day it rings on relative to the pickup, and the hour
/// on that day.
///
/// **A list of these, rather than one day and one hour**, because a bin missed
/// is a fortnight of bin — the households that asked for this wanted the
/// evening before *and* a last word before the lorry, not a choice between
/// them. The pair is the identity: two reminders on the same day at the same
/// minute are one reminder, and [NotificationSettingsNotifier] folds them
/// together rather than scheduling the same notice twice.
class AbfallReminder implements Comparable<AbfallReminder> {
  /// Rings on the morning of the pickup rather than the evening before.
  final bool sameDay;

  /// Minutes past midnight of whichever day [sameDay] picks.
  final int minutes;

  const AbfallReminder({required this.sameDay, required this.minutes});

  /// Chronological: the evening before comes before the morning of, whatever
  /// the clocks say, which is why the day is worth a whole day of sort order.
  int get _order => sameDay ? minutes + 1440 : minutes;

  @override
  int compareTo(AbfallReminder other) => _order.compareTo(other._order);

  @override
  bool operator ==(Object other) =>
      other is AbfallReminder && other.sameDay == sameDay && other.minutes == minutes;

  @override
  int get hashCode => Object.hash(sameDay, minutes);

  String get label {
    final time = formatTimeOfDay(minutes ~/ 60, minutes % 60);
    return sameDay ? L.s.reminderMorningOf(time) : L.s.reminderDayBefore(time);
  }

  Map<String, Object> toJson() => {'d': sameDay, 'm': minutes};

  static AbfallReminder? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final d = raw['d'], m = raw['m'];
    if (d is! bool || m is! int || m < 0 || m >= 1440) return null;
    return AbfallReminder(sameDay: d, minutes: m);
  }
}

/// Deduplicated, in the order they ring, and never more than
/// [kAbfallReminderLimit] of them — the one shape the rest of the app may see.
List<AbfallReminder> normalizeAbfallReminders(Iterable<AbfallReminder> raw) {
  final unique = {...raw}.toList()..sort();
  return unique.length > kAbfallReminderLimit ? unique.sublist(0, kAbfallReminderLimit) : unique;
}

/// What this device will be told, and whether the OS will let it through.
class NotificationSettings {
  final bool loaded;
  final NotificationAccess access;

  /// The morning brief. See `composeNotices`.
  final bool brief;
  final int briefMinutes;

  /// Whether a waste pickup is announced at all — the master switch over
  /// [abfallTimes], kept beside the list rather than folded into "the list is
  /// empty" so that switching the card off and on again returns the hours the
  /// household set rather than the default.
  final bool abfall;

  /// **Every reminder a pickup gets**, in the order they ring, deduplicated and
  /// capped at [kAbfallReminderLimit]. Pickup is around six in the morning, so
  /// the evening before is the one that can still get a bin to the kerb — but
  /// it is no longer the only one a household may have, because an evening
  /// reminder at 19:00 is easy to answer with "later" and then forget.
  ///
  /// Only ever written through `normalizeAbfallReminders`.
  final List<AbfallReminder> abfallTimes;

  /// The hour to offer for a day that has no reminder on it yet — the one
  /// already set there if there is one, so the two presets in an event sheet
  /// keep saying what the household chose.
  int abfallHourFor({required bool sameDay}) {
    for (final r in abfallTimes) {
      if (r.sameDay == sameDay) return r.minutes;
    }
    return sameDay ? kAbfallMorningDefault : kAbfallEveningDefault;
  }

  /// A to-do that names an hour. Setting one is the user asking to be reminded.
  final bool taskTimes;

  /// A budget running ahead of the month, or past its limit. **Plus and admin
  /// only**, like Ausgaben itself — a household without budgets never hears
  /// from it, which is what lets it default on.
  final bool budgets;

  /// What has already been said, `budgetNoticeKey` → the moment its notice was
  /// scheduled for.
  ///
  /// **A budget crossing a line is not an appointment: it has no time of its
  /// own, and it stays crossed.** So where the other four kinds are re-derived
  /// from scratch every time with nothing remembered, this one has to remember
  /// or a blown budget would be announced every evening for the rest of the
  /// month — the exact "follows somebody around" failure a tracker is built to
  /// avoid.
  ///
  /// The value is a time rather than a flag because even a notice that fires at
  /// once is *scheduled*, a minute out: until that minute is up the derivation
  /// has to keep emitting it, or `replaceAll` would take back the one it just
  /// sent. Once the time is past, the key is spent for the month.
  final Map<String, DateTime> announcedBudgets;

  final List<EventReminder> reminders;

  const NotificationSettings({
    this.loaded = false,
    this.access = NotificationAccess.notDetermined,
    this.brief = false,
    this.briefMinutes = 7 * 60,
    this.abfall = true,
    this.abfallTimes = const [AbfallReminder(sameDay: false, minutes: kAbfallEveningDefault)],
    this.taskTimes = true,
    this.budgets = true,
    this.announcedBudgets = const {},
    this.reminders = const [],
  });

  EventReminder? reminderFor(CalendarEvent e) {
    for (final r in reminders) {
      if (r.matches(e)) return r;
    }
    return null;
  }

  NotificationSettings copyWith({
    bool? loaded,
    NotificationAccess? access,
    bool? brief,
    int? briefMinutes,
    bool? abfall,
    List<AbfallReminder>? abfallTimes,
    bool? taskTimes,
    bool? budgets,
    Map<String, DateTime>? announcedBudgets,
    List<EventReminder>? reminders,
  }) => NotificationSettings(
    loaded: loaded ?? this.loaded,
    access: access ?? this.access,
    brief: brief ?? this.brief,
    briefMinutes: briefMinutes ?? this.briefMinutes,
    abfall: abfall ?? this.abfall,
    abfallTimes: abfallTimes ?? this.abfallTimes,
    taskTimes: taskTimes ?? this.taskTimes,
    budgets: budgets ?? this.budgets,
    announcedBudgets: announcedBudgets ?? this.announcedBudgets,
    reminders: reminders ?? this.reminders,
  );
}

const _kBrief = 'notify_brief';
const _kBriefMinutes = 'notify_brief_minutes';
const _kAbfall = 'notify_abfall';
const _kAbfallTimes = 'notify_abfall_times';

// The three keys the single bin reminder was stored under, read once by
// `_loadAbfallTimes` so an install that already had an hour set keeps it, and
// written by nothing any more.
const _kLegacyAbfallMinutes = 'notify_abfall_minutes';
const _kLegacyAbfallSameDay = 'notify_abfall_same_day';
const _kLegacyAbfallMorningMinutes = 'notify_abfall_morning_minutes';
const _kTaskTimes = 'notify_task_times';
const _kBudgets = 'notify_budgets';
const _kAnnouncedBudgets = 'notify_budgets_announced';
const _kReminders = 'notify_event_reminders';

class NotificationSettingsNotifier extends StateNotifier<NotificationSettings> {
  NotificationSettingsNotifier() : super(const NotificationSettings()) {
    _load();
  }

  final _os = const LocalNotifications();

  /// **The brief is on by default only where it can arrive quietly.** On iOS it
  /// rides a provisional grant — no dialog, delivered silently to Notification
  /// Centre, promoted by the user if they like it — which is a better first
  /// contact than a permission prompt on day one. Android has no quiet grant, so
  /// there it waits to be switched on.
  static bool get _briefByDefault => provisionalNotificationsAvailable;

  Future<void> _load() async {
    var next = state.copyWith(brief: _briefByDefault);
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kReminders);
      final decoded = raw == null ? const <Object?>[] : jsonDecode(raw);
      next = next.copyWith(
        brief: prefs.getBool(_kBrief) ?? _briefByDefault,
        briefMinutes: prefs.getInt(_kBriefMinutes),
        abfall: prefs.getBool(_kAbfall),
        abfallTimes: _loadAbfallTimes(prefs),
        taskTimes: prefs.getBool(_kTaskTimes),
        budgets: prefs.getBool(_kBudgets),
        announcedBudgets: _decodeAnnounced(prefs.getString(_kAnnouncedBudgets)),
        reminders: [
          if (decoded is List)
            for (final item in decoded) ?EventReminder.fromJson(item),
        ],
      );
    } catch (_) {
      // No storage this session — defaults, in memory only.
    }
    final access = await _os.status();
    if (!mounted) return;
    state = next.copyWith(loaded: true, access: access);
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kBrief, state.brief);
      await prefs.setInt(_kBriefMinutes, state.briefMinutes);
      await prefs.setBool(_kAbfall, state.abfall);
      await prefs.setString(
        _kAbfallTimes,
        jsonEncode([for (final r in state.abfallTimes) r.toJson()]),
      );
      await prefs.setBool(_kTaskTimes, state.taskTimes);
      await prefs.setBool(_kBudgets, state.budgets);
      await prefs.setString(
        _kAnnouncedBudgets,
        jsonEncode({
          for (final MapEntry(key: k, value: at) in state.announcedBudgets.entries)
            k: at.millisecondsSinceEpoch,
        }),
      );
      await prefs.setString(_kReminders, jsonEncode([for (final r in state.reminders) r.toJson()]));
    } catch (_) {
      // Best-effort, like every other preference in the app.
    }
  }

  /// Re-read from the OS. The user can change it in system settings at any
  /// moment, so a resume and opening the settings page both ask again.
  Future<void> refreshAccess() async {
    final access = await _os.status();
    if (mounted && access != state.access) state = state.copyWith(access: access);
  }

  /// iOS, once: the quiet grant that lets the brief and the bins arrive without
  /// a dialog. Does nothing if the user has ever answered, and nothing on
  /// Android.
  Future<void> requestQuietly() async {
    if (!provisionalNotificationsAvailable) return;
    final current = await _os.status();
    if (current != NotificationAccess.notDetermined) {
      if (mounted) state = state.copyWith(access: current);
      return;
    }
    final access = await _os.request(provisional: true);
    if (mounted) state = state.copyWith(access: access);
  }

  /// **The real prompt, at the moment it is worth something** — a reminder set,
  /// a switch turned on — and never at launch. Also promotes a quiet grant: a
  /// reminder that lands silently in Notification Centre has not reminded
  /// anybody.
  Future<NotificationAccess> ensureAccess() async {
    var access = await _os.status();
    if (access == NotificationAccess.notDetermined || access == NotificationAccess.provisional) {
      access = await _os.request();
    }
    if (mounted) state = state.copyWith(access: access);
    return access;
  }

  Future<void> openSystemSettings() => _os.openSettings();

  void setBrief(bool value) => _set(state.copyWith(brief: value), asks: value);

  void setBriefMinutes(int minutes) => _set(state.copyWith(briefMinutes: minutes));

  /// **Switching the card back on restores the hours, and an empty list is
  /// refilled with the default.** The list can only be emptied by removing the
  /// last reminder, which switches the card off in the same breath — so a card
  /// that is on always has at least one line under it.
  void setAbfall(bool value) => _set(
    state.copyWith(
      abfall: value,
      abfallTimes: value && state.abfallTimes.isEmpty
          ? const [AbfallReminder(sameDay: false, minutes: kAbfallEveningDefault)]
          : null,
    ),
    asks: value,
  );

  /// On, with exactly one reminder on the day given. What a bin day's own
  /// reminder row writes: the two presets there are one-reminder shortcuts, and
  /// the row beside them leads to the page where more can be built.
  void setAbfallDay({required bool sameDay}) => _set(
    state.copyWith(
      abfall: true,
      abfallTimes: [
        AbfallReminder(sameDay: sameDay, minutes: state.abfallHourFor(sameDay: sameDay)),
      ],
    ),
    asks: true,
  );

  /// Adds a line. A reminder the household already has is not added twice —
  /// `normalizeAbfallReminders` folds it back into the one that is there, so
  /// the tap is a no-op rather than a duplicate notice.
  void addAbfallReminder(AbfallReminder reminder) => _setAbfallTimes([
    ...state.abfallTimes,
    reminder,
  ]);

  /// Changes one line's day or hour in place. [from] is the reminder as it was
  /// drawn, which is its whole identity — the list carries no ids because two
  /// reminders that ring at the same minute on the same day *are* one.
  void replaceAbfallReminder(AbfallReminder from, AbfallReminder to) => _setAbfallTimes([
    for (final r in state.abfallTimes)
      if (r == from) to else r,
  ]);

  /// Takes a line away, and **switches the card off when it was the last one**:
  /// a bin reminder that is on and rings at no hour is a switch that lies.
  void removeAbfallReminder(AbfallReminder reminder) => _setAbfallTimes([
    for (final r in state.abfallTimes)
      if (r != reminder) r,
  ]);

  void _setAbfallTimes(Iterable<AbfallReminder> times) {
    final next = normalizeAbfallReminders(times);
    _set(state.copyWith(abfall: next.isNotEmpty && state.abfall, abfallTimes: next));
  }

  void setTaskTimes(bool value) => _set(state.copyWith(taskTimes: value), asks: value);

  void setBudgets(bool value) => _set(state.copyWith(budgets: value), asks: value);

  /// Records what the scheduler has just put on the device, so the same budget
  /// is not announced again tomorrow evening.
  ///
  /// **Keys whose moment has passed are kept and everything else is replaced by
  /// [pending].** Kept, because a notice that has fired is spent for the month;
  /// replaced, because a budget that fell back under its pace before the
  /// evening came had its notice taken off the device again and should be free
  /// to re-arm. Keys from other months are dropped here rather than anywhere
  /// else — it is the only place this map is written.
  void recordBudgetNotices(Map<String, DateTime> pending) {
    final now = DateTime.now();
    final month = '${now.year}-${now.month}';
    final next = <String, DateTime>{
      for (final MapEntry(key: k, value: at) in state.announcedBudgets.entries)
        if (!at.isAfter(now) && k.contains('|$month|')) k: at,
      ...pending,
    };
    if (_sameAnnounced(next, state.announcedBudgets)) return;
    state = state.copyWith(announcedBudgets: next);
    unawaited(_persist());
  }

  static bool _sameAnnounced(Map<String, DateTime> a, Map<String, DateTime> b) {
    if (a.length != b.length) return false;
    for (final MapEntry(key: k, value: v) in a.entries) {
      if (b[k] != v) return false;
    }
    return true;
  }

  void _set(NotificationSettings next, {bool asks = false}) {
    state = next;
    unawaited(_persist());
    // A switch turned on where nothing can arrive asks for the grant. A quiet
    // grant is left alone here — it does deliver, and the user chose a category,
    // not an interruption level.
    if (asks && !state.access.delivers) unawaited(ensureAccess());
  }

  /// Sets, changes or clears ([minutes] null) the reminder on [event]. Returns
  /// the access the OS ended up with, so the sheet can say when it is refused.
  Future<NotificationAccess> setReminder(CalendarEvent event, int? minutes) async {
    final others = [
      for (final r in state.reminders)
        if (!r.matches(event)) r,
    ];
    state = state.copyWith(
      reminders: [
        ...others,
        if (minutes != null)
          EventReminder(
            calendarId: event.calendarId,
            uid: event.uid,
            startsAt: event.startsAt,
            minutesBefore: minutes,
          ),
      ],
    );
    unawaited(_persist());
    if (minutes == null) return state.access;
    return ensureAccess();
  }

  /// Drops reminders on appointments that have been over for a while, so the
  /// stored list does not grow for the life of the install.
  void pruneReminders(DateTime before) {
    final kept = [
      for (final r in state.reminders)
        if (!r.startsAt.isBefore(before)) r,
    ];
    if (kept.length == state.reminders.length) return;
    state = state.copyWith(reminders: kept);
    unawaited(_persist());
  }
}

final notificationSettingsProvider =
    StateNotifierProvider<NotificationSettingsNotifier, NotificationSettings>(
      (ref) => NotificationSettingsNotifier(),
    );

/// The stored bin reminders, or the single one this install used to have.
///
/// **The migration is the whole reason this is a function.** A household that
/// had already moved the notice to 06:00 on the pickup day must not be handed
/// back 19:00 the evening before because the shape of the setting changed
/// underneath them, so the old day flag picks which of the two old hours
/// survives and it becomes the first line. Returns null for a fresh install,
/// which lets `copyWith` fall through to the default.
List<AbfallReminder>? _loadAbfallTimes(SharedPreferences prefs) {
  final raw = prefs.getString(_kAbfallTimes);
  if (raw != null) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return normalizeAbfallReminders([for (final item in decoded) ?AbfallReminder.fromJson(item)]);
      }
    } catch (_) {
      // Unreadable — fall through to the legacy keys, then to the default.
    }
  }
  final sameDay = prefs.getBool(_kLegacyAbfallSameDay);
  final evening = prefs.getInt(_kLegacyAbfallMinutes);
  final morning = prefs.getInt(_kLegacyAbfallMorningMinutes);
  if (sameDay == null && evening == null && morning == null) return null;
  final minutes = (sameDay ?? false)
      ? morning ?? kAbfallMorningDefault
      : evening ?? kAbfallEveningDefault;
  return [AbfallReminder(sameDay: sameDay ?? false, minutes: minutes)];
}

Map<String, DateTime> _decodeAnnounced(String? raw) {
  if (raw == null) return const {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const {};
    return {
      for (final MapEntry(key: k, value: v) in decoded.entries)
        if (k is String && v is int) k: DateTime.fromMillisecondsSinceEpoch(v),
    };
  } catch (_) {
    return const {};
  }
}

@visibleForTesting
String debugReminderKey(EventReminder r) => '${r.calendarId}|${r.uid}|${r.startsAt}';
