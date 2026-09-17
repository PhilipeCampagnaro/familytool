import Flutter
import UIKit

/// The system share sheet — the "aporah/share" channel.
///
/// **The answer is load-bearing.** Sharing a list mints a link on the server
/// before this sheet can offer it, and only the link's hash is stored, so a
/// link from a sheet that was cancelled is one nobody holds. The Dart side
/// revokes it on `false`, which is what keeps "Teilen, abbrechen, Teilen" from
/// leaving a trail of live invitations behind. "Kopieren" counts as sent: the
/// link left the app, and nothing here can tell where it went.
enum ShareSheet {
  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "share",
          let args = call.arguments as? [String: Any],
          let text = args["text"] as? String
    else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let presenter = topViewController() else {
      // Nothing to present from. Dart reads nil as "no sheet appeared" and
      // falls back to the clipboard.
      result(nil)
      return
    }

    // Text and URL as separate items: Messages and WhatsApp draw a link preview
    // for the URL, and "Kopieren" still takes both.
    var items: [Any] = [text]
    if let raw = args["url"] as? String, let url = URL(string: raw) {
      items.append(url)
    }
    let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)

    // iPad presents the sheet as a popover, which has to point at something —
    // the button that asked, in the Flutter view's own points.
    if let popover = controller.popoverPresentationController {
      popover.sourceView = presenter.view
      if let anchor = args["anchor"] as? [String: Double],
         let x = anchor["x"], let y = anchor["y"], let w = anchor["w"], let h = anchor["h"] {
        popover.sourceRect = CGRect(x: x, y: y, width: w, height: h)
      } else {
        let bounds = presenter.view.bounds
        popover.sourceRect = CGRect(x: bounds.midX, y: bounds.midY, width: 0, height: 0)
      }
    }

    // Answered once. The handler can run again after an extension finishes, and
    // a FlutterResult called twice crashes the app.
    var answered = false
    controller.completionWithItemsHandler = { _, completed, _, _ in
      guard !answered else { return }
      answered = true
      result(completed)
    }
    presenter.present(controller, animated: true)
  }

  private static func topViewController() -> UIViewController? {
    let window = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }?
      .windows
      .first { $0.isKeyWindow }
    var top = window?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}
