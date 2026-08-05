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

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final options = ref.watch(calendarProvider).writableCalendars;

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
            _LocationField(controller: widget.form.location, accent: accent),
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
                    // The real UISwitch, so Ganztägig looks like the
                    // Dunkelmodus switch in Settings — iOS 26 draws a Liquid
                    // Glass knob that `CupertinoSwitch` doesn't redraw.
                    // This is a platform view inside a sheet body, the thing
                    // [SheetSwitch] exists to avoid; if the card below this row
                    // ever renders blank on device again, that's the failure
                    // coming back and `SheetSwitch` is the one-line fallback.
                    NativeSwitch(value: _draft.allDay, onChanged: _setAllDay),
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
        // Every writable calendar, listed. It used to be a row that opened a
        // second sheet on top of this one — two taps and a screen change to
        // answer a question that fits in the form, and the answer was hidden
        // behind a name until you opened it.
        SectionCard(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 13, 16, 9),
              child: Text(L.s.calendar, style: AppText.microLabel),
            ),
            if (options.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Text(
                  L.s.noWritableCalendar,
                  style: AppText.input.copyWith(color: AppColors.inkTertiary),
                ),
              )
            else
              ...dividedRows([
                for (final option in options)
                  _CalendarOptionRow(
                    source: option,
                    selected: option.id == _draft.calendarId,
                    onTap: () => _draft = _draft.copyWith(calendarId: option.id),
                  ),
              ]),
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

/// The "Ort" row, with the device's own place search under it.
///
/// The field stayed free text for a long time and typing into it did nothing,
/// which is the wrong shape for what people actually put there: an appointment
/// is at Rossmann, at the Zahnarzt, at a street address somebody read off a
/// letter. [searchPlaces] answers with **businesses as well as addresses**,
/// biased towards the household's own town, and picking one writes the whole
/// thing — name *and* address — into the field, so the detail sheet's map and
/// the route menu can find it afterwards.
///
/// Free text still wins: nothing here forces a choice. A place MapKit has never
/// heard of ("Turnhalle") is typed and saved exactly as before.
class _LocationField extends ConsumerStatefulWidget {
  final TextEditingController controller;
  final Color accent;

  const _LocationField({required this.controller, required this.accent});

  @override
  ConsumerState<_LocationField> createState() => _LocationFieldState();
}

class _LocationFieldState extends ConsumerState<_LocationField> {
  /// Below this a query is mostly noise — "Al" matches half of Germany, and
  /// every keystroke costs a MapKit request.
  static const _minQuery = 3;

  final FocusNode _focus = FocusNode();
  Timer? _debounce;

  /// Which request the answer on screen belongs to. Typing is faster than the
  /// network, so a slow "Ros" landing after a quick "Rossmann" would otherwise
  /// replace the right list with a stale one.
  int _request = 0;

  /// The query [_results] answers. Also what stops a re-search when the text
  /// comes back to something already asked — a backspace, or the field being
  /// focused again after a pick.
  String _asked = '';
  List<PlaceSuggestion> _results = const [];
  bool _answered = false;

  @override
  void initState() {
    super.initState();
    // The list belongs to the field being edited: losing focus puts the form
    // back the way it looks when it is opened.
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final text = value.trim();
    if (text.length < _minQuery) {
      setState(() {
        _asked = text;
        _results = const [];
        _answered = false;
      });
      return;
    }
    if (text == _asked) return;
    _debounce = Timer(const Duration(milliseconds: 250), () => _search(text));
  }

  Future<void> _search(String text) async {
    final token = ++_request;
    final found = await searchPlaces(
      query: text,
      // The town from onboarding, never device GPS — same rule the weather
      // follows. It only biases the ranking; a search for a place in another
      // city still finds it.
      near: ref.read(familyProvider).household?.address,
    );
    if (!mounted || token != _request) return;
    setState(() {
      _asked = text;
      _results = found;
      _answered = true;
    });
  }

  void _pick(PlaceSuggestion place) {
    final value = place.value;
    widget.controller.text = value;
    widget.controller.selection = TextSelection.collapsed(offset: value.length);
    _debounce?.cancel();
    _request++; // whatever is still in flight answers a question already settled
    setState(() {
      _asked = value;
      _results = const [];
      _answered = false;
    });
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final searching = _focus.hasFocus && _asked.length >= _minQuery;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: AppColors.surfaceAlt, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Icon(LucideIcons.mapPin, size: 16, color: widget.accent),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.search,
                  style: AppText.input,
                  onChanged: _onChanged,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: L.s.searchPlace,
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (searching)
          for (final place in _results) ...[
            InsetDivider(),
            _PlaceRow(place: place, onTap: () => _pick(place)),
          ],
        if (searching && _results.isEmpty && _answered) ...[
          InsetDivider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(57, 12, 16, 13),
            child: Text(L.s.noPlacesFound, style: AppText.label),
          ),
        ],
      ],
    );
  }
}

/// One suggestion: the name on top, where it is underneath.
class _PlaceRow extends StatelessWidget {
  final PlaceSuggestion place;
  final VoidCallback onTap;

  const _PlaceRow({required this.place, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
        child: Row(
          children: [
            Icon(LucideIcons.mapPin, size: 15, color: AppColors.mutedLight),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    place.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.rowTitle,
                  ),
                  if (place.address.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      place.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.label,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One destination in the calendar card — the colour dot, the name, and a check
/// on the one this event is going to.
class _CalendarOptionRow extends StatelessWidget {
  final CalendarSource source;
  final bool selected;
  final VoidCallback onTap;

  const _CalendarOptionRow({required this.source, required this.selected, required this.onTap});

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
