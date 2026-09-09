import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/board_data.dart';
import '../../models/tracker.dart';
import '../../models/who.dart';
import '../../state/family_state.dart';
import '../../state/tracker_state.dart';
import '../../theme/app_icons.dart';
import '../../theme/tokens.dart';
import '../../widgets/anchored_menu.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/avatar.dart';
import '../../widgets/bottom_nav.dart';
import '../../widgets/collapsing_header.dart';
import '../../widgets/expandable_title.dart';
import '../../widgets/glass.dart';
import '../../widgets/icon_picker.dart';
import '../../widgets/toast_chip.dart';
import '../../l10n/l10n.dart';
import 'schedule_sheet.dart';
import 'tracker_chart.dart';

/// One tracker's own screen — its record, and what it is.
///
/// A mode of the Board rather than a pushed route, the same way Listen opens a
/// list and Box a box: the tab bar stays put, the back chevron is the header's,
/// and no route is laid over the native views. [TrackerState.openId] is the
/// switch.
///
/// **The chart here answers a different question from the one in the Board's
/// header.** That grid is the household's trackers averaged together, which is
/// the right thing above a list of all of them and no help at all when somebody
/// wants to know how *this* one is going. Five trackers on the Board used to
/// produce one line; now each of them has its own.
///
/// Editing is the same sheet the Board's row opens, reached from the menu —
/// hence [onEdit] rather than a call into `board_screen.dart`, which would make
/// the two files import each other for one function.
class TrackerDetailView extends ConsumerWidget {
  final Tracker tracker;
  final Color accent;
  final VoidCallback onEdit;

  const TrackerDetailView({
    super.key,
    required this.tracker,
    required this.accent,
    required this.onEdit,
  });

  /// First-frame estimate of the name block only — [CollapsingHeaderScreen]
  /// re-measures it. See the collapsing-headers section of
  /// `docs/design-system.md`: a constant tuned against a widget test's fallback
  /// font clips the real one.
  static const _extraHeight = 84.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(trackerProvider);
    final notifier = ref.read(trackerProvider.notifier);
    final today = boardDay(DateTime.now());
    final checks = state.checksFor(tracker.id);
    final streak = state.streakOf(tracker, today);
    final dayBased = tracker.schedule.isDayBased;

    return CollapsingHeaderScreen(
      backdrop: HeaderBrandGlow(color: accent, strength: .14),
      // The pinned row keeps the generic "Tracker" label at rest — the
      // tracker's own name is the big row below it — and swaps to that name as
      // the big one scrolls away, so the bar never stops saying which one you
      // are in.
      titleRowBuilder: (context, t) => CollapsingScreenTitle(
        title: L.s.trackerTitle,
        collapsedTitle: tracker.text,
        collapsedIcon: IconTile(iconKey: tracker.iconKey, size: 24, imageSize: 17),
        t: t,
        expandedAlignment: Alignment.center,
        expandedFontSize: 19,
        fontWeight: FontWeight.w500,
        leadingWidth: 48,
        trailingWidth: 48,
        leading: GlassIconButton(icon: AppIcons.caretLeft, onTap: notifier.back),
        // No "Teilen": `public.shareable_kind` names no value for a tracker,
        // and a rhythm a household keeps is not a thing to hand to an outsider.
        trailing: GlassMenuButton(
          items: [
            AnchoredMenuItem(label: L.s.edit, icon: AppIcons.pencilSimple, onSelected: onEdit),
            AnchoredMenuItem(
              label: L.s.delete,
              icon: AppIcons.trash,
              destructive: true,
              onSelected: () async {
                // Captured before the write: this menu lives on the screen the
                // delete itself unmounts, which is what drops us back on the
                // Board.
                final confirm = confirmChipOf(context);
                if (await notifier.deleteTracker(tracker)) {
                  confirm(L.s.trackerDeleted, undo: () => notifier.restoreTracker(tracker));
                }
              },
            ),
          ],
        ),
      ),
      estimatedExtraHeight: _extraHeight,
      extra: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Row(
            children: [
              IconTile(iconKey: tracker.iconKey, size: 44, imageSize: 30),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Unfolds when the name is longer than the line, exactly as
                    // a list's and a box's do — see [ExpandableTitle].
                    ExpandableTitle(text: tracker.text),
                    const SizedBox(height: 3),
                    Text(
                      // The streak, and nothing else that could be mistaken for
                      // a score. What the household is keeping up is the fact
                      // worth putting under the name; a percentage would invite
                      // the app to start grading them.
                      streak > 0
                          ? (dayBased ? L.s.streakDays(streak) : L.s.streakWeeks(streak))
                          : scheduleSummary(tracker.schedule),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.label,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: ScreenBodyPanel(
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 18, 16, navContentInset(context, pill: 140)),
          children: [
            SectionCard(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (dayBased) ...[
                        TrackerDayChart(
                          tracker: tracker,
                          checkedDays: checks,
                          today: today,
                          accent: accent,
                          title: L.s.trackerHistory,
                          onToggleDay: (day) =>
                              _backfill(context, notifier, tracker, day, today, checks),
                        ),
                        const SizedBox(height: 14),
                        TrackerChartLegend(accent: accent),
                        const SizedBox(height: 8),
                        Text(
                          L.s.trackerBackfillOlderHint,
                          style: AppText.microLabel.copyWith(color: AppColors.mutedLight),
                        ),
                      ] else
                        TrackerWeekChart(
                          tracker: tracker,
                          checkedDays: checks,
                          today: today,
                          accent: accent,
                          title: L.s.trackerHistory,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SectionCard(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: TrackerRecentDays(
                    tracker: tracker,
                    checkedDays: checks,
                    today: today,
                    accent: accent,
                    onToggleDay: (day) => _backfill(context, notifier, tracker, day, today, checks),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SectionCard(
              children: dividedRows([
                _FactRow(label: L.s.trackerRhythm, value: scheduleSummary(tracker.schedule)),
                _AssigneeRow(tracker: tracker),
                _FactRow(
                  label: L.s.trackerStartedOn,
                  value: L.s.dayMonth(tracker.startsOn.day, tracker.startsOn.month),
                ),
                if (tracker.meta case final note? when note.trim().isNotEmpty) _NoteRow(note: note),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ticks a day, and says which one it was.
///
/// The chip is the whole point: a back-fill is a tap on one small circle among
/// seven, or one square among a hundred, and a mis-tap that silently writes the
/// neighbouring day would leave a record quietly wrong. Naming the day makes it
/// visible, and the undo makes it cheap — tapping the same day again would do
/// the same job, but only once you have worked out which day you actually hit.
///
/// **Today is excepted.** Ticking today is not filling anything in, the circle
/// changes under the thumb where the eye already is, and a chip on every evening
/// check-off would be noise the Board's own row does not make either.
Future<void> _backfill(
  BuildContext context,
  TrackerNotifier notifier,
  Tracker tracker,
  DateTime day,
  DateTime today,
  Set<DateTime> checks,
) async {
  final at = boardDay(day);
  if (at == boardDay(today)) {
    await notifier.toggleCheck(tracker, at);
    return;
  }

  // Taken before the write, like every other confirmation in the app.
  final confirm = confirmChipOf(context);
  final was = checks.contains(at);
  final label = L.s.weekdayWithDateShort(at.weekday % 7, at.day, at.month);

  if (await notifier.toggleCheck(tracker, at)) {
    confirm(
      was ? L.s.trackerDayCleared(label) : L.s.trackerDayFilledIn(label),
      undo: () => notifier.toggleCheck(tracker, at),
    );
  }
}

/// A label on the left, an answer on the right. Read-only: everything on this
/// card is changed in the edit sheet, which is one tap away in the header menu,
/// and a row that edited in place would be a second way to write the same
/// column.
class _FactRow extends StatelessWidget {
  final String label;
  final String value;

  const _FactRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppText.rowTitle)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.label,
            ),
          ),
        ],
      ),
    );
  }
}

/// Who keeps it, and who in the household can see it — the same two axes the
/// Board's row wears as a badge, spelled out here where there is room for them.
class _AssigneeRow extends ConsumerWidget {
  final Tracker tracker;

  const _AssigneeRow({required this.tracker});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(householdMembersProvider);
    final w = whoBadge(
      assigneeId: tracker.assigneeId,
      visibility: tracker.visibility,
      sharedWith: tracker.sharedWith,
      members: members,
    );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        children: [
          Expanded(child: Text(L.s.assigneeLabel, style: AppText.rowTitle)),
          const SizedBox(width: 12),
          Semantics(
            label: w.label,
            excludeSemantics: true,
            child: WhoAvatars(who: w, size: 24, fontSize: 10),
          ),
          VisibilityBadge(
            visibility: tracker.visibility,
            sharedWith: tracker.sharedWith,
            members: members,
            padding: const EdgeInsets.only(left: 6),
          ),
        ],
      ),
    );
  }
}

/// The tracker's note, under its own label rather than squeezed into a value
/// column: it is a sentence somebody typed, and truncating it to one line on
/// the right would show the first three words of it.
class _NoteRow extends StatelessWidget {
  final String note;

  const _NoteRow({required this.note});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(L.s.notes, style: AppText.rowTitle),
          const SizedBox(height: 5),
          Text(note, style: AppText.label),
        ],
      ),
    );
  }
}
