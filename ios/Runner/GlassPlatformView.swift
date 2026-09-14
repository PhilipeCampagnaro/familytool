import Flutter
import UIKit

/// Factory for the native glass background used by `NativeGlassView` in Dart
/// (lib/widgets/native_glass_view.dart). Registered in AppDelegate under the
/// view type "aporah/glass_view".
class GlassPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    return GlassPlatformView(
      frame: frame,
      viewId: viewId,
      arguments: args as? [String: Any],
      messenger: messenger
    )
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    return FlutterStandardMessageCodec.sharedInstance()
  }
}

/// The glass's own touch targets.
///
/// They exist for exactly one reason: `UIGlassEffect.isInteractive` is the
/// material's own press response — the lensing that gathers under a finger and
/// follows it — and it only fires for touches **UIKit itself delivers into the
/// effect view**. This view used to be `isUserInteractionEnabled = false` with
/// the tap handled by a Flutter `GestureDetector` layered over it, which meant
/// `isInteractive` was set on every glass surface in the app and could never
/// once run: what the user got instead was a Flutter `AnimatedScale` shrinking
/// the whole control, which is a different gesture language entirely (iOS 26
/// glass does not shrink, it *lenses*).
///
/// So the press is UIKit's and only the *action* comes back to Dart. Regions
/// are fractions of the view's bounds rather than points, so a control that is
/// laid out by Flutter — which every one of these is — needs no resize traffic
/// over the channel; `layoutSubviews` re-derives them from whatever size
/// Flutter has just given the container.
///
/// A surface with **no** regions (the nav bar's backing capsule, the floating
/// pill, the `Mehr` shelf) keeps the old behaviour and takes no touches at all,
/// so nothing that was never a button starts swallowing gestures.
final class GlassTouchContainer: UIView {
  /// One fractional rect (0…1 of this view's bounds) per tappable segment.
  /// A plain button has one covering the whole surface; a `GlassIconGroup`
  /// capsule has one per segment.
  var regions: [CGRect] = [] {
    didSet { rebuildControls() }
  }

  /// Touch-down / touch-up, so Dart can mirror the press in whatever it draws
  /// *over* the glass (a `GlassIconGroup` still scales its own glyph — the
  /// icon is Flutter's, and the material's lensing says nothing about which
  /// of several segments was hit).
  var onPress: ((Int, Bool) -> Void)?

  /// A completed tap — the only thing that is still Dart's to act on.
  var onTap: ((Int) -> Void)?

  /// Where the controls are hung: the effect's own `contentView`, so the
  /// touches land *inside* the glass rather than in a sibling above it.
  weak var host: UIView?

  private var controls: [UIControl] = []

  private func rebuildControls() {
    for control in controls { control.removeFromSuperview() }
    controls = regions.indices.map { index in
      let control = UIControl()
      control.tag = index
      control.addTarget(self, action: #selector(pressDown(_:)), for: [.touchDown, .touchDragEnter])
      control.addTarget(
        self,
        action: #selector(pressUp(_:)),
        for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit]
      )
      control.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
      (host ?? self).addSubview(control)
      return control
    }
    // Only a surface that has something to tap takes touches; see the note
    // above. This is also what keeps `hitTest` out of the way of the Flutter
    // scrollable underneath a purely decorative glass panel.
    isUserInteractionEnabled = !controls.isEmpty
    setNeedsLayout()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    for (control, region) in zip(controls, regions) {
      control.frame = CGRect(
        x: region.minX * bounds.width,
        y: region.minY * bounds.height,
        width: region.width * bounds.width,
        height: region.height * bounds.height
      )
    }
  }

  @objc private func pressDown(_ sender: UIControl) { onPress?(sender.tag, true) }
  @objc private func pressUp(_ sender: UIControl) { onPress?(sender.tag, false) }
  @objc private func tapped(_ sender: UIControl) { onTap?(sender.tag) }
}

/// Wraps a `UIVisualEffectView` configured with iOS 26's real `UIGlassEffect`
/// material. On earlier iOS versions (no `UIGlassEffect` symbol) it falls
/// back to a system blur so the app still runs, but the Dart side should
/// prefer the pure-Flutter approximation there instead of this view.
///
/// Touches are the container's business — see [GlassTouchContainer] for why a
/// glass button has to be pressed by UIKit rather than by Flutter.
class GlassPlatformView: NSObject, FlutterPlatformView {
  private let container: GlassTouchContainer
  private let channel: FlutterMethodChannel
  private let effectView: UIVisualEffectView

  /// Held so a later "setTint" can build the same material again with a new
  /// colour — `UIGlassEffect` is applied as a whole effect object, so there is
  /// no tint property on the view to poke.
  private let styleName: String
  private let interactive: Bool

  init(frame: CGRect, viewId: Int64, arguments args: [String: Any]?, messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "aporah/glass_view_\(viewId)", binaryMessenger: messenger)

    // `tint` is optional: when absent we leave `UIGlassEffect.tintColor` unset
    // so the system's own adaptive appearance applies (it adapts opacity and
    // light/dark automatically, especially at small sizes) instead of a flat
    // forced color.
    let tintARGB = (args?["tint"] as? NSNumber)?.int64Value
    let styleName = (args?["style"] as? String) ?? "regular"
    let interactive = (args?["interactive"] as? NSNumber)?.boolValue ?? true

    let effect: UIVisualEffect
    if #available(iOS 26.0, *) {
      let glass = UIGlassEffect(style: styleName == "clear" ? .clear : .regular)
      glass.isInteractive = interactive
      if let argb = tintARGB {
        glass.tintColor = GlassPlatformView.color(fromARGB: argb)
      }
      effect = glass
    } else {
      effect = UIBlurEffect(style: .systemUltraThinMaterial)
    }

    self.styleName = styleName
    self.interactive = interactive

    let effectView = UIVisualEffectView(effect: effect)
    effectView.frame = CGRect(origin: .zero, size: frame.size)
    effectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

    // Every shape we use (the nav bar pill, the circular icon buttons) is a
    // capsule. This must be set on the effect view itself so the glass
    // renders its edge lensing/highlight for the real shape — clipping it
    // externally (e.g. Flutter's ClipRRect) only crops the rendered output
    // of what the glass thinks is a plain rectangle, so the characteristic
    // edge highlight never appears.
    if #available(iOS 26.0, *) {
      effectView.cornerConfiguration = .capsule()
    }

    self.effectView = effectView

    container = GlassTouchContainer(frame: frame)
    container.backgroundColor = .clear
    container.addSubview(effectView)
    // Hung inside the material, not beside it: `isInteractive` responds to
    // touches the effect view is part of delivering.
    container.host = effectView.contentView

    super.init()

    container.onPress = { [weak self] index, pressed in
      self?.channel.invokeMethod("pressed", arguments: ["index": index, "pressed": pressed])
    }
    container.onTap = { [weak self] index in
      self?.channel.invokeMethod("tapped", arguments: ["index": index])
    }
    container.regions = GlassPlatformView.regions(from: args?["regions"])

    // The whole point of `UIGlassEffect` is that it adapts — and what it adapts
    // to is the trait collection, i.e. the *device's* light/dark setting.
    // Aporah's dark mode is its own switch in Settings, so left alone this
    // renders a light frosted header over a dark app whenever the two disagree.
    // Same contract as the tab bar, search field and switch: Dart passes the
    // app's brightness at creation and pushes changes over "setBrightness".
    container.overrideUserInterfaceStyle = (args?["dark"] as? Bool == true) ? .dark : .light

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterMethodNotImplemented)
        return
      }
      let args = call.arguments as? [String: Any]
      switch call.method {
      case "setBrightness":
        let dark = args?["dark"] as? Bool ?? false
        self.container.overrideUserInterfaceStyle = dark ? .dark : .light
        result(nil)
      case "setTint":
        // A `UiKitView` never re-reads its creationParams, so a control whose
        // tint depends on state — the accent that a sheet's save button gains
        // the moment its name field is filled in — has to be told here or it
        // keeps the colour it was created with.
        self.applyTint(argb: (args?["tint"] as? NSNumber)?.int64Value)
        result(nil)
      case "setRegions":
        // Same contract as "setTint", for the same reason: a group's segment
        // count is a build-time value on the Dart side and the view was made
        // once. Fractions, so a resize needs no message at all.
        self.container.regions = GlassPlatformView.regions(from: args?["regions"])
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func view() -> UIView {
    return container
  }

  /// Swaps in a fresh effect carrying `argb` (or none, for the material's own
  /// adaptive appearance). Animated, because the accent arriving on a save
  /// button the instant a character is typed reads as a flicker otherwise.
  private func applyTint(argb: Int64?) {
    guard #available(iOS 26.0, *) else { return }
    let glass = UIGlassEffect(style: styleName == "clear" ? .clear : .regular)
    glass.isInteractive = interactive
    if let argb = argb {
      glass.tintColor = GlassPlatformView.color(fromARGB: argb)
    }
    UIView.animate(withDuration: 0.2) {
      self.effectView.effect = glass
    }
  }

  /// Flat `[x, y, w, h, x, y, w, h, …]` in bounds fractions — one quadruple per
  /// segment. Flat because `StandardMessageCodec` sends a `List<double>` as a
  /// single `Float64List` and a list-of-lists as a boxed array per row.
  private static func regions(from value: Any?) -> [CGRect] {
    guard let flat = (value as? FlutterStandardTypedData)?.data else {
      guard let numbers = value as? [NSNumber] else { return [] }
      return rects(from: numbers.map { CGFloat($0.doubleValue) })
    }
    var doubles = [Double](repeating: 0, count: flat.count / MemoryLayout<Double>.size)
    _ = doubles.withUnsafeMutableBytes { flat.copyBytes(to: $0) }
    return rects(from: doubles.map { CGFloat($0) })
  }

  private static func rects(from values: [CGFloat]) -> [CGRect] {
    stride(from: 0, to: values.count - 3, by: 4).map { i in
      CGRect(x: values[i], y: values[i + 1], width: values[i + 2], height: values[i + 3])
    }
  }

  private static func color(fromARGB value: Int64) -> UIColor {
    let a = CGFloat((value >> 24) & 0xff) / 255.0
    let r = CGFloat((value >> 16) & 0xff) / 255.0
    let g = CGFloat((value >> 8) & 0xff) / 255.0
    let b = CGFloat(value & 0xff) / 255.0
    return UIColor(red: r, green: g, blue: b, alpha: a)
  }
}
