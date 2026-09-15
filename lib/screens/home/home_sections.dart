import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/board_data.dart';
import '../../data/calendar_data.dart';
import '../../data/tracker_data.dart';
import '../../l10n/l10n.dart';
import '../../models/shopping_list.dart';
import '../../models/tracker.dart';
import '../../state/list_state.dart';
import '../../state/nav_state.dart';
import '../../state/tracker_state.dart';
import '../../theme/app_icons.dart';
import '../../theme/tokens.dart';
import '../../widgets/check_off.dart';
import '../../widgets/icon_picker.dart';

/// Everything on Home that is **not** about the selected day.
///
/// This is the part of Home's grey surface below the divider under the day, and
/// that divider is the whole point of it: above it is whichever date the strip
/// is on, below it is the household as it stands right now. Tap a Thursday
/// three weeks out and the day changes while none of this does — which is
/// correct, and only stays legible because the day visibly ends there.
///
/// So nothing here may be day-scoped. A tracker is owed today; a shopping list
/// has no date at all. A "tomorrow" block would read as belonging to the strip
/// and would be wrong on every day but one.
///
/// **Open to-dos are deliberately absent too.** The week view above already
/// draws each to-do on its due day, so a second card of them repeated the strip
/// in a different shape.
///
/// **Boxen is deliberately absent.** A box answers "where did we put the winter
/// coats", which is a question you already know you have when you go looking. It
/// would be here because it is a tab, and that is not a reason.
class HomeSections extends ConsumerWidget {
  const HomeSections({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      // The day's own inset inside the grey (`_DayBody`), not the screen's
      // margin: these sit on the same surface as the calendar above them, so
      // their headings and cards line up with its heading and time rail.
      padding: const EdgeInsets.fromLTRB(14, 22, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        // **Not `const`.** Each of them reads a design token while it
        // builds, and a const instance is canonical: the parent handing back an
        // identical widget is how Flutter knows it can skip the subtree, so
        // these went on painting the palette they were born in. The
        // heading above each card refreshed anyway — `_Section` depends on
        // `Theme.of(context)`, which marks it dirty across the skip — which is
        // why this showed up as light-ink list names under a white section
        // title on the dark palette. See `tool/check_const_palette.dart`.
        children: [_TrackersToday(), _ListsOverview()],
      ),
    );
  }
}

/// A heading, an optional way through to the tab that owns it, and a card of
/// rows. One shell for all three so the sections cannot drift apart.
class _Section extends StatelessWidget {
  final String title;
  final VoidCallback? onShowAll;
  final List<Widget> rows;

  const _Section({required this.title, required this.rows, this.onShowAll});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 10),
          child: Row(
            children: [
              Text(title, style: AppText.sectionHeading),
              const Spacer(),
              if (onShowAll != null)
                GestureDetector(
                  onTap: onShowAll,
                  behavior: HitTestBehavior.opaque,
                  child: Text(L.s.homeShowAll, style: AppText.caption.copyWith(color: accent)),
                ),
            ],
          ),
        ),
        // **[AppColors.cardOnSurface], not [AppColors.surface].** These sit on
        // Home's grey surface (`_DayBody`), and on dark `surface` is *darker*
        // than nothing much — `cardOnSurface` takes the lift there, one step
        // above the grey on both palettes, with the shadow token doing the
        // separating on light.
        Container(
          decoration: BoxDecoration(
            color: AppColors.cardOnSurface,
            borderRadius: BorderRadius.circular(AppRadii.card),
            boxShadow: AppShadows.card,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) Divider(height: 1, thickness: 1, color: AppColors.cardOnSurfaceDivider),
                rows[i],
              ],
            ],
          ),
        ),
        const SizedBox(height: 22),
      ],
    );
  }
}

/// The rhythms today asks for, with their circles.
///
/// **The circle is the reason this section exists.** A tracker you have to
/// navigate to in order to tick is a tracker that stops being ticked, and the
/// whole record then says the household stopped doing the thing rather than
/// that the app made it awkward.
///
/// Ticked ones stay on the card with a filled circle rather than dropping off
/// it. A section that emptied itself as the day went on would read as a day
/// that never owed anything.
class _TrackersToday extends ConsumerWidget {
  const _TrackersToday();

  static const _max = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(trackerProvider);
    final accent = Theme.of(context).colorScheme.primary;
    final today = calToday();
    final due = state.dueOn(today).take(_max).toList();
    if (due.isEmpty) return const SizedBox.shrink();

    return _Section(
      title: L.s.homeTrackerSection,
      onShowAll: () => ref.read(tabJumpProvider.notifier).toTab(boardTabIndex),
      rows: [
        for (final tracker in due)
          _TrackerRow(
            key: ValueKey(tracker.id),
            tracker: tracker,
            accent: accent,
            checked: state.isCheckedOn(tracker.id, today),
            checkedDays: state.checksFor(tracker.id),
            streak: state.streakOf(tracker, today),
            today: today,
          ),
      ],
    );
  }
}

class _TrackerRow extends ConsumerWidget {
  final Tracker tracker;
  final Color accent;
  final bool checked;

  /// Every day this tracker was ticked, for the week strip under the name. The
  /// whole set rather than the seven days it draws: the section holds it
  /// already, and slicing it here would be a loop to save a loop.
  final Set<DateTime> checkedDays;

  /// How many days the rhythm has been kept in a row, read off the state the
  /// section already holds rather than watched again per row.
  final int streak;

  final DateTime today;

  const _TrackerRow({
    super.key,
    required this.tracker,
    required this.accent,
    required this.checked,
    required this.checkedDays,
    required this.streak,
    required this.today,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          // The name and its week share one line, the way somebody would write
          // the two down: "Sport ▪▪▫▪▪▪▫". Stacked, the squares read as a
          // second fact about the tracker; beside the name they read as the
          // answer to it. The name takes whatever the strip leaves.
          Expanded(
            child: Text(tracker.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.itemTitle),
          ),
          const SizedBox(width: 12),
          _WeekStrip(tracker: tracker, checkedDays: checkedDays, today: today, accent: accent),
          if (streak > 1) ...[
            const SizedBox(width: 10),
            AppIcon(AppIcons.flame, size: 13, color: AppColors.muted),
            const SizedBox(width: 3),
            Text('$streak', style: AppText.microLabel.copyWith(color: AppColors.muted)),
          ],
          const SizedBox(width: 12),
          CheckOffButton(
            progress: checked ? 1 : 0,
            accent: accent,
            size: 26,
            filled: checked,
            onTap: () => ref.read(trackerProvider.notifier).toggleCheck(tracker, today),
          ),
        ],
      ),
    );
  }
}

/// The last seven days of one rhythm, oldest on the left and today on the
/// right.
///
/// **A week is as much history as a row can carry and still be read at a
/// glance**, and it is the span somebody actually asks about: whether the thing
/// is going well this week. The months of record live on the tracker's own
/// screen, where the chart is tall enough to be read rather than glanced at.
///
/// The three marks are the detail chart's, colour for colour, because they mean
/// exactly what they mean there — kept, asked for and missed, and a day the
/// rhythm never named. **The last of those is never drawn as a miss**: a
/// Montag/Donnerstag tracker with a perfect record would otherwise report five
/// failures a week. Days before the tracker existed leave their space empty
/// rather than filling it, so the strip starts where the tracker did without the
/// squares shifting under the ones beside them.
///
/// Not tappable. The circle at the end of the row already ticks today, and
/// back-filling a day somebody forgot is the detail chart's job — a 9-point
/// square on a summary row is a mis-tap waiting to write a day nobody meant.
class _WeekStrip extends StatelessWidget {
  final Tracker tracker;
  final Set<DateTime> checkedDays;
  final DateTime today;
  final Color accent;

  const _WeekStrip({
    required this.tracker,
    required this.checkedDays,
    required this.today,
    required this.accent,
  });

  static const _days = 7;
  static const _size = 9.0;
  static const _gap = 4.0;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var back = _days - 1; back >= 0; back--) ...[
          if (back < _days - 1) const SizedBox(width: _gap),
          _mark(boardDaysAfter(today, -back)),
        ],
      ],
    );
  }

  Widget _mark(DateTime day) {
    final mark = trackerDayMark(tracker, checkedDays, day, today);
    if (mark == TrackerDayMark.blank) return const SizedBox(width: _size, height: _size);
    return AnimatedContainer(
      // The same 280ms the detail chart fills a square in, so today's square
      // lands with the same weight wherever it is ticked.
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        color: switch (mark) {
          TrackerDayMark.kept => accent,
          TrackerDayMark.missed => tint(accent, .82),
          _ => AppColors.hairline,
        },
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

/// The household's lists and how much is still on each.
///
/// Counts, not articles. "Einkauf, 12 offen" is the whole question somebody has
/// about a shopping list from the other side of the app; the twelve articles are
/// a screen, and the screen is one tap away.
class _ListsOverview extends ConsumerWidget {
  const _ListsOverview();

  static const _max = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(listProvider);
    // "Alle Artikel" is computed rather than stored and counts every other
    // list's articles a second time, so it would double the section's numbers.
    final lists = [
      for (final l in state.lists)
        if (!l.isSummary) l,
    ];

    final withOpen = <(ShoppingList, int)>[];
    for (final list in lists) {
      final open = [
        for (final item in state.itemsFor(list.id))
          if (!item.done) item,
      ].length;
      if (open > 0) withOpen.add((list, open));
    }
    withOpen.sort((a, b) => b.$2.compareTo(a.$2));
    final shown = withOpen.take(_max).toList();
    if (shown.isEmpty) return const SizedBox.shrink();

    return _Section(
      title: L.s.homeListsSection,
      onShowAll: () => ref.read(tabJumpProvider.notifier).toTab(listsTabIndex),
      rows: [
        for (final (list, open) in shown)
          GestureDetector(
            key: ValueKey(list.id),
            behavior: HitTestBehavior.opaque,
            onTap: () => ref.read(tabJumpProvider.notifier).toList(list.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  IconTile(iconKey: list.iconKey, size: 34, imageSize: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(list.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.itemTitle),
                  ),
                  const SizedBox(width: 10),
                  Text(L.s.homeListOpenItems(open), style: AppText.microLabel.copyWith(color: AppColors.muted)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
