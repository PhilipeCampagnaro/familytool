import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whether Ausgaben exists on this platform at all.
///
/// **The whole feature, not just the automatic half.** [SpendIntents.isSupported]
/// answers whether *capture* can work; this answers whether the household is
/// offered the screen, the fifth tab's second row and the Apple Pay page in
/// Settings. Today both are "iOS", and they are still two questions: manual
/// entry is half of Ausgaben and would run anywhere, so the day the Play build
/// ships a typed-only version this flips and [SpendIntents.isSupported] stays
/// false.
///
/// It is false on Android deliberately rather than for want of work. Google's
/// Wallet API issues passes and reads no transactions, so the automatic half
/// has nothing to be built on there, and a tab that leads to a form the other
/// parent's iPhone fills in by itself is a worse product than no tab. See
/// [docs/spend.md](../../docs/spend.md).
bool get spendAvailable => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// This phone's side of Apple Pay spend capture.
///
/// **The app never sees the transaction.** An iOS Personal Automation with a
/// Transaction trigger runs an App Intent that Aporah donates, the intent posts
/// straight to `spend-ingest` in Swift, and Flutter learns about it on the next
/// refresh like any other row. There is no method channel carrying a payment,
/// because there is no moment at which Flutter is running when one arrives — the
/// phone is usually locked and the app is not on screen.
///
/// So what crosses this channel is only the plumbing the intent needs and Dart
/// owns: the token from `spend-enroll`, which Swift keeps in the Keychain where
/// a background intent can reach it, and the device's name and vendor id, so the
/// enrolment can be named and later revoked.
///
/// Off iOS every call is a no-op and [isSupported] is false. There is no
/// Android equivalent to fall back to: Google's Wallet API issues passes and
/// reads no transactions, and the only automatic route there is reading the
/// bank app's own notifications, which is per-bank, fragile, and a restricted
/// Play Store permission. Android enters spending by hand.
class SpendIntents {
  const SpendIntents();

  static const _channel = MethodChannel('aporah/spend');

  /// Whether this device can capture Apple Pay transactions at all.
  ///
  /// Answers for the platform, not for the OS version: the Swift side needs
  /// iOS 16 for App Intents and reports that separately through
  /// [describeDevice], because a phone that cannot run the intent can still
  /// hold a token and would otherwise be told nothing.
  bool get isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Whether the Keychain holds a token on this device.
  ///
  /// The device list from the server answers a different question — who *may*
  /// write — and cannot tell this iPhone from the other parent's.
  Future<bool> hasToken() async {
    if (!isSupported) return false;
    return await _invoke<bool>('hasToken') ?? false;
  }

  /// Puts the token, and the address it is good for, where the App Intent will
  /// look for them.
  ///
  /// Stored with `kSecAttrAccessibleAfterFirstUnlock`, which is what makes
  /// background capture work at all: a Personal Automation fires on a locked
  /// phone, and an item that is only readable while unlocked would be
  /// unreadable exactly when it is needed.
  ///
  /// The endpoint travels with the token rather than being compiled into Swift,
  /// so a build pointed at a staging project with `--dart-define=SUPABASE_URL=…`
  /// files its spends there too. Two copies of that address would be one copy
  /// too many, and the wrong one would only show up as transactions silently
  /// landing in the wrong project.
  Future<void> storeToken({
    required String token,
    required String endpoint,
    required String apiKey,
  }) async {
    if (!isSupported) return;
    await _invoke<void>('storeToken', {
      'token': token,
      'endpoint': endpoint,
      'api_key': apiKey,
    });
  }

  Future<void> clearToken() async {
    if (!isSupported) return;
    await _invoke<void>('clearToken');
  }

  /// What to call this device in the revoke list, and the id that makes
  /// re-enrolling it replace its row rather than add one beside it.
  Future<SpendDeviceIdentity> describeDevice() async {
    final map = await _invoke<Map<Object?, Object?>>('describeDevice');
    return SpendDeviceIdentity(
      label: map?['label'] as String? ?? 'iPhone',
      uid: map?['uid'] as String? ?? '',
      // False on iOS 15, where App Intents do not exist. The setup screen says
      // so instead of walking the user into Shortcuts to look for an action
      // that was never donated.
      canRunIntents: map?['can_run_intents'] as bool? ?? false,
    );
  }

  Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

class SpendDeviceIdentity {
  /// The device's own name, as the user set it in iOS Settings.
  final String label;

  /// `identifierForVendor` — stable for this app on this device, and reset when
  /// the app is deleted. Not a tracking identifier: it never leaves our own
  /// backend and is only ever compared against itself.
  final String uid;

  final bool canRunIntents;

  const SpendDeviceIdentity({
    required this.label,
    required this.uid,
    required this.canRunIntents,
  });
}
