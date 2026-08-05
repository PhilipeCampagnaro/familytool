import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FileOptions, FunctionException, SignedUrlSuccess;

import '../models/who.dart';
import '../services/supabase.dart';
import 'auth_state.dart';
import '../l10n/l10n.dart';

/// The private bucket the profile pictures live in — see
/// `supabase/migrations/20260805174643_avatar_pictures.sql`.
const _avatarBucket = 'avatars';

/// How long a signed avatar URL stays good for.
///
/// A week rather than an hour: the URL is re-signed on every [load], so the
/// only thing a short expiry would buy is a broken face in an app that was left
/// open over a weekend.
const _avatarUrlTtl = Duration(days: 7);

/// The two avatar letters for a name, derived the same way `handle_new_user`
/// derives them server-side so a profile written from either end matches.
String initialsOf(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) {
    final w = words.first;
    return (w.length == 1 ? w : w.substring(0, 2)).toUpperCase();
  }
  return (words[0][0] + words[1][0]).toUpperCase();
}

/// The roles in `public.member_role`.
///
/// Named to match the database exactly — the old UI-only enum in
/// `settings_state.dart` spelled the third one `child`, which would have failed
/// as an enum value on write.
enum FamilyRole { admin, member, kid }

FamilyRole _roleFrom(String value) {
  switch (value) {
    case 'admin':
      return FamilyRole.admin;
    case 'kid':
      return FamilyRole.kid;
    default:
      return FamilyRole.member;
  }
}

extension FamilyRoleLabel on FamilyRole {
  String get wire => name;

  String get label => switch (this) {
    FamilyRole.admin => L.s.roleAdmin,
    FamilyRole.member => L.s.roleMember,
    FamilyRole.kid => L.s.roleChild,
  };
}

/// One household member: their profile as rendered, plus their role.
class HouseholdMember {
  final String userId;
  final String name;
  final String initials;

  /// Index into `AppTones.list`, the same convention `profiles.tone` stores.
  final int tone;

  /// What `profiles.avatar_url` actually stores: an object path in the private
  /// `avatars` bucket, `<user_id>/<uuid>.<ext>`. Null when this member has no
  /// picture and their circle is initials on a tone colour.
  final String? avatarPath;

  /// A signed URL for [avatarPath], resolved at [HouseholdNotifier.load] time
  /// and good for [_avatarUrlTtl]. Null both when there is no picture and when
  /// signing failed — the avatar falls back to the initials either way.
  final String? avatarUrl;

  final FamilyRole role;

  const HouseholdMember({
    required this.userId,
    required this.name,
    required this.initials,
    required this.tone,
    required this.role,
    this.avatarPath,
    this.avatarUrl,
  });

  HouseholdMember copyWith({
    String? name,
    String? initials,
    int? tone,
    FamilyRole? role,
    String? avatarPath,
    String? avatarUrl,
    bool clearAvatar = false,
  }) {
    return HouseholdMember(
      userId: userId,
      name: name ?? this.name,
      initials: initials ?? this.initials,
      tone: tone ?? this.tone,
      role: role ?? this.role,
      avatarPath: clearAvatar ? null : (avatarPath ?? this.avatarPath),
      avatarUrl: clearAvatar ? null : (avatarUrl ?? this.avatarUrl),
    );
  }

  /// Bridge to the existing `FamilyMember` the WhoPicker and avatar widgets
  /// already take, so those don't have to change to render a live roster.
  FamilyMember get asFamilyMember =>
      FamilyMember(id: userId, name: name, initials: initials, tone: tone);
}

class Household {
  final String id;
  final String name;
  final String? address;
  final bool onboardingDone;

  const Household({
    required this.id,
    required this.name,
    required this.onboardingDone,
    this.address,
  });
}

/// An invitation that has been sent and not yet accepted — a `family_invites`
/// row with `status = 'pending'`.
///
/// The token is deliberately absent: only its hash is stored, and the raw one
/// is handed back exactly once, by `invite-member`, at the moment it is created.
class PendingInvite {
  final String id;
  final String email;
  final String name;
  final FamilyRole role;
  final DateTime? expiresAt;

  const PendingInvite({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    this.expiresAt,
  });
}

/// What `invite-member` handed back for an invitation that was just created.
///
/// **The link is deliberately not on here.** The function returns the raw token
/// once, and the app drops it on the floor: the invitation travels by mail and
/// only by mail, so an invite can't be forwarded out of a chat group by
/// somebody who was only meant to receive it. [mailSent] is what the function's
/// mailer reported — a false is not a failed invite, it is a live invitation
/// nobody has been told about yet, and the way to fix that is to invite them
/// again, not to hand the token over.
class SentInvite {
  final String email;
  final String name;
  final FamilyRole role;
  final bool mailSent;
  final DateTime? expiresAt;

  const SentInvite({
    required this.email,
    required this.name,
    required this.role,
    required this.mailSent,
    this.expiresAt,
  });
}

/// The result of [HouseholdNotifier.inviteMember]: either the invitation or the
/// reason there isn't one.
///
/// Handed back rather than pushed into `actionError` like the other membership
/// writes, because this one is always made from a sheet that stays open: the
/// message belongs under the field it was typed into, and the success half
/// carries content (the link) that no toast could show.
class InviteOutcome {
  final SentInvite? invite;
  final String? error;

  const InviteOutcome.sent(SentInvite this.invite) : error = null;
  const InviteOutcome.failed(String this.error) : invite = null;
}

class FamilyState {
  /// Null while loading, and null when signed out. `loaded` distinguishes the
  /// two — without it the app shell can't tell "still fetching" from "there is
  /// genuinely nothing", and would flash an empty household at every launch.
  final Household? household;

  final List<HouseholdMember> members;

  /// Only ever populated for an admin: `family_invites_select` is admin-only, so
  /// for anybody else this is empty because the database said so, not because
  /// the UI chose to hide it.
  final List<PendingInvite> invites;

  final bool loaded;
  final String? error;

  /// A *write* that didn't land, as opposed to [error], which means the
  /// household could not be read at all. Kept apart because they need opposite
  /// treatments: a failed load leaves an empty page that needs an explanation
  /// which stays put, a failed write leaves the page intact and wants a snack.
  final String? actionError;

  const FamilyState({
    this.household,
    this.members = const [],
    this.invites = const [],
    this.loaded = false,
    this.error,
    this.actionError,
  });

  /// The signed-in user's own row, or null if the roster hasn't loaded.
  HouseholdMember? me(String? userId) {
    if (userId == null) return null;
    for (final m in members) {
      if (m.userId == userId) return m;
    }
    return null;
  }

  FamilyState copyWith({
    Household? household,
    List<HouseholdMember>? members,
    List<PendingInvite>? invites,
    bool? loaded,
    String? error,
    bool clearError = false,
    String? actionError,
    bool clearActionError = false,
  }) {
    return FamilyState(
      household: household ?? this.household,
      members: members ?? this.members,
      invites: invites ?? this.invites,
      loaded: loaded ?? this.loaded,
      error: clearError ? null : (error ?? this.error),
      actionError: clearActionError ? null : (actionError ?? this.actionError),
    );
  }
}

/// The household the signed-in user belongs to, and everyone in it.
///
/// Deliberately does **not** filter by `family_id` — RLS already restricts
/// `family_members` and `profiles` to what this user may see, and a guest is
/// specifically allowed to resolve a *few* profiles from another household
/// (the ones whose names appear on a shared list) without being in it. Adding a
/// client-side family filter would break exactly that case.
class HouseholdNotifier extends StateNotifier<FamilyState> {
  HouseholdNotifier(this._userId) : super(const FamilyState()) {
    if (_userId != null) load();
  }

  final String? _userId;

  Future<void> load() async {
    final uid = _userId;
    if (uid == null) {
      state = const FamilyState(loaded: true);
      return;
    }

    try {
      final db = AporahSupabase.client;

      // Which household am I in, and as what?
      final membership = await db
          .from('family_members')
          .select('family_id, role')
          .eq('user_id', uid)
          .maybeSingle();

      if (membership == null) {
        // Should be unreachable: handle_new_user gives every user a household
        // in the same transaction as the user row. If it ever happens, say so
        // rather than rendering a plausible-looking empty family.
        state = FamilyState(
          loaded: true,
          error: L.s.noHouseholdForAccount,
        );
        return;
      }

      final familyId = membership['family_id'] as String;

      final familyRow = await db
          .from('families')
          .select('id, name, address, onboarding_done')
          .eq('id', familyId)
          .maybeSingle();

      final memberRows = await db
          .from('family_members')
          .select('user_id, role')
          .eq('family_id', familyId);

      // family_members.user_id references auth.users, not profiles, so there
      // is no foreign key for PostgREST to embed across — the profiles come as
      // their own query.
      final ids = [for (final r in memberRows) r['user_id'] as String];
      final profileRows = ids.isEmpty
          ? const <Map<String, dynamic>>[]
          : await db
                .from('profiles')
                .select('id, display_name, initials, tone, avatar_url')
                .inFilter('id', ids);

      final profiles = {for (final p in profileRows) p['id'] as String: p};

      final signed = await _signAvatars([
        for (final p in profileRows)
          if (p['avatar_url'] is String) p['avatar_url'] as String,
      ]);

      final members = <HouseholdMember>[
        for (final r in memberRows)
          () {
            final id = r['user_id'] as String;
            final p = profiles[id];
            final avatarPath = p?['avatar_url'] as String?;
            return HouseholdMember(
              userId: id,
              name: (p?['display_name'] as String?) ?? L.s.unknown,
              initials: (p?['initials'] as String?) ?? '?',
              tone: (p?['tone'] as num?)?.toInt() ?? 0,
              avatarPath: avatarPath,
              avatarUrl: avatarPath == null ? null : signed[avatarPath],
              role: _roleFrom(r['role'] as String),
            );
          }(),
      ];

      // Me first, then the rest by name — the roster is rendered as an avatar
      // row and "you" belongs at its head.
      members.sort((a, b) {
        if (a.userId == uid) return -1;
        if (b.userId == uid) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      // Admin-only by policy, so this comes back empty for everyone else
      // rather than being filtered here. A failure is not fatal — a member who
      // cannot read invites still has a household to render.
      var invites = const <PendingInvite>[];
      try {
        final inviteRows = await db
            .from('family_invites')
            .select('id, email, name, role, expires_at')
            .eq('family_id', familyId)
            .eq('status', 'pending')
            .order('created_at');
        invites = [
          for (final r in inviteRows)
            PendingInvite(
              id: r['id'] as String,
              email: r['email'] as String,
              name: (r['name'] as String?) ?? '',
              role: _roleFrom(r['role'] as String),
              expiresAt: DateTime.tryParse((r['expires_at'] as String?) ?? '')?.toLocal(),
            ),
        ];
      } catch (_) {
        // Not an admin, or the read failed. Either way: no pending section.
      }

      if (!mounted) return;
      state = FamilyState(
        household: familyRow == null
            ? null
            : Household(
                id: familyRow['id'] as String,
                name: familyRow['name'] as String,
                address: familyRow['address'] as String?,
                onboardingDone: familyRow['onboarding_done'] as bool? ?? false,
              ),
        members: members,
        invites: invites,
        loaded: true,
      );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(
        loaded: true,
        error: L.s.householdLoadFailed,
      );
    }
  }

  void clearActionError() => state = state.copyWith(clearActionError: true);

  void _fail(String message) {
    if (mounted) state = state.copyWith(actionError: message);
  }

  /// Path → signed URL, for every avatar in the household at once.
  ///
  /// One request for the whole roster rather than one per face, and a total
  /// failure is not fatal: an empty map means everybody falls back to their
  /// initials, which is exactly what a member without a picture already shows.
  Future<Map<String, String>> _signAvatars(List<String> paths) async {
    if (paths.isEmpty) return const {};
    try {
      final signed = await AporahSupabase.client.storage
          .from(_avatarBucket)
          .createSignedUrlsResult(paths, _avatarUrlTtl.inSeconds);
      return {
        // A `SignedUrlFailure` is one member whose object has gone missing, not
        // a reason to drop the other four faces — hence the per-path result
        // type rather than the older list-of-urls call.
        for (final s in signed)
          if (s is SignedUrlSuccess) s.path: s.signedUrl,
      };
    } catch (_) {
      return const {};
    }
  }

  // ---------------------------------------------------------------------------
  // Membership
  //
  // Only the invite needs an Edge Function, and only because of the token: it
  // has to be generated where the client cannot see it, stored as a hash and
  // mailed. Changing a role and removing a member are plain writes — RLS admits
  // only admins, and `enforce_last_admin` / `enforce_membership_immutable` /
  // `reassign_content_on_member_removal` hold the line from there. Putting them
  // behind functions too would move the rules out of the database and into a
  // place they could be forgotten.
  // ---------------------------------------------------------------------------

  /// Sends an invitation, and says what came of it.
  ///
  /// The function's `link` is read and discarded on purpose — see [SentInvite].
  /// A failure comes back as a message rather than through `actionError`: see
  /// [InviteOutcome].
  Future<InviteOutcome> inviteMember({
    required String email,
    String name = '',
    FamilyRole role = FamilyRole.member,
  }) async {
    final trimmed = email.trim();
    final trimmedName = name.trim();
    if (!trimmed.contains('@')) return InviteOutcome.failed(L.s.enterValidEmail);

    try {
      final res = await AporahSupabase.client.functions.invoke(
        'invite-member',
        body: {'email': trimmed, 'name': trimmedName, 'role': role.wire},
      );
      final data = res.data;
      await load();
      final map = data is Map ? data : const {};
      return InviteOutcome.sent(SentInvite(
        email: trimmed,
        name: trimmedName,
        role: role,
        // Absent counts as "not sent": the honest reading of a mailer that
        // didn't say.
        mailSent: map['mail_sent'] as bool? ?? false,
        expiresAt: DateTime.tryParse((map['expires_at'] as String?) ?? '')?.toLocal(),
      ));
    } on FunctionException catch (e) {
      // The function's messages are written for the user and in German, so the
      // one it chose ("Nur Admins können Mitglieder einladen") beats anything
      // generic invented here.
      final details = e.details;
      return InviteOutcome.failed(
        (details is Map ? details['error'] as String? : null) ??
            L.s.inviteSendFailed,
      );
    } catch (_) {
      return InviteOutcome.failed(L.s.inviteSendFailed);
    }
  }

  /// Changes somebody's role. Optimistic — the row is a single enum and the
  /// picker should answer instantly — with the previous state put back if the
  /// database refuses.
  Future<void> setRole(String userId, FamilyRole role) async {
    final previous = state.members;
    state = state.copyWith(
      members: [
        for (final m in state.members)
          if (m.userId == userId) m.copyWith(role: role) else m,
      ],
    );

    try {
      final updated = await AporahSupabase.client
          .from('family_members')
          .update({'role': role.wire})
          .eq('user_id', userId)
          .select('user_id');
      // RLS refuses by returning nothing, not by raising — so an empty result
      // is the failure case, and without this check a non-admin would watch the
      // role change on screen and stay unchanged in the database.
      if (updated.isEmpty) throw StateError('refused');
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(members: previous, actionError: L.s.roleChangeFailed);
    }
  }

  /// Removes somebody from the household.
  ///
  /// Not undone locally on failure the way [setRole] is: `enforce_last_admin`
  /// and `reassign_content_on_member_removal` both fire here — the second one
  /// reassigns the leaver's family-visible content and *deletes* their private
  /// content — so the honest way to show the result is to re-read it.
  Future<void> removeMember(String userId) async {
    try {
      final deleted = await AporahSupabase.client
          .from('family_members')
          .delete()
          .eq('user_id', userId)
          .select('user_id');
      if (deleted.isEmpty) throw StateError('refused');
    } catch (_) {
      _fail(L.s.memberRemoveFailed);
    }
    await load();
  }

  /// Withdraws an invitation that hasn't been accepted yet. The token's hash
  /// stays in the row; `accept-invite` checks `status`, so a revoked link stops
  /// working immediately.
  Future<void> revokeInvite(String inviteId) async {
    final previous = state.invites;
    state = state.copyWith(invites: [for (final i in state.invites) if (i.id != inviteId) i]);
    try {
      final updated = await AporahSupabase.client
          .from('family_invites')
          .update({'status': 'revoked'})
          .eq('id', inviteId)
          .select('id');
      if (updated.isEmpty) throw StateError('refused');
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(invites: previous, actionError: L.s.inviteRevokeFailed);
    }
  }

  /// Saves the signed-in user's own profile row.
  ///
  /// `initials` is derived here rather than stored separately in the UI,
  /// matching what `handle_new_user` does at signup — otherwise a renamed user
  /// keeps the avatar letters of their old name.
  Future<void> saveMyProfile({String? displayName, int? tone}) async {
    final uid = _userId;
    if (uid == null) return;

    final patch = <String, dynamic>{};

    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) {
      patch['display_name'] = name;
      patch['initials'] = initialsOf(name);
    }
    if (tone != null) patch['tone'] = tone;
    if (patch.isEmpty) return;

    final current = state.me(uid);
    if (current != null &&
        (patch['display_name'] ?? current.name) == current.name &&
        (patch['tone'] ?? current.tone) == current.tone) {
      return; // Nothing actually changed — don't spend a round trip.
    }

    try {
      await AporahSupabase.client.from('profiles').update(patch).eq('id', uid);
      if (!mounted) return;
      state = state.copyWith(
        members: [
          for (final m in state.members)
            if (m.userId == uid)
              m.copyWith(
                name: patch['display_name'] as String?,
                initials: patch['initials'] as String?,
                tone: patch['tone'] as int?,
              )
            else
              m,
        ],
      );
    } catch (_) {
      // Left alone deliberately: the profile page is not a place to interrupt
      // someone with a network error, and the next load re-reads the truth.
    }
  }

  // ---------------------------------------------------------------------------
  // Profile picture
  //
  // Uploaded straight from the client rather than through an Edge Function: the
  // storage policies already say "your own folder, nobody else's", and the
  // bucket's own `allowed_mime_types` and `file_size_limit` are enforced by
  // Storage before a byte is stored. A function in front would only be a second
  // place for those rules to disagree.
  // ---------------------------------------------------------------------------

  /// Uploads [file] as the signed-in user's picture and points the profile at
  /// it. Returns true if it landed.
  ///
  /// Each upload gets its own object name and the previous one is deleted
  /// afterwards. Overwriting a fixed name would be simpler, but the signed URLs
  /// already handed out (and every image cache holding one) would keep serving
  /// the old face until they expired.
  Future<bool> setMyAvatar(File file) async {
    final uid = _userId;
    if (uid == null) return false;

    final extension = () {
      final dot = file.path.lastIndexOf('.');
      final ext = dot == -1 ? '' : file.path.substring(dot + 1).toLowerCase();
      // The bucket accepts five types; anything else is named .jpg and will be
      // rejected by Storage on content type if it really isn't an image.
      return const {'jpg', 'jpeg', 'png', 'heic', 'heif', 'webp'}.contains(ext) ? ext : 'jpg';
    }();
    final path = '$uid/${DateTime.now().microsecondsSinceEpoch}.$extension';
    final previous = state.me(uid)?.avatarPath;

    try {
      final storage = AporahSupabase.client.storage.from(_avatarBucket);
      await storage.upload(path, file, fileOptions: FileOptions(contentType: _contentTypeFor(extension)));
      await AporahSupabase.client.from('profiles').update({'avatar_url': path}).eq('id', uid);

      final signed = await storage.createSignedUrl(path, _avatarUrlTtl.inSeconds);

      if (mounted) {
        state = state.copyWith(
          members: [
            for (final m in state.members)
              if (m.userId == uid) m.copyWith(avatarPath: path, avatarUrl: signed) else m,
          ],
        );
      }

      // Best-effort: an orphaned object costs a few kilobytes, a failed upload
      // that already deleted the old picture costs the user their avatar.
      if (previous != null && previous != path) {
        try {
          await storage.remove([previous]);
        } catch (_) {}
      }
      return true;
    } catch (_) {
      _fail(L.s.avatarUploadFailed);
      return false;
    }
  }

  /// Drops the picture, so the avatar goes back to initials on a tone colour.
  Future<void> removeMyAvatar() async {
    final uid = _userId;
    if (uid == null) return;
    final previous = state.me(uid)?.avatarPath;
    if (previous == null) return;

    try {
      await AporahSupabase.client.from('profiles').update({'avatar_url': null}).eq('id', uid);
      if (mounted) {
        state = state.copyWith(
          members: [
            for (final m in state.members)
              if (m.userId == uid) m.copyWith(clearAvatar: true) else m,
          ],
        );
      }
      try {
        await AporahSupabase.client.storage.from(_avatarBucket).remove([previous]);
      } catch (_) {
        // The row no longer points at it; the object is just litter.
      }
    } catch (_) {
      _fail(L.s.avatarRemoveFailed);
    }
  }

  /// Storage matches the upload against the bucket's `allowed_mime_types`, and
  /// the SDK's default (`application/octet-stream`) is not on that list — so
  /// the type has to be named rather than guessed by the server.
  String _contentTypeFor(String extension) => switch (extension) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'heif' => 'image/heif',
    _ => 'image/jpeg',
  };

  /// Flips `families.onboarding_done`, which is what actually decides whether
  /// the wizard shows — the local `shared_preferences` flag can only speak for
  /// one device, and the wizard is a property of the household.
  ///
  /// Optimistic: the gate switches immediately and the write follows. A failed
  /// write means the wizard reappears next launch, which is recoverable; making
  /// the user wait on the network to leave onboarding is not worth it.
  Future<void> markOnboardingDone() async {
    final household = state.household;
    if (household == null || household.onboardingDone) return;

    state = state.copyWith(
      household: Household(
        id: household.id,
        name: household.name,
        address: household.address,
        onboardingDone: true,
      ),
    );

    try {
      await AporahSupabase.client
          .from('families')
          .update({'onboarding_done': true})
          .eq('id', household.id);
    } catch (_) {
      // Left as-is on purpose — see above.
    }
  }
}

/// Rebuilt whenever the signed-in user changes, so signing out and back in as
/// someone else cannot leave the previous household on screen.
final familyProvider = StateNotifierProvider<HouseholdNotifier, FamilyState>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  return HouseholdNotifier(userId);
});

/// The signed-in user's own role. Defaults to `kid` — the least privileged —
/// while the roster is still loading, so no admin-only control can flash into
/// view before the answer is known. RLS denies regardless; this only keeps the
/// UI honest.
final myRoleProvider = Provider<FamilyRole>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  final family = ref.watch(familyProvider);
  return family.me(userId)?.role ?? FamilyRole.kid;
});

final isAdminProvider = Provider<bool>((ref) => ref.watch(myRoleProvider) == FamilyRole.admin);

/// The live household roster, in the shape the existing avatar and picker
/// widgets already take.
final householdMembersProvider = Provider<List<FamilyMember>>((ref) {
  return [for (final m in ref.watch(familyProvider).members) m.asFamilyMember];
});
