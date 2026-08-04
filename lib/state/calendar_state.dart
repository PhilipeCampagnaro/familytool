import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/calendar_data.dart';
import '../data/repositories/calendar_repository.dart';
import '../models/calendar_event.dart';
import 'auth_state.dart';
import 'family_state.dart';
import '../l10n/l10n.dart';

class CalSelectedDay {
  final int y;
  final int m;
  final int d;

  const CalSelectedDay(this.y, this.m, this.d);

  @override
  bool operator ==(Object other) => other is CalSelectedDay && other.y == y && other.m == m && other.d == d;

  @override
  int get hashCode => Object.hash(y, m, d);
}

class CalendarScreenState {
  final bool isWeek;
  final CalSelectedDay selected;
  final bool monthDetailExpanded;

  /// The calendar being filtered to, by id. Null is "Alle".
  final String? calendarFilter;

  /// The household's calendars, and its events keyed 'y-m-d'. These replace the
  /// old `added`/`edits`/`deletedKeys` overlay maps: with a real backend the
  /// server holds the truth, so there is nothing to overlay on top of — the
  /// same move `ListNotifier` made.
  final List<CalendarSource> calendars;
  final Map<String, List<CalendarEvent>> eventsByDay;

  final bool loaded;
  final String? error;

  /// True while what is on screen came off the device cache and the network has
  /// not answered yet. The calendar is fully usable in this state — it is the
  /// offline case, not a loading case.
  final bool fromCache;

  final CalendarEvent? openEvent;
  final String openEventDateLine;
  final DateTime now;

  CalendarScreenState({
    this.isWeek = true,
    CalSelectedDay? selected,
    this.monthDetailExpanded = false,
    this.calendarFilter,
    this.calendars = const [],
    this.eventsByDay = const {},
    this.loaded = false,
    this.error,
    this.fromCache = false,
    this.openEvent,
    this.openEventDateLine = '',
    DateTime? now,
  })  : now = now ?? DateTime.now(),
        selected = selected ?? _todaySelected();

  static CalSelectedDay _todaySelected() {
    final t = calToday();
    return CalSelectedDay(t.year, t.month, t.day);
  }

  CalendarScreenState copyWith({
    bool? isWeek,
    CalSelectedDay? selected,
    bool? monthDetailExpanded,
    String? calendarFilter,
    bool clearCalendarFilter = false,
    List<CalendarSource>? calendars,
    Map<String, List<CalendarEvent>>? eventsByDay,
    bool? loaded,
    String? error,
    bool clearError = false,
    bool? fromCache,
    CalendarEvent? openEvent,
    bool clearOpenEvent = false,
    String? openEventDateLine,
    DateTime? now,
  }) {
    return CalendarScreenState(
      isWeek: isWeek ?? this.isWeek,
      selected: selected ?? this.selected,
      monthDetailExpanded: monthDetailExpanded ?? this.monthDetailExpanded,
      calendarFilter: clearCalendarFilter ? null : (calendarFilter ?? this.calendarFilter),
      calendars: calendars ?? this.calendars,
      eventsByDay: eventsByDay ?? this.eventsByDay,
      loaded: loaded ?? this.loaded,
      error: clearError ? null : (error ?? this.error),
      fromCache: fromCache ?? this.fromCache,
      openEvent: clearOpenEvent ? null : (openEvent ?? this.openEvent),
      openEventDateLine: openEventDateLine ?? this.openEventDateLine,
      now: now ?? this.now,
    );
  }

  static String key(int y, int m, int d) => '$y-$m-$d';

  /// The calendars that actually hold an event in the loaded window — what the
  /// filter chip row renders.
  ///
  /// Derived rather than "every calendar": a Google account can contribute a
  /// dozen calendars, most of them empty, and a chip row of twelve names nobody
  /// has an event in is not a filter, it is noise.
  List<CalendarSource> get activeSources {
    final seen = <String>{};
    for (final day in eventsByDay.values) {
      for (final e in day) {
        seen.add(e.calendarId);
      }
    }
    return [for (final c in calendars) if (seen.contains(c.id)) c];
  }

  CalendarSource? sourceById(String? id) {
    if (id == null) return null;
    for (final c in calendars) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// The calendars an event can be written into — Aporah's own, plus every
  /// connected one the account has write access to. Ferien, Abfall and
  /// read-only subscriptions are not destinations.
  ///
  /// Aporah's own calendar is created on first use, so a household that has only
  /// ever connected Google has no row for it yet. Leaving it out of the picker
  /// would mean a family with no connections at all could not create an event —
  /// so it appears as a placeholder and is materialised on save.
  List<CalendarSource> get writableCalendars {
    final out = [for (final c in calendars) if (c.editable) c];
    if (!out.any((c) => c.isOwn)) out.insert(0, CalendarSource.ownPlaceholder);
    return out;
  }

  /// Where a new event goes unless the user says otherwise.
  ///
  /// Aporah's own calendar, deliberately. The alternative — defaulting to the
  /// first connected calendar — means an arbitrary one of a dozen Google
  /// calendars, and a family's first appointment quietly landing in somebody's
  /// work calendar is a worse surprise than having to pick.
  CalendarSource get defaultTarget {
    final writable = writableCalendars;
    for (final c in writable) {
      if (c.isOwn) return c;
    }
    return writable.first;
  }

  List<CalendarEvent> eventsFor(int y, int m, int d) {
    final all = eventsByDay[key(y, m, d)] ?? const <CalendarEvent>[];
    if (calendarFilter == null) return all;
    return [for (final e in all) if (e.calendarId == calendarFilter) e];
  }

  /// The dots under a day cell — **one per event**, in the order the day is
  /// listed in, each carrying its calendar's colour.
  ///
  /// It used to de-duplicate by calendar, so four appointments in one Google
  /// calendar drew a single dot and read as a quiet day. The dot row is how busy
  /// a day looks at a glance, and that is a question about events, not about how
  /// many calendars they happen to be spread across. The cells cap the row and
  /// turn the rest into a "+" badge, so a heavy day stays the same width.
  List<Color> dayColors(int y, int m, int d) => [
        for (final e in eventsFor(y, m, d)) e.srcColor,
      ];

  /// Day numbers in this month that fall inside a school holiday — the days the
  /// month grid tints, with the "Feiertag" legend above it.
  ///
  /// It reads the **Ferien feed and nothing else**. "All-day event on a
  /// read-only calendar", which this used to be, is also true of every waste
  /// pickup and of any subscribed calendar a Google account can only read, so a
  /// household with the bin calendar connected saw a third of the month tinted
  /// as holiday. The tint has one meaning; only the feed that carries that
  /// meaning may set it.
  Set<int> holidaysIn(int y, int m) {
    final out = <int>{};
    final days = DateTime(y, m + 1, 0).day;
    for (var d = 1; d <= days; d++) {
      for (final e in eventsFor(y, m, d)) {
        if (sourceById(e.calendarId)?.feedKind == 'ferien') {
          out.add(d);
          break;
        }
      }
    }
    return out;
  }
}

/// Owns the household's calendars and events.
///
/// Loads in two stages, which is what a proxied calendar requires: the device
/// cache paints immediately — offline, on a train, before the first request —
/// and the network answer replaces it when it lands. Aporah's server holds no
/// events from anybody's Google or iCloud account, so that cache is the only
/// thing standing between the user and a spinner on every cold start.
class CalendarNotifier extends StateNotifier<CalendarScreenState> {
  CalendarNotifier(this._repo, this._familyId, {required bool signedIn})
      : super(CalendarScreenState(now: DateTime.now())) {
    if (signedIn) load();
    // Ticks the real-time clock so the agenda's timeline phase (done/live/
    // upcoming) advances on its own instead of only updating on interaction.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      state = state.copyWith(now: DateTime.now());
    });
  }

  final CalendarRepository _repo;
  final String? _familyId;

  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Cache first, then network.
  ///
  /// The cached snapshot is shown even when it is weeks old: a calendar with
  /// last week's events in it is useful and honest, an empty one is neither. If
  /// the network then fails, whatever the cache gave stays on screen and only
  /// the banner changes.
  Future<void> load() async {
    final cached = await _repo.cached();
    if (!mounted) return;
    if (cached != null) _apply(cached);

    await refresh(silent: cached != null);
  }

  /// Re-reads everything, going out to every connected provider. This is what
  /// "Jetzt aktualisieren" runs, and what the app does when Kalender opens.
  ///
  /// [silent] keeps a failure quiet when there is already a cached calendar on
  /// screen — the user has their events, and a red banner over a working
  /// calendar would just be noise.
  Future<void> refresh({bool silent = false}) async {
    try {
      final snapshot = await _repo.fetch();
      if (!mounted) return;
      _apply(snapshot);
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(
        loaded: true,
        error: silent ? null : L.s.calendarLoadFailed,
      );
    }
  }

  void _apply(CalendarSnapshot snapshot) {
    state = state.copyWith(
      calendars: snapshot.calendars,
      eventsByDay: snapshot.eventsByDay,
      loaded: true,
      fromCache: snapshot.fromCache,
      clearError: true,
    );
  }

  /// Jumps the selection to the real current day — what the "Heute" button
  /// does. Kept here rather than resolved at each call site so every caller
  /// agrees on which day "today" is.
  void selectDayToday() {
    final t = calToday();
    selectDay(t.year, t.month, t.day);
  }

  void setWeekView() => state = state.copyWith(isWeek: true);
  void setMonthView() => state = state.copyWith(isWeek: false);

  void selectDay(int y, int m, int d) {
    final same = state.selected.y == y && state.selected.m == m && state.selected.d == d;
    state = state.copyWith(
      selected: CalSelectedDay(y, m, d),
      monthDetailExpanded: same ? !state.monthDetailExpanded : true,
    );
  }

  void setCalendarFilter(String calendarId) {
    final same = state.calendarFilter == calendarId;
    state = state.copyWith(calendarFilter: same ? null : calendarId, clearCalendarFilter: same);
  }

  /// "Alle" — clears any active calendar filter so every source shows again.
  void clearCalendarFilter() => state = state.copyWith(clearCalendarFilter: true);

  void openEvent(CalendarEvent e, String dateLine) =>
      state = state.copyWith(openEvent: e, openEventDateLine: dateLine);

  void closeEvent() => state = state.copyWith(clearOpenEvent: true);

  void clearError() => state = state.copyWith(clearError: true);

  /// A blank event on the selected day, ready for the form.
  ///
  /// Starts at the next full hour when the selected day is today, so the common
  /// case ("something later on") needs no scrolling, and at 10:00 on any other
  /// day. Hour 24 rolls into the next morning on its own, which is the right
  /// answer for an event added at half past eleven at night.
  EventDraft newDraft() {
    final sel = state.selected;
    final today = calToday();
    final isToday = sel.y == today.year && sel.m == today.month && sel.d == today.day;
    final start = isToday
        ? DateTime(sel.y, sel.m, sel.d, DateTime.now().hour + 1)
        : DateTime(sel.y, sel.m, sel.d, 10);

    return EventDraft(
      calendarId: state.defaultTarget.id,
      title: '',
      location: '',
      notes: '',
      allDay: false,
      start: start,
      end: start.add(const Duration(hours: 1)),
    );
  }

  /// Whether an event may be changed at all — false for Ferien, Abfall and any
  /// calendar the connected account only has read access to.
  bool canEdit(CalendarEvent event) => state.sourceById(event.calendarId)?.editable ?? false;

  /// True when this destination is Aporah's own calendar, which is written as an
  /// ordinary row rather than sent out to a provider.
  bool _isOwn(String calendarId) =>
      calendarId == CalendarSource.ownPlaceholderId ||
      (state.sourceById(calendarId)?.isOwn ?? false);

  /// Creates the event. Returns false and records a German message on failure,
  /// so the sheet can stay open with what the user typed still in it.
  Future<bool> createEvent(EventDraft draft) async {
    final clean = draft.copyWith(title: draft.title.trim());
    if (clean.title.isEmpty) return _failed(L.s.eventNeedsTitle);

    try {
      await _write(clean);
      await refresh();
      return true;
    } catch (e) {
      return _failed(_message(e, L.s.eventSaveFailed));
    }
  }

  /// Saves an edited event, including a move to a different calendar.
  ///
  /// A move is a create followed by a delete, in that order on purpose: if the
  /// create fails nothing has been lost, whereas deleting first and then failing
  /// to create would lose the appointment outright. The remaining failure mode
  /// leaves a duplicate, which the user can see and remove.
  Future<bool> saveEvent(CalendarEvent event, EventDraft draft) async {
    final clean = draft.copyWith(title: draft.title.trim());
    if (clean.title.isEmpty) return _failed(L.s.eventNeedsTitle);
    if (!canEdit(event)) return _failed(L.s.calendarNotEditable);

    try {
      if (clean.calendarId == event.calendarId) {
        if (_isOwn(event.calendarId)) {
          // Built from the event rather than the draft, so the id, the calendar
          // and the fields the form does not show survive the edit untouched.
          await _repo.updateEvent(event.copyWith(
            title: clean.title,
            startsAt: clean.start,
            endsAt: clean.end,
            allDay: clean.allDay,
            loc: clean.location,
            body: clean.notes,
          ));
        } else {
          await _repo.writeExternal(
            action: 'update',
            calendarId: event.calendarId,
            uid: event.uid,
            draft: clean,
          );
        }
      } else {
        await _write(clean);
        await _remove(event);
      }

      state = state.copyWith(clearOpenEvent: true);
      await refresh();
      return true;
    } catch (e) {
      return _failed(_message(e, L.s.changeSaveFailed));
    }
  }

  Future<bool> deleteEvent(CalendarEvent event) async {
    if (!canEdit(event)) return _failed(L.s.calendarNotEditable);
    state = state.copyWith(clearOpenEvent: true);

    try {
      await _remove(event);
      await refresh();
      return true;
    } catch (e) {
      return _failed(_message(e, L.s.eventDeleteFailed));
    }
  }

  /// Writes a deleted appointment back where it came from — the chip's
  /// "Rückgängig".
  ///
  /// The cheapest restore of the four: [_write] already routes by calendar, so
  /// an own event becomes a `public.events` row again and a Google or CalDAV one
  /// goes back out through `calendar-write`, exactly as it was created. What it
  /// cannot bring back is the provider's own id — the appointment returns as a
  /// new one — which matters only to a guest who had been invited to it in
  /// Google.
  Future<bool> restoreEvent(CalendarEvent event) async {
    try {
      await _write(EventDraft.of(event));
      await refresh();
      return true;
    } catch (e) {
      return _failed(_message(e, L.s.eventRestoreFailed));
    }
  }

  /// The one place that decides where an event is written: an ordinary row on
  /// Aporah's own calendar, or straight back out to the provider that owns it.
  Future<void> _write(EventDraft draft) async {
    final target = state.sourceById(draft.calendarId);

    // No row behind it: the placeholder, standing in for an own calendar that
    // does not exist yet. Materialised here rather than at signup, so a family
    // that only ever uses Google never accumulates an empty "Aporah".
    //
    // Every member has their own, which is why this cannot simply take the
    // first `isOwn` calendar it finds — that could be somebody else's.
    if (target == null) {
      if (draft.calendarId != CalendarSource.ownPlaceholderId) {
        throw CalendarWriteException(L.s.calendarNoLongerAvailable);
      }
      final familyId = _familyId;
      if (familyId == null) {
        throw CalendarWriteException(L.s.noHouseholdFound);
      }
      final calendar = await _repo.ownCalendar(familyId);
      await _repo.createEvent(draft.toEvent(calendar: calendar));
      return;
    }

    if (target.isOwn) {
      await _repo.createEvent(draft.toEvent(calendar: target));
    } else {
      await _repo.writeExternal(action: 'create', calendarId: target.id, draft: draft);
    }
  }

  Future<void> _remove(CalendarEvent event) async {
    if (_isOwn(event.calendarId)) {
      await _repo.deleteEvent(event.id);
    } else {
      await _repo.writeExternal(
        action: 'delete',
        calendarId: event.calendarId,
        uid: event.uid,
      );
    }
  }

  /// Keeps the provider's own German explanation when there is one — an expired
  /// connection and an unreachable server need different things from the user.
  String _message(Object error, String fallback) =>
      error is CalendarWriteException ? error.message : fallback;

  bool _failed(String message) {
    if (mounted) state = state.copyWith(error: message);
    return false;
  }
}

final calendarRepositoryProvider = Provider<CalendarRepository>((ref) => CalendarRepository());

/// `select` rather than a bare `watch(familyProvider)`, matching listProvider,
/// boxProvider and boardProvider. Without it, saving a profile — anything that
/// touches FamilyState at all — disposes this notifier and rebuilds it, which
/// here means cancelling the clock ticker and re-running load(): a cache read
/// followed by a `calendar-events` call that fans out to Google, Outlook and
/// every CalDAV server the household has connected. It is the most expensive
/// rebuild in the app, triggered by the least related action.
final calendarProvider = StateNotifierProvider<CalendarNotifier, CalendarScreenState>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  return CalendarNotifier(
    ref.watch(calendarRepositoryProvider),
    ref.watch(familyProvider.select((s) => s.household?.id)),
    signedIn: userId != null,
  );
});
