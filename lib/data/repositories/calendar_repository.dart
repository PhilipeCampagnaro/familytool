import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/calendar_event.dart';
import '../../services/calendar_cache.dart';
import '../../services/supabase.dart';
import 'list_repository.dart' show newUuidV4;
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

/// The only file that knows where Kalender's data comes from — and it comes from
/// two places, on purpose.
///
/// **Aporah's own calendar** is stored: events somebody typed into this app have
/// nowhere else to live, so they are ordinary `public.events` rows read straight
/// off PostgREST under RLS.
///
/// **Everything else is not stored at all.** Google, Outlook, iCloud and IServ
/// are read through the `calendar-events` function on every refresh and never
/// written to our database; Ferien and Abfall come back from the same call out
/// of `public.public_feeds`, which is municipal data shared by every household
/// rather than anything belonging to this one. What lands on the device is the
/// [CalendarCache], which is also what makes the calendar work offline.
///
/// The rule that follows from this, and the one to keep: **`toMap()` may only
/// ever be sent for an event on an `aporah` calendar.** Everything else is
/// read-only here because it is somebody else's system of record.
class CalendarRepository {
  CalendarRepository({SupabaseClient? client, CalendarCache? cache})
    : _db = client ?? AporahSupabase.client,
      _cache = cache ?? CalendarCache();

  final SupabaseClient _db;
  final CalendarCache _cache;

  static const _calendarColumns = 'id, name, color, is_read_only, position, provider';
  static const _eventColumns =
      'id, calendar_id, title, starts_at, ends_at, all_day, location, location_sub, '
      'notes, online, url, reminder_minutes, created_by';

  /// How old a cached calendar may be and still be worth showing while the
  /// network answers. Generous: a stale calendar with a refresh on the way beats
  /// an empty one, and the refresh usually wins the race anyway.
  static const _cacheMaxAge = Duration(days: 30);

  String get _uid {
    final id = AporahSupabase.userId;
    if (id == null) throw StateError(L.s.notSignedIn);
    return id;
  }

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
  /// The two sources are gathered in parallel because neither depends on the
  /// other, and the external one is the slow half — it is talking to Google.
  Future<CalendarSnapshot> fetch() async {
    final results = await Future.wait([
      _own(),
      _external(),
      _profiles(),
    ]);

    final own = results[0] as ({List<Map<String, dynamic>> calendars, List<Map<String, dynamic>> events});
    final external = results[1] as ({List<Map<String, dynamic>> calendars, List<Map<String, dynamic>> events});
    final profiles = results[2] as List<Map<String, dynamic>>;

    final calendars = [...own.calendars, ...external.calendars];
    final events = [...own.events, ...external.events];

    await _cache.write({'calendars': calendars, 'events': events, 'profiles': profiles});
    return _assemble(calendars, events, _names(profiles));
  }

  /// Aporah's own calendar and the events typed into it. Plain PostgREST: RLS
  /// already decides what this household may see, and no `family_id` filter
  /// belongs here.
  Future<({List<Map<String, dynamic>> calendars, List<Map<String, dynamic>> events})> _own() async {
    final calendarRows = await _db
        .from('calendars')
        .select(_calendarColumns)
        .eq('provider', 'aporah')
        .order('position');

    final calendars = [for (final row in calendarRows) Map<String, dynamic>.from(row)];
    if (calendars.isEmpty) return (calendars: calendars, events: <Map<String, dynamic>>[]);

    final eventRows = await _db
        .from('events')
        .select(_eventColumns)
        .inFilter('calendar_id', [for (final c in calendars) c['id'] as String])
        .order('starts_at');

    return (
      calendars: calendars,
      events: [for (final row in eventRows) Map<String, dynamic>.from(row)],
    );
  }

  /// Connected accounts and public feeds, proxied. Nothing in this response was
  /// read from our database except the shared Ferien/Abfall feeds.
  ///
  /// A failure here is not fatal: the household's own events still render, and
  /// the connections screen is where a broken account gets reported. Blanking
  /// the whole calendar because Google timed out would be the wrong trade.
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
  // Write — Aporah's own calendar only
  // -------------------------------------------------------------------------

  /// The household's own calendar — where a typed event goes.
  ///
  /// Created on first use rather than at signup, so a family that only ever
  /// connects Google never accumulates an empty "Aporah" calendar beside it.
  /// Uses a client-generated id and a separate read because **`insert …
  /// returning` is rejected on `calendars`**, exactly as it is on `lists` — see
  /// the "Writing containers from the client" section of docs/backend.md.
  Future<CalendarSource> ownCalendar(String familyId) async {
    final existing = await _db
        .from('calendars')
        .select(_calendarColumns)
        .eq('provider', 'aporah')
        .eq('owner_id', _uid)
        .limit(1)
        .maybeSingle();

    if (existing != null) {
      return CalendarSource.fromMap(Map<String, dynamic>.from(existing));
    }

    final id = newUuidV4();
    await _db.from('calendars').insert({
      'id': id,
      'family_id': familyId,
      'name': 'Aporah',
      'provider': 'aporah',
      'color': 0xff1668ff.toSigned(32),
      'owner_id': _uid,
      // Never private. A calendar belongs to the whole household — see the
      // calendar rule in CLAUDE.md.
      'visibility': 'family',
    });

    final created = await _db
        .from('calendars')
        .select(_calendarColumns)
        .eq('id', id)
        .single();
    return CalendarSource.fromMap(Map<String, dynamic>.from(created));
  }

  Future<void> createEvent(CalendarEvent event) async {
    await _db.from('events').insert({
      ...event.toMap(),
      'id': newUuidV4(),
      'created_by': _uid,
    });
  }

  Future<void> updateEvent(CalendarEvent event) async {
    await _db.from('events').update(event.toMap()).eq('id', event.id);
  }

  Future<void> deleteEvent(String eventId) async {
    await _db.from('events').delete().eq('id', eventId);
  }

  // -------------------------------------------------------------------------
  // Write — connected calendars
  // -------------------------------------------------------------------------

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
