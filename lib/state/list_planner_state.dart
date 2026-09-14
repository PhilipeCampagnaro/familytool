import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/list_plan.dart';
import '../services/list_planner.dart';

/// Which of the screen's four faces is showing.
///
/// One screen rather than four, so the goal that was typed stays above the
/// answer it produced — see "The experience" in
/// [docs/list-planner.md](../../docs/list-planner.md).
enum PlannerPhase { ask, working, answer, failed }

class PlannerState {
  /// Whether the Vorhaben card is unfolded under Listen's title.
  ///
  /// This *is* what puts it on screen — `PlannerCard` cross-fades on it and
  /// `ListIsland`'s caret points at it — and it does one more thing besides.
  /// A request outlives the card that started it, so [PlannerNotifier.run]
  /// reads this back before it publishes an answer: closed means the reader
  /// folded the card away and there is nobody left to give it to.
  final bool open;

  final PlannerPhase phase;

  /// What was asked. Kept through [PlannerPhase.working] and
  /// [PlannerPhase.answer] so the screen can print it above the result, and so
  /// "Nochmal" can put it back in the field to be edited rather than retyped.
  final String goal;

  final ListPlan? plan;
  final PlannerFailure? failure;

  /// Articles the reader has ticked *off* before the list is made — the salt
  /// and the olive oil they already have.
  ///
  /// **Indices, not names.** A plan can legitimately name the same article
  /// twice ("Zwiebeln" for the sauce and for the topping), and keying on the
  /// text would drop both when one is tapped.
  final Set<int> dropped;

  const PlannerState({
    this.open = false,
    this.phase = PlannerPhase.ask,
    this.goal = '',
    this.plan,
    this.failure,
    this.dropped = const {},
  });

  /// What will actually be written, in plan order.
  List<ListPlanItem> get keptItems => [
    for (final (i, item) in (plan?.items ?? const <ListPlanItem>[]).indexed)
      if (!dropped.contains(i)) item,
  ];

  PlannerState copyWith({
    bool? open,
    PlannerPhase? phase,
    String? goal,
    ListPlan? plan,
    PlannerFailure? failure,
    Set<int>? dropped,
  }) => PlannerState(
    open: open ?? this.open,
    phase: phase ?? this.phase,
    goal: goal ?? this.goal,
    plan: plan ?? this.plan,
    failure: failure ?? this.failure,
    dropped: dropped ?? this.dropped,
  );
}

class PlannerNotifier extends StateNotifier<PlannerState> {
  PlannerNotifier() : super(const PlannerState());

  /// Empty, and about to be looked at. Always a fresh question rather than last
  /// week's dinner still on it — there is no draft worth restoring, and an
  /// answer that reappeared under a title saying "Vorhaben" would look like a
  /// new one.
  void open() => state = const PlannerState(open: true);

  /// The page has gone — the chevron, the create button, a back-swipe. Called
  /// from `openPlanner` once for all of them.
  ///
  /// **A request still in flight is abandoned, not awaited.** [run] checks
  /// [PlannerState.open] again when the answer lands, so a plan nobody is
  /// waiting for is dropped rather than being written into a page that is no
  /// longer on screen.
  void close() => state = const PlannerState();

  /// Put the answer away and the goal back in the field, ready to be edited.
  ///
  /// **This is what "Nochmal" does, and it deliberately does not re-send.** The
  /// reader has to press the button again, because a retry is another paid
  /// request and a button that spends money on its own is a button nobody
  /// trusts.
  void editGoal() => state = PlannerState(open: true, phase: PlannerPhase.ask, goal: state.goal);

  void toggleDropped(int index) {
    final next = {...state.dropped};
    if (!next.remove(index)) next.add(index);
    state = state.copyWith(dropped: next);
  }

  Future<void> run(String goal) async {
    final trimmed = goal.trim();
    if (trimmed.isEmpty || state.phase == PlannerPhase.working) return;

    state = PlannerState(open: true, phase: PlannerPhase.working, goal: trimmed);
    try {
      final plan = await planList(trimmed);
      // `open` as well as `mounted`: the reader may have left while the request
      // was out, and the notifier outlives the page — so without this the plan
      // would be sitting there, half a minute stale, the next time somebody
      // opened Vorhaben.
      if (!mounted || !state.open) return;
      state = PlannerState(open: true, phase: PlannerPhase.answer, goal: trimmed, plan: plan);
    } on PlannerException catch (e) {
      if (!mounted || !state.open) return;
      state = PlannerState(open: true, phase: PlannerPhase.failed, goal: trimmed, failure: e.failure);
    }
  }
}

/// **Not `autoDispose`.** The page is a route, and a route rebuilds its body on
/// every frame of the push animation; an auto-disposing provider read only from
/// inside it would be torn down and recreated the moment the page closes
/// mid-request, losing the answer somebody is waiting for.
/// [PlannerNotifier.close] is what clears it instead, on the way out.
final plannerProvider = StateNotifierProvider<PlannerNotifier, PlannerState>((ref) => PlannerNotifier());
