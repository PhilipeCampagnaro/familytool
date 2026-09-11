import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/board_state.dart';
import '../../state/calendar_state.dart';
import '../../state/family_state.dart';
import '../../state/list_state.dart';
import '../../state/nav_state.dart';
import '../../state/tracker_state.dart';
import '../../theme/app_icons.dart';
import '../../theme/tokens.dart';
import '../board_screen.dart';
import '../calendar_connect_screen.dart';
import '../settings/family_page.dart';

/// The setup checklist Home shows a brand-new household, in the order it is
/// worth doing.
///
/// There is no "address" step even though the address is what Abfall, Ferien
/// and the weather all hang off. Onboarding is the only place in the app that
/// can save one — `FamilyNotifier.saveAddress` has exactly one caller — so a
/// step pointing at it would have nowhere to send anybody. Connecting Abfall
/// asks for the address on the way, which is the door that does exist.
enum FirstStep { calendar, family, todo, tracker, list }

/// The steps this household has **not** done, newest-first in setup order.
///
/// **Every one is derived from live state, and none of them is stored.** A
/// stored checkbox drifts the moment somebody deletes their only list, does not
/// travel to the other parent's phone, and needs a column, a migration and a
/// policy of its own. Asking the providers costs nothing — the screen is
/// already watching all five for other reasons — and it answers correctly on a
/// second device, after a restore, and for the household that set everything up
/// before this card existed.
///
/// Empty while the two slow loads are still out, so an established family never
/// sees a checklist flash up telling them to connect the calendar they already
/// have. The other three answer from memory and need no such guard.
final firstStepsProvider = Provider<List<FirstStep>>((ref) {
  final ready = ref.watch(familyProvider.select((s) => s.loaded)) &&
      ref.watch(calendarProvider.select((s) => s.loaded));
  if (!ready) return const [];

  final hasCalendar = ref.watch(calendarProvider.select((s) => s.calendars.isNotEmpty));
  // **Sending the invitation is the step, not the other parent accepting it.**
  // A household that has just invited somebody has done everything this list
  // can ask of them, and leaving the row standing there reads as the invitation
  // having failed. `invites` is admin-only, which costs nothing here: only an
  // admin can invite, so only an admin can be looking at a step they have
  // already taken.
  final hasFamily = ref.watch(
    familyProvider.select((s) => s.members.length > 1 || s.invites.isNotEmpty),
  );
  final hasTodo = ref.watch(boardProvider.select((s) => s.tasks.isNotEmpty));
  final hasTracker = ref.watch(trackerProvider.select((s) => s.trackers.isNotEmpty));
  final hasList = ref.watch(listProvider.select((s) => s.lists.isNotEmpty));

  return [
    if (!hasCalendar) FirstStep.calendar,
    if (!hasFamily) FirstStep.family,
    if (!hasTodo) FirstStep.todo,
    if (!hasTracker) FirstStep.tracker,
    if (!hasList) FirstStep.list,
  ];
});

/// How many steps there are in total — what the island's "2 von 5" counts
/// against.
final int firstStepCount = FirstStep.values.length;

/// Whether the checklist under the island is unfolded.
///
/// It lives here rather than in the card's own `State` because three widgets
/// need it and none of them contains the others: the chevron that toggles it is
/// in the island, the panel is a row of the collapsing header, and `StartScreen`
/// has to know how tall that row is before either of them builds.
final firstStepsOpenProvider = StateProvider<bool>((ref) => false);

/// Every row is the same height, and the panel's height is arithmetic over it.
///
/// **The header has to be told how tall the panel is before it lays it out.**
/// The collapsing block is a fixed extent that both the sliver's expanded
/// height and its every frame of collapse are computed from, so a panel that
/// sized itself to its own content would be measured a frame after the header
/// that has to contain it. Fixed rows are how the answer is knowable in
/// advance, and they cost nothing: every row is a glyph, a line and a line
/// under it.
const double firstStepRowHeight = 52;
const double _panelPadTop = 6;
const double _panelPadBottom = 6;

/// The air between the island and the top of the panel. Part of the measured
/// height rather than a gap the header adds, so the two numbers stay one
/// number — and it opens first, which is what makes the card read as coming out
/// from under the line above it rather than as growing off it.
const double _panelGapTop = 12;

double firstStepsPanelHeight(int steps) =>
    steps == 0 ? 0 : _panelGapTop + _panelPadTop + steps * firstStepRowHeight + _panelPadBottom;

/// The checklist itself, in the header directly under the island.
///
/// **It expands in place and pushes the day down.** It was a card in the scroll
/// body first, which put the filter chips and the whole day strip between the
/// chevron and the thing the chevron opened; it was a floating panel after
/// that, which sat in the right place but hovered over the day rather than
/// belonging to the header the control is in. A disclosure that opens where it
/// is and closes back into the same space is the plain reading of the chevron,
/// and the header simply grows by the height of it.
///
/// Nothing but the rows: the title, the count and the chevron are the island's,
/// so the two read as one control rather than as a header repeated twice, and
/// the island's own second line already says what the checklist is for.
class FirstStepsCard extends ConsumerWidget {
  const FirstStepsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remaining = ref.watch(firstStepsProvider);
    if (remaining.isEmpty) return const SizedBox.shrink();
    final accent = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.only(top: _panelGapTop),
      child: Container(
        // Tinted rather than the white card the content uses, because this is
        // guidance about the app and not something the family put here. It also
        // stops the rows reading as the first section of the day below them.
        decoration: BoxDecoration(
          color: tint(accent, .93),
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        padding: const EdgeInsets.fromLTRB(14, _panelPadTop, 10, _panelPadBottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final step in remaining) _FirstStepRow(step: step)],
        ),
      ),
    );
  }
}

class _FirstStepRow extends ConsumerWidget {
  final FirstStep step;

  const _FirstStepRow({required this.step});

  IconData get _icon => switch (step) {
    FirstStep.calendar => AppIcons.calendarPlus,
    FirstStep.family => AppIcons.userPlus,
    FirstStep.todo => AppIcons.checkCircle,
    FirstStep.tracker => AppIcons.repeat,
    FirstStep.list => AppIcons.listPlus,
  };

  String get _title => switch (step) {
    FirstStep.calendar => L.s.firstStepCalendar,
    FirstStep.family => L.s.firstStepFamily,
    FirstStep.todo => L.s.firstStepTodo,
    FirstStep.tracker => L.s.firstStepTracker,
    FirstStep.list => L.s.firstStepList,
  };

  String get _body => switch (step) {
    FirstStep.calendar => L.s.firstStepCalendarBody,
    FirstStep.family => L.s.firstStepFamilyBody,
    FirstStep.todo => L.s.firstStepTodoBody,
    FirstStep.tracker => L.s.firstStepTrackerBody,
    FirstStep.list => L.s.firstStepListBody,
  };

  /// Where a step sends you, and two of them can only send you to a tab.
  ///
  /// A to-do has a public sheet to open over Home ([openTaskSheet]); a tracker
  /// and a list do not, and inventing one here would mean a second door into
  /// each create flow that then has to be kept in step with the first. The tab
  /// is one more tap and no new surface.
  void _open(BuildContext context, WidgetRef ref) {
    // The panel has done its job the moment somebody takes a step, and leaving
    // it hanging over the screen they come back to would make them dismiss it
    // for a second time.
    ref.read(firstStepsOpenProvider.notifier).state = false;
    switch (step) {
      case FirstStep.calendar:
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => CalendarConnectionsPage()));
      case FirstStep.family:
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => FamilyPage()));
      case FirstStep.todo:
        openTaskSheet(context, ref);
      case FirstStep.tracker:
        ref.read(tabJumpProvider.notifier).toTab(boardTabIndex);
      case FirstStep.list:
        ref.read(tabJumpProvider.notifier).toTab(listsTabIndex);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _open(context, ref),
      child: SizedBox(
        height: firstStepRowHeight,
        child: Row(
          children: [
            // An empty ring, not a check: every row here is a step still to
            // take, so a tick would be the one thing it never means.
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
              // Ink, not the accent. The island above is already carrying the
              // colour, and five accent glyphs stacked under it made the panel
              // read as five things wanting attention rather than one list. The
              // tinted ground the rows sit on is the panel's colour; the rows
              // themselves are content.
              child: Center(child: AppIcon(_icon, size: 17, color: AppColors.inkSecondary)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_title, style: AppText.rowTitle),
                  const SizedBox(height: 1),
                  Text(_body, style: AppText.microLabel.copyWith(color: AppColors.muted)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AppIcon(AppIcons.caretRight, size: 15, color: AppColors.mutedLight, flat: true),
          ],
        ),
      ),
    );
  }
}
