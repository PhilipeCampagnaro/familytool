part of '../calendar_screen.dart';

// The sheet an event is created and edited in, and the rows it is built
// from. Reached from the '+' in the title row and from the detail sheet's
// 'Bearbeiten'.

void _openNewEventSheet(BuildContext context, WidgetRef ref) {
  final notifier = ref.read(calendarProvider.notifier);
  final form = _EventForm(notifier.newDraft());
  showAppSheet(
    context: context,
    title: L.s.newEvent,
    onSave: () async {
      // The chip is the only sign a write to a *connected* calendar went out —
      // the event itself only shows up once the next `calendar-events` read
      // brings it back from the provider.
      final confirm = confirmChipOf(context);
      if (await notifier.createEvent(form.result())) confirm(L.s.eventCreated);
    },
    child: _EventFormBody(form: form),
  );
}

/// Reopens an existing event in the same form it was created in.
///
/// One form for both, deliberately: a create sheet richer than the edit sheet is
/// how you end up with a location that can be typed once and never corrected.
void _openEditEventSheet(BuildContext context, WidgetRef ref, CalendarEvent event) {
  final notifier = ref.read(calendarProvider.notifier);
  final form = _EventForm(EventDraft.of(event));
  showAppSheet(
    context: context,
    title: L.s.editEvent,
    onSave: () async {
      final confirm = confirmChipOf(context);
      if (await notifier.saveEvent(event, form.result())) confirm(L.s.eventUpdated);
    },
    child: _EventFormBody(form: form),
  );
}

/// The event being typed, held by reference.
///
/// The sheet's save button belongs to the shared chrome ([showAppSheet]) and is
/// handed its callback before the body exists, so the two need one object
/// between them — the same arrangement `IconDraft` uses.
class _EventForm {
  _EventForm(this.draft)
      : title = TextEditingController(text: draft.title),
        location = TextEditingController(text: draft.location),
        notes = TextEditingController(text: draft.notes);

  /// Everything that is not free text. The three controllers below own their own
  /// fields, so rebuilding on every keystroke isn't necessary.
  EventDraft draft;

  final TextEditingController title;
  final TextEditingController location;
  final TextEditingController notes;

  EventDraft result() =>
      draft.copyWith(title: title.text, location: location.text, notes: notes.text);

  void dispose() {
    title.dispose();
    location.dispose();
    notes.dispose();
  }
}

class _EventFormBody extends ConsumerStatefulWidget {
  final _EventForm form;

  const _EventFormBody({required this.form});

  @override
  ConsumerState<_EventFormBody> createState() => _EventFormBodyState();
}

class _EventFormBodyState extends ConsumerState<_EventFormBody> {
  EventDraft get _draft => widget.form.draft;
  set _draft(EventDraft value) => setState(() => widget.form.draft = value);

  @override
  void dispose() {
    widget.form.dispose();
    super.dispose();
  }

  /// The end the user sees. An all-day event carries an **exclusive** end, so a
  /// single day on the 5th is stored as ending on the 6th — showing that would
  /// read as a two-day event to everyone except a calendar developer.
  DateTime get _shownEnd => _draft.allDay ? _addDays(_draft.end, -1) : _draft.end;

  /// Calendar-correct, unlike `add(Duration(days: 1))`: adding 24 absolute hours
  /// across the March DST change lands at 01:00, and an all-day event that
  /// starts at one in the morning is a bug the user sees.
  static DateTime _addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);

  static DateTime _onDate(DateTime time, DateTime date) =>
      DateTime(date.year, date.month, date.day, time.hour, time.minute);

  static DateTime _atTime(DateTime date, TimeOfDay t) =>
      DateTime(date.year, date.month, date.day, t.hour, t.minute);

  /// Moving the start moves the whole event: a family dragging an appointment an
  /// hour later means later, not longer.
  void _setStart(DateTime next) {
    if (_draft.allDay) {
      final start = DateTime(next.year, next.month, next.day);
      final days = _draft.end.difference(_draft.start).inDays.clamp(1, 400);
      _draft = _draft.copyWith(start: start, end: _addDays(start, days));
      return;
    }
    final length = _draft.end.difference(_draft.start);
    _draft = _draft.copyWith(start: next, end: next.add(length));
  }

  /// [next] is the end as shown — the last day for an all-day event. An end that
  /// would land at or before the start is given back the length it had instead
  /// of producing a zero-length event some servers reject outright.
  void _setEnd(DateTime next) {
    if (_draft.allDay) {
      final last = DateTime(next.year, next.month, next.day);
      final stored = _addDays(last, 1);
      _draft = _draft.copyWith(
        end: stored.isAfter(_draft.start) ? stored : _addDays(_draft.start, 1),
      );
      return;
    }
    _draft = _draft.copyWith(
      end: next.isAfter(_draft.start) ? next : _draft.start.add(const Duration(hours: 1)),
    );
  }

  void _setAllDay(bool value) {
    if (value) {
      final start = DateTime(_draft.start.year, _draft.start.month, _draft.start.day);
      var end = DateTime(_draft.end.year, _draft.end.month, _draft.end.day);
      if (!end.isAfter(start)) end = _addDays(start, 1);
      _draft = _draft.copyWith(allDay: true, start: start, end: end);
    } else {
      // Back to a timed event on the same day. 10:00 rather than the midnight it
      // has been sitting at, which nobody means.
      final start = DateTime(_draft.start.year, _draft.start.month, _draft.start.day, 10);
      _draft = _draft.copyWith(
        allDay: false,
        start: start,
        end: start.add(const Duration(hours: 1)),
      );
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final current = isStart ? _draft.start : _shownEnd;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year - 5),
      lastDate: DateTime(current.year + 5),
    );
    if (picked == null || !mounted) return;
    if (isStart) {
      _setStart(_onDate(_draft.start, picked));
    } else {
      _setEnd(_onDate(_shownEnd, picked));
    }
  }

  Future<void> _pickTime({required bool isStart}) async {
    final current = isStart ? _draft.start : _draft.end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (picked == null || !mounted) return;
    if (isStart) {
      _setStart(_atTime(_draft.start, picked));
    } else {
      _setEnd(_atTime(_draft.end, picked));
    }
  }

  /// Which calendar the event is written to — and with it, *how*: Aporah's own
  /// is a row of ours, everything else travels back out to the account that
  /// owns it.
  Future<void> _pickCalendar(List<CalendarSource> options) async {
    final picked = await showAppSheet<CalendarSource>(
      context: context,
      header: SheetPickerHeader(title: L.s.calendar),
      heightFactor: 0.6,
      child: SectionCard(
        children: dividedRows([
          for (final option in options)
            _CalendarOptionRow(source: option, selected: option.id == _draft.calendarId),
        ]),
      ),
    );
    if (picked == null || !mounted) return;
    _draft = _draft.copyWith(calendarId: picked.id);
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final options = ref.watch(calendarProvider).writableCalendars;
    final target = options.firstWhere(
      (c) => c.id == _draft.calendarId,
      orElse: () => CalendarSource.ownPlaceholder,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionCard(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              child: TextField(
                controller: widget.form.title,
                textCapitalization: TextCapitalization.sentences,
                style: AppText.inputTitle,
                decoration: InputDecoration(border: InputBorder.none, hintText: L.s.titleLabel, isDense: true),
              ),
            ),
            CardDivider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(color: AppColors.surfaceAlt, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Icon(LucideIcons.mapPin, size: 16, color: accent),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: TextField(
                      controller: widget.form.location,
                      textCapitalization: TextCapitalization.sentences,
                      style: AppText.input,
                      decoration: InputDecoration(border: InputBorder.none, hintText: L.s.place, isDense: true),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SectionCard(
          children: [
            GestureDetector(
              onTap: () => _setAllDay(!_draft.allDay),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                child: Row(
                  children: [
                    Expanded(child: Text(L.s.allDay, style: AppText.rowTitle)),
                    // SheetSwitch, not NativeSwitch — a platform view here makes
                    // iOS drop everything painted below it. See [SheetSwitch].
                    SheetSwitch(value: _draft.allDay, onChanged: _setAllDay),
                  ],
                ),
              ),
            ),
            CardDivider(),
            _TimeRow(
              label: L.s.startsAt,
              value: _draft.start,
              showTime: !_draft.allDay,
              accent: accent,
              onPickDate: () => _pickDate(isStart: true),
              onPickTime: () => _pickTime(isStart: true),
            ),
            CardDivider(),
            _TimeRow(
              label: L.s.endsAt,
              value: _shownEnd,
              showTime: !_draft.allDay,
              accent: accent,
              onPickDate: () => _pickDate(isStart: false),
              onPickTime: () => _pickTime(isStart: false),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SectionCard(
          children: [
            GestureDetector(
              onTap: () => _pickCalendar(options),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                child: Row(
                  children: [
                    Text(L.s.calendar, style: AppText.rowTitle),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(width: 9, height: 9, decoration: BoxDecoration(color: target.color, shape: BoxShape.circle)),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              target.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.input.copyWith(color: AppColors.inkTertiary),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(LucideIcons.chevronRight, size: 16, color: AppColors.mutedLight),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SectionCard(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(L.s.notes, style: AppText.microLabel),
                  const SizedBox(height: 6),
                  TextField(
                    controller: widget.form.notes,
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                    style: AppText.input,
                    decoration: InputDecoration(border: InputBorder.none, hintText: L.s.addNotes, isDense: true),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One destination in the calendar picker. Pops the sheet with its own source —
/// picking *is* the save here, which is why the sheet has no check button.
class _CalendarOptionRow extends StatelessWidget {
  final CalendarSource source;
  final bool selected;

  const _CalendarOptionRow({required this.source, required this.selected});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(source),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: source.color, shape: BoxShape.circle)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                source.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.rowTitle,
              ),
            ),
            if (selected) Icon(LucideIcons.check, size: 18, color: accent),
          ],
        ),
      ),
    );
  }
}

/// "Beginn / Mi, 5. Aug / 10:00" — the date and the time are separate targets,
/// because they open different pickers.
class _TimeRow extends StatelessWidget {
  final String label;
  final DateTime value;
  final bool showTime;
  final Color accent;
  final VoidCallback onPickDate;
  final VoidCallback onPickTime;

  const _TimeRow({
    required this.label,
    required this.value,
    required this.showTime,
    required this.accent,
    required this.onPickDate,
    required this.onPickTime,
  });

  String get _date =>
      '${weekdayShort[value.weekday % 7]}, ${L.s.dayMonthShort(value.day, value.month)}';

  String get _time => formatTime(value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppText.rowTitle)),
          GestureDetector(
            onTap: onPickDate,
            behavior: HitTestBehavior.opaque,
            child: Text(_date, style: AppText.input.copyWith(color: AppColors.inkTertiary)),
          ),
          if (showTime) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onPickTime,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: tint(accent, .9), borderRadius: BorderRadius.circular(12)),
                child: Text(_time, style: AppText.rowTitle.copyWith(color: accent)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
