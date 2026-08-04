import 'visibility.dart';

DateTime? _timeFrom(Object? value) => value == null ? null : DateTime.tryParse(value as String)?.toLocal();

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

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const BoardTask({
    required this.id,
    required this.familyId,
    this.dueDate,
    required this.text,
    required this.ownerId,
    this.meta,
    this.assigneeId,
    this.done = false,
    this.doneBy,
    this.doneAt,
    this.visibility = ItemVisibility.family,
    this.sharedWith = const [],
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
      text: map['text'] as String,
      meta: map['meta'] as String?,
      assigneeId: map['assignee_id'] as String?,
      done: map['done'] as bool? ?? false,
      doneBy: map['done_by'] as String?,
      doneAt: _timeFrom(map['done_at']),
      ownerId: map['owner_id'] as String,
      visibility: visibilityFrom(map['visibility'] as String?),
      sharedWith: sharedWith,
      createdAt: _timeFrom(map['created_at']),
      updatedAt: _timeFrom(map['updated_at']),
    );
  }

  /// `owner_id`/`family_id` only on insert — on update
  /// `enforce_container_ownership` rejects them from anyone but the owner.
  Map<String, dynamic> toMap({bool forInsert = false}) => {
    'due_date': dueDate == null ? null : formatDueDate(dueDate!),
    'text': text,
    'meta': meta,
    'assignee_id': assigneeId,
    'done': done,
    'done_by': doneBy,
    'done_at': doneAt?.toUtc().toIso8601String(),
    'visibility': visibility.name,
    if (forInsert) ...{'family_id': familyId, 'owner_id': ownerId},
  };

  BoardTask copyWith({
    DateTime? dueDate,
    bool clearDueDate = false,
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
  }) => BoardTask(
    id: id,
    familyId: familyId,
    dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
    text: text ?? this.text,
    meta: clearMeta ? null : (meta ?? this.meta),
    assigneeId: clearAssignee ? null : (assigneeId ?? this.assigneeId),
    done: done ?? this.done,
    doneBy: clearDoneBy ? null : (doneBy ?? this.doneBy),
    doneAt: clearDoneAt ? null : (doneAt ?? this.doneAt),
    ownerId: ownerId,
    visibility: visibility ?? this.visibility,
    sharedWith: sharedWith ?? this.sharedWith,
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
