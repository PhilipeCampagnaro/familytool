import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/task.dart' show formatDueDate;
import '../../models/tracker.dart';
import '../../models/visibility.dart';
import '../../services/supabase.dart';
import '../board_data.dart';
import '../tracker_data.dart';
import 'list_repository.dart' show newUuidV4;
import '../../l10n/l10n.dart';

/// Everything a tracker and its checks are, in one place — the only file that
/// knows they live in PostgREST.
///
/// Same two rules as the other four repositories: no `family_id` filter (RLS
/// already decides what "my trackers" means) and column names live here and
/// nowhere else.
class TrackerRepository {
  TrackerRepository([SupabaseClient? client]) : _db = client ?? AporahSupabase.client;

  final SupabaseClient _db;

  static const _columns =
      'id, family_id, text, meta, icon_key, schedule, weekdays, target, assignee_id, '
      'starts_on, archived_at, owner_id, visibility, created_at, updated_at';

  String get _uid {
    final id = AporahSupabase.userId;
    if (id == null) throw StateError(L.s.notSignedIn);
    return id;
  }

  // -------------------------------------------------------------------------
  // Read
  // -------------------------------------------------------------------------

  /// The live trackers, oldest first. Archived ones stay in the table and out of
  /// the app: they are kept so the days they were held do not vanish, not so
  /// they keep asking to be ticked.
  Future<List<Tracker>> fetchTrackers() async {
    final rows = await _db
        .from('trackers')
        .select(_columns)
        .isFilter('archived_at', null)
        .order('created_at', ascending: true);
    if (rows.isEmpty) return const [];

    final ids = [for (final r in rows) r['id'] as String];
    final shareRows = await _db.from('tracker_shares').select('tracker_id, user_id').inFilter('tracker_id', ids);

    final sharedWith = <String, List<String>>{};
    for (final r in shareRows) {
      (sharedWith[r['tracker_id'] as String] ??= []).add(r['user_id'] as String);
    }

    return [
      for (final r in rows) Tracker.fromMap(r, sharedWith: sharedWith[r['id'] as String] ?? const []),
    ];
  }

  /// Every check inside the history window, grouped by tracker.
  ///
  /// One window rather than one query per tracker: a household keeps a handful
  /// of trackers and half a year of days is a few hundred rows at most, which is
  /// smaller than the task list beside it. Bounded all the same, because the
  /// record is meant to outlive the rows it describes.
  Future<Map<String, Set<DateTime>>> fetchChecks() async {
    final since = boardDaysAfter(boardDay(DateTime.now()), -trackerHistoryDays);
    final rows = await _db
        .from('tracker_checks')
        .select('tracker_id, day, done_by, done_at')
        .gte('day', formatDueDate(since));

    final byTracker = <String, Set<DateTime>>{};
    for (final r in rows) {
      final check = TrackerCheck.fromMap(r);
      (byTracker[check.trackerId] ??= <DateTime>{}).add(check.day);
    }
    return byTracker;
  }

  // -------------------------------------------------------------------------
  // Write
  // -------------------------------------------------------------------------

  /// **The insert carries no `.select()`** — see [ListRepository.createList] for
  /// why `insert … returning` fails the SELECT policy on every container table.
  Future<Tracker> createTracker({
    required String familyId,
    required String text,
    required TrackerSchedule schedule,
    String? meta,
    String? iconKey,
    String? assigneeId,
    DateTime? startsOn,
    ItemVisibility visibility = ItemVisibility.family,
    Set<String> sharedWith = const {},
  }) async {
    final id = newUuidV4();
    final ownerId = _uid;
    final draft = Tracker(
      id: id,
      familyId: familyId,
      text: text,
      meta: meta,
      iconKey: iconKey,
      schedule: schedule,
      assigneeId: assigneeId,
      // Today unless told otherwise: a tracker made this morning has kept no
      // days and missed none either.
      startsOn: startsOn ?? boardDay(DateTime.now()),
      ownerId: ownerId,
      visibility: visibility,
    );

    await _db.from('trackers').insert({...draft.toMap(forInsert: true), 'id': id});

    final members = _effectiveShares(visibility, sharedWith, ownerId);
    if (members.isNotEmpty) await _writeShares(id, familyId, members);

    final row = await _db.from('trackers').select(_columns).eq('id', id).single();
    return Tracker.fromMap(row, sharedWith: members.toList());
  }

  Future<Tracker> updateTracker(
    Tracker tracker, {
    required String text,
    String? meta,
    String? iconKey,
    TrackerSchedule? schedule,
    String? assigneeId,
    bool clearAssignee = false,
    ItemVisibility? visibility,
    Set<String>? sharedWith,
  }) async {
    final patch = <String, dynamic>{
      'text': text,
      'meta': meta,
      // Omitted rather than nulled when nothing was picked: a null here would
      // clear an icon the tracker already has.
      'icon_key': ?iconKey,
      // The whole rhythm or none of it. Sending `weekdays` without `schedule`
      // would leave a row half-way between two kinds, which
      // `trackers_schedule_shape` rejects outright.
      if (schedule != null) ...schedule.toMap(),
      'assignee_id': clearAssignee ? null : assigneeId,
      if (visibility != null && visibility != tracker.visibility) 'visibility': visibility.name,
    };

    final row = await _db.from('trackers').update(patch).eq('id', tracker.id).select(_columns).single();
    final saved = Tracker.fromMap(row);

    // Shares are the owner's to change, so a member editing someone else's
    // tracker leaves them alone.
    if (sharedWith == null || saved.ownerId != AporahSupabase.userId) {
      return saved.copyWith(sharedWith: tracker.sharedWith);
    }

    final members = _effectiveShares(saved.visibility, sharedWith, saved.ownerId);
    await _db.from('tracker_shares').delete().eq('tracker_id', saved.id);
    if (members.isNotEmpty) await _writeShares(saved.id, saved.familyId, members);

    return saved.copyWith(sharedWith: members.toList());
  }

  /// Ticks [day] off, or takes the tick back.
  ///
  /// An upsert rather than an insert: two people tapping the same tracker on the
  /// same morning is an ordinary race in a household, and the second tap should
  /// be a no-op rather than a duplicate-key error thrown into somebody's face.
  /// Unticking removes the row — there is no "not done" to record, because a
  /// miss is the absence of a check on a scheduled day.
  Future<void> setChecked(String trackerId, String familyId, DateTime day, bool checked) async {
    final key = formatDueDate(boardDay(day));
    if (!checked) {
      await _db.from('tracker_checks').delete().eq('tracker_id', trackerId).eq('day', key).eq('done_by', _uid);
      return;
    }
    await _db.from('tracker_checks').upsert({
      'tracker_id': trackerId,
      'family_id': familyId,
      'day': key,
      'done_by': _uid,
      'done_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'tracker_id,day,done_by');
  }

  /// Retires a tracker without touching its record. The checks stay, so a
  /// household that stops tracking the bins in June can still see the spring.
  Future<void> archiveTracker(String id) async {
    await _db.from('trackers').update({
      'archived_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  /// Deletes it outright, checks and all — `on delete cascade` takes the record
  /// with it. This is the row menu's "löschen"; archiving is what the app does
  /// when somebody only wants it off the screen.
  Future<void> deleteTracker(String id) async {
    await _db.from('trackers').delete().eq('id', id);
  }

  Set<String> _effectiveShares(ItemVisibility visibility, Set<String> sharedWith, String ownerId) {
    if (visibility != ItemVisibility.custom) return const {};
    return {...sharedWith}..remove(ownerId);
  }

  Future<void> _writeShares(String trackerId, String familyId, Set<String> members) async {
    await _db.from('tracker_shares').insert([
      for (final userId in members) {'tracker_id': trackerId, 'family_id': familyId, 'user_id': userId},
    ]);
  }
}
