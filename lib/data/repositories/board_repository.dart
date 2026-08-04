import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/task.dart';
import '../../models/visibility.dart';
import '../../services/supabase.dart';
import 'list_repository.dart' show newUuidV4;

/// One round trip's worth of Board: every task the signed-in user may see,
/// grouped by the day it is due.
class BoardSnapshot {
  /// Midnight-normalised day → its tasks. The Board renders one day at a time
  /// and paints dots on the week strip, so both want this shape rather than a
  /// flat list.
  final Map<DateTime, List<BoardTask>> tasksByDay;

  const BoardSnapshot({required this.tasksByDay});

  static const empty = BoardSnapshot(tasksByDay: {});
}

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
    if (id == null) throw StateError('Kein angemeldeter Benutzer.');
    return id;
  }

  // -------------------------------------------------------------------------
  // Read
  // -------------------------------------------------------------------------

  /// Every task in a date window, which is what the Board actually shows.
  ///
  /// Bounded rather than "all of them": a household two years in has a few
  /// thousand tasks and looks at seven days of them. The window is generous —
  /// the strip only moves a week at a time — and re-fetched when it is left.
  Future<BoardSnapshot> fetchRange(DateTime from, DateTime to) async {
    final rows = await _db
        .from('tasks')
        .select(_columns)
        .gte('due_date', formatDueDate(from))
        .lte('due_date', formatDueDate(to))
        .order('due_date')
        .order('created_at');
    if (rows.isEmpty) return BoardSnapshot.empty;

    final ids = [for (final r in rows) r['id'] as String];
    final shareRows = await _db.from('task_shares').select('task_id, user_id').inFilter('task_id', ids);

    final sharedWith = <String, List<String>>{};
    for (final r in shareRows) {
      (sharedWith[r['task_id'] as String] ??= []).add(r['user_id'] as String);
    }

    final byDay = <DateTime, List<BoardTask>>{};
    for (final r in rows) {
      final task = BoardTask.fromMap(r, sharedWith: sharedWith[r['id'] as String] ?? const []);
      (byDay[task.dueDate] ??= []).add(task);
    }
    return BoardSnapshot(tasksByDay: byDay);
  }

  // -------------------------------------------------------------------------
  // Write
  // -------------------------------------------------------------------------

  /// **The insert carries no `.select()`** — see
  /// [ListRepository.createList] for why `insert … returning` fails the SELECT
  /// policy on every container table.
  Future<BoardTask> createTask({
    required String familyId,
    required DateTime dueDate,
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
    String? assigneeId,
    bool clearAssignee = false,
    ItemVisibility? visibility,
    Set<String>? sharedWith,
  }) async {
    final patch = <String, dynamic>{
      'text': text,
      'meta': meta,
      'assignee_id': clearAssignee ? null : assigneeId,
      if (dueDate != null) 'due_date': formatDueDate(dueDate),
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
