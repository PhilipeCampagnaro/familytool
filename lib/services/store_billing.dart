import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';

/// **The store behind "Plus holen", as one interface** — so
/// `entitlementProvider` never learns which store it is on, and Play Billing
/// can arrive as a second implementation without a screen changing.
///
/// **Nothing here grants Plus.** A store answers with a signed transaction;
/// `StoreNotifier` posts it to `store-verify`, which checks the signature and
/// writes `families.plan`, and the app reads the plan back off the household
/// row like everybody else in the family does. A client that lies from here
/// gets a household that is still on free.
abstract class StoreBilling {
  /// The name `store-verify` routes on — `families.plan_source`'s own value.
  String get source;

  /// Puts up the store's own screen for Plus, monthly and yearly side by side,
  /// and answers once it closes. [householdId] rides the purchase as Apple's
  /// `appAccountToken`, so a renewal reported months later can find the
  /// household even if this device never reached the server.
  Future<StoreOutcome> showStore({required String householdId});

  /// Transactions the store has not been told are delivered yet — a purchase
  /// whose post to the server failed, an Ask to Buy approved overnight. Read on
  /// every start: this is the retry.
  Future<List<StoreTransaction>> unfinished();

  /// What this store account is subscribed to right now, without asking the
  /// user anything. Read after the store screen closes, because its own
  /// "Wiederherstellen" button reports nothing back.
  Future<List<StoreTransaction>> current();

  /// Asks the store for this account's purchases — may put up a sign-in
  /// prompt, so only ever from a button. Null when the user cancelled it.
  Future<List<StoreTransaction>?> restore();

  /// Tells the store the household has it. Only after the server said so.
  Future<void> finish(StoreTransaction transaction);

  /// The system's own subscription management — change plan, cancel.
  Future<bool> manage();

  /// Transactions that arrive outside a purchase: renewals, approvals, refunds.
  Stream<StoreTransaction> get updates;
}

/// One transaction as the store signed it. [signed] is the only thing the
/// server believes; [id] is what [StoreBilling.finish] hands back.
@immutable
class StoreTransaction {
  final String id;
  final String signed;

  const StoreTransaction({required this.id, required this.signed});

  static StoreTransaction? fromWire(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final signed = value['jws'];
    if (id is! String || signed is! String) return null;
    return StoreTransaction(id: id, signed: signed);
  }
}

enum StoreOutcomeKind {
  purchased,

  /// Ask to Buy, or a bank's own confirmation step — the transaction comes
  /// later through [StoreBilling.updates].
  pending,
  cancelled,
  failed,

  /// No store to talk to — no products configured, no scene to present on.
  unavailable,
}

@immutable
class StoreOutcome {
  final StoreOutcomeKind kind;
  final StoreTransaction? transaction;

  const StoreOutcome(this.kind, [this.transaction]);
}

/// The Plus products, in App Store Connect and in `store-verify`'s own list.
/// **Change one and change the other**, or the server refuses a real purchase.
const plusProductIds = ['com.aporah.plus.monthly', 'com.aporah.plus.yearly'];

/// The policy links the store screen shows under the prices, which App Review
/// requires on any subscription screen. Terms are Apple's standard EULA; the
/// privacy page has to exist on aporah.io before the build is submitted.
const _termsUrl = 'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';
const _privacyUrl = 'https://aporah.io/datenschutz';

/// The store on this platform, or null where there is none yet — Android until
/// Play Billing lands, and the web for good. The paywall's button stays inert
/// there rather than disappearing.
final StoreBilling? storeBilling = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS ? _AppStoreBilling() : null;

bool get storeBillingAvailable => storeBilling != null;

class _AppStoreBilling implements StoreBilling {
  static const _channel = MethodChannel('aporah/store');

  final _updates = StreamController<StoreTransaction>.broadcast();

  _AppStoreBilling() {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'transaction') return;
      final transaction = StoreTransaction.fromWire(call.arguments);
      if (transaction != null) _updates.add(transaction);
    });
  }

  @override
  String get source => 'app_store';

  @override
  Stream<StoreTransaction> get updates => _updates.stream;

  @override
  Future<StoreOutcome> showStore({required String householdId}) async {
    final Object? answer;
    try {
      answer = await _channel.invokeMethod<Object?>('showStore', {
        'ids': plusProductIds,
        'accountToken': householdId,
        'termsUrl': _termsUrl,
        'privacyUrl': _privacyUrl,
        // Only the iOS 15/16 action sheet shows these; the store view above
        // that is localised by the system.
        'title': L.s.plusName,
        'cancel': L.s.cancel,
      });
    } on PlatformException {
      return const StoreOutcome(StoreOutcomeKind.failed);
    } on MissingPluginException {
      return const StoreOutcome(StoreOutcomeKind.unavailable);
    }
    if (answer is! Map) return const StoreOutcome(StoreOutcomeKind.cancelled);
    return switch (answer['status']) {
      'purchased' => StoreOutcome(StoreOutcomeKind.purchased, StoreTransaction.fromWire(answer['transaction'])),
      'pending' => const StoreOutcome(StoreOutcomeKind.pending),
      'failed' => const StoreOutcome(StoreOutcomeKind.failed),
      'unavailable' => const StoreOutcome(StoreOutcomeKind.unavailable),
      _ => const StoreOutcome(StoreOutcomeKind.cancelled),
    };
  }

  @override
  Future<List<StoreTransaction>> unfinished() => _list('unfinished');

  @override
  Future<List<StoreTransaction>> current() => _list('current');

  @override
  Future<List<StoreTransaction>?> restore() async {
    final answer = await _channel.invokeMethod<List<Object?>>('restore');
    if (answer == null) return null;
    return [for (final row in answer) ?StoreTransaction.fromWire(row)];
  }

  @override
  Future<void> finish(StoreTransaction transaction) async {
    try {
      await _channel.invokeMethod<void>('finish', {'id': transaction.id});
    } on PlatformException {
      // Left unfinished, it is simply offered again on the next start — and
      // `store-verify` is idempotent, so that costs one request.
    }
  }

  @override
  Future<bool> manage() async {
    try {
      return await _channel.invokeMethod<bool>('manage') ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<List<StoreTransaction>> _list(String method) async {
    try {
      final answer = await _channel.invokeMethod<List<Object?>>(method) ?? const [];
      return [for (final row in answer) ?StoreTransaction.fromWire(row)];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }
}
