import Flutter
import StoreKit
import UIKit

/// The system's rating prompt — the "aporah/review" channel.
///
/// **Neither this nor anything else can tell whether the user rated.** The call
/// has no callback and no return value, and iOS shows the prompt at most three
/// times a year per app, suppressing it outright for somebody who has already
/// rated this version. So `requestReview` answers only "we asked the system",
/// never "a prompt appeared". Who is asked, and when, is decided once in
/// `lib/services/app_review.dart`.
///
/// Never wire this to a button: Apple's guidelines forbid prompting in response
/// to a user action. The Settings row opens the App Store page instead.
enum AppReview {
  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "requestReview":
      guard let scene = activeScene() else {
        result(false)
        return
      }
      Task { @MainActor in
        if #available(iOS 16.0, *) {
          AppStore.requestReview(in: scene)
        } else {
          SKStoreReviewController.requestReview(in: scene)
        }
        result(true)
      }

    case "version":
      // Part of the rule "never twice in one version" — there is no
      // package_info plugin in this app, and one key is not worth one.
      result(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func activeScene() -> UIWindowScene? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
  }
}
