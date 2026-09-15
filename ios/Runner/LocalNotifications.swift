import Flutter
import UIKit
import UserNotifications

/// Scheduled, on-device notifications — the "aporah/notifications" channel.
///
/// **Local, not push.** Everything Aporah says today is something the phone
/// already knows the time of: an appointment's reminder, the evening before the
/// bins go out, a to-do's hour, the morning brief. None of it needs a server, a
/// push key or a token, and all of it works in flight mode. See
/// docs/notifications.md.
///
/// **The Dart side owns the schedule; this side only replaces it.** Appointments
/// move and vanish in somebody else's calendar and we find out on the next read,
/// so nothing here is ever "one notification added". `replaceAll` takes the whole
/// pending set, derived fresh by `lib/state/notification_scheduler.dart`, and
/// swaps ours for it. Only identifiers carrying [prefix] are touched.
///
/// **iOS keeps the 64 soonest pending requests per app and silently drops the
/// rest.** The Dart side caps what it sends below that; this side trusts it.
final class LocalNotifications: NSObject, UNUserNotificationCenterDelegate {
  private let center = UNUserNotificationCenter.current()

  private static let prefix = "aporah."

  /// Must run before launch finishes, or a tap on a notification that launched
  /// the app is delivered to nobody.
  func install() {
    center.delegate = self
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "status":
      status { value in DispatchQueue.main.async { result(value) } }

    case "request":
      let args = call.arguments as? [String: Any]
      var options: UNAuthorizationOptions = [.alert, .sound, .badge]
      // Quiet delivery to Notification Centre with no dialog at all. Asking
      // again *without* it later is what puts up the real prompt, which is how
      // a provisional grant gets promoted.
      if args?["provisional"] as? Bool == true { options.insert(.provisional) }
      center.requestAuthorization(options: options) { [weak self] _, _ in
        self?.status { value in DispatchQueue.main.async { result(value) } }
      }

    case "openSettings":
      let raw: String
      if #available(iOS 16.0, *) {
        raw = UIApplication.openNotificationSettingsURLString
      } else {
        raw = UIApplication.openSettingsURLString
      }
      if let url = URL(string: raw) { UIApplication.shared.open(url) }
      result(nil)

    case "replaceAll":
      guard let args = call.arguments as? [String: Any],
            let items = args["items"] as? [[String: Any]]
      else {
        result(FlutterError(code: "bad_args", message: "items missing", details: nil))
        return
      }
      replaceAll(items) { DispatchQueue.main.async { result(nil) } }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func status(_ done: @escaping (String) -> Void) {
    center.getNotificationSettings { settings in
      switch settings.authorizationStatus {
      case .notDetermined: done("notDetermined")
      case .denied: done("denied")
      case .provisional: done("provisional")
      // Ephemeral is an App Clip's grant; treat it as the real thing.
      default: done("authorized")
      }
    }
  }

  private func replaceAll(_ items: [[String: Any]], done: @escaping () -> Void) {
    center.getPendingNotificationRequests { [weak self] pending in
      guard let self else { return done() }
      let ours = pending.map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
      self.center.removePendingNotificationRequests(withIdentifiers: ours)

      let now = Date()
      for item in items {
        guard let id = item["id"] as? String,
              let at = item["at"] as? NSNumber,
              let title = item["title"] as? String
        else { continue }

        // An interval rather than a calendar trigger: every one of these is an
        // instant, and the whole set is re-derived on each foreground, so a
        // time-zone change is corrected the next time the app is opened.
        let interval = Date(timeIntervalSince1970: at.doubleValue / 1000).timeIntervalSince(now)
        guard interval > 1 else { continue }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = item["body"] as? String ?? ""
        content.sound = .default
        if let thread = item["thread"] as? String { content.threadIdentifier = thread }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        self.center.add(UNNotificationRequest(identifier: Self.prefix + id, content: content, trigger: trigger))
      }
      done()
    }
  }

  // MARK: UNUserNotificationCenterDelegate

  /// Shown while the app is open too. The morning brief arriving while somebody
  /// happens to be looking at Home is still the morning brief.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .list, .sound])
  }

  /// A tap opens the app, and that is all it does for now.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    completionHandler()
  }
}
