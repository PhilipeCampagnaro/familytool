/// The appointment a list or a task was created for.
///
/// **Points at an event that is not ours and is not stored anywhere.** Aporah
/// keeps no calendar of its own — every event is proxied from the connected
/// account or the shared feed on each read — so a link cannot be a foreign key
/// to a row. It is the pair the provider itself guarantees: the calendar, and
/// the event's own [uid]. `Homework.eventUid` already names a lesson the same
/// way, and this is deliberately the same mechanism rather than a second one.
///
/// **It carries no title, on purpose.** The appointment's name is content out
/// of somebody's calendar, and writing it onto a `lists` row to label a badge
/// with would be keeping a copy of it in our database — the one thing the
/// backend refuses to do. `EventLinkChip` resolves the live name through
/// `CalendarScreenState.eventForLink` when Kalender is holding the event, and
/// prints the date when it is not.
///
/// [startsAt] is the exception and is a date rather than content: without it the
/// tap back has nowhere to go for an appointment outside the fortnight Kalender
/// loads, which is most of them. On a task the same day is already in
/// `due_date`. It is a snapshot and goes stale if the appointment is moved,
/// which costs a wrong day and never a wrong list.
class EventLink {
  /// A `public.calendars.id`, or a `public.public_feeds.id` for Ferien and
  /// Abfall. Two tables on purpose: a shared feed is not a household's
  /// calendar. That is also why the column carries no foreign key.
  final String calendarId;

  /// The provider's own identifier for the event — the same value
  /// `calendar-write` addresses an edit with.
  final String uid;

  /// When it started, for the jump back into Kalender.
  final DateTime? startsAt;

  const EventLink({required this.calendarId, required this.uid, this.startsAt});

  /// Null when the row is not linked to anything — which is almost every row,
  /// so callers read this as "is there a link?" rather than checking columns.
  static EventLink? fromMap(Map<String, dynamic> map) {
    final calendarId = (map['event_calendar_id'] as String? ?? '').trim();
    final uid = (map['event_uid'] as String? ?? '').trim();
    if (calendarId.isEmpty || uid.isEmpty) return null;
    final starts = map['event_starts_at'] as String?;
    return EventLink(
      calendarId: calendarId,
      uid: uid,
      // Local, like every other instant the app renders. An all-day event's
      // link lands on its own midnight either way, because the jump only reads
      // the date off this.
      startsAt: starts == null ? null : DateTime.tryParse(starts)?.toLocal(),
    );
  }

  /// All three columns — a null link writes three nulls rather than nothing, so
  /// that clearing one is expressible. See [columnsOf].
  Map<String, dynamic> toMap() => {
    'event_calendar_id': calendarId,
    'event_uid': uid,
    'event_starts_at': startsAt?.toUtc().toIso8601String(),
  };

  /// What to send for a link that may or may not be there. The database's
  /// `*_event_link_complete` check refuses half a link, so the columns are
  /// always written together.
  static Map<String, dynamic> columnsOf(EventLink? link) =>
      link?.toMap() ??
      const {'event_calendar_id': null, 'event_uid': null, 'event_starts_at': null};

  /// The day the appointment falls on, midnight-normalised — what Kalender is
  /// jumped to. Null where the snapshot has no date, in which case the jump
  /// lands on today and the event is simply not highlighted.
  DateTime? get day =>
      startsAt == null ? null : DateTime(startsAt!.year, startsAt!.month, startsAt!.day);

  /// Whether this names the given event. Both halves, because the same
  /// appointment invited to two accounts in one household keeps its `uid` and
  /// arrives on two calendars — a list hung off one of them belongs to that one.
  bool namesEvent({required String calendarId, required String uid}) =>
      uid.isNotEmpty && this.uid == uid && this.calendarId == calendarId;
}
