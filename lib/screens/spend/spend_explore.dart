import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/grocery_search.dart' show foldTerm;
import '../../data/spend_analysis.dart';
import '../../l10n/l10n.dart';
import '../../services/native_menu.dart';
import '../../models/spend.dart';
import '../../state/family_state.dart';
import '../../state/spend_state.dart';
import '../../theme/app_icons.dart';
import '../../theme/tokens.dart';
import '../../widgets/anchored_menu.dart';
import '../../widgets/collapsing_header.dart';
import '../../widgets/glass.dart';
import '../../widgets/native_search_field.dart';
import '../spend_screen.dart';
import 'spend_breakdown.dart';
import 'spend_budgets.dart';
import 'spend_charts.dart' show spendCurrency;

/// The four ways the explore page cuts the money.
enum SpendExploreView {
  all,
  members,
  merchants,
  categories;

  /// The breakdown this view lists, or null for the payments themselves.
  SpendGrouping? get grouping => switch (this) {
    SpendExploreView.all => null,
    SpendExploreView.members => SpendGrouping.member,
    SpendExploreView.merchants => SpendGrouping.merchant,
    SpendExploreView.categories => SpendGrouping.category,
  };

  /// What the card below the chart calls itself — **and the words in the
  /// picker are the same words**, so the row with the tick beside it reads
  /// exactly like the heading it is standing under. The three breakdowns
  /// borrow their headings from [SpendGrouping], which is what Ausgaben's own
  /// card prints, so the page behind the link and the card in front of it
  /// never call one thing two names.
  ///
  /// They used to be shorter — "Alle", "Personen" — because four of them had
  /// to fit across a pill; a dropdown has the width of the card.
  String get title => grouping?.title ?? L.s.spendAllPurchases;

  IconData get icon => grouping?.icon ?? AppIcons.receipt;

  /// The glyph UIKit draws in its own menu. Validated against the runtime's
  /// own list — see `showAnchoredMenu`.
  String get symbol => grouping?.symbol ?? 'list.bullet';

  static SpendExploreView of(SpendGrouping grouping) => switch (grouping) {
    SpendGrouping.category => SpendExploreView.categories,
    SpendGrouping.merchant => SpendExploreView.merchants,
    SpendGrouping.member => SpendExploreView.members,
  };
}

/// **"How much do we spend at REWE?"** — the page that answers it.
///
/// The chart card from Ausgaben on top, the payments or a breakdown under it,
/// and the phone's own search field at the foot, exactly where Settings keeps
/// its. **Whatever is typed or tapped filters the rows before they are folded**,
/// so the headline, the line, the bars, the ring and the list all describe the
/// same subset — typing "rewe" and putting the slicer on 1 J. is a year of REWE
/// against the year before.
///
/// Tapping a row of a breakdown drills into it: the shop, the person or the
/// category becomes a filter chip and the page goes back to the payments. The
/// range and the metric are the page's own shared ones, so the figures here are
/// the figures on Ausgaben behind it.
class SpendExplorePage extends ConsumerStatefulWidget {
  final SpendExploreView view;

  /// The filters to open with — a ring, or a row tapped on Ausgaben's
  /// breakdown card. Each becomes a chip the reader can take off.
  final SpendCategory? category;
  final String? merchant;
  final ({String? id, String name})? member;

  /// Raise the keyboard on arrival — for the header's search button, which is
  /// a request to type.
  final bool focusSearch;

  const SpendExplorePage({
    super.key,
    this.view = SpendExploreView.all,
    this.category,
    this.merchant,
    this.member,
    this.focusSearch = false,
  });

  @override
  ConsumerState<SpendExplorePage> createState() => _SpendExplorePageState();
}

class _SpendExplorePageState extends ConsumerState<SpendExplorePage> {
  static const _searchGap = 10.0;

  late SpendExploreView _view = widget.view;

  /// Any number of categories; empty is all of them. A household asking about
  /// "food" means groceries, the bakery and the restaurant together.
  late Set<SpendCategory> _categories = {?widget.category};

  /// A shop, as the statement spells it; matched on the same case-folded key
  /// the breakdown groups by.
  late String? _merchant = widget.merchant;

  /// A person. The id is null for somebody who has left the household, whose
  /// rows are still on the record under no one.
  late ({String? id, String name})? _member = widget.member;

  String _query = '';

  final _categoryAnchor = GlobalKey();

  /// The heading of the card below the chart, which is the view picker — the
  /// same control Ausgaben's breakdown card wears, for the same reason.
  final _viewAnchor = GlobalKey();

  void _toggleCategory(SpendCategory c) => setState(() {
    _categories = _categories.contains(c) ? ({..._categories}..remove(c)) : {..._categories, c};
    _view = SpendExploreView.all;
  });

  /// Every category, from the header's glass button, **ticked on and off with
  /// the menu staying open** — the way Kalender's calendar filter works, so
  /// "groceries and the bakery" is one trip rather than two.
  ///
  /// The system menu keeps itself open on iOS 17.4 and later; anywhere it
  /// cannot, the app's own menu toggles one per opening.
  Future<void> _pickCategory() async {
    final box = _categoryAnchor.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final anchor = box.localToGlobal(Offset.zero) & box.size;

    // Read off the field rather than a copy, for the same reason Kalender
    // does: a tick is pushed back to the open menu before any rebuild.
    List<bool> states() => [for (final c in SpendCategory.values) _categories.contains(c)];

    final initial = states();
    final picked = await showNativeMenu(
      anchor: anchor,
      title: L.s.spendCategory,
      options: [
        for (final (i, c) in SpendCategory.values.indexed)
          NativeMenuOption(
            c.label,
            // The category's donut colour, which is what the ring below
            // calls it.
            color: AppSpendColors.forCategory(c.index),
            selected: initial[i],
            keepsOpen: true,
          ),
      ],
      cancelLabel: L.s.cancel,
      dark: AppColors.isDark,
      onKeptOpen: (index) {
        _toggleCategory(SpendCategory.values[index]);
        updateNativeMenuSelection(states());
      },
    );
    if (picked != null || !mounted) return;

    await showAnchoredMenuAt(
      context: context,
      anchor: anchor,
      title: L.s.spendCategory,
      items: [
        for (final c in SpendCategory.values)
          AnchoredMenuItem(
            label: c.label,
            icon: c.icon,
            selected: _categories.contains(c),
            onSelected: () => _toggleCategory(c),
          ),
      ],
    );
  }

  /// Which of the four cuts the card below the chart is showing.
  ///
  /// **The heading is the control, and the pill it replaced is gone.** Four
  /// segments across a phone spent a full row saying "there are four of
  /// these" and had to abbreviate all four to fit; the card underneath then
  /// printed a heading of its own saying the same thing in different words.
  /// One heading that can be tapped is the pattern Ausgaben's breakdown card
  /// already set, and a reader looking for "nach Person" looks at the heading
  /// that currently says something else.
  void _pickView() => showAnchoredMenu(
    context: context,
    anchorKey: _viewAnchor,
    items: [
      for (final view in SpendExploreView.values)
        AnchoredMenuItem(
          label: view.title,
          icon: view.icon,
          symbol: view.symbol,
          selected: view == _view,
          onSelected: () => setState(() => _view = view),
        ),
    ],
  );

  bool _accepts(Spend s, Map<String, String> names, String query) {
    if (_categories.isNotEmpty && !_categories.contains(s.category)) return false;
    if (_merchant case final m? when s.merchant.trim().toLowerCase() != m.trim().toLowerCase()) return false;
    if (_member case final m? when s.payerId != m.id) return false;
    if (query.isEmpty) return true;

    // Everything a person might remember a payment by, folded the way Listen's
    // search folds — case, umlauts and accents optional.
    final haystack = foldTerm(
      [s.merchant, s.category.label, ?s.note, ?s.cardLabel, ?names[s.payerId]].join(' '),
    );
    return haystack.contains(query);
  }

  void _drill(SpendBreakdownEntry entry) => setState(() {
    _view = SpendExploreView.all;
    if (entry.category case final c?) {
      // Drilling into a row is looking at that one category.
      _categories = {c};
    } else if (entry.merchant case final m?) {
      _merchant = m;
    } else if (entry.byMember) {
      _member = (id: entry.payerId, name: entry.title);
    }
  });

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(spendProvider);
    final members = ref.watch(familyProvider).members;
    final names = {for (final m in members) m.userId: m.name};

    final query = foldTerm(_query);
    final filtered = _categories.isNotEmpty || _merchant != null || _member != null || query.isNotEmpty;
    final rows = filtered
        ? [
            for (final s in state.spends)
              if (_accepts(s, names, query)) s,
          ]
        : state.spends;
    final summary = summariseRange(rows, state.range, metric: state.metric);

    // A budget is about one category, so the budget card and the budget line on the
    // chart appear only while exactly one is picked. Two budgets added together
    // would be a promise nobody made.
    final category = _categories.length == 1 ? _categories.first : null;
    final progress = category == null
        ? null
        : state.budgetProgress.where((p) => p.budget.category == category).firstOrNull;

    final title =
        _member?.name ??
        _merchant ??
        category?.label ??
        (_categories.isEmpty ? L.s.spendTitle : L.s.spendViewCategories);
    final hasChips = _categories.isNotEmpty || _merchant != null || _member != null;

    // Parked above the keyboard by hand, as on Settings: resizing the Scaffold
    // would re-measure the collapsing header mid-animation.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.surface,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: CollapsingHeaderScreen(
              titleRowBuilder: (context, t) => CollapsingScreenTitle(
                title: title,
                t: t,
                expandedAlignment: Alignment.center,
                expandedFontSize: AppText.headerCollapsed,
                leading: GlassIconButton(icon: AppIcons.caretLeft, onTap: () => Navigator.of(context).pop()),
                leadingWidth: 48,
                // Picks categories, and is always there: a chip's X takes one
                // away, and this is where one comes back or another is added.
                // Keyed so the system menu can stand beside the button.
                trailing: KeyedSubtree(
                  key: _categoryAnchor,
                  child: GlassIconButton(
                    icon: AppIcons.shapes,
                    label: L.s.spendCategory,
                    onTap: _pickCategory,
                  ),
                ),
                trailingWidth: 48,
              ),
              // The active filters live in the header, under the title that
              // names them, rather than as the first row of the panel: the
              // header had room to spare, and a chip there reads as what the
              // page *is* rather than as one more card to scroll past. First
              // frame only — the block measures itself once laid out.
              estimatedExtraHeight: hasChips ? 64 : 1,
              // Sideways only. The header measures the block *inside* this
              // padding, so vertical padding here is never counted in its
              // height and the chip's bottom edge was clipped; the gaps go
              // inside the block instead.
              extraPadding: const EdgeInsets.symmetric(horizontal: 16),
              extra: !hasChips
                  // One point, not nothing: a header whose block measures zero
                  // keeps `bareTitleHeadroom` (44) under the title for a large
                  // title to shrink over, and this title is already nav-bar
                  // sized — so an empty block left a band of nothing above the
                  // panel once the last chip went.
                  ? const SizedBox(height: 1)
                  // Full width, or the loose header slot centres a short row.
                  : Container(
                      width: double.infinity,
                      // Clear of the back button above, and of the panel's
                      // rounded top below.
                      padding: const EdgeInsets.only(top: 24, bottom: 6),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          // In the enum's order rather than the order they were
                          // picked, so the row does not reshuffle as it grows.
                          for (final c in SpendCategory.values)
                            if (_categories.contains(c))
                              _FilterChip(label: c.label, icon: c.icon, onRemove: () => _toggleCategory(c)),
                          if (_merchant case final m?)
                            _FilterChip(
                              label: m,
                              icon: AppIcons.storefront,
                              onRemove: () => setState(() => _merchant = null),
                            ),
                          if (_member case final m?)
                            _FilterChip(
                              label: m.name,
                              icon: AppIcons.user,
                              onRemove: () => setState(() => _member = null),
                            ),
                        ],
                      ),
                    ),
              body: ScreenBodyPanel(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(16, 18, 16, safeBottom + kNativeSearchFieldHeight + 28),
                  children: [
                    if (category != null) ...[
                      SpendBudgetCard(category: category, progress: progress),
                      const SizedBox(height: AppSpacing.blockGap),
                    ],

                    // Keyed for the same reason as on Ausgaben: the chips and the
                    // budget card above it come and go, and an unkeyed card would
                    // lose its pager page and its slicer's thumb each time.
                    SpendAnalysisCard(
                      key: const ValueKey('analysis'),
                      summary: summary,
                      budgetCents: progress?.budget.amountCents,
                    ),
                    const SizedBox(height: AppSpacing.blockGap),

                    _content(summary, members),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: (keyboard > 0 ? keyboard : safeBottom) + _searchGap,
            child: NativeSearchField(
              placeholder: L.s.spendSearchPlaceholder,
              autofocus: widget.focusSearch,
              onChanged: (v) {
                if (v != _query) setState(() => _query = v);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(SpendSummary summary, List<HouseholdMember> members) {
    // The picker stays reachable on an empty search too: the four cuts are how
    // somebody gets *away* from a filter that found nothing.
    if (summary.isEmpty) {
      return SpendCard(
        title: _view.title,
        titleKey: _viewAnchor,
        onTitleTap: _pickView,
        child: Text(L.s.spendNoMatches, style: AppText.body.copyWith(color: AppColors.inkSecondary)),
      );
    }

    final currency = spendCurrency(summary.rows);

    final grouping = _view.grouping;
    if (grouping == null) {
      return SpendCard(
        title: _view.title,
        titleKey: _viewAnchor,
        onTitleTap: _pickView,
        bleedChild: true,
        // No link here: this page *is* the rest of them. The count keeps the
        // slot the link takes on Ausgaben.
        trailing: Text(
          L.s.spendCountShort(summary.rows.length),
          style: AppText.body.copyWith(color: AppColors.inkSecondary),
        ),
        // The whole point of the foot on this page: a filter is on, the list
        // is long, and the figure it adds up to is a screen above.
        footer: SpendTotalRow(cents: summary.totalCents, currency: currency),
        child: Column(children: [for (final spend in summary.rows) SpendRow(spend: spend)]),
      );
    }

    return SpendCard(
      title: _view.title,
      titleKey: _viewAnchor,
      onTitleTap: _pickView,
      footer: SpendTotalRow(cents: summary.totalCents, currency: currency),
      child: Column(
        children: [
          for (final entry in spendBreakdownRows(summary, grouping, members))
            SpendBreakdownRow(row: entry, currency: currency, onTap: () => _drill(entry)),
        ],
      ),
    );
  }
}

/// One active filter, and the X that takes it off.
class _FilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onRemove;

  const _FilterChip({required this.label, required this.icon, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label, ${L.s.spendClearFilter}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onRemove,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
          // The header's own grey, not a card: it sits on the frosted header
          // now, where a white card with a shadow would float.
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadii.bar),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(icon, size: AppGlyph.inline, color: AppColors.ink),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(label, style: AppText.buttonSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 6),
              AppIcon(AppIcons.x, size: AppGlyph.inline, flat: true, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
