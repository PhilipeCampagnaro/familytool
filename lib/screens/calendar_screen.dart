import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../data/calendar_data.dart';
import '../models/calendar_event.dart';
import '../state/calendar_state.dart';
import '../theme/tokens.dart';
import '../widgets/app_sheet.dart';
import '../widgets/avatar.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/day_circle.dart';
import '../widgets/error_note.dart';
import '../widgets/event_dots.dart';
import '../widgets/glass.dart';
import '../widgets/native_switch.dart';
import '../widgets/swipe_actions.dart';

IconData _weatherIcon(String cond) {
  switch (cond) {
    case 'sun':
      return LucideIcons.sun;
    case 'cloud-sun':
      return LucideIcons.cloudSun;
    case 'rain':
      return LucideIcons.cloudRain;
    default:
      return LucideIcons.cloud;
  }
}

bool _sameDay(CalSelectedDay s, int y, int m, int d) => s.y == y && s.m == m && s.d == d;

bool _isToday(int y, int m, int d) {
  final t = calToday();
  return y == t.year && m == t.month && d == t.day;
}

/// A day's dot colours, already narrowed to the active calendar chip.
///
/// The narrowing now happens inside [CalendarScreenState.dayColors], because
/// `eventsFor` applies the filter by calendar id. Matching on colour, as this
/// used to, silently merged two calendars a household had given the same
/// colour.

/// Year/month `monthOffset` months from the real "today", used to anchor the
/// month view's infinite scroll (offset 0 = today's month, negative = past,
/// positive = future) independent of whichever day is currently selected.
(int, int) _monthAt(int monthOffset) {
  final today = calToday();
  final total = today.month - 1 + monthOffset;
  final year = today.year + (total >= 0 ? total ~/ 12 : (total - 11) ~/ 12);
  final month = ((total % 12) + 12) % 12 + 1;
  return (year, month);
}

class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(calendarProvider);
    final accent = Theme.of(context).colorScheme.primary;

    // A write that didn't land is reported once and then forgotten, so the same
    // message can appear again if the next attempt fails too. This matters more
    // here than anywhere else in the app: the sheet's save button closes the
    // sheet before the write to Google has finished, so without this a family
    // would walk away believing an appointment is in their calendar when it
    // never arrived.
    ref.listen<String?>(calendarProvider.select((s) => s.error), (_, message) {
      if (message == null) return;
      showErrorSnack(context, message);
      ref.read(calendarProvider.notifier).clearError();
    });

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: false,
        // Both views build their own header (title + month/toggle row) inside
        // a scroll-collapsing sliver-or-listener, so it can shrink as their
        // content scrolls — see _WeekView / _MonthView.
        child: state.isWeek ? _WeekView(state: state, accent: accent) : _MonthView(state: state, accent: accent),
      ),
    );
  }
}

/// The screen's "Kalender" title + add button — always visible. [t] (0 =
/// expanded, 1 = fully collapsed) morphs the title from a large left-aligned
/// heading down to a small centered one, matching an iOS large-title nav bar
/// collapse. Both views drive it continuously from scroll offset (the week
/// view via [CollapsingSliverHeaderDelegate], the month view off its own
/// `ScrollController`).
class _TitleRow extends StatelessWidget {
  final double t;
  final VoidCallback onAdd;

  /// Optional control pinned to the far left, alongside the title — the
  /// calendar-filter dropdown lives here, and only while collapsed: it stands
  /// in for the [_ToggleAndChipsRow] chip row, which has scrolled away by
  /// then. See [_leadingOpacity].
  final Widget? leading;

  const _TitleRow({required this.t, required this.onAdd, this.leading});

  /// The filter dropdown duplicates the chip row, so it stays hidden until
  /// those chips are essentially gone — it fades in over the last 40% of the
  /// collapse rather than cross-fading against the control it replaces.
  double get _leadingOpacity => ((t - 0.6) / 0.4).clamp(0.0, 1.0);

  /// Horizontal breathing room reserved on both sides of the collapsed title —
  /// wide enough for the filter pill, which is the wider of the two flanking
  /// controls. Both sides get the *same* inset at t == 1 even though the add
  /// button needs less, because an asymmetric inset is exactly what knocks a
  /// centered title off-center.
  static const _collapsedSideInset = 86.0;

  /// What the title must clear on the right at rest: the add button plus a gap.
  static const _addButtonSlot = 48.0;

  @override
  Widget build(BuildContext context) {
    final leadingOpacity = _leadingOpacity;
    return SizedBox(
      height: 40,
      child: Stack(
        children: [
          // The title is its own full-width layer rather than an `Expanded`
          // sibling of the add button: as a Row child its "center" would be
          // the center of the space the buttons left over, so the collapsed
          // title sat visibly off-center by half the button's width. Spanning
          // the whole row makes centered mean centered, whatever flanks it.
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(
                left: _collapsedSideInset * t,
                right: _addButtonSlot + (_collapsedSideInset - _addButtonSlot) * t,
              ),
              child: Align(
                alignment: Alignment.lerp(Alignment.centerLeft, Alignment.center, t)!,
                child: Text(
                  'Kalender',
                  maxLines: 1,
                  style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, letterSpacing: -0.3, fontSize: 26 - 9 * t, color: AppColors.ink),
                ),
              ),
            ),
          ),
          Positioned(right: 0, top: 0, bottom: 0, child: Center(child: GlassIconButton(icon: LucideIcons.plus, onTap: onAdd))),
          // Overlaid rather than laid out inline for the same reason as the
          // title: reserving width for it would drag the expanded, left-aligned
          // title sideways even at t == 0, where this isn't visible at all.
          if (leading != null && leadingOpacity > 0)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                ignoring: leadingOpacity < 1,
                child: Opacity(opacity: leadingOpacity, child: leading!),
              ),
            ),
        ],
      ),
    );
  }
}

/// Identifies the filter chip row for tests. The day strip is a horizontal
/// `ListView` too, so "the horizontal list in the header" isn't specific enough
/// to find it by.
const calendarChipRowKey = ValueKey('calendarChipRow');

/// Identifies the week view's scrolling day strip for tests.
const calendarDayStripKey = ValueKey('calendarDayStrip');

/// Month/year label + list-vs-grid toggle, and the calendar filter chip row —
/// the part of the header that fades/shrinks away entirely as either view
/// collapses, at which point [_CalendarFilterButton] fades into the title row
/// to take the chips' place. Shared by both views so the two behave
/// identically.
class _ToggleAndChipsRow extends ConsumerWidget {
  final CalendarScreenState state;
  final Color accent;
  final String monthLabel;

  const _ToggleAndChipsRow({required this.state, required this.accent, required this.monthLabel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MonthYearToggleRow(state: state, accent: accent, monthLabel: monthLabel),
        const SizedBox(height: 14),
        SizedBox(
          height: 40,
          child: ListView(
            key: calendarChipRowKey,
            scrollDirection: Axis.horizontal,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _CalendarChip(
                  label: 'Alle',
                  color: AppColors.muted,
                  active: state.calendarFilter == null,
                  onTap: () => ref.read(calendarProvider.notifier).clearCalendarFilter(),
                ),
              ),
              for (final src in state.activeSources)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _CalendarChip(
                    label: src.name,
                    color: src.color,
                    active: state.calendarFilter == src.id,
                    onTap: () => ref.read(calendarProvider.notifier).setCalendarFilter(src.id),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Month/year label (crossfading as the visible month changes) + the
/// list-vs-grid view toggle — shared by the week view's full header
/// ([_ToggleAndChipsRow]) and the month view's own collapsing header.
class _MonthYearToggleRow extends StatelessWidget {
  final CalendarScreenState state;
  final Color accent;
  final String monthLabel;

  const _MonthYearToggleRow({required this.state, required this.accent, required this.monthLabel});

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero).animate(animation),
                  child: child,
                ),
              ),
              child: Text(monthLabel, key: ValueKey(monthLabel), style: AppText.sectionHeading),
            ),
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(20)),
              child: Row(
                children: [
                  _ViewToggleButton(icon: LucideIcons.list, active: state.isWeek, accent: accent, onTap: () => ref.read(calendarProvider.notifier).setWeekView()),
                  _ViewToggleButton(icon: LucideIcons.layoutPanelLeft, active: !state.isWeek, accent: accent, onTap: () => ref.read(calendarProvider.notifier).setMonthView()),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

void _openNewEventSheet(BuildContext context, WidgetRef ref) {
  final notifier = ref.read(calendarProvider.notifier);
  final form = _EventForm(notifier.newDraft());
  showAppSheet(
    context: context,
    title: 'Neuer Termin',
    onSave: () => notifier.createEvent(form.result()),
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
    title: 'Termin bearbeiten',
    onSave: () => notifier.saveEvent(event, form.result()),
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
      header: const SheetPickerHeader(title: 'Kalender'),
      heightFactor: 0.6,
      child: SectionCard(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) CardDivider(),
            _CalendarOptionRow(
              source: options[i],
              selected: options[i].id == _draft.calendarId,
            ),
          ],
        ],
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
                style: TextStyle(fontFamily: 'Poppins', fontSize: 17, fontWeight: FontWeight.w500, color: AppColors.ink),
                decoration: const InputDecoration(border: InputBorder.none, hintText: 'Titel', isDense: true),
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
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 16, color: AppColors.ink),
                      decoration: const InputDecoration(border: InputBorder.none, hintText: 'Ort', isDense: true),
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
                    Expanded(child: Text('Ganztägig', style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.ink))),
                    // SheetSwitch, not NativeSwitch — a platform view here makes
                    // iOS drop everything painted below it. See [SheetSwitch].
                    SheetSwitch(value: _draft.allDay, onChanged: _setAllDay),
                  ],
                ),
              ),
            ),
            CardDivider(),
            _TimeRow(
              label: 'Beginn',
              value: _draft.start,
              showTime: !_draft.allDay,
              accent: accent,
              onPickDate: () => _pickDate(isStart: true),
              onPickTime: () => _pickTime(isStart: true),
            ),
            CardDivider(),
            _TimeRow(
              label: 'Ende',
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
                    Text('Kalender', style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.ink)),
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
                              style: TextStyle(fontFamily: 'Poppins', fontSize: 15, color: AppColors.inkTertiary),
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
                  Text('Notizen', style: AppText.microLabel),
                  const SizedBox(height: 6),
                  TextField(
                    controller: widget.form.notes,
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 15, color: AppColors.ink),
                    decoration: const InputDecoration(border: InputBorder.none, hintText: 'Notizen hinzufügen', isDense: true),
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
                style: TextStyle(fontFamily: 'Poppins', fontSize: 15.5, fontWeight: FontWeight.w500, color: AppColors.ink),
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

  String get _date => '${weekdayShort[value.weekday % 7]}, ${value.day}. ${monthShort[value.month]}';

  String get _time =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.ink))),
          GestureDetector(
            onTap: onPickDate,
            behavior: HitTestBehavior.opaque,
            child: Text(_date, style: TextStyle(fontFamily: 'Poppins', fontSize: 15, color: AppColors.inkTertiary)),
          ),
          if (showTime) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onPickTime,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: tint(accent, .9), borderRadius: BorderRadius.circular(12)),
                child: Text(_time, style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w500, color: accent)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ViewToggleButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  const _ViewToggleButton({required this.icon, required this.active, required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 34,
        decoration: BoxDecoration(
          color: active ? AppColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(17),
          boxShadow: active ? AppShadows.thumb : null,
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 17, color: active ? accent : AppColors.muted),
      ),
    );
  }
}

/// A single calendar's filter chip in the shared header — same outline-ring
/// (1.5px inset) as the day circles, but coloured per calendar source instead
/// of the app accent. Shown above both week and month views; tapping the
/// active chip again clears the filter (shows every calendar).
class _CalendarChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool active;
  final VoidCallback onTap;

  const _CalendarChip({required this.label, required this.color, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(27),
          border: Border.all(color: active ? color : Colors.transparent, width: 1.5),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: active ? tint(color, .82) : AppColors.surfaceAlt, borderRadius: BorderRadius.circular(24)),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 7),
              Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 13.5, fontWeight: active ? FontWeight.w600 : FontWeight.w400, color: active ? AppColors.ink : AppColors.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact "liquid glass" dropdown standing in for the filter chip row once
/// the header has collapsed — the chips don't fit a collapsed header, so this
/// pins a small dot (the active source's colour, or muted for "Alle") +
/// chevron in the title row itself, opening a native-feeling glass menu (dot
/// + full name per calendar) to pick a filter from. Only visible while
/// collapsed; see [_TitleRow.leading].
class _CalendarFilterButton extends ConsumerWidget {
  final CalendarScreenState state;

  const _CalendarFilterButton({required this.state});

  Color get _dotColor {
    final filter = state.calendarFilter;
    if (filter == null) return AppColors.muted;
    return state.sourceById(filter)?.color ?? AppColors.muted;
  }

  Future<void> _openMenu(BuildContext context, WidgetRef ref) async {
    final button = context.findRenderObject() as RenderBox;
    final anchor = button.localToGlobal(Offset.zero) & button.size;
    final selected = await Navigator.of(context).push(_FilterMenuRoute(anchor: anchor, state: state));
    if (selected == null) return;
    if (selected.isEmpty) {
      ref.read(calendarProvider.notifier).clearCalendarFilter();
    } else {
      ref.read(calendarProvider.notifier).setCalendarFilter(selected);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAll = state.calendarFilter == null;
    return GestureDetector(
      onTap: () => _openMenu(context, ref),
      child: SizedBox(
        height: 40,
        child: Center(
          child: GlassSurface(
            borderRadius: BorderRadius.circular(18),
            // No forced `tint`: on iOS this is a real UIGlassEffect, and
            // pinning its tintColor to a near-opaque grey made it render as a
            // flat pill instead of glass. The Flutter approximation still
            // needs a light colour to keep the chevron legible.
            fallbackTint: AppColors.navPillTint,
            blurSigma: 16,
            boxShadow: AppShadows.glassButton,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: isAll ? 13 : 12, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // "Alle" is spelled out — a plain gray dot doesn't read as
                  // "everything" the way a source's own colour reads as that
                  // source. Once a specific calendar is picked, its dot alone
                  // is unambiguous, so the label drops back to just that.
                  if (isAll)
                    Text('Alle', style: TextStyle(fontFamily: 'Poppins', fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.muted))
                  else
                    Container(width: 9, height: 9, decoration: BoxDecoration(color: _dotColor, shape: BoxShape.circle)),
                  const SizedBox(width: 7),
                  Icon(LucideIcons.chevronDown, size: 15, color: AppColors.inkTertiary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Anchored dropdown route for [_CalendarFilterButton]. This used to be
/// `showMenu` + a single disabled `PopupMenuItem`, but that route animates by
/// growing the panel's height while staggering each item's own fade — behind
/// a translucent glass surface that read as a smeared, half-drawn slab
/// overlapping the grid rather than a menu. This instead lays the finished
/// panel out under the button and scales + fades it out of its anchor corner,
/// the way a UIKit menu opens.
class _FilterMenuRoute extends PopupRoute<String> {
  /// The filter button's rect in global coordinates.
  final Rect anchor;
  final CalendarScreenState state;

  _FilterMenuRoute({required this.anchor, required this.state});

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String get barrierLabel => 'Schließen';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 200);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 140);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    final size = MediaQuery.sizeOf(context);
    return Stack(
      children: [
        Positioned(
          // Left-aligned with the button, nudged back inside the screen if a
          // wide menu would otherwise run off the right edge.
          left: anchor.left.clamp(AppSpacing.screenPad, (size.width - _FilterMenuSurface.width - AppSpacing.screenPad).clamp(AppSpacing.screenPad, double.infinity)),
          top: anchor.bottom + 6,
          child: _FilterMenuSurface(state: state),
        ),
      ],
    );
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeIn);
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
        alignment: Alignment.topLeft,
        child: child,
      ),
    );
  }
}

/// The [_CalendarFilterButton]'s dropdown content — listing "Alle" plus every
/// calendar source (dot + full name), checkmarking whichever is active.
/// Positioned and dismissed by [_FilterMenuRoute]; this only draws the panel.
///
/// Deliberately *not* a [GlassSurface]: UIKit's own menus aren't liquid glass,
/// they're a near-opaque vibrant material, and a glass panel over the dense
/// month grid just let the day numbers read through the rows. This matches the
/// native menu instead — a blurred backdrop under an almost-solid fill, tight
/// 14pt corners and hairline separators.
class _FilterMenuSurface extends StatelessWidget {
  static const width = 244.0;

  final CalendarScreenState state;

  const _FilterMenuSurface({required this.state});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            ...AppShadows.menu,
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              width: width,
              // Only the last 3% of translucency, so the material still picks
              // up a hint of what's behind it without anything reading through.
              color: AppColors.menuSurface,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _FilterMenuRow(label: 'Alle', color: AppColors.muted, active: state.calendarFilter == null, value: ''),
                  for (final src in state.activeSources) ...[
                    // Hairline, inset past the dot the way a UIKit menu insets
                    // separators past the row's leading icon.
                    Padding(
                      padding: EdgeInsets.only(left: 16),
                      child: Divider(height: 0.5, thickness: 0.5, color: AppColors.menuSeparator),
                    ),
                    _FilterMenuRow(label: src.name, color: src.color, active: state.calendarFilter == src.id, value: src.id),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterMenuRow extends StatelessWidget {
  final String label;
  final Color color;
  final bool active;
  final String value;

  const _FilterMenuRow({required this.label, required this.color, required this.active, required this.value});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 14.5, fontWeight: active ? FontWeight.w600 : FontWeight.w400, color: AppColors.ink),
              ),
            ),
            if (active) Icon(LucideIcons.check, size: 16, color: AppColors.ink),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Week view
// ---------------------------------------------------------------------------

class _WeekView extends ConsumerStatefulWidget {
  final CalendarScreenState state;
  final Color accent;

  const _WeekView({required this.state, required this.accent});

  @override
  ConsumerState<_WeekView> createState() => _WeekViewState();
}

/// The day strip is a plain continuously-scrolling list of days: flick it and
/// it moves by however far you flicked, like any other horizontal list. It used
/// to page a whole week at a time off a drag-velocity threshold, which made
/// small drags either snap seven days away or do nothing at all.
///
/// The list is finite but deep ([_stripDayCount] days centred on today), which
/// is far past anything reachable by flicking and avoids the bookkeeping of a
/// two-directional `center:` sliver for a strip this simple. Days are addressed
/// by index off [_stripEpoch]; [_stripDate] and [_stripIndexOf] convert.
class _WeekViewState extends ConsumerState<_WeekView> {
  static const _stripDaysBefore = 730;
  static const _stripDayCount = 1461;
  static const _stripGap = 6.0;

  static final DateTime _stripEpoch = calToday().subtract(const Duration(days: _stripDaysBefore));

  static DateTime _stripDate(int index) => _stripEpoch.add(Duration(days: index));

  static int _stripIndexOf(DateTime date) => DateTime(date.year, date.month, date.day).difference(_stripEpoch).inDays;

  final ScrollController _stripController = ScrollController();

  /// Per-day extent including its trailing gap, set once the strip has been
  /// laid out — the conversions between scroll offset and day index need it,
  /// and it depends on the available width.
  double _stripItemExtent = 0;

  /// Leftmost fully-visible day, driven by the strip's scroll position. The
  /// month/year header follows this rather than the selected day: on a strip
  /// you can scroll freely without selecting, a header pinned to the selection
  /// would sit there naming a month that's nowhere on screen.
  DateTime _stripAnchor = calToday();

  /// Whether today is currently on screen in the strip — drives the "Heute"
  /// button, which now tracks the strip rather than the selected week.
  bool _todayVisible = true;

  CalSelectedDay? _lastSelected;

  @override
  void initState() {
    super.initState();
    _stripController.addListener(_onStripScroll);
    _lastSelected = widget.state.selected;
  }

  @override
  void dispose() {
    _stripController.dispose();
    super.dispose();
  }

  void _onStripScroll() {
    if (_stripItemExtent <= 0 || !_stripController.hasClients) return;
    final firstIndex = (_stripController.offset / _stripItemExtent).round().clamp(0, _stripDayCount - 1);
    final anchor = _stripDate(firstIndex);
    final todayIndex = _stripIndexOf(calToday());
    final todayVisible = todayIndex >= firstIndex && todayIndex < firstIndex + 7;
    if (anchor != _stripAnchor || todayVisible != _todayVisible) {
      setState(() {
        _stripAnchor = anchor;
        _todayVisible = todayVisible;
      });
    }
  }

  /// Scrolls [date] into view. Used when the selection changes from outside
  /// the strip, and by the "Heute" button — never in response to the user's own
  /// scrolling, since a strip that yanked itself back after every flick would
  /// be unusable.
  void _revealDate(DateTime date, {bool animate = true}) {
    if (_stripItemExtent <= 0 || !_stripController.hasClients) return;
    final index = _stripIndexOf(date);
    final firstIndex = (_stripController.offset / _stripItemExtent).round();
    if (index >= firstIndex && index < firstIndex + 7) return;
    // Land the day third-from-left so there's context on both sides of it.
    final target = ((index - 2) * _stripItemExtent).clamp(0.0, _stripController.position.maxScrollExtent);
    if (animate) {
      _stripController.animateTo(target, duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
    } else {
      _stripController.jumpTo(target);
    }
  }

  void _jumpToToday() {
    ref.read(calendarProvider.notifier).selectDayToday();
    // Scrolled explicitly rather than leaning on the selection-change path in
    // build(): the button's visibility tracks the *strip*, so the common case
    // is that today is still the selected day and the strip has simply been
    // scrolled away from it. `selectDay` is then a no-op and nothing would move.
    _revealDate(calToday());
  }

  // The header's total height at rest (title row + toggle/chips row + day
  // strip) versus what's left once collapsed (title row + the gap below it) —
  // see _buildHeader. Approximates the natural height of that content; minor
  // mismatches just mean a few px of empty/clipped space, not a layout error,
  // since the collapsing math is self-consistent (collapsed + extra always
  // sums back to expanded).
  //
  // _collapsedGap is inside the *collapsed* height on purpose: it's the strip
  // of header that survives below the title row at t == 1, and — since the
  // header has a frosted background (see _buildHeader) — it's the band the gray
  // agenda body passes under blurred, so the sharp gray starts a little below
  // the glass buttons instead of butting straight against them.
  static const _collapsedGap = 14.0;
  static const _collapsedHeaderHeight = 48.0 + _collapsedGap;
  // 16 top + 40 toggle row + 14 + 40 chip row + 12 + the strip + 4 bottom,
  // rounded up so a font-metric wobble leaves slack rather than clipping.
  static const _extraHeaderHeight = 240.0;
  static const _expandedHeaderHeight = _collapsedHeaderHeight + _extraHeaderHeight;

  Widget _buildHeader(BuildContext context, double t, CalendarScreenState state, Color accent, String monthLabel) {
    // Frosted, not transparent and not solid: NestedScrollView's body isn't
    // clipped to below the pinned header — the gray agenda keeps sliding up
    // until its top hits the screen's — so a see-through header had the agenda's
    // first rows rendering sharply behind the title and glass buttons. The blur
    // is what makes them stop reading as content while still showing that
    // they're there, passing underneath (an iOS nav bar).
    //
    // A Stack, not a ColoredBox wrapper, so the frost is a sibling layer that
    // fills the header's *current* extent — as the sliver shrinks, the blurred
    // band shrinks with it.
    return Stack(
      children: [
        Positioned.fill(child: FrostedHeaderBackground()),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.screenPad, 8, AppSpacing.screenPad, 0),
              child: _TitleRow(
                t: t,
                onAdd: () => _openNewEventSheet(context, ref),
                leading: _CalendarFilterButton(state: state),
              ),
            ),
            SizedBox(
              height: _extraHeaderHeight * (1 - t),
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  minHeight: _extraHeaderHeight,
                  maxHeight: _extraHeaderHeight,
                  child: Opacity(
                    opacity: (1 - t).clamp(0.0, 1.0),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(AppSpacing.screenPad, 16, AppSpacing.screenPad, 0),
                          child: _ToggleAndChipsRow(state: state, accent: accent, monthLabel: monthLabel),
                        ),
                        Padding(
                          // Only the left edge is inset: the strip runs to the
                          // right screen edge so days visibly continue off-screen
                          // rather than stopping at a margin, which is what makes
                          // it read as scrollable.
                          padding: const EdgeInsets.fromLTRB(AppSpacing.screenPad, 12, 0, 4),
                          child: SizedBox(height: _stripHeight, child: _buildDayStrip(state, accent)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Kept outside the collapsing block so it survives at t == 1 — this
            // is the band of frost between the header buttons and the sharp
            // gray body.
            const SizedBox(height: _collapsedGap),
          ],
        ),
      ],
    );
  }

  // Weekday letter + gap + the rounded day tile (dots, gap, 34pt day circle).
  static const _stripHeight = 110.0;

  Widget _buildDayStrip(CalendarScreenState state, Color accent) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Size cells so exactly seven fill the screen's usable width — the
        // strip scrolls freely, but a week still lines up with what you see.
        final usable = constraints.maxWidth - AppSpacing.screenPad;
        final cellWidth = (usable - _stripGap * 6) / 7;
        final itemExtent = cellWidth + _stripGap;
        if (itemExtent != _stripItemExtent) {
          _stripItemExtent = itemExtent;
          // First layout: put the selected day's week on screen without an
          // animation, since there's nothing to animate away from yet.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _stripController.hasClients && _stripController.offset != 0) return;
            final sel = widget.state.selected;
            _revealDate(DateTime(sel.y, sel.m, sel.d), animate: false);
            _onStripScroll();
          });
        }
        return ListView.builder(
          key: calendarDayStripKey,
          controller: _stripController,
          scrollDirection: Axis.horizontal,
          itemExtent: itemExtent,
          padding: EdgeInsets.zero,
          itemCount: _stripDayCount,
          itemBuilder: (context, index) {
            final date = _stripDate(index);
            return Padding(
              padding: const EdgeInsets.only(right: _stripGap),
              child: _DayStripCell(
                date: date,
                letter: dayLetters[(date.weekday + 6) % 7],
                state: state,
                accent: accent,
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final accent = widget.accent;
    final sel = state.selected;
    final selDate = DateTime(sel.y, sel.m, sel.d);
    final events = state.eventsFor(sel.y, sel.m, sel.d);
    final headingIsToday = _isToday(sel.y, sel.m, sel.d);
    final headingText = headingIsToday ? 'Heute, ${sel.d}. ${monthNames[sel.m]}' : '${weekdayLong[selDate.weekday % 7]}, ${sel.d}. ${monthNames[sel.m]}';
    // The header names whatever month the strip is actually showing, not the
    // selected day's — see _stripAnchor.
    final monthLabel = '${monthNames[_stripAnchor.month]} ${_stripAnchor.year}';

    // A selection made outside the strip (the "Heute" button) has to be
    // scrolled to; one made by tapping a cell is already on screen, and
    // _revealDate no-ops for it.
    final last = _lastSelected;
    if (last == null || last.y != sel.y || last.m != sel.m || last.d != sel.d) {
      _lastSelected = sel;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _revealDate(selDate);
      });
    }

    return Stack(
      children: [
        NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverPersistentHeader(
              pinned: true,
              delegate: CollapsingSliverHeaderDelegate(
                expandedHeight: _expandedHeaderHeight,
                collapsedHeight: _collapsedHeaderHeight,
                builder: (context, t) => _buildHeader(context, t, state, accent, monthLabel),
              ),
            ),
          ],
          body: _AgendaGrayBody(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero).animate(animation),
                  child: child,
                ),
              ),
              child: KeyedSubtree(
                key: ValueKey('${sel.y}-${sel.m}-${sel.d}-${state.calendarFilter}'),
                child: events.isEmpty
                    ? Padding(
                        padding: EdgeInsets.only(bottom: navContentInset(context)),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Keine Termine an diesem Tag', style: TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w400, color: AppColors.inkTertiary)),
                              const SizedBox(height: 18),
                              GlassAccentButton(label: 'Termin hinzufügen', onTap: () {}),
                            ],
                          ),
                        ),
                      )
                    : ListView(
                        padding: EdgeInsets.only(bottom: navContentInset(context)),
                        children: [
                          for (var i = 0; i < events.length; i++)
                            _EventAgendaRow(
                              event: events[i],
                              isFirst: i == 0,
                              headingText: headingText,
                              accent: accent,
                            ),
                        ],
                      ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: navContentInset(context, pill: 106, gap: 36),
          child: Center(
            child: _JumpToTodayButton(
              visible: !_todayVisible,
              accent: accent,
              onTap: _jumpToToday,
            ),
          ),
        ),
      ],
    );
  }
}

/// Full-width, top-rounded gray body used below the fixed header on both the
/// week view (day strip above the agenda) — kept as its own widget so the
/// gray body treatment can't visually drift from the rest of the screen.
class _AgendaGrayBody extends StatelessWidget {
  final Widget child;

  const _AgendaGrayBody({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppColors.screenBg, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      padding: const EdgeInsets.fromLTRB(14, 20, 16, 0),
      child: child,
    );
  }
}

class _DayStripCell extends ConsumerWidget {
  final DateTime date;
  final String letter;
  final CalendarScreenState state;
  final Color accent;

  const _DayStripCell({required this.date, required this.letter, required this.state, required this.accent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sel = state.selected;
    final isSel = _sameDay(sel, date.year, date.month, date.day);
    final today = _isToday(date.year, date.month, date.day);
    final colors = state.dayColors(date.year, date.month, date.day);
    final dots = colors.take(3).toList();
    final overflowCount = colors.length - 3;

    return GestureDetector(
      onTap: () => ref.read(calendarProvider.notifier).selectDay(date.year, date.month, date.day),
      child: Column(
        children: [
          Text(letter, style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w500, color: isSel ? AppColors.ink : AppColors.muted)),
          const SizedBox(height: 9),
          Container(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
            decoration: BoxDecoration(color: isSel ? tint(accent, .9) : AppColors.screenBg, borderRadius: BorderRadius.circular(22)),
            child: Column(
              children: [
                SizedBox(
                  height: 8,
                  child: Center(child: EventDots(colors: dots, overflowCount: overflowCount)),
                ),
                const SizedBox(height: 14),
                DaySelectorCircle(day: date.day, selected: isSel, today: today, accent: accent),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared agenda-row rail: the time / dot / connecting-line timeline on the
/// left, paired with the event card. Used by both the week view's day agenda
/// and the month view's per-day details box so the timeline isn't drawn
/// twice with two different implementations.
class _EventAgendaRow extends ConsumerWidget {
  final CalendarEvent event;
  final bool isFirst;
  final String headingText;
  final Color accent;
  final bool compact;

  const _EventAgendaRow({required this.event, required this.isFirst, required this.headingText, required this.accent, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(calendarProvider);
    final phase = event.phaseAt(state.now);
    final past = phase == EventPhase.done;
    final live = phase == EventPhase.now;
    final rail = AppColors.hairline2;
    final timeColor = past ? AppColors.muted : (live ? accent : AppColors.inkTertiary);
    // Ferien, Abfall and any calendar the connected account can only read stay
    // untouchable — offering the swipe action there would be a lie. Everything
    // else is editable, including a Google event, which travels back out to
    // Google rather than being changed in a row of ours.
    final editable = state.sourceById(event.calendarId)?.editable ?? false;
    const railAnim = Duration(milliseconds: 320);
    const railCurve = Curves.easeOutCubic;

    return Padding(
      padding: const EdgeInsets.only(bottom: 0),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 42,
              child: Column(
                children: [
                  AnimatedContainer(duration: railAnim, curve: railCurve, width: 2, height: 10, color: isFirst ? Colors.transparent : (past || live ? accent : rail)),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: AnimatedDefaultTextStyle(
                      duration: railAnim,
                      curve: railCurve,
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600, color: timeColor, letterSpacing: -0.3),
                      child: Text(event.timeLabel),
                    ),
                  ),
                  AnimatedContainer(
                    duration: railAnim,
                    curve: railCurve,
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: past ? accent : AppColors.surface, shape: BoxShape.circle, border: Border.all(color: past || live ? accent : rail, width: 2.5)),
                  ),
                  Expanded(child: AnimatedContainer(duration: railAnim, curve: railCurve, width: 2, color: past ? accent : rail)),
                ],
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: compact ? 10 : 14),
                // Swipe-left on a card reveals Edit/Delete, so fixing a title
                // or removing an event doesn't always require opening the full
                // detail sheet first.
                child: SwipeActionsRow(
                  borderRadius: BorderRadius.circular(compact ? 16 : 20),
                  onTap: () {
                    ref.read(calendarProvider.notifier).openEvent(event, headingText);
                    _showEventDetailSheet(context, ref);
                  },
                  actions: [
                    if (editable) ...[
                      SwipeAction(
                        icon: LucideIcons.pencil,
                        color: accent,
                        // No need to open the event first: the edit sheet is
                        // seeded from the row it was swiped on.
                        onTap: () => _openEditEventSheet(context, ref, event),
                      ),
                      SwipeAction(
                        icon: LucideIcons.trash,
                        color: AppColors.danger,
                        // The confirm dialog and the removal own what happens
                        // next; snapping the row shut under it just fights that.
                        closesRow: false,
                        onTap: () => _confirmDeleteEvent(context, ref, event),
                      ),
                    ],
                  ],
                  child: _EventCard(event: event, live: live, accent: accent, compact: compact),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  final CalendarEvent event;
  final bool live;
  final Color accent;
  final bool compact;

  const _EventCard({required this.event, required this.live, required this.accent, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, compact ? 13 : 16, 16, compact ? 14 : 18),
      decoration: BoxDecoration(
        color: live ? tint(accent, .72) : AppColors.surface,
        borderRadius: BorderRadius.circular(compact ? 16 : 20),
        boxShadow: live ? null : AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(event.title, style: TextStyle(fontFamily: 'Poppins', fontSize: compact ? 14.5 : 15.5, fontWeight: FontWeight.w600, color: AppColors.ink, letterSpacing: -0.1)),
          if (!compact) ...[
            const SizedBox(height: 5),
            Text(event.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'Poppins', fontSize: 13.5, fontWeight: FontWeight.w300, color: AppColors.inkTertiary, height: 1.5)),
          ],
          const SizedBox(height: 11),
          Row(
            children: [
              // Layout is in place for the real weather API; until it is wired
              // up nothing has weather, and an event without it shows no
              // placeholder at all. Takes the avatar's old spot, so the title
              // above no longer reserves corner space for it.
              if (event.temp.isNotEmpty) ...[
                Icon(_weatherIcon(event.cond), size: 18, color: accent),
                const SizedBox(width: 6),
                Text(event.temp, style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink)),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _Chip(bg: live ? AppColors.surface.withValues(alpha: .72) : AppColors.surfaceAlt, child: Row(children: [
                        Container(width: 7, height: 7, decoration: BoxDecoration(color: event.srcColor, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text(event.source, style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, fontWeight: FontWeight.w500, color: AppColors.inkSecondary)),
                      ])),
                      const SizedBox(width: 7),
                      _Chip(bg: live ? AppColors.surface.withValues(alpha: .72) : AppColors.surfaceAlt, child: Text(event.durationLabel, style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, fontWeight: FontWeight.w500, color: AppColors.muted))),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final Color bg;
  final Widget child;

  const _Chip({required this.bg, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: child,
    );
  }
}

/// Floating liquid-glass "Heute" pill shown above the bottom nav whenever
/// today's date has scrolled out of view (week view: today isn't in the
/// displayed week; month view: today's day cell isn't in the viewport).
/// Tapping it re-selects today and (in month view) scrolls back to it.
class _JumpToTodayButton extends StatefulWidget {
  final bool visible;
  final Color accent;
  final VoidCallback onTap;

  const _JumpToTodayButton({required this.visible, required this.accent, required this.onTap});

  @override
  State<_JumpToTodayButton> createState() => _JumpToTodayButtonState();
}

class _JumpToTodayButtonState extends State<_JumpToTodayButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !widget.visible,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        offset: widget.visible ? Offset.zero : const Offset(0, 0.7),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          opacity: widget.visible ? 1 : 0,
          child: GestureDetector(
            onTap: widget.onTap,
            onTapDown: (_) => _setPressed(true),
            onTapUp: (_) => _setPressed(false),
            onTapCancel: () => _setPressed(false),
            child: AnimatedScale(
              scale: _pressed ? 0.92 : 1.0,
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              child: GlassSurface(
                borderRadius: BorderRadius.circular(22),
                // Same reasoning as _CalendarFilterButton: let the real
                // UIGlassEffect adapt on iOS, tint only the fallback so the
                // dark "Heute" label stays legible off-iOS.
                fallbackTint: AppColors.navPillTint,
                blurSigma: 20,
                boxShadow: AppShadows.floatingPill,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.calendarCheck, size: 15, color: widget.accent),
                      const SizedBox(width: 7),
                      Text('Heute', style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Month view
// ---------------------------------------------------------------------------

/// Infinite, bidirectionally-scrolling month view (Apple Calendar-style): the
/// legend + weekday header stay fixed, and each visible month is a lazily
/// built [_MonthBlock] below/above a stable `center` sliver anchored on the
/// real "today" month — scrolling never runs out in either direction.
class _MonthView extends ConsumerStatefulWidget {
  final CalendarScreenState state;
  final Color accent;

  const _MonthView({required this.state, required this.accent});

  @override
  ConsumerState<_MonthView> createState() => _MonthViewState();
}

class _MonthViewState extends ConsumerState<_MonthView> {
  final Key _centerKey = UniqueKey();
  final GlobalKey _todayCellKey = GlobalKey();
  final GlobalKey _viewportKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();
  bool _todayVisible = true;

  // The month/year + view-toggle row and the calendar chip row (see
  // _buildHeader) — the part of the header that fades away as the grid
  // scrolls, leaving just the title (shrunk + centered) and the filter
  // dropdown that stands in for the chips + the add button. 16 top padding +
  // 40 toggle row + 14 gap + 40 chip row + 16 bottom padding. Driven directly
  // off `_scrollController.offset` (rather than a NestedScrollView sliver, as
  // the week view uses) since this scroll view already needs its own
  // controller for the "Heute" visibility check below, and a
  // `center:`-anchored CustomScrollView doesn't compose with
  // NestedScrollView's overlap-injection contract.
  static const _extraHeaderHeight = 126.0;
  double _headerT = 0.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _scheduleVisibilityCheck();
  }

  void _onScroll() {
    final next = (_scrollController.offset / _extraHeaderHeight).clamp(0.0, 1.0);
    if (next != _headerT) setState(() => _headerT = next);
    _scheduleVisibilityCheck();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // The scroll listener fires the instant `.offset` changes, before that
  // frame's layout/paint has run — reading render-box positions right then
  // would see last frame's (stale) geometry. Defer to a post-frame callback
  // so the check runs once the new scroll position has actually been laid out.
  void _scheduleVisibilityCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateTodayVisibility();
    });
  }

  /// Checks whether today's day cell (keyed via [_todayCellKey], only ever
  /// attached to the one cell in the `monthOffset == 0` block) currently
  /// intersects the scroll viewport — driving the floating "Heute" button.
  void _updateTodayVisibility() {
    final todayCtx = _todayCellKey.currentContext;
    final viewportCtx = _viewportKey.currentContext;
    bool visible;
    if (todayCtx == null || viewportCtx == null) {
      visible = false;
    } else {
      final todayBox = todayCtx.findRenderObject() as RenderBox;
      final viewportBox = viewportCtx.findRenderObject() as RenderBox;
      final offset = todayBox.localToGlobal(Offset.zero, ancestor: viewportBox);
      visible = offset.dy + todayBox.size.height > 0 && offset.dy < viewportBox.size.height;
    }
    if (visible != _todayVisible) setState(() => _todayVisible = visible);
  }

  void _jumpToToday() {
    ref.read(calendarProvider.notifier).selectDayToday();
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
    }
  }

  /// The collapsing part of the header: title (shrinking + centering via
  /// [_TitleRow], same as the week view), with the month/year + toggle row
  /// and the calendar chips fading away underneath as [_headerT] goes 0 (top
  /// of the grid) to 1 (scrolled in) — at which point the filter dropdown
  /// fades into the title row to stand in for the chips.
  Widget _buildHeader(BuildContext context, CalendarScreenState state, Color accent, String monthLabel) {
    final t = _headerT;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.screenPad, 8, AppSpacing.screenPad, 0),
          child: _TitleRow(
            t: t,
            onAdd: () => _openNewEventSheet(context, ref),
            leading: _CalendarFilterButton(state: state),
          ),
        ),
        SizedBox(
          height: _extraHeaderHeight * (1 - t),
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topCenter,
              minHeight: _extraHeaderHeight,
              maxHeight: _extraHeaderHeight,
              child: Opacity(
                opacity: (1 - t).clamp(0.0, 1.0),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.screenPad, 16, AppSpacing.screenPad, 16),
                  child: _ToggleAndChipsRow(state: state, accent: accent, monthLabel: monthLabel),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final accent = widget.accent;
    final monthLabel = '${monthNames[state.selected.m]} ${state.selected.y}';

    return Column(
      children: [
        _buildHeader(context, state, accent, monthLabel),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.screenPad, 6, AppSpacing.screenPad, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Row(
                children: [
                  SizedBox(
                    width: 13,
                    height: 8,
                    child: Stack(children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: AppColors.srcOutlook, shape: BoxShape.circle, border: Border.fromBorderSide(BorderSide(color: AppColors.surface, width: 1.5)))),
                      Positioned(left: 5, child: Container(width: 8, height: 8, decoration: BoxDecoration(color: AppColors.srcIserv, shape: BoxShape.circle, border: Border.fromBorderSide(BorderSide(color: AppColors.surface, width: 1.5))))),
                    ]),
                  ),
                  const SizedBox(width: 7),
                  Text('Termine je Kalender', style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, fontWeight: FontWeight.w300, color: AppColors.inkTertiary)),
                  const SizedBox(width: 18),
                  Container(width: 13, height: 13, decoration: BoxDecoration(color: tint(accent, .86), shape: BoxShape.circle)),
                  const SizedBox(width: 7),
                  Text('Feiertag', style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, fontWeight: FontWeight.w300, color: AppColors.inkTertiary)),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [for (final l in dayLetters) Expanded(child: SizedBox(height: 26, child: Center(child: Text(l, style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, fontWeight: FontWeight.w500, color: AppColors.muted)))))],
              ),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            key: _viewportKey,
            children: [
              CustomScrollView(
                controller: _scrollController,
                center: _centerKey,
                slivers: [
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _MonthBlock(monthOffset: -i - 1, state: state, accent: accent, todayCellKey: _todayCellKey),
                    ),
                  ),
                  SliverList(
                    key: _centerKey,
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _MonthBlock(monthOffset: i, state: state, accent: accent, todayCellKey: _todayCellKey),
                    ),
                  ),
                ],
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: navContentInset(context, pill: 106, gap: 36),
                child: Center(
                  child: _JumpToTodayButton(visible: !_todayVisible, accent: accent, onTap: _jumpToToday),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One month's heading, day grid, and (if its selected day lives in this
/// month and is expanded) the inline day-detail card — the same widgets
/// [_MonthView] used to render for a single fixed month, now repeated per
/// scrolled-to month so every month behaves identically to "current setup".
class _MonthBlock extends StatelessWidget {
  final int monthOffset;
  final CalendarScreenState state;
  final Color accent;
  final GlobalKey? todayCellKey;

  const _MonthBlock({required this.monthOffset, required this.state, required this.accent, this.todayCellKey});

  @override
  Widget build(BuildContext context) {
    final (year, month) = _monthAt(monthOffset);
    final holidays = state.holidaysIn(year, month);
    final firstOfMonth = DateTime(year, month, 1);
    final lead = (firstOfMonth.weekday + 6) % 7;
    final len = DateTime(year, month + 1, 0).day;

    final sel = state.selected;
    final isSelectedMonth = sel.y == year && sel.m == month;
    final selDate = DateTime(sel.y, sel.m, sel.d);
    final headingText = _isToday(sel.y, sel.m, sel.d) ? 'Heute, ${sel.d}. ${monthNames[sel.m]}' : '${weekdayLong[selDate.weekday % 7]}, ${sel.d}. ${monthNames[sel.m]}';
    final dayEvents = isSelectedMonth ? state.eventsFor(sel.y, sel.m, sel.d) : const <CalendarEvent>[];

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screenPad, 20, AppSpacing.screenPad, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${monthNames[month]} $year', style: AppText.sectionHeading),
          const SizedBox(height: 10),
          for (var row = 0; row < ((lead + len) / 7).ceil(); row++)
            Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: _MonthCell(
                      key: (monthOffset == 0 && row * 7 + col - lead + 1 == calToday().day) ? todayCellKey : null,
                      index: row * 7 + col,
                      lead: lead,
                      len: len,
                      year: year,
                      month: month,
                      state: state,
                      accent: accent,
                      holidays: holidays,
                    ),
                  ),
              ],
            ),
          if (isSelectedMonth)
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 280),
              sizeCurve: Curves.easeOutCubic,
              firstCurve: Curves.easeOut,
              secondCurve: Curves.easeIn,
              crossFadeState: state.monthDetailExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              firstChild: const SizedBox(width: double.infinity, height: 0),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Container(
                  decoration: BoxDecoration(color: AppColors.screenBg, borderRadius: BorderRadius.all(Radius.circular(20))),
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(child: Text(headingText, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'Poppins', fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.ink))),
                          const SizedBox(width: 8),
                          Text(dayEvents.length == 1 ? '1 Termin' : '${dayEvents.length} Termine', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w300, color: AppColors.muted)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (dayEvents.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Column(
                            children: [
                              Text('Keine Termine an diesem Tag', style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w300, color: AppColors.inkTertiary)),
                              const SizedBox(height: 14),
                              GlassAccentButton(label: 'Termin hinzufügen', onTap: () {}),
                            ],
                          ),
                        )
                      else
                        for (var i = 0; i < dayEvents.length; i++)
                          _EventAgendaRow(
                            event: dayEvents[i],
                            isFirst: i == 0,
                            headingText: headingText,
                            accent: accent,
                            compact: true,
                          ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Small source-colour dots under a day, overlapping by 0.5px like the
/// reference design (Flutter disallows negative padding/margin, so the
/// overlap is done via Stack + Positioned offsets instead).
class _MonthCell extends ConsumerWidget {
  final int index;
  final int lead;
  final int len;
  final int year;
  final int month;
  final CalendarScreenState state;
  final Color accent;
  final Set<int> holidays;

  const _MonthCell({super.key, required this.index, required this.lead, required this.len, required this.year, required this.month, required this.state, required this.accent, required this.holidays});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (index < lead || index - lead >= len) return const SizedBox(height: 50);
    final n = index - lead + 1;
    final isSel = _sameDay(state.selected, year, month, n);
    final isToday = _isToday(year, month, n);
    final holiday = holidays.contains(n);
    final colors = state.dayColors(year, month, n);
    final dots = colors.take(3).toList();
    final overflowCount = colors.length - 3;

    return GestureDetector(
      onTap: () => ref.read(calendarProvider.notifier).selectDay(year, month, n),
      child: SizedBox(
        height: 50,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DaySelectorCircle(
              day: n,
              selected: isSel,
              today: isToday,
              holiday: holiday,
              accent: accent,
              size: 38,
              fontSize: 15,
              unselectedFill: Colors.transparent,
              unselectedTextColor: AppColors.ink,
              holidayFill: tint(accent, .86),
                          ),
            const SizedBox(height: 3),
            SizedBox(
              height: 8,
              child: Center(child: EventDots(colors: dots, overflowCount: overflowCount)),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Event detail sheet
// ---------------------------------------------------------------------------

/// Builds the event-detail sheet's collapsing header: the title and the close
/// button share the first row, and the source/owner chips sit on a second row
/// underneath that fades and shrinks away as the sheet's body is scrolled
/// (same mechanism as the Kalender week view's own header — see
/// [CollapsingSliverHeaderDelegate]). The title always stays visible, morphing
/// from a large left-aligned heading down to a small centered one.
Widget _buildEventDetailHeader(BuildContext context, WidgetRef ref, double t) {
  final state = ref.watch(calendarProvider);
  final e = state.openEvent;
  if (e == null) return const SizedBox.shrink();
  final tone = AppTones.list[e.ownerTone];

  // Everything is laid out absolutely against the header's *expanded* geometry
  // and the Stack (hardEdge by default) clips whatever no longer fits as the
  // sliver shrinks. That's deliberately simpler than shrinking a Column child
  // with ClipRect + OverflowBox: the rows never move or re-lay-out, so the
  // title can't shift a pixel as the chips go away.
  return Stack(
    children: [
      // Frosted for the same reason as the week view's header (see
      // _WeekViewState._buildHeader): a sheet's NestedScrollView body isn't
      // clipped to below the pinned header, so the sheet's gray content slides
      // up underneath — blurred, rather than reading sharply through the title.
      Positioned.fill(child: FrostedHeaderBackground()),
      // Below the title row, and painted before it: the chips are the part that
      // collapses away, so putting them first in the Column used to push the
      // title down a line and strand the close button beside them.
      Positioned(
        top: _eventDetailTopPad + _eventDetailTitleRowHeight,
        left: 22,
        right: 22,
        height: _eventDetailChipsRowHeight,
        child: Opacity(
          opacity: (1 - t).clamp(0.0, 1.0),
          child: Padding(
            padding: const EdgeInsets.only(top: _eventDetailChipsGap),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                  decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(14)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 7, height: 7, decoration: BoxDecoration(color: e.srcColor, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(e.source, style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, fontWeight: FontWeight.w500, color: AppColors.inkSecondary)),
                  ]),
                ),
                // An event has no owner until there is an account behind the
                // app; the chip is dropped rather than shown blank.
                if (e.owner.isNotEmpty) ...[
                  const SizedBox(width: 7),
                  Container(
                    padding: const EdgeInsets.fromLTRB(3, 3, 11, 3),
                    decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(14)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Avatar(size: 21, bg: tone.bg, fg: tone.fg, initials: e.ownerInitial, fontSize: 9),
                      const SizedBox(width: 6),
                      Text(e.owner, style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, fontWeight: FontWeight.w500, color: AppColors.inkSecondary)),
                    ]),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      // Title layer: full width, not a Row sibling of the close button — as a
      // sibling its centered state landed half a button's width left of the
      // sheet's actual center.
      Positioned(
        top: _eventDetailTopPad,
        // Right stays reserved for the close button at every t; the left grows
        // in to match it, so collapsed reads symmetric (truly centered) while at
        // rest the title still starts flush left.
        left: 22 + 48 * t,
        right: 14 + 48,
        height: _eventDetailTitleRowHeight,
        child: Align(
          alignment: Alignment.lerp(Alignment.centerLeft, Alignment.center, t)!,
          child: Text(
            e.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: 'Poppins', fontSize: 24 - 7 * t, fontWeight: FontWeight.w600, letterSpacing: -0.5, color: AppColors.ink),
          ),
        ),
      ),
      // Painted last so the glass — a native platform view on iOS, which
      // composites above whatever Flutter draws after it — sits over the frost
      // and the title rather than forcing them into an overlay layer.
      Positioned(
        top: _eventDetailTopPad,
        right: 14,
        height: _eventDetailTitleRowHeight,
        child: Center(
          child: GlassIconButton(
            icon: LucideIcons.x,
            onTap: () {
              ref.read(calendarProvider.notifier).closeEvent();
              Navigator.of(context).pop();
            },
          ),
        ),
      ),
    ],
  );
}

/// Height of the event-detail sheet's action row. The trash [GlassIconButton]
/// is square, so this is also its width — it's sized from the "Bearbeiten"
/// pill beside it, whose height is its 14pt padding top and bottom around a
/// ~22pt line of Poppins 15.
const _detailActionHeight = 50.0;

// The event-detail header's geometry, shared by its builder (which positions
// every row against these) and the sliver that sizes it.
const _eventDetailTopPad = 2.0;
const _eventDetailTitleRowHeight = 44.0;
const _eventDetailChipsGap = 8.0;
// Only just clears the chips themselves (8 above + a 27pt chip): the leftover
// is dead space between the chips and the gray body, and showAppSheet already
// adds its own 14pt margin above that body.
const _eventDetailChipsRowHeight = _eventDetailChipsGap + 28.0;
// What survives at t == 1: the band of frost the sheet's gray body passes under,
// so the sharp gray starts clear of the title and close button.
const _eventDetailCollapsedGap = 8.0;
const _eventDetailCollapsedHeight = _eventDetailTopPad + _eventDetailTitleRowHeight + _eventDetailCollapsedGap;
const _eventDetailExpandedHeight = _eventDetailCollapsedHeight + _eventDetailChipsRowHeight;

void _showEventDetailSheet(BuildContext context, WidgetRef ref) {
  showAppSheet(
    context: context,
    heightFactor: 0.88,
    collapsingHeader: SheetCollapsingHeader(
      expandedHeight: _eventDetailExpandedHeight,
      collapsedHeight: _eventDetailCollapsedHeight,
      builder: (context, t) => Consumer(
        builder: (context, ref, _) => _buildEventDetailHeader(context, ref, t),
      ),
    ),
    child: Consumer(
      builder: (context, ref, _) {
        final state = ref.watch(calendarProvider);
        final e = state.openEvent;
        final accent = Theme.of(context).colorScheme.primary;
        if (e == null) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IntrinsicHeight(
              child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), boxShadow: AppShadows.card),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Icon(LucideIcons.calendar, size: 15, color: AppColors.muted),
                                        SizedBox(width: 9),
                                        Text('Termin', style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, fontWeight: FontWeight.w500, color: AppColors.muted, letterSpacing: 0.3)),
                                      ]),
                                      const SizedBox(height: 9),
                                      Text(state.openEventDateLine, style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink)),
                                      const SizedBox(height: 2),
                                      Text(e.timeRangeLabel, style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w300, color: AppColors.inkTertiary)),
                                    ],
                                  ),
                                ),
                              ),
                              // Same as the agenda row: no invented weather, so
                              // the card is absent until the Weather API lands
                              // and the row beside it takes the full width.
                              if (e.temp.isNotEmpty) ...[
                                const SizedBox(width: 10),
                                Container(
                                  width: 126,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), boxShadow: AppShadows.card),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Icon(_weatherIcon(e.cond), size: 28, color: accent),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const SizedBox(height: 8),
                                          Text(e.temp, style: TextStyle(fontFamily: 'Poppins', fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.5, color: AppColors.ink)),
                                          Text(e.condLabel, style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w300, color: AppColors.inkTertiary)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), boxShadow: AppShadows.card),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                                  child: Row(
                                    children: [
                                      Container(width: 38, height: 38, decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(13)), alignment: Alignment.center, child: Icon(LucideIcons.mapPin, size: 18, color: accent)),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(e.loc, style: TextStyle(fontFamily: 'Poppins', fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.ink)),
                                            if (e.locSub.isNotEmpty) Text(e.locSub, style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, fontWeight: FontWeight.w300, color: AppColors.muted)),
                                          ],
                                        ),
                                      ),
                                      Icon(LucideIcons.chevronRight, size: 17, color: AppColors.muted),
                                    ],
                                  ),
                                ),
                                if (!e.online)
                                  Container(
                                    height: 132,
                                    margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                                    decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(15)),
                                    child: Stack(
                                      children: [
                                        Align(
                                          alignment: Alignment.center,
                                          child: Container(
                                            width: 22,
                                            height: 22,
                                            decoration: BoxDecoration(color: accent, borderRadius: const BorderRadius.only(topLeft: Radius.circular(11), topRight: Radius.circular(11), bottomRight: Radius.circular(11))),
                                          ),
                                        ),
                                        Positioned(
                                          right: 10,
                                          bottom: 10,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.all(Radius.circular(13))),
                                            child: Text('Route', style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, fontWeight: FontWeight.w500, color: accent)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), boxShadow: AppShadows.card),
                            child: Row(
                              children: [
                                Container(width: 38, height: 38, decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(13)), alignment: Alignment.center, child: Icon(LucideIcons.bell, size: 18, color: accent)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Erinnerung', style: AppText.microLabel),
                                      Text(e.reminder, style: TextStyle(fontFamily: 'Poppins', fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.ink)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), boxShadow: AppShadows.card),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Notizen', style: AppText.microLabel),
                                const SizedBox(height: 6),
                                Text(e.body, style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w300, color: AppColors.inkSecondary, height: 1.55)),
                              ],
                            ),
                          ),
                          // Wider than the 12pt rhythm between the detail
                          // cards above: these are the sheet's actions, not
                          // another card, so they need to read as a separate
                          // group rather than crowding the notes card.
                          const SizedBox(height: 22),
                          // Hidden for anything proxied from a connected account
                          // or a public feed: Aporah keeps no copy of those, so
                          // there is nothing here to edit or delete. The source
                          // app — or the Stadtreinigung — owns them.
                          if (state.sourceById(e.calendarId)?.editable ?? false)
                            Row(
                              children: [
                                Expanded(
                                  child: GlassAccentButton(
                                    label: 'Bearbeiten',
                                    expand: true,
                                    onTap: () => _openEditEventSheet(context, ref, e),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                // Same size as the pill beside it is tall, so the
                                // pair reads as one row of controls in the same
                                // material rather than a button and a card.
                                GlassIconButton(
                                  icon: LucideIcons.trash,
                                  size: _detailActionHeight,
                                  iconSize: 18,
                                  iconColor: AppColors.danger,
                                  onTap: () => _confirmDeleteEvent(context, ref, e, closeParentSheet: true),
                                ),
                              ],
                            ),
          ],
        );
      },
    ),
  );
}

/// [closeParentSheet] should only be `true` when called from within the
/// event detail sheet itself (closing it after delete) — the swipe-action
/// entry point on the agenda card calls this directly from the screen, with
/// no parent sheet route to pop.
void _confirmDeleteEvent(BuildContext context, WidgetRef ref, CalendarEvent event, {bool closeParentSheet = false}) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Termin löschen?'),
      content: Text('„${event.title}" wird endgültig gelöscht.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Abbrechen'),
        ),
        TextButton(
          onPressed: () {
            ref.read(calendarProvider.notifier).deleteEvent(event);
            Navigator.of(dialogContext).pop();
            if (closeParentSheet) Navigator.of(context).pop();
          },
          child: Text('Löschen', style: TextStyle(color: AppColors.danger)),
        ),
      ],
    ),
  );
}
