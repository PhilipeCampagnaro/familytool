import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/spend_analysis.dart';
import '../l10n/l10n.dart';
import '../models/spend.dart';
import '../state/family_state.dart';
import '../state/spend_state.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import '../widgets/anchored_menu.dart';
import '../widgets/app_sheet.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/collapsing_header.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_note.dart';
import '../widgets/glass.dart';
import '../widgets/rolling_number.dart';
import '../widgets/segmented_control.dart';
import '../widgets/settings_chrome.dart';
import '../widgets/step_dots.dart';
import '../widgets/swipe_actions.dart';
import '../widgets/toast_chip.dart';
import 'settings/wallet_capture_page.dart';
import 'spend/spend_charts.dart';
import 'spend/spend_breakdown.dart';
import 'spend/spend_island.dart';
import 'spend/spend_mark.dart';
import 'spend/spend_sheets.dart';

/// **Ausgaben** — a stretch of the household's spending, and what it adds up to.
///
/// Two ways in and one table behind them. An Apple Pay payment arrives on its
/// own, filed by an App Intent a Personal Automation woke on a locked phone
/// (`ios/Runner/SpendAppIntent.swift`); everything the automation cannot see —
/// cash, a physical card, a browser checkout, a bank transfer — is typed in.
/// **Manual entry is not the fallback here**, it is half the feature: Apple Pay
/// is a slice of how a German household actually pays, and a page that only
/// counted taps would quietly under-report the month and be worse than useless
/// for deciding anything.
///
/// The page is admin-only, and that is enforced in the database rather than
/// here — `spends_select` names `private.is_admin()`. The check in [build] is
/// so a member sees a sentence instead of an empty month they would read as
/// "nobody spent anything".
class SpendScreen extends ConsumerWidget {
  const SpendScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(spendProvider);
    final isAdmin = ref.watch(isAdminProvider);

    if (!isAdmin) {
      return _Shell(
        ref: ref,
        showAdd: false,
        body: [
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: EmptyState(icon: AppIcons.lock, message: L.s.spendAdminsOnly),
          ),
        ],
      );
    }

    final summary = state.summary;

    return _Shell(
      ref: ref,
      showAdd: true,
      showIsland: true,
      body: [
        if (state.error case final message?) ...[
          ErrorNote(message: message, onRetry: () => ref.read(spendProvider.notifier).load()),
          const SizedBox(height: AppSpacing.blockGap),
        ],

        // The rows the island is offering to show, when it has been asked. It
        // is above the analysis because a payment nobody could read is the one
        // thing on this page asking for something rather than telling you
        // something.
        if (summary.needsReview.isNotEmpty)
          _ReviewDrawer(key: const ValueKey('review'), rows: summary.needsReview),

        // The analysis, and it is drawn even on an empty stretch: the range
        // slicer inside it is how somebody gets *to* a stretch with money in
        // it, and an empty state that swallows the controls is an empty state
        // you cannot leave.
        // **Keyed, and the key is load-bearing.** The rows above it come and
        // go with the range — a wider stretch can turn up a payment to review
        // where the narrower one had none — and an unkeyed child that changes
        // position in this list is matched against the widget that used to be
        // there, which throws its state away. That state is the chart the pager
        // is on and the thumb's place in the range slicer, so a week-to-month
        // tap snapped the thumb across instead of sliding it and put the pager
        // back on the first chart.
        _AnalysisBlock(key: const ValueKey('analysis'), state: state),
        const SizedBox(height: AppSpacing.blockGap),

        if (state.loading && state.spends.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (summary.isEmpty)
          _EmptyRange(enrolled: state.thisDeviceEnrolled)
        else ...[
          _BreakdownCard(summary: summary),
          const SizedBox(height: AppSpacing.blockGap),
          _TransactionList(rows: summary.rows),
        ],

        // The way through to Apple Pay capture — one row, only while this phone
        // is not set up, leading to the Settings page that holds the switch,
        // the steps and the household's other phones. Last, because it is setup
        // rather than content. It carries its own gap, so a hidden one leaves
        // no space behind.
        WalletSetupCard(),
      ],
    );
  }
}

/// The collapsing header every screen but Kalender shares, with [SpendIsland]
/// as its collapsing block.
///
/// The month used to live there as a swipeable block with its own total and a
/// row of dots. What sits there now is one sentence about the money — the same
/// slot Home gives its day and Kalender its month name — because that block is
/// the place a screen says what is going on, and a second row of figures above
/// the card that already prints them would have been a dashboard on top of a
/// dashboard.
class _Shell extends StatelessWidget {
  /// The same 48 Home's `_WeekView` gives its own island — a sentence over the
  /// noun it counts needs eight points more than the 40 a single line takes,
  /// and the two screens must not put the same widget at two different heights.
  static const _islandRowHeight = 48.0;

  /// And the same 16 Home leaves between its title row and that row. The
  /// collapsing block starts flush under the title row here, where Home's sits
  /// inside a padding of its own, which is the whole of why the two islands did
  /// not line up.
  static const _islandRowTop = 16.0;

  final WidgetRef ref;
  final bool showAdd;
  final List<Widget> body;

  /// False on the page a member sees, which has no rows to say anything about.
  final bool showIsland;

  /// [GlassIconGroup.width] for two actions plus the gap the title keeps from
  /// it — the same 100 Kalender's header reserves for its pair.
  static const _groupWidth = 100.0;

  /// Whether there is a capture page to lead to. `SpendScreen` only ships where
  /// there is, so this is the belt to that braces, as in [WalletSetupCard].
  bool get _hasWallet => ref.read(spendIntentsProvider).isSupported;

  const _Shell({
    required this.ref,
    required this.showAdd,
    required this.body,
    this.showIsland = false,
  });

  @override
  Widget build(BuildContext context) {
    return CollapsingHeaderScreen(
      titleRowBuilder: (context, t) => CollapsingScreenTitle(
        title: L.s.spendTitle,
        t: t,
        trailingWidth: showAdd && _hasWallet ? _groupWidth : 48,
        trailing: !showAdd
            ? null
            : _hasWallet
            // Kalender's pair: the setup place beside the daily verb, in one
            // glass capsule. The wallet opens the page that holds the switch,
            // the steps and the household's phones — the same page the card at
            // the bottom leads to while this phone is not set up yet.
            ? GlassIconGroup(
                actions: [
                  GlassIconAction(
                    icon: AppIcons.wallet,
                    label: ref.read(spendIntentsProvider).usesNotificationAccess
                        ? L.s.settingsWalletCapture
                        : L.s.settingsApplePay,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => WalletCapturePage(parentTitle: L.s.spendTitle),
                      ),
                    ),
                  ),
                  GlassIconAction(
                    icon: AppIcons.plus,
                    label: L.s.spendAdd,
                    onTap: () => showSpendSheet(context, ref),
                  ),
                ],
              )
            : GlassIconButton(
                icon: AppIcons.plus,
                onTap: () => showSpendSheet(context, ref),
              ),
      ),
      // First frame only — the block re-measures itself once laid out, and a
      // constant here would clip it on a phone with large text. See
      // docs/design-system.md.
      estimatedExtraHeight: showIsland ? _islandRowTop + _islandRowHeight : 0,
      // The island gets the same slot it has on Home: a fixed 48-point row that
      // centres it, and the row's whole width rather than what it asks for —
      // a child measured against infinity cannot ellipsise, and the sentence
      // can be holding a category's name. Not `const`, because the island
      // reads the palette in its own build; see `tool/check_const_palette.dart`.
      extra: showIsland
          ? Padding(
              padding: const EdgeInsets.only(top: _islandRowTop),
              child: SizedBox(
                height: _islandRowHeight,
                child: Row(children: [Expanded(child: SpendIsland())]),
              ),
            )
          : const SizedBox.shrink(),
      body: ScreenBodyPanel(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.screenPad,
            AppSpacing.blockGap,
            AppSpacing.screenPad,
            navContentInset(context),
          ),
          children: body,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The analysis
// ---------------------------------------------------------------------------

/// The card: the total, the drawing, which of the three it is, and which
/// stretch of time it is all about.
///
/// **The three charts are swiped, not tapped.** A pill of three glyphs was a
/// second control stacked above the range slicer, which is forty points of a
/// phone spent saying "there are three of these" — and the glyphs had to be
/// learned before they meant anything. A row of dots says the same thing in six
/// points and names the gesture the phone already taught, the same mark and the
/// same reasoning as the month pager this page used to carry.
///
/// Which chart is local state and the range is not: the range decides what is
/// fetched and what every card below this one counts, so it lives in the
/// notifier; the chart is three ways of looking at rows already in hand and
/// nothing outside this card cares which one is showing.
class _AnalysisBlock extends StatefulWidget {
  final SpendState state;

  const _AnalysisBlock({super.key, required this.state});

  @override
  State<_AnalysisBlock> createState() => _AnalysisBlockState();
}

class _AnalysisBlockState extends State<_AnalysisBlock> {
  final _pages = PageController();
  SpendChart _chart = SpendChart.trend;

  /// Which bucket the chart is being read at, if one is. See [ChartScrub] — on
  /// the bars and on the line alike it is a choice that stays put, made by a
  /// tap or by the end of a slide.
  int? _scrub;

  /// A reading belongs to the drawing it was taken off, and a range or metric
  /// change is a different drawing. It matters because a picked bucket stays
  /// picked: without this, tapping the slicer would leave the fifth bucket of
  /// last week lit up as the fifth bucket of last year.
  @override
  void didUpdateWidget(_AnalysisBlock old) {
    super.didUpdateWidget(old);
    if (old.state.summary.range != widget.state.summary.range ||
        old.state.summary.metric != widget.state.summary.metric) {
      _scrub = null;
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// What the headline says instead of the range's total while the chart is
  /// being read.
  ///
  /// The bounds check is not belt and braces: the range can change under a
  /// finger — a realtime row arrives, or the slicer is tapped — and an index
  /// into the buckets that were there a moment ago is the one way this can go
  /// wrong.
  ({String value, String caption})? _reading(SpendSummary summary) {
    final at = _scrub;
    if (at == null || at >= summary.buckets.length) return null;

    final bucket = summary.buckets[at];
    // The line is cumulative and the bars are not, so they answer different
    // questions at the same point: "how much by here" against "how much here".
    final cents = _chart == SpendChart.trend
        ? (at < summary.cumulative.length ? summary.cumulative[at] : summary.totalCents)
        : bucket.cents;

    return (
      value: formatMoneyShort(cents, currency: spendCurrency(summary.rows)),
      caption: bucket.caption,
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.state.summary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.cardPad),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The headline follows the page as it turns rather than after it
          // lands, because the line under the total is the chart's own caption
          // — a trend's is the gap against last time, a bar chart's is the
          // average drawn through it — and a caption that arrives late belongs
          // to the drawing that has already gone.
          _Headline(summary: summary, chart: _chart, reading: _reading(summary)),
          const SizedBox(height: 14),
          SizedBox(
            height: spendChartHeight,
            child: PageView(
              controller: _pages,
              onPageChanged: (page) => setState(() {
                _chart = SpendChart.values[page];
                // A reading belongs to the drawing it was taken off.
                _scrub = null;
              }),
              children: [
                for (final chart in SpendChart.values)
                  Semantics(
                    // Three unnamed pictures with a row of dots under them, to
                    // anybody not looking at them.
                    label: chart.label,
                    // **The old drawing leaves while the new one arrives.** The
                    // reveal inside each chart sweeps it on from the left; on
                    // its own that leaves the picture it replaced disappearing
                    // a frame earlier, which is the blink the sweep was for.
                    // The key is the range and the metric — the two things that
                    // change what is being drawn — so turning the pager and
                    // dragging a finger across a chart go on rebuilding the
                    // same element and leave it alone.
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeOut,
                      layoutBuilder: (current, previous) => Stack(
                        fit: StackFit.expand,
                        children: [...previous, ?current],
                      ),
                      child: KeyedSubtree(
                        key: ValueKey((summary.range, summary.metric, chart)),
                        child: switch (chart) {
                          SpendChart.trend => SpendTrendChart(
                            summary: summary,
                            scrub: _scrub,
                            onScrub: (at) => setState(() => _scrub = at),
                          ),
                          SpendChart.bars => SpendBarsChart(
                            summary: summary,
                            scrub: _scrub,
                            onScrub: (at) => setState(() => _scrub = at),
                          ),
                          SpendChart.ring => _RingView(summary: summary),
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          StepDots(count: SpendChart.values.length, index: _chart.index),
          const SizedBox(height: 16),
          _RangeSlicer(range: widget.state.range),
        ],
      ),
    );
  }
}

/// The total, what it is, and the one line that qualifies it.
///
/// Left-aligned and stacked, because the eye reads down a left edge: the label
/// says what is being counted, the figure answers it, and the line underneath
/// says against what.
class _Headline extends StatelessWidget {
  final SpendSummary summary;
  final SpendChart chart;

  /// What the chart is being asked about right now, while a finger is on it —
  /// see [ChartScrub]. The headline is where a reading goes: the alternative is
  /// a bubble following the finger, which covers the very stretch of chart the
  /// reader is dragging along.
  final ({String value, String caption})? reading;

  const _Headline({required this.summary, required this.chart, this.reading});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              // Scaled down rather than cut off: this figure is the answer the
              // whole card is for, and an ellipsis in the middle of an amount
              // is worse than a smaller amount.
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: _Figure(
                    reading: reading?.value,
                    total: formatMoneyShort(
                      summary.totalCents,
                      currency: spendCurrency(summary.rows),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Beside the figure rather than above it. It is still the total's
            // label — swapping it changes what the number means — and reading
            // "1.234 €" and "Extras" on one line says that as plainly as
            // stacking them did, in one row of a card instead of two.
            _MetricChip(metric: summary.metric),
          ],
        ),
        const SizedBox(height: 4),
        if (reading case final at?)
          // The date, and nothing else. The line under the total normally says
          // what the figure is being measured against, and none of those
          // comparisons is true of one day picked out of the middle.
          Text(
            at.caption,
            style: AppText.body.copyWith(color: AppColors.inkSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          )
        else
          _ContextLine(summary: summary, chart: chart),
      ],
    );
  }
}

/// The card's big figure: the range's total, or the one bucket the reader has
/// picked off the chart.
///
/// **The digits roll for the slicer and the chart's readings are simply set**,
/// because the two are asking different things. Changing the range or the
/// metric asks the same question of a longer stretch, so the figure that
/// answers it is the *same quantity* moving — which is the whole of what a
/// rolling column says, and only the digits that changed move. Picking a bar
/// asks about one day instead: 1.234 € and 87 € are two readings rather than
/// one number that changed, and every way of animating between them says
/// otherwise. Rolling invents a relationship they do not have, a cross-fade
/// leaves both legible at once and neither for long, and a slide puts motion
/// under a finger that is already moving. What is left is the figure changing
/// the instant the bar is tapped, which is what a readout does.
///
/// There is no switcher here and that is the mechanism, not an omission. While
/// the headline is on the total it is one [RollingNumber] that stays put across
/// slicer taps, so its columns roll; a reading replaces it with plain text, and
/// coming back builds it afresh — and a `RollingNumber` appearing for the first
/// time sets itself rather than rolling, there being nothing for it to have
/// come from.
class _Figure extends StatelessWidget {
  /// The picked bucket's figure, or null when the headline is back on the
  /// range's total.
  final String? reading;
  final String total;

  const _Figure({required this.reading, required this.total});

  @override
  Widget build(BuildContext context) {
    return switch (reading) {
      final at? => Text(at, style: AppText.screenTitle, maxLines: 1),
      null => RollingNumber(value: total, style: AppText.screenTitle),
    };
  }
}

/// "▲ 12.868 € · Dieses Jahr", or "Durchschn. 12.215 € pro Monat · Dieses Jahr".
///
/// Which one depends on the chart, because it is the chart's own caption: the
/// line is a race against the stretch before, so it prints the gap between
/// them; the bars are a distribution, so they print the average that is drawn
/// through them.
class _ContextLine extends StatelessWidget {
  final SpendSummary summary;
  final SpendChart chart;

  const _ContextLine({required this.summary, required this.chart});

  @override
  Widget build(BuildContext context) {
    final caption = Text(
      summary.range.caption,
      style: AppText.body.copyWith(color: AppColors.inkSecondary),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    final lead = switch (chart) {
      SpendChart.trend => _change(),
      SpendChart.bars => _average(),
      // The ring says it in its own hole.
      SpendChart.ring => null,
    };

    if (lead == null) return caption;

    return Row(
      children: [
        lead,
        Text(' · ', style: AppText.body.copyWith(color: AppColors.inkSecondary)),
        Flexible(child: caption),
      ],
    );
  }

  /// The gap in euros rather than in percent. A household reads "€12.868 mehr"
  /// faster than "+15 %", and on a stretch with nothing behind it there is
  /// nothing honest to print at all.
  Widget? _change() {
    final change = summary.changeCents;
    if (change == null || change == 0) return null;

    final up = change > 0;
    // Up is the danger colour and down is the good one, which is the one place
    // in the app where a rising number is the bad news.
    final color = up ? AppColors.danger : AppColors.success;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Carets rather than arrows: the set has no `arrowDown`, and a caret
        // pair is the mark a reader already knows means up and down.
        AppIcon(up ? AppIcons.caretUp : AppIcons.caretDown, size: AppGlyph.inline, flat: true, color: color),
        const SizedBox(width: 4),
        Text(
          formatMoneyShort(change.abs(), currency: spendCurrency(summary.rows)),
          style: AppText.body.copyWith(color: color),
        ),
      ],
    );
  }

  Widget _average() {
    final amount = formatMoneyShort(summary.averagePerUnitCents, currency: spendCurrency(summary.rows));
    final text = summary.range.unit == SpendBucketUnit.day
        ? L.s.spendAveragePerDay(amount)
        : L.s.spendAveragePerMonth(amount);

    return Flexible(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Ink, to match the dashed rule it is describing — which is ink
          // because the bars under it are now the accent.
          AppIcon(AppIcons.chartBar, size: AppGlyph.inline, flat: true, color: AppColors.ink),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              style: AppText.body.copyWith(color: AppColors.ink),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// The ring, with how many payments made it in the hole — or, once an arc has
/// been tapped, what that arc is.
///
/// **The total is not in there any more.** It sits in the headline above, where
/// the other two views put it — one figure, in one place, whichever drawing is
/// on screen — and repeating it inside the donut would be the same number twice
/// eighty points apart. The hole keeps the count, which is the thing the ring
/// itself cannot show: five arcs say how the money split and nothing about how
/// many payments it took.
///
/// **And the hole is where a tapped arc answers.** A slice of a donut is a
/// shape with no words on it; tapping one has to say which category it was and
/// what it came to, and the hole is already the middle of what the finger is
/// pointing at. A second tap on the same arc puts it back.
class _RingView extends StatefulWidget {
  final SpendSummary summary;

  const _RingView({required this.summary});

  @override
  State<_RingView> createState() => _RingViewState();
}

class _RingViewState extends State<_RingView> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    final slices = ringSlices(summary);
    // The range can change under a selection — the slicer is right below — and
    // an index into the arcs that were there a moment ago is the one way this
    // goes wrong.
    final at = _selected != null && _selected! < slices.length ? slices[_selected!] : null;

    return Center(
      child: SpendCategoryRing(
        summary: summary,
        // Exactly the height the other two are drawn at, so nothing in the
        // card moves as the pages are turned.
        size: spendChartHeight,
        selected: at == null ? null : _selected,
        onTapSlice: (index) => setState(() => _selected = index),
        center: at == null
            ? _RingHole(
                label: L.s.spendPaymentsWord(summary.transactionCount),
                value: '${summary.transactionCount}',
              )
            : _RingHole(
                label: at.label,
                value: formatMoneyShort(at.cents, currency: spendCurrency(summary.rows)),
                footnote: L.s.percent((at.share * 100).round()),
                // The arc's own colour, and the one place on this page a slice
                // colour appears as text: it is what joins the words in the
                // hole to the band they came off.
                footnoteColor: at.color,
              ),
      ),
    );
  }
}

/// What the hole says, in both of its states: the name of the thing on top and
/// the figure answering it underneath.
///
/// **One shape for both, because a tap should change the answer and not the
/// furniture.** The hole used to print "27 Zahlungen" on one line and then, on
/// a tap, rearrange itself into a label over an amount — so the first thing
/// that moved was the layout rather than the reading. Set the same way round,
/// the count and a category read as two answers to the same question, which is
/// what they are.
class _RingHole extends StatelessWidget {
  final String label;
  final String value;

  /// The share, on the selected state only. Nothing qualifies a plain count.
  final String? footnote;
  final Color? footnoteColor;

  const _RingHole({
    required this.label,
    required this.value,
    this.footnote,
    this.footnoteColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppText.body.copyWith(color: AppColors.inkSecondary),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        // Scaled down rather than ellipsised: a long category name may wrap,
        // but a figure with its end cut off is worse than a small figure.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value, style: AppText.cardTitle, maxLines: 1),
        ),
        if (footnote case final share?) ...[
          const SizedBox(height: 1),
          Text(share, style: AppText.body.copyWith(color: footnoteColor, fontSize: 12)),
        ],
      ],
    );
  }
}

/// What is being counted, and the control that changes it.
///
/// It sits where the total's label would, because it *is* the total's label:
/// swapping it changes what every figure on the page means. A filter parked
/// somewhere else would leave the headline saying "Ausgaben" over a number that
/// is only the fixed ones.
class _MetricChip extends ConsumerStatefulWidget {
  final SpendMetric metric;

  const _MetricChip({required this.metric});

  @override
  ConsumerState<_MetricChip> createState() => _MetricChipState();
}

class _MetricChipState extends ConsumerState<_MetricChip> {
  final _anchor = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(spendProvider.notifier);

    return GestureDetector(
      key: _anchor,
      onTap: () => showAnchoredMenu(
        context: context,
        anchorKey: _anchor,
        items: [
          for (final metric in SpendMetric.values)
            AnchoredMenuItem(
              label: metric.label,
              icon: switch (metric) {
                SpendMetric.all => AppIcons.money,
                SpendMetric.budget => AppIcons.repeat,
                SpendMetric.extra => AppIcons.sparkle,
              },
              symbol: switch (metric) {
                SpendMetric.all => 'eurosign.circle',
                SpendMetric.budget => 'repeat',
                SpendMetric.extra => 'sparkles',
              },
              selected: metric == widget.metric,
              onSelected: () => notifier.showMetric(metric),
            ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(11, 5, 8, 5),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.metric.label, style: AppText.buttonSmall.copyWith(color: AppColors.inkSecondary)),
            const SizedBox(width: 4),
            AppIcon(AppIcons.caretUpDown, size: AppGlyph.inline, flat: true, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

/// The four spans, and the calendar that goes anywhere else.
///
/// The button is beside the pill rather than a fifth segment because it is not
/// one of the four: it opens a picker and comes back with something the pill
/// cannot show. When it does, no segment is lit — which is the honest state,
/// and the reason the pill's thumb is allowed to match nothing.
class _RangeSlicer extends ConsumerStatefulWidget {
  final SpendRange range;

  const _RangeSlicer({required this.range});

  @override
  ConsumerState<_RangeSlicer> createState() => _RangeSlicerState();
}

class _RangeSlicerState extends ConsumerState<_RangeSlicer> {
  Future<void> _pick() async {
    final notifier = ref.read(spendProvider.notifier);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final picked = await showDateRangePicker(
      context: context,
      // Three years back covers every question a household asks of its own
      // record, and tomorrow is not a day anybody has spent yet.
      firstDate: DateTime(today.year - 3),
      lastDate: today,
      initialDateRange: DateTimeRange(
        start: widget.range.from,
        end: widget.range.lastDay.isAfter(today) ? today : widget.range.lastDay,
      ),
      helpText: L.s.spendRangePick,
    );

    if (picked == null) return;
    await notifier.showRange(SpendRange.custom(picked.start, picked.end));
  }

  @override
  Widget build(BuildContext context) {
    final custom = widget.range.period == SpendPeriod.custom;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SegmentedControl<SpendPeriod>(
              pill: true,
              value: widget.range.period,
              onChanged: (period) => ref.read(spendProvider.notifier).showPeriod(period),
              options: [
                for (final period in const [
                  SpendPeriod.week,
                  SpendPeriod.month,
                  SpendPeriod.halfYear,
                  SpendPeriod.year,
                ])
                  SegmentedOption(value: period, label: period.shortLabel),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _pick,
            child: Semantics(
              button: true,
              selected: custom,
              label: L.s.spendRangePick,
              child: Container(
                width: 52,
                decoration: BoxDecoration(
                  // Lit while a picked range is the one in force, because
                  // nothing else on the row is: the pill has no thumb to give.
                  color: custom ? AppColors.accent.withValues(alpha: .12) : AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Center(
                  child: AppIcon(
                    AppIcons.calendarDots,
                    size: AppGlyph.row,
                    flat: true,
                    color: custom ? AppColors.accent : AppColors.inkSecondary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cards
// ---------------------------------------------------------------------------

/// The shared shape every block on this page sits in.
class _Card extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  /// A tap on the title, for the one card whose heading is a picker.
  final GlobalKey? titleKey;
  final VoidCallback? onTitleTap;

  /// Runs [child] to the card's own edges, padding the heading instead. For
  /// the one card made of swipeable rows: a delete strip that stops a card's
  /// padding short of the edge reads as a floating red block rather than as
  /// the row's own action. See [_SpendRow].
  final bool bleedChild;

  const _Card({
    required this.title,
    required this.child,
    this.trailing,
    this.titleKey,
    this.onTitleTap,
    this.bleedChild = false,
  });

  @override
  Widget build(BuildContext context) {
    final heading = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(title, style: AppText.sectionHeading, maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (onTitleTap != null) ...[
          const SizedBox(width: 5),
          AppIcon(AppIcons.caretDown, size: AppGlyph.inline, flat: true, color: AppColors.muted),
        ],
      ],
    );

    final head = Row(
      children: [
        Expanded(
          child: onTitleTap == null
              ? heading
              : GestureDetector(
                  key: titleKey,
                  behavior: HitTestBehavior.opaque,
                  onTap: onTitleTap,
                  child: heading,
                ),
        ),
        ?trailing,
      ],
    );

    return Container(
      width: double.infinity,
      padding: bleedChild ? EdgeInsets.zero : const EdgeInsets.all(AppSpacing.cardPad),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: AppShadows.card,
      ),
      // Only where the child reaches the corners: an unclipped card is
      // cheaper, and it is what every other card here wants.
      clipBehavior: bleedChild ? Clip.antiAlias : Clip.none,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          bleedChild
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.cardPad,
                    AppSpacing.cardPad,
                    AppSpacing.cardPad,
                    0,
                  ),
                  child: head,
                )
              : head,
          const SizedBox(height: 14),
          child,
          if (bleedChild) const SizedBox(height: AppSpacing.cardPad),
        ],
      ),
    );
  }
}

/// The link in a card's heading that opens the page holding the rest of it.
///
/// **It is only ever drawn where there is something behind it.** "Alle
/// anzeigen" over a list that is already all of them is a promise of a page
/// with nothing new on it, which is how a reader learns to stop tapping the
/// ones that do have more.
class _ShowAll extends StatelessWidget {
  final String label;
  final Widget Function() page;

  const _ShowAll({required this.label, required this.page});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page())),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: AppText.buttonSmall.copyWith(color: AppColors.accent)),
          const SizedBox(width: 2),
          AppIcon(AppIcons.caretRight, size: AppGlyph.inline, flat: true, color: AppColors.accent),
        ],
      ),
    );
  }
}

/// Where the money went — by category, by shop, or by who paid.
///
/// **One card with a picker rather than three cards down the page.** They are
/// three answers to the same question and only ever one is being asked; stacked,
/// two of them were always scrolled past. The heading is the control, which is
/// why it carries a caret: a reader looking for "wo am meisten" looks at the
/// heading that currently says something else.
///
/// **Five rows, and "alle anzeigen" for the rest.** Five is what the ring shows
/// and the two have to agree — a card listing fourteen categories under a
/// drawing of five is a card contradicting the picture above it. The full list
/// is a page rather than a longer card, because a breakdown somebody is reading
/// properly deserves the screen, and a card that grows to forty rows buries the
/// payments under it.
class _BreakdownCard extends ConsumerStatefulWidget {
  final SpendSummary summary;

  const _BreakdownCard({required this.summary});

  @override
  ConsumerState<_BreakdownCard> createState() => _BreakdownCardState();
}

class _BreakdownCardState extends ConsumerState<_BreakdownCard> {
  final _anchor = GlobalKey();
  SpendGrouping _by = SpendGrouping.category;

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    final members = ref.watch(familyProvider).members;
    final rows = spendBreakdownRows(summary, _by, members, limit: spendBreakdownPreview);

    return _Card(
      title: _by.title,
      titleKey: _anchor,
      onTitleTap: () => showAnchoredMenu(
        context: context,
        anchorKey: _anchor,
        items: [
          for (final by in SpendGrouping.values)
            AnchoredMenuItem(
              label: by.title,
              icon: by.icon,
              symbol: by.symbol,
              selected: by == _by,
              onSelected: () => setState(() => _by = by),
            ),
        ],
      ),
      trailing: spendBreakdownRows(summary, _by, members).length <= rows.length
          ? null
          : _ShowAll(
              label: L.s.spendShowAll,
              page: () => SpendBreakdownPage(grouping: _by),
            ),
      child: Column(
        children: [
          for (final row in rows)
            SpendBreakdownRow(row: row, currency: spendCurrency(summary.rows)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The rows themselves
// ---------------------------------------------------------------------------

/// How many payments the card holds before it offers the rest on a page.
///
/// **Ten, where the breakdown takes five, because the two lists are answering
/// different questions.** Five is what the ring above the breakdown draws and
/// the card has to agree with the picture; this list has no picture to agree
/// with, and what somebody scrolling to the bottom of Ausgaben is doing is
/// scanning recent payments for one they half-remember. Ten is about a week of
/// a normal household, which is as far back as that kind of looking usually
/// goes.
const int _purchasePreview = 10;

/// The payments themselves, newest first.
///
/// **The card is the recent ones and the page is all of them.** A year selected
/// in the slicer above puts several hundred rows here, and a card that long
/// turns the rest of the page into something you scroll past on the way to the
/// tab bar — the charts, the breakdown and the wallet card included. The count
/// that used to sit in the heading is not lost: it is inside the link, because
/// a heading on a phone holds a title and one other thing.
class _TransactionList extends ConsumerWidget {
  final List<Spend> rows;

  const _TransactionList({required this.rows});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = rows.take(_purchasePreview).toList();

    return _Card(
      title: L.s.spendAllPurchases,
      bleedChild: true,
      trailing: rows.length <= shown.length
          ? Text(
              L.s.spendCountShort(rows.length),
              style: AppText.body.copyWith(color: AppColors.inkSecondary),
            )
          : _ShowAll(
              label: L.s.spendShowAllCount(rows.length),
              page: () => SpendPurchasesPage(),
            ),
      child: Column(
        children: [
          for (final spend in shown) _SpendRow(spend: spend),
        ],
      ),
    );
  }
}

/// Every payment in the selected range, on a screen of its own.
///
/// **It reads the live range rather than the list it was opened with.** The
/// slicer stays on the page behind it, so a range changed there and a page
/// showing the old rows would be two answers to one question; watching the
/// provider also means a payment deleted from a row here leaves the page
/// without the caller having to hand anything back.
class SpendPurchasesPage extends ConsumerWidget {
  const SpendPurchasesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(spendProvider).summary;
    final rows = summary.rows;

    return SettingsDetailPage(
      icon: AppIcons.receipt,
      title: L.s.spendAllPurchases,
      // The stretch and how much of it there is — the two things the card's
      // heading said between them before this page existed.
      description: '${summary.range.caption} · ${L.s.spendCountShort(rows.length)}',
      parentTitle: L.s.spendTitle,
      estimatedHeroHeight: 200,
      children: [
        SectionCard(
          radius: AppRadii.card,
          children: [
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.cardPad, vertical: 18),
                child: Text(
                  L.s.spendIslandNothing,
                  style: AppText.body.copyWith(color: AppColors.inkSecondary),
                ),
              )
            else
              // Vertical only: the rows pad themselves sideways so their
              // swipe strip reaches the card's edge. See [_SpendRow].
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    for (final spend in rows) _SpendRow(spend: spend),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// One payment, wearing the same swipe the Listen and Boxen rows wear.
///
/// **It used to delete on a long press, which is the reason this now goes
/// through [SwipeToEditDelete].** A press-and-hold is what a finger does while
/// it decides — resting on a row, scrolling a card that has stopped moving —
/// and the app answered it by taking the payment away. Nowhere else does a
/// long press do anything at all, let alone something destructive; the gesture
/// for "do something to this row" is the leftward swipe, and it shows what it
/// is about to do before the finger lifts.
///
/// The row is drawn edge to edge and carries its own horizontal padding, so
/// the revealed strip reaches the card's own corners rather than stopping
/// short of them — every container that holds one of these therefore pads
/// around it vertically only.
class _SpendRow extends ConsumerWidget {
  final Spend spend;

  const _SpendRow({required this.spend});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SwipeToEditDelete(
      identity: spend.id,
      // The detail sheet, not the form: a row that already exists opens as
      // something to read, and editing it is the pencil in that sheet's
      // header — the same two steps an appointment takes.
      onTap: () => showSpendDetailSheet(context, ref, spend),
      // The swipe is the shortcut past those two steps, so it opens the form
      // itself. Its `true` — deleted from inside — needs nothing here: there
      // is no detail sheet underneath this one to close.
      onEdit: () => showSpendSheet(context, ref, spend: spend),
      onDelete: () async {
        // Captured before the write: the row this was swiped in is the one the
        // delete unmounts.
        final confirm = confirmChipOf(context);
        final notifier = ref.read(spendProvider.notifier);
        if (await notifier.deleteSpend(spend.id) case final deleted?) {
          confirm(L.s.spendDeleted, undo: () => notifier.undoDelete(deleted));
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: AppSpacing.cardPad),
        child: Row(
          children: [
            // The shop, not its category: the row's own title is the shop,
            // and the category is already the middle word of the line under
            // it. See [SpendMark].
            SpendMark(size: AppText.rowMark, merchant: spend.merchant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          spend.merchant,
                          style: AppText.rowTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (spend.needsReview) ...[
                        const SizedBox(width: 6),
                        AppIcon(AppIcons.warning, size: 14, color: AppColors.danger),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _subtitle(spend),
                    style: AppText.body.copyWith(color: AppColors.inkSecondary, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(formatMoney(spend.amountCents, currency: spend.currency), style: AppText.rowTitle),
          ],
        ),
      ),
    );
  }

  /// Day, category, and the card where there was one — the three things that
  /// tell two payments at the same shop apart.
  String _subtitle(Spend spend) {
    final parts = [
      L.s.dayMonthShort(spend.occurredAt.day, spend.occurredAt.month),
      spend.category.label,
      ?spend.cardLabel,
    ];
    return parts.join(' · ');
  }
}

/// The rows Apple's Transaction trigger handed over with a hole in them, folded
/// out of the island above.
///
/// **There is no button here and no banner.** The banner was a bordered panel
/// that opened the page and gave the loudest block on the screen to the rarest
/// thing on it; the button that replaced it said the same sentence the island
/// was already saying two rows higher. The island is the notice, the same way
/// Home's first-steps line is the notice and `FirstStepsCard` is only what
/// unfolds from it — so this draws nothing at all until it is asked for.
class _ReviewDrawer extends ConsumerWidget {
  final List<Spend> rows;

  const _ReviewDrawer({super.key, required this.rows});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(spendReviewOpenProvider);

    // AnimatedCrossFade rather than `if (open)`: it keeps both states around so
    // the card sizes *and* fades in both directions — see the expand/collapse
    // rule in docs/design-system.md.
    return AnimatedCrossFade(
      firstChild: const SizedBox(width: double.infinity),
      secondChild: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.blockGap),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.card),
            boxShadow: AppShadows.card,
          ),
          // The rows run to the card's edge, so the card clips its own corners
          // rather than letting a revealed delete strip square them off.
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.cardPad,
                  AppSpacing.cardPad,
                  AppSpacing.cardPad,
                  8,
                ),
                child: Text(
                  L.s.spendReviewBody,
                  style: AppText.body.copyWith(color: AppColors.inkSecondary),
                ),
              ),
              for (final spend in rows) _SpendRow(spend: spend),
              const SizedBox(height: AppSpacing.cardPad),
            ],
          ),
        ),
      ),
      crossFadeState: open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
      duration: const Duration(milliseconds: 200),
      sizeCurve: Curves.easeOutCubic,
      firstCurve: Curves.easeOut,
      secondCurve: Curves.easeIn,
      alignment: Alignment.topCenter,
    );
  }
}

class _EmptyRange extends StatelessWidget {
  final bool enrolled;

  const _EmptyRange({required this.enrolled});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: EmptyState(
        icon: AppIcons.receipt,
        message: enrolled ? L.s.spendEmptyEnrolled : L.s.spendEmpty,
      ),
    );
  }
}
