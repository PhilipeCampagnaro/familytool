import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/board_data.dart';
import '../data/repositories/tracker_repository.dart';
import '../data/tracker_data.dart';
import '../models/tracker.dart';
import '../models/visibility.dart';
import '../services/supabase.dart';
import 'auth_state.dart';
import 'family_state.dart';
import '../l10n/l10n.dart';

/// The Board's trackers, the days they were kept, and the rhythm the create
/// sheet is drafting.
///
/// The rhythm is the *only* draft field here. Who does it, who may see it and
/// the notes are asked identically of a task and a tracker, so they stay on
/// [BoardState] and one sheet answers them once — the type switch changes a
/// single row of that sheet, not the sheet.
class TrackerState {
  final List<Tracker> trackers;

  /// Tracker id -> the midnight-normalised days it was ticked, inside
  /// [trackerHistoryDays]. A day is present or it is not; there is no "missed"
  /// to store, because a miss is the absence of one of these on a day the
  /// rhythm scheduled.
  final Map<String, Set<DateTime>> checks;

  /// The create/edit sheet's rhythm.
  final TrackerSchedule newSchedule;

  final bool loading;

  /// German, and safe to render verbatim.
  final String? error;

  const TrackerState({
    this.trackers = const [],
    this.checks = const {},
    this.newSchedule = TrackerSchedule.daily,
    this.loading = true,
    this.error,
  });

  TrackerState copyWith({
    List<Tracker>? trackers,
    Map<String, Set<DateTime>>? checks,
    TrackerSchedule? newSchedule,
    bool? loading,
    String? error,
    bool clearError = false,
  }) => TrackerState(
    trackers: trackers ?? this.trackers,
    checks: checks ?? this.checks,
    newSchedule: newSchedule ?? this.newSchedule,
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
  );

  bool get isEmpty => trackers.isEmpty;

  Set<DateTime> checksFor(String trackerId) => checks[trackerId] ?? const <DateTime>{};

  bool isCheckedOn(String trackerId, DateTime day) => checksFor(trackerId).contains(boardDay(day));

  /// The trackers a person chip lets through, on the same rule the tasks follow:
  /// a member chip narrows to what is **assigned** to them, and everything else
  /// leaves the trackers alone.
  List<Tracker> visibleTrackers(String? personFilter) {
    if (personFilter == null || !personFilter.startsWith('member:')) return trackers;
    final memberId = personFilter.substring('member:'.length);
    return [for (final t in trackers) if (t.assigneeId == memberId) t];
  }

  /// What the Board's tracker card shows today.
  List<Tracker> dueOn(DateTime today, {String? personFilter}) =>
      trackersOn(visibleTrackers(personFilter), today);

  /// What the header grid draws. Day-based trackers only — see
  /// [trackerDayTallies].
  Map<DateTime, BoardDayTally> dayTallies(DateTime today, {String? personFilter}) =>
      trackerDayTallies(visibleTrackers(personFilter), checks, today);

  int streakOf(Tracker tracker, DateTime today) =>
      trackerStreak(tracker, checksFor(tracker.id), today);

  int weekDoneFor(Tracker tracker, DateTime day) => trackerWeekDone(checksFor(tracker.id), day);
}

class TrackerNotifier extends StateNotifier<TrackerState> {
  TrackerNotifier(this._repo, this._userId, this._familyId) : super(const TrackerState()) {
    if (_userId != null) load();
  }

  final TrackerRepository _repo;
  final String? _userId;
  final String? _familyId;

  static const _tempPrefix = 'tmp:';
  static bool _isTemp(String id) => id.startsWith(_tempPrefix);
  static String _tempId() => '$_tempPrefix${DateTime.now().microsecondsSinceEpoch}';

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> load() async {
    if (_userId == null) {
      state = state.copyWith(loading: false);
      return;
    }

    state = state.copyWith(loading: true, clearError: true);
    try {
      final trackers = await _repo.fetchTrackers();
      // Skipped entirely when there is nothing to have checks for — a household
      // that keeps no trackers should not pay for a second round trip on every
      // cold start.
      final checks = trackers.isEmpty ? <String, Set<DateTime>>{} : await _repo.fetchChecks();
      if (!mounted) return;
      state = state.copyWith(trackers: trackers, checks: checks, loading: false);
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(loading: false, error: L.s.trackersLoadFailed);
    }
  }

  void clearError() => state = state.copyWith(clearError: true);

  void _fail(String message) {
    if (mounted) state = state.copyWith(error: message);
  }

  // ---------------------------------------------------------------------------
  // Sheet draft
  // ---------------------------------------------------------------------------

  void setSchedule(TrackerSchedule schedule) => state = state.copyWith(newSchedule: schedule);

  /// Opens the sheet on a tracker's own rhythm, or on the default for a new one.
  ///
  /// Daily is the default because it is the rhythm that needs no second answer:
  /// somebody who wants Montag and Donnerstag is going into the picker anyway,
  /// and somebody who does not gets a working tracker without opening it.
  void primeDraft(Tracker? tracker) =>
      state = state.copyWith(newSchedule: tracker?.schedule ?? TrackerSchedule.daily);

  // ---------------------------------------------------------------------------
  // Trackers
  // ---------------------------------------------------------------------------

  /// True only once the server has it — the row appears optimistically either
  /// way, but the confirmation chip is a claim about the *write*.
  Future<bool> addTracker(
    String text, {
    String? meta,
    String? iconKey,
    String? assigneeId,
    ItemVisibility visibility = ItemVisibility.family,
    Set<String> sharedWith = const {},
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    final familyId = _familyId;
    if (familyId == null) {
      _fail(L.s.householdNotLoaded);
      return false;
    }

    final schedule = state.newSchedule;
    // Every chip cleared. The database would reject it, so the sheet is told
    // first rather than being allowed to save into an error.
    if (!schedule.isComplete) {
      _fail(L.s.pickAtLeastOneDay);
      return false;
    }

    final optimistic = Tracker(
      id: _tempId(),
      familyId: familyId,
      text: trimmed,
      meta: meta,
      iconKey: iconKey,
      schedule: schedule,
      assigneeId: assigneeId,
      startsOn: boardDay(DateTime.now()),
      ownerId: _userId ?? '',
      visibility: visibility,
      sharedWith: sharedWith.toList(),
      createdAt: DateTime.now(),
    );
    state = state.copyWith(trackers: [...state.trackers, optimistic]);

    try {
      final saved = await _repo.createTracker(
        familyId: familyId,
        text: trimmed,
        schedule: schedule,
        meta: meta,
        iconKey: iconKey,
        assigneeId: assigneeId,
        visibility: visibility,
        sharedWith: sharedWith,
      );
      if (!mounted) return false;
      _patchTracker(optimistic.id, (_) => saved);
      return true;
    } catch (_) {
      if (!mounted) return false;
      _removeTracker(optimistic.id);
      _fail(L.s.trackerSaveFailed);
      return false;
    }
  }

  /// Writes back what the edit sheet changed. An emptied text means "left it
  /// alone", the same rule every other row follows.
  Future<bool> updateTracker(
    Tracker tracker, {
    required String text,
    String? meta,
    String? iconKey,
    String? assigneeId,
    ItemVisibility? visibility,
    Set<String>? sharedWith,
  }) async {
    if (_isTemp(tracker.id)) return false; // Still in flight; the reconcile would clobber it.

    final newText = text.trim().isEmpty ? tracker.text : text.trim();
    final newMeta = meta?.trim();
    final schedule = state.newSchedule;
    if (!schedule.isComplete) {
      _fail(L.s.pickAtLeastOneDay);
      return false;
    }

    final previous = state.trackers;
    _patchTracker(
      tracker.id,
      (t) => t.copyWith(
        text: newText,
        meta: newMeta,
        clearMeta: newMeta == null || newMeta.isEmpty,
        iconKey: iconKey,
        schedule: schedule,
        assigneeId: assigneeId,
        clearAssignee: assigneeId == null,
        visibility: visibility,
        sharedWith: sharedWith?.toList(),
      ),
    );

    try {
      final saved = await _repo.updateTracker(
        tracker,
        text: newText,
        meta: newMeta == null || newMeta.isEmpty ? null : newMeta,
        iconKey: iconKey,
        schedule: schedule,
        assigneeId: assigneeId,
        clearAssignee: assigneeId == null,
        visibility: visibility,
        sharedWith: sharedWith,
      );
      if (!mounted) return false;
      _patchTracker(tracker.id, (_) => saved);
      return true;
    } catch (_) {
      if (!mounted) return false;
      state = state.copyWith(trackers: previous, error: L.s.trackerSaveFailed);
      return false;
    }
  }

  /// Ticks today (or any loaded day) off, or takes the tick back.
  ///
  /// Optimistic, like every other check-off on the Board: the square darkens
  /// under the thumb and the write follows. A refused write puts the day back
  /// exactly as it was rather than leaving a tick the server never accepted.
  Future<void> toggleCheck(Tracker tracker, DateTime day) async {
    if (_isTemp(tracker.id)) return;
    final at = boardDay(day);
    final was = state.isCheckedOn(tracker.id, at);

    _setCheck(tracker.id, at, !was);
    try {
      await _repo.setChecked(tracker.id, tracker.familyId, at, !was);
    } catch (_) {
      if (!mounted) return;
      _setCheck(tracker.id, at, was);
      _fail(L.s.trackerCheckFailed);
    }
  }

  Future<bool> deleteTracker(Tracker tracker) async {
    final previousTrackers = state.trackers;
    final previousChecks = state.checks;
    _removeTracker(tracker.id);
    if (_isTemp(tracker.id)) return true;

    try {
      await _repo.deleteTracker(tracker.id);
      return true;
    } catch (_) {
      if (!mounted) return false;
      state = state.copyWith(
        trackers: previousTrackers,
        checks: previousChecks,
        error: L.s.trackerDeleteFailed,
      );
      return false;
    }
  }

  /// Puts a deleted tracker back — the chip's "Rückgängig".
  ///
  /// A re-insert under a new id, like the other restores, and **the record does
  /// not come back**: `on delete cascade` took the checks with the row, and
  /// re-inserting days somebody may not have kept would be inventing history.
  /// The rhythm, the notes, who it is for and who may see it all return; the
  /// streak starts again, which is the honest outcome of having deleted it.
  Future<bool> restoreTracker(Tracker tracker) async {
    final familyId = _familyId;
    if (familyId == null) {
      _fail(L.s.householdNotLoaded);
      return false;
    }

    try {
      final saved = await _repo.createTracker(
        familyId: familyId,
        text: tracker.text,
        schedule: tracker.schedule,
        meta: tracker.meta,
        iconKey: tracker.iconKey,
        assigneeId: tracker.assigneeId,
        startsOn: tracker.startsOn,
        visibility: tracker.visibility,
        sharedWith: tracker.sharedWith.toSet(),
      );
      if (!mounted) return false;
      state = state.copyWith(trackers: [...state.trackers, saved]);
      return true;
    } catch (_) {
      _fail(L.s.trackerRestoreFailed);
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Bookkeeping
  // ---------------------------------------------------------------------------

  void _patchTracker(String id, Tracker Function(Tracker) patch) {
    state = state.copyWith(
      trackers: [for (final t in state.trackers) t.id == id ? patch(t) : t],
    );
  }

  void _removeTracker(String id) {
    state = state.copyWith(
      trackers: [for (final t in state.trackers) if (t.id != id) t],
      checks: {...state.checks}..remove(id),
    );
  }

  void _setCheck(String trackerId, DateTime day, bool checked) {
    final days = {...state.checksFor(trackerId)};
    if (checked) {
      days.add(day);
    } else {
      days.remove(day);
    }
    state = state.copyWith(checks: {...state.checks, trackerId: days});
  }
}

final trackerRepositoryProvider = Provider<TrackerRepository>((ref) => TrackerRepository(AporahSupabase.client));

/// Rebuilt when the signed-in user or their household changes, and only then.
final trackerProvider = StateNotifierProvider<TrackerNotifier, TrackerState>((ref) {
  return TrackerNotifier(
    ref.watch(trackerRepositoryProvider),
    ref.watch(currentUserIdProvider),
    ref.watch(familyProvider.select((s) => s.household?.id)),
  );
});
