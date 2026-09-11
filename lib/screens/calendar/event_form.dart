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
    requiredField: form.title,
    onSave: () async {
      // The chip is the only sign a write to a *connected* calendar went out —
      // the event itself only shows up once the next `calendar-events` read
      // brings it back from the provider.
      //
      // And that takes **seconds**, not a moment: the write goes out to Google,
      // Outlook or a school's CalDAV server and the read then goes out to all
      // of them again. A confirmation that only appears at the end of that
      // leaves the sheet closing onto a calendar with nothing new in it, which
      // reads as a save that silently failed. So the chip goes up *now*, with a
      // spinner, and says which calendar the appointment is going into; the
      // notifier moves it on to the refresh, and the spinner becomes the tick.
      final draft = form.result();
      final calendar = ref.read(calendarProvider).sourceById(draft.calendarId)?.name;
      final chip = showPendingChip(
        context,
        calendar == null ? L.s.eventBeingCreated : L.s.eventBeingCreatedIn(calendar),
      );
      if (await notifier.createEvent(draft, onProgress: chip.step)) {
        chip.done(L.s.eventCreated);
      } else {
        // Taken down rather than turned red: the screen already listens on
        // `state.error` and puts the failure up itself, and two chips saying
        // the same thing is one too many.
        chip.dismiss();
      }
    },
    child: _EventFormBody(form: form),
  );
}

/// Reopens an existing event in the same form it was created in.
///
/// One form for both, deliberately: a create sheet richer than the edit sheet is
/// how you end up with a location that can be typed once and never corrected.
///
/// Answers `true` when the event was **deleted** from in here rather than
/// saved. That is for the detail sheet, which opens this one from its header
/// and has to go away with it — it would otherwise be left describing an
/// appointment the calendar no longer has. Swiping straight to the edit sheet
/// from an agenda card ignores the answer; there is nothing behind it.
Future<bool> _openEditEventSheet(BuildContext context, WidgetRef ref, CalendarEvent event) async {
  final notifier = ref.read(calendarProvider.notifier);
  final form = _EventForm(EventDraft.of(event));
  final deleted = await showAppSheet<bool>(
    context: context,
    title: L.s.editEvent,
    // Deliberately *not* guarded on the title, unlike the create sheet: an
    // appointment proxied from Google or Outlook may genuinely have no summary,
    // and somebody fixing its time should not be made to name it first.
    onSave: () async {
      final confirm = confirmChipOf(context);
      if (await notifier.saveEvent(event, form.result(), scope: form.scope)) {
        confirm(L.s.eventUpdated);
      }
    },
    child: _EventFormBody(form: form, event: event),
  );
  return deleted ?? false;
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

  /// Which occurrences a save reaches, on an event that repeats. Lives here
  /// rather than on [EventDraft] because it is not a property of the
  /// appointment — it is an answer about this one edit, and the sheet's save
  /// button needs it at the same moment it needs the draft.
  EventScope scope = EventScope.single;

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

  /// The event being edited, or null when this is a new one. Only "Termin
  /// löschen" needs it — there is nothing to delete before the first save.
  final CalendarEvent? event;

  const _EventFormBody({required this.form, this.event});

  @override
  ConsumerState<_EventFormBody> createState() => _EventFormBodyState();
}

class _EventFormBodyState extends ConsumerState<_EventFormBody> {
  /// Whether the repeat card is showing its six choices.
  ///
  /// Collapsed by default and expanded in place rather than opened as a menu:
  /// this sheet's chrome is native glass, and Flutter content composited after a
  /// platform view is dropped whole on device — the same reason "Ganztägig" is a
  /// [SheetSwitch]. An inline list is also what the calendar card below already
  /// does, so the sheet has one way of asking a multiple-choice question.
  bool _repeatOpen = false;

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
  ///
  /// A repeat end left behind by the move is dropped rather than carried: a
  /// series that ends before it begins is one the provider accepts and then
  /// never shows, which reads as the save having failed.
  void _setStart(DateTime next) {
    if (_draft.allDay) {
      final start = DateTime(next.year, next.month, next.day);
      final days = _draft.end.difference(_draft.start).inDays.clamp(1, 400);
      _draft = _withValidRepeatEnd(_draft.copyWith(start: start, end: _addDays(start, days)));
      return;
    }
    final length = _draft.end.difference(_draft.start);
    _draft = _withValidRepeatEnd(_draft.copyWith(start: next, end: next.add(length)));
  }

  static EventDraft _withValidRepeatEnd(EventDraft draft) {
    final until = draft.repeatUntil;
    if (until == null) return draft;
    final firstDay = DateTime(draft.start.year, draft.start.month, draft.start.day);
    return until.isBefore(firstDay) ? draft.copyWith(clearRepeatUntil: true) : draft;
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

  /// What each rule is called, with the start's own weekday filled in — the
  /// rule carries no day of its own, so "Jeden Montag" is only true while the
  /// appointment starts on one, and this is read fresh on every rebuild.
  String _repeatLabel(EventRepeat repeat) {
    final weekday = L.s.weekdayLong[_draft.start.weekday % 7];
    return switch (repeat) {
      EventRepeat.never => L.s.repeatNever,
      EventRepeat.daily => L.s.repeatDaily,
      EventRepeat.weekly => L.s.repeatWeekly(weekday),
      EventRepeat.biweekly => L.s.repeatBiweekly(weekday),
      EventRepeat.monthly => L.s.repeatMonthly,
      EventRepeat.yearly => L.s.repeatYearly,
    };
  }

  /// "Nie", or the last day the series may land on.
  String get _repeatEndLabel {
    final until = _draft.repeatUntil;
    return until == null ? L.s.repeatNever : L.s.dayMonth(until.day, until.month);
  }

  void _setRepeat(EventRepeat repeat) {
    setState(() {
      _repeatOpen = false;
      widget.form.draft = repeat == EventRepeat.never
          ? _draft.copyWith(repeat: repeat, clearRepeatUntil: true)
          : _draft.copyWith(repeat: repeat);
    });
  }

  /// The last day the series may land on. Opens two months out by default,
  /// which is the length of a Kurs — the case the picker exists for.
  Future<void> _pickRepeatEnd() async {
    final first = _addDays(DateTime(_draft.start.year, _draft.start.month, _draft.start.day), 1);
    final suggested = DateTime(_draft.start.year, _draft.start.month + 2, _draft.start.day);
    final current = _draft.repeatUntil;
    final picked = await showDatePicker(
      context: context,
      initialDate: current != null && !current.isBefore(first) ? current : suggested,
      firstDate: first,
      lastDate: DateTime(_draft.start.year + 5),
    );
    if (picked == null || !mounted) return;
    _draft = _draft.copyWith(repeatUntil: DateTime(picked.year, picked.month, picked.day));
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
                textInputAction: TextInputAction.next,
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
                    // Flutter's switch, not the real `UISwitch`: a platform
                    // view here is a third one in a sheet that already embeds
                    // two in its header, and iOS then drops the overlay layer
                    // holding everything painted after it — Beginn, Ende, the
                    // calendar card and the notes field all laid out and all
                    // invisible. That regression shipped once already. See
                    // [SheetSwitch]; it must stay a [SheetSwitch].
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
        // How often, and until when.
        //
        // Below the times rather than above them on purpose: the rule is
        // anchored to the start — "jeden Montag" *is* a Monday start plus
        // weekly — so the day it repeats on is already settled by the time this
        // card is read.
        if (widget.event?.repeats == true)
          // An occurrence of an existing series. There is no rule to show: a
          // provider hands back expanded occurrences, so all the app knows is
          // that this one comes round. What it can ask instead is the only
          // question that matters here — how far this edit reaches.
          SectionCard(
            children: [
              _CardLabel(text: L.s.repeatingEvent),
              ...dividedRows([
                _ChoiceRow(
                  label: L.s.thisEventOnly,
                  selected: widget.form.scope == EventScope.single,
                  accent: accent,
                  onTap: () => setState(() => widget.form.scope = EventScope.single),
                ),
                _ChoiceRow(
                  label: L.s.wholeSeries,
                  selected: widget.form.scope == EventScope.series,
                  accent: accent,
                  onTap: () => setState(() => widget.form.scope = EventScope.series),
                ),
              ]),
              CardDivider(),
              _CardNote(text: L.s.repeatNotEditable),
            ],
          )
        else
          SectionCard(
            children: [
              _ValueRow(
                label: L.s.eventRepeat,
                value: _repeatLabel(_draft.repeat),
                onTap: () => setState(() => _repeatOpen = !_repeatOpen),
              ),
              if (_repeatOpen)
                for (final option in EventRepeat.values) ...[
                  InsetDivider(),
                  _ChoiceRow(
                    label: _repeatLabel(option),
                    selected: option == _draft.repeat,
                    accent: accent,
                    onTap: () => _setRepeat(option),
                  ),
                ],
              // Nothing to end when nothing repeats. A never-ending series is
              // the ordinary case — a Sportkurs runs until somebody stops
              // going — so this defaults to "Nie" rather than to a date.
              if (_draft.repeat != EventRepeat.never) ...[
                CardDivider(),
                _ValueRow(
                  label: L.s.repeatEnds,
                  value: _repeatEndLabel,
                  onTap: _pickRepeatEnd,
                  onClear: _draft.repeatUntil == null
                      ? null
                      : () => _draft = _draft.copyWith(clearRepeatUntil: true),
                ),
              ],
            ],
          ),
        const SizedBox(height: 14),
        // Every writable calendar, listed. It used to be a row that opened a
        // second sheet on top of this one — two taps and a screen change to
        // answer a question that fits in the form, and the answer was hidden
        // behind a name until you opened it.
        SectionCard(
          children: [
            // The rows below fill the card, so these two have to be stretched
            // to match — a bare Padding sizes to its text and SectionCard's
            // Column would then centre it.
            SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 13, 16, 9),
                child: Text(L.s.calendar, style: AppText.microLabel),
              ),
            ),
            if (options.isEmpty)
              SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Text(
                    L.s.noWritableCalendar,
                    style: AppText.input.copyWith(color: AppColors.inkTertiary),
                  ),
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
        // The foot of the sheet, the same place and the same widget as the task
        // sheet's "To-do löschen". Here rather than beside "Bearbeiten" on the
        // detail sheet, because deleting is something done *to* the event and
        // this is the sheet you are already in to change it — and it takes the
        // one destructive control in the calendar out of the sheet people open
        // simply to read a time off.
        if (widget.event case final event?) ...[
          const SizedBox(height: 14),
          OutlinedSheetAction(
            icon: AppIcons.trash,
            label: L.s.deleteEvent,
            destructive: true,
            // Pops this sheet with `true` rather than just closing it: the
            // detail sheet underneath, if there is one, closes on that answer.
            onTap: () => _confirmDeleteEvent(
              context,
              ref,
              event,
              onDeleted: () => Navigator.of(context).pop(true),
            ),
          ),
        ],
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
    // No device place search here, so the field is plain free text and nothing
    // is asked. Not merely a search that answers nothing: that would put
    // "Keine Orte gefunden" under every third letter typed on Android, which
    // says the place does not exist when what happened is that nobody looked.
    // See `deviceMapsAvailable`.
    if (!deviceMapsAvailable) return;
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
                child: AppIcon(AppIcons.mapPin, size: 16, color: widget.accent),
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
            AppIcon(AppIcons.mapPin, size: 15, color: AppColors.mutedLight),
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

/// A card's own heading — "Terminserie" over the two scope rows.
///
/// Stretched to the card's width for the same reason the calendar card's
/// heading is: [SectionCard]'s Column would otherwise centre a Padding that
/// sizes itself to its text.
class _CardLabel extends StatelessWidget {
  final String text;

  const _CardLabel({required this.text});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 9),
      child: Text(text, style: AppText.microLabel),
    ),
  );
}

/// A sentence at the foot of a card, explaining why it has nothing more to
/// offer. One line, in the tertiary ink the calendar card's empty state uses.
class _CardNote extends StatelessWidget {
  final String text;

  const _CardNote({required this.text});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 11, 16, 13),
      child: Text(text, style: AppText.label.copyWith(color: AppColors.inkTertiary)),
    ),
  );
}

/// "Wiederholen · Jeden Montag" — a label, the answer, and the whole row as the
/// target, shaped like [_TimeRow] so the two cards read as one column.
///
/// [onClear] adds the small × that takes an answer back to its default. It is
/// only ever the repeat end: every other row here always has a value.
class _ValueRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _ValueRow({
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            // The label sizes to itself and the answer takes the rest,
            // right-aligned: two flexible children would split the row in half
            // and leave a short answer like "Nie" stranded in the middle,
            // out of line with the dates in the card above.
            Text(label, style: AppText.rowTitle),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: AppText.input.copyWith(color: AppColors.inkTertiary),
              ),
            ),
            if (onClear case final clear?) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: clear,
                behavior: HitTestBehavior.opaque,
                child: AppIcon(AppIcons.x, size: 16, color: AppColors.mutedLight),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One answer in a card that asks a question — the label and a check on the one
/// that is chosen. The calendar card's row is the same thing with a colour dot;
/// this is for the lists that have nothing to put in front of the name.
class _ChoiceRow extends StatelessWidget {
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _ChoiceRow({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
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
            if (selected) AppIcon(AppIcons.check, size: 18, color: accent),
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
            if (selected) AppIcon(AppIcons.check, size: 18, color: accent),
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
