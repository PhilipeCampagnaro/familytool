import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/spend_state.dart';
import '../../theme/app_icons.dart';
import '../../widgets/status_island.dart';

/// Whether the flagged rows are folded out.
///
/// A provider rather than state inside a widget because the line that toggles
/// it is in the collapsing header and the rows it reveals are in the body, the
/// same split `firstStepsOpenProvider` has on Home.
final spendReviewOpenProvider = StateProvider<bool>((ref) => false);

/// **Ausgaben' one-line status**, in the collapsing block under the page title.
///
/// The same thing Home does with its day ([DayIsland]), with money in it: one
/// sentence, always the most pressing one, over a second line saying what it is
/// counting. A row of figures there would be a second dashboard directly above
/// the real one — the card below already prints the total, the trend and the
/// breakdown — so this says the thing a household would otherwise have had to
/// work out by looking.
///
/// **The cases are a ladder and the first match wins**: still working it out,
/// then the rows the automation could not read, then a range with nothing in
/// it, then a rise or a fall worth mentioning, then which category is carrying
/// the range. Only the first is about the app; every rung under it is about the
/// money.
///
/// **Every glyph is ink, and none of them is coloured.** A red warning and a
/// green fall were the obvious design and they were wrong here for the reason
/// the words are already black: this line sits directly above a card that is
/// nothing but colour — seven category hues in the ring, a red trend line, a
/// blue average — and a tinted mark above all of that reads as a fourth thing
/// competing rather than as a tone. The glyph's job is to name what the
/// sentence is about, and the sentence says whether it is good news.
class SpendIsland extends ConsumerWidget {
  const SpendIsland({super.key});

  /// Under a fifth of a period either way is noise, and an island that
  /// announced a four-percent rise every month would be an island nobody reads.
  /// It is deliberately far above the one percent the old header chip used:
  /// that chip was a caption on a figure the reader was already looking at,
  /// this is a sentence claiming something is worth knowing.
  static const _notable = 0.05;

  @override
  Widget build(BuildContext context, WidgetRef ref) => StatusIsland(child: _line(ref));

  Widget _line(WidgetRef ref) {
    final state = ref.watch(spendProvider);
    final summary = state.summary;

    // Before it can say anything it says that it is working it out. Everything
    // below is a fold over rows that arrive over the network, and printing
    // "nichts erfasst" while they are in flight is an answer that turns out to
    // be wrong a second later.
    if (state.loading && state.spends.isEmpty) {
      return IslandLine(
        key: const ValueKey('thinking'),
        icon: AppIcons.brain,
        label: L.s.spendIslandThinking,
        hint: L.s.spendIslandThinkingHint,
        // The one state that shimmers over and over: here the wave *is* the
        // spinner, and it stops the moment there is something to say.
        sweep: IslandSweep.loop,
      );
    }

    // A row the automation could not read outranks anything about the shape of
    // the money, because it is the one thing on the page asking for something
    // rather than telling you something.
    if (summary.needsReview.isNotEmpty) {
      final open = ref.watch(spendReviewOpenProvider);
      return IslandLine(
        key: const ValueKey('review'),
        icon: AppIcons.warning,
        label: L.s.spendReviewTitle(summary.needsReview.length),
        hint: L.s.spendIslandReviewHint,
        expanded: open,
        onTap: () => ref.read(spendReviewOpenProvider.notifier).state = !open,
      );
    }

    if (summary.isEmpty) {
      return IslandLine(
        key: const ValueKey('empty'),
        icon: AppIcons.receipt,
        label: L.s.spendIslandNothing,
        hint: summary.range.caption,
      );
    }

    // A change is only news against something. A first month has no previous
    // one, and a previous one of exactly zero divides into an infinity that
    // renders as a shrug — `changeVsPrevious` answers null to both.
    if (summary.changeVsPrevious case final change? when change.abs() >= _notable) {
      final percent = (change.abs() * 100).round();
      final up = change > 0;
      return IslandLine(
        key: ValueKey(up ? 'up' : 'down'),
        // **Not a caret.** A caret under a title is a disclosure mark first and
        // a direction second, and this island really does expand on the review
        // rung directly above — so readers tapped the sentence waiting for rows
        // that were never coming. `trendUp`/`trendDown` is a chart line with an
        // arrowhead: it can only mean which way the money went, and it is a
        // duotone glyph like every other one on this line rather than a bare
        // mark borrowed from a control.
        icon: up ? AppIcons.trendUp : AppIcons.trendDown,
        label: up ? L.s.spendIslandUp(percent) : L.s.spendIslandDown(percent),
        hint: L.s.spendIslandVsPrevious,
      );
    }

    // What is carrying the range. Its own glyph, so the sentence and the ring
    // below it name the same thing the same way.
    final top = summary.byCategory.first;
    return IslandLine(
      key: const ValueKey('top'),
      icon: top.key.icon,
      label: L.s.spendIslandTop(top.key.label),
      hint: L.s.spendIslandTopHint((top.share * 100).round()),
    );
  }
}
