import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The two things somebody outside the app can hand a person as a link: a seat
/// in a household (`invite-member`) or one list or box (`create-share-link`).
enum IncomingLinkKind { invite, share }

@immutable
class IncomingLink {
  final IncomingLinkKind kind;

  /// The raw token. Only its hash is stored server-side, so this is the one
  /// copy that can redeem it — never log it.
  final String token;

  const IncomingLink(this.kind, this.token);
}

/// The hosts the app claims as Universal Links / App Links. Must match
/// `ios/Runner/Runner.entitlements`, the Android intent filter, and the
/// `apple-app-site-association` file served on the domain — a host missing
/// from any one of them opens the browser instead of the app.
const incomingLinkHosts = {'aporah.io', 'www.aporah.io'};

/// `https://aporah.io/invite/<token>`, `https://aporah.io/share/<token>`, or
/// the same paths under the `aporah://` scheme. Anything else is not ours to
/// handle — `aporah://login-callback` in particular belongs to supabase_flutter,
/// which listens to the same stream.
IncomingLink? parseIncomingLink(Uri uri) {
  final List<String> segments;
  if (uri.scheme == 'aporah') {
    segments = [uri.host, ...uri.pathSegments];
  } else if (uri.scheme == 'https' && incomingLinkHosts.contains(uri.host)) {
    segments = uri.pathSegments;
  } else {
    return null;
  }
  final parts = segments.where((s) => s.isNotEmpty).toList();
  if (parts.length != 2) return null;
  final kind = switch (parts[0]) {
    'invite' => IncomingLinkKind.invite,
    'share' => IncomingLinkKind.share,
    _ => null,
  };
  return kind == null ? null : IncomingLink(kind, parts[1]);
}

/// The link the app was opened with, held until somebody can act on it.
///
/// Held rather than handled on arrival because the person tapping an
/// invitation is very often not signed in yet — they are the one being invited.
/// The link waits through sign-up and is picked up by `IncomingLinkHandler`
/// once there is a session and a household to leave.
class IncomingLinkNotifier extends StateNotifier<IncomingLink?> {
  IncomingLinkNotifier() : super(null) {
    final links = AppLinks();
    // `getInitialLink` as well as the stream: supabase_flutter subscribed to
    // the same singleton first, and a cold-start link is not guaranteed to be
    // replayed to a second listener.
    unawaited(links.getInitialLink().then((uri) => uri == null ? null : _take(uri)));
    _sub = links.uriLinkStream.listen(_take);
  }

  StreamSubscription<Uri>? _sub;

  /// Tokens already taken, so the initial link arriving on both paths is
  /// handled once.
  final _seen = <String>{};

  void _take(Uri uri) {
    final link = parseIncomingLink(uri);
    if (link == null || !mounted || !_seen.add(link.token)) return;
    state = link;
  }

  void done() => state = null;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final incomingLinkProvider = StateNotifierProvider<IncomingLinkNotifier, IncomingLink?>((ref) => IncomingLinkNotifier());
