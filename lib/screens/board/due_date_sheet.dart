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

/// The Board's date picker: four shortcuts, then the calendar behind them.
///
/// Shortcuts first because they are what gets tapped — "Heute" and "Morgen"
/// between them cover most of what a family board is for, and reaching them
/// through a month grid would be three taps for the commonest answer. The full
/// [showDatePicker] is one row further down for everything else, the same
/// Material picker the Kalender event form uses, so the two agree.
Future<DueDateChoice?> showDueDateSheet(BuildContext context, {DateTime? current}) {
  return showAppSheet<DueDateChoice>(
    context: context,
    header: SheetPickerHeader(title: L.s.dueLabel),
    heightFactor: 0.58,
    child: _DueDateOptions(current: current),
  );
}

class _DueDateOptions extends StatelessWidget {
  final DateTime? current;

  const _DueDateOptions({required this.current});

  /// Saturday of the current week, or *next* Saturday once the weekend is here:
  /// tapping "Wochenende" on a Sunday means the coming one, not this morning.
  DateTime _weekend(DateTime today) {
    final days = DateTime.saturday - today.weekday;
    return boardDaysAfter(today, days > 0 ? days : days + 7);
  }

  DateTime _nextMonday(DateTime today) => boardDaysAfter(today, 8 - today.weekday);

  Future<void> _pickExact(BuildContext context, DateTime today) async {
    final start = current ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: DateTime(start.year - 5),
      lastDate: DateTime(start.year + 5),
    );
    if (picked == null || !context.mounted) return;
    Navigator.of(context).pop(DueDateChoice(boardDay(picked)));
  }

  @override
  Widget build(BuildContext context) {
    final today = boardDay(DateTime.now());
    final tomorrow = boardDaysAfter(today, 1);
    final weekend = _weekend(today);
    final nextWeek = _nextMonday(today);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionCard(
          children: dividedRows([
            _DueOptionRow(
              label: L.s.sectionToday,
              hint: L.s.dayMonthShort(today.day, today.month),
              selected: current != null && boardIsSameDay(current!, today),
              day: today,
            ),
            _DueOptionRow(
              label: L.s.sectionTomorrow,
              hint: L.s.dayMonthShort(tomorrow.day, tomorrow.month),
              selected: current != null && boardIsSameDay(current!, tomorrow),
              day: tomorrow,
            ),
            _DueOptionRow(
              label: L.s.dueThisWeekend,
              hint: L.s.dayMonthShort(weekend.day, weekend.month),
              selected: current != null && boardIsSameDay(current!, weekend),
              day: weekend,
            ),
            _DueOptionRow(
              label: L.s.dueNextWeek,
              hint: L.s.dayMonthShort(nextWeek.day, nextWeek.month),
              selected: current != null && boardIsSameDay(current!, nextWeek),
              day: nextWeek,
            ),
          ]),
        ),
        const SizedBox(height: 14),
        SectionCard(
          children: dividedRows([
            _DueActionRow(
              icon: LucideIcons.calendar,
              label: L.s.duePickDate,
              onTap: () => _pickExact(context, today),
            ),
            // Always offered, even on a task that has no date: the row then
            // reads as the answer it already has, with a check beside it, which
            // is how every other picker in the app shows its current state.
            _DueActionRow(
              icon: LucideIcons.calendarOff,
              label: L.s.sectionUndated,
              selected: current == null,
              onTap: () => Navigator.of(context).pop(const DueDateChoice(null)),
            ),
          ]),
        ),
      ],
    );
  }
}

/// One shortcut. Picking *is* the save, so the row pops the sheet with its own
/// date — the same shape as the Kalender's calendar picker rows.
class _DueOptionRow extends StatelessWidget {
  final String label;
  final String hint;
  final bool selected;
  final DateTime day;

  const _DueOptionRow({required this.label, required this.hint, required this.selected, required this.day});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(DueDateChoice(day)),
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
  final VoidCallback onTap;

  const _DueActionRow({required this.icon, required this.label, required this.onTap, this.selected = false});

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
