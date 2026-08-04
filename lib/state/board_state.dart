import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/board_data.dart';
import '../data/repositories/board_repository.dart';
import '../models/task.dart';
import '../models/visibility.dart';
import '../services/supabase.dart';
import 'auth_state.dart';
import 'family_state.dart';
import '../l10n/l10n.dart';

/// Everything the Board renders, and nothing it doesn't.
///
/// The old overlay maps (`done`, `extra`, `cleared`) are gone: they existed
/// because the tasks were `const` seed data that could not be changed in place,
/// and over a server they would be a second source of truth that the next
/// reload silently overrules. `done` is now a column on the task.
class BoardState {
  /// Every task the Board renders, flat and unsorted — [boardGroups] buckets
  /// them into Überfällig / Heute / Morgen / … at render time.
  ///
  /// A flat list rather than the old `Map<DateTime, List<BoardTask>>`: keying by
  /// day made an undated task unrepresentable, and the map was only ever a map
  /// because a week strip picked one key out of it.
  final List<BoardTask> tasks;

  /// The create/edit sheet's draft answers. `visibility` + `sharedWith` say who
  /// may *see* it; `assigneeId` says who is meant to *do* it. Two questions, and
  /// the old single `who` string could only answer one of them at a time.
  ///
  /// The sheet asks them in two deliberately different shapes — a "Zuständig"
  /// field row for this one, the shared avatar picker for the audience. They
  /// were two stacked avatar rows once and read as the same question asked
  /// twice.
  final ItemVisibility newVisibility;
  final Set<String> newSharedWith;
  final String? newAssigneeId;

  /// The draft's due date, and null is a real answer — "Ohne Datum" is where a
  /// new task starts. It used to be `selectedDay`, i.e. whatever the week strip
  /// happened to be on, which meant the sheet could not ask the question at all.
  final DateTime? newDueDate;

  /// Task the user just checked off or undid, or `''` — lets the section it
  /// landed in animate that one row in (see `CheckOffArrival`) and leave the
  /// rest at rest. Pass `''` to clear it.
  final String justMoved;

  final bool loading;

  /// German, and safe to render verbatim.
  final String? error;

  const BoardState({
    this.tasks = const [],
    this.newVisibility = ItemVisibility.family,
    this.newSharedWith = const {},
    this.newAssigneeId,
    this.newDueDate,
    this.justMoved = '',
    this.loading = true,
    this.error,
  });

  BoardState copyWith({
    List<BoardTask>? tasks,
    ItemVisibility? newVisibility,
    Set<String>? newSharedWith,
    String? newAssigneeId,
    bool clearAssignee = false,
    DateTime? newDueDate,
    bool clearDueDate = false,
    String? justMoved,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return BoardState(
      tasks: tasks ?? this.tasks,
      newVisibility: newVisibility ?? this.newVisibility,
      newSharedWith: newSharedWith ?? this.newSharedWith,
      newAssigneeId: clearAssignee ? null : (newAssigneeId ?? this.newAssigneeId),
      newDueDate: clearDueDate ? null : (newDueDate ?? this.newDueDate),
      justMoved: justMoved ?? this.justMoved,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }

  /// The open tasks, in the sections the screen draws. Empty sections are
  /// already gone.
  List<BoardGroup> groupsOn(DateTime today) => boardGroups(tasks, today);

  /// Recently finished tasks, newest first — the "Erledigt" card. How far back
  /// "recently" reaches is [BoardRepository.fetchBoard]'s call, not the UI's.
  List<BoardTask> get doneTasks {
    final done = [for (final t in tasks) if (t.done) t];
    done.sort((a, b) => (b.doneAt ?? DateTime(0)).compareTo(a.doneAt ?? DateTime(0)));
    return done;
  }

  /// What the header's progress bar reports on: everything due today, done or
  /// not, plus anything overdue that is still open. Today is the one day the
  /// Board still singles out — it is what somebody opens the app to see — and an
  /// overdue task is today's problem rather than history.
  ///
  /// A task that was overdue and *is* done stays out: it would only ever pad
  /// both halves of "3 von 8 erledigt" with work nobody has to think about.
  List<BoardTask> onDeck(DateTime today) => [
    for (final t in tasks)
      if (t.dueDate case final due?)
        if (boardDay(due) == today || (boardDay(due).isBefore(today) && !t.done)) t,
  ];

  bool get isEmpty => tasks.isEmpty;
}

class BoardNotifier extends StateNotifier<BoardState> {
  BoardNotifier(this._repo, this._userId, this._familyId) : super(const BoardState()) {
    if (_userId != null) load();
  }

  final BoardRepository _repo;
  final String? _userId;
  final String? _familyId;

  static const _tempPrefix = 'tmp:';
  static bool _isTemp(String id) => id.startsWith(_tempPrefix);
  static String _tempId() => '$_tempPrefix${DateTime.now().microsecondsSinceEpoch}';

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// One shot, and no window to page: the repository decides what is worth
  /// loading (every open task, plus the recently finished ones). The date-window
  /// refetch that used to fire when the week strip walked out of range went with
  /// the strip.
  Future<void> load() async {
    if (_userId == null) {
      state = state.copyWith(loading: false);
      return;
    }

    state = state.copyWith(loading: true, clearError: true);
    try {
      final tasks = await _repo.fetchBoard();
      if (!mounted) return;
      state = state.copyWith(tasks: tasks, loading: false);
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(loading: false, error: L.s.tasksLoadFailed);
    }
  }

  void clearError() => state = state.copyWith(clearError: true);

  void _fail(String message) {
    if (mounted) state = state.copyWith(error: message);
  }

  // ---------------------------------------------------------------------------
  // Navigation and sheet drafts
  // ---------------------------------------------------------------------------

  /// The draft's due date. `null` clears it — "Kein Datum" in the picker, and
  /// the state every new task starts in.
  void setDueDate(DateTime? day) {
    state = state.copyWith(
      newDueDate: day == null ? null : boardDay(day),
      clearDueDate: day == null,
    );
  }

  void setVisibility(ItemVisibility visibility, Set<String> sharedWith) {
    state = state.copyWith(
      newVisibility: visibility,
      newSharedWith: visibility == ItemVisibility.custom ? sharedWith : const {},
    );
  }

  /// Who is meant to do it. Independent of [setVisibility]: assigning a task to
  /// Lea says nothing about who can see it.
  ///
  /// Takes a member, never `null`: the sheet dropped its "Niemand" option, so
  /// there is no longer a way to un-assign a task from the UI. The column stays
  /// nullable for the rows written before that rule and for
  /// `on delete set null` when a member's account goes away.
  void setAssignee(String userId) => state = state.copyWith(newAssigneeId: userId);

  /// Opens the sheet on a task's own answers, or on the defaults for a new one.
  ///
  /// [initialDue] is the date a *new* task starts on, which is null — undated —
  /// unless the sheet was opened from a section header that names a day. An
  /// existing task always brings its own date, whatever it is.
  void primeDraft(BoardTask? task, {DateTime? initialDue}) {
    // Somebody is always on the hook — a task nobody is responsible for is a
    // task nobody does. A new one starts on you; an older one carrying no
    // `assignee_id` falls back to whoever created it rather than to whoever
    // happens to be opening the sheet.
    final owner = (task?.ownerId ?? '').isEmpty ? null : task!.ownerId;
    final assignee = task?.assigneeId ?? owner ?? _userId;
    final due = task == null ? initialDue : task.dueDate;
    state = state.copyWith(
      newVisibility: task?.visibility ?? ItemVisibility.family,
      newSharedWith: {...?task?.sharedWith},
      newAssigneeId: assignee,
      clearAssignee: assignee == null,
      newDueDate: due,
      clearDueDate: due == null,
    );
  }

  // ---------------------------------------------------------------------------
  // Tasks
  // ---------------------------------------------------------------------------

  /// Files a task on the draft's date — or on no date at all — on screen first
  /// and on the server after.
  ///
  /// True only once the server has it: the row appears optimistically either
  /// way, but the confirmation chip is a claim about the *write*, and a rolled
  /// back row gets the error snack instead.
  Future<bool> addTask(String text, {String? meta}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    final familyId = _familyId;
    if (familyId == null) {
      _fail(L.s.householdNotLoaded);
      return false;
    }

    final due = state.newDueDate;
    final optimistic = BoardTask(
      id: _tempId(),
      familyId: familyId,
      dueDate: due,
      text: trimmed,
      meta: meta,
      assigneeId: state.newAssigneeId,
      ownerId: _userId ?? '',
      visibility: state.newVisibility,
      sharedWith: state.newSharedWith.toList(),
      // Only so the optimistic row sorts where the saved one will — every other
      // timestamp on the model comes from the server.
      createdAt: DateTime.now(),
    );
    state = state.copyWith(tasks: [...state.tasks, optimistic], justMoved: optimistic.id);

    try {
      final saved = await _repo.createTask(
        familyId: familyId,
        dueDate: due,
        text: trimmed,
        meta: meta,
        assigneeId: state.newAssigneeId,
        visibility: state.newVisibility,
        sharedWith: state.newSharedWith,
      );
      if (!mounted) return false;
      _patchTask(optimistic.id, (_) => saved);
      state = state.copyWith(justMoved: saved.id);
      return true;
    } catch (_) {
      if (!mounted) return false;
      _removeTask(optimistic.id);
      _fail(L.s.taskSaveFailed);
      return false;
    }
  }

  /// Writes back what the edit sheet changed. An emptied text means "left it
  /// alone", the same rule the list and box rows follow.
  ///
  /// The date is not exempt from that: the sheet always submits the draft's
  /// answer, so moving a task to another section — or out of all of them, into
  /// "Ohne Datum" — happens here like any other edit.
  Future<bool> updateTask(BoardTask task, {required String text, String? meta}) async {
    if (_isTemp(task.id)) return false; // Still in flight; the reconcile would clobber it.

    final newText = text.trim().isEmpty ? task.text : text.trim();
    final newMeta = meta?.trim();
    final newDue = state.newDueDate;

    _patchTask(
      task.id,
      (t) => t.copyWith(
        text: newText,
        meta: newMeta,
        clearMeta: newMeta == null || newMeta.isEmpty,
        dueDate: newDue,
        clearDueDate: newDue == null,
        assigneeId: state.newAssigneeId,
        clearAssignee: state.newAssigneeId == null,
        visibility: state.newVisibility,
      ),
    );

    try {
      final saved = await _repo.updateTask(
        task,
        text: newText,
        meta: (newMeta == null || newMeta.isEmpty) ? null : newMeta,
        dueDate: newDue,
        clearDueDate: newDue == null,
        assigneeId: state.newAssigneeId,
        clearAssignee: state.newAssigneeId == null,
        visibility: state.newVisibility,
        sharedWith: state.newSharedWith,
      );
      if (!mounted) return false;
      _patchTask(task.id, (_) => saved);
      return true;
    } catch (_) {
      if (!mounted) return false;
      _patchTask(task.id, (_) => task);
      _fail(L.s.changeSaveFailed);
      return false;
    }
  }

  /// Ticks a task off, or undoes it.
  Future<void> toggle(BoardTask task) async {
    if (_isTemp(task.id)) return;

    final next = !task.done;
    _patchTask(
      task.id,
      (t) => t.copyWith(
        done: next,
        doneBy: next ? _userId : null,
        clearDoneBy: !next,
        doneAt: next ? DateTime.now() : null,
        clearDoneAt: !next,
      ),
    );
    state = state.copyWith(justMoved: task.id);

    try {
      final saved = await _repo.setDone(task.id, next);
      if (!mounted) return;
      _patchTask(task.id, (_) => saved);
    } catch (_) {
      if (!mounted) return;
      _patchTask(task.id, (_) => task);
      _fail(L.s.saveFailed);
    }
  }

  /// "Erledigte löschen" — the whole card, which is now every recently finished
  /// task rather than one day's worth. Rows the database refused to delete
  /// (somebody else's task, cleared by a non-admin) come straight back rather
  /// than disappearing until the next reload.
  Future<void> clearDone() async {
    final ids = [for (final t in state.tasks) if (t.done && !_isTemp(t.id)) t.id];
    if (ids.isEmpty) return;

    final previous = state.tasks;
    _removeTasks(ids.toSet());

    try {
      final deleted = await _repo.clearDone(ids);
      if (!mounted) return;
      final refused = ids.toSet().difference(deleted);
      if (refused.isEmpty) return;
      state = state.copyWith(tasks: previous);
      _removeTasks(deleted);
      _fail(L.s.someDoneTasksNotDeleted);
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(tasks: previous, error: L.s.doneTasksDeleteFailed);
    }
  }

  Future<bool> deleteTask(BoardTask task) async {
    final previous = state.tasks;
    _removeTask(task.id);
    state = state.copyWith(justMoved: '');
    // Never reached the server, so there is nothing to delete there — but the
    // row is gone, which is what the confirmation is about.
    if (_isTemp(task.id)) return true;

    try {
      await _repo.deleteTask(task.id);
      return true;
    } catch (_) {
      if (!mounted) return false;
      state = state.copyWith(tasks: previous, error: L.s.taskDeleteFailed);
      return false;
    }
  }

  /// Puts a deleted task back — the chip's "Rückgängig".
  ///
  /// A re-insert under a new id, like the list and box restores: the text, the
  /// date, who it was for, who may see it and whether it was already ticked off
  /// all come back; the id doesn't, so an external share link to this task
  /// stays dead.
  Future<bool> restoreTask(BoardTask task) async {
    final familyId = _familyId;
    if (familyId == null) {
      _fail(L.s.householdNotLoaded);
      return false;
    }

    try {
      var saved = await _repo.createTask(
        familyId: familyId,
        dueDate: task.dueDate,
        text: task.text,
        meta: task.meta,
        assigneeId: task.assigneeId,
        visibility: task.visibility,
        sharedWith: task.sharedWith.toSet(),
      );
      // `createTask` has no say over it, and a restored task landing in "Offen"
      // when it was ticked off would be a change, not an undo.
      if (task.done) saved = await _repo.setDone(saved.id, true);
      if (!mounted) return false;
      state = state.copyWith(tasks: [...state.tasks, saved], justMoved: saved.id);
      return true;
    } catch (_) {
      _fail(L.s.taskRestoreFailed);
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Bookkeeping
  // ---------------------------------------------------------------------------
  //
  // One flat list, so none of these have to be told which day a task is on any
  // more — which is what made them wrong for a task that is on none.

  void _patchTask(String taskId, BoardTask Function(BoardTask) patch) {
    state = state.copyWith(
      tasks: [for (final t in state.tasks) t.id == taskId ? patch(t) : t],
    );
  }

  void _removeTask(String taskId) {
    state = state.copyWith(tasks: [for (final t in state.tasks) if (t.id != taskId) t]);
  }

  void _removeTasks(Set<String> taskIds) {
    state = state.copyWith(tasks: [for (final t in state.tasks) if (!taskIds.contains(t.id)) t]);
  }
}

final boardRepositoryProvider = Provider<BoardRepository>((ref) => BoardRepository(AporahSupabase.client));

/// Rebuilt when the signed-in user or their household changes, and only then.
final boardProvider = StateNotifierProvider<BoardNotifier, BoardState>((ref) {
  return BoardNotifier(
    ref.watch(boardRepositoryProvider),
    ref.watch(currentUserIdProvider),
    ref.watch(familyProvider.select((s) => s.household?.id)),
  );
});
