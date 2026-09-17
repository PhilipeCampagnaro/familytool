import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';
import '../models/calendar_event.dart';
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

/// What this device will be told, and whether the OS will let it through.
class NotificationSettings {
  final bool loaded;
  final NotificationAccess access;

  /// The morning brief. See `composeNotices`.
  final bool brief;
  final int briefMinutes;

  /// The evening before a waste pickup. Pickup is at six in the morning, so the
  /// only reminder that can still get a bin to the kerb is the night before.
  final bool abfall;
  final int abfallMinutes;

  /// A to-do that names an hour. Setting one is the user asking to be reminded.
  final bool taskTimes;

  final List<EventReminder> reminders;

  const NotificationSettings({
    this.loaded = false,
    this.access = NotificationAccess.notDetermined,
    this.brief = false,
    this.briefMinutes = 7 * 60,
    this.abfall = true,
    this.abfallMinutes = 19 * 60,
    this.taskTimes = true,
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
    int? abfallMinutes,
    bool? taskTimes,
    List<EventReminder>? reminders,
  }) => NotificationSettings(
    loaded: loaded ?? this.loaded,
    access: access ?? this.access,
    brief: brief ?? this.brief,
    briefMinutes: briefMinutes ?? this.briefMinutes,
    abfall: abfall ?? this.abfall,
    abfallMinutes: abfallMinutes ?? this.abfallMinutes,
    taskTimes: taskTimes ?? this.taskTimes,
    reminders: reminders ?? this.reminders,
  );
}

const _kBrief = 'notify_brief';
const _kBriefMinutes = 'notify_brief_minutes';
const _kAbfall = 'notify_abfall';
const _kAbfallMinutes = 'notify_abfall_minutes';
const _kTaskTimes = 'notify_task_times';
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
        abfallMinutes: prefs.getInt(_kAbfallMinutes),
        taskTimes: prefs.getBool(_kTaskTimes),
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
      await prefs.setInt(_kAbfallMinutes, state.abfallMinutes);
      await prefs.setBool(_kTaskTimes, state.taskTimes);
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

  void setAbfall(bool value) => _set(state.copyWith(abfall: value), asks: value);

  void setAbfallMinutes(int minutes) => _set(state.copyWith(abfallMinutes: minutes));

  void setTaskTimes(bool value) => _set(state.copyWith(taskTimes: value), asks: value);

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

@visibleForTesting
String debugReminderKey(EventReminder r) => '${r.calendarId}|${r.uid}|${r.startsAt}';
