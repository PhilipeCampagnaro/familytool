import 'dart:async';

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
/// There are two senders and they are not redundant. **A device announces its
/// own writes**, which is what works today and is what makes a shared list feel
/// shared. **A trigger announces everything else** — `spend-ingest` filing an
/// Apple Pay transaction on a locked phone is a change no client made — and is
/// currently dropped by the platform for want of a partition on
/// `realtime.messages`; it will start arriving on its own. Both land in the same
/// callback and the receiver is idempotent, so the day the second one works, the
/// only cost of the overlap is one coalesced re-read.
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

  Stream<FamilyChange> get changes => _changes.stream;

  String get topic => 'family:$familyId';

  void connect() {
    if (_channel != null) return;
    final channel = _db.channel(
      topic,
      // `self: false` so a device does not hear its own broadcast back. The
      // `actor` check below is still needed and is not belt-and-braces: the
      // trigger's messages come from the database and carry no such courtesy.
      opts: const RealtimeChannelConfig(private: true, self: false),
    )..onBroadcast(event: _event, callback: _receive);
    channel.subscribe();
    _channel = channel;
  }

  void _receive(Map<String, dynamic> payload) {
    final table = payload['table'];
    if (table is! String || table.isEmpty) return;

    // Our own write, arriving back through the database's trigger. The change is
    // already on screen — often optimistically — and re-reading would fight the
    // update that put it there.
    if (payload['actor'] == userId) return;

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
void reloadOnFamilyChange(Ref ref, Set<String> tables, void Function() reload) {
  ref.listen(familyChangesProvider, (_, next) {
    final change = next.valueOrNull;
    if (change != null && tables.contains(change.table)) reload();
  });
}
