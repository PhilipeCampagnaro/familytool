import 'task.dart' show formatDueDate, parseDueDate;
import 'visibility.dart';

DateTime? _timeFrom(Object? value) => value == null ? null : DateTime.tryParse(value as String)?.toLocal();

/// The two kinds of rhythm a tracker can keep — `public.tracker_schedule`.
///
/// [daily] and [weekdays] make the **day** the unit: a Donnerstag tracker is met
/// or missed on Donnerstag, and the Board can say "heute dran" about it.
/// [weeklyCount] makes the **week** the unit: "vier Tage pro Woche" owes nothing
/// on any particular day and cannot be missed until Sunday has closed.
///
/// They are not three presets of one thing, which is why the app renders them
/// differently and why the day grid only counts the first two. Asking a
/// four-days-a-week tracker whether it is due today has no answer.
enum TrackerScheduleKind { daily, weekdays, weeklyCount }

/// The wire spelling — the Postgres enum is snake_case and Dart is not.
const _scheduleWire = {
  TrackerScheduleKind.daily: 'daily',
  TrackerScheduleKind.weekdays: 'weekdays',
  TrackerScheduleKind.weeklyCount: 'weekly_count',
};

TrackerScheduleKind _scheduleKindFrom(String? value) => switch (value) {
  'weekdays' => TrackerScheduleKind.weekdays,
  'weekly_count' => TrackerScheduleKind.weeklyCount,
  _ => TrackerScheduleKind.daily,
};

/// A tracker's rhythm: the kind, plus the one number or set the kind needs.
///
/// One class rather than a sealed hierarchy because the sheet edits it as one
/// draft — somebody switching from "an bestimmten Tagen" to "x-mal pro Woche"
/// and back expects to find their weekdays where they left them. The unused
/// side is simply not written: [toMap] sends null for whichever column this
/// kind does not use, which is what `trackers_schedule_shape` insists on.
class TrackerSchedule {
  final TrackerScheduleKind kind;

  /// ISO weekdays, 1 = Montag … 7 = Sonntag, matching `DateTime.weekday` so no
  /// renumbering happens anywhere. Empty unless [kind] is
  /// [TrackerScheduleKind.weekdays].
  final Set<int> weekdays;

  /// Days per week, 1..7. Zero unless [kind] is
  /// [TrackerScheduleKind.weeklyCount].
  final int target;

  const TrackerSchedule._(this.kind, this.weekdays, this.target);

  static const daily = TrackerSchedule._(TrackerScheduleKind.daily, <int>{}, 0);

  /// Days outside 1..7 are dropped rather than clamped: a 0 clamped to Monday
  /// would silently schedule a day nobody picked.
  factory TrackerSchedule.onWeekdays(Iterable<int> days) => TrackerSchedule._(TrackerScheduleKind.weekdays, {
    for (final d in days)
      if (d >= 1 && d <= 7) d,
  }, 0);

  factory TrackerSchedule.timesPerWeek(int target) =>
      TrackerSchedule._(TrackerScheduleKind.weeklyCount, const <int>{}, target.clamp(1, 7));

  /// Whether the rhythm names particular days, and so whether "heute dran" and
  /// the header's day grid mean anything for it.
  bool get isDayBased => kind != TrackerScheduleKind.weeklyCount;

  /// The days this rhythm covers, ascending, for the weekday chips to light up.
  /// Every day for [TrackerScheduleKind.daily]; empty for a weekly count, which
  /// names no day at all.
  List<int> get activeWeekdays => switch (kind) {
    TrackerScheduleKind.daily => const [1, 2, 3, 4, 5, 6, 7],
    TrackerScheduleKind.weekdays => weekdays.toList()..sort(),
    TrackerScheduleKind.weeklyCount => const [],
  };

  /// True for a rhythm the database would reject — an empty weekday set is the
  /// only way a user can reach one, by clearing every chip.
  bool get isComplete => switch (kind) {
    TrackerScheduleKind.daily => true,
    TrackerScheduleKind.weekdays => weekdays.isNotEmpty,
    TrackerScheduleKind.weeklyCount => target >= 1 && target <= 7,
  };

  factory TrackerSchedule.fromMap(Map<String, dynamic> map) {
    final kind = _scheduleKindFrom(map['schedule'] as String?);
    return switch (kind) {
      TrackerScheduleKind.daily => TrackerSchedule.daily,
      TrackerScheduleKind.weekdays => TrackerSchedule.onWeekdays(
        // PostgREST hands a smallint[] back as a plain List of ints.
        [for (final d in (map['weekdays'] as List<dynamic>? ?? const [])) (d as num).toInt()],
      ),
      TrackerScheduleKind.weeklyCount => TrackerSchedule.timesPerWeek((map['target'] as num?)?.toInt() ?? 1),
    };
  }

  Map<String, dynamic> toMap() => {
    'schedule': _scheduleWire[kind],
    'weekdays': kind == TrackerScheduleKind.weekdays ? (weekdays.toList()..sort()) : null,
    'target': kind == TrackerScheduleKind.weeklyCount ? target : null,
  };

  @override
  bool operator ==(Object other) =>
      other is TrackerSchedule &&
      other.kind == kind &&
      other.target == target &&
      other.weekdays.length == weekdays.length &&
      other.weekdays.containsAll(weekdays);

  @override
  int get hashCode => Object.hash(kind, target, Object.hashAllUnordered(weekdays));
}

/// One Board tracker — a `public.trackers` row.
///
/// A tracker is a *rule*, not a pile of dated rows: which days it was due is
/// computed from [schedule] whenever something asks, and the only thing stored
/// per day is a [TrackerCheck] saying it was met. See the migration for why the
/// future is never materialised.
///
/// The three axes are the same ones every container carries — [assigneeId] is
/// who does it, [visibility] plus `tracker_shares` is who in the household sees
/// it, and there is deliberately no third: a tracker is not externally
/// shareable, and `public.shareable_kind` names no value for one.
class Tracker {
  final String id;
  final String familyId;
  final String text;
  final String? meta;

  /// The same key space lists and boxes use, so `suggestIcon` can name a
  /// tracker off the typed text like any other container.
  final String? iconKey;

  final TrackerSchedule schedule;

  /// Who is meant to keep it, or null for a row written before the sheet
  /// insisted on somebody. Never a visibility hint.
  final String? assigneeId;

  /// Midnight-normalised. Nothing before this day can be missed — a tracker made
  /// in September must not open on a grid of failures reaching back to whenever
  /// the household signed up.
  final DateTime startsOn;

  /// Retired, and kept only for the record. The Board loads live trackers alone.
  final DateTime? archivedAt;

  final String ownerId;
  final ItemVisibility visibility;

  /// The user ids in `tracker_shares`, when [visibility] is
  /// [ItemVisibility.custom]. The owner is implicit and not repeated.
  final List<String> sharedWith;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Tracker({
    required this.id,
    required this.familyId,
    required this.text,
    required this.schedule,
    required this.startsOn,
    required this.ownerId,
    this.meta,
    this.iconKey,
    this.assigneeId,
    this.archivedAt,
    this.visibility = ItemVisibility.family,
    this.sharedWith = const [],
    this.createdAt,
    this.updatedAt,
  });

  bool get isArchived => archivedAt != null;

  factory Tracker.fromMap(Map<String, dynamic> map, {List<String> sharedWith = const []}) => Tracker(
    id: map['id'] as String,
    familyId: map['family_id'] as String,
    text: map['text'] as String,
    meta: map['meta'] as String?,
    iconKey: map['icon_key'] as String?,
    schedule: TrackerSchedule.fromMap(map),
    assigneeId: map['assignee_id'] as String?,
    startsOn: parseDueDate(map['starts_on'] as String),
    archivedAt: _timeFrom(map['archived_at']),
    ownerId: map['owner_id'] as String,
    visibility: visibilityFrom(map['visibility'] as String?),
    sharedWith: sharedWith,
    createdAt: _timeFrom(map['created_at']),
    updatedAt: _timeFrom(map['updated_at']),
  );

  /// `owner_id`/`family_id` only on insert — on update
  /// `enforce_container_ownership` rejects them from anyone but the owner.
  Map<String, dynamic> toMap({bool forInsert = false}) => {
    'text': text,
    'meta': meta,
    'icon_key': iconKey,
    ...schedule.toMap(),
    'assignee_id': assigneeId,
    'starts_on': formatDueDate(startsOn),
    'archived_at': archivedAt?.toUtc().toIso8601String(),
    'visibility': visibility.name,
    if (forInsert) ...{'family_id': familyId, 'owner_id': ownerId},
  };

  Tracker copyWith({
    String? text,
    String? meta,
    bool clearMeta = false,
    String? iconKey,
    bool clearIcon = false,
    TrackerSchedule? schedule,
    String? assigneeId,
    bool clearAssignee = false,
    DateTime? startsOn,
    DateTime? archivedAt,
    bool clearArchived = false,
    ItemVisibility? visibility,
    List<String>? sharedWith,
  }) => Tracker(
    id: id,
    familyId: familyId,
    text: text ?? this.text,
    meta: clearMeta ? null : (meta ?? this.meta),
    iconKey: clearIcon ? null : (iconKey ?? this.iconKey),
    schedule: schedule ?? this.schedule,
    assigneeId: clearAssignee ? null : (assigneeId ?? this.assigneeId),
    startsOn: startsOn ?? this.startsOn,
    archivedAt: clearArchived ? null : (archivedAt ?? this.archivedAt),
    ownerId: ownerId,
    visibility: visibility ?? this.visibility,
    sharedWith: sharedWith ?? this.sharedWith,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// One day a tracker was met — a `public.tracker_checks` row.
///
/// There is no "missed" counterpart and there never will be: a miss is the
/// absence of one of these on a day the rule scheduled, and only the rule knows
/// which days those were. Ticking writes a row, unticking deletes it.
class TrackerCheck {
  final String trackerId;

  /// Midnight-normalised local day. A `date` column, so no time and no zone —
  /// a Donnerstag ticked off in Berlin is Donnerstag everywhere.
  final DateTime day;

  final String doneBy;
  final DateTime? doneAt;

  const TrackerCheck({required this.trackerId, required this.day, required this.doneBy, this.doneAt});

  factory TrackerCheck.fromMap(Map<String, dynamic> map) => TrackerCheck(
    trackerId: map['tracker_id'] as String,
    day: parseDueDate(map['day'] as String),
    doneBy: map['done_by'] as String,
    doneAt: _timeFrom(map['done_at']),
  );
}
