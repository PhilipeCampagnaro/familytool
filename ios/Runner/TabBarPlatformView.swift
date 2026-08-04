import Flutter
import UIKit

/// Factory for the real system tab bar used by `NativeTabBar` in Dart
/// (lib/widgets/native_tab_bar.dart). Registered in AppDelegate under the view
/// type "aporah/tab_bar".
class TabBarPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    return TabBarPlatformView(
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

/// An actual `UITabBar`, embedded in the Flutter tree as a platform view.
///
/// The point is to get everything Flutter can't draw: on iOS 26 UIKit renders
/// this as the floating Liquid Glass bar — the capsule background, the
/// selection pill that slides between tabs, the specular shimmer under a
/// finger, the SF Symbol bounce, the automatic light/dark and accessibility
/// behaviour. None of that is configured here; it comes free with the real
/// control. On iOS 25 and earlier the same bar renders in the classic
/// translucent style.
///
/// Unlike `GlassPlatformView` this view *must* take touches — taps are handled
/// by UIKit and reported back over a per-view method channel, so Flutter only
/// learns which tab was picked.
class TabBarPlatformView: NSObject, FlutterPlatformView, UITabBarDelegate {
  private let container: UIView
  private let tabBar = UITabBar(frame: .zero)
  private let channel: FlutterMethodChannel

  init(frame: CGRect, viewId: Int64, arguments args: [String: Any]?, messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "aporah/tab_bar_\(viewId)", binaryMessenger: messenger)
    container = UIView(frame: frame)

    super.init()

    let labels = (args?["labels"] as? [String]) ?? []
    let symbols = (args?["symbols"] as? [String]) ?? []
    let selectedSymbols = (args?["selectedSymbols"] as? [String]) ?? []
    let selectedIndex = (args?["selectedIndex"] as? NSNumber)?.intValue ?? 0

    container.backgroundColor = .clear
    // Pinned to the *app's* appearance, not the device's: Aporah's dark mode is
    // its own setting (the "Dunkelmodus" switch in Settings), so a light app on
    // a dark phone must not draw dark system chrome — and vice versa. Dart
    // passes it at creation and pushes changes over "setBrightness".
    container.overrideUserInterfaceStyle = (args?["dark"] as? Bool == true) ? .dark : .light

    // `configureWithDefaultBackground` is what opts the bar into the system
    // material — the Liquid Glass on iOS 26, the blur before it. Configuring a
    // custom background instead would opt out of both.
    let appearance = UITabBarAppearance()
    appearance.configureWithDefaultBackground()
    tabBar.standardAppearance = appearance
    if #available(iOS 15.0, *) {
      tabBar.scrollEdgeAppearance = appearance
    }

    if let tint = (args?["tint"] as? NSNumber)?.int64Value {
      tabBar.tintColor = TabBarPlatformView.color(fromARGB: tint)
    }
    if let unselected = (args?["unselectedTint"] as? NSNumber)?.int64Value {
      tabBar.unselectedItemTintColor = TabBarPlatformView.color(fromARGB: unselected)
    }

    tabBar.delegate = self
    tabBar.items = TabBarPlatformView.items(labels: labels, symbols: symbols, selectedSymbols: selectedSymbols)
    setSelectedIndex(selectedIndex)

    tabBar.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(tabBar)
    NSLayoutConstraint.activate([
      tabBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      tabBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      tabBar.topAnchor.constraint(equalTo: container.topAnchor),
      tabBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      switch call.method {
      // The bar sizes itself and Dart lays the platform view out to match, so
      // UIKit's geometry decides how big the bar is rather than us guessing.
      //
      // Measured against the width we were actually given, never an unbounded
      // one — `sizeThatFits` is free to hand back whatever width it was asked
      // to fit, and a `greatestFiniteMagnitude` coming back through the
      // channel would blow up Flutter's layout. A bar that wants the full
      // width reports it (the iOS 26 glass platter is then drawn inset inside
      // those bounds); one that wants to be narrower — a capsule sized to its
      // items — reports that instead, and Dart centers it.
      case "getIntrinsicSize":
        let available = self.container.bounds.width > 0
          ? self.container.bounds.width
          : UIScreen.main.bounds.width
        let fitted = self.tabBar.sizeThatFits(CGSize(width: available, height: .greatestFiniteMagnitude))
        let width = fitted.width.isFinite && fitted.width > 0 ? min(fitted.width, available) : available
        let height = fitted.height.isFinite && fitted.height > 0 ? fitted.height : 49
        result(["width": Double(width), "height": Double(height)])
      // Aporah's theme is an in-app setting, so the embedded control has to be
      // told when it flips; there's no device-appearance change to observe.
      case "setBrightness":
        let dark = (call.arguments as? [String: Any])?["dark"] as? Bool ?? false
        self.container.overrideUserInterfaceStyle = dark ? .dark : .light
        result(nil)
      case "setSelectedIndex":
        let index = (call.arguments as? [String: Any]).flatMap { ($0["index"] as? NSNumber)?.intValue }
        self.setSelectedIndex(index ?? 0)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func view() -> UIView {
    return container
  }

  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    guard let index = tabBar.items?.firstIndex(of: item) else { return }
    channel.invokeMethod("tabSelected", arguments: ["index": index])
  }

  private func setSelectedIndex(_ index: Int) {
    guard let items = tabBar.items, index >= 0, index < items.count else { return }
    tabBar.selectedItem = items[index]
  }

  private static func items(labels: [String], symbols: [String], selectedSymbols: [String]) -> [UITabBarItem] {
    let count = max(labels.count, symbols.count)
    return (0..<count).map { i in
      let image = i < symbols.count ? UIImage(systemName: symbols[i]) : nil
      let selected = i < selectedSymbols.count ? UIImage(systemName: selectedSymbols[i]) : nil
      let item = UITabBarItem(
        title: i < labels.count ? labels[i] : nil,
        image: image,
        selectedImage: selected ?? image
      )
      item.tag = i
      return item
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
