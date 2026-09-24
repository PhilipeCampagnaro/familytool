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

  /// Whether the bar is on screen at all — false while a sheet or a pushed
  /// page covers the shell (`occludedByRoute`), and before the shell exists.
  ///
  /// Read by the confirmation chip, which floats in the root overlay above
  /// every route and so cannot ask the shell's route itself. Parked above a
  /// bar that isn't there, it hung in the middle of the page, over the very
  /// buttons the next delete needed; with nothing to clear it drops to the
  /// bottom edge instead, and rises again when the bar comes back.
  final bool onScreen;

  const NavBarState({this.compact = false, this.barHeight, this.onScreen = false});

  NavBarState copyWith({bool? compact, double? barHeight, bool? onScreen}) => NavBarState(
    compact: compact ?? this.compact,
    barHeight: barHeight ?? this.barHeight,
    onScreen: onScreen ?? this.onScreen,
  );
}

class NavBarNotifier extends StateNotifier<NavBarState> {
  NavBarNotifier() : super(const NavBarState());

  /// Whether scrolling may collapse the bar. False from a tap on the compacted
  /// button until a finger next starts a drag.
  ///
  /// **Momentum outlives the finger.** A flick keeps the list gliding for
  /// seconds, and every frame of that glide is a downward scroll past the
  /// threshold — so without this, the tap expanded the bar and the next frame
  /// collapsed it again, and it took two or three taps to land one after the
  /// glide had died. A deliberate tap wins over leftover motion; a new drag is
  /// the reader asking again.
  bool _compactArmed = true;

  /// Called from a scroll listener on every frame of a downward flick, so it
  /// must stay cheap and idempotent — the guard is what keeps it from
  /// rebuilding the shell sixty times a second.
  void compact() {
    if (_compactArmed && !state.compact) state = state.copyWith(compact: true);
  }

  /// [holdOpen] is the tap on the compacted button — see [_compactArmed].
  void expand({bool holdOpen = false}) {
    if (holdOpen) _compactArmed = false;
    if (state.compact) state = state.copyWith(compact: false);
  }

  /// A finger started dragging a vertical list, so scrolling may collapse the
  /// bar again.
  void dragStarted() => _compactArmed = true;

  void setBarHeight(double height) {
    if (state.barHeight != height) state = state.copyWith(barHeight: height);
  }

  void setOnScreen(bool value) {
    if (state.onScreen != value) state = state.copyWith(onScreen: value);
  }
}

final navBarProvider = StateNotifierProvider<NavBarNotifier, NavBarState>((ref) => NavBarNotifier());

/// Which tab is actually on screen.
///
/// **The shell's `_index` is local state, and every screen is always mounted**
/// — the five live in one `IndexedStack` — so "is my screen the one being
/// looked at?" has no answer inside a screen. Anything that acts on arrival
/// rather than on a tap needs one: `RecipeLinkWatcher` offers a clipboard link
/// when the reader reaches Listen, and would otherwise offer it while they were
/// somewhere else entirely.
///
/// Published by the shell, read by screens. Not a way to *change* tab — that is
/// [tabJumpProvider], which the shell also listens to; a second writable copy
/// of the same number is how the two drift apart.
final activeTabProvider = StateProvider<int>((ref) => homeTabIndex);

// ---------------------------------------------------------------------------
// Jumping from one tab to another
// ---------------------------------------------------------------------------

/// Where each screen sits in the shell's `IndexedStack`, by name.
///
/// The shell is a single stack of five always-mounted screens switched by index
/// — there is no `go_router` and no named route to address one with (see
/// CLAUDE.md), so an index *is* the address. It was a private constant in
/// `main.dart` while Kalender's collapsing nav bar was the only thing that
/// needed to know one; a link that opens a list or a task in another tab needs
/// a name for the tab it is pointing at.
/// Home, which is the calendar's week view — see `StartScreen`. Named for the
/// same reason the others are: the shell has to know which tabs behave like the
/// calendar, and an index literal in `main.dart` said nothing about which.
const int homeTabIndex = 0;
const int calendarTabIndex = 1;
const int listsTabIndex = 2;
const int boardTabIndex = 3;

/// The tab that holds Boxen and Ausgaben. Which of the two it shows is
/// `moreProvider`'s business — see `MoreScreen`. **The only nav item whose tap
/// is not a tab change**: it puts up a menu first and the shell switches here
/// only once a row has been picked.
///
/// Where Ausgaben does not ship (`spendAvailable`) this slot is plain Boxen,
/// labelled and iconed as such, and it behaves like every other tab. The index
/// is the same either way, which is why the name stays.
const int moreTabIndex = 4;

/// One tab asking the shell to show another, and telling it what to open there.
///
/// It carries the two directions that really do change tab: an appointment's
/// sheet offering the list or the task hung off it. **Kalender is not one of
/// them.** The chip pointing the other way — from a task or a list back to the
/// appointment — opens the event's sheet where the reader already is, because
/// switching tab for it left people on a calendar they had not asked for; see
/// `showLinkedEventSheet`.
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

  final int seq;

  const TabJump({required this.tab, required this.seq, this.listId, this.taskId});
}

class TabJumpNotifier extends StateNotifier<TabJump?> {
  TabJumpNotifier() : super(null);

  int _seq = 0;

  void toList(String listId) => state = TabJump(tab: listsTabIndex, seq: ++_seq, listId: listId);

  void toTask(String taskId) => state = TabJump(tab: boardTabIndex, seq: ++_seq, taskId: taskId);

  /// Switch tab and open nothing in particular.
  ///
  /// What Home's section headers use: "Alle anzeigen" over the open to-dos
  /// means the Board itself, not one task on it. It still goes through the same
  /// sequence number as the two above, so tapping the same header twice fires
  /// twice rather than setting an identical value nobody listens to.
  void toTab(int tab) => state = TabJump(tab: tab, seq: ++_seq);

  /// Called by whichever screen acted on it. The shell does the tab switch and
  /// leaves the payload alone, so a screen that is mid-transition still finds
  /// its instructions when its listener runs.
  void done() => state = null;
}

final tabJumpProvider = StateNotifierProvider<TabJumpNotifier, TabJump?>((ref) => TabJumpNotifier());
