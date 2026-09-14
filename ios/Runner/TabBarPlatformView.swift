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
      // Where UIKit actually put the **Mehr** item, so the shelf can stand on
      // it — see `lastItemFrame`.
      case "getMoreItemFrame":
        result(TabBarPlatformView.lastItemFrame(in: self.tabBar, relativeTo: self.container))
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
      // The interface language is an in-app setting too, so the titles have to
      // be pushed down the same way the theme is. Rebuilding the items would
      // drop the selection, so the existing ones are retitled in place.
      case "setLabels":
        let labels = (call.arguments as? [String: Any])?["labels"] as? [String] ?? []
        if let items = self.tabBar.items {
          for (i, item) in items.enumerated() where i < labels.count {
            item.title = labels[i]
          }
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

  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    guard let index = tabBar.items?.firstIndex(of: item) else { return }
    channel.invokeMethod("tabSelected", arguments: ["index": index])
  }

  private func setSelectedIndex(_ index: Int) {
    guard let items = tabBar.items, index >= 0, index < items.count else { return }
    tabBar.selectedItem = items[index]
  }

  /// The outermost item's frame in the container's own coordinates, or nil.
  ///
  /// The **Mehr** shelf stands a column of Flutter buttons on that item, and a
  /// `UITabBarItem` is a *description*, not a view — there is no public frame to
  /// ask it for. Dividing the bar into five is close enough to grow a menu
  /// bubble out of and visibly wrong for standing a control on: an iOS 26 bar
  /// reports the full display width and then draws its floating glass platter
  /// inset inside those bounds, so the last fifth of what it reported lands to
  /// the right of the item the user is looking at. Mehr is the last tab on both
  /// bars, so the rightmost item view is the one and only one wanted here.
  ///
  /// **It reads and changes nothing** — no `layoutIfNeeded`, no items rebuilt,
  /// no sizing. That is not tidiness, it is the whole design: forcing this bar
  /// to lay itself out before Flutter has given the platform view its real
  /// frame lays five items out in zero width, and a `UITabBarItem`'s title
  /// keeps the width it was first laid out at — which is a bar that looks
  /// perfectly spread reading `Home Ka… Li… Bo… Me…` until a tab is selected.
  /// Left alone, UIKit lays the bar out for the first time when it has its real
  /// frame, and the labels are simply right.
  ///
  /// So it answers nil until there is something to see, and Dart asks at the
  /// moment the item is tapped, by which time the bar has been on screen for as
  /// long as the app has.
  private static func lastItemFrame(in bar: UITabBar, relativeTo container: UIView) -> [String: Any]? {
    // **Two passes, kept apart, and the named one wins outright.** The view
    // UIKit lays out for an item has carried the same class name across every
    // version of the bar — but iOS 26 reworked the bar's insides for Liquid
    // Glass, and a renamed class would find nothing at all here. Failing the
    // name, the shape: an item is a control with a real size, which in a bar of
    // five items and no accessories is only ever one of the five. Mixed, a
    // stray control on the platter could out-rank a real item; apart, the shape
    // pass only speaks when the name pass is silent.
    var named: [CGRect] = []
    var controls: [CGRect] = []
    // The platter the items sit on — the glass capsule on iOS 26, the classic
    // bar background before it. Worth having even when no item view can be
    // found, because it is the band they were laid out in: **this** is the
    // thing an iOS 26 bar insets inside its own bounds, so a fifth of the
    // platter is off by the padding inside it where a fifth of the bar is off
    // by the whole inset. Kept apart from any old glass view — the selection
    // pill has one of its own — so the background wins.
    var background = CGRect.null
    var glass = CGRect.null

    func walk(_ view: UIView) {
      for sub in view.subviews {
        let name = NSStringFromClass(type(of: sub))
        // Not descended into: the label and the image inside an item are not
        // items.
        if name.contains("TabBarButton") || name.contains("TabBarItem") {
          named.append(container.convert(sub.bounds, from: sub))
          continue
        }
        if let control = sub as? UIControl, control.bounds.width > 1, control.bounds.height > 1 {
          controls.append(container.convert(control.bounds, from: control))
          continue
        }
        if name.contains("BarBackground") || name.contains("Platter") {
          background = background.union(container.convert(sub.bounds, from: sub))
        } else if name.contains("Glass") {
          glass = glass.union(container.convert(sub.bounds, from: sub))
        }
        walk(sub)
      }
    }
    walk(bar)

    let frames = named.isEmpty ? controls : named
    let platter = background.isNull ? glass : background
    var found = named.isEmpty ? "shape:\(controls.count)" : "named:\(named.count)"
    var last = frames.max(by: { $0.midX < $1.midX }) ?? .null

    // Neither pass found an item view, so the last resort: the band they were
    // laid out in, split into as many slots as there are items. A guess, and
    // said to be one in `found` — but the alternative is Dart splitting the
    // whole bar, which on an iOS 26 floating capsule is tens of points wrong
    // rather than a few.
    if last.isNull || last.width <= 1, !platter.isNull, platter.width > 1 {
      let count = CGFloat(max(bar.items?.count ?? 0, 1))
      let slot = platter.width / count
      last = CGRect(x: platter.maxX - slot, y: platter.minY, width: slot, height: platter.height)
      found = "platter/\(Int(count))"
    }

    guard !last.isNull, last.width > 1 else { return nil }
    return [
      "x": Double(last.minX),
      "y": Double(last.minY),
      "width": Double(last.width),
      "height": Double(last.height),
      // What answered, so a shelf standing in the wrong place says why from one
      // console line. The difference between "UIKit moved the item" and "we
      // measured something that is not an item" is otherwise invisible from the
      // Dart side.
      "found": found,
      "barWidth": Double(bar.bounds.width),
      "containerWidth": Double(container.bounds.width),
    ]
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
