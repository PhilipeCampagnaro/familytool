import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/calendar_data.dart';
import '../../models/tracker.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_sheet.dart';
import '../../l10n/l10n.dart';

/// What the sheet is building, held outside its body.
///
/// The save button belongs to the shared chrome rather than to us, so it cannot
/// reach a `State` inside the sheet — the same reason `IconDraft` exists for the
/// Listen sheet's icon picker. The body writes here; [showScheduleSheet] reads
/// it once the sheet is gone.
class _ScheduleDraft {
  TrackerSchedule value;

  /// Set by the header's check. Without it a dismissal and a save would be
  /// indistinguishable, and closing the sheet with the X would silently apply
  /// whatever had been tapped on the way out.
  bool saved = false;

  _ScheduleDraft(this.value);
}

/// The Board's rhythm picker — the row a tracker has where a task has "Fällig
/// am".
///
/// Returns null when the sheet was dismissed, which is the difference between
/// "leave the rhythm alone" and any answer the user actually gave. Same reason
/// [DueDateChoice] exists next door.
///
/// **Picking a kind does not close it**, unlike the date shortcuts. Two of the
/// three kinds need a second answer — which days, or how many — so a sheet that
/// popped on the first tap could only ever offer "jeden Tag". The kinds sit in
/// one card, whatever the chosen kind needs sits under it, and the standard
/// header's blue check is the way out, exactly as in every other sheet that
/// submits an answer.
Future<TrackerSchedule?> showScheduleSheet(BuildContext context, {required TrackerSchedule current}) async {
  final draft = _ScheduleDraft(current);
  await showAppSheet<void>(
    context: context,
    title: L.s.trackerRhythm,
    onSave: () => draft.saved = true,
    heightFactor: 0.62,
    child: _ScheduleOptions(draft: draft),
  );
  return draft.saved ? draft.value : null;
}

/// A summary short enough for a field row: "Jeden Tag", "Mo, Do", "4-mal pro
/// Woche".
///
/// The weekday case names the days rather than counting them, because the
/// count is the *other* rhythm and "2 Tage" beside "2-mal pro Woche" would be
/// two different promises wearing the same words.
String scheduleSummary(TrackerSchedule schedule) => switch (schedule.kind) {
  TrackerScheduleKind.daily => L.s.rhythmDaily,
  TrackerScheduleKind.weekdays => [
    // `weekdayShort` is Sunday-first on `DateTime.weekday % 7`, so Sunday (7)
    // lands on index 0 and the rest fall where they are.
    for (final d in schedule.activeWeekdays) weekdayShort[d % 7],
  ].join(', '),
  TrackerScheduleKind.weeklyCount => L.s.timesPerWeekValue(schedule.target),
};

class _ScheduleOptions extends StatefulWidget {
  final _ScheduleDraft draft;

  const _ScheduleOptions({required this.draft});

  @override
  State<_ScheduleOptions> createState() => _ScheduleOptionsState();
}

class _ScheduleOptionsState extends State<_ScheduleOptions> {
  late TrackerScheduleKind _kind = widget.draft.value.kind;

  /// Held apart from the kind so switching to "x-mal pro Woche" and back finds
  /// the weekdays where they were left. A draft that dropped them would punish
  /// somebody for looking at the other option.
  late Set<int> _weekdays = {...widget.draft.value.weekdays};
  late int _target = widget.draft.value.kind == TrackerScheduleKind.weeklyCount ? widget.draft.value.target : 3;

  TrackerSchedule get _schedule => switch (_kind) {
    TrackerScheduleKind.daily => TrackerSchedule.daily,
    TrackerScheduleKind.weekdays => TrackerSchedule.onWeekdays(_weekdays),
    TrackerScheduleKind.weeklyCount => TrackerSchedule.timesPerWeek(_target),
  };

  /// Every edit lands on the draft immediately, so the header's check has the
  /// current answer whenever it is tapped.
  void _publish() => widget.draft.value = _schedule;

  void _pickKind(TrackerScheduleKind kind) {
    setState(() {
      _kind = kind;
      // An empty set is the one rhythm the database refuses, and arriving in the
      // weekday option with nothing lit reads as broken. Today is the day the
      // user is standing on, so it is the least surprising one to start from.
      if (kind == TrackerScheduleKind.weekdays && _weekdays.isEmpty) {
        _weekdays = {DateTime.now().weekday};
      }
      _publish();
    });
  }

  /// The last lit day cannot be put out. Better than disabling the header's
  /// check over a state nobody meant to reach: a tracker on no days at all is
  /// not a rhythm somebody is part-way through typing, it is a dead row.
  void _toggleDay(int weekday) {
    setState(() {
      if (_weekdays.contains(weekday)) {
        if (_weekdays.length > 1) _weekdays.remove(weekday);
      } else {
        _weekdays.add(weekday);
      }
      _publish();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionCard(
          children: dividedRows([
            _KindRow(
              label: L.s.rhythmDaily,
              hint: L.s.rhythmDailyHint,
              selected: _kind == TrackerScheduleKind.daily,
              onTap: () => _pickKind(TrackerScheduleKind.daily),
            ),
            _KindRow(
              label: L.s.rhythmWeekdays,
              hint: L.s.rhythmWeekdaysHint,
              selected: _kind == TrackerScheduleKind.weekdays,
              onTap: () => _pickKind(TrackerScheduleKind.weekdays),
            ),
            _KindRow(
              label: L.s.rhythmTimesPerWeek,
              hint: L.s.rhythmTimesPerWeekHint,
              selected: _kind == TrackerScheduleKind.weeklyCount,
              onTap: () => _pickKind(TrackerScheduleKind.weeklyCount),
            ),
          ]),
        ),
        if (_kind == TrackerScheduleKind.weekdays) ...[
          const SizedBox(height: 14),
          _CardLabel(text: L.s.whichDays),
          SectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Monday first: the household is German, and it is the week
                    // the rest of the Board already closes on Sunday.
                    for (var weekday = 1; weekday <= 7; weekday++)
                      _DayChip(
                        label: weekdayShort[weekday % 7],
                        on: _weekdays.contains(weekday),
                        onTap: () => _toggleDay(weekday),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
        if (_kind == TrackerScheduleKind.weeklyCount) ...[
          const SizedBox(height: 14),
          _CardLabel(text: L.s.howOften),
          SectionCard(
            children: [
              _TargetStepper(
                value: _target,
                onChanged: (value) => setState(() {
                  _target = value;
                  _publish();
                }),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
            child: Text(L.s.timesPerWeekExplainer, style: AppText.caption.copyWith(color: AppColors.muted)),
          ),
        ],
      ],
    );
  }
}

/// The label over a card, in the same micro type the sheet's other captions use.
class _CardLabel extends StatelessWidget {
  final String text;

  const _CardLabel({required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 2, bottom: 8),
    child: Text(text, style: AppText.microLabel),
  );
}

class _KindRow extends StatelessWidget {
  final String label;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  const _KindRow({required this.label, required this.hint, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.rowTitle),
                  const SizedBox(height: 2),
                  Text(hint, style: AppText.caption.copyWith(color: AppColors.muted)),
                ],
              ),
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

/// One weekday, lit or not.
///
/// Round, like the Kalender's day circles: a day of the week is the same kind of
/// thing on both screens, and the two shapes side by side in one app read as two
/// unrelated controls rather than as one idea.
class _DayChip extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;

  const _DayChip({required this.label, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? accent : AppColors.surfaceAlt,
          shape: BoxShape.circle,
          border: Border.all(color: on ? accent : AppColors.hairline),
        ),
        child: Text(
          label,
          style: AppText.buttonSmall.copyWith(color: on ? AppColors.surface : AppColors.inkTertiary),
        ),
      ),
    );
  }
}

/// "4-mal pro Woche", with a minus and a plus. Capped at seven, because a week
/// has seven days and a target above them can never be met.
class _TargetStepper extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _TargetStepper({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              L.s.timesPerWeekValue(value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.rowTitle,
            ),
          ),
          _StepButton(icon: LucideIcons.minus, enabled: value > 1, onTap: () => onChanged(value - 1)),
          const SizedBox(width: 8),
          _StepButton(icon: LucideIcons.plus, enabled: value < 7, onTap: () => onChanged(value + 1)),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _StepButton({required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Icon(icon, size: 17, color: enabled ? accent : AppColors.mutedLight),
      ),
    );
  }
}
