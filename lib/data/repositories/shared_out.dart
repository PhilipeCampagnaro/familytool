import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/l10n.dart';
import '../../models/who.dart';
import '../../services/avatars.dart';

/// Who outside the household holds a set of containers, and which of them are
/// out at all.
///
/// [ids] answers "is this shared outward" — a guest other than me, or a link
/// still open — and [guests] answers "with whom", as the faces the audience
/// stack draws. A container can be in [ids] and absent from [guests]: an
/// invitation nobody has used yet is somebody who has not arrived, and there is
/// no face to draw for them.
typedef SharedOut = ({Set<String> ids, Map<String, List<FamilyMember>> guests});

const SharedOut noSharedOut = (ids: <String>{}, guests: <String, List<FamilyMember>>{});

/// [SharedOut] for one kind of container, in the two reads both Listen and
/// Boxen need.
///
/// **One function rather than one per repository**, which is unlike the rest of
/// this folder and deliberate: the three predicates it leans on
/// (`guest_access_select`, `share_links_select`, `can_see_profile`) are the same
/// three whatever `kind` is, and a second copy is how two screens end up
/// disagreeing about what "shared" means. `kind` is a `shareable_kind` value —
/// `'list'` or `'box'`; a task has no screen that shares it.
///
/// The names come along with the ids because the stack on a shelf row draws
/// household and guests in one line of circles, and resolving them per row
/// through `SharingNotifier` would be two round trips per row. `can_see_profile`
/// allows exactly the guests on a resource the caller can read, so this reads no
/// more of a stranger's household than the share sheet already does.
///
/// Never throws — it only decides whether a small stack is drawn, and a
/// container without one is still a container. `share_links_select` shows a
/// member only their own links (an admin sees all), so a member does not see the
/// mark for an invitation another member sent until somebody has come in
/// through it.
Future<SharedOut> sharedOutFor(
  SupabaseClient db, {
  required String kind,
  required List<String> resourceIds,
  required String uid,
}) async {
  if (resourceIds.isEmpty) return noSharedOut;
  try {
    final results = await Future.wait([
      db
          .from('guest_access')
          .select('resource_id, user_id')
          .eq('resource_kind', kind)
          .inFilter('resource_id', resourceIds)
          .neq('user_id', uid),
      db
          .from('share_links')
          .select('resource_id')
          .eq('resource_kind', kind)
          .inFilter('resource_id', resourceIds)
          .isFilter('revoked_at', null)
          .or('expires_at.is.null,expires_at.gt.${DateTime.now().toUtc().toIso8601String()}'),
    ]);
    final grantRows = results[0];
    final linkRows = results[1];

    final userIds = {for (final r in grantRows) r['user_id'] as String}.toList();
    final profileRows = userIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : await db
              .from('profiles')
              .select('id, display_name, initials, tone, avatar_url')
              .inFilter('id', userIds);
    final signed = await signAvatarUrls([
      for (final p in profileRows)
        if (p['avatar_url'] is String) p['avatar_url'] as String,
    ]);
    final people = {
      for (final p in profileRows)
        p['id'] as String: FamilyMember(
          id: p['id'] as String,
          // A guest whose profile did not come back is still somebody with
          // access, so they keep a circle rather than disappearing out of the
          // stack that is meant to be the whole answer.
          name: (p['display_name'] as String?) ?? L.s.guest,
          initials: (p['initials'] as String?) ?? '?',
          tone: (p['tone'] as num?)?.toInt() ?? 0,
          imageUrl: signed[p['avatar_url']],
        ),
    };

    final guests = <String, List<FamilyMember>>{};
    for (final r in grantRows) {
      final person = people[r['user_id'] as String];
      if (person == null) continue;
      (guests[r['resource_id'] as String] ??= []).add(person);
    }

    return (
      ids: {
        for (final rows in [grantRows, linkRows])
          for (final r in rows) r['resource_id'] as String,
      },
      guests: guests,
    );
  } catch (_) {
    return noSharedOut;
  }
}
