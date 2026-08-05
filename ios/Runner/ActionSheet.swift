import Flutter
import UIKit

/// A system action sheet, behind the "aporah/action_sheet" channel that
/// `lib/services/action_sheet.dart` calls. Registered in AppDelegate.
///
/// The app's own dropdown (`lib/widgets/anchored_menu.dart`) is the normal way
/// to offer a short choice, and it stays that way everywhere it works. This
/// exists for the one place it doesn't: a menu opened from *inside* a sheet
/// that carries native glass buttons. Flutter content composited after a
/// platform view can be dropped whole on device — it already ate this sheet's
/// title once, and then the route menu — and a menu you cannot see is worse
/// than a menu that looks like iOS's rather than like ours. `UIAlertController`
/// is presented by UIKit itself, so there is no Flutter layer left to lose.
///
/// Answers the index that was picked, [cancelled] when the user dismissed it,
/// and `nil` when there was nothing to present from — Dart falls back to its
/// own menu on `nil`, which is also what every non-iOS platform gets.
final class ActionSheet: NSObject {
  /// What Dart reads as "the user backed out", as opposed to a `nil` that means
  /// "this device could not put a sheet up at all".
  private static let cancelled = -1

  /// The pending choice's callback. One sheet at a time; a second request
  /// finishes the first as a cancel rather than stranding it.
  private var pending: FlutterResult?

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "show",
          let args = call.arguments as? [String: Any],
          let options = args["options"] as? [String],
          !options.isEmpty
    else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let host = topViewController else {
      result(nil)
      return
    }
    finish(nil)
    pending = result

    let sheet = UIAlertController(
      title: args["title"] as? String,
      message: args["message"] as? String,
      preferredStyle: .actionSheet
    )
    for (index, option) in options.enumerated() {
      sheet.addAction(UIAlertAction(title: option, style: .default) { [weak self] _ in
        self?.finish(index)
      })
    }
    sheet.addAction(UIAlertAction(title: args["cancel"] as? String ?? "Cancel", style: .cancel) { [weak self] _ in
      self?.finish(ActionSheet.cancelled)
    })
    // Aporah's dark mode is its own switch in Settings, not the device's — same
    // contract as the glass views, tab bar and switch: Dart says which one the
    // app is in.
    sheet.overrideUserInterfaceStyle = (args["dark"] as? Bool == true) ? .dark : .light
    // On iPad an action sheet is a popover and must say where it comes from.
    // Anchored to the bottom centre with no arrow, so it reads like the sheet
    // it is on the phone rather than pointing at an arbitrary control.
    if let popover = sheet.popoverPresentationController {
      popover.sourceView = host.view
      popover.sourceRect = CGRect(x: host.view.bounds.midX, y: host.view.bounds.maxY, width: 0, height: 0)
      popover.permittedArrowDirections = []
    }
    // A popover dismissed by tapping outside runs no action at all, so without
    // this the Dart future would simply never complete.
    sheet.presentationController?.delegate = self
    host.present(sheet, animated: true)
  }

  /// The controller to present from: the key window's root, walked down past
  /// anything Flutter already has up (the event-detail sheet is a Flutter
  /// route, but a `showModalBottomSheet` from a plugin would be a real one).
  private var topViewController: UIViewController? {
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
    var controller = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
    while let presented = controller?.presentedViewController {
      controller = presented
    }
    return controller
  }

  private func finish(_ value: Any?) {
    pending?(value)
    pending = nil
  }
}

extension ActionSheet: UIAdaptivePresentationControllerDelegate {
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    finish(ActionSheet.cancelled)
  }
}
