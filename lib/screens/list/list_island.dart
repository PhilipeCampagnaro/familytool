import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/list_planner_state.dart';
import '../../theme/app_icons.dart';
import '../../widgets/status_island.dart';

/// **Listen's one line under the title**, in the slot Home gives its day and
/// Ausgaben its money — and on this tab it is the invitation to Vorhaben.
///
/// It replaces two things at once. The search pill that used to fill this block
/// said nothing (search is the magnifier beside the `+` now), and the intro card
/// at the top of the body said this — a card with a heading, a paragraph and a
/// glyph tile, sitting above the household's own lists as a permanent
/// advertisement, which is the failure mode docs/list-planner.md set out to
/// avoid. The same sentence in the header is the app's own voice in the place
/// where the app already speaks, and it costs the lists no room at all.
///
/// **It carries the disclosure caret** ([IslandLine.expanded]), because the tap
/// does not go anywhere: [PlannerCard] unfolds under it, at the top of the
/// body, with the household's own lists still on screen below. Without a caret
/// a heading that answers a tap is indistinguishable from one that does not —
/// and a right-pointing one would promise a screen that no longer exists.
///
/// **One rung, and it is a ladder anyway.** Home and Ausgaben pick the most
/// pressing of seven cases; Listen has exactly one thing worth a sentence, so
/// this is the [StatusIsland] shape with a single case in it rather than a row
/// that happens to look like one. A count of lists or open articles would be the
/// row of counters the island exists not to be — the card below already lists
/// every list with its own count on it.
class ListIsland extends ConsumerWidget {
  const ListIsland({super.key});

  /// The height of the row that hosts it — the same 48 points Ausgaben gives
  /// its island, so the two tabs' headers are the same height.
  static const rowHeight = 48.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(plannerProvider.select((s) => s.open));
    return StatusIsland(
      child: IslandLine(
        key: const ValueKey('planner'),
        // A bulb, not a sparkle: the sparkle is the icon picker's mark and
        // Ausgaben's "Extra", and a second meaning for it here would be the
        // generic "AI happens" badge rather than a glyph about this feature.
        icon: AppIcons.lightbulb,
        label: L.s.plannerIslandLine,
        hint: L.s.plannerIslandHint,
        expanded: open,
        onTap: () {
          final notifier = ref.read(plannerProvider.notifier);
          open ? notifier.close() : notifier.open();
        },
        // Nothing changed under it — the line is the same sentence every time
        // the tab is opened, and a wave on each visit would be the app waving
        // at itself.
        sweep: IslandSweep.none,
      ),
    );
  }
}
