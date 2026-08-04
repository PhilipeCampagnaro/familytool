import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/who.dart';
import '../services/supabase.dart';
import '../l10n/l10n.dart';

/// What can be shared outside the household — exactly `public.shareable_kind`.
///
/// Three values, and no calendar among them. That is structural rather than a
/// convention: the enum names no calendar, and the calendar read policy has no
/// guest branch, so there is no code path that could share one outward by
/// accident. A German family's calendar holds doctor's appointments.
enum ShareableKind { list, box, task }

extension ShareableKindLabel on ShareableKind {
  String get wire => name;

  /// What the sheet calls it, in the accusative — "… teilen".
  String get noun => switch (this) {
    ShareableKind.list => L.s.theList,
    ShareableKind.box => L.s.theBox,
    ShareableKind.task => L.s.theTask,
  };
}

/// One outbound link. The token itself is **not** here: only its SHA-256 hash is
/// stored, and the raw one is returned exactly once, when the link is created.
/// A link whose URL was never copied cannot be recovered — it can only be
/// revoked and replaced.
class ShareLink {
  final String id;
  final bool canEdit;
  final DateTime? expiresAt;
  final int useCount;
  final int? maxUses;
  final DateTime? createdAt;

  const ShareLink({
    required this.id,
    required this.canEdit,
    this.expiresAt,
    this.useCount = 0,
    this.maxUses,
    this.createdAt,
  });

  bool get expired => expiresAt != null && expiresAt!.isBefore(DateTime.now());
  bool get usedUp => maxUses != null && useCount >= maxUses!;
  bool get live => !expired && !usedUp;
}

/// Somebody outside the household who has redeemed a link.
class Guest {
  final String userId;
  final String name;
  final String initials;
  final int tone;
  final bool canEdit;

  const Guest({
    required this.userId,
    required this.name,
    required this.initials,
    required this.tone,
    required this.canEdit,
  });

  FamilyMember get asFamilyMember =>
      FamilyMember(id: userId, name: name, initials: initials, tone: tone);
}

class SharingState {
  final List<ShareLink> links;
  final List<Guest> guests;
  final bool loading;

  /// The URL just minted, held only until the sheet is closed. This is the one
  /// moment it exists in the app at all.
  final String? freshUrl;

  final String? error;

  const SharingState({
    this.links = const [],
    this.guests = const [],
    this.loading = true,
    this.freshUrl,
    this.error,
  });

  /// Whether anything is currently shared outward — what the row badge reads.
  bool get isShared => guests.isNotEmpty || links.any((l) => l.live);

  SharingState copyWith({
    List<ShareLink>? links,
    List<Guest>? guests,
    bool? loading,
    String? freshUrl,
    bool clearFreshUrl = false,
    String? error,
    bool clearError = false,
  }) => SharingState(
    links: links ?? this.links,
    guests: guests ?? this.guests,
    loading: loading ?? this.loading,
    freshUrl: clearFreshUrl ? null : (freshUrl ?? this.freshUrl),
    error: clearError ? null : (error ?? this.error),
  );
}

/// Which resource a [sharingProvider] is about. A record rather than two
/// arguments so the family provider can key on it.
typedef ShareTarget = ({ShareableKind kind, String id});

class SharingNotifier extends StateNotifier<SharingState> {
  SharingNotifier(this._target) : super(const SharingState()) {
    load();
  }

  final ShareTarget _target;

  SupabaseClient get _db => AporahSupabase.client;

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      // Both reads are unfiltered by household on purpose — `share_links_select`
      // is "my household, and mine or I'm an admin", and `guest_access_select`
      // is "mine, or a resource I can read". Narrowing here would only be able
      // to get it wrong.
      final linkRows = await _db
          .from('share_links')
          .select('id, can_edit, expires_at, use_count, max_uses, created_at, revoked_at')
          .eq('resource_kind', _target.kind.wire)
          .eq('resource_id', _target.id)
          .isFilter('revoked_at', null)
          .order('created_at');

      final guestRows = await _db
          .from('guest_access')
          .select('user_id, can_edit')
          .eq('resource_kind', _target.kind.wire)
          .eq('resource_id', _target.id);

      final ids = [for (final r in guestRows) r['user_id'] as String];
      // `can_see_profile` lets a household member resolve exactly the guests on
      // a resource they can read — no more of that stranger's household.
      final profileRows = ids.isEmpty
          ? const <Map<String, dynamic>>[]
          : await _db.from('profiles').select('id, display_name, initials, tone').inFilter('id', ids);
      final profiles = {for (final p in profileRows) p['id'] as String: p};

      if (!mounted) return;
      state = state.copyWith(
        loading: false,
        links: [
          for (final r in linkRows)
            ShareLink(
              id: r['id'] as String,
              canEdit: r['can_edit'] as bool? ?? true,
              expiresAt: DateTime.tryParse((r['expires_at'] as String?) ?? '')?.toLocal(),
              useCount: (r['use_count'] as num?)?.toInt() ?? 0,
              maxUses: (r['max_uses'] as num?)?.toInt(),
              createdAt: DateTime.tryParse((r['created_at'] as String?) ?? '')?.toLocal(),
            ),
        ],
        guests: [
          for (final r in guestRows)
            () {
              final id = r['user_id'] as String;
              final p = profiles[id];
              return Guest(
                userId: id,
                name: (p?['display_name'] as String?) ?? L.s.guest,
                initials: (p?['initials'] as String?) ?? '?',
                tone: (p?['tone'] as num?)?.toInt() ?? 0,
                canEdit: r['can_edit'] as bool? ?? true,
              );
            }(),
        ],
      );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(loading: false, error: L.s.sharesLoadFailed);
    }
  }

  void clearError() => state = state.copyWith(clearError: true);

  void clearFreshUrl() => state = state.copyWith(clearFreshUrl: true);

  /// Mints a link, and optionally mails it. The URL comes back **once** — it is
  /// put straight into [SharingState.freshUrl] so the sheet can show a copy
  /// button, and it is gone the next time the sheet is opened.
  Future<void> createLink({bool canEdit = true, int? expiresInDays, String? email}) async {
    try {
      final res = await _db.functions.invoke('create-share-link', body: {
        'kind': _target.kind.wire,
        'resource_id': _target.id,
        'can_edit': canEdit,
        'expires_in_days': ?expiresInDays,
        if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
      });
      final data = res.data;
      final url = data is Map ? data['url'] as String? : null;
      await load();
      if (!mounted) return;
      state = state.copyWith(freshUrl: url);
    } on FunctionException catch (e) {
      // The function's own German message says why — a kid trying to share, a
      // daily cap reached — and beats anything generic invented here.
      final details = e.details;
      _fail((details is Map ? details['error'] as String? : null) ??
          L.s.shareLinkCreateFailed);
    } catch (_) {
      _fail(L.s.shareLinkCreateFailed);
    }
  }

  /// Withdraws a link. `revoke_link_guests` fires on the update and drops every
  /// guest who came in through it — revoking a link that somebody is *using*
  /// has to actually take the access away, not just stop new redemptions.
  Future<void> revokeLink(String linkId) async {
    final previous = state.links;
    state = state.copyWith(links: [for (final l in state.links) if (l.id != linkId) l]);
    try {
      final updated = await _db
          .from('share_links')
          .update({'revoked_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', linkId)
          .select('id');
      if (updated.isEmpty) throw StateError('refused');
      await load();
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(links: previous, error: L.s.linkRevokeFailed);
    }
  }

  /// Removes one guest, leaving any link intact — somebody who was let in by
  /// mistake shouldn't cost everyone else their access.
  Future<void> removeGuest(String userId) async {
    final previous = state.guests;
    state = state.copyWith(guests: [for (final g in state.guests) if (g.userId != userId) g]);
    try {
      final deleted = await _db
          .from('guest_access')
          .delete()
          .eq('resource_kind', _target.kind.wire)
          .eq('resource_id', _target.id)
          .eq('user_id', userId)
          .select('user_id');
      if (deleted.isEmpty) throw StateError('refused');
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(guests: previous, error: L.s.guestRemoveFailed);
    }
  }

  void _fail(String message) {
    if (mounted) state = state.copyWith(error: message);
  }
}

/// One notifier per shared resource. `autoDispose` because a sheet is the only
/// thing that ever watches one, and a household with forty lists should not keep
/// forty of these alive.
final sharingProvider =
    StateNotifierProvider.autoDispose.family<SharingNotifier, SharingState, ShareTarget>(
  (ref, target) => SharingNotifier(target),
);
