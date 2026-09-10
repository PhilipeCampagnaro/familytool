import 'event_link.dart';
import 'visibility.dart';

DateTime? _timeFrom(Object? value) => value == null ? null : DateTime.tryParse(value as String)?.toLocal();

/// The hour a to-do is owed by, when it names one.
///
/// **A wall clock, not an instant** — the pair `(due_date, due_time)` is a local
/// reading the way "Donnerstag um acht" is, and neither half carries a zone. A
/// `DateTime` here would have to invent one, and a household that travels would
/// watch its week move; see the migration beside `tasks.due_time`.
///
/// Plain Dart rather than Flutter's `TimeOfDay`, so the models stay free of
/// `material.dart` the way the rest of `lib/models/` is. The one place the two
/// meet is the picker, which converts at its own edge.
class DueTime implements Comparable<DueTime> {
  final int hour;
  final int minute;

  const DueTime(this.hour, this.minute);

  /// Postgres hands a `time` back as `HH:MM:SS`, and sometimes with a fractional
  /// part. Anything past the minute is dropped: the picker cannot produce it and
  /// nothing in the app would show it.
  static DueTime? parse(String? value) {
    if (value == null) return null;
    final parts = value.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return DueTime(h, m);
  }

  /// `HH:MM` — what a Postgres `time` column takes.
  String toSql() => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  /// Minutes since midnight, which is what sorting a day by it comes down to.
  int get minutes => hour * 60 + minute;

  @override
  int compareTo(DueTime other) => minutes.compareTo(other.minutes);

  @override
  bool operator ==(Object other) => other is DueTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);
}

/// One Board task — a `public.tasks` row.
///
/// Two things changed when this stopped being seed data, and both are the point
/// of the row rather than incidental:
///
/// * The single `who` string (`'all' | 'private' | <memberId>`) is gone. It
///   conflated *who may see this* with *who is meant to do it* — the old
///   `whoHint` said so out loud: "Zugewiesen an Lea — für alle sichtbar."
///   Those are now [visibility] (+ `task_shares`) and [assigneeId], and they
///   move independently: a task can be assigned to Lea and private to you.
/// * The day is a real [dueDate], not a day-of-month `int`. A week regularly
///   straddles two months, where an `int` collides.
class BoardTask {
  final String id;
  final String familyId;

  /// Midnight-normalised local date, or **null for a task with no date at all**.
  /// `due_date` is a Postgres `date`, so it carries no time and no zone — a task
  /// due "Donnerstag" is due Donnerstag wherever the phone is.
  ///
  /// Nullable because the Board is a grouped list rather than a day: "Ohne
  /// Datum" is a section like any other, and it is where a new task starts.
  /// Anything reading this has to answer for the null — see [boardSectionOf].
  final DateTime? dueDate;

  /// The hour it is owed by, or null — which is most to-dos. Only ever set
  /// alongside a [dueDate]; the database refuses the other combination
  /// (`tasks_due_time_needs_date`), because an hour with no day names nothing.
  ///
  /// **It does not decide when the to-do is overdue.** That stays a question
  /// about the day — [boardSectionOf] never reads this. A row moving into
  /// "Überfällig" at 09:01 of the day it was planned for would nag inside the
  /// one section people open the app to see. What the hour does is place the
  /// to-do among the appointments in the Kalender agenda, which is the only
  /// screen that has a position to give it.
  final DueTime? dueTime;

  final String text;
  final String? meta;

  /// Who is meant to do it, or null for "anybody". Never a visibility hint.
  final String? assigneeId;

  final bool done;
  final String? doneBy;
  final DateTime? doneAt;

  final String ownerId;
  final ItemVisibility visibility;

  /// The user ids in `task_shares`, when [visibility] is
  /// [ItemVisibility.custom]. The owner is implicit and not repeated.
  final List<String> sharedWith;

  /// The appointment this task was created for, or null — which is almost every
  /// task. Set once, when the task is made from an event's detail sheet; the
  /// edit sheet neither shows nor touches it.
  ///
  /// **Not the same thing as [dueDate].** A task made from an appointment gets
  /// the appointment's date as its deadline, but a deadline is a day and this
  /// is a specific event — two tasks due the same Thursday, one of them hung off
  /// the Zahnarzt, are exactly the case the badge exists to tell apart.
  final EventLink? eventLink;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const BoardTask({
    required this.id,
    required this.familyId,
    this.dueDate,
    this.dueTime,
    required this.text,
    required this.ownerId,
    this.meta,
    this.assigneeId,
    this.done = false,
    this.doneBy,
    this.doneAt,
    this.visibility = ItemVisibility.family,
    this.sharedWith = const [],
    this.eventLink,
    this.createdAt,
    this.updatedAt,
  });

  factory BoardTask.fromMap(Map<String, dynamic> map, {List<String> sharedWith = const []}) {
    return BoardTask(
      id: map['id'] as String,
      familyId: map['family_id'] as String,
      dueDate: switch (map['due_date']) {
        final String value => parseDueDate(value),
        _ => null,
      },
      dueTime: DueTime.parse(map['due_time'] as String?),
      text: map['text'] as String,
      meta: map['meta'] as String?,
      assigneeId: map['assignee_id'] as String?,
      done: map['done'] as bool? ?? false,
      doneBy: map['done_by'] as String?,
      doneAt: _timeFrom(map['done_at']),
      ownerId: map['owner_id'] as String,
      visibility: visibilityFrom(map['visibility'] as String?),
      sharedWith: sharedWith,
      eventLink: EventLink.fromMap(map),
      createdAt: _timeFrom(map['created_at']),
      updatedAt: _timeFrom(map['updated_at']),
    );
  }

  /// `owner_id`/`family_id` only on insert — on update
  /// `enforce_container_ownership` rejects them from anyone but the owner.
  Map<String, dynamic> toMap({bool forInsert = false}) => {
    'due_date': dueDate == null ? null : formatDueDate(dueDate!),
    // Written together with the date, so clearing the date clears the hour in
    // the same statement rather than tripping the check constraint.
    'due_time': dueDate == null ? null : dueTime?.toSql(),
    'text': text,
    'meta': meta,
    'assignee_id': assigneeId,
    'done': done,
    'done_by': doneBy,
    'done_at': doneAt?.toUtc().toIso8601String(),
    'visibility': visibility.name,
    // All four columns or none — see [ShoppingList.toMap].
    ...EventLink.columnsOf(eventLink),
    if (forInsert) ...{'family_id': familyId, 'owner_id': ownerId},
  };

  BoardTask copyWith({
    DateTime? dueDate,
    bool clearDueDate = false,
    DueTime? dueTime,
    bool clearDueTime = false,
    String? text,
    String? meta,
    bool clearMeta = false,
    String? assigneeId,
    bool clearAssignee = false,
    bool? done,
    String? doneBy,
    bool clearDoneBy = false,
    DateTime? doneAt,
    bool clearDoneAt = false,
    ItemVisibility? visibility,
    List<String>? sharedWith,
    EventLink? eventLink,
  }) => BoardTask(
    id: id,
    familyId: familyId,
    dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
    // A to-do that loses its day loses its hour with it — the pair is what
    // means something, and the database says so too.
    dueTime: clearDueDate || clearDueTime ? null : (dueTime ?? this.dueTime),
    text: text ?? this.text,
    meta: clearMeta ? null : (meta ?? this.meta),
    assigneeId: clearAssignee ? null : (assigneeId ?? this.assigneeId),
    done: done ?? this.done,
    doneBy: clearDoneBy ? null : (doneBy ?? this.doneBy),
    doneAt: clearDoneAt ? null : (doneAt ?? this.doneAt),
    ownerId: ownerId,
    visibility: visibility ?? this.visibility,
    sharedWith: sharedWith ?? this.sharedWith,
    eventLink: eventLink ?? this.eventLink,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// 'YYYY-MM-DD' — what a Postgres `date` column takes.
///
/// Hand-formatted rather than `toIso8601String().substring(0, 10)`: that goes
/// through UTC for a UTC `DateTime`, and a task created late on a summer evening
/// in Berlin would be filed under the previous day.
String formatDueDate(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

/// The inverse. `DateTime.parse('2026-08-13')` gives local midnight, which is
/// exactly the midnight-normalised key the Board's day maps use.
DateTime parseDueDate(String value) => DateTime.parse(value);
