import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whether Ausgaben exists on this platform at all.
///
/// **The whole feature, not just the automatic half.** [SpendIntents.isSupported]
/// answers whether *capture* can work; this answers whether the household is
/// offered the screen, the fifth tab's second row and the capture page in
/// Settings. They are still two questions, because manual entry is half of
/// Ausgaben and would run anywhere — but on both platforms that ship today the
/// answer happens to be the same.
bool get spendAvailable =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android);

/// How this phone hears about a payment.
///
/// Not cosmetic: the two routes need different setup, different copy and
/// different promises, and every branch in the capture page turns on this rather
/// than on `defaultTargetPlatform` scattered through the widgets.
enum SpendCaptureRoute {
  /// iOS. A Personal Automation with a Transaction trigger runs an App Intent
  /// Aporah donates, and the intent posts the payment itself. The transaction
  /// arrives **typed** — Apple hands over a merchant and an amount as fields.
  appIntent,

  /// Android. There is no payment trigger and no wallet API that reads
  /// transactions, so the wallet's own notification is read instead. The
  /// transaction arrives as **a sentence written for a human**, which is why
  /// `WalletNotifications.kt` is a parser and why a shop name it had to guess is
  /// filed flagged.
  notificationListener,

  /// Nowhere else. Manual entry still works; nothing captures.
  none,
}

SpendCaptureRoute get spendCaptureRoute {
  if (kIsWeb) return SpendCaptureRoute.none;
  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS => SpendCaptureRoute.appIntent,
    TargetPlatform.android => SpendCaptureRoute.notificationListener,
    _ => SpendCaptureRoute.none,
  };
}

/// Whether setup on this platform has a second, OS-owned switch in it.
///
/// True only on Android. Top-level as well as on [SpendIntents] because the
/// Settings row and the Ausgaben row need it to choose a *label* long before
/// anybody has an instance in hand, and reaching for the provider to answer a
/// question about the platform would be the long way round.
bool get spendUsesNotificationAccess => spendCaptureRoute == SpendCaptureRoute.notificationListener;

/// This phone's side of automatic spend capture.
///
/// **The app never sees the transaction, on either platform.** On iOS an App
/// Intent woken by a Personal Automation posts straight to `spend-ingest` in
/// Swift; on Android a `NotificationListenerService` the system keeps alive does
/// the same in Kotlin. Flutter learns about the row on the next refresh like any
/// other. There is no method channel carrying a payment, because at the moment
/// one arrives there is no Flutter engine to carry it to — the phone is usually
/// locked and the app is not on screen, and on Android the app may not have been
/// opened for a week.
///
/// So what crosses this channel is only the plumbing that capture needs and Dart
/// owns: the token from `spend-enroll`, which the native side keeps where a
/// background process can reach it, and the device's name and id, so the
/// enrolment can be named and later revoked. Android adds one question iOS does
/// not have — whether the user has granted notification access — because there
/// the OS grant is a second switch beside our own and capture is dead without
/// it.
///
/// Off both platforms every call is a no-op and [isSupported] is false.
class SpendIntents {
  const SpendIntents();

  static const _channel = MethodChannel('aporah/spend');

  /// Whether this device can capture transactions at all.
  ///
  /// Answers for the platform, not for the OS version: iOS needs 16 for App
  /// Intents and reports that separately through [describeDevice], because a
  /// phone that cannot run the intent can still hold a token and would otherwise
  /// be told nothing. Android's floor is below the notification listener's, so
  /// there the version question cannot fail.
  bool get isSupported => spendCaptureRoute != SpendCaptureRoute.none;

  /// Whether setup has a second, OS-owned switch in it.
  ///
  /// True only on Android. It is the difference between the two routes that the
  /// user actually feels: on iOS the remaining work is in the Shortcuts app, on
  /// Android it is a toggle in system Settings that Aporah can open but cannot
  /// set.
  bool get usesNotificationAccess => spendUsesNotificationAccess;

  /// Whether this device holds a token.
  ///
  /// The device list from the server answers a different question — who *may*
  /// write — and cannot tell this phone from the other parent's.
  Future<bool> hasToken() async {
    if (!isSupported) return false;
    return await _invoke<bool>('hasToken') ?? false;
  }

  /// Whether the user has granted this app notification access.
  ///
  /// Android only; false everywhere else, and the capture page only asks where
  /// [usesNotificationAccess] is true. Read from the system's own setting on
  /// every call rather than remembered: the user can revoke it in Settings at
  /// any time, and a remembered "granted" would leave the page claiming a
  /// capture that has silently stopped.
  Future<bool> hasNotificationAccess() async {
    if (!usesNotificationAccess) return false;
    return await _invoke<bool>('hasNotificationAccess') ?? false;
  }

  /// Opens the system screen that grants it.
  ///
  /// There is no runtime permission dialog for notification access and there
  /// never has been — the user has to find Aporah in a system list and switch it
  /// on. So this opens the list and the page spells the step out beside it,
  /// rather than pretending a tap here is the grant.
  Future<void> openNotificationAccess() async {
    if (!usesNotificationAccess) return;
    await _invoke<void>('openNotificationAccess');
  }

  /// Puts the token, and the address it is good for, where capture will look for
  /// them.
  ///
  /// Stored on iOS with `kSecAttrAccessibleAfterFirstUnlock` and on Android in
  /// an AES-GCM-wrapped app-private file, which is the same promise twice:
  /// readable once the phone has been unlocked at least since boot, and
  /// unreadable before that. It is what makes background capture work at all,
  /// because a payment happens with the phone in a pocket.
  ///
  /// The endpoint travels with the token rather than being compiled into the
  /// native side, so a build pointed at a staging project with
  /// `--dart-define=SUPABASE_URL=…` files its spends there too. Two copies of
  /// that address would be one copy too many, and the wrong one would only show
  /// up as transactions silently landing in the wrong project.
  Future<void> storeToken({required String token, required String endpoint, required String apiKey}) async {
    if (!isSupported) return;
    await _invoke<void>('storeToken', {'token': token, 'endpoint': endpoint, 'api_key': apiKey});
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
      label: map?['label'] as String? ?? _fallbackLabel,
      uid: map?['uid'] as String? ?? '',
      // False on iOS 15, where App Intents do not exist. The setup screen says
      // so instead of walking the user into Shortcuts to look for an action that
      // was never donated. Always true on Android.
      canCapture: map?['can_run_intents'] as bool? ?? false,
      notificationAccess: map?['has_notification_access'] as bool? ?? false,
    );
  }

  String get _fallbackLabel =>
      spendCaptureRoute == SpendCaptureRoute.notificationListener ? 'Android' : 'iPhone';

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
  /// The device's own name, as the user set it — iOS Settings, or Android's
  /// `device_name`. A model number is the fallback, never the first answer: the
  /// revoke list has to be readable by whoever is holding the other phone.
  final String label;

  /// `identifierForVendor` on iOS, a uuid minted once per install on Android.
  /// Stable for this app on this device, reset when the app's data goes. Not a
  /// tracking identifier: it never leaves our own backend and is only ever
  /// compared against itself.
  final String uid;

  /// Whether the OS is new enough to capture at all.
  final bool canCapture;

  /// Android's second switch, answered at the same time so the page can show
  /// both halves of setup without a second round trip.
  final bool notificationAccess;

  const SpendDeviceIdentity({
    required this.label,
    required this.uid,
    required this.canCapture,
    required this.notificationAccess,
  });
}
