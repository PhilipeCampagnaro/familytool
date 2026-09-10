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

  /// The channel this was registered on, so a row that *keeps the menu up* can
  /// be reported while the request it belongs to is still open. Set by
  /// AppDelegate; a `FlutterResult` answers once, and one of these rows is a
  /// toggle the user may flip twice before picking anything.
  weak var channel: FlutterMethodChannel?

  /// The menu currently on screen, kept so a `keepsOpen` row can be re-drawn
  /// with its checkmark flipped without closing anything.
  private var liveOptions: [[String: Any]] = []
  private var liveStates: [Bool] = []
  private var liveTitle: String?

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    // A menu that stays open while it is being ticked has to be re-drawn from
    // the state its own taps changed: one row's tap can move every other row's
    // checkmark (untick a calendar while "Alle" is on, and every *other*
    // calendar becomes explicitly ticked), and UIKit never re-asks for a menu
    // it has already presented.
    if call.method == "update" {
      if #available(iOS 17.4, *), let selected = (call.arguments as? [String: Any])?["selected"] as? [Bool] {
        redraw(with: selected)
      }
      result(nil)
      return
    }
    guard call.method == "show",
          let args = call.arguments as? [String: Any],
          let options = args["options"] as? [[String: Any]],
          !options.isEmpty
    else {
      result(FlutterMethodNotImplemented)
      return
    }
    // One menu at a time: a second request finishes the first **as a cancel**
    // and takes its anchor with it, rather than leaving a transparent control
    // lying over the row. Cancel and not `nil`, which is a different sentence
    // entirely — `nil` tells Dart there was no system menu to put up, so a
    // superseded caller would answer a tap that has already been answered by
    // painting its own dropdown *underneath the menu that superseded it*. Two
    // taps in quick succession put both on screen at once, which is exactly
    // what it looked like.
    //
    // Retired rather than ripped out: a menu on screen is animated out of a
    // preview of the very view it hangs off, so taking that view away while it
    // is up is fatal — see [MenuAnchorButton.retire].
    finish(NativeMenu.cancelled)
    tearDownAnchor()
    // Aporah's dark mode is its own switch in Settings, not the device's — same
    // contract as the glass views, tab bar and switch: Dart says which one the
    // app is in.
    let style: UIUserInterfaceStyle = (args["dark"] as? Bool == true) ? .dark : .light
    let title = args["title"] as? String

    pending = result
    if #available(iOS 17.4, *), let rect = NativeMenu.rect(args["anchor"]), let container = flutterView {
      presentMenu(options: options, title: title, style: style, at: rect, in: container, args: args)
    } else {
      presentSheet(options: options, args: args, style: style)
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
    args: [String: Any]
  ) {
    liveOptions = options
    liveStates = options.map { $0["selected"] as? Bool == true }
    liveTitle = title
    let menu = buildMenu()

    // A control of the anchor's own size, so the bubble grows out of the row
    // that was tapped rather than out of a point. It goes in the Flutter view,
    // whose coordinates the rect is already in — **not** in the window above it,
    // which looks like the safer place and is not: a menu asked to present from
    // a bare window subview never came up at all, and the sheet took over.
    let anchor = MenuAnchorButton(frame: rect)
    anchor.backgroundColor = .clear
    anchor.overrideUserInterfaceStyle = style
    // Setting `menu` is what enables the button's context-menu interaction, and
    // `showsMenuAsPrimaryAction` is what makes that menu the thing the button
    // *does* — which is what `performPrimaryAction()` then does.
    anchor.showsMenuAsPrimaryAction = true
    anchor.menu = menu
    anchor.onEnd = { [weak self, weak anchor] in
      // One hop after the animation, so an action handler landing on the same
      // turn as the dismissal has already answered — `finish` is a no-op once
      // it has.
      DispatchQueue.main.async {
        // **Only if this is still the menu that is up.** A closing menu reports
        // itself when its animation ends, which is a good half-second after a
        // second tap has already replaced it — or after the grace below gave up
        // and put the sheet there instead. Without this the *late* menu tore
        // down the *live* one's anchor and answered its caller: you tapped a
        // chip, the menu opened, and about a second later it closed by itself.
        guard let self, let anchor, self.anchorView === anchor else { return }
        // The anchor has already taken itself out of the hierarchy; this is
        // only letting go of it.
        self.anchorView = nil
        self.finish(NativeMenu.cancelled)
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
      // Retiring is what marks it: a menu still on its way up when we gave up
      // on it arrives, finds its anchor retired and closes itself rather than
      // landing over the sheet that replaced it.
      self.tearDownAnchor()
      self.presentSheet(options: options, args: args, style: style)
    }
  }

  /// The menu as it stands, built from [liveOptions] and the checkmarks in
  /// [liveStates] — called again, unchanged, every time a `keepsOpen` row flips
  /// one of those.
  ///
  /// Rows carrying the same `section` are wrapped in an inline submenu, which
  /// is how UIKit draws a group: a hairline above it, no indent. That is the
  /// one thing the app's own panel says that this cannot — a calendar listed
  /// *under* its account — so an account and its calendars share a section
  /// rather than a margin.
  @available(iOS 17.4, *)
  private func buildMenu() -> UIMenu {
    var sections: [[UIMenuElement]] = []
    var sectionKeys: [Int] = []
    var sectionTitles: [String] = []
    for (index, option) in liveOptions.enumerated() {
      let key = option["section"] as? Int ?? 0
      let action = self.action(for: option, at: index)
      if sectionKeys.last == key {
        sections[sections.count - 1].append(action)
      } else {
        sections.append([action])
        sectionKeys.append(key)
        // The caption the app's own panel prints over an account's calendars.
        // An inline submenu draws its title as that header, which is the only
        // place a UIMenu has for one.
        sectionTitles.append(option["sectionTitle"] as? String ?? "")
      }
    }
    if sections.count <= 1, sectionTitles.first?.isEmpty != false {
      return UIMenu(title: liveTitle ?? "", children: sections.first ?? [])
    }
    return UIMenu(
      title: liveTitle ?? "",
      children: sections.enumerated().map {
        UIMenu(title: sectionTitles[$0.offset], options: .displayInline, children: $0.element)
      }
    )
  }

  /// Puts [selected] on the menu that is up, if one still is.
  @available(iOS 17.4, *)
  private func redraw(with selected: [Bool]) {
    guard selected.count == liveOptions.count, let anchor = anchorView as? MenuAnchorButton else { return }
    liveStates = selected
    let menu = buildMenu()
    anchor.menu = menu
    anchor.contextMenuInteraction?.updateVisibleMenu { _ in menu }
  }

  @available(iOS 17.4, *)
  private func action(for option: [String: Any], at index: Int) -> UIAction {
    var attributes: UIMenuElement.Attributes = []
    if option["destructive"] as? Bool == true { attributes.insert(.destructive) }
    let keepsOpen = option["keepsOpen"] as? Bool == true
    if keepsOpen { attributes.insert(.keepsMenuPresented) }
    return UIAction(
      title: option["label"] as? String ?? "",
      image: NativeMenu.image(for: option),
      attributes: attributes,
      state: liveStates.indices.contains(index) && liveStates[index] ? .on : .off
    ) { [weak self] _ in
      guard let self else { return }
      guard keepsOpen else {
        // Answered here rather than on dismissal: the closing animation runs
        // either side of this and Dart has a photo library to put up. Tearing
        // the anchor down is left to the end of that animation, so it still has
        // the control it is animating out of.
        self.finish(index)
        return
      }
      // A row that stays: the tick is flipped here rather than waiting for Dart
      // to answer, because the menu on screen is a snapshot — UIKit will not
      // re-ask for it — and a toggle that doesn't visibly toggle reads as a
      // dead row.
      self.liveStates[index].toggle()
      let menu = self.buildMenu()
      if let anchor = self.anchorView as? MenuAnchorButton {
        anchor.menu = menu
        anchor.contextMenuInteraction?.updateVisibleMenu { _ in menu }
      }
      self.channel?.invokeMethod("keptOpen", arguments: ["index": index])
    }
  }

  /// A row's glyph: an SF Symbol by name, or a filled dot in a colour Dart
  /// sends as ARGB — a calendar's colour is data, not an icon, and there is no
  /// symbol for "green".
  private static func image(for option: [String: Any]) -> UIImage? {
    if let argb = option["color"] as? Int {
      let color = UIColor(
        red: CGFloat((argb >> 16) & 0xFF) / 255,
        green: CGFloat((argb >> 8) & 0xFF) / 255,
        blue: CGFloat(argb & 0xFF) / 255,
        alpha: CGFloat((argb >> 24) & 0xFF) / 255
      )
      return UIImage(systemName: "circle.fill", withConfiguration: UIImage.SymbolConfiguration(scale: .small))?
        .withTintColor(color, renderingMode: .alwaysOriginal)
    }
    return (option["symbol"] as? String).flatMap { UIImage(systemName: $0) }
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

  /// The controller to present from is read **here**, not when the request came
  /// in: a menu that was up at that moment is a presented controller itself,
  /// and a sheet put up inside it would go out with it.
  private func presentSheet(
    options: [[String: Any]],
    args: [String: Any],
    style: UIUserInterfaceStyle
  ) {
    guard let host = topViewController else {
      // Nothing to present from is the one thing `nil` means: Dart draws its
      // own panel instead.
      finish(nil)
      return
    }
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

  private var keyWindow: UIWindow? {
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
    return windows.first { $0.isKeyWindow } ?? windows.first
  }

  /// The controller to present the **sheet** from: the key window's root,
  /// walked down past anything already up (a Flutter sheet is a route, but a
  /// photo picker is a real controller).
  private var topViewController: UIViewController? {
    var controller = keyWindow?.rootViewController
    while let presented = controller?.presentedViewController {
      controller = presented
    }
    return controller
  }

  /// The view the **anchor** hangs in: Flutter's own, and never whatever
  /// happens to be presented over it.
  ///
  /// [topViewController] was doing this job and is wrong for it twice over. The
  /// rect Dart sends is in Flutter's coordinates, so any other view puts the
  /// menu somewhere else on screen — and a menu that is already up is itself a
  /// presented view controller, so a second menu was being hung inside the
  /// first one's presentation. Sometimes that view was not in a window yet and
  /// UIKit killed the app on the spot
  /// (`BUG_IN_CLIENT_OF_TARGETED_PREVIEW__VIEW_IS_NOT_IN_A_WINDOW`); the rest
  /// of the time the new menu opened and then went out with the old one's
  /// dismissal a moment later, which is the "it closes by itself" this was
  /// reported as.
  ///
  /// Nil while there is no window to present into, which is a `nil` to Dart and
  /// so a fall back to the app's own dropdown.
  private var flutterView: UIView? {
    guard let root = keyWindow?.rootViewController else { return nil }
    let flutter = root as? FlutterViewController
      ?? root.children.compactMap { $0 as? FlutterViewController }.first
    guard let view = (flutter ?? root).viewIfLoaded, view.window != nil else { return nil }
    return view
  }

  private func finish(_ value: Any?) {
    pending?(value)
    pending = nil
  }

  /// Lets go of the anchor. The view itself leaves when it is safe for it to —
  /// see [MenuAnchorButton.retire].
  private func tearDownAnchor() {
    if #available(iOS 17.4, *), let anchor = anchorView as? MenuAnchorButton {
      anchor.retire()
    } else {
      anchorView?.removeFromSuperview()
    }
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
  /// Run when the menu has finished closing, however it closed — unless this
  /// anchor was retired first, in which case nobody is waiting on it any more.
  var onEnd: (() -> Void)?

  /// Whether the menu ever came up, which is what [NativeMenu] waits on before
  /// deciding to fall back to the sheet.
  private(set) var didDisplayMenu = false

  /// Whether the menu is on screen right now, which decides whether this view
  /// may be taken out of the hierarchy.
  private var menuIsUp = false

  /// No longer the live anchor: a second tap has replaced it, or the grace
  /// period gave up on it and put the sheet up instead.
  private var retired = false

  /// Stand down, and take the menu with you.
  ///
  /// **Not `removeFromSuperview`.** UIKit animates a menu out of a targeted
  /// preview of the view it hangs off and asserts that the view is still in a
  /// window, so pulling the anchor out from under a menu that is up aborts the
  /// app. The menu is dismissed instead and the view goes when the animation
  /// has finished. A menu that has not appeared yet is left to arrive, see that
  /// this anchor is retired, and close itself.
  func retire() {
    retired = true
    onEnd = nil
    guard !menuIsUp else {
      contextMenuInteraction?.dismissMenu()
      return
    }
    // Nothing on screen to wait for — but a presentation may still be on its
    // way, and it would assert against a view that had already left. Well past
    // any of that is soon enough for a transparent view that answers no touch.
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
      guard let self, !self.menuIsUp else { return }
      self.removeFromSuperview()
    }
  }

  /// Never the answer to a touch. It is a stand-in for a Flutter row, laid over
  /// that row, and a button that took the tap would both swallow the row
  /// underneath it and — being a button whose primary action *is* its menu, on
  /// touch-down — put a second menu up from an anchor on its way out.
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    didDisplayMenu || retired ? nil : super.hitTest(point, with: event)
  }

  override func contextMenuInteraction(
    _ interaction: UIContextMenuInteraction,
    willDisplayMenuFor configuration: UIContextMenuConfiguration,
    animator: UIContextMenuInteractionAnimating?
  ) {
    super.contextMenuInteraction(interaction, willDisplayMenuFor: configuration, animator: animator)
    didDisplayMenu = true
    menuIsUp = true
    if retired { interaction.dismissMenu() }
  }

  override func contextMenuInteraction(
    _ interaction: UIContextMenuInteraction,
    willEndFor configuration: UIContextMenuConfiguration,
    animator: UIContextMenuInteractionAnimating?
  ) {
    super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
    menuIsUp = false
    let ended = { [weak self] in
      guard let self else { return }
      self.removeFromSuperview()
      self.onEnd?()
    }
    if let animator {
      animator.addCompletion(ended)
    } else {
      ended()
    }
  }
}
