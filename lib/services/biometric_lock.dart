import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Which sensor this phone unlocks with, which is what the Settings row and the
/// lock screen are named after. Face ID and Touch ID are Apple's words and only
/// ever come from iOS; Android does not say which sensor a prompt will use when
/// a phone has two, so it answers [fingerprint] or [face] only when there is
/// exactly one, and [biometrics] otherwise.
enum BiometricKind {
  faceId,
  touchId,
  opticId,
  fingerprint,
  face,
  biometrics,

  /// A screen lock but no enrolled biometry. The app lock still works — it asks
  /// for the code the phone asks for.
  passcode,

  /// No screen lock at all, so nothing to lock with. The Settings row is absent.
  none,
}

enum BiometricOutcome {
  ok,

  /// Cancelled, or the face/finger/code was not accepted.
  failed,

  /// The phone lost its screen lock since the app lock was switched on. The
  /// lock cannot be kept, and holding the household's data behind a door with
  /// no key would be the worse failure — see `AppLockNotifier.unlock`.
  unavailable,
}

/// The app lock's native half — "aporah/biometrics", in
/// `ios/Runner/BiometricLock.swift` and `BiometricChannel.kt`. Both evaluate
/// "the phone's owner" rather than "a biometric", so a locked-out sensor falls
/// back to the passcode instead of shutting the family out of the app.
class BiometricLock {
  BiometricLock._();

  static const _channel = MethodChannel('aporah/biometrics');

  static bool get _supported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android);

  static Future<BiometricKind> kind() async {
    if (!_supported) return BiometricKind.none;
    try {
      final raw = await _channel.invokeMethod<String>('kind');
      return BiometricKind.values.firstWhere((k) => k.name == raw, orElse: () => BiometricKind.none);
    } on PlatformException {
      return BiometricKind.none;
    } on MissingPluginException {
      return BiometricKind.none;
    }
  }

  static Future<BiometricOutcome> authenticate(String reason) async {
    if (!_supported) return BiometricOutcome.unavailable;
    try {
      final raw = await _channel.invokeMethod<String>('authenticate', {'reason': reason});
      return BiometricOutcome.values.firstWhere((o) => o.name == raw, orElse: () => BiometricOutcome.failed);
    } on PlatformException {
      return BiometricOutcome.failed;
    } on MissingPluginException {
      return BiometricOutcome.unavailable;
    }
  }
}
