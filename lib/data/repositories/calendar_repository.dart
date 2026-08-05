import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/calendar_event.dart';
import '../../services/calendar_cache.dart';
import '../../services/supabase.dart';
import '../../l10n/l10n.dart';

/// One round trip's worth of Kalender: the household's calendars, and every
/// event in them keyed by the day it falls on.
class CalendarSnapshot {
  final List<CalendarSource> calendars;

  /// 'y-m-d' -> the events on that day. A multi-day event (a Ferien block) is
  /// present under each of its days — the calendar renders per day, so the
  /// expansion happens once here rather than in every view.
  final Map<String, List<CalendarEvent>> eventsByDay;

  /// True when this came off the device cache rather than the network, so the
  /// screen can say "Stand von …" instead of implying it is live.
  final bool fromCache;

  const CalendarSnapshot({
    required this.calendars,
    required this.eventsByDay,
    this.fromCache = false,
  });

  static const empty = CalendarSnapshot(calendars: [], eventsByDay: {});
}

/// The only file that knows where Kalender's data comes from — and **none of it
/// is ours.**
///
/// Aporah has no calendar of its own. Every calendar the household sees belongs
/// to a connected account (Google, Outlook, iCloud, IServ), read through the
/// `calendar-events` function on every refresh and never written to our
/// database, or to a shared Ferien/Abfall feed out of `public.public_feeds`,
/// which is municipal data shared by every household rather than anything
/// belonging to this one. What lands on the device is the [CalendarCache], which
/// is also what makes the calendar work offline.
///
/// There used to be a second half: a `provider: 'aporah'` calendar with
/// `public.events` rows behind it, for appointments typed into the app itself.
/// It is gone. An event typed here is written **out to the account that will
/// still have it if Aporah disappears** — which is the whole point of connecting
/// one — so there is no read of `public.events` and no `toMap()` write left in
/// this file. Don't reintroduce either; a calendar in our database that the
/// family's own phone calendar never learns about is a trap, not a feature.
class CalendarRepository {
  CalendarRepository({SupabaseClient? client, CalendarCache? cache})
    : _db = client ?? AporahSupabase.client,
      _cache = cache ?? CalendarCache();

  final SupabaseClient _db;
  final CalendarCache _cache;

  /// How old a cached calendar may be and still be worth showing while the
  /// network answers. Generous: a stale calendar with a refresh on the way beats
  /// an empty one, and the refresh usually wins the race anyway.
  static const _cacheMaxAge = Duration(days: 30);

  // -------------------------------------------------------------------------
  // Read
  // -------------------------------------------------------------------------

  /// The last snapshot this device saw, or null. Never touches the network, so
  /// the calendar can paint before the first request has even been made.
  Future<CalendarSnapshot?> cached() async {
    final raw = await _cache.read(maxAge: _cacheMaxAge);
    if (raw == null) return null;
    try {
      return _assemble(
        _rows(raw['calendars']),
        _rows(raw['events']),
        _names(_rows(raw['profiles'])),
        fromCache: true,
      );
    } catch (_) {
      return null;
    }
  }

  /// Everything, live. Writes the result to the device cache on the way out.
  ///
  /// The two reads are gathered in parallel because neither depends on the
  /// other, and the calendar half is the slow one — it is talking to Google.
  Future<CalendarSnapshot> fetch() async {
    final results = await Future.wait([
      _external(),
      _profiles(),
    ]);

    final external = results[0] as ({List<Map<String, dynamic>> calendars, List<Map<String, dynamic>> events});
    final profiles = results[1] as List<Map<String, dynamic>>;

    await _cache.write({
      'calendars': external.calendars,
      'events': external.events,
      'profiles': profiles,
    });
    return _assemble(external.calendars, external.events, _names(profiles));
  }

  /// Connected accounts and public feeds, proxied — **every calendar there is.**
  /// Nothing in this response was read from our database except the shared
  /// Ferien/Abfall feeds.
  ///
  /// A failure here is no longer survivable the way it once was: with no own
  /// calendar behind it there is nothing else to render, so the cache is what
  /// stands between a timeout and an empty screen. The connections page is still
  /// where a broken account gets reported.
  Future<({List<Map<String, dynamic>> calendars, List<Map<String, dynamic>> events})> _external() async {
    try {
      final res = await _db.functions.invoke('calendar-events', body: const {});
      final data = res.data;
      if (data is! Map) return (calendars: <Map<String, dynamic>>[], events: <Map<String, dynamic>>[]);
      return (calendars: _rows(data['calendars']), events: _rows(data['events']));
    } catch (_) {
      return (calendars: <Map<String, dynamic>>[], events: <Map<String, dynamic>>[]);
    }
  }

  Future<List<Map<String, dynamic>>> _profiles() async {
    try {
      final rows = await _db.from('profiles').select('id, display_name, initials, tone');
      return [for (final row in rows) Map<String, dynamic>.from(row)];
    } catch (_) {
      // Names are decoration on an event row. Losing them must not lose the
      // calendar.
      return const [];
    }
  }

  static List<Map<String, dynamic>> _rows(Object? raw) => raw is List
      ? [for (final r in raw) if (r is Map) Map<String, dynamic>.from(r)]
      : const [];

  static Map<String?, ({String name, String initials, int tone})> _names(
    List<Map<String, dynamic>> rows,
  ) => {
    for (final row in rows)
      row['id'] as String: (
        name: row['display_name'] as String? ?? '',
        initials: row['initials'] as String? ?? '',
        tone: (row['tone'] as num?)?.toInt() ?? 0,
      ),
  };

  /// The one parser. Cached rows and live rows go through it identically, which
  /// is the whole reason the cache stores wire shapes rather than parsed
  /// objects — there is no second decoder to drift out of step.
  CalendarSnapshot _assemble(
    List<Map<String, dynamic>> calendarRows,
    List<Map<String, dynamic>> eventRows,
    Map<String?, ({String name, String initials, int tone})> names, {
    bool fromCache = false,
  }) {
    final calendars = [for (final row in calendarRows) CalendarSource.fromMap(row)];
    if (calendars.isEmpty) {
      return CalendarSnapshot(calendars: const [], eventsByDay: const {}, fromCache: fromCache);
    }

    final byId = {for (final c in calendars) c.id: c};
    final eventsByDay = <String, List<CalendarEvent>>{};

    for (final map in eventRows) {
      final calendar = byId[map['calendar_id'] as String?];
      // A calendar the read did not return is one RLS hid, or one a connection
      // stopped offering; skip rather than render an event with no source.
      if (calendar == null) continue;

      final member = names[map['created_by'] as String?];
      final event = CalendarEvent.fromMap(
        map,
        calendar: calendar,
        owner: member?.name ?? '',
        ownerInitial: member?.initials ?? '',
        ownerTone: member?.tone ?? 0,
      );

      for (final day in event.days) {
        (eventsByDay['${day.year}-${day.month}-${day.day}'] ??= []).add(event);
      }
    }

    for (final list in eventsByDay.values) {
      list.sort((a, b) {
        // All-day events head the day — they are context for it, not an
        // appointment competing for a slot in it.
        if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
        return a.startsAt.compareTo(b.startsAt);
      });
    }

    return CalendarSnapshot(calendars: calendars, eventsByDay: eventsByDay, fromCache: fromCache);
  }

  // -------------------------------------------------------------------------
  // Write — connected calendars, which is all of them
  // -------------------------------------------------------------------------
  //
  // There is deliberately no `createEvent`/`updateEvent`/`deleteEvent` pair to
  // this one. Those wrote `public.events` rows on a `provider: 'aporah'`
  // calendar, and that calendar no longer exists: every destination the form
  // offers belongs to a connected account, so every write goes out through
  // [writeExternal].

  /// Sends one change out to Google, Outlook or a CalDAV server through
  /// `calendar-write`, and returns the provider's id for the event.
  ///
  /// Nothing is stored on the way through: the event lands in the account, and
  /// comes back on the next [fetch] like any other event of theirs. That is the
  /// write half of the same trade the read path makes — the account stays the
  /// system of record.
  ///
  /// Unlike [_external], a failure here **is** fatal. A read that fails silently
  /// costs the user a refresh; a write that fails silently loses what they
  /// typed, and lets them close the sheet believing a doctor's appointment is in
  /// the family calendar when it is nowhere.
  Future<String> writeExternal({
    required String action,
    required String calendarId,
    String? uid,
    EventDraft? draft,
  }) async {
    try {
      final res = await _db.functions.invoke('calendar-write', body: {
        'action': action,
        'calendar_id': calendarId,
        if (uid != null && uid.isNotEmpty) 'uid': uid,
        if (draft != null) ...draft.toWire(),
      });
      final data = res.data;
      return data is Map ? (data['uid'] as String? ?? '') : '';
    } on FunctionException catch (e) {
      // `details` carries the JSON body, which is where every Aporah function
      // puts its German `error`. Without this the user gets "FunctionException:
      // 409" instead of being told the connection expired.
      final details = e.details;
      if (details is Map && details['error'] is String) {
        throw CalendarWriteException(details['error'] as String);
      }
      throw CalendarWriteException(L.s.eventSaveFailedRemote);
    } catch (_) {
      throw CalendarWriteException(L.s.noServerConnection);
    }
  }
}

/// Carries the Edge Function's own German message up to the notifier, so the
/// user is told *why* — an expired connection and an unreachable server need
/// different things from them.
class CalendarWriteException implements Exception {
  final String message;
  const CalendarWriteException(this.message);

  @override
  String toString() => message;
}
