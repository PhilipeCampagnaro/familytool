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

/// Wraps a `UIVisualEffectView` configured with iOS 26's real `UIGlassEffect`
/// material. On earlier iOS versions (no `UIGlassEffect` symbol) it falls
/// back to a system blur so the app still runs, but the Dart side should
/// prefer the pure-Flutter approximation there instead of this view.
///
/// `isUserInteractionEnabled` is kept false so this purely-visual background
/// never intercepts touches meant for the Flutter gesture detector layered on
/// top of it.
class GlassPlatformView: NSObject, FlutterPlatformView {
  private let container: UIView
  private let channel: FlutterMethodChannel

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

    container = UIView(frame: frame)
    container.backgroundColor = .clear
    container.isUserInteractionEnabled = false
    container.addSubview(effectView)

    super.init()

    // The whole point of `UIGlassEffect` is that it adapts — and what it adapts
    // to is the trait collection, i.e. the *device's* light/dark setting.
    // Aporah's dark mode is its own switch in Settings, so left alone this
    // renders a light frosted header over a dark app whenever the two disagree.
    // Same contract as the tab bar, search field and switch: Dart passes the
    // app's brightness at creation and pushes changes over "setBrightness".
    container.overrideUserInterfaceStyle = (args?["dark"] as? Bool == true) ? .dark : .light

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self, call.method == "setBrightness" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let dark = (call.arguments as? [String: Any])?["dark"] as? Bool ?? false
      self.container.overrideUserInterfaceStyle = dark ? .dark : .light
      result(nil)
    }
  }

  func view() -> UIView {
    return container
  }

  private static func color(fromARGB value: Int64) -> UIColor {
    let a = CGFloat((value >> 24) & 0xff) / 255.0
    let r = CGFloat((value >> 16) & 0xff) / 255.0
    let g = CGFloat((value >> 8) & 0xff) / 255.0
    let b = CGFloat(value & 0xff) / 255.0
    return UIColor(red: r, green: g, blue: b, alpha: a)
  }
}
