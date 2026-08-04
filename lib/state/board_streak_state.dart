import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/board_data.dart';
import '../models/task.dart';
import '../services/board_streak_cache.dart';
import 'board_state.dart';

/// The Board header's day tracker: one tally per past day, merged from the
/// tasks currently loaded and the on-device ledger behind them.
class BoardStreakState {
  /// Midnight-normalised day -> that day's tally. Nothing in here is in the
  /// future; see [boardDayTallies].
  final Map<DateTime, BoardDayTally> days;

  const BoardStreakState({this.days = const {}});

  BoardDayTally on(DateTime day) => days[day] ?? const BoardDayTally();
}

class BoardStreakNotifier extends StateNotifier<BoardStreakState> {
  BoardStreakNotifier(this._cache) : super(const BoardStreakState()) {
    _restore();
  }

  final BoardStreakCache _cache;

  /// Ticking a task off changes today's square, and a family clearing a morning's
  /// worth of tasks would otherwise be one file write per tap. The last write
  /// within the window is the only one that matters, so they collapse into it.
  static const _persistDelay = Duration(seconds: 2);

  Timer? _save;
  bool _restored = false;
  bool _dirty = false;

  /// Reads the ledger and folds it under whatever the Board has already
  /// reported. [record] can and does run first — `boardProvider` may already
  /// hold tasks by the time this file comes back — which is why the two sides
  /// go through the same [_merged] rather than one overwriting the other.
  Future<void> _restore() async {
    final stored = <DateTime, BoardDayTally>{};
    for (final entry in (await _cache.read()).entries) {
      final day = BoardStreakCache.parseDayKey(entry.key);
      if (day == null) continue;
      stored[day] = BoardDayTally(done: entry.value[0], planned: entry.value[1]);
    }

    if (!mounted) return;
    _restored = true;
    state = BoardStreakState(days: _merged(stored, state.days, boardDay(DateTime.now())));
    if (_dirty) _schedulePersist();
  }

  /// Folds what the Board is currently showing into the record.
  ///
  /// Called from [boardStreakProvider]'s listener rather than from the screen:
  /// a widget may not write to a provider while it is building, and the strip
  /// has to learn about a checked-off task at the moment the Board does.
  void record(List<BoardTask> tasks, DateTime today) {
    final live = boardDayTallies(tasks, today);
    final merged = _merged(state.days, live, today);
    if (_sameDays(merged, state.days)) return;
    state = BoardStreakState(days: merged);
    _dirty = true;
    _schedulePersist();
  }

  /// **Today is live; every day before it only ever improves.**
  ///
  /// Today is whatever the Board says, full stop — it is being edited right now,
  /// and un-ticking a task has to darken its square again.
  ///
  /// A past day is history, and the only two things that ever happen to the rows
  /// behind it *lose* information: they age out of the fourteen-day done window,
  /// or "Erledigte löschen" deletes them. Either one would turn a finished day
  /// into an empty or a failed one if the live count simply won. So the larger
  /// of the two counts survives, which means a day can still be corrected upward
  /// — adding a task dated last Tuesday raises that Tuesday's `planned` — while
  /// no amount of tidying up can quietly erase a day somebody actually finished.
  /// The cost is that un-ticking a task due last week leaves its square as it
  /// was, which is a fair trade for a record that survives the delete button.
  static Map<DateTime, BoardDayTally> _merged(
    Map<DateTime, BoardDayTally> base,
    Map<DateTime, BoardDayTally> live,
    DateTime today,
  ) {
    final merged = <DateTime, BoardDayTally>{...base};
    for (final entry in live.entries) {
      final day = entry.key;
      final fresh = entry.value;
      final known = merged[day];
      if (known == null || day == today) {
        merged[day] = fresh;
        continue;
      }
      final planned = known.planned > fresh.planned ? known.planned : fresh.planned;
      final done = known.done > fresh.done ? known.done : fresh.done;
      merged[day] = BoardDayTally(done: done > planned ? planned : done, planned: planned);
    }
    return merged;
  }

  /// A rebuild of the Board that changed nothing about any day must not cost a
  /// state update — the strip would repaint on every unrelated task edit.
  static bool _sameDays(Map<DateTime, BoardDayTally> a, Map<DateTime, BoardDayTally> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null || other.done != entry.value.done || other.planned != entry.value.planned) {
        return false;
      }
    }
    return true;
  }

  void _schedulePersist() {
    // Nothing is written before the file has been read, or the first two
    // seconds of the app's life would overwrite the whole history with the
    // fortnight that happened to be loaded.
    if (!_restored) return;
    _save?.cancel();
    _save = Timer(_persistDelay, _persist);
  }

  Future<void> _persist() async {
    _dirty = false;
    await _cache.write(_encode(state.days));
  }

  static Map<String, List<int>> _encode(Map<DateTime, BoardDayTally> days) => {
    for (final entry in days.entries)
      BoardStreakCache.dayKey(entry.key): [entry.value.done, entry.value.planned],
  };

  @override
  void dispose() {
    _save?.cancel();
    // Signing out or a hot restart lands here with a debounce still pending;
    // the day that was in flight is written out rather than dropped.
    final pending = _dirty && _restored ? _encode(state.days) : null;
    if (pending != null) unawaited(_cache.write(pending));
    super.dispose();
  }
}

final boardStreakCacheProvider = Provider<BoardStreakCache>((ref) => BoardStreakCache());

/// Fed by [boardProvider], not by the screen. The strip only has to watch this.
final boardStreakProvider = StateNotifierProvider<BoardStreakNotifier, BoardStreakState>((ref) {
  final notifier = BoardStreakNotifier(ref.watch(boardStreakCacheProvider));
  ref.listen<BoardState>(
    boardProvider,
    (_, next) {
      // A load that hasn't landed yet has no days to report, and recording its
      // empty task list would tell the ledger the last two weeks were blank.
      if (next.loading) return;
      notifier.record(next.tasks, boardDay(DateTime.now()));
    },
    fireImmediately: true,
  );
  return notifier;
});
