import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/list_plan.dart';
import '../services/list_planner.dart';
import '../services/recipe_fetch.dart';
import '../services/recipe_import.dart';
import '../services/youtube_import.dart';
import 'entitlement_state.dart';

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

  /// When a [PlannerFailure.dailyLimit] lifts, local time.
  final DateTime? retryAt;

  /// The household's month as the server last reported it. **Survives every
  /// phase change and closing the card** — it is a fact about the household,
  /// not about this question, and dropping it would blank the line under the
  /// field on every "Nochmal" until the next round trip.
  final PlannerUsage? usage;

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
    this.retryAt,
    this.usage,
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
    DateTime? retryAt,
    PlannerUsage? usage,
    Set<int>? dropped,
  }) => PlannerState(
    open: open ?? this.open,
    phase: phase ?? this.phase,
    goal: goal ?? this.goal,
    plan: plan ?? this.plan,
    failure: failure ?? this.failure,
    retryAt: retryAt ?? this.retryAt,
    usage: usage ?? this.usage,
    dropped: dropped ?? this.dropped,
  );
}

class PlannerNotifier extends StateNotifier<PlannerState> {
  PlannerNotifier(this._ref) : super(const PlannerState());

  final Ref _ref;

  bool get _ignoreLimits => _ref.read(plannerLimitsLiftedProvider);

  /// The Settings plan switch, in the wire name `list-plan` reads. Also only a
  /// request: the server applies it for an exempt account and nobody else.
  String? get _simulatePlan => _ref.read(planOverrideProvider)?.name;

  /// Empty, and about to be looked at. Always a fresh question rather than last
  /// week's dinner still on it — there is no draft worth restoring, and an
  /// answer that reappeared under a title saying "Vorhaben" would look like a
  /// new one.
  ///
  /// The count is asked for again every time: another parent may have made a
  /// plan on their phone since this one last looked.
  void open() {
    state = PlannerState(open: true, usage: state.usage);
    refreshUsage();
  }

  /// The card has folded away — the island's caret, or a list being made from
  /// the answer.
  ///
  /// **A request still in flight is abandoned, not awaited.** [run] checks
  /// [PlannerState.open] again when the answer lands, so a plan nobody is
  /// waiting for is dropped rather than being written into a card that is no
  /// longer on screen.
  void close() => state = PlannerState(usage: state.usage);

  /// Put the answer away and the goal back in the field, ready to be edited.
  ///
  /// **This is what "Nochmal" does, and it deliberately does not re-send.** The
  /// reader has to press the button again, because a retry is another paid
  /// request and a button that spends money on its own is a button nobody
  /// trusts.
  void editGoal() =>
      state = PlannerState(open: true, phase: PlannerPhase.ask, goal: state.goal, usage: state.usage);

  /// Re-reads the household's month. Also called by the debug switch, so
  /// flipping it shows its effect on the line straight away.
  Future<void> refreshUsage() async {
    final usage = await fetchPlannerUsage(ignoreLimits: _ignoreLimits, simulatePlan: _simulatePlan);
    if (!mounted || usage == null) return;
    state = state.copyWith(usage: usage);
  }

  void toggleDropped(int index) {
    final next = {...state.dropped};
    if (!next.remove(index)) next.add(index);
    state = state.copyWith(dropped: next);
  }

  /// A recipe page turned into a plan, **without the model**.
  ///
  /// The household was already reading the page; schema.org's Recipe markup —
  /// which Google's recipe rich card obliges the site to publish — carries the
  /// ingredient list in a machine-readable form. So this is a fetch and a
  /// parse, and the answer lands in the same [PlannerPhase.answer] card as a
  /// generated plan, because from the card's point of view a plan is a plan.
  ///
  /// **It costs nothing and is therefore not counted.** No request to
  /// `list-plan`, no `list_plan_runs` row, no monthly cap — [PlannerState.usage]
  /// is carried through untouched. A household on the free plan can import
  /// every recipe it reads, which is the correct answer: we are not paying for
  /// any of it.
  Future<void> runImport(Uri url) async {
    if (state.phase == PlannerPhase.working) return;
    // The address is what goes above the answer. It is what the reader handed
    // over, and a plan captioned with the URL it came from is legible in a way
    // that a bare dish name from somebody else's page is not.
    final goal = url.toString();
    final videoId = youtubeVideoId(url);
    state = PlannerState(open: true, phase: PlannerPhase.working, goal: goal, usage: state.usage);
    try {
      final imported = videoId == null
          ? parseRecipePage(html: await fetchRecipePage(url), pageUrl: goal)
          : await _fromVideo(videoId, goal);
      if (!mounted || !state.open) return;
      if (imported == null || !imported.plan.isUsable) {
        state = PlannerState(
          open: true,
          phase: PlannerPhase.failed,
          goal: goal,
          // Reached the page and found no recipe on it — a different thing
          // from the network failing, and the copy says so, because "try
          // again in a moment" is wrong advice for a page that will never
          // have a recipe on it. A video says so in its own words: the
          // description is a free-text box, and "no ingredients under this
          // video" is a fact about that box rather than about the page.
          failure: videoId == null
              ? PlannerFailure.noRecipeOnPage
              : PlannerFailure.noRecipeInVideo,
          usage: state.usage,
        );
        return;
      }
      state = PlannerState(
        open: true,
        phase: PlannerPhase.answer,
        goal: goal,
        plan: imported.plan,
        usage: state.usage,
      );
    } catch (_) {
      if (!mounted || !state.open) return;
      state = PlannerState(
        open: true,
        phase: PlannerPhase.failed,
        goal: goal,
        failure: PlannerFailure.unavailable,
        usage: state.usage,
      );
    }
  }

  /// A YouTube address: the description first, and the recipe it points at
  /// second.
  ///
  /// **Two fetches at most, and the second only when it is worth it.** The
  /// description usually holds the list itself; when it does not, a line the
  /// channel wrote saying "Zum Rezept:" over a link is a good enough reason to
  /// follow exactly one of them ([recipeLinkInDescription]). Every other link
  /// under a cooking video is the knife, the book or the shop.
  ///
  /// The Liste keeps the **video's** address either way. It is what the reader
  /// handed over and what they will want to open again — the blog post is
  /// where the words came from, not where they were.
  Future<RecipeImport?> _fromVideo(String videoId, String goal) async {
    final html = await fetchRecipePage(youtubeWatchUrl(videoId));
    if (!mounted || !state.open) return null;
    final fromDescription = parseYoutubePage(html: html, pageUrl: goal);
    if (fromDescription != null) return fromDescription;

    final details = youtubeVideoDetails(html);
    final linked = details == null ? null : recipeLinkInDescription(details.description);
    if (linked == null) return null;
    final page = await fetchRecipePage(linked);
    if (!mounted || !state.open) return null;
    return parseRecipePage(html: page, pageUrl: goal);
  }

  Future<void> run(String goal) async {
    final trimmed = goal.trim();
    if (trimmed.isEmpty || state.phase == PlannerPhase.working) return;

    // A page beats a guess. When what arrived is an address rather than a
    // sentence, the ingredients are already written down on the other end of
    // it — so read them instead of asking a model to invent a version of the
    // same recipe. See [runImport].
    final page = recipePageUrl(trimmed);
    if (page != null) return runImport(page);

    state = PlannerState(open: true, phase: PlannerPhase.working, goal: trimmed, usage: state.usage);
    try {
      final result = await planList(trimmed, ignoreLimits: _ignoreLimits, simulatePlan: _simulatePlan);
      // `open` as well as `mounted`: the reader may have left while the request
      // was out, and the notifier outlives the card — so without this the plan
      // would be sitting there, half a minute stale, the next time somebody
      // opened Vorhaben.
      if (!mounted || !state.open) return;
      state = PlannerState(
        open: true,
        phase: PlannerPhase.answer,
        goal: trimmed,
        plan: result.plan,
        usage: result.usage ?? state.usage,
      );
    } on PlannerException catch (e) {
      if (!mounted || !state.open) return;
      state = PlannerState(
        open: true,
        phase: PlannerPhase.failed,
        goal: trimmed,
        failure: e.failure,
        retryAt: e.retryAt,
        usage: e.usage ?? state.usage,
      );
    }
  }
}

/// **Not `autoDispose`.** The card and the island's caret both read it, and the
/// card cross-fades out of the tree's attention rather than leaving it; an
/// auto-disposing provider would be one rebuild away from dropping the answer
/// somebody is waiting for. [PlannerNotifier.close] is what clears it instead.
final plannerProvider = StateNotifierProvider<PlannerNotifier, PlannerState>((ref) => PlannerNotifier(ref));

/// The debug switch in Settings: ask `list-plan` to skip the Vorhaben limits.
///
/// **It asks; it does not grant.** The server honours it only for an account
/// listed in `public.plan_limit_exemptions`, which no client can read or write,
/// so it is inert for everybody else and in any build that shows the row by
/// mistake. In memory only, like `planOverrideProvider` — a restart puts the
/// limits back, which is the state every test should end in.
final plannerLimitsLiftedProvider = StateProvider<bool>((ref) => false);
