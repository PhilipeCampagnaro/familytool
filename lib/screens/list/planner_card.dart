import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/calendar_data.dart';
import '../../data/grocery_catalog.dart';
import '../../data/icon_suggestions.dart';
import '../../data/planner_examples.dart';
import '../../l10n/l10n.dart';
import '../../models/grocery_unit.dart';
import '../../models/list_plan.dart';
import '../../models/shopping_list.dart';
import '../../services/list_planner.dart';
import '../../services/recipe_fetch.dart';
import '../../state/list_planner_state.dart';
import '../../state/list_state.dart';
import '../../theme/app_icons.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/filter_chip.dart';
import '../../widgets/glass.dart';
import '../../widgets/icon_picker.dart';
import '../../widgets/markdown_text.dart';
import '../../widgets/status_island.dart';
import '../../widgets/toast_chip.dart';

/// **Vorhaben: one goal in, one finished list out.**
///
/// Not a chat, and the answer is not a wall of chat markdown — the reasoning is
/// in [docs/list-planner.md](../../../docs/list-planner.md). A chat invites a
/// second turn, every second turn is another paid request, and the app would
/// never know when the conversation was finished. So the model fills a schema
/// and this file draws it with the app's own widgets: `IconTile`, `dividedRows`,
/// the real type scale. What comes back looks like a list somebody made by
/// hand, which is the whole point.
///
/// The one field with any markup in it is `recipe`, and it is held to a subset
/// this app draws itself — see [MarkdownText]. A method has structure that
/// prose cannot carry; a chatbot transcript is still not what any of this is.
///
/// ## It unfolds where you tapped, and that is the third answer
///
/// A sheet was the first and a pushed page the second. Both were a *departure*:
/// you asked Listen a question and Listen went away. This is the same content
/// under the sentence that offered it — [ListIsland] carries the disclosure
/// caret, this card grows out from under it, and the household's own lists stay
/// on screen below the whole time. Which is what makes the answer read as a
/// draft of a list rather than as a page about lists, and it means there is
/// nothing to come back from: the list you make is already underneath.
///
/// The card grows **twice**. Open, it is a field, a row of suggestions and a
/// send button. When the answer lands it grows again into the whole plan with
/// the accent pill under it. Both are one [AnimatedSize] around a `switch` on
/// the phase, so the card is never rebuilt from scratch — it is the same
/// surface, taller.
///
/// **Nothing here is `const`**: every one of these reads a palette token in its
/// own `build` (see `tool/check_const_palette.dart`).
class PlannerCard extends ConsumerStatefulWidget {
  const PlannerCard({super.key});

  @override
  ConsumerState<PlannerCard> createState() => _PlannerCardState();
}

class _PlannerCardState extends ConsumerState<PlannerCard> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  /// Long enough to read as growth rather than a jump, short enough that the
  /// lists below do not appear to be sliding away from the reader.
  static const _grow = Duration(milliseconds: 280);

  /// **Folded on arrival, every time.** The shopping is why the card was
  /// opened; the method is what you want later, at the hob. Held here rather
  /// than in [PlannerState] because it is how this card is being *read*, not
  /// part of the plan — "Nochmal fragen" rebuilds the plan and this should
  /// simply be shut again, which falls out of resetting it in [_again].
  bool _methodOpen = false;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Whether what is in the field is a page to read rather than a goal to plan.
  ///
  /// The same test [PlannerNotifier.run] routes on, asked here so the button
  /// and the send agree — a button that is enabled for something `run` would
  /// then hand to the model is worse than either.
  bool get _isLink => recipePageUrl(_controller.text) != null;

  void _send() {
    FocusScope.of(context).unfocus();
    ref.read(plannerProvider.notifier).run(_controller.text);
  }

  /// "Nochmal" — the answer goes away and the goal comes back into the field to
  /// be edited. **Deliberately does not re-send**: a retry is another paid
  /// request, and a button that spends money on its own is one nobody trusts.
  ///
  /// **The card is scrolled back up before it shrinks, not while.** "Nochmal"
  /// sits at the foot of an answer that is easily three screens tall, so the
  /// card's top is far above the viewport when it is pressed. Shrinking it from
  /// there left it stuck at a stale height — the list does not lay out a child
  /// that is scrolled out of range, so the size animation never got the frames
  /// it needed — and the chips under it froze half-grown for the same reason.
  /// With the top in view every frame of the shrink is laid out, and the reader
  /// is looking at the field the goal comes back into.
  /// [clear] empties the field instead of restoring the goal, for the one
  /// failure where the goal is the problem rather than the wording: a page that
  /// held no ingredients. Putting that address back would leave the reader
  /// selecting and deleting a URL before they could do the thing the sentence
  /// above the button just told them to do.
  Future<void> _again({bool clear = false}) async {
    await Scrollable.ensureVisible(
      context,
      duration: _grow,
      curve: Curves.easeOutCubic,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    );
    if (!mounted) return;
    _methodOpen = false;
    ref.read(plannerProvider.notifier).editGoal();
    _controller.text = clear ? '' : ref.read(plannerProvider).goal;
    _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
    _focus.requestFocus();
  }

  void _seed(String example) {
    _controller.text = example;
    _controller.selection = TextSelection.collapsed(offset: example.length);
    setState(() {});
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(plannerProvider);

    // Closing empties the field and takes the keyboard away with it. Done here
    // rather than in the notifier because the text is the widget's, not the
    // state's — the state only ever hears the goal that was actually sent.
    ref.listen<bool>(plannerProvider.select((s) => s.open), (was, now) {
      if (now == true && was != true) {
        _focus.requestFocus();
      } else if (now == false) {
        _controller.clear();
        _focus.unfocus();
      }
    });

    // AnimatedCrossFade rather than `if (open)`: it keeps both states around so
    // the card sizes *and* fades in both directions — see the expand/collapse
    // rule in docs/design-system.md.
    return AnimatedCrossFade(
      firstChild: SizedBox(width: double.infinity),
      secondChild: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.blockGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // **A [SectionCard], not a container that resembles one.** It sits
            // directly above the household's own lists, which are one, and the
            // hand-rolled copy this started as differed from it in every way a
            // copy does: a 22 radius against their 20, and its own idea of the
            // lift. Two cards of the same width, fourteen points apart, wearing
            // two different shadows is exactly the thing you see and cannot
            // name. Being the same widget is the only way that stays true.
            SectionCard(
              children: [
                AnimatedSize(
                  duration: _grow,
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: switch (state.phase) {
                      PlannerPhase.ask => _ask(state),
                      PlannerPhase.working => _working(state),
                      PlannerPhase.failed => _failed(state),
                      PlannerPhase.answer => _answer(state),
                    },
                  ),
                ),
              ],
            ),
            _suggestions(asking: state.phase == PlannerPhase.ask),
          ],
        ),
      ),
      crossFadeState: state.open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
      duration: _grow,
      sizeCurve: Curves.easeOutCubic,
    );
  }

  /// **Outside the card, under it, on the panel's own grey.**
  ///
  /// They were inside at first and it was the wrong reading: in there they sat
  /// on the same white as the field, under the same rim, and looked like part
  /// of the thing being filled in — a row of tags on the draft rather than four
  /// ways to start one. Out here they are what they are, offers *about* the
  /// card, and the card goes back to being one field and one button.
  ///
  /// They also leave the moment the question is sent, which is the other half
  /// of it: a suggestion is only a suggestion while the field is still empty
  /// enough to take one.
  Widget _suggestions({required bool asking}) => AnimatedCrossFade(
    firstChild: SizedBox(width: double.infinity),
    secondChild: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 14),
        Text(L.s.plannerExamplesLabel, style: AppText.microLabel),
        const SizedBox(height: 8),
        // Kalender's chip, not a second one that resembles it — see
        // [AppFilterChip]. **[ChipTone.outlined], which is neither of the filter
        // tones**: nothing is being filtered here, so the pair those two make
        // has nothing to say. Grey would be four disabled-looking buttons and
        // accent four chips claiming a selection nobody made; white with a
        // hairline rim reads as *press me* without reading as *on*.
        //
        // The glyph comes off the example itself — see [PlannerExample] — so it
        // cannot end up describing a different suggestion than the one it sits
        // on.
        //
        // **Four of twenty-four, and tomorrow it is a different four** —
        // [plannerSuggestions] draws one from each of the four groups, keyed on
        // the date. Calling it here rather than caching it in state is
        // deliberate and safe: it is a pure function of the day, so a rebuild
        // mid-sentence returns exactly the same four.
        SizedBox(
          height: AppFilterChip.rowHeight,
          child: ListView(
            scrollDirection: Axis.horizontal,
            // None of its own: the body already insets this by the screen
            // padding, and the row is meant to line up with the card above it
            // and run off the right edge from there.
            padding: EdgeInsets.zero,
            children: [
              for (final example in plannerSuggestions(calToday()))
                Padding(
                  padding: const EdgeInsets.only(right: AppFilterChip.gap),
                  child: AppFilterChip(
                    label: example.text,
                    tone: ChipTone.outlined,
                    onTap: () => _seed(example.text),
                    padding: const EdgeInsets.only(left: 11, right: 14, top: 8, bottom: 8),
                    leading: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: AppIcon(example.icon, size: 17, color: AppColors.inkSecondary),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
    crossFadeState: asking ? CrossFadeState.showSecond : CrossFadeState.showFirst,
    duration: _grow,
    sizeCurve: Curves.easeOutCubic,
  );

  // ------------------------------------------------------------------- ask

  List<Widget> _ask(PlannerState state) => [
    Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        maxLines: 4,
        minLines: 2,
        maxLength: plannerGoalMaxLength,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _send(),
        style: AppText.input,
        decoration: InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
          hintText: L.s.plannerHint,
          // The counter is noise until the cap is close: this is a sentence,
          // not a form field, and a "0/300" under an empty box makes it read
          // like one.
          counterText: '',
        ),
        onChanged: (_) => setState(() {}),
      ),
    ),
    Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 14, 14),
      child: Row(
        children: [
          // **How many are left, on the same row as the button that spends
          // one.** Beside the send button rather than in the island or on the
          // paywall: it is information about *this* press, and the reader sees
          // it at the moment it matters instead of meeting a refusal after the
          // wait. The number is the server's (see [PlannerUsage]).
          //
          // Gone while the field holds a link, for that same reason: this press
          // spends nothing, and a count of remaining Vorhaben beside it would
          // be answering a question the reader is not asking.
          Expanded(child: _isLink ? const SizedBox.shrink() : _UsageLine(usage: state.usage)),
          const SizedBox(width: 12),
          // The real accent glass, not a coloured circle: it is the one control
          // on the card and it sits on the card's own white, where an opaque fill
          // would read as a sticker. `enabled` keeps its place and its shape
          // while there is nothing to send, so it reads as "not yet" rather than
          // appearing under the reader's thumb the moment they type a letter.
          //
          // An up arrow rather than `paperPlaneTilt`, which in this app means
          // sending something *to somebody* — it is the invite button in
          // onboarding. Nothing is being sent to a person here.
          //
          // Off, too, once the month is used up: the line beside it says why,
          // and a press that could only come back as a refusal is not one to
          // offer.
          //
          // **Unless what is in the field is a link.** An import reads the page
          // and never asks the model, so it costs nothing and is not counted —
          // see [PlannerNotifier.runImport]. Leaving the button off for one was
          // the quota refusing a request that would never have been made: the
          // reader pasted a recipe, pressed send, and nothing happened at all.
          GlassConfirmButton(
            icon: AppIcons.arrowUp,
            enabled:
                _controller.text.trim().isNotEmpty &&
                (_isLink || !(state.usage?.usedUp ?? false)),
            onTap: _send,
          ),
        ],
      ),
    ),
  ];

  // --------------------------------------------------------------- working

  List<Widget> _working(PlannerState state) => [
    // The island's own wave, looping — the one loading signal the app already
    // has, so the question reads as *being worked on* rather than as a caption.
    _GoalLine(goal: state.goal, waving: true),
    // A skeleton rather than a spinner: it says what is coming — a list of
    // rows — so the wait reads as the list being written rather than as the app
    // having stopped.
    _Skeleton(),
    Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      child: Text(L.s.plannerWorking, style: AppText.label, textAlign: TextAlign.center),
    ),
  ];

  // ---------------------------------------------------------------- failed

  List<Widget> _failed(PlannerState state) {
    // **"Anders formulieren" only where different words could help.** A goal
    // the model could not turn into a list may well work phrased another way,
    // and a timeout may work the second time. A used-up month, a rate limit
    // and a missing key will refuse the rephrased goal exactly as they refused
    // this one, so a button offering it would be a small lie with a wait in
    // it. Those three say when (or that) it will work instead, and the island's
    // caret still folds the card away.
    final canRephrase =
        state.failure == PlannerFailure.unusable ||
        state.failure == PlannerFailure.unavailable;
    // **A page that held no ingredients is not a badly worded goal.** This one
    // came through the import path, where there is no question and no model —
    // the reader pasted an address and it turned out to be an address we
    // cannot read. Offering to word it differently is nonsense: the URL is the
    // URL, and rewriting it would take them somewhere else entirely. The
    // button stays, because there *is* one thing that works from here and the
    // sentence above already names it, so the button says the same thing and
    // hands over an empty field to do it in.
    final noRecipe = state.failure == PlannerFailure.noRecipeOnPage ||
        state.failure == PlannerFailure.noRecipeInVideo;
    return [
      _GoalLine(goal: state.goal),
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
        child: Column(
          children: [
            AppIcon(AppIcons.warning, size: 30, color: AppColors.muted),
            const SizedBox(height: 10),
            Text(
              _failureText(state),
              style: AppText.body.copyWith(color: AppColors.inkSecondary, height: 1.45),
              textAlign: TextAlign.center,
            ),
            if (canRephrase || noRecipe) ...[
              const SizedBox(height: 16),
              GlassPillButton(
                label: noRecipe ? L.s.plannerTypeInstead : L.s.plannerEditGoal,
                onTap: () => _again(clear: noRecipe),
              ),
            ],
          ],
        ),
      ),
    ];
  }

  /// The limits name the moment they lift rather than "tomorrow" or "on the
  /// 1st": the daily window rolls, so "morgen" was wrong for most of the day,
  /// and a date is what somebody planning Saturday's dinner can act on. Each
  /// falls back to the old sentence when the function did not send the time.
  String _failureText(PlannerState state) => switch (state.failure) {
    PlannerFailure.notConfigured => L.s.plannerNotConfigured,
    PlannerFailure.unusable => L.s.plannerUnusable,
    PlannerFailure.noRecipeOnPage => L.s.plannerNoRecipeOnPage,
    PlannerFailure.noRecipeInVideo => L.s.plannerNoRecipeInVideo,
    PlannerFailure.monthlyLimit => switch (state.usage?.resetsAt) {
      final at? => L.s.plannerMonthlyLimitUntil(at.day, monthNames[at.month]),
      null => L.s.plannerMonthlyLimit,
    },
    PlannerFailure.dailyLimit => switch (state.retryAt) {
      final at? => L.s.plannerDailyLimitAt(
        formatTime(at),
        tomorrow: !DateUtils.isSameDay(at, DateTime.now()),
      ),
      null => L.s.plannerDailyLimit,
    },
    _ => L.s.plannerUnavailable,
  };

  // ---------------------------------------------------------------- answer

  List<Widget> _answer(PlannerState state) {
    final plan = state.plan!;
    final kept = state.keptItems.length;
    return [
      // **The question does not come back with the answer.** A [_GoalLine]
      // reading "Silvesterabend für 10 Personen" sat directly above a title
      // reading "Silvesterparty für 10": the same sentence twice, in two sizes,
      // spending the top of the card telling the reader what they typed thirty
      // seconds ago. The bulb was the part worth keeping, so it moves onto the
      // title and the wave that used to wash the question washes the answer
      // instead. The goal is not lost — "Nochmal" puts it straight back into
      // the field, which is the only place it can still be edited.
      _PlanTitle(title: plan.title),

      // **The list first, because the list is the point.**
      _AnswerLabel(label: L.s.plannerWhatToBuy, trailing: L.s.plannerItemCount(kept)),
      ...dividedRows([
        for (final (i, item) in plan.items.indexed)
          _PlanItemRow(
            item: item,
            kind: plan.kind,
            dropped: state.dropped.contains(i),
            onTap: () => ref.read(plannerProvider.notifier).toggleDropped(i),
          ),
      ], inset: true),

      // **A second section under the first, not a line above it.** It was tried
      // directly under the title and that was worse than invisible: a heading
      // sitting above the articles is read as the heading *of* the articles, so
      // "REZEPT" over a column of Sekt and Weißwein said the shopping was the
      // recipe. Below the list, after a full-bleed rule, it is plainly a second
      // thing — and the peek under it is what says so without being opened.
      if (plan.steps.isNotEmpty || plan.recipe != null)
        _MethodDisclosure(
          steps: plan.steps,
          recipe: plan.recipe,
          open: _methodOpen,
          onToggle: () => setState(() => _methodOpen = !_methodOpen),
        ),

      Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
        // The blue glass pill, the same one every primary action in the app
        // wears. It appears only with the answer, because until then there is
        // no list to make.
        child: GlassAccentButton(
          label: L.s.plannerCreateList,
          icon: AppIcons.listPlus,
          expand: true,
          enabled: kept > 0,
          onTap: () => _create(plan),
        ),
      ),
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _again,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16, top: 4),
          child: Text(
            L.s.plannerAgain,
            style: AppText.rowTitle.copyWith(color: AppColors.muted),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ];
  }

  Future<void> _create(ListPlan plan) async {
    final items = ref.read(plannerProvider).keptItems;
    if (items.isEmpty) return;

    final confirm = confirmChipOf(context);
    final notifier = ref.read(listProvider.notifier);

    // The household's own list, not whatever the last sheet in Listen was
    // drafting — the same reset an Aktivität does before stamping one out.
    notifier.primeVisibility(null);

    // Folded away first, deliberately. The list appears on screen before the
    // insert answers (client-side uuid, no read-back — see the "Writing
    // containers from the client" section of docs/backend.md), and the card is
    // sitting exactly where the new row is about to land.
    ref.read(plannerProvider.notifier).close();

    // Straight into it: the reader just asked for this list, and leaving them on
    // the shelf made them go looking for it.
    final created = await notifier.createListWithItems(
      openIt: true,
      name: plan.title,
      kind: plan.kind,
      items: [
        for (final item in items) (text: item.name, sub: item.quantity, unit: item.unit),
      ],
      // **The method goes with the articles.** Dropping it here is what used to
      // send the household off to look the recipe up again once the shopping
      // was done, which is the one moment the feature was meant to help.
      steps: plan.steps,
      recipe: plan.recipe,
      // An imported plan's counterpart to the method: it has no `recipe` to
      // carry, and the page it was read from is what the cook wants back.
      sourceUrl: plan.sourceUrl,
    );
    if (created) confirm(L.s.plannerListCreated);
  }
}

// ---------------------------------------------------------------------------
// Pieces
// ---------------------------------------------------------------------------

/// What was asked, at the top of the card, above what came back.
///
/// The field is gone the moment the request goes out — there is nothing to type
/// into any more — so this is what keeps the answer from floating free of its
/// question.
class _GoalLine extends StatelessWidget {
  final String goal;

  /// While the request is out. [WaveSweep] washes the bulb and the words with
  /// the card's own white, so it reads the same on the dark palette; it is
  /// dropped the moment the answer or the failure lands.
  final bool waving;

  const _GoalLine({required this.goal, this.waving = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: WaveSweep(trigger: goal, mode: waving ? IslandSweep.loop : IslandSweep.none, child: _row()),
    );
  }

  Widget _row() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: AppIcon(AppIcons.lightbulb, size: 15, color: AppColors.accent),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            goal,
            style: AppText.label.copyWith(color: AppColors.inkSecondary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// The plan's own name, wearing the bulb that used to head the question.
///
/// **One title, not two.** The card carried the goal and the title as separate
/// lines, and for a plan they are near enough the same words — the second one
/// was a heading about the first. So the bulb comes down onto the title, at the
/// title's own weight rather than a caption's, and there is one thing at the
/// top of the card saying what this is.
///
/// [WaveSweep] on arrival for the same reason it ran on the question: the wash
/// is how this card says a sentence is new, and the sentence that is new now is
/// the answer.
class _PlanTitle extends StatelessWidget {
  final String title;

  const _PlanTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 2),
      child: WaveSweep(
        trigger: title,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // **Measured against the title's ink, not taken from [AppGlyph].**
            // Those four tiers size *controls*; this is a mark naming the
            // thing, and a duotone glyph fills only about seven tenths of the
            // box it is given, so it takes a larger number than the type it
            // stands beside to weigh the same. The point of padding sits it on
            // the first line's cap height when the title wraps to two.
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: AppIcon(AppIcons.lightbulb, size: 26, color: AppColors.accent),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: AppText.detailTitle)),
          ],
        ),
      ),
    );
  }
}

/// "Noch 27 von 30 Vorhaben diesen Monat", beside the send button.
///
/// **Nothing at all until the server has answered**, and nothing on a plan
/// without a cap: a placeholder number would be a guess about money, and an
/// empty row costs the card no height because the button sets it.
class _UsageLine extends StatelessWidget {
  final PlannerUsage? usage;

  const _UsageLine({required this.usage});

  @override
  Widget build(BuildContext context) {
    final u = usage;
    final text = switch (u) {
      null => null,
      PlannerUsage(exempt: true) => L.s.plannerLimitsLifted,
      // The date is read in UTC — see [PlannerUsage.resetsAt].
      PlannerUsage(usedUp: true) => L.s.plannerNoneLeft(u.resetsAt.day, monthNames[u.resetsAt.month]),
      PlannerUsage(:final left?, :final limit?) => L.s.plannerLeft(left, limit),
      _ => null,
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      layoutBuilder: (current, previous) =>
          Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
      child: text == null
          ? const SizedBox.shrink()
          : Text(
              text,
              key: ValueKey(text),
              maxLines: 2,
              style: AppText.caption.copyWith(
                color: (u?.usedUp ?? false) ? AppColors.inkSecondary : AppColors.muted,
              ),
            ),
    );
  }
}

/// "Was du brauchst · 12 Artikel" — the heading over one block of the answer.
class _AnswerLabel extends StatelessWidget {
  final String label;
  final String? trailing;

  const _AnswerLabel({required this.label, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppText.microLabel),
          if (trailing case final count?) Text(count, style: AppText.microLabel),
        ],
      ),
    );
  }
}

/// One article, drawn exactly as it will be once it is a real row.
///
/// **The icon comes from [planItemIconKey] and nothing else** — the same pure
/// function the created row goes through. So the preview cannot promise a
/// picture the list then does not get: a Lebensmittel plan arrives wearing
/// photographs from `assets/grocery/`, and a Bauhaus one wears nothing at all,
/// because nothing guesses a picture for a Sonstige article any more.
class _PlanItemRow extends StatelessWidget {
  final ListPlanItem item;
  final ListKind kind;
  final bool dropped;
  final VoidCallback onTap;

  const _PlanItemRow({required this.item, required this.kind, required this.dropped, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final grocery = kind == ListKind.grocery;
    final iconKey = planItemIconKey(item.name, grocery: grocery);
    final quantity = _quantityLabel();

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        child: Row(
          children: [
            // A grocery article without a photo gets the general cart, as its
            // row in the list will — not IconTile's fallback glyph. A Sonstige
            // one gets no slot at all rather than an empty one: a column of
            // blank squares down the left is a picture of what is missing.
            if (grocery) ...[
              IconTile(
                iconKey: iconKey ?? generalGroceryAsset,
                size: AppText.rowMark,
                imageSize: AppText.markImage(AppText.rowMark),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: AppText.rowTitle.copyWith(
                      color: dropped ? AppColors.doneInk : AppColors.ink,
                      decoration: dropped ? TextDecoration.lineThrough : null,
                      decorationColor: AppColors.doneInk,
                    ),
                  ),
                  if (quantity != null) ...[
                    const SizedBox(height: 1),
                    Text(
                      quantity,
                      style: AppText.caption.copyWith(color: dropped ? AppColors.doneInk : AppColors.muted),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            // **Ticked means "leave this out", not "done".** The salt and the
            // olive oil they already have, dropped before the list is made
            // rather than deleted from it afterwards.
            AppIcon(
              dropped ? AppIcons.x : AppIcons.checkCircle,
              size: AppGlyph.row,
              flat: true,
              color: dropped ? AppColors.mutedLight : AppColors.accent,
            ),
          ],
        ),
      ),
    );
  }

  /// "500 g", "2", or nothing at all.
  ///
  /// The unit's word comes from `L.s` through [groceryUnitLabel], never from
  /// the stored key — the app switches language while it is running.
  String? _quantityLabel() {
    final unit = item.unit == null ? null : groceryUnitLabel(item.unit!);
    if (item.quantity == null) return unit;
    return unit == null ? item.quantity : '${item.quantity} $unit';
  }
}

/// The method — the overview steps and, when there is one, the full recipe —
/// folded behind its own label.
///
/// **Nothing that only says a thing exists can make anybody open it.** This was
/// a label and a caret — twice, in fact: a grey `microLabel`, then a rung
/// larger and heavier, then an accent pill. All three were invisible or worse,
/// and the size was never what was wrong with them. A word is a promise about
/// content, and a promise is easy to decline; the reader has the list they came
/// for and nothing on screen contradicts the feeling that they are done.
///
/// So the method **shows itself instead of announcing itself**. The first
/// [_peek] points of it are simply there, under the heading, faded out at the
/// bottom, and **Alles anzeigen** takes the lid off. What is visible is a
/// sentence of the actual recipe, which nobody has to take on trust.
///
/// **The fade is load-bearing, not decoration.** A fixed height cuts prose
/// mid-word, and in four languages there is no height that does not; the
/// gradient is what turns that cut into an edge. It is [BlendMode.dstIn] over
/// an [OverflowBox], so the text is laid out at its true height and *clipped*
/// rather than squeezed into [_peek] points.
///
/// **Whether it peeks at all is decided from the content, not from a
/// measurement** — see [_peeks]. Getting it wrong is cheap in both directions:
/// a short method that peeks anyway fades over its own last line, which is what
/// the fade is for, and a long one drawn in full is the behaviour this had
/// before.
///
/// **An [AnimatedSize] rather than an `if`**, so opening it grows the card the
/// way every other disclosure in this file does instead of teleporting the
/// create button down the screen.
///
/// **An [AnimatedSize] rather than an `if`**, so opening it grows the card the
/// way every other disclosure in this file does instead of teleporting the
/// create button down the screen.
///
/// The recipe is drawn by [MarkdownText], which parses the small subset the
/// prompt asks for — headings, bullets, numbered steps, bold — and prints
/// everything else exactly as it arrived. The same widget draws it in the
/// method sheet on the finished list, so the plan and the list it becomes are
/// the same page twice.
class _MethodDisclosure extends StatelessWidget {
  final List<String> steps;
  final String? recipe;
  final bool open;
  final VoidCallback onToggle;

  const _MethodDisclosure({
    required this.steps,
    required this.recipe,
    required this.open,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // **Full-bleed, where the articles above it are parted by
        // [InsetDivider]s.** The heavier of the app's two rules is what makes
        // this read as the end of one block rather than the gap between two
        // rows of the same one.
        Padding(padding: const EdgeInsets.only(top: 8), child: CardDivider()),

        // The articles' own heading style, deliberately: now that the peek and
        // the "Alles anzeigen" row do the inviting, this is a caption again and
        // has nothing to prove. A plan with a recipe is a plan about cooking,
        // and "Rezept" is the truer name for what is inside than "So geht's".
        _AnswerLabel(label: recipe == null ? L.s.plannerHowTo : L.s.plannerRecipe),

        AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: double.infinity,
            child: open || !_peeks ? _body() : _peeked(),
          ),
        ),

        if (_peeks) _more(),
      ],
    );
  }

  /// How much of the method is simply there while it is shut — about a heading
  /// and three lines, so what shows is a real stage of the plan rather than a
  /// teasing strip of one.
  static const _peek = 132.0;

  /// **Is there enough behind this to be worth hiding?**
  ///
  /// Decided from the shape of the content rather than from a laid-out height:
  /// measuring means rendering the prose twice, or a render object, to answer a
  /// question whose wrong answers both cost nothing. A recipe always overflows
  /// [_peek]; `steps[0]` is the plan's `#` title and every entry after it is a
  /// titled stage of about three lines, so three entries is the point where a
  /// method reliably does too. Below that it is drawn in full, with no fade and
  /// no row under it, because there would be nothing behind them.
  bool get _peeks => recipe != null || steps.length > 2;

  /// The top of the method, cut off and faded out.
  ///
  /// [OverflowBox] is what makes this a *cut*: the column inside it is laid out
  /// against an unbounded height, exactly as it will be when open, so the words
  /// do not reflow when the lid comes off — the box around it is simply shorter
  /// than they are, and [ClipRect] takes the rest away.
  Widget _peeked() => ClipRect(
    child: SizedBox(
      height: _peek,
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        // Only the alpha of these colours is read. Opaque for the first sixty
        // percent so the fade reads as an edge at the bottom rather than as
        // prose that was printed too faintly.
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Colors.white, Colors.transparent],
          stops: [0, 0.6, 1],
        ).createShader(rect),
        // `minHeight: 0` explicitly: left null it inherits the [SizedBox]'s
        // tight 132, which would stretch a body shorter than the peek instead
        // of letting it end where it ends.
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: 0,
          maxHeight: double.infinity,
          child: _body(),
        ),
      ),
    ),
  );

  /// The app's own "there is more behind this" row — the same centred accent
  /// label and caret the icon picker puts under a shortened list of shops. Its
  /// place at the foot of the block is the point: it is the first thing below
  /// the fade, so the gesture the fade asks for is directly under the hand.
  Widget _more() {
    final accent = AppColors.accent;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 15),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              open ? L.s.showLess : L.s.plannerShowMethod,
              style: AppText.buttonSmall.copyWith(color: accent),
            ),
            const SizedBox(width: 6),
            AppIcon(
              open ? AppIcons.caretUp : AppIcons.caretDown,
              size: AppGlyph.caret,
              flat: true,
              color: accent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    final text = recipe?.trim() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (steps.isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(18, 0, 18, text.isEmpty ? 6 : 0),
            child: MarkdownText(stepsAsMarkdown(steps)),
          ),
        if (text.isNotEmpty)
          Padding(padding: EdgeInsets.fromLTRB(18, steps.isEmpty ? 0 : 14, 18, 6), child: MarkdownText(text)),
      ],
    );
  }
}

/// Four grey rows where the articles will be, each trying on glyphs.
///
/// **The glyphs are the answer's own vocabulary** — a cart, a pot, a hammer, a
/// cake — so the wait says *a list of things is being written* rather than
/// *please hold*. They turn over a row at a time, top to bottom, which is what
/// separates writing from blinking: four circles changing together would be a
/// loading graphic again. Deliberately not a guess at this plan's articles —
/// nothing is known about them until the answer lands, and a wrong guess
/// drawn confidently is worse than an honest placeholder.
class _Skeleton extends StatefulWidget {
  const _Skeleton();

  @override
  State<_Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<_Skeleton> with TickerProviderStateMixin {
  static const _glyphs = [
    AppIcons.shoppingCart,
    AppIcons.cookingPot,
    AppIcons.hammer,
    AppIcons.cake,
    AppIcons.plant,
    AppIcons.basket,
    AppIcons.pizza,
    AppIcons.paintRoller,
    AppIcons.package,
    AppIcons.egg,
    AppIcons.tShirt,
    AppIcons.forkKnife,
  ];

  /// How long each glyph stays before the next one.
  static const _hold = Duration(milliseconds: 850);

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  /// One pass through every glyph; a row's position in it is offset by its
  /// index, which is what makes the change ripple down the rows.
  late final AnimationController _cycle = AnimationController(vsync: this, duration: _hold * _glyphs.length)
    ..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    _cycle.dispose();
    super.dispose();
  }

  IconData _glyphFor(int row) {
    final step = (_cycle.value * _glyphs.length + row * 0.22).floor();
    return _glyphs[(step + row * 3) % _glyphs.length];
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_pulse, _cycle]),
      builder: (context, _) => Column(
        children: dividedRows([
          for (var i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              child: Row(
                children: [
                  Container(
                    width: AppText.rowMark,
                    height: AppText.rowMark,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.surfaceAlt, shape: BoxShape.circle),
                    // Keyed on the glyph, so the switcher only fades when a row
                    // actually moves on — not on every frame of the pulse.
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 320),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween<double>(begin: 0.6, end: 1).animate(animation),
                          child: child,
                        ),
                      ),
                      child: AppIcon(
                        _glyphFor(i),
                        key: ValueKey(_glyphFor(i)),
                        size: AppText.rowMark * 0.52,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    // Only the bar breathes. The glyph is already moving, and a
                    // glyph that also pulsed would be two animations on one dot.
                    child: Opacity(
                      opacity: 0.45 + _pulse.value * 0.35,
                      child: Container(
                        height: 11,
                        // Staggered widths, or four identical bars read as a
                        // loading graphic rather than as rows of words.
                        margin: EdgeInsets.only(right: [40.0, 96.0, 20.0, 68.0][i]),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceAlt,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ], inset: true),
      ),
    );
  }
}
