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
import '../widgets/toast_chip.dart';
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
          _ReviewDrawer(rows: summary.needsReview),

        // The analysis, and it is drawn even on an empty stretch: the range
        // slicer inside it is how somebody gets *to* a stretch with money in
        // it, and an empty state that swallows the controls is an empty state
        // you cannot leave.
        _AnalysisBlock(state: state),
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

        // The way through to Apple Pay capture — one row saying whether this
        // iPhone files payments by itself, leading to the Settings page that
        // holds the switch, the steps and the household's other phones. Last,
        // because it is setup rather than content, and present even on a full
        // month, since a second parent's phone is enrolled long after the
        // first one's.
        const SizedBox(height: AppSpacing.blockGap),
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
        trailingWidth: 48,
        trailing: showAdd
            ? GlassIconButton(
                icon: AppIcons.plus,
                onTap: () => showSpendSheet(context, ref),
              )
            : null,
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

  const _AnalysisBlock({required this.state});

  @override
  State<_AnalysisBlock> createState() => _AnalysisBlockState();
}

class _AnalysisBlockState extends State<_AnalysisBlock> {
  final _pages = PageController();
  SpendChart _chart = SpendChart.trend;

  /// Which bucket a finger is holding on the chart, if one is. See
  /// [ChartScrub].
  int? _scrub;

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
                  child: RollingNumber(
                    value: reading?.value ??
                        formatMoneyShort(summary.totalCents, currency: spendCurrency(summary.rows)),
                    style: AppText.screenTitle,
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
        AppIcon(up ? AppIcons.caretUp : AppIcons.caretDown, size: 12, flat: true, color: color),
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
          AppIcon(AppIcons.chartBar, size: 13, flat: true, color: AppColors.ink),
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
            AppIcon(AppIcons.caretUpDown, size: 12, flat: true, color: AppColors.muted),
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
                    size: 18,
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

  const _Card({
    required this.title,
    required this.child,
    this.trailing,
    this.titleKey,
    this.onTitleTap,
  });

  @override
  Widget build(BuildContext context) {
    final heading = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(title, style: AppText.sectionHeading, maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (onTitleTap != null) ...[
          const SizedBox(width: 5),
          AppIcon(AppIcons.caretDown, size: 13, flat: true, color: AppColors.muted),
        ],
      ],
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.cardPad),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
          ),
          const SizedBox(height: 14),
          child,
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
          AppIcon(AppIcons.caretRight, size: 13, flat: true, color: AppColors.accent),
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.cardPad, vertical: 6),
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

class _SpendRow extends ConsumerWidget {
  final Spend spend;

  const _SpendRow({required this.spend});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      // The detail sheet, not the form: a row that already exists opens as
      // something to read, and editing it is the pencil in that sheet's
      // header — the same two steps an appointment takes.
      onTap: () => showSpendDetailSheet(context, ref, spend),
      onLongPress: () async {
        // Captured before the write: the row this was tapped in is the one the
        // delete unmounts.
        final confirm = confirmChipOf(context);
        final notifier = ref.read(spendProvider.notifier);
        if (await notifier.deleteSpend(spend.id) case final deleted?) {
          confirm(L.s.spendDeleted, undo: () => notifier.undoDelete(deleted));
        }
      },
      borderRadius: BorderRadius.circular(AppRadii.cardSmall),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            // The shop, not its category: the row's own title is the shop,
            // and the category is already the middle word of the line under
            // it. See [SpendMark].
            SpendMark(size: 34, merchant: spend.merchant),
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

  const _ReviewDrawer({required this.rows});

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
          padding: const EdgeInsets.all(AppSpacing.cardPad),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.card),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                L.s.spendReviewBody,
                style: AppText.body.copyWith(color: AppColors.inkSecondary),
              ),
              const SizedBox(height: 8),
              for (final spend in rows) _SpendRow(spend: spend),
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
