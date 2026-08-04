import Flutter
import UIKit

/// Factory for the real system switch used by `NativeSwitch` in Dart
/// (lib/widgets/native_switch.dart). Registered in AppDelegate under the view
/// type "aporah/switch".
class SwitchPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    return SwitchPlatformView(
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

/// An actual `UISwitch`, embedded in the Flutter tree as a platform view —
/// same reasoning as `SearchFieldPlatformView`: Flutter's `CupertinoSwitch` is
/// a hand-drawn copy of the *old* switch, so on iOS 26 it misses the system's
/// Liquid Glass knob and its highlight/press response. The real control is the
/// only way to get the current appearance, and it keeps tracking it across OS
/// releases for free.
///
/// What comes free with the real control and is deliberately not configured
/// here: the Liquid Glass rendering and its press/settle animation,
/// drag-to-toggle with the knob following the finger, the haptic on commit,
/// the system on-tint, Reduce Motion / Increased Contrast / differentiate
/// without color behaviour, and the accessibility traits and value.
///
/// Flutter only ever learns the value: every user-driven change is pushed over
/// a per-view method channel, and Dart pushes state changes back with
/// "setValue" so the control still follows the provider when something else
/// flips it.
class SwitchPlatformView: NSObject, FlutterPlatformView {
  private let container: UIView
  private let control = UISwitch(frame: .zero)
  private let channel: FlutterMethodChannel

  init(frame: CGRect, viewId: Int64, arguments args: [String: Any]?, messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "aporah/switch_\(viewId)", binaryMessenger: messenger)
    container = UIView(frame: frame)

    super.init()

    container.backgroundColor = .clear
    // Pinned to the *app's* appearance, not the device's: Aporah's dark mode is
    // its own setting (the "Dunkelmodus" switch in Settings), so a light app on
    // a dark phone must not draw a dark off-state track — and vice versa. Dart
    // passes it at creation and pushes changes over "setBrightness".
    container.overrideUserInterfaceStyle = (args?["dark"] as? Bool == true) ? .dark : .light

    control.isOn = args?["value"] as? Bool ?? false
    // No `onTintColor` override on purpose: the system green *is* the native
    // look, and on iOS 26 the on-state track is a material rather than a flat
    // fill, which a forced color would flatten.
    control.addTarget(self, action: #selector(valueChanged), for: .valueChanged)

    control.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(control)
    // Centered rather than pinned: the control has one fixed intrinsic size,
    // so stretching it to the container's edges would fight its own layout if
    // Dart ever gives it a slightly different box.
    NSLayoutConstraint.activate([
      control.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      control.centerYAnchor.constraint(equalTo: container.centerYAnchor),
    ])

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      switch call.method {
      // UIKit's metrics decide the size rather than a constant in Dart that
      // would drift with the OS version.
      case "getIntrinsicSize":
        let fitted = self.control.intrinsicContentSize
        let width = fitted.width.isFinite && fitted.width > 0 ? fitted.width : 51
        let height = fitted.height.isFinite && fitted.height > 0 ? fitted.height : 31
        result(["width": Double(width), "height": Double(height)])
      // Animated so a change coming from elsewhere in the app reads as the
      // same control moving, not as a repaint.
      // Aporah's theme is an in-app setting, so the embedded control has to be
      // told when it flips; there's no device-appearance change to observe.
      case "setBrightness":
        let dark = (call.arguments as? [String: Any])?["dark"] as? Bool ?? false
        self.container.overrideUserInterfaceStyle = dark ? .dark : .light
        result(nil)
      case "setValue":
        let value = (call.arguments as? [String: Any])?["value"] as? Bool ?? false
        if self.control.isOn != value {
          self.control.setOn(value, animated: true)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func view() -> UIView {
    return container
  }

  @objc private func valueChanged() {
    channel.invokeMethod("valueChanged", arguments: ["value": control.isOn])
  }
}
