import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'external_links.dart';

/// Whether the system rating prompt exists here.
bool get reviewAvailable =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android);

/// The App Store id, once the listing exists. **Empty until then**, and the
/// Settings row that opens the store is absent while it is — a link to a
/// listing that does not exist is a dead button.
const _appStoreId = '';

const _playPackage = 'com.aporah.aporah';

/// The store page's review form, or null where there is none to open yet.
///
/// This is what a **button** opens. The system prompt is never wired to a tap
/// (Apple forbids it, and the system may ignore it); this link is unlimited,
/// costs no quota and is where somebody who wants to rate goes.
String? get storeReviewUrl {
  if (kIsWeb) return null;
  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS when _appStoreId.isNotEmpty =>
      'https://apps.apple.com/app/id$_appStoreId?action=write-review',
    TargetPlatform.android => 'https://play.google.com/store/apps/details?id=$_playPackage',
    _ => null,
  };
}

Future<void> openStoreReview() async {
  final url = storeReviewUrl;
  if (url != null) await openExternalUrl(url);
}

/// **Who is asked for a rating, and when — decided here and nowhere else.**
///
/// Neither store tells an app whether somebody rated it. Apple has no callback;
/// Play's flow completes the same way for five stars and a swipe. What protects
/// a user who already rated is the OS itself: iOS shows the prompt at most three
/// times a year and not at all to someone who rated this version, and Play keeps
/// a quota of its own. So this class does not try to know who rated. It makes
/// sure the few attempts the system allows are spent on a good moment:
///
/// * never in the first [_settleIn] of use;
/// * never twice in one app version, never within [_gap] of the last ask, and
///   at most [_perYear] times in a year — one below Apple's three, so there is
///   always one left for a version that deserves it;
/// * never within [_afterPaywall] of the paywall: somebody who just declined to
///   pay is not who to ask for five stars;
/// * only from a **win the user just caused** — the callers are a shopping list
///   ticked off and a tracker reaching a week — never on a timer.
///
/// A plain object rather than a provider because its callers are notifiers,
/// which hold no `ref`, and because it has no state anybody draws.
class ReviewPrompt {
  ReviewPrompt._();

  static const _channel = MethodChannel('aporah/review');

  static const _settleIn = Duration(days: 14);
  static const _gap = Duration(days: 120);
  static const _perYear = 2;
  static const _afterPaywall = Duration(minutes: 15);

  static const _kFirstSeen = 'review_first_seen';
  static const _kAsks = 'review_asks';
  static const _kLastVersion = 'review_last_version';

  DateTime? _paywallAt;
  bool _askedThisSession = false;

  /// Called once the household's app shell is up — the start of "use".
  Future<void> noteLaunch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.containsKey(_kFirstSeen)) {
        await prefs.setInt(_kFirstSeen, DateTime.now().millisecondsSinceEpoch);
      }
    } catch (_) {
      // No storage this session: nobody is asked, which is the safe answer.
    }
  }

  void notePaywall() => _paywallAt = DateTime.now();

  /// A win just happened. Asks if everything above agrees; otherwise nothing.
  Future<void> maybeAsk() async {
    if (!reviewAvailable || _askedThisSession) return;
    final now = DateTime.now();
    final paywall = _paywallAt;
    if (paywall != null && now.difference(paywall) < _afterPaywall) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final firstSeen = prefs.getInt(_kFirstSeen);
      if (firstSeen == null) return;
      if (now.difference(DateTime.fromMillisecondsSinceEpoch(firstSeen)) < _settleIn) return;

      final asks = [
        for (final raw in prefs.getStringList(_kAsks) ?? const <String>[])
          if (int.tryParse(raw) case final ms?) DateTime.fromMillisecondsSinceEpoch(ms),
      ]..sort();
      if (asks.isNotEmpty && now.difference(asks.last) < _gap) return;
      final thisYear = asks.where((a) => now.difference(a) < const Duration(days: 365)).length;
      if (thisYear >= _perYear) return;

      final version = await _channel.invokeMethod<String>('version');
      if (version != null && version == prefs.getString(_kLastVersion)) return;

      // Recorded before the call, not after: the call cannot report whether a
      // prompt appeared, so an attempt is what counts against the budget.
      _askedThisSession = true;
      await prefs.setStringList(_kAsks, [
        for (final a in asks) '${a.millisecondsSinceEpoch}',
        '${now.millisecondsSinceEpoch}',
      ]);
      if (version != null) await prefs.setString(_kLastVersion, version);

      // After the moment has landed on screen — the last tick's animation, the
      // streak number — rather than over the top of it.
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      await _channel.invokeMethod<bool>('requestReview');
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    } catch (_) {
      return;
    }
  }
}

final reviewPrompt = ReviewPrompt._();
