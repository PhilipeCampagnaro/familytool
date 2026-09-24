import 'package:supabase_flutter/supabase_flutter.dart' show SignedUrlSuccess;

import 'supabase.dart';

/// The private bucket the profile pictures live in — see
/// `supabase/migrations/20260805174643_avatar_pictures.sql`.
const avatarBucket = 'avatars';

/// How long a signed avatar URL stays good for.
///
/// A week rather than an hour: the URL is re-signed on every load, so the only
/// thing a short expiry would buy is a broken face in an app that was left open
/// over a weekend.
const avatarUrlTtl = Duration(days: 7);

/// Path → signed URL, for a whole roster of `profiles.avatar_url` paths at once.
///
/// One request for every face rather than one per face, and a total failure is
/// not fatal: an empty map means everybody falls back to their initials, which
/// is exactly what a member without a picture already shows.
///
/// It lives here rather than beside the household roster because three
/// unrelated layers need it — the roster, the guests on a shared resource
/// ([SharingNotifier.load]) and the audience stack Listen draws on every row —
/// and the storage read policy already admits all of them:
/// `avatars_read_visible_profiles` keys on `can_see_profile`, the same
/// predicate that let them read the profile row in the first place.
Future<Map<String, String>> signAvatarUrls(List<String> paths) async {
  if (paths.isEmpty) return const {};
  try {
    final signed = await AporahSupabase.client.storage
        .from(avatarBucket)
        .createSignedUrlsResult(paths, avatarUrlTtl.inSeconds);
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
