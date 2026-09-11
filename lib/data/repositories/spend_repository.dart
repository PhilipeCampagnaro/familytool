import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/l10n.dart';
import '../../models/spend.dart';
import '../../services/supabase.dart';
import 'list_repository.dart' show newUuidV4;

/// Everything a spend is, in one place — the only file that knows they live in
/// PostgREST.
///
/// Same two rules as the other five repositories: no `family_id` filter in Dart
/// (RLS already decides what "our spending" means, and here it also decides
/// *who may see any of it* — the policies are admin-only), and column names live
/// here and nowhere else.
class SpendRepository {
  SpendRepository([SupabaseClient? client]) : _db = client ?? AporahSupabase.client;

  final SupabaseClient _db;

  static const _columns =
      'id, family_id, payer_id, merchant, amount_cents, currency, occurred_at, '
      'category, kind, source, card_label, note, needs_review';

  // -------------------------------------------------------------------------
  // Read
  // -------------------------------------------------------------------------

  /// Every spend in a half-open range, newest first.
  ///
  /// The range is half-open — `from` inclusive, `to` exclusive — so asking for
  /// two adjacent months can neither drop the row at midnight nor count it
  /// twice. `spends_family_occurred_idx` answers this directly.
  Future<List<Spend>> fetchRange(DateTime from, DateTime to) async {
    final rows = await _db
        .from('spends')
        .select(_columns)
        .gte('occurred_at', from.toUtc().toIso8601String())
        .lt('occurred_at', to.toUtc().toIso8601String())
        .order('occurred_at', ascending: false);

    return [for (final r in rows) Spend.fromMap(r)];
  }

  // -------------------------------------------------------------------------
  // Write
  // -------------------------------------------------------------------------

  /// Files one spend the user typed, and hands back the row the database made
  /// of it.
  ///
  /// **This one does read back**, unlike `createList` and the other container
  /// inserts. Their SELECT policy is a `stable` function that cannot see the row
  /// being inserted, so `insert … returning` fails outright; `spends_select`
  /// reads only the new row's own `family_id` and the caller's role, so it can.
  /// And the read-back earns its round trip here rather than merely costing one:
  /// leaving `category` null is how the caller asks the `spends_classify`
  /// trigger to name it, and the answer only exists on the returned row.
  ///
  /// The id is still generated here, so an optimistic row and the real one can
  /// be reconciled without matching on content.
  Future<Spend> createSpend({
    required String familyId,
    required String merchant,
    required int amountCents,
    required DateTime occurredAt,
    String? payerId,
    SpendCategory? category,
    SpendKind? kind,
    String? note,
    String currency = 'EUR',
  }) async {
    final payload = <String, dynamic>{
      'id': newUuidV4(),
      'family_id': familyId,
      'payer_id': payerId ?? AporahSupabase.userId,
      'merchant': merchant.trim(),
      'amount_cents': amountCents,
      'currency': currency,
      'occurred_at': occurredAt.toUtc().toIso8601String(),
      'source': SpendSource.manual.wire,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      // Omitted rather than sent as null when the user did not choose: PostgREST
      // would send an explicit null either way, which is exactly what the
      // trigger reads as "you decide", so both spellings work. Left out for
      // clarity about who is deciding.
      if (category != null) 'category': category.wire,
      if (kind != null) 'kind': kind.wire,
    };

    final row = await _db.from('spends').insert(payload).select(_columns).single();
    return Spend.fromMap(row);
  }

  /// Corrects a row. Used both for ordinary edits and for clearing the
  /// `needs_review` flag on a Wallet row that arrived with a hole in it — which
  /// is the same gesture, so it is the same call.
  Future<Spend> updateSpend(Spend spend) async {
    final row = await _db
        .from('spends')
        .update({
          'merchant': spend.merchant.trim(),
          'amount_cents': spend.amountCents,
          'occurred_at': spend.occurredAt.toUtc().toIso8601String(),
          'category': spend.category.wire,
          'kind': spend.kind.wire,
          'payer_id': spend.payerId,
          'note': spend.note,
          'needs_review': spend.needsReview,
        })
        .eq('id', spend.id)
        .select(_columns)
        .single();
    return Spend.fromMap(row);
  }

  Future<void> deleteSpend(String id) async {
    await _db.from('spends').delete().eq('id', id);
  }

  /// Re-inserts a deleted row unchanged, for undo. Keeps the original id, so a
  /// second undo of the same row is a no-op rather than a duplicate.
  Future<void> restoreSpend(Spend spend) async {
    await _db.from('spends').insert(spend.toMap());
  }

  // -------------------------------------------------------------------------
  // Enrolling this device
  // -------------------------------------------------------------------------

  /// Asks `spend-enroll` for a token this device may write Apple Pay
  /// transactions with, and hands it back exactly once.
  ///
  /// The caller's job is to put it in the Keychain and forget it. It is never
  /// shown, never copied to a clipboard and never written to
  /// `shared_preferences` — the whole point of the rebuild is that the user no
  /// longer handles a credential at all.
  Future<SpendEnrolment> enrolDevice({required String label, required String deviceUid}) async {
    final res = await _db.functions.invoke(
      'spend-enroll',
      body: {'label': label, 'device_uid': deviceUid},
    );

    final data = res.data;
    if (data is! Map || data['token'] is! String) {
      throw StateError(_errorFrom(data) ?? L.s.spendEnrolFailed);
    }
    return SpendEnrolment(deviceId: data['device_id'] as String, token: data['token'] as String);
  }

  /// The phones currently allowed to file spends, so Settings can name them and
  /// take one back. `token_hash` is revoked from `authenticated` at the column
  /// level, so it cannot be selected here even by mistake.
  Future<List<SpendDevice>> fetchDevices() async {
    final rows = await _db
        .from('spend_ingest_devices')
        .select('id, label, created_at, last_used_at, revoked_at')
        .isFilter('revoked_at', null)
        .order('created_at', ascending: true);

    return [
      for (final r in rows)
        SpendDevice(
          id: r['id'] as String,
          label: r['label'] as String,
          lastUsedAt: r['last_used_at'] == null
              ? null
              : DateTime.parse(r['last_used_at'] as String).toLocal(),
        ),
    ];
  }

  /// Stops a phone filing spends. The row stays so the revocation is a fact
  /// somebody can see, and re-enrolling the same phone brings it back rather
  /// than adding a second one beside it.
  Future<void> revokeDevice(String id) async {
    await _db
        .from('spend_ingest_devices')
        .update({'revoked_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id);
  }

  /// Edge Functions answer a failure with `{ "error": "..." }` in German,
  /// meant to be shown as-is.
  String? _errorFrom(Object? data) =>
      data is Map && data['error'] is String ? data['error'] as String : null;
}

/// What `spend-enroll` hands back. The token exists in this object and in the
/// Keychain, and nowhere else ever.
class SpendEnrolment {
  final String deviceId;
  final String token;

  const SpendEnrolment({required this.deviceId, required this.token});
}

class SpendDevice {
  final String id;
  final String label;
  final DateTime? lastUsedAt;

  const SpendDevice({required this.id, required this.label, this.lastUsedAt});
}
