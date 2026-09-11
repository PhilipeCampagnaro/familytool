part of '../calendar_screen.dart';

// The event form's "Wiederholen" row and the sheet behind it.

/// What the repeat sheet came back with.
///
/// A wrapper rather than a bare [EventRepeat], because the rule and the day the
/// series stops are one answer given in one place, and because a dismissal has
/// to be tellable from a rule of "Nie" — see [_showRepeatSheet]. Same reason
/// `DueDateChoice` exists on the Board.
class _RepeatChoice {
  final EventRepeat repeat;

  /// The last day the series may land on, or null for a rule that never ends.
  /// Always null on [EventRepeat.never], which has nothing to end.
  final DateTime? until;

  /// The day the rule hangs off, as the sheet left it — unchanged unless the
  /// start row at the top was used. Carries the start's own hour, which this
  /// sheet never asks about and therefore never alters.
  final DateTime start;

  const _RepeatChoice(this.repeat, this.until, this.start);
}

/// What the sheet is building, held outside its body.
///
/// The save button belongs to the shared chrome rather than to us, so it cannot
/// reach a `State` inside the sheet — the same arrangement the Board's due-date
/// and rhythm sheets use.
class _RepeatDraft {
  EventRepeat repeat;
  DateTime? until;
  DateTime start;

  /// Set by the header's check. Without it a dismissal and a save would be
  /// indistinguishable, and closing with the X would apply whatever had been
  /// tapped on the way out.
  bool saved = false;

  _RepeatDraft(this.repeat, this.until, this.start);
}

/// The recurrence picker: the day the rule hangs off, the six rules, and under
/// them the day the series stops.
///
/// **The start is at the top and can be changed here.** Every rule but
/// "Täglich" is read off it — "jeden Montag" is a Monday start plus weekly —
/// so a sheet that only named the weekday left the reader closing it, fixing
/// the date on the form and opening it again to see what the rule had become.
///
/// A sheet rather than a card that unfolds in place. Six choices and an end
/// date pushed the calendar, the notes and "Termin löschen" off the bottom of
/// the form, so opening the one question cost you the sight of every other
/// answer — and the form is read as a whole before it is saved. This is the
/// shape the Board already uses for "Fällig" and for a tracker's rhythm: a row
/// carrying its answer, a sheet holding the choices.
///
/// **Picking a rule does not close it.** The end date is a follow-up question
/// that only exists once something repeats, so a sheet that popped on the first
/// tap could only ever offer a series that runs forever. The header's blue
/// check is the way out, as in every other sheet that submits an answer.
///
/// Returns null when the sheet was dismissed, which is the difference between
/// "leave the rule alone" and any answer the user actually gave.
Future<_RepeatChoice?> _showRepeatSheet(
  BuildContext context, {
  required EventRepeat current,
  required DateTime? until,
  required DateTime start,
}) async {
  final draft = _RepeatDraft(current, until, start);
  await showAppSheet<void>(
    context: context,
    title: L.s.eventRepeat,
    onSave: () => draft.saved = true,
    heightFactor: 0.78,
    child: _RepeatOptions(draft: draft),
  );
  return draft.saved ? _RepeatChoice(draft.repeat, draft.until, draft.start) : null;
}

/// What each rule is called, with the start's own weekday filled in — the rule
/// carries no day of its own, so "Jeden Montag" is only true while the
/// appointment starts on one, and this is read fresh wherever it is drawn.
String _repeatRuleLabel(EventRepeat repeat, DateTime start) {
  final weekday = L.s.weekdayLong[start.weekday % 7];
  return switch (repeat) {
    EventRepeat.never => L.s.repeatNever,
    EventRepeat.daily => L.s.repeatDaily,
    EventRepeat.weekly => L.s.repeatWeekly(weekday),
    EventRepeat.biweekly => L.s.repeatBiweekly(weekday),
    EventRepeat.monthly => L.s.repeatMonthly,
    EventRepeat.yearly => L.s.repeatYearly,
  };
}

/// The answer as the form's row shows it: "Nie", "Jeden Montag", or
/// "Jeden Montag · bis 15. Nov".
///
/// The end rides on the same line rather than taking a row of its own, for the
/// reason the Board's due-date row carries its hour: it is one answer to one
/// question, and a second row saying "Endet" would suggest a series can stop on
/// a day without repeating at all.
String _repeatSummary(EventRepeat repeat, DateTime? until, DateTime start) {
  final rule = _repeatRuleLabel(repeat, start);
  if (repeat == EventRepeat.never || until == null) return rule;
  return '$rule · ${L.s.repeatUntilDate(L.s.dayMonthShort(until.day, until.month))}';
}

class _RepeatOptions extends StatefulWidget {
  final _RepeatDraft draft;

  const _RepeatOptions({required this.draft});

  @override
  State<_RepeatOptions> createState() => _RepeatOptionsState();
}

class _RepeatOptionsState extends State<_RepeatOptions> {
  late EventRepeat _repeat = widget.draft.repeat;
  late DateTime? _until = widget.draft.until;

  /// The event's first day: it names the weekday in the rules, and it is the
  /// floor under the end picker.
  late DateTime _start = widget.draft.start;

  /// Every tap lands on the draft immediately, so the header's check has the
  /// current answer whenever it is pressed.
  void _pickRule(EventRepeat repeat) {
    setState(() {
      _repeat = repeat;
      widget.draft.repeat = repeat;
      // "Nie" takes the end with it: a stop date on a rule that never comes
      // round is an answer to a question the sheet is no longer asking.
      if (repeat == EventRepeat.never) {
        _until = null;
        widget.draft.until = null;
      }
    });
  }

  /// The day only. The hour is the form's business and rides along untouched:
  /// a rule cares which weekday it lands on, never at what time.
  ///
  /// An end left behind by the move is dropped rather than carried, for the
  /// reason the form drops one — a series that ends before it begins is one the
  /// provider accepts and then never shows.
  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(_start.year - 5),
      lastDate: DateTime(_start.year + 5),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _start = DateTime(picked.year, picked.month, picked.day, _start.hour, _start.minute);
      widget.draft.start = _start;
      final until = _until;
      if (until != null && !until.isAfter(DateTime(_start.year, _start.month, _start.day))) {
        _until = null;
        widget.draft.until = null;
      }
    });
  }

  void _setUntil(DateTime? day) {
    setState(() {
      _until = day;
      widget.draft.until = day;
    });
  }

  /// The last day the series may land on. Opens two months out by default,
  /// which is the length of a Kurs — the case the picker exists for.
  Future<void> _pickUntil() async {
    final start = _start;
    final first = DateTime(start.year, start.month, start.day + 1);
    final suggested = DateTime(start.year, start.month + 2, start.day);
    final current = _until;
    final picked = await showDatePicker(
      context: context,
      initialDate: current != null && !current.isBefore(first) ? current : suggested,
      firstDate: first,
      lastDate: DateTime(start.year + 5),
    );
    // The calendar closes over the sheet, which stays open behind it: the date
    // it hands back is a selection like any other, and the header's check is
    // still what applies it.
    if (picked == null || !mounted) return;
    _setUntil(DateTime(picked.year, picked.month, picked.day));
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final until = _until;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The same "Beginn" row as the form's, minus the hour. Here because
        // every rule below is read off it, and changeable here because seeing
        // the wrong day and being unable to fix it is worse than a second way
        // in to one field.
        SectionCard(
          children: [
            _TimeRow(
              label: L.s.startsAt,
              value: _start,
              showTime: false,
              accent: accent,
              onPickDate: _pickStart,
            ),
            CardDivider(),
            _CardNote(text: L.s.repeatFollowsStart),
          ],
        ),
        const SizedBox(height: 14),
        SectionCard(
          children: dividedRows([
            for (final option in EventRepeat.values)
              _ChoiceRow(
                label: _repeatRuleLabel(option, _start),
                selected: option == _repeat,
                accent: accent,
                onTap: () => _pickRule(option),
              ),
          ]),
        ),
        // Nothing to end when nothing repeats. A never-ending series is the
        // ordinary case — a Sportkurs runs until somebody stops going — so this
        // defaults to "Nie" rather than to a date.
        if (_repeat != EventRepeat.never) ...[
          const SizedBox(height: 14),
          SectionCard(
            children: [
              _CardLabel(text: L.s.repeatEnds),
              ...dividedRows([
                _RepeatEndRow(
                  label: L.s.duePickDate,
                  // Carries the date once there is one, so a day picked out of
                  // the calendar is visible on the sheet rather than only after
                  // it closes.
                  hint: until == null ? null : L.s.dayMonthShort(until.day, until.month),
                  selected: until != null,
                  onTap: _pickUntil,
                ),
                _RepeatEndRow(
                  label: L.s.repeatNever,
                  selected: until == null,
                  onTap: () => _setUntil(null),
                ),
              ]),
            ],
          ),
        ],
      ],
    );
  }
}

/// One answer in the end card: the label, the date when there is one, and a
/// check on the one that holds. [_ChoiceRow] with somewhere to put the day.
class _RepeatEndRow extends StatelessWidget {
  final String label;
  final String? hint;
  final bool selected;
  final VoidCallback onTap;

  const _RepeatEndRow({required this.label, this.hint, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.rowTitle),
            ),
            if (hint case final text?) ...[
              Text(text, style: AppText.input.copyWith(color: AppColors.inkTertiary)),
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
