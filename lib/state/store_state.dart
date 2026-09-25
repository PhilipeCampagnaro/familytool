import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/store_billing.dart';
import '../services/supabase.dart';
import 'entitlement_state.dart';
import 'family_state.dart';

/// What came of pressing "Plus holen" or "Kauf wiederherstellen" — one word
/// each, turned into a sentence by the screen that asked.
enum StoreAnswer {
  /// The household is on Plus now.
  plus,

  /// Ask to Buy or a bank's confirmation step; Plus arrives when it clears.
  pending,
  cancelled,
  failed,

  /// No store here, or the store had no products to offer.
  unavailable,

  /// The subscription is already carrying another household — the unique
  /// index on `plan_original_txn_id` said so. One payment, one family.
  ownedElsewhere,

  /// A restore that found nothing to restore.
  nothingFound,
}

/// Whether a purchase or restore is in flight, so the button can say so.
final storeBusyProvider = StateProvider<bool>((ref) => false);

/// **The only path from a store to `families.plan`, and it runs through the
/// server.** A purchase hands back Apple's signed transaction; this posts it to
/// `store-verify`, which checks the signature, writes the household row, and
/// answers — and only then is the transaction finished and the household
/// reloaded. The plan the app draws is read back off that row, exactly as the
/// other parent's phone reads it.
final storeProvider = Provider<StoreNotifier>((ref) {
  final notifier = StoreNotifier(ref);
  final billing = storeBilling;
  if (billing == null) return notifier;

  // Renewals, Ask to Buy approvals and refunds reported while the app is open.
  final sub = billing.updates.listen((t) => notifier._deliver([t]));
  ref.onDispose(sub.cancel);

  // **The retry.** Anything the store still holds unfinished — a purchase
  // whose post never arrived — is delivered as soon as there is a household
  // to deliver it to, which is also the first moment there is a session.
  ref.listen<String?>(
    familyProvider.select((s) => s.household?.id),
    (previous, next) {
      if (next != null && next != previous) unawaited(notifier._sweepUnfinished());
    },
    fireImmediately: true,
  );
  return notifier;
});

class StoreNotifier {
  final Ref _ref;

  StoreNotifier(this._ref);

  /// Puts up the store's own screen and delivers whatever was bought.
  Future<StoreAnswer> buyPlus() async {
    final billing = storeBilling;
    final household = _ref.read(familyProvider).household;
    if (billing == null || household == null) return StoreAnswer.unavailable;

    return _busy(() async {
      final outcome = await billing.showStore(householdId: household.id);
      switch (outcome.kind) {
        case StoreOutcomeKind.purchased:
          final transaction = outcome.transaction;
          if (transaction == null) return StoreAnswer.failed;
          return _deliver([transaction]);
        case StoreOutcomeKind.pending:
          return StoreAnswer.pending;
        case StoreOutcomeKind.failed:
          return StoreAnswer.failed;
        case StoreOutcomeKind.unavailable:
          return StoreAnswer.unavailable;
        case StoreOutcomeKind.cancelled:
          // The store screen has its own "Wiederherstellen", which reports
          // nothing back — so whatever the account holds now is delivered on
          // the way out. Asks the user nothing and costs nothing when empty.
          final held = await billing.current();
          if (held.isEmpty || _ref.read(entitlementProvider).isPlus) return StoreAnswer.cancelled;
          final answer = await _deliver(held);
          return answer == StoreAnswer.plus ? StoreAnswer.plus : StoreAnswer.cancelled;
      }
    });
  }

  /// "Kauf wiederherstellen": asks the store for this account's purchases and
  /// hands them to the server, which attaches them to this household unless
  /// another one already holds them.
  Future<StoreAnswer> restore() async {
    final billing = storeBilling;
    if (billing == null) return StoreAnswer.unavailable;

    return _busy(() async {
      final List<StoreTransaction>? held;
      try {
        held = await billing.restore();
      } catch (_) {
        return StoreAnswer.failed;
      }
      if (held == null) return StoreAnswer.cancelled;
      if (held.isEmpty) return StoreAnswer.nothingFound;
      final answer = await _deliver(held);
      // A subscription that has run out is found and verified, and changes
      // nothing — which, to the person who pressed the button, is "nothing
      // to restore".
      return answer == StoreAnswer.failed || answer == StoreAnswer.ownedElsewhere || answer == StoreAnswer.plus
          ? answer
          : StoreAnswer.nothingFound;
    });
  }

  /// The system's own screen for changing plan or cancelling.
  Future<bool> manage() async => await storeBilling?.manage() ?? false;

  Future<void> _sweepUnfinished() async {
    final billing = storeBilling;
    if (billing == null) return;
    final pending = await billing.unfinished();
    if (pending.isNotEmpty) await _deliver(pending);
  }

  Future<StoreAnswer> _deliver(List<StoreTransaction> transactions) async {
    final billing = storeBilling;
    if (billing == null || transactions.isEmpty) return StoreAnswer.unavailable;

    final Object? data;
    try {
      final res = await AporahSupabase.client.functions.invoke(
        'store-verify',
        body: {
          'source': billing.source,
          'transactions': [for (final t in transactions) t.signed],
        },
      );
      data = res.data;
    } on FunctionException catch (e) {
      final details = e.details;
      final code = details is Map ? details['code'] : null;
      if (code == 'owned_elsewhere') {
        // Finished anyway: the store would otherwise offer it again on every
        // start, and the answer will not change.
        for (final t in transactions) {
          await billing.finish(t);
        }
        return StoreAnswer.ownedElsewhere;
      }
      // Left unfinished on purpose, so the next start tries again.
      return StoreAnswer.failed;
    } catch (_) {
      return StoreAnswer.failed;
    }

    for (final t in transactions) {
      await billing.finish(t);
    }
    await _ref.read(familyProvider.notifier).load();
    final plan = data is Map ? data['plan'] : null;
    return plan == 'plus' ? StoreAnswer.plus : StoreAnswer.nothingFound;
  }

  Future<StoreAnswer> _busy(Future<StoreAnswer> Function() work) async {
    final busy = _ref.read(storeBusyProvider.notifier);
    if (busy.state) return StoreAnswer.cancelled;
    busy.state = true;
    try {
      return await work();
    } finally {
      busy.state = false;
    }
  }
}
