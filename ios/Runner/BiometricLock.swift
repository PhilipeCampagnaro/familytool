import Flutter
import LocalAuthentication
import UIKit

/// The app lock's two questions — the "aporah/biometrics" channel.
///
/// `kind` says which sensor this phone has, so Settings can name the row after
/// it: Face ID on a phone with a TrueDepth camera, Touch ID on one with a home
/// button or a sensor in the side key, Optic ID on Vision Pro. Asked every
/// time rather than cached, because a user can enrol or remove a face in
/// Settings while the app is suspended.
///
/// `authenticate` evaluates `.deviceOwnerAuthentication`, **not**
/// `…WithBiometrics`, on purpose: after too many failed faces the sensor locks
/// out, and a biometrics-only policy would then have no way in at all — the
/// household's lists behind a lock only a trip to the phone's own Settings can
/// open. With the owner policy iOS offers the passcode as the fallback, which is
/// the same key that unlocks the phone the app is on.
enum BiometricLock {
  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "kind":
      result(kind())

    case "authenticate":
      let reason = (call.arguments as? [String: Any])?["reason"] as? String ?? " "
      let context = LAContext()
      var error: NSError?
      guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
        // No passcode on the phone at all. Dart reads this as "the lock cannot
        // be kept" rather than as a failed attempt — see `unavailable`.
        result("unavailable")
        return
      }
      context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in
        DispatchQueue.main.async { result(ok ? "ok" : "failed") }
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// `none` means no passcode is set, and then there is nothing to lock with.
  /// `passcode` means a passcode but no enrolled biometry — the lock still
  /// works, it just asks for the code.
  private static func kind() -> String {
    let context = LAContext()
    var error: NSError?
    if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
      switch context.biometryType {
      case .faceID: return "faceId"
      case .touchID: return "touchId"
      default:
        if #available(iOS 17.0, *), context.biometryType == .opticID { return "opticId" }
        return "biometrics"
      }
    }
    return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) ? "passcode" : "none"
  }
}
