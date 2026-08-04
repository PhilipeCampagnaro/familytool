import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/task.dart';
import '../../models/visibility.dart';
import '../../services/supabase.dart';
import 'list_repository.dart' show newUuidV4;
import '../../l10n/l10n.dart';

/// The only file in the app that knows Board tasks are stored in PostgREST.
///
/// Same two rules as `ListRepository` and `BoxRepository`: no `family_id`
/// filter (RLS already decides what "my tasks" means, and filtering would drop
/// the guest branch), and column names live here and nowhere else.
class BoardRepository {
  BoardRepository([SupabaseClient? client]) : _db = client ?? AporahSupabase.client;

  final SupabaseClient _db;

  static const _columns =
      'id, family_id, due_date, text, meta, assignee_id, done, done_by, done_at, owner_id, visibility, created_at, updated_at';

  String get _uid {
    final id = AporahSupabase.userId;
    if (id == null) throw StateError(L.s.notSignedIn);
    return id;
  }

  // -------------------------------------------------------------------------
  // Read
  // -------------------------------------------------------------------------

  /// How far back finished tasks are still worth showing. The "Erledigt" card is
  /// a record of the last few days, not an archive — and without a cut-off it
  /// would be the longest thing on the screen within a month.
  static const _doneWindowDays = 14;

  /// Everything the Board shows, in one round trip: every open task the
  /// signed-in user may see, whatever its date or lack of one, plus the tasks
  /// finished in the last [_doneWindowDays].
  ///
  /// The old `fetchRange(from, to)` was bounded by the week strip's date window
  /// and re-fetched when the strip walked out of it. With the strip gone there
  /// is no window to page — and a `due_date` window could not have loaded an
  /// undated task at all, since `null` satisfies neither `gte` nor `lte`. What
  /// bounds this instead is *done*: open tasks are the Board's whole job and a
  /// household has tens of them, while finished ones accumulate forever.
  Future<List<BoardTask>> fetchBoard() async {
    final since = DateTime.now().toUtc().subtract(const Duration(days: _doneWindowDays));
    final rows = await _db
        .from('tasks')
        .select(_columns)
        .or('done.eq.false,done_at.gte.${since.toIso8601String()}')
        .order('created_at', ascending: true);
    if (rows.isEmpty) return const [];

    final ids = [for (final r in rows) r['id'] as String];
    final shareRows = await _db.from('task_shares').select('task_id, user_id').inFilter('task_id', ids);

    final sharedWith = <String, List<String>>{};
    for (final r in shareRows) {
      (sharedWith[r['task_id'] as String] ??= []).add(r['user_id'] as String);
    }

    return [
      for (final r in rows) BoardTask.fromMap(r, sharedWith: sharedWith[r['id'] as String] ?? const []),
    ];
  }

  // -------------------------------------------------------------------------
  // Write
  // -------------------------------------------------------------------------

  /// **The insert carries no `.select()`** — see
  /// [ListRepository.createList] for why `insert … returning` fails the SELECT
  /// policy on every container table.
  Future<BoardTask> createTask({
    required String familyId,
    DateTime? dueDate,
    required String text,
    String? meta,
    String? assigneeId,
    ItemVisibility visibility = ItemVisibility.family,
    Set<String> sharedWith = const {},
  }) async {
    final id = newUuidV4();
    final ownerId = _uid;
    final draft = BoardTask(
      id: id,
      familyId: familyId,
      dueDate: dueDate,
      text: text,
      meta: meta,
      assigneeId: assigneeId,
      ownerId: ownerId,
      visibility: visibility,
    );

    await _db.from('tasks').insert({...draft.toMap(forInsert: true), 'id': id});

    final members = _effectiveShares(visibility, sharedWith, ownerId);
    if (members.isNotEmpty) await _writeShares(id, familyId, members);

    final row = await _db.from('tasks').select(_columns).eq('id', id).single();
    return BoardTask.fromMap(row, sharedWith: members.toList());
  }

  Future<BoardTask> updateTask(
    BoardTask task, {
    required String text,
    String? meta,
    DateTime? dueDate,
    bool clearDueDate = false,
    String? assigneeId,
    bool clearAssignee = false,
    ItemVisibility? visibility,
    Set<String>? sharedWith,
  }) async {
    final patch = <String, dynamic>{
      'text': text,
      'meta': meta,
      'assignee_id': clearAssignee ? null : assigneeId,
      // Three states, not two: leave the date alone, set it, or take it away.
      // Without [clearDueDate] a null `dueDate` could only ever mean the first,
      // and "Kein Datum" in the sheet would silently do nothing.
      if (clearDueDate) 'due_date': null else if (dueDate != null) 'due_date': formatDueDate(dueDate),
      if (visibility != null && visibility != task.visibility) 'visibility': visibility.name,
    };

    final row = await _db.from('tasks').update(patch).eq('id', task.id).select(_columns).single();
    final saved = BoardTask.fromMap(row);

    // Shares are the owner's to change, so a member editing someone else's task
    // leaves them alone.
    if (sharedWith == null || saved.ownerId != AporahSupabase.userId) {
      return saved.copyWith(sharedWith: task.sharedWith);
    }

    final members = _effectiveShares(saved.visibility, sharedWith, saved.ownerId);
    await _db.from('task_shares').delete().eq('task_id', saved.id);
    if (members.isNotEmpty) await _writeShares(saved.id, saved.familyId, members);

    return saved.copyWith(sharedWith: members.toList());
  }

  /// Ticking off writes all three columns together: who ticked it and when is
  /// what a shared Board renders, and a `done` without them is a row that
  /// cannot say who did the job.
  Future<BoardTask> setDone(String taskId, bool done) async {
    final row = await _db
        .from('tasks')
        .update({
          'done': done,
          'done_by': done ? _uid : null,
          'done_at': done ? DateTime.now().toUtc().toIso8601String() : null,
        })
        .eq('id', taskId)
        .select(_columns)
        .single();
    return BoardTask.fromMap(row);
  }

  Future<void> deleteTask(String id) async {
    await _db.from('tasks').delete().eq('id', id);
  }

  /// "Erledigte löschen". One statement for the batch, but `tasks_delete` still
  /// applies per row, so somebody else's task survives a clear-out run by a
  /// non-admin. Returns the ids that actually went away.
  Future<Set<String>> clearDone(Iterable<String> taskIds) async {
    final ids = taskIds.toList();
    if (ids.isEmpty) return const {};
    final rows = await _db.from('tasks').delete().inFilter('id', ids).select('id');
    return {for (final r in rows) r['id'] as String};
  }

  Set<String> _effectiveShares(ItemVisibility visibility, Set<String> sharedWith, String ownerId) {
    if (visibility != ItemVisibility.custom) return const {};
    return {...sharedWith}..remove(ownerId);
  }

  Future<void> _writeShares(String taskId, String familyId, Set<String> userIds) async {
    await _db.from('task_shares').insert([
      for (final userId in userIds) {'task_id': taskId, 'family_id': familyId, 'user_id': userId},
    ]);
  }
}
