import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/board_data.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_sheet.dart';
import '../../l10n/l10n.dart';

/// What the due-date sheet came back with.
///
/// A wrapper rather than a bare `DateTime?`, because the sheet has **three**
/// answers and a nullable date can only carry two: a date, no date at all, and
/// "the user dismissed the sheet, leave it alone". Returning null for both of
/// the last two would make "Kein Datum" a no-op.
class DueDateChoice {
  final DateTime? day;

  const DueDateChoice(this.day);
}

/// What the sheet is building, held outside its body.
///
/// The save button belongs to the shared chrome rather than to us, so it cannot
/// reach a `State` inside the sheet. Same arrangement as the rhythm sheet next
/// door, and as `IconDraft` in the Listen sheet.
class _DueDraft {
  DateTime? day;

  /// Set by the header's check. Without it a dismissal and a save would be
  /// indistinguishable, and closing with the X would apply whatever had been
  /// tapped on the way out.
  bool saved = false;

  _DueDraft(this.day);
}

/// The Board's date picker: four shortcuts, then the calendar behind them.
///
/// Shortcuts first because they are what gets tapped — "Heute" and "Morgen"
/// between them cover most of what a family board is for, and reaching them
/// through a month grid would be three taps for the commonest answer. The full
/// [showDatePicker] is one row further down for everything else, the same
/// Material picker the Kalender event form uses, so the two agree.
///
/// **Tapping a row selects; the header's blue check applies it.** It used to pop
/// the sheet on the first tap, which was one tap fewer and read as a different
/// control from every other sheet in the app — there was no way to see what you
/// had chosen before committing, and no way to change your mind without
/// reopening. The check is the standard, so this wears it too.
Future<DueDateChoice?> showDueDateSheet(BuildContext context, {DateTime? current}) async {
  final draft = _DueDraft(current);
  await showAppSheet<void>(
    context: context,
    title: L.s.dueLabel,
    onSave: () => draft.saved = true,
    heightFactor: 0.58,
    child: _DueDateOptions(draft: draft),
  );
  return draft.saved ? DueDateChoice(draft.day) : null;
}

class _DueDateOptions extends StatefulWidget {
  final _DueDraft draft;

  const _DueDateOptions({required this.draft});

  @override
  State<_DueDateOptions> createState() => _DueDateOptionsState();
}

class _DueDateOptionsState extends State<_DueDateOptions> {
  late DateTime? _selected = widget.draft.day;

  /// Every tap lands on the draft immediately, so the header's check has the
  /// current answer whenever it is pressed.
  void _select(DateTime? day) {
    setState(() {
      _selected = day;
      widget.draft.day = day;
    });
  }

  /// Saturday of the current week, or *next* Saturday once the weekend is here:
  /// tapping "Wochenende" on a Sunday means the coming one, not this morning.
  DateTime _weekend(DateTime today) {
    final days = DateTime.saturday - today.weekday;
    return boardDaysAfter(today, days > 0 ? days : days + 7);
  }

  DateTime _nextMonday(DateTime today) => boardDaysAfter(today, 8 - today.weekday);

  Future<void> _pickExact(BuildContext context, DateTime today) async {
    final start = _selected ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: DateTime(start.year - 5),
      lastDate: DateTime(start.year + 5),
    );
    // The calendar closes over the sheet, which stays open behind it: the date
    // it hands back is a selection like any other, and the header's check is
    // still what applies it.
    if (picked == null || !context.mounted) return;
    _select(boardDay(picked));
  }

  @override
  Widget build(BuildContext context) {
    final today = boardDay(DateTime.now());
    final tomorrow = boardDaysAfter(today, 1);
    final weekend = _weekend(today);
    final nextWeek = _nextMonday(today);

    final chosen = _selected;
    bool isShortcut(DateTime day) => chosen != null && boardIsSameDay(chosen, day);
    // A date the shortcuts cannot express — it belongs on "Datum wählen …", or
    // the sheet would show a selection with nothing lit anywhere.
    final custom = chosen != null &&
        !isShortcut(today) &&
        !isShortcut(tomorrow) &&
        !isShortcut(weekend) &&
        !isShortcut(nextWeek);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionCard(
          children: dividedRows([
            _DueOptionRow(
              label: L.s.sectionToday,
              hint: L.s.dayMonthShort(today.day, today.month),
              selected: isShortcut(today),
              onTap: () => _select(today),
            ),
            _DueOptionRow(
              label: L.s.sectionTomorrow,
              hint: L.s.dayMonthShort(tomorrow.day, tomorrow.month),
              selected: isShortcut(tomorrow),
              onTap: () => _select(tomorrow),
            ),
            _DueOptionRow(
              label: L.s.dueThisWeekend,
              hint: L.s.dayMonthShort(weekend.day, weekend.month),
              selected: isShortcut(weekend),
              onTap: () => _select(weekend),
            ),
            _DueOptionRow(
              label: L.s.dueNextWeek,
              hint: L.s.dayMonthShort(nextWeek.day, nextWeek.month),
              selected: isShortcut(nextWeek),
              onTap: () => _select(nextWeek),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        SectionCard(
          children: dividedRows([
            _DueActionRow(
              icon: LucideIcons.calendar,
              label: L.s.duePickDate,
              // Carries the answer once it is one the four shortcuts cannot
              // give, so a date picked out of the calendar is visible on the
              // sheet rather than only after it closes.
              hint: custom ? L.s.dayMonthShort(chosen.day, chosen.month) : null,
              selected: custom,
              onTap: () => _pickExact(context, today),
            ),
            // Always offered, even on a task that has no date: the row then
            // reads as the answer it already has, with a check beside it, which
            // is how every other picker in the app shows its current state.
            _DueActionRow(
              icon: LucideIcons.calendarOff,
              label: L.s.sectionUndated,
              selected: chosen == null,
              onTap: () => _select(null),
            ),
          ]),
        ),
      ],
    );
  }
}

/// One shortcut. Selects rather than saves — the header's check is what applies
/// it, so a mis-tap costs a second tap instead of a reopened sheet.
class _DueOptionRow extends StatelessWidget {
  final String label;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  const _DueOptionRow({required this.label, required this.hint, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.rowTitle,
              ),
            ),
            Text(
              hint,
              style: AppText.buttonSmall.copyWith(fontWeight: FontWeight.w400, color: AppColors.inkTertiary),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 18,
              child: selected ? Icon(LucideIcons.check, size: 18, color: accent) : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _DueActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final String? hint;
  final VoidCallback onTap;

  const _DueActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.rowTitle,
              ),
            ),
            if (hint case final text?) ...[
              Text(
                text,
                style: AppText.buttonSmall.copyWith(fontWeight: FontWeight.w400, color: AppColors.inkTertiary),
              ),
              const SizedBox(width: 10),
            ],
            SizedBox(
              width: 18,
              child: selected ? Icon(LucideIcons.check, size: 18, color: accent) : null,
            ),
          ],
        ),
      ),
    );
  }
}
