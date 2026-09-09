import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The bottom navigation's own state: chrome, not domain state, which is why
/// it sits on its own rather than inside `calendarProvider`. The bar belongs to
/// `AppShell`, the scroll that collapses it happens two screens down, and no
/// repository ever hears about it.
@immutable
class NavBarState {
  /// Whether the bar is collapsed to a single button. Only Kalender drives it
  /// today — the shell also gates on the tab index, so a stale `true` can never
  /// follow the user to another tab.
  final bool compact;

  /// The height UIKit laid the native bar out at, once it has one. Published
  /// here rather than kept in the shell because Kalender's "Heute" button has
  /// to hang off the same centre line as the compacted nav button, and it is
  /// built in a different subtree. Null off iOS and until the bar is measured;
  /// `navRowBottom` handles both.
  final double? barHeight;

  const NavBarState({this.compact = false, this.barHeight});

  NavBarState copyWith({bool? compact, double? barHeight}) =>
      NavBarState(compact: compact ?? this.compact, barHeight: barHeight ?? this.barHeight);
}

class NavBarNotifier extends StateNotifier<NavBarState> {
  NavBarNotifier() : super(const NavBarState());

  /// Called from a scroll listener on every frame of a downward flick, so it
  /// must stay cheap and idempotent — the guard is what keeps it from
  /// rebuilding the shell sixty times a second.
  void compact() {
    if (!state.compact) state = state.copyWith(compact: true);
  }

  void expand() {
    if (state.compact) state = state.copyWith(compact: false);
  }

  void setBarHeight(double height) {
    if (state.barHeight != height) state = state.copyWith(barHeight: height);
  }
}

final navBarProvider = StateNotifierProvider<NavBarNotifier, NavBarState>((ref) => NavBarNotifier());

// ---------------------------------------------------------------------------
// Jumping from one tab to another
// ---------------------------------------------------------------------------

/// Where each screen sits in the shell's `IndexedStack`, by name.
///
/// The shell is a single stack of five always-mounted screens switched by index
/// — there is no `go_router` and no named route to address one with (see
/// CLAUDE.md), so an index *is* the address. It was a private constant in
/// `main.dart` while Kalender's collapsing nav bar was the only thing that
/// needed to know one; a task that points back at its appointment needs a name
/// for the tab it is pointing at.
const int calendarTabIndex = 1;
const int listsTabIndex = 2;
const int boardTabIndex = 3;

/// One tab asking the shell to show another, and telling it what to open there.
///
/// This is what makes a link a link rather than a badge: tapping the calendar
/// icon on a task has to leave Board, land on Kalender, and arrive at the day
/// the appointment is on. Only the shell can do the first part and only Kalender
/// can do the last, so the request travels between them as state.
///
/// **Consumed once.** [seq] increments on every request so that asking for the
/// same destination twice still fires — without it, opening a list, going back
/// and tapping the same link again would set an identical value and no listener
/// would run.
@immutable
class TabJump {
  final int tab;

  /// Listen: the list to open in detail view.
  final String? listId;

  /// Board: the task whose sheet to open.
  final String? taskId;

  /// Kalender: the day to select, and the event to open there if it happens to
  /// be in the loaded window. The day is what always works — the event may be
  /// months out, where nothing is loaded and landing on the date is the honest
  /// best answer.
  final DateTime? day;
  final String? eventCalendarId;
  final String? eventUid;

  final int seq;

  const TabJump({
    required this.tab,
    required this.seq,
    this.listId,
    this.taskId,
    this.day,
    this.eventCalendarId,
    this.eventUid,
  });
}

class TabJumpNotifier extends StateNotifier<TabJump?> {
  TabJumpNotifier() : super(null);

  int _seq = 0;

  void toList(String listId) => state = TabJump(tab: listsTabIndex, seq: ++_seq, listId: listId);

  void toTask(String taskId) => state = TabJump(tab: boardTabIndex, seq: ++_seq, taskId: taskId);

  void toEvent({required String calendarId, required String uid, DateTime? day}) => state =
      TabJump(tab: calendarTabIndex, seq: ++_seq, day: day, eventCalendarId: calendarId, eventUid: uid);

  /// Called by whichever screen acted on it. The shell does the tab switch and
  /// leaves the payload alone, so a screen that is mid-transition still finds
  /// its instructions when its listener runs.
  void done() => state = null;
}

final tabJumpProvider = StateNotifierProvider<TabJumpNotifier, TabJump?>((ref) => TabJumpNotifier());
