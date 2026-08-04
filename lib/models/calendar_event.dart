import 'package:flutter/material.dart';

import '../data/abfall_bins.dart';

enum EventPhase { done, now, next }

/// One of the household's calendars — the app's own, or one produced by a
/// connected account.
///
/// Replaces the old `EventSource` enum, which was a fixed taxonomy of the five
/// providers Aporah *can* connect to. A household has actual calendars with
/// their own names and colours ("Schulferien Niedersachsen", "Abfallkalender"),
/// and a Google account alone can contribute a dozen of them, so the identity
/// has to be the row rather than the provider.
class CalendarSource {
  final String id;
  final String name;
  final Color color;

  /// Calendars nobody can write to: Ferien, Abfall, a subscribed school
  /// calendar, or a Google calendar this account only has read access to. The
  /// UI uses it to hide edit affordances; the provider refuses regardless.
  final bool readOnly;

  /// Aporah's own calendar, as opposed to anything connected or subscribed.
  ///
  /// This decides **how** a write happens, not whether it may. Own events are
  /// `public.events` rows the client writes over PostgREST; everything else is
  /// proxied — there is no row of ours behind it, so an edit has to travel back
  /// out to Google, Outlook or the CalDAV server through `calendar-write`.
  final bool isOwn;

  /// `'ferien'` or `'abfall'` for a public feed, empty for everything else.
  ///
  /// Only Abfall reads it, and only to colour each entry by its bin — see
  /// [binColorFor]. A feed is otherwise an ordinary read-only calendar.
  final String feedKind;

  const CalendarSource({
    required this.id,
    required this.name,
    required this.color,
    this.readOnly = false,
    this.isOwn = false,
    this.feedKind = '',
  });

  /// Whether the household can add to, change or delete events in this calendar
  /// — its own, and any connected one the account has write access to.
  bool get editable => !readOnly;

  /// Stands in for Aporah's own calendar in the destination picker before it
  /// exists. `ownCalendar()` creates the real row the first time an event is
  /// saved into it; until then there is nothing to list, and a household with no
  /// connected calendars would have nowhere to put an event at all.
  static const ownPlaceholderId = 'aporah-own-placeholder';

  static const ownPlaceholder = CalendarSource(
    id: ownPlaceholderId,
    name: 'Aporah',
    color: Color(0xff1668ff),
    isOwn: true,
  );

  /// `calendars.color` is a signed 32-bit ARGB int, editable by the household.
  ///
  /// `provider` is absent from the `calendar-events` response by design: every
  /// calendar in it is external, so a missing provider reads as "not ours",
  /// which is exactly right.
  factory CalendarSource.fromMap(Map<String, dynamic> map) => CalendarSource(
    id: map['id'] as String,
    name: map['name'] as String? ?? 'Kalender',
    color: Color((map['color'] as num?)?.toInt().toUnsigned(32) ?? 0xff1668ff),
    readOnly: map['is_read_only'] == true,
    isOwn: map['provider'] == 'aporah',
    feedKind: map['feed_kind'] as String? ?? '',
  );
}

/// What the event form produces: one event as the user typed it, before
/// anything has decided where it will be stored.
///
/// [start] and [end] are **local** wall-clock times, and stay that way all the
/// way to the provider. A family types "14:00" and means 14:00 — normalising to
/// UTC in the app would freeze whichever offset applied on the day they typed
/// it, and a Google event created in August would move an hour in November.
/// Aporah's own events are timestamps, so those do convert; connected calendars
/// take the date and the clock time separately.
///
/// [end] is **exclusive** for an all-day event, matching [CalendarEvent.endsAt],
/// iCalendar and Google: a single day ends the following midnight.
class EventDraft {
  final String calendarId;
  final String title;
  final String location;
  final String notes;
  final bool allDay;
  final DateTime start;
  final DateTime end;

  const EventDraft({
    required this.calendarId,
    required this.title,
    required this.location,
    required this.notes,
    required this.allDay,
    required this.start,
    required this.end,
  });

  EventDraft copyWith({
    String? calendarId,
    String? title,
    String? location,
    String? notes,
    bool? allDay,
    DateTime? start,
    DateTime? end,
  }) => EventDraft(
    calendarId: calendarId ?? this.calendarId,
    title: title ?? this.title,
    location: location ?? this.location,
    notes: notes ?? this.notes,
    allDay: allDay ?? this.allDay,
    start: start ?? this.start,
    end: end ?? this.end,
  );

  /// The shape `calendar-write` reads: a date and a clock time, kept apart so
  /// the Edge Function can hand the provider `Europe/Berlin` rather than an
  /// instant.
  Map<String, dynamic> toWire() => {
    'title': title,
    'all_day': allDay,
    'date': _date(start),
    'time': allDay ? null : _clock(start),
    'end_date': _date(end),
    'end_time': allDay ? null : _clock(end),
    'location': location,
    'notes': notes,
  };

  /// The same draft as a row for Aporah's own calendar.
  CalendarEvent toEvent({required CalendarSource calendar, String id = ''}) => CalendarEvent(
    id: id,
    calendarId: calendar.id,
    title: title,
    startsAt: start,
    endsAt: end,
    allDay: allDay,
    loc: location,
    body: notes,
    source: calendar.name,
    srcColor: calendar.color,
  );

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _clock(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// Reopens an existing event in the form.
  factory EventDraft.of(CalendarEvent e) => EventDraft(
    calendarId: e.calendarId,
    title: e.title,
    location: e.loc,
    notes: e.body,
    allDay: e.allDay,
    start: e.startsAt,
    end: e.endsAt,
  );
}

class CalendarEvent {
  final String id;
  final String calendarId;

  /// The provider's own identifier, for events proxied from a connected
  /// account. Empty for anything on Aporah's own calendar, where [id] *is* the
  /// row. This is what `calendar-write` needs in order to change the right event
  /// in Google or on the CalDAV server.
  final String uid;

  final String title;

  final DateTime startsAt;
  final DateTime endsAt;

  /// All-day events carry an **exclusive** end, the way iCalendar and Google
  /// both express them: a one-day event ends the following midnight. Every
  /// duration and phase calculation has to know this, which is why it is on the
  /// model rather than inferred from the times.
  final bool allDay;

  final String body;
  final String loc;
  final String locSub;
  final bool online;
  final String url;
  final String reminder;

  /// Who created it. Empty for anything synced — a Ferien entry has no author,
  /// and inventing one would put a stranger's initials on a public holiday.
  final String owner;
  final String ownerInitial;
  final int ownerTone;

  /// The calendar's name and colour, denormalised onto the event so the agenda
  /// row can render without a second lookup per item.
  final String source;
  final Color srcColor;

  /// Weather. No service is wired up yet, so these stay empty and the detail
  /// sheet hides the block — see docs/ported-features.md.
  final String temp;
  final String cond;
  final String condLabel;

  const CalendarEvent({
    required this.id,
    required this.calendarId,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    required this.source,
    required this.srcColor,
    this.uid = '',
    this.allDay = false,
    this.body = '',
    this.loc = '',
    this.locSub = '',
    this.online = false,
    this.url = '',
    this.reminder = '',
    this.owner = '',
    this.ownerInitial = '',
    this.ownerTone = 0,
    this.temp = '',
    this.cond = '',
    this.condLabel = '',
  });

  /// "09:15". Empty for an all-day event, which has no meaningful clock time —
  /// callers should prefer [timeLabel], which says so in German.
  String get time => allDay ? '' : _hm(startsAt);
  String get endTime => allDay ? '' : _hm(endsAt);

  String get timeLabel => allDay ? 'Ganztägig' : _hm(startsAt);

  /// The line the agenda and detail sheet print. All-day events say so instead
  /// of printing "00:00 – 00:00 Uhr".
  String get timeRangeLabel => allDay ? 'Ganztägig' : '${_hm(startsAt)} – ${_hm(endsAt)} Uhr';

  static String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// Done / live / upcoming against the wall clock.
  ///
  /// All-day events are compared on the whole span, so a Ferien week reads as
  /// "now" for its entire duration rather than being done at one minute past
  /// midnight on the first day.
  EventPhase phaseAt(DateTime now) {
    if (!now.isBefore(endsAt)) return EventPhase.done;
    if (!now.isBefore(startsAt)) return EventPhase.now;
    return EventPhase.next;
  }

  /// "1 Std 30", or the day count for an all-day span.
  String get durationLabel {
    if (allDay) {
      final days = endsAt.difference(startsAt).inDays;
      if (days <= 1) return 'Ganztägig';
      return '$days Tage';
    }
    final minutes = endsAt.difference(startsAt).inMinutes;
    if (minutes >= 60) {
      return minutes % 60 == 0 ? '${minutes ~/ 60} Std' : '${minutes ~/ 60} Std ${minutes % 60}';
    }
    return '$minutes Min';
  }

  /// Every date this event covers, midnight-normalised.
  ///
  /// A Ferien block is one row spanning two weeks; the calendar renders per day,
  /// so it has to appear on each of them. The exclusive end is why the loop
  /// stops *before* `endsAt` for an all-day event.
  List<DateTime> get days {
    final first = DateTime(startsAt.year, startsAt.month, startsAt.day);
    final lastMoment = allDay ? endsAt.subtract(const Duration(seconds: 1)) : endsAt;
    final last = DateTime(lastMoment.year, lastMoment.month, lastMoment.day);

    final out = <DateTime>[first];
    // Guarded: a malformed provider row with a wild end date must not spin here.
    for (var day = first; day.isBefore(last) && out.length < 400;) {
      day = DateTime(day.year, day.month, day.day + 1);
      out.add(day);
    }
    return out;
  }

  CalendarEvent copyWith({
    String? title,
    DateTime? startsAt,
    DateTime? endsAt,
    bool? allDay,
    String? body,
    String? loc,
    String? locSub,
    bool? online,
    String? reminder,
    String? source,
    Color? srcColor,
  }) {
    return CalendarEvent(
      id: id,
      calendarId: calendarId,
      uid: uid,
      title: title ?? this.title,
      startsAt: startsAt ?? this.startsAt,
      endsAt: endsAt ?? this.endsAt,
      allDay: allDay ?? this.allDay,
      body: body ?? this.body,
      loc: loc ?? this.loc,
      locSub: locSub ?? this.locSub,
      online: online ?? this.online,
      url: url,
      reminder: reminder ?? this.reminder,
      owner: owner,
      ownerInitial: ownerInitial,
      ownerTone: ownerTone,
      source: source ?? this.source,
      srcColor: srcColor ?? this.srcColor,
      temp: temp,
      cond: cond,
      condLabel: condLabel,
    );
  }

  /// The real `public.events` columns. [calendar] supplies the name and colour,
  /// which live on the calendar rather than the event.
  static CalendarEvent fromMap(
    Map<String, dynamic> map, {
    required CalendarSource calendar,
    String owner = '',
    String ownerInitial = '',
    int ownerTone = 0,
  }) {
    final starts = DateTime.parse(map['starts_at'] as String).toLocal();
    final endsRaw = map['ends_at'] as String?;
    final minutes = (map['reminder_minutes'] as num?)?.toInt();
    final title = (map['title'] as String? ?? '').trim();

    // On a waste calendar the colour answers the only question anybody asks of
    // it — which bin goes out — so it comes from the fraction rather than from
    // the feed. Everywhere else the calendar's colour is the event's, which is
    // what makes a Google calendar recognisable at a glance.
    final color = calendar.feedKind == 'abfall'
        ? binColorFor(title) ?? calendar.color
        : calendar.color;

    return CalendarEvent(
      id: map['id'] as String,
      calendarId: map['calendar_id'] as String,
      // Absent on a PostgREST row by design: our own events have no provider
      // identity, and inventing one would make them look proxied.
      uid: map['uid'] as String? ?? '',
      title: title.isEmpty ? 'Ohne Titel' : title,
      startsAt: starts,
      endsAt: endsRaw == null ? starts : DateTime.parse(endsRaw).toLocal(),
      allDay: map['all_day'] == true,
      body: map['notes'] as String? ?? '',
      loc: map['location'] as String? ?? '',
      locSub: map['location_sub'] as String? ?? '',
      online: map['online'] == true,
      url: map['url'] as String? ?? '',
      reminder: minutes == null ? '' : '$minutes Minuten vorher',
      owner: owner,
      ownerInitial: ownerInitial,
      ownerTone: ownerTone,
      source: calendar.name,
      srcColor: color,
    );
  }

  /// Only the columns a client may write. `external_uid`, `external_href` and
  /// `external_etag` are the sync function's, and are deliberately absent: an
  /// event typed by hand must never look like a pulled one, or the next
  /// reconcile would delete it.
  Map<String, dynamic> toMap() => {
    'calendar_id': calendarId,
    'title': title,
    'starts_at': startsAt.toUtc().toIso8601String(),
    'ends_at': endsAt.toUtc().toIso8601String(),
    'all_day': allDay,
    'notes': body.isEmpty ? null : body,
    'location': loc.isEmpty ? null : loc,
    'location_sub': locSub.isEmpty ? null : locSub,
    'online': online,
    'url': url.isEmpty ? null : url,
  };
}
