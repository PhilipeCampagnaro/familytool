import 'package:flutter/material.dart';

import '../../data/board_data.dart';
import '../../models/task.dart' show DueTime;
import '../../theme/tokens.dart';
import '../../widgets/app_sheet.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_icons.dart';

/// What the due-date sheet came back with.
///
/// A wrapper rather than a bare `DateTime?`, because the sheet has **three**
/// answers and a nullable date can only carry two: a date, no date at all, and
/// "the user dismissed the sheet, leave it alone". Returning null for both of
/// the last two would make "Kein Datum" a no-op.
class DueDateChoice {
  final DateTime? day;

  /// The hour, when one was named. Always null where [day] is — an hour with no
  /// day names nothing, and the database refuses the pair outright.
  final DueTime? time;

  const DueDateChoice(this.day, [this.time]);
}

/// What the sheet is building, held outside its body.
///
/// The save button belongs to the shared chrome rather than to us, so it cannot
/// reach a `State` inside the sheet. Same arrangement as the rhythm sheet next
/// door, and as `IconDraft` in the Listen sheet.
class _DueDraft {
  DateTime? day;
  DueTime? time;

  /// Set by the header's check. Without it a dismissal and a save would be
  /// indistinguishable, and closing with the X would apply whatever had been
  /// tapped on the way out.
  bool saved = false;

  _DueDraft(this.day, this.time);
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
Future<DueDateChoice?> showDueDateSheet(BuildContext context, {DateTime? current, DueTime? currentTime}) async {
  final draft = _DueDraft(current, currentTime);
  await showAppSheet<void>(
    context: context,
    title: L.s.dueLabel,
    onSave: () => draft.saved = true,
    // Taller than it was by one card: the hour lives at the bottom of this
    // sheet, and a control below the fold of a sheet is a control nobody finds.
    heightFactor: 0.72,
    child: _DueDateOptions(draft: draft),
  );
  return draft.saved ? DueDateChoice(draft.day, draft.time) : null;
}

class _DueDateOptions extends StatefulWidget {
  final _DueDraft draft;

  const _DueDateOptions({required this.draft});

  @override
  State<_DueDateOptions> createState() => _DueDateOptionsState();
}

class _DueDateOptionsState extends State<_DueDateOptions> {
  late DateTime? _selected = widget.draft.day;
  late DueTime? _time = widget.draft.time;

  /// Every tap lands on the draft immediately, so the header's check has the
  /// current answer whenever it is pressed.
  ///
  /// **"Kein Datum" takes the hour with it.** The two are one answer — the
  /// database's `tasks_due_time_needs_date` says as much — and an hour left
  /// behind on a dateless to-do would be an answer to a question the sheet is
  /// no longer asking.
  void _select(DateTime? day) {
    setState(() {
      _selected = day;
      widget.draft.day = day;
      if (day == null) {
        _time = null;
        widget.draft.time = null;
      }
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

  /// The system clock picker, which comes up 12- or 24-hour according to the
  /// app's language rather than the phone's — `main.dart` overrides
  /// `alwaysUse24HourFormat` for exactly this.
  Future<void> _pickTime(BuildContext context) async {
    final start = _time;
    final picked = await showTimePicker(
      context: context,
      initialTime: start == null ? const TimeOfDay(hour: 9, minute: 0) : TimeOfDay(hour: start.hour, minute: start.minute),
    );
    if (picked == null || !context.mounted) return;
    setState(() {
      _time = DueTime(picked.hour, picked.minute);
      widget.draft.time = _time;
    });
  }

  void _clearTime() {
    setState(() {
      _time = null;
      widget.draft.time = null;
    });
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
              icon: AppIcons.calendar,
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
              icon: AppIcons.calendarSlash,
              label: L.s.sectionUndated,
              selected: chosen == null,
              onTap: () => _select(null),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        // **The hour, and it is optional twice over.** Most to-dos never get
        // one — "Geschenk kaufen" is owed by a day, not at a moment — so this
        // is the last card rather than a field beside the date, and nothing
        // here has to be answered.
        //
        // Shown even with no date chosen, muted and inert, rather than
        // appearing and disappearing as the date above it changes: a card that
        // materialises mid-sheet moves every row under the reader's thumb. The
        // hint says why it cannot be tapped, which is the one thing a disabled
        // control owes the person looking at it.
        SectionCard(
          children: dividedRows([
            _DueActionRow(
              icon: AppIcons.clock,
              label: L.s.dueTimeLabel,
              enabled: chosen != null,
              hint: chosen == null
                  ? L.s.dueTimeNeedsDate
                  : (_time == null ? null : formatTimeOfDay(_time!.hour, _time!.minute)),
              selected: _time != null,
              onTap: () => _pickTime(context),
            ),
            // Only once there is an hour to take away. Unlike "Kein Datum",
            // which is a real answer the sheet always offers, no-hour is simply
            // the absence of one and needs no row to stand for it.
            if (_time != null)
              _DueActionRow(
                icon: AppIcons.xCircle,
                label: L.s.dueNoTime,
                onTap: _clearTime,
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
              child: selected ? AppIcon(AppIcons.check, size: 18, color: accent) : null,
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

  /// False on the hour row while no day has been chosen. The row still draws —
  /// see the card's own note — but greys out and swallows nothing: the tap
  /// simply does not fire, rather than opening a picker whose answer could not
  /// be saved.
  final bool enabled;

  const _DueActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.hint,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            AppIcon(icon, size: 18, color: enabled ? AppColors.muted : AppColors.mutedLight),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: enabled ? AppText.rowTitle : AppText.rowTitle.copyWith(color: AppColors.mutedLight),
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
              child: selected ? AppIcon(AppIcons.check, size: 18, color: accent) : null,
            ),
          ],
        ),
      ),
    );
  }
}
