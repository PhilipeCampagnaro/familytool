import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/calendar_connection_repository.dart';
import '../models/calendar_connection.dart';
import 'auth_state.dart';
import 'calendar_state.dart';
import '../l10n/l10n.dart';

class CalendarConnectionsState {
  final List<CalendarConnection> connections;

  /// False until the first fetch lands. Without it the provider list would flash
  /// "Nicht verbunden" against every row on every open, including the ones that
  /// are in fact connected.
  final bool loaded;

  /// True while a refresh is in flight. One flag rather than a set of ids:
  /// `calendar-events` reads every account and feed in one call, so there is no
  /// longer such a thing as refreshing a single connection.
  final bool refreshing;

  final String? error;

  const CalendarConnectionsState({
    this.connections = const [],
    this.loaded = false,
    this.refreshing = false,
    this.error,
  });

  /// A household connects one Google account, not one per provider — but it may
  /// well connect two, so this returns all of them.
  List<CalendarConnection> of(CalendarProvider provider) =>
      [for (final c in connections) if (c.provider == provider) c];

  bool get anyNeedsAttention => connections.any((c) => c.needsAttention);

  CalendarConnectionsState copyWith({
    List<CalendarConnection>? connections,
    bool? loaded,
    bool? refreshing,
    String? error,
    bool clearError = false,
  }) => CalendarConnectionsState(
    connections: connections ?? this.connections,
    loaded: loaded ?? this.loaded,
    refreshing: refreshing ?? this.refreshing,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Owns the household's calendar connections.
///
/// Every mutating method re-reads the list afterwards rather than patching it
/// locally: `status`, `status_detail` and `last_synced_at` are written by the
/// sync function and cannot be predicted here. Guessing at them is exactly how
/// a UI ends up claiming a connection is healthy while the server has already
/// marked it expired.
class CalendarConnectionsNotifier extends StateNotifier<CalendarConnectionsState> {
  CalendarConnectionsNotifier(this._repo, {required bool signedIn})
    : super(const CalendarConnectionsState()) {
    if (signedIn) load();
  }

  final CalendarConnectionRepository _repo;

  Future<void> load() async {
    try {
      final connections = await _repo.fetchAll();
      if (!mounted) return;
      state = state.copyWith(connections: connections, loaded: true, clearError: true);
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(loaded: true, error: L.s.connectionsLoadFailed);
    }
  }

  /// The consent URL to open in the system browser. Returns null and records the
  /// reason when the provider has not been set up yet — the common case before
  /// the Google and Microsoft secrets are in place.
  Future<String?> oauthUrl(CalendarProvider provider) async {
    state = state.copyWith(clearError: true);
    try {
      return await _repo.oauthUrl(provider);
    } on CalendarConnectionException catch (e) {
      if (mounted) state = state.copyWith(error: e.message);
      return null;
    }
  }

  /// Throws [CalendarConnectionException] so the connect form can render the
  /// message beside its own fields — a wrong password belongs next to the
  /// password box, not in a banner at the top of the page.
  ///
  /// Returns the new connection's id so the screen can offer to name it, which
  /// is the same last step every other provider ends with.
  Future<({String? id, List<RemoteCalendar> calendars})> connectCaldav({
    required CalendarProvider provider,
    required String username,
    required String password,
    String? server,
  }) async {
    final result = await _repo.connectCaldav(
      provider: provider,
      username: username,
      password: password,
      server: server,
    );
    await _afterConnect(result.id);
    return result;
  }

  /// What an already-connected account offers, for the picker step of the setup
  /// flow. Never throws and never touches the state: a listing that fails means
  /// "no picker", not "the connect failed" — see the repository.
  Future<List<RemoteCalendar>> listCalendars(String connectionId) =>
      _repo.listCalendars(connectionId);

  /// [displayName] is the name the user typed in the confirm sheet. It is
  /// applied before the list is re-read, so the new row appears already
  /// carrying it rather than flashing the server's default first.
  Future<String?> connectFerien(String stateCode, {String? displayName}) async =>
      _afterConnect(await _repo.connectFerien(stateCode), displayName: displayName, isFeed: true);

  Future<String?> connectAbfall({
    required Map<String, dynamic> config,
    required String label,
    HouseNumber? houseNumber,
    String? displayName,
  }) async => _afterConnect(
    await _repo.connectAbfall(config: config, label: label, houseNumber: houseNumber),
    displayName: displayName,
    isFeed: true,
  );

  Future<String?> connectIcs({
    required String url,
    required String label,
    String? displayName,
  }) async => _afterConnect(
    await _repo.connectIcs(url: url, label: label),
    displayName: displayName,
    isFeed: true,
  );

  /// Connecting a calendar and then having to ask for its events separately is
  /// not two steps a user should know about — the first read runs here.
  ///
  /// The read is deliberately *not* awaited: `calendar-events` fans out across
  /// every account and feed the household has, which is seconds of work that
  /// says nothing about whether this connect worked. The connection is already
  /// on screen by then, and a provider that refuses to hand over events records
  /// that on its own row, which is what the "Erneut verbinden" state renders.
  Future<String?> _afterConnect(String? id, {String? displayName, bool isFeed = false}) async {
    if (id != null && displayName != null && displayName.trim().isNotEmpty) {
      // A rename that fails must not turn a successful connect into an error —
      // the calendar is connected either way, under the server's own name.
      try {
        await _repo.renameById(id: id, isFeed: isFeed, name: displayName);
      } catch (_) {}
    }
    await load();
    if (id != null) unawaited(refresh());
    return id;
  }

  /// Re-reads every account and feed, and reloads the calendar behind it.
  ///
  /// One call for all of them: `calendar-events` proxies the lot in a single
  /// request and stores none of it, so there is nothing to refresh
  /// connection-by-connection any more.
  Future<void> refresh() async {
    state = state.copyWith(refreshing: true, clearError: true);
    try {
      await _repo.refresh();
      await load();
      // The events just read are the calendar's, not this screen's — Kalender is
      // where they are actually shown.
      await _onCalendarChanged?.call();
    } on CalendarConnectionException catch (e) {
      if (mounted) state = state.copyWith(error: e.message);
    } finally {
      if (mounted) state = state.copyWith(refreshing: false);
    }
  }

  Future<void> disconnect(CalendarConnection connection) async {
    state = state.copyWith(clearError: true);
    try {
      await _repo.disconnect(connection);
    } on CalendarConnectionException catch (e) {
      if (mounted) state = state.copyWith(error: e.message);
    }
    await load();
    await _onCalendarChanged?.call();
  }

  Future<void> rename(CalendarConnection connection, String displayName) async {
    await _repo.rename(connection, displayName);
    await _settle();
  }

  /// Which of the account's sub-calendars sync, by the provider's own ids, and
  /// what the household calls each of them.
  ///
  /// Written before the connection's own rename in the setup flow, because it
  /// decides what the next `calendar-events` read will even fetch — and what it
  /// will call each calendar it creates. Null means "all of them" and is what a
  /// connection starts as; see the repository.
  Future<void> selectCalendars(
    String connectionId,
    List<String>? externalIds, {
    Map<String, String>? names,
  }) async {
    await _repo.setCalendarSelection(
      id: connectionId,
      externalIds: externalIds,
      names: names,
    );
    await _settle();
  }

  /// Renames one calendar inside an account — the row the household sees in
  /// "Verbunden", which is a calendar rather than the account it arrived on.
  Future<void> renameCalendar(CalendarConnection connection, String externalId, String name) async {
    await _repo.renameCalendar(
      connection: connection,
      externalId: externalId,
      name: name,
    );
    await _settle();
  }

  /// Stops reading one calendar of an account, leaving the account connected.
  ///
  /// Its name goes with it: a calendar that comes back later — reselected, or
  /// re-offered by the provider — should arrive under the provider's own name
  /// rather than one the household gave a different decision. `calendar-events`
  /// deletes the `calendars` row on the next read, which takes its events with
  /// it.
  Future<void> removeCalendar(CalendarConnection connection, String externalId) async {
    final remaining = [
      for (final id in connection.selectedCalendars ?? const <String>[])
        if (id != externalId) id,
    ];
    await _repo.setCalendarSelection(
      id: connection.id,
      externalIds: remaining,
      names: {...connection.calendarNames}..remove(externalId),
    );
    await _settle();
  }

  /// Re-read, and tell Kalender. Both are housekeeping *after* a write that has
  /// already landed, so neither may throw back at the caller: the confirm sheet
  /// turns anything thrown into "Das hat gerade nicht geklappt.", and reporting
  /// a failure for a change the server accepted is worse than a stale list —
  /// the user retries, and the retry looks broken too.
  ///
  /// `load()` and the calendar's own refresh already swallow their own errors;
  /// what this adds is cover for *reaching* them at all, which is what fails
  /// when this notifier has been disposed underneath an open sheet.
  Future<void> _settle() async {
    try {
      await load();
      await _onCalendarChanged?.call();
    } catch (_) {
      // Nothing to say: the write is done either way, and the next open reads
      // the list fresh.
    }
  }

  /// Called whenever what Kalender should show has changed. Set by the provider
  /// below; null in tests that construct the notifier directly.
  Future<void> Function()? _onCalendarChanged;
}

final calendarConnectionRepositoryProvider = Provider<CalendarConnectionRepository>(
  (ref) => CalendarConnectionRepository(),
);

/// Rebuilt when the signed-in user changes, so signing out cannot leave another
/// household's connections on screen.
final calendarConnectionsProvider =
    StateNotifierProvider<CalendarConnectionsNotifier, CalendarConnectionsState>((ref) {
      final userId = ref.watch(currentUserIdProvider);
      final notifier = CalendarConnectionsNotifier(
        ref.watch(calendarConnectionRepositoryProvider),
        signedIn: userId != null,
      );
      // Connecting, refreshing or removing a calendar changes what Kalender
      // shows. `ref.read` rather than `watch`: this screen reacts to the
      // calendar's data, it does not depend on it.
      notifier._onCalendarChanged = () => ref.read(calendarProvider.notifier).refresh();
      return notifier;
    });
