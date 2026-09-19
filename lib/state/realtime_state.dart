import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase.dart';
import 'auth_state.dart';
import 'family_state.dart';

/// One change somewhere in the household, as it reaches the other devices.
///
/// A class rather than a bare `String` for a reason that only shows up in
/// Riverpod: a provider drops a notification whose new state equals the old one,
/// so two consecutive `'lists'` strings would deliver the first change and
/// silently swallow the second. This has no `==`, so identity keeps every one of
/// them distinct.
class FamilyChange {
  FamilyChange(this.table);

  /// Not a table: "you may have missed something, re-read everything".
  ///
  /// Broadcasts are not replayed. iOS closes the socket the moment the app is
  /// backgrounded and supabase_flutter disconnects on pause, so a list created
  /// while the other phone was in a pocket was announced to nobody — and
  /// without this that phone showed the old list until it was killed and
  /// relaunched. Sent on every resume and on every rejoin after the first.
  static const catchUp = '*';

  bool get isCatchUp => table == catchUp;

  /// The table that changed — `lists`, `list_items`, `tasks`, and so on.
  ///
  /// **Never a row.** See the migration: the message carries the table's name
  /// and nothing else, and the receiver re-reads through the same repository it
  /// always uses, which goes through RLS. A payload with the row in it would be
  /// a second read path with its own access rules to get wrong.
  final String table;
}

/// The household's live channel — one topic, `family:<uuid>`, private.
///
/// **Broadcast rather than Postgres Changes.** `postgres_changes` re-evaluates
/// every subscriber's RLS against every changed row, so one tick on a shopping
/// list costs a policy evaluation per connected device. Broadcast authorizes
/// once, when a device joins, and relays a message the database never has to
/// store.
///
/// There are two senders. **A trigger announces every row** — lists, boxes,
/// tasks, spends and the household roster alike, including a change no client
/// made, like `spend-ingest` filing an Apple Pay transaction on a locked phone.
/// **A device announces its calendar writes** ([announce]), because we store no
/// events and so there is no row for a trigger to fire on.
///
/// **Broadcasts are not replayed**, which is the other half of being live: a
/// phone that was backgrounded, offline or mid-reconnect when a message went out
/// never gets it. Every rejoin after the first, and every resume
/// ([catchUp]), therefore re-reads everything once.
class FamilyChannel {
  FamilyChannel(this._db, {required this.familyId, required this.userId});

  final SupabaseClient _db;
  final String familyId;
  final String userId;

  static const _event = 'change';

  /// How long a burst of changes is gathered before anyone re-reads.
  ///
  /// Someone typing a shopping list produces a write per keystroke-pause, and
  /// deleting a list with fifty articles fires the row trigger fifty times. One
  /// re-read at the end of that is the whole point; fifty would turn a live
  /// calendar into a stuttering one and put the load back on the database we
  /// avoided by not using Postgres Changes.
  static const _coalesce = Duration(milliseconds: 400);

  RealtimeChannel? _channel;
  final _changes = StreamController<FamilyChange>.broadcast();
  final Map<String, Timer> _pending = {};
  bool _joinedBefore = false;
  bool _disposed = false;
  Timer? _reopen;

  Stream<FamilyChange> get changes => _changes.stream;

  String get topic => 'family:$familyId';

  void connect() {
    if (_channel != null || _disposed) return;
    final channel = _db.channel(
      topic,
      // `self: false` so a device does not hear its own broadcast back. The
      // `actor` check below is still needed and is not belt-and-braces: the
      // trigger's messages come from the database and carry no such courtesy.
      opts: const RealtimeChannelConfig(private: true, self: false),
    )..onBroadcast(event: _event, callback: _receive);
    channel.subscribe((status, error) => _onStatus(channel, status, error));
    _channel = channel;
  }

  /// The join's verdict, which the first version never asked for — a channel
  /// that failed to authorize looked exactly like a quiet household.
  ///
  /// The reply hooks survive a rejoin, so this runs again every time the socket
  /// comes back: after a resume, after a dead Wi-Fi, after a token refresh.
  void _onStatus(RealtimeChannel channel, RealtimeSubscribeStatus status, Object? error) {
    if (_disposed || !identical(channel, _channel)) return;
    switch (status) {
      case RealtimeSubscribeStatus.subscribed:
        // Every join after the first is a return from somewhere the messages
        // could not reach, so whatever was sent meanwhile is gone.
        if (_joinedBefore) catchUp();
        _joinedBefore = true;
      case RealtimeSubscribeStatus.channelError:
      case RealtimeSubscribeStatus.timedOut:
        // The client schedules its own rejoin for both; the log is so a
        // refused join is not silent again.
        debugPrint('FamilyChannel $topic: $status ${error ?? ''}');
      case RealtimeSubscribeStatus.closed:
        // Closed by the server, not by us (dispose clears `_channel` first).
        // A closed channel never rejoins on its own, so open a fresh one.
        debugPrint('FamilyChannel $topic: closed, reopening');
        _channel = null;
        unawaited(_db.removeChannel(channel));
        _reopen?.cancel();
        _reopen = Timer(const Duration(seconds: 2), connect);
    }
  }

  /// Asks every screen to re-read. Coalesced with anything already pending, so
  /// a resume and the rejoin it causes cost one read, not two.
  void catchUp() => _queue(FamilyChange.catchUp);

  void _receive(Map<String, dynamic> message) {
    // **The callback is handed the whole envelope** — `{type, event, payload}` —
    // not the payload inside it, whatever the parameter's name in
    // `onBroadcast` suggests. Reading `table` off the top level found nothing,
    // and for the channel's first week every message that reached a phone was
    // dropped here without a trace. The fallback is for a client version that
    // one day unwraps it.
    final inner = message['payload'];
    final payload = inner is Map ? Map<String, dynamic>.from(inner) : message;
    final table = payload['table'];
    if (table is! String || table.isEmpty) return;

    // Our own write, arriving back through the database's trigger. The change is
    // already on screen — often optimistically — and re-reading would fight the
    // update that put it there.
    if (payload['actor'] == userId) return;

    _queue(table);
  }

  void _queue(String table) {
    if (_disposed) return;
    // A catch-up re-reads everything, so a table already waiting inside one
    // would only read twice.
    if (table != FamilyChange.catchUp && _pending.containsKey(FamilyChange.catchUp)) return;
    if (table == FamilyChange.catchUp) {
      for (final t in _pending.values) {
        t.cancel();
      }
      _pending.clear();
    }
    _pending[table]?.cancel();
    _pending[table] = Timer(_coalesce, () {
      _pending.remove(table);
      if (!_changes.isClosed) _changes.add(FamilyChange(table));
    });
  }

  /// Tells the household's other devices that [table] changed.
  ///
  /// Fire-and-forget on purpose. The write it accompanies has already succeeded;
  /// a failed courtesy must not surface as an error on an action that worked, and
  /// the other devices catch up on their next resume regardless.
  void announce(String table) {
    final channel = _channel;
    if (channel == null) return;
    unawaited(
      channel
          .sendBroadcastMessage(event: _event, payload: {'table': table, 'actor': userId})
          .catchError((_) => ChannelResponse.error),
    );
  }

  Future<void> dispose() async {
    _disposed = true;
    _reopen?.cancel();
    for (final timer in _pending.values) {
      timer.cancel();
    }
    _pending.clear();
    await _changes.close();
    final channel = _channel;
    _channel = null;
    if (channel != null) await _db.removeChannel(channel);
  }
}

/// The channel for the household currently signed in, or null when there is
/// none to join yet.
///
/// Rebuilt when the household changes, which tears the old channel down — a
/// device that left a family must stop hearing about its shopping lists.
final familyChannelProvider = Provider<FamilyChannel?>((ref) {
  final familyId = ref.watch(familyProvider.select((s) => s.household?.id));
  final userId = ref.watch(currentUserIdProvider);
  if (familyId == null || userId == null) return null;

  final channel = FamilyChannel(AporahSupabase.client, familyId: familyId, userId: userId)..connect();
  ref.onDispose(() => unawaited(channel.dispose()));
  return channel;
});

/// Every change reaching this device from somebody else's.
final familyChangesProvider = StreamProvider<FamilyChange>((ref) {
  final channel = ref.watch(familyChannelProvider);
  return channel?.changes ?? const Stream<FamilyChange>.empty();
});

/// Wires a screen's notifier to the tables it draws.
///
/// Every screen does exactly this, so it is written once: listen, and when one
/// of [tables] changes somewhere else in the household, re-read. The re-read is
/// the notifier's ordinary `load()`, which goes through RLS like every other
/// read in the app — the broadcast decides *when* to look, never *what* is
/// visible.
///
/// A catch-up (resume, reconnect) reloads too, unless [catchUp] is false —
/// which is for the calendar alone: its read fans out to every connected
/// provider, and it has its own throttled refresh on resume.
void reloadOnFamilyChange(Ref ref, Set<String> tables, void Function() reload, {bool catchUp = true}) {
  ref.listen(familyChangesProvider, (_, next) {
    final change = next.valueOrNull;
    if (change == null) return;
    if (tables.contains(change.table) || (catchUp && change.isCatchUp)) reload();
  });
}

/// The tables behind the household itself — who is in it, their names and
/// faces, its name and address, the pending invitations.
const householdTables = {'family_members', 'families', 'profiles', 'family_invites'};
