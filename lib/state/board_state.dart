import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/board_data.dart';
import '../data/repositories/board_repository.dart';
import '../models/task.dart';
import '../models/visibility.dart';
import '../services/supabase.dart';
import 'auth_state.dart';
import 'family_state.dart';

/// Everything the Board renders, and nothing it doesn't.
///
/// The old overlay maps (`done`, `extra`, `cleared`) are gone: they existed
/// because the tasks were `const` seed data that could not be changed in place,
/// and over a server they would be a second source of truth that the next
/// reload silently overrules. `done` is now a column on the task.
class BoardState {
  /// Midnight-normalised (see [boardDay]) so it can be compared and used as a
  /// map key.
  final DateTime selectedDay;

  /// Day → its tasks, as loaded for the window around [selectedDay].
  final Map<DateTime, List<BoardTask>> tasksByDay;

  /// The create/edit sheet's draft answers. `visibility` + `sharedWith` say who
  /// may *see* it; `assigneeId` says who is meant to *do* it. Two questions, and
  /// the old single `who` string could only answer one of them at a time.
  final ItemVisibility newVisibility;
  final Set<String> newSharedWith;
  final String? newAssigneeId;

  /// Task the user just checked off or undid, or `''` — lets the section it
  /// landed in animate that one row in (see `CheckOffArrival`) and leave the
  /// rest at rest. Pass `''` to clear it.
  final String justMoved;

  final bool loading;

  /// German, and safe to render verbatim.
  final String? error;

  BoardState({
    DateTime? selectedDay,
    this.tasksByDay = const {},
    this.newVisibility = ItemVisibility.family,
    this.newSharedWith = const {},
    this.newAssigneeId,
    this.justMoved = '',
    this.loading = true,
    this.error,
  }) : selectedDay = selectedDay ?? boardDay(DateTime.now());

  BoardState copyWith({
    DateTime? selectedDay,
    Map<DateTime, List<BoardTask>>? tasksByDay,
    ItemVisibility? newVisibility,
    Set<String>? newSharedWith,
    String? newAssigneeId,
    bool clearAssignee = false,
    String? justMoved,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return BoardState(
      selectedDay: selectedDay ?? this.selectedDay,
      tasksByDay: tasksByDay ?? this.tasksByDay,
      newVisibility: newVisibility ?? this.newVisibility,
      newSharedWith: newSharedWith ?? this.newSharedWith,
      newAssigneeId: clearAssignee ? null : (newAssigneeId ?? this.newAssigneeId),
      justMoved: justMoved ?? this.justMoved,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }

  List<BoardTask> tasksFor(DateTime day) => tasksByDay[boardDay(day)] ?? const [];

  bool get isEmpty => tasksByDay.isEmpty;
}

class BoardNotifier extends StateNotifier<BoardState> {
  BoardNotifier(this._repo, this._userId, this._familyId) : super(BoardState()) {
    if (_userId != null) load();
  }

  final BoardRepository _repo;
  final String? _userId;
  final String? _familyId;

  /// How far either side of the selected day is loaded. Five weeks each way
  /// covers a good deal of paging through the strip without a refetch, and is
  /// still a bounded query on a table that grows forever.
  static const _windowDays = 35;

  static const _tempPrefix = 'tmp:';
  static bool _isTemp(String id) => id.startsWith(_tempPrefix);
  static String _tempId() => '$_tempPrefix${DateTime.now().microsecondsSinceEpoch}';

  /// The window currently held, so paging the strip only refetches when it
  /// actually leaves what is loaded.
  DateTime? _from;
  DateTime? _to;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> load() async {
    if (_userId == null) {
      state = state.copyWith(loading: false);
      return;
    }
    final centre = state.selectedDay;
    final from = DateTime(centre.year, centre.month, centre.day - _windowDays);
    final to = DateTime(centre.year, centre.month, centre.day + _windowDays);

    state = state.copyWith(loading: true, clearError: true);
    try {
      final snapshot = await _repo.fetchRange(from, to);
      if (!mounted) return;
      _from = from;
      _to = to;
      state = state.copyWith(tasksByDay: snapshot.tasksByDay, loading: false);
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(loading: false, error: 'Aufgaben konnten nicht geladen werden.');
    }
  }

  void clearError() => state = state.copyWith(clearError: true);

  void _fail(String message) {
    if (mounted) state = state.copyWith(error: message);
  }

  // ---------------------------------------------------------------------------
  // Navigation and sheet drafts
  // ---------------------------------------------------------------------------

  void selectDay(DateTime day) {
    final selected = boardDay(day);
    state = state.copyWith(selectedDay: selected, justMoved: '');
    // Only when the strip has walked out of what is loaded — otherwise every
    // tap on a day would be a round trip.
    if (_from == null || _to == null || selected.isBefore(_from!) || selected.isAfter(_to!)) {
      load();
    }
  }

  void setVisibility(ItemVisibility visibility, Set<String> sharedWith) {
    state = state.copyWith(
      newVisibility: visibility,
      newSharedWith: visibility == ItemVisibility.custom ? sharedWith : const {},
    );
  }

  /// Who is meant to do it. Independent of [setVisibility]: assigning a task to
  /// Lea says nothing about who can see it.
  void setAssignee(String? userId) {
    state = userId == null
        ? state.copyWith(clearAssignee: true)
        : state.copyWith(newAssigneeId: userId);
  }

  /// Opens the sheet on a task's own answers, or on the defaults for a new one.
  void primeDraft(BoardTask? task) {
    state = state.copyWith(
      newVisibility: task?.visibility ?? ItemVisibility.family,
      newSharedWith: {...?task?.sharedWith},
      newAssigneeId: task?.assigneeId,
      clearAssignee: task?.assigneeId == null,
    );
  }

  // ---------------------------------------------------------------------------
  // Tasks
  // ---------------------------------------------------------------------------

  /// Files a task on the selected day, on screen first and on the server after.
  Future<void> addTask(String text, {String? meta}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final familyId = _familyId;
    if (familyId == null) {
      _fail('Dein Haushalt ist noch nicht geladen.');
      return;
    }

    final day = state.selectedDay;
    final optimistic = BoardTask(
      id: _tempId(),
      familyId: familyId,
      dueDate: day,
      text: trimmed,
      meta: meta,
      assigneeId: state.newAssigneeId,
      ownerId: _userId ?? '',
      visibility: state.newVisibility,
      sharedWith: state.newSharedWith.toList(),
    );
    _putTasks(day, [...state.tasksFor(day), optimistic]);

    try {
      final saved = await _repo.createTask(
        familyId: familyId,
        dueDate: day,
        text: trimmed,
        meta: meta,
        assigneeId: state.newAssigneeId,
        visibility: state.newVisibility,
        sharedWith: state.newSharedWith,
      );
      if (!mounted) return;
      _patchTask(day, optimistic.id, (_) => saved);
    } catch (_) {
      if (!mounted) return;
      _removeTaskLocally(day, optimistic.id);
      _fail('Die Aufgabe konnte nicht gespeichert werden.');
    }
  }

  /// Writes back what the edit sheet changed. An emptied text means "left it
  /// alone", the same rule the list and box rows follow.
  Future<void> updateTask(BoardTask task, {required String text, String? meta}) async {
    if (_isTemp(task.id)) return; // Still in flight; the reconcile would clobber it.

    final newText = text.trim().isEmpty ? task.text : text.trim();
    final newMeta = meta?.trim();

    _patchTask(
      task.dueDate,
      task.id,
      (t) => t.copyWith(
        text: newText,
        meta: newMeta,
        clearMeta: newMeta == null || newMeta.isEmpty,
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
        assigneeId: state.newAssigneeId,
        clearAssignee: state.newAssigneeId == null,
        visibility: state.newVisibility,
        sharedWith: state.newSharedWith,
      );
      if (!mounted) return;
      _patchTask(task.dueDate, task.id, (_) => saved);
    } catch (_) {
      if (!mounted) return;
      _patchTask(task.dueDate, task.id, (_) => task);
      _fail('Die Änderung konnte nicht gespeichert werden.');
    }
  }

  /// Ticks a task off, or undoes it.
  Future<void> toggle(BoardTask task) async {
    if (_isTemp(task.id)) return;

    final next = !task.done;
    _patchTask(
      task.dueDate,
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
      _patchTask(task.dueDate, task.id, (_) => saved);
    } catch (_) {
      if (!mounted) return;
      _patchTask(task.dueDate, task.id, (_) => task);
      _fail('Konnte nicht gespeichert werden.');
    }
  }

  /// "Erledigte löschen" for the selected day. Rows the database refused to
  /// delete (somebody else's task, cleared by a non-admin) come straight back
  /// rather than disappearing until the next reload.
  Future<void> clearDone() async {
    final day = state.selectedDay;
    final ids = [for (final t in state.tasksFor(day)) if (t.done && !_isTemp(t.id)) t.id];
    if (ids.isEmpty) return;

    final previous = state.tasksByDay;
    _removeTasksLocally(day, ids.toSet());

    try {
      final deleted = await _repo.clearDone(ids);
      if (!mounted) return;
      final refused = ids.toSet().difference(deleted);
      if (refused.isEmpty) return;
      state = state.copyWith(tasksByDay: previous);
      _removeTasksLocally(day, deleted);
      _fail('Nicht alle erledigten Aufgaben konnten gelöscht werden.');
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(tasksByDay: previous, error: 'Die erledigten Aufgaben konnten nicht gelöscht werden.');
    }
  }

  Future<void> deleteTask(BoardTask task) async {
    final previous = state.tasksByDay;
    _removeTaskLocally(task.dueDate, task.id);
    state = state.copyWith(justMoved: '');
    if (_isTemp(task.id)) return;

    try {
      await _repo.deleteTask(task.id);
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(tasksByDay: previous, error: 'Die Aufgabe konnte nicht gelöscht werden.');
    }
  }

  // ---------------------------------------------------------------------------
  // Bookkeeping
  // ---------------------------------------------------------------------------

  void _putTasks(DateTime day, List<BoardTask> tasks) {
    state = state.copyWith(tasksByDay: {...state.tasksByDay, boardDay(day): tasks});
  }

  void _patchTask(DateTime day, String taskId, BoardTask Function(BoardTask) patch) {
    final key = boardDay(day);
    final tasks = state.tasksByDay[key];
    if (tasks == null) return;
    _putTasks(key, [for (final t in tasks) t.id == taskId ? patch(t) : t]);
  }

  void _removeTaskLocally(DateTime day, String taskId) {
    final key = boardDay(day);
    final tasks = state.tasksByDay[key];
    if (tasks == null) return;
    _putTasks(key, [for (final t in tasks) if (t.id != taskId) t]);
  }

  void _removeTasksLocally(DateTime day, Set<String> taskIds) {
    final key = boardDay(day);
    final tasks = state.tasksByDay[key];
    if (tasks == null) return;
    _putTasks(key, [for (final t in tasks) if (!taskIds.contains(t.id)) t]);
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
