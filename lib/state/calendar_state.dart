import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/calendar_data.dart';
import '../data/repositories/calendar_repository.dart';
import '../data/repositories/list_repository.dart' show newUuidV4;
import '../models/calendar_event.dart';
import 'auth_state.dart';
import 'family_state.dart';
import 'realtime_state.dart';
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
  final CalSelectedDay selected;
  final bool monthDetailExpanded;

  /// The calendars being filtered to, by id. Null — not the empty set — is
  /// "Alle". The empty set is its own thing and does occur: unticking the last
  /// row in a picker leaves nothing showing on purpose, because unticking a box
  /// must never tick the others back on. The way out is the "Alle" chip.
  ///
  /// A set rather than one id because a chip is now an *account*: one connected
  /// Google or IServ account contributes several calendars, and "Alice · IServ"
  /// means all three of hers. Refining that down to one of the three is what
  /// the chip's own popup does, and it stays inside the set.
  final Set<String>? calendarFilter;

  /// The household's calendars, and its events keyed 'y-m-d'. These replace the
  /// old `added`/`edits`/`deletedKeys` overlay maps: with a real backend the
  /// server holds the truth, so there is nothing to overlay on top of — the
  /// same move `ListNotifier` made.
  /// Which chip in the filter row is lit, or null for "Alle".
  ///
  /// Tracked rather than derived from [calendarFilter], because the id set does
  /// not say which chip put it there. A selection narrowed inside a chip's own
  /// popup is a *subset* of that chip's calendars and must keep it lit (as a
  /// partial), and a hand-picked set spanning two accounts belongs to no chip at
  /// all — that is what [kPickedCalendarFilterId] is for.
  final String? filterGroupId;

  /// Whether the Board's to-dos are laid over the calendar.
  ///
  /// **Additive, unlike every other chip in that row.** The rest of the row
  /// narrows: picking a person hides the other people. This one adds a second
  /// kind of thing on top of whatever is already showing, which is why its chip
  /// stands apart from the faces and why it is not part of [calendarFilter].
  ///
  /// **And it is deliberately not narrowed by that filter.** A calendar group
  /// is a person's *calendars*; a to-do's [BoardTask.assigneeId] is who is meant
  /// to do it. They are near enough to look like the same question and far
  /// enough apart to answer it differently, so filtering to Papa and losing the
  /// to-do he is not assigned to would be the row quietly changing what it
  /// means. Every to-do the reader may see is either shown or not.
  ///
  /// Session state, like [calendarFilter] — nothing on this screen
  /// is persisted, and one flag that survived a restart while the filter beside
  /// it did not would read as a bug.
  final bool showTasks;

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
    CalSelectedDay? selected,
    this.monthDetailExpanded = false,
    this.calendarFilter,
    this.filterGroupId,
    this.showTasks = false,
    this.calendars = const [],
    this.eventsByDay = const {},
    this.loaded = false,
    this.error,
    this.fromCache = false,
    this.openEvent,
    this.openEventDateLine = '',
    DateTime? now,
  }) : now = now ?? DateTime.now(),
       selected = selected ?? _todaySelected();

  static CalSelectedDay _todaySelected() {
    final t = calToday();
    return CalSelectedDay(t.year, t.month, t.day);
  }

  CalendarScreenState copyWith({
    CalSelectedDay? selected,
    bool? monthDetailExpanded,
    Set<String>? calendarFilter,
    bool clearCalendarFilter = false,
    String? filterGroupId,
    bool? showTasks,
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
      selected: selected ?? this.selected,
      monthDetailExpanded: monthDetailExpanded ?? this.monthDetailExpanded,
      calendarFilter: clearCalendarFilter ? null : (calendarFilter ?? this.calendarFilter),
      filterGroupId: clearCalendarFilter ? null : (filterGroupId ?? this.filterGroupId),
      showTasks: showTasks ?? this.showTasks,
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
    return [
      for (final c in calendars)
        if (seen.contains(c.id)) c,
    ];
  }

  CalendarSource? sourceById(String? id) {
    if (id == null) return null;
    for (final c in calendars) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// The calendars an event can be written into — every connected calendar the
  /// household has write access to. Ferien, Abfall and read-only subscriptions
  /// are not destinations.
  ///
  /// **Only calendars that exist, and none of them ours.** There used to be an
  /// "Aporah" entry here — first a synthetic one, then a real `provider:
  /// 'aporah'` row — and it is gone both times over. The app has no calendar of
  /// its own, so a household with nothing connected is told to connect one
  /// rather than offered a destination that lives nowhere but here.
  List<CalendarSource> get writableCalendars => [
    for (final c in calendars)
      if (c.editable) c,
  ];

  /// Where a new event goes unless the user says otherwise, and null when the
  /// household has nowhere to put one yet.
  ///
  /// The first writable calendar, which is an arbitrary one of however many the
  /// connected accounts contribute — so the form shows the whole list with this
  /// one ticked rather than filing anything silently. A first appointment landing
  /// unseen in somebody's work calendar is the surprise worth avoiding here.
  CalendarSource? get defaultTarget => writableCalendars.isEmpty ? null : writableCalendars.first;

  List<CalendarEvent> eventsFor(int y, int m, int d) {
    final all = eventsByDay[key(y, m, d)] ?? const <CalendarEvent>[];
    final filter = calendarFilter;
    if (filter == null) return all;
    return [
      for (final e in all)
        if (filter.contains(e.calendarId)) e,
    ];
  }

  /// The loaded event a list or a task points back at, or null.
  ///
  /// **Unfiltered on purpose.** A task hung off Ferdi's football training must
  /// find it even while the chip row is narrowed to Mama, because the tap that
  /// got here was on the task and had nothing to do with the filter. Nothing is
  /// widened afterwards either: `showLinkedEventSheet` stacks the sheet over
  /// Board or Listen and leaves Kalender's own view exactly as its owner left
  /// it.
  ///
  /// [day] is the snapshot the link carries and is only a hint: it is checked
  /// first because it is nearly always right, and the whole loaded window after
  /// it because an appointment that has since been moved is exactly the case
  /// where the snapshot is not. Null means "outside the fortnight we hold",
  /// which is the ordinary answer for anything more than a few weeks out.
  CalendarEvent? eventForLink({required String calendarId, required String uid, DateTime? day}) {
    if (uid.isEmpty) return null;

    bool matches(CalendarEvent e) => e.uid == uid && e.calendarId == calendarId;

    if (day != null) {
      for (final e in eventsByDay[key(day.year, day.month, day.day)] ?? const <CalendarEvent>[]) {
        if (matches(e)) return e;
      }
    }
    for (final events in eventsByDay.values) {
      for (final e in events) {
        if (matches(e)) return e;
      }
    }
    return null;
  }

  /// A value that changes whenever the filter does, for the widget keys that
  /// rebuild on it. A `Set` is identity-compared inside a [ValueKey], so the
  /// key would never notice a filter change; the ids are sorted so that two
  /// equal filters built in a different order still compare equal.
  /// Every calendar id the chip row can actually reach — the union of
  /// [activeGroups].
  ///
  /// The cross-account picker starts from this rather than from [calendars]:
  /// a calendar with nothing in the loaded window has no row to tick, so
  /// leaving it out of a hand-picked filter would hide it with no way back.
  Set<String> get pickableCalendarIds => {for (final g in activeGroups) ...g.ids};

  String get calendarFilterKey {
    final filter = calendarFilter;
    if (filter == null) return '';
    return (filter.toList()..sort()).join(',');
  }

  /// The chip row: one entry per connected account, plus one for every calendar
  /// that belongs to no account.
  ///
  /// This is the whole reason `group_id` travels on the wire. A child's IServ
  /// account holds an Aufgaben, a Klausurplan and a Klassenkalender, and three
  /// chips reading "Alice IServ Aufgaben", "Alice IServ Klausurplan", "Alice
  /// IServ Klassenkalender" push everything else off the row while saying the
  /// same two words three times. One "Alice · IServ" chip that opens into the
  /// three says it once. A Google account with a work and a private calendar
  /// gets the same treatment for the same reason.
  ///
  /// A group appears once **anything** in it has an event in the loaded window,
  /// and then lists **all** of that account's calendars — not only the ones
  /// with something in view. Building the list itself from the events instead
  /// was wrong twice over: a Klausurplan with two dates and an Aufgaben with
  /// none collapsed to a group of one, so the chip read "Klausurplan" rather
  /// than the account, and the empty calendar could not be reached to be
  /// unticked. An account's calendars are a property of the account, not of
  /// what happens to fall in the fortnight on screen — a Klausurplan is empty
  /// all summer and is still Alice's.
  List<CalendarGroup> get activeGroups {
    final seen = <String>{};
    for (final day in eventsByDay.values) {
      for (final e in day) {
        seen.add(e.calendarId);
      }
    }

    final out = <CalendarGroup>[];
    final byId = <String, int>{};

    for (final src in calendars) {
      // A feed has no account: it stands alone under its own name, exactly as
      // it did before there were groups.
      if (src.groupId.isEmpty) {
        out.add(CalendarGroup(id: src.id, name: src.name, calendars: [src]));
        continue;
      }
      final at = byId[src.groupId];
      if (at == null) {
        byId[src.groupId] = out.length;
        out.add(
          CalendarGroup(
            id: src.groupId,
            name: src.groupName.isEmpty ? src.name : src.groupName,
            calendars: [src],
          ),
        );
      } else {
        out[at] = out[at].withCalendar(src);
      }
    }

    return [
      for (final g in out)
        if (g.calendars.any((c) => seen.contains(c.id)))
          // A connection offering exactly one calendar is not a group: it says
          // the account's name where the calendar's own is more useful, and it
          // would offer a popup with a single row in it.
          //
          // **A person is a group however few calendars they have.** The row is
          // faces, and a chip reading "iCloud" under somebody's photograph is
          // the account leaking back into a row that stopped being about
          // accounts — worse, it is exactly what a household sees right after
          // assigning their one calendar to themselves, so the assignment reads
          // as having done nothing.
          g.calendars.length == 1 && !g.isPerson ? g.asSingle() : g,
    ];
  }

  /// The dots under a day cell — **one per event**, in the order the day is
  /// listed in, each carrying its calendar's colour.
  ///
  /// It used to de-duplicate by calendar, so four appointments in one Google
  /// calendar drew a single dot and read as a quiet day. The dot row is how busy
  /// a day looks at a glance, and that is a question about events, not about how
  /// many calendars they happen to be spread across. The cells cap the row and
  /// turn the rest into a "+" badge, so a heavy day stays the same width.
  List<Color> dayColors(int y, int m, int d) => [for (final e in eventsFor(y, m, d)) e.srcColor];

  /// Whether the household subscribed to a Schulferien feed at all — which is
  /// what decides whether the month grid's legend mentions Ferien. Nobody needs
  /// a key to a wash that never appears.
  bool get hasFerienFeed => calendars.any((c) => c.feedKind == 'ferien');

  /// Whether this day falls inside a school holiday.
  ///
  /// It reads the **Ferien feed and nothing else**. "All-day event on a
  /// read-only calendar", which this used to be, is also true of every waste
  /// pickup and of any subscribed calendar a Google account can only read, so a
  /// household with the bin calendar connected saw a third of the month washed
  /// as holiday. The wash has one meaning; only the feed that carries that
  /// meaning may set it.
  ///
  /// Via [eventsFor], so it follows the calendar filter: narrowing the grid to
  /// one calendar drops everything the other ones were saying, including this.
  ///
  /// The *striped* days are a different question and are not derived from here
  /// at all — those are the Feiertage, computed from the household's Bundesland
  /// by `lib/data/german_holidays.dart` behind `germanHolidaysProvider`.
  bool isSchoolHoliday(int y, int m, int d) {
    for (final e in eventsFor(y, m, d)) {
      if (sourceById(e.calendarId)?.feedKind == 'ferien') return true;
    }
    return false;
  }

  /// Day numbers in this month that fall inside a school holiday — one pass for
  /// a whole month block, rather than [isSchoolHoliday] per cell.
  Set<int> schoolHolidaysIn(int y, int m) {
    final out = <int>{};
    final days = DateTime(y, m + 1, 0).day;
    for (var d = 1; d <= days; d++) {
      if (isSchoolHoliday(y, m, d)) out.add(d);
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
/// The [CalendarScreenState.filterGroupId] a hand-picked selection wears.
///
/// Not a real group id, and deliberately not one: it belongs to the "Alle"
/// chip, which is the one chip in the row standing for no account — and so the
/// only place a filter spanning two people can be built.
const kPickedCalendarFilterId = '__picked__';

class CalendarNotifier extends StateNotifier<CalendarScreenState> {
  CalendarNotifier(this._repo, {required bool signedIn, FamilyChannel? channel})
    // `channel` is the public name and `_channel` the private field. Dart
    // forbids an underscore in a named parameter, so an initializing formal
    // is not available here.
    // ignore: prefer_initializing_formals
    : _channel = channel,
      super(CalendarScreenState(now: DateTime.now())) {
    if (signedIn) load();
    // Ticks the real-time clock so the agenda's timeline phase (done/live/
    // upcoming) advances on its own instead of only updating on interaction.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      state = state.copyWith(now: DateTime.now());
      // And, far more rarely, a re-read. This is the only thing that catches an
      // appointment somebody added **in Google itself** while the app sat open:
      // no trigger fires for that and no device broadcasts it, so the one way to
      // learn about it is to ask. Riding the clock ticker rather than a second
      // timer is also what makes it foreground-only for free — iOS suspends
      // timers along with the app, so a phone in a pocket polls nothing.
      unawaited(refreshIfStale(after: _foregroundStaleAfter));
    });
  }

  final CalendarRepository _repo;

  /// The household's live channel, for telling the other devices that an
  /// appointment moved.
  ///
  /// **The calendar is the one thing a database trigger cannot announce**, which
  /// is exactly the point of storing no events: there is no row anywhere in our
  /// database to fire on. The device that made the change is the only thing that
  /// knows it happened, so it says so — and everybody else re-reads through
  /// `calendar-events` like they always do. Null before the household is known.
  final FamilyChannel? _channel;

  /// The name this screen's changes travel under. Not a table, deliberately: it
  /// sits in the same namespace as `lists` and `tasks` because it does the same
  /// job for the same receivers, and there is no table it could be named after.
  static const kCalendarTopic = 'calendar';

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
  /// The read that is currently out, if there is one. See [refresh].
  Future<CalendarSnapshot>? _inFlight;

  Future<void> refresh({bool silent = false}) async {
    try {
      // Two callers asking at once get one read, not two. This is the cheapest
      // possible guard and the only one that cannot be wrong: it never delays a
      // refresh and never suppresses one, it only declines to start a second
      // fan-out while the first is still in the air.
      //
      // Worth having because a `calendar-events` call is the most expensive
      // thing the app can do — it goes out to Google, Outlook and every CalDAV
      // server the household has connected, on a 90-second budget — so the
      // usual cost of an accidental double call is not a wasted request but a
      // doubled load on somebody's school server and on our own provider
      // quota, which is shared across every user of the app. Kalender opening
      // while the connections screen finishes a connect is the ordinary way to
      // get two, and a provider rebuild loop is the alarming way.
      final snapshot = await (_inFlight ??= _repo.fetch());
      if (!mounted) return;
      _apply(snapshot);
    } catch (_) {
      if (!mounted) return;
      // Nothing is cleared here on purpose: whatever the cache put on screen
      // stays there, and only the banner changes. That is the whole reason
      // CalendarRepository._external throws rather than returning empty lists.
      state = state.copyWith(loaded: true, error: silent ? null : L.s.calendarLoadFailed);
    } finally {
      _inFlight = null;
    }
  }

  /// How long a calendar read stays good enough that coming back to the app
  /// doesn't trigger another one.
  ///
  /// Short enough that a phone picked up after lunch shows this afternoon, long
  /// enough that flicking to Mail to check a confirmation and straight back
  /// doesn't cost every connected provider another fan-out. The cost of getting
  /// this wrong is asymmetric — too long is a stale calendar the user can see,
  /// too short is load on somebody's school server that nobody can see — so it
  /// errs short and the throttle exists to stop the pathological case, not to
  /// ration ordinary use.
  static const _resumeStaleAfter = Duration(minutes: 2);

  /// How long the app may sit open before it asks the providers again.
  ///
  /// Much longer than the resume window, and the asymmetry is deliberate: coming
  /// back to the app is a moment the user is about to *look*, whereas this fires
  /// whether anyone is looking or not. Every household doing this hits the same
  /// providers, and the quota it spends is shared across every user of the app —
  /// so four fan-outs an hour per open app is the ceiling, not a target.
  static const _foregroundStaleAfter = Duration(minutes: 15);

  /// When the last **network** read landed. Null until one has, and deliberately
  /// not set by a cache read: a month-old snapshot restored at launch is on
  /// screen, but it is not a reason to skip the refresh behind it.
  DateTime? _lastFetched;

  /// Re-read only if the calendar on screen has had time to go wrong.
  ///
  /// This is what returning to the app runs. It is separate from [refresh]
  /// because "the user asked" and "the user came back" are different questions:
  /// **"Jetzt aktualisieren" must always go out**, however recently we looked,
  /// or the one control whose entire job is to fetch would sometimes do nothing.
  Future<void> refreshIfStale({Duration? after}) async {
    final last = _lastFetched;
    if (last != null && DateTime.now().difference(last) < (after ?? _resumeStaleAfter)) {
      return;
    }
    // Silent whenever there is already a calendar on screen. A resume is not an
    // action the user took on the calendar, so a red banner over a working one
    // would be the app reporting a failure nobody asked it to risk.
    await refresh(silent: state.loaded);
  }

  // ---------------------------------------------------------------------------
  // Optimistic writes
  //
  // **We store no events, so a write cannot appear until a provider hands it
  // back** — and that is two round trips away: `calendar-write` puts the
  // appointment in Google, Outlook or the school's CalDAV server, and then
  // `calendar-events` asks every connected calendar again. Waiting for both left
  // the user staring at the day they had just filled, still empty. On the one
  // screen this product is sold on.
  //
  // So the appointment goes on screen first and the round trips happen behind
  // it. The overlay below is what makes that safe: rather than patching the
  // fetched day map in place — where the next refresh, a resume or somebody
  // else's, would silently wipe the change back off — provisional events are
  // held *beside* the snapshot and merged on the way into state. A refresh can
  // then land at any moment without the write flickering away.
  // ---------------------------------------------------------------------------

  /// The last read, unmerged. Kept so the overlay can be re-composed against it
  /// when a write starts or settles without going back to the network.
  CalendarSnapshot? _snapshot;

  /// Appointments written here that no provider has handed back yet.
  final List<CalendarEvent> _pendingAdds = [];

  /// Event ids removed or replaced here, suppressed until a read agrees they
  /// are gone. An edit is both: the original hidden, the new one added.
  final Set<String> _pendingHides = {};

  /// Overlay entries waiting for a read to agree with them.
  ///
  /// Not dropped as soon as the write succeeds, which would blink the
  /// appointment out for the length of the read that follows, and not dropped
  /// after it either, which would show the provisional and the real one side by
  /// side for a frame. Retiring them *with* the snapshot is the only timing that
  /// is never wrong on screen.
  ///
  /// **And only against a snapshot that actually contains the change** — see
  /// [_retire]. Retiring on the first read back was right for Google and Graph,
  /// which are read-your-writes for the same credential, and wrong for CalDAV:
  /// iCloud accepts the PUT and then serves a REPORT without the new event in it
  /// for a few seconds more. The appointment blinked off the day it had just
  /// been added to and did not come back until the next read — fifteen minutes
  /// later, or the next launch, which is what "I have to restart the app" was.
  final Set<String> _retiring = {};

  /// The provider's own id for each provisional event, once the write answered
  /// with one. This is what a later read is checked against; an entry is dropped
  /// with the overlay it belongs to.
  final Map<String, String> _writtenUids = {};

  void _apply(CalendarSnapshot snapshot) {
    if (!snapshot.fromCache) _lastFetched = DateTime.now();
    if (_retiring.isNotEmpty) _retire(snapshot);
    _snapshot = snapshot;
    _compose(clearError: true);
  }

  /// Drops the overlay entries this snapshot has caught up with, and **keeps the
  /// ones it has not**.
  ///
  /// Settled means different things for the two halves, and they are settled
  /// independently on purpose. An add is settled when the appointment itself
  /// comes back; a hide when the row it suppresses is really gone. A move
  /// between calendars is both at once and the two providers answer at their own
  /// speed — retiring them as a pair would mean either showing the appointment
  /// twice or not at all for as long as the slower one took.
  void _retire(CalendarSnapshot snapshot) {
    final live = <String, CalendarEvent>{};
    for (final day in snapshot.eventsByDay.values) {
      for (final event in day) {
        live[event.id] = event;
      }
    }

    _pendingAdds.removeWhere((provisional) {
      if (!_retiring.contains(provisional.id)) return false;
      final landed = _landed(provisional, live.values);
      if (landed == null) return false;
      _retiring.remove(provisional.id);
      _writtenUids.remove(provisional.id);
      // An edit that left the appointment's own id alone — a changed title,
      // say — is hiding the very row that is now the answer. That hide goes
      // with the overlay it belonged to: left standing, it would take the
      // appointment off the day at the moment the provisional came down.
      _pendingHides.remove(landed.id);
      _retiring.remove(landed.id);
      return true;
    });

    _pendingHides.removeWhere((id) {
      if (!_retiring.contains(id)) return false;
      final gone = !live.containsKey(id);
      if (gone) _retiring.remove(id);
      return gone;
    });
  }

  /// The real appointment a provisional one turned into, or null while no read
  /// has brought it back yet.
  ///
  /// Matched on the provider's id **and the title**: an update keeps the id, so
  /// the id alone would settle an edit against the version it was meant to
  /// replace. A write that reported no id of its own cannot be looked for at
  /// all and settles on the first read the way every write used to — the
  /// fallback, not the path, since all three providers do report one.
  CalendarEvent? _landed(CalendarEvent provisional, Iterable<CalendarEvent> live) {
    final uid = _writtenUids[provisional.id] ?? '';
    if (uid.isEmpty) return provisional;
    for (final event in live) {
      if (event.uid == uid && event.title == provisional.title) return event;
    }
    return null;
  }

  /// Remembers what the provider called the appointment it just accepted.
  void _noteUid(String provisionalId, String uid) {
    if (uid.isNotEmpty) _writtenUids[provisionalId] = uid;
  }

  /// Puts the snapshot plus whatever is in flight into state.
  ///
  /// [clearError] only on a fresh read. An overlay change is not an answer to
  /// the question a banner is asking, and a failed write sets its own message
  /// straight after rolling back.
  void _compose({bool clearError = false}) {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    state = state.copyWith(
      calendars: snapshot.calendars,
      eventsByDay: _withPending(snapshot.eventsByDay),
      loaded: true,
      fromCache: snapshot.fromCache,
      clearError: clearError,
    );
  }

  Map<String, List<CalendarEvent>> _withPending(Map<String, List<CalendarEvent>> fetched) {
    // The overwhelmingly common case: nothing in flight, so the read's own map
    // goes through untouched and costs nothing to overlay.
    if (_pendingAdds.isEmpty && _pendingHides.isEmpty) return fetched;

    final out = <String, List<CalendarEvent>>{};
    fetched.forEach((day, events) {
      final kept = [
        for (final e in events)
          if (!_pendingHides.contains(e.id)) e,
      ];
      if (kept.isNotEmpty) out[day] = kept;
    });

    final touched = <String>{};
    for (final event in _pendingAdds) {
      for (final day in event.days) {
        final k = CalendarScreenState.key(day.year, day.month, day.day);
        (out[k] ??= []).add(event);
        touched.add(k);
      }
    }
    for (final k in touched) {
      out[k]!.sort(CalendarEvent.compareForDay);
    }
    return out;
  }

  /// The appointment as it will look once the provider has it, drawn from the
  /// draft and the calendar it is going into.
  ///
  /// The id is ours and local — a provider's own uid does not exist until it
  /// answers — which is exactly why the overlay is keyed on it: nothing a read
  /// returns can ever collide with one.
  CalendarEvent _provisional(EventDraft draft, CalendarSource target) => CalendarEvent(
    id: 'pending:${newUuidV4()}',
    calendarId: target.id,
    title: draft.title,
    startsAt: draft.start,
    endsAt: draft.end,
    allDay: draft.allDay,
    body: draft.notes,
    loc: draft.location,
    source: target.name,
    srcColor: target.color,
  );

  void _addPending(CalendarEvent event) {
    _pendingAdds.add(event);
    _compose();
  }

  /// Hides [event], and its whole series when that is what is being removed —
  /// otherwise "Ganze Serie" would take one Monday off the grid and leave the
  /// rest of the term sitting there until the read came back.
  Set<String> _hidePending(CalendarEvent event, EventScope scope) {
    final ids = <String>{event.id};
    if (scope == EventScope.series && event.seriesUid.isNotEmpty) {
      for (final day in state.eventsByDay.values) {
        for (final e in day) {
          if (e.seriesUid == event.seriesUid) ids.add(e.id);
        }
      }
    }
    _pendingHides.addAll(ids);
    _compose();
    return ids;
  }

  void _rollBack({Iterable<String> adds = const [], Iterable<String> hides = const []}) {
    _pendingAdds.removeWhere((e) => adds.contains(e.id));
    _pendingHides.removeAll(hides);
    for (final id in adds) {
      _writtenUids.remove(id);
    }
    _compose();
  }

  /// Re-reads in the background and retires [ids] when the answer lands.
  ///
  /// Deliberately not awaited by the write that starts it. The write is the part
  /// that can fail in a way the user must know about; the read behind it is
  /// housekeeping, and making the sheet wait for it is the whole problem this
  /// section exists to remove.
  ///
  /// A provider that has not caught up with its own write yet will return
  /// without the appointment, and retiring the overlay against that answer
  /// blinks it off until the next read. Google and Graph are read-your-writes
  /// for the same credential so this is a CalDAV-only risk, and the honest
  /// alternative — holding a provisional event on screen that the server may
  /// have rejected — is worse.
  /// Settle our own view, and tell the rest of the household to re-read.
  ///
  /// Every successful write ends here, which is why the announcement sits here
  /// rather than at four call sites that would drift apart.
  void _reconcile(Iterable<String> ids) {
    _channel?.announce(kCalendarTopic);
    unawaited(_readAfterWrite(ids.toList()));
  }

  /// Somebody else in the household changed an appointment.
  ///
  /// Always goes out, unlike a resume: this is not a guess that the calendar
  /// might have moved on, it is a device saying that it has. Silent because the
  /// user did nothing to provoke it and a banner over a working calendar would
  /// be the app reporting a failure nobody asked it to risk.
  Future<void> refreshFromElsewhere() => refresh(silent: true);

  Future<void> _readAfterWrite(List<String> ids) async {
    // **Never retire against a read that was already in the air.** [refresh]
    // deliberately joins a fetch in flight rather than starting a second one,
    // which is right for two screens asking at once and wrong here: that fetch
    // left before this write did, so it cannot contain it, and retiring the
    // overlay against its answer would blink the appointment straight back off.
    // A resume landing while the event sheet saves is the ordinary way to get
    // one.
    final inFlight = _inFlight;
    if (inFlight != null) {
      try {
        await inFlight;
      } catch (_) {
        // Its failure is its own caller's to report; this read carries on.
      }
      if (!mounted) return;
    }

    _retiring.addAll(ids);
    await refresh(silent: true);

    // **A CalDAV server is allowed to be slower than one read.** iCloud takes
    // the PUT and then serves a REPORT without the event in it for a few
    // seconds; the overlay now survives that ([_retire]), and these are what
    // bring the real appointment back in seconds rather than at the next
    // fifteen-minute refresh. Two extra reads at most, and none at all once
    // everything has settled — which is every Google and Graph write, and most
    // CalDAV ones.
    for (final wait in _settleReads) {
      if (!mounted || !ids.any(_retiring.contains)) return;
      await Future<void>.delayed(wait);
      if (!mounted) return;
      await refresh(silent: true);
    }
    // Still not back. The overlay stays up rather than being forced down — the
    // write was accepted, so the appointment exists, and showing it is the
    // honest answer until an ordinary refresh finds it.
  }

  /// How long to keep asking after a write before leaving the rest to an
  /// ordinary refresh.
  ///
  /// Spaced rather than repeated: a `calendar-events` call fans out to every
  /// connected provider, so this is the smallest number of reads that covers a
  /// server taking a moment, not a poll.
  static const _settleReads = [Duration(seconds: 6), Duration(seconds: 18)];

  /// Jumps the selection to the real current day — what the "Heute" button
  /// does. Kept here rather than resolved at each call site so every caller
  /// agrees on which day "today" is.
  void selectDayToday() {
    final t = calToday();
    selectDay(t.year, t.month, t.day);
  }

  /// The to-do chip. Additive, so it neither reads nor clears
  /// [CalendarScreenState.calendarFilter] — see [CalendarScreenState.showTasks].
  void toggleTasks() => state = state.copyWith(showTasks: !state.showTasks);

  void selectDay(int y, int m, int d) {
    final same = state.selected.y == y && state.selected.m == m && state.selected.d == d;
    state = state.copyWith(
      selected: CalSelectedDay(y, m, d),
      monthDetailExpanded: same ? !state.monthDetailExpanded : true,
    );
  }

  /// Close the month view's inline day card without moving the selection —
  /// what its X does. Tapping the day again is still the other way out, but a
  /// card several event rows tall pushes its own day number off screen, so
  /// "tap the day again" stops being a visible option exactly when the card is
  /// biggest.
  void collapseMonthDetail() {
    if (state.monthDetailExpanded) state = state.copyWith(monthDetailExpanded: false);
  }

  /// Tapping a chip: show **exactly this chip's calendars** and nothing else.
  ///
  /// It used to union a person's chip with the household's shared calendars, on
  /// the reasoning that a family dinner really is on Alice's Thursday. It came
  /// out because it made the row untrustworthy: tapping "Alice" showed
  /// calendars that were visibly not hers, with no way to see where they had
  /// come from — her own popup lists only her calendars, so the extras could
  /// neither be found nor unticked there. A filter that shows more than it was
  /// asked for reads as broken however good the reason.
  ///
  /// Worse, "family" is also where an **unassigned** calendar lands
  /// (`groupFor` in `calendar-events`), so the union quietly pulled in every
  /// calendar nobody had got round to assigning yet.
  ///
  /// Both calendars at once is still expressible, and in the one place that
  /// means it: the "Alle" chip's picker, which is allowed to span accounts —
  /// see [toggleCalendarAnywhere].
  void filterToGroup(CalendarGroup group) {
    state = state.copyWith(calendarFilter: {...group.ids}, filterGroupId: group.id);
  }

  void setCalendarFilter(Set<String> calendarIds) {
    final current = state.calendarFilter;
    final same = current != null && current.length == calendarIds.length && current.containsAll(calendarIds);
    state = state.copyWith(
      calendarFilter: same ? null : calendarIds,
      clearCalendarFilter: same || calendarIds.isEmpty,
    );
  }

  /// Ticking one calendar inside a chip's popup.
  ///
  /// The popup refines *within* its own account, which is what the chip it
  /// hangs off already means — so a filter pointing somewhere else is replaced
  /// by this account's calendars rather than added to. Starting from the whole
  /// group is what makes the first tap read as "everything here except that
  /// one", which is the thing people actually want from a Klausurplan they are
  /// not revising for.
  ///
  /// Unticking the last one goes back to "Alle": an empty filter is a blank
  /// calendar with no visible way out of it.
  void toggleCalendarInGroup(CalendarGroup group, String calendarId) {
    final current = state.calendarFilter;
    final Set<String> base;
    if (current == null) {
      // Nothing is filtered, so every one of this account's calendars is
      // showing: start from all of them.
      base = {...group.ids};
    } else {
      final within = current.intersection(group.ids);
      // A filter pointing at *another* account is replaced by this one, since
      // the popup refines within the chip it hangs off. An **empty** filter is
      // not that: it is this account already emptied, and it has to stay empty
      // so the next tick adds one calendar back rather than reading as "all of
      // them except that one".
      base = within.isEmpty && current.isNotEmpty ? {...group.ids} : {...within};
    }

    if (!base.remove(calendarId)) base.add(calendarId);

    // Set the filter directly rather than through [setCalendarFilter], whose
    // empty case means "the chip was tapped off, show everything again".
    // Emptying the last row here means the opposite — "none of Alice's, thanks"
    // — and unticking a box must never tick the others back on. The way out is
    // the "Alle" chip, which is always the first thing in the row, or ticking a
    // row again; the chip row itself is built from unfiltered events, so it
    // stays on screen with nothing selected.
    state = state.copyWith(calendarFilter: base, filterGroupId: group.id);
  }

  /// Ticking a calendar in the "Alle" chip's picker — the one filter that is
  /// allowed to span two accounts.
  ///
  /// An account's own popup refines *within* that account, because that is what
  /// the chip it hangs off means. This one hangs off "Alle", which means nobody
  /// in particular, so it adds to and removes from whatever is showing instead
  /// of replacing it: Alice's Klausurplan plus the family calendar plus Papa's
  /// work calendar is one selection here, and there is nowhere else in the app
  /// it can be expressed.
  void toggleCalendarAnywhere(String calendarId) {
    final all = state.pickableCalendarIds;
    final current = state.calendarFilter;
    // No filter means every calendar is showing, so the first tick reads as
    // "everything except that one" — the same starting point a chip's own
    // popup takes, for the same reason.
    final next = {...(current ?? all)};
    if (!next.remove(calendarId)) next.add(calendarId);

    // Everything ticked is "Alle" again, not a hand-picked set that happens to
    // hold every calendar today: the chip should go back to saying "Alle", and
    // an account connected tomorrow should join it rather than arrive hidden.
    if (next.length == all.length && next.containsAll(all)) {
      state = state.copyWith(clearCalendarFilter: true);
      return;
    }

    // An emptied selection stays empty, exactly as it does inside an account's
    // popup: unticking the last row must not tick every other one back on. The
    // way out is the "Alle" row at the top of the same panel.
    state = state.copyWith(calendarFilter: next, filterGroupId: kPickedCalendarFilterId);
  }

  /// The "Alle" row inside a multi-select menu: a checkbox over all of them.
  ///
  /// Lit (nothing filtered) it unticks every calendar at once; unlit it ticks
  /// them all back. Emptied is a hand-picked set of none rather than "Alle",
  /// exactly as unticking the last row one by one leaves it — so the next tick
  /// adds one calendar back instead of reading as "all except that one".
  void toggleAllCalendars() {
    if (state.calendarFilter == null) {
      state = state.copyWith(calendarFilter: <String>{}, filterGroupId: kPickedCalendarFilterId);
    } else {
      clearCalendarFilter();
    }
  }

  /// "Alle" — clears any active calendar filter so every source shows again.
  ///
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
      calendarId: state.defaultTarget?.id ?? '',
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

  /// Creates the event. Returns false and records a German message on failure,
  /// so the sheet can stay open with what the user typed still in it.
  ///
  /// **The appointment is on the calendar before this is called back.** It goes
  /// up as a provisional event the moment the draft is known to be writable, and
  /// the answer here is only about whether `calendar-write` accepted it — the
  /// re-read that follows is housekeeping and nothing waits for it. See the
  /// optimistic-writes section above.
  ///
  /// It is **one** calendar being written, the one the sheet picked; the fan-out
  /// to the providers happens inside the Edge Function.
  Future<bool> createEvent(EventDraft draft) async {
    final clean = draft.copyWith(title: draft.title.trim());
    if (clean.title.isEmpty) return _failed(L.s.eventNeedsTitle);

    // Resolved before anything is drawn: a provisional event needs the
    // calendar's name and colour, and this is the same check `_write` would
    // have failed on anyway.
    final target = state.sourceById(clean.calendarId);
    if (target == null) {
      return _failed(clean.calendarId.isEmpty ? L.s.noWritableCalendar : L.s.calendarNoLongerAvailable);
    }

    final provisional = _provisional(clean, target);
    _addPending(provisional);

    try {
      _noteUid(
        provisional.id,
        await _repo.writeExternal(action: 'create', calendarId: target.id, draft: clean),
      );
    } catch (e) {
      _rollBack(adds: [provisional.id]);
      return _failed(_message(e, L.s.eventSaveFailed));
    }

    _reconcile([provisional.id]);
    return true;
  }

  /// Saves an edited event, including a move to a different calendar.
  ///
  /// A move is a create followed by a delete, in that order on purpose: if the
  /// create fails nothing has been lost, whereas deleting first and then failing
  /// to create would lose the appointment outright. The remaining failure mode
  /// leaves a duplicate, which the user can see and remove.
  /// [scope] only means anything on a repeating appointment, and the sheet only
  /// asks for it there.
  ///
  /// **A whole series cannot move to another calendar, and says so.** A move is
  /// a create on the far side followed by a delete on this one, and the create
  /// would have no rule to carry: the app is shown expanded occurrences and
  /// never the RRULE behind them, so "ganze Serie" plus a new calendar can only
  /// produce one appointment over there and an entire term deleted over here.
  /// Refusing is the honest answer; moving a single occurrence still works.
  Future<bool> saveEvent(
    CalendarEvent event,
    EventDraft draft, {
    EventScope scope = EventScope.single,
  }) async {
    final clean = draft.copyWith(title: draft.title.trim());
    if (clean.title.isEmpty) return _failed(L.s.eventNeedsTitle);
    if (!canEdit(event)) return _failed(L.s.calendarNotEditable);
    if (scope == EventScope.series && clean.calendarId != event.calendarId) {
      return _failed(L.s.seriesCannotMoveCalendar);
    }

    state = state.copyWith(clearOpenEvent: true);

    // A whole series is the one edit that is not drawn ahead of the answer.
    // The app is handed expanded occurrences and never the rule behind them, so
    // there is no way to work out on the client which other days a changed
    // series lands on — and an overlay that moved this Monday while leaving the
    // rest of the term where it was would be a worse lie than a short wait.
    if (scope == EventScope.series) {
      try {
        await _repo.writeExternal(
          action: 'update',
          calendarId: event.calendarId,
          uid: event.uid,
          draft: clean,
          scope: scope,
          seriesUid: event.seriesUid,
          occurrence: event,
        );
        _channel?.announce(kCalendarTopic);
        await refresh();
        return true;
      } catch (e) {
        return _failed(_message(e, L.s.changeSaveFailed));
      }
    }

    final target = state.sourceById(clean.calendarId);
    if (target == null) return _failed(L.s.calendarNoLongerAvailable);

    // Both routes are the same change on screen — this appointment gone, that
    // one in its place — however differently the providers have to be told.
    final provisional = _provisional(clean, target);
    final hidden = _hidePending(event, EventScope.single);
    _addPending(provisional);

    try {
      if (clean.calendarId == event.calendarId) {
        _noteUid(
          provisional.id,
          await _repo.writeExternal(
            action: 'update',
            calendarId: event.calendarId,
            uid: event.uid,
            draft: clean,
            scope: scope,
            seriesUid: event.seriesUid,
            occurrence: event,
          ),
        );
      } else {
        // Create first, delete second, on purpose: a failed create has lost
        // nothing, where deleting first and then failing would lose the
        // appointment outright. Only a single occurrence gets this far, so the
        // delete takes an EXDATE or one instance and leaves the series alone.
        _noteUid(provisional.id, await _write(clean));
        await _remove(event);
      }
    } catch (e) {
      _rollBack(adds: [provisional.id], hides: hidden);
      return _failed(_message(e, L.s.changeSaveFailed));
    }

    _reconcile([provisional.id, ...hidden]);
    return true;
  }

  Future<bool> deleteEvent(CalendarEvent event, {EventScope scope = EventScope.single}) async {
    if (!canEdit(event)) return _failed(L.s.calendarNotEditable);
    state = state.copyWith(clearOpenEvent: true);

    final hidden = _hidePending(event, scope);

    try {
      await _remove(event, scope: scope);
    } catch (e) {
      _rollBack(hides: hidden);
      return _failed(_message(e, L.s.eventDeleteFailed));
    }

    _reconcile(hidden);
    return true;
  }

  /// Writes a deleted appointment back where it came from — the chip's
  /// "Rückgängig".
  ///
  /// The cheapest restore of the four: [_write] sends it back out through
  /// `calendar-write` exactly as it was created. What it cannot bring back is the
  /// provider's own id — the appointment returns as a new one — which matters
  /// only to a guest who had been invited to it in Google.
  Future<bool> restoreEvent(CalendarEvent event) async {
    final draft = EventDraft.of(event);
    final target = state.sourceById(draft.calendarId);
    if (target == null) return _failed(L.s.calendarNoLongerAvailable);

    // Back on the grid before the write goes out, like any other create. Undo is
    // the one action where a wait is least forgivable: the user is already
    // looking at the gap they want filled.
    final provisional = _provisional(draft, target);
    _addPending(provisional);

    try {
      _noteUid(
        provisional.id,
        await _repo.writeExternal(action: 'create', calendarId: target.id, draft: draft),
      );
    } catch (e) {
      _rollBack(adds: [provisional.id]);
      return _failed(_message(e, L.s.eventRestoreFailed));
    }

    _reconcile([provisional.id]);
    return true;
  }

  /// The one place an event is written, and there is only one route out: back to
  /// the connected account that owns the calendar it was filed under. Answers
  /// with the provider's own id for it, which is what [_landed] looks for.
  Future<String> _write(EventDraft draft) async {
    final target = state.sourceById(draft.calendarId);

    // Nothing behind the id. Either the household has no writable calendar at
    // all (the form says so and does not let it get this far), or the one that
    // was picked has since been disconnected under the open sheet.
    if (target == null) {
      throw CalendarWriteException(
        draft.calendarId.isEmpty ? L.s.noWritableCalendar : L.s.calendarNoLongerAvailable,
      );
    }

    return _repo.writeExternal(action: 'create', calendarId: target.id, draft: draft);
  }

  Future<void> _remove(CalendarEvent event, {EventScope scope = EventScope.single}) async {
    await _repo.writeExternal(
      action: 'delete',
      calendarId: event.calendarId,
      uid: event.uid,
      scope: scope,
      seriesUid: event.seriesUid,
      occurrence: event,
    );
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
/// Calendar id -> the person chip it belongs under, so a screen can group by
/// the same faces Kalender does without knowing how a calendar is owned.
final calendarOwnerProvider = Provider<Map<String, String>>((ref) {
  final calendars = ref.watch(calendarProvider.select((s) => s.calendars));
  return {
    for (final c in calendars)
      if (c.groupId.isNotEmpty) c.id: c.groupId,
  };
});

final calendarProvider = StateNotifierProvider<CalendarNotifier, CalendarScreenState>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  // Watched but not passed on: nothing in the notifier needs the household's id
  // any more — no calendar is created from the client — but a household change
  // still has to rebuild it, or the calendar of the family just left stays on
  // screen.
  ref.watch(familyProvider.select((s) => s.household?.id));
  final notifier = CalendarNotifier(
    ref.watch(calendarRepositoryProvider),
    signedIn: userId != null,
    channel: ref.watch(familyChannelProvider),
  );
  reloadOnFamilyChange(ref, const {CalendarNotifier.kCalendarTopic}, notifier.refreshFromElsewhere);
  return notifier;
});
