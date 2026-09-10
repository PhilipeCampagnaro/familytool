import Flutter
import UIKit

/// The system's own menu, **anchored to the control that opened it**, behind
/// the "aporah/menu" channel that `lib/services/native_menu.dart` calls.
/// Registered in AppDelegate.
///
/// The app's own dropdown (`lib/widgets/anchored_menu.dart`) is still the
/// normal way to offer a short choice, and it stays that way everywhere it
/// works. This exists for the one place it doesn't: a menu opened from *inside*
/// a sheet that carries native glass buttons. Flutter content composited after
/// a platform view can be dropped whole on device — it already ate a sheet's
/// title once, and then the event sheet's route menu — and a menu you cannot
/// see is worse than a menu that isn't ours. UIKit presents this one itself, so
/// there is no Flutter layer left to lose.
///
/// **It is a menu beside the tap, not a sheet at the bottom of the screen.** A
/// `UIAlertController` was the first way out of that trap and it was the wrong
/// shape: you press a row halfway up a sheet and the answer appears at the
/// opposite end of the display, detached from the thing you pressed. A
/// `UIMenu` presented through `UIContextMenuInteraction` is what iOS itself
/// puts under a control — the same glass bubble growing out of the row — so the
/// anchored dropdown the app draws everywhere else and the one UIKit draws here
/// read as the same gesture. The interaction hangs on a transparent view laid
/// over the anchor's rect, which Dart sends in Flutter's global coordinates:
/// those are points in the Flutter view, which is this controller's own view.
///
/// There is no public call that simply puts a `UIMenu` on screen: the one way
/// in is a `UIButton` whose *primary action* is its menu, fired with
/// `performPrimaryAction()`, which is iOS 17.4. It has to be a button rather
/// than a plain `UIControl` — a control only offers its menu on a touch-down of
/// the user's own, and there is no touch here. Below that the old action sheet
/// is still the fallback — the compositing trap it was written for is older
/// than the menu that replaces it — and so is the case where the menu was asked
/// for and never appeared, which is checked rather than assumed.
///
/// Answers the index that was picked, [cancelled] when the user dismissed it,
/// and `nil` when there was nothing to present from — Dart falls back to its
/// own dropdown on `nil`, which is also what every non-iOS platform gets.
final class NativeMenu: NSObject {
  /// What Dart reads as "the user backed out", as opposed to a `nil` that means
  /// "this device could not put a menu up at all".
  private static let cancelled = -1

  /// The pending choice's callback. One menu at a time; a second request
  /// finishes the first as a cancel rather than stranding it.
  private var pending: FlutterResult?

  /// The transparent view the menu hangs off, for as long as it is up.
  private var anchorView: UIView?

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "show",
          let args = call.arguments as? [String: Any],
          let options = args["options"] as? [[String: Any]],
          !options.isEmpty
    else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let host = topViewController, let container = host.view else {
      result(nil)
      return
    }
    // One menu at a time: a second request finishes the first as a cancel and
    // takes its anchor with it rather than leaving a transparent control lying
    // over the row.
    finish(nil)
    tearDownAnchor()
    // Aporah's dark mode is its own switch in Settings, not the device's — same
    // contract as the glass views, tab bar and switch: Dart says which one the
    // app is in.
    let style: UIUserInterfaceStyle = (args["dark"] as? Bool == true) ? .dark : .light
    let title = args["title"] as? String

    pending = result
    if #available(iOS 17.4, *), let rect = NativeMenu.rect(args["anchor"]) {
      presentMenu(options: options, title: title, style: style, at: rect, in: container, host: host, args: args)
    } else {
      presentSheet(options: options, args: args, style: style, host: host)
    }
  }

  // MARK: - The anchored menu

  /// How long the control is given to put its menu up before we decide it
  /// isn't going to and fall back. Long enough to cover a frame or two of
  /// presentation, short enough that a user who tapped a row is still waiting
  /// for *something* rather than looking at a dead screen.
  private static let presentationGrace: TimeInterval = 0.4

  @available(iOS 17.4, *)
  private func presentMenu(
    options: [[String: Any]],
    title: String?,
    style: UIUserInterfaceStyle,
    at rect: CGRect,
    in container: UIView,
    host: UIViewController,
    args: [String: Any]
  ) {
    let actions: [UIMenuElement] = options.enumerated().map { index, option in
      var attributes: UIMenuElement.Attributes = []
      if option["destructive"] as? Bool == true { attributes.insert(.destructive) }
      return UIAction(
        title: option["label"] as? String ?? "",
        image: (option["symbol"] as? String).flatMap { UIImage(systemName: $0) },
        attributes: attributes,
        state: (option["selected"] as? Bool == true) ? .on : .off
      ) { [weak self] _ in
        // Answered here rather than on dismissal: the closing animation runs
        // either side of this and Dart has a photo library to put up. Tearing
        // the anchor down is left to the end of that animation, so it still has
        // the control it is animating out of.
        self?.finish(index)
      }
    }
    let menu = UIMenu(title: title ?? "", children: actions)

    // A control of the anchor's own size, so the bubble grows out of the row
    // that was tapped rather than out of a point.
    let anchor = MenuAnchorButton(frame: rect)
    anchor.backgroundColor = .clear
    anchor.overrideUserInterfaceStyle = style
    // Setting `menu` is what enables the button's context-menu interaction, and
    // `showsMenuAsPrimaryAction` is what makes that menu the thing the button
    // *does* — which is what `performPrimaryAction()` then does.
    anchor.showsMenuAsPrimaryAction = true
    anchor.menu = menu
    anchor.onEnd = { [weak self] in
      // One hop after the animation, so an action handler landing on the same
      // turn as the dismissal has already answered — `finish` is a no-op once
      // it has.
      DispatchQueue.main.async {
        self?.tearDownAnchor()
        self?.finish(NativeMenu.cancelled)
      }
    }
    container.addSubview(anchor)
    anchorView = anchor
    anchor.performPrimaryAction()

    // A menu that never came up would leave the tap unanswered forever, so the
    // sheet takes over rather than the caller waiting on nothing.
    DispatchQueue.main.asyncAfter(deadline: .now() + NativeMenu.presentationGrace) { [weak self, weak anchor] in
      guard let self, let anchor, self.anchorView === anchor, self.pending != nil, !anchor.didDisplayMenu
      else { return }
      self.tearDownAnchor()
      self.presentSheet(options: options, args: args, style: style, host: host)
    }
  }

  /// The anchor's rect in Flutter's global coordinates, which are points in the
  /// Flutter view. `nil` when Dart had no anchor to measure — a control that
  /// hasn't been laid out — which is also the cue to fall back to the sheet.
  private static func rect(_ raw: Any?) -> CGRect? {
    guard let a = raw as? [String: Any],
          let x = a["x"] as? Double, let y = a["y"] as? Double,
          let width = a["width"] as? Double, let height = a["height"] as? Double
    else { return nil }
    return CGRect(x: x, y: y, width: width, height: height)
  }

  // MARK: - The fallback sheet

  private func presentSheet(
    options: [[String: Any]],
    args: [String: Any],
    style: UIUserInterfaceStyle,
    host: UIViewController
  ) {
    let sheet = UIAlertController(
      title: args["title"] as? String,
      message: args["message"] as? String,
      preferredStyle: .actionSheet
    )
    for (index, option) in options.enumerated() {
      let destructive = option["destructive"] as? Bool == true
      sheet.addAction(
        UIAlertAction(title: option["label"] as? String ?? "", style: destructive ? .destructive : .default) { [weak self] _ in
          self?.finish(index)
        }
      )
    }
    sheet.addAction(UIAlertAction(title: args["cancel"] as? String ?? "Cancel", style: .cancel) { [weak self] _ in
      self?.finish(NativeMenu.cancelled)
    })
    sheet.overrideUserInterfaceStyle = style
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

  // MARK: - Plumbing

  /// The controller to present from: the key window's root, walked down past
  /// anything Flutter already has up (a sheet is a Flutter route, but a
  /// `showModalBottomSheet` from a plugin would be a real one).
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

  private func tearDownAnchor() {
    anchorView?.removeFromSuperview()
    anchorView = nil
  }
}

extension NativeMenu: UIAdaptivePresentationControllerDelegate {
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    finish(NativeMenu.cancelled)
  }
}

/// The transparent stand-in the menu hangs off.
///
/// A `UIButton` rather than a plain view, or even a plain `UIControl`, because
/// the button is the one control that *presents* its menu when its primary
/// action is performed. `UIControl` only offers the menu on a touch-down of the
/// user's own ("If the contextMenuInteraction is the primary action of the
/// control, invoked on touch-down", UIControl.h) — there is no touch here, the
/// user already tapped a Flutter row, so a bare control put nothing on screen.
/// `UIButton.menu` enables the interaction by itself and
/// `performPrimaryAction()` fires it.
///
/// Nothing is drawn: the row it stands over is Flutter's, and the button's own
/// empty snapshot is what the menu grows out of.
@available(iOS 17.4, *)
private final class MenuAnchorButton: UIButton {
  /// Run when the menu has finished closing, however it closed.
  var onEnd: (() -> Void)?

  /// Whether the menu ever came up, which is what [NativeMenu] waits on before
  /// deciding to fall back to the sheet.
  private(set) var didDisplayMenu = false

  override func contextMenuInteraction(
    _ interaction: UIContextMenuInteraction,
    willDisplayMenuFor configuration: UIContextMenuConfiguration,
    animator: UIContextMenuInteractionAnimating?
  ) {
    super.contextMenuInteraction(interaction, willDisplayMenuFor: configuration, animator: animator)
    didDisplayMenu = true
  }

  override func contextMenuInteraction(
    _ interaction: UIContextMenuInteraction,
    willEndFor configuration: UIContextMenuConfiguration,
    animator: UIContextMenuInteractionAnimating?
  ) {
    super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
    if let animator {
      animator.addCompletion { [onEnd] in onEnd?() }
    } else {
      onEnd?()
    }
  }
}
