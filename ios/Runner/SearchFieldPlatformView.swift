import Flutter
import UIKit

/// Factory for the real system search control used by `NativeSearchField` in
/// Dart (lib/widgets/native_search_field.dart). Registered in AppDelegate under
/// the view type "aporah/search_field".
class SearchFieldPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    return SearchFieldPlatformView(
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

/// An actual system search control, embedded in the Flutter tree as a platform
/// view — same reasoning as `TabBarPlatformView`: the behaviour the app wants is
/// the system control's, not something worth reimplementing.
///
/// Two shapes, chosen by the "style" creation param:
///
/// - `bar`: a whole `UISearchBar`. It brings its own Cancel button, which
///   animates in beside the contracting field while editing, and it decides its
///   own height (Dart asks for it via `getIntrinsicSize`). Used for the
///   standalone search of a page.
/// - `field`: just the `UISearchTextField` that lives inside that bar, sized to
///   whatever height Flutter lays it out at. Used in the screen headers, where a
///   52pt bar doesn't fit the title row and the way out is a glass X drawn by
///   Flutter beside it, so the Cancel button would be a second one.
///
/// What comes free with the real control either way: the magnifier glyph and its
/// focus transition, the clear button, the keyboard's search return key,
/// Scribble/dictation, and the whole accessibility and Dynamic Type story. On
/// iOS 26 it's rendered in the system's Liquid Glass style, on older releases in
/// the classic one.
///
/// Flutter only ever learns the query: every text change is pushed over a
/// per-view method channel and the Dart side filters its own content.
class SearchFieldPlatformView: NSObject, FlutterPlatformView, UISearchBarDelegate {
  private let container: UIView
  private let channel: FlutterMethodChannel

  /// Exactly one of these is non-nil — see the class docs.
  private let searchBar: UISearchBar?
  private let searchField: UISearchTextField?

  init(frame: CGRect, viewId: Int64, arguments args: [String: Any]?, messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "aporah/search_field_\(viewId)", binaryMessenger: messenger)
    container = UIView(frame: frame)

    let placeholder = args?["placeholder"] as? String
    let asField = (args?["style"] as? String) == "field"
    searchBar = asField ? nil : UISearchBar(frame: .zero)
    searchField = asField ? UISearchTextField(frame: .zero) : nil

    super.init()

    container.backgroundColor = .clear
    // Pinned to the *app's* appearance, not the device's: Aporah's dark mode is
    // its own setting (the "Dunkelmodus" switch in Settings), so a light app on
    // a dark phone must not draw dark system chrome — and vice versa. Dart
    // passes it at creation and pushes changes over "setBrightness".
    container.overrideUserInterfaceStyle = (args?["dark"] as? Bool == true) ? .dark : .light

    // Parenthesised so `map` runs on the Optional rather than being read as a
    // further link in the optional chain (which would try to call it on Int64).
    let tint = ((args?["tint"] as? NSNumber)?.int64Value).map { SearchFieldPlatformView.color(fromARGB: $0) }

    if let searchBar = searchBar {
      searchBar.placeholder = placeholder
      // `.minimal` drops the bar's own opaque chrome so only the rounded field
      // is drawn — it sits on the app's own surface, which is already providing
      // the background a default-style bar would paint over.
      searchBar.searchBarStyle = .minimal
      searchBar.backgroundColor = .clear
      searchBar.isTranslucent = true
      searchBar.autocapitalizationType = .none
      searchBar.autocorrectionType = .no
      searchBar.returnKeyType = .search
      searchBar.enablesReturnKeyAutomatically = false
      // No clear button inside the field: the bar already reveals a Cancel/X
      // beside it while editing, and UIKit's own clear would put a second X in
      // the same row the moment you type.
      searchBar.searchTextField.clearButtonMode = .never
      if let tint = tint { searchBar.tintColor = tint }
      searchBar.delegate = self
      pin(searchBar)
    }

    if let searchField = searchField {
      searchField.placeholder = placeholder
      searchField.autocapitalizationType = .none
      searchField.autocorrectionType = .no
      searchField.returnKeyType = .search
      // Same as the bar: the glass X Flutter draws beside this field is the one
      // X in the row, so UIKit mustn't add its own once there's text.
      searchField.clearButtonMode = .never
      if let tint = tint { searchField.tintColor = tint }
      searchField.addTarget(self, action: #selector(fieldTextChanged), for: .editingChanged)
      searchField.addTarget(self, action: #selector(fieldReturned), for: .editingDidEndOnExit)
      pin(searchField)
    }

    if args?["autofocus"] as? Bool == true {
      // Next runloop turn: at init the view isn't in a window yet, and
      // `becomeFirstResponder` on a view without one is a no-op.
      DispatchQueue.main.async { [weak self] in
        self?.focus()
      }
    }

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      switch call.method {
      // The bar sizes itself and Dart lays the platform view out to match, so
      // UIKit's metrics decide the height rather than a constant in Dart that
      // would drift with the OS version or the user's text size.
      //
      // Measured against the width we were actually given, never an unbounded
      // one — `sizeThatFits` may hand back whatever width it was asked to fit,
      // and a `greatestFiniteMagnitude` coming back through the channel would
      // blow up Flutter's layout.
      case "getIntrinsicSize":
        let available = self.container.bounds.width > 0
          ? self.container.bounds.width
          : UIScreen.main.bounds.width
        let control: UIView = self.searchBar ?? self.searchField!
        let fitted = control.sizeThatFits(CGSize(width: available, height: .greatestFiniteMagnitude))
        let width = fitted.width.isFinite && fitted.width > 0 ? min(fitted.width, available) : available
        let height = fitted.height.isFinite && fitted.height > 0 ? fitted.height : 52
        result(["width": Double(width), "height": Double(height)])
      // Aporah's theme is an in-app setting, so the embedded control has to be
      // told when it flips; there's no device-appearance change to observe.
      case "setBrightness":
        let dark = (call.arguments as? [String: Any])?["dark"] as? Bool ?? false
        self.container.overrideUserInterfaceStyle = dark ? .dark : .light
        result(nil)
      // The interface language is an in-app setting too, so the placeholder has
      // to be pushed down the same way the theme is — a Settings page left
      // mounted behind the language picker would otherwise keep the old one.
      case "setPlaceholder":
        let placeholder = (call.arguments as? [String: Any])?["placeholder"] as? String
        self.searchBar?.placeholder = placeholder
        self.searchField?.placeholder = placeholder
        result(nil)
      case "focus":
        self.focus()
        result(nil)
      case "clear":
        self.searchBar?.text = ""
        self.searchBar?.setShowsCancelButton(false, animated: true)
        self.searchField?.text = ""
        self.resignFirstResponder()
        self.channel.invokeMethod("textChanged", arguments: ["text": ""])
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func view() -> UIView {
    return container
  }

  private func pin(_ control: UIView) {
    control.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(control)
    NSLayoutConstraint.activate([
      control.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      control.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      control.topAnchor.constraint(equalTo: container.topAnchor),
      control.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
  }

  private func focus() {
    let control: UIView? = searchBar ?? searchField
    control?.becomeFirstResponder()
  }

  private func resignFirstResponder() {
    searchBar?.resignFirstResponder()
    searchField?.resignFirstResponder()
  }

  // MARK: - UISearchTextField

  @objc private func fieldTextChanged(_ sender: UITextField) {
    channel.invokeMethod("textChanged", arguments: ["text": sender.text ?? ""])
  }

  @objc private func fieldReturned(_ sender: UITextField) {
    sender.resignFirstResponder()
  }

  // MARK: - UISearchBarDelegate

  func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
    channel.invokeMethod("textChanged", arguments: ["text": searchText])
  }

  /// Showing the cancel control only while editing is what produces the
  /// contract-and-reveal the design asks for: the field animates narrower and
  /// the system's cancel/X appears beside it. Both sides of that are UIKit's
  /// animation, driven by this one call.
  func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
    searchBar.setShowsCancelButton(true, animated: true)
  }

  func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
    searchBar.setShowsCancelButton(false, animated: true)
  }

  func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
    searchBar.text = ""
    searchBar.setShowsCancelButton(false, animated: true)
    searchBar.resignFirstResponder()
    channel.invokeMethod("textChanged", arguments: ["text": ""])
  }

  func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
    searchBar.resignFirstResponder()
  }

  private static func color(fromARGB value: Int64) -> UIColor {
    let a = CGFloat((value >> 24) & 0xff) / 255.0
    let r = CGFloat((value >> 16) & 0xff) / 255.0
    let g = CGFloat((value >> 8) & 0xff) / 255.0
    let b = CGFloat(value & 0xff) / 255.0
    return UIColor(red: r, green: g, blue: b, alpha: a)
  }
}
