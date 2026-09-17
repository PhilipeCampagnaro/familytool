import Flutter
import UIKit

/// Factory for the **real** UIKit Liquid Glass button used by
/// `NativeGlassButtons` in Dart (lib/widgets/native_glass_buttons.dart).
/// Registered in AppDelegate under the view type "aporah/glass_buttons".
class GlassButtonPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    return GlassButtonPlatformView(
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

/// The app's own icon glyphs, drawn by UIKit.
///
/// The alternative was SF Symbols, which is what a `UIMenu` row has to take
/// (see the menu section of CLAUDE.md) — but a menu row is a list item and a
/// header button is the *same* glyph the rest of the screen draws. Swapping
/// `plus` for `plus.circle` on the one control at the top of every tab would
/// put two icon families on one screen. So the Phosphor face Flutter already
/// ships as an asset is read straight out of the Flutter bundle with CoreText
/// and rasterised to a **template** image, which lets UIKit tint it and gives
/// it the glass's own vibrancy for free.
///
/// The font is *not* looked up by family name. `pubspec.yaml` calls it
/// `PhosphorRegular`, which is Flutter's name for it and not the PostScript name
/// UIKit would need; the name is read off the file's own descriptor instead, so
/// the two can never drift.
/// A font Flutter ships as an asset, made usable by UIKit.
///
/// Both fonts a native button draws with come from here: the Phosphor face for
/// its glyph and Poppins for its title. Neither is looked up by family name —
/// `pubspec.yaml` calls them `PhosphorRegular` and `Poppins`, which are Flutter's
/// names for them and not the PostScript names UIKit would need. The name is
/// read off each file's own descriptor instead, so the two can never drift.
enum BundledFonts {
  /// One registered PostScript name per asset. Nil if the asset moved, in
  /// which case the caller draws nothing rather than crashing.
  private static var names: [String: String] = [:]

  static func font(asset: String, size: CGFloat) -> UIFont? {
    guard let name = postScriptName(forAsset: asset) else { return nil }
    return UIFont(name: name, size: size)
  }

  private static func postScriptName(forAsset asset: String) -> String? {
    if let cached = names[asset] { return cached }
    let key = FlutterDartProject.lookupKey(forAsset: asset)
    guard let path = Bundle.main.path(forResource: key, ofType: nil) else { return nil }
    let url = URL(fileURLWithPath: path) as CFURL
    guard
      let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url) as? [CTFontDescriptor],
      let descriptor = descriptors.first,
      let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String
    else { return nil }
    // `.process` — this app only, no system-wide side effect.
    CTFontManagerRegisterFontsForURL(url, .process, nil)
    names[asset] = name
    return name
  }
}

enum PhosphorGlyphs {
  /// Rendering a glyph is a text layout plus a bitmap, and a header button
  /// rebuilds whenever its screen does. Keyed on what decides the pixels.
  private static var cache: [String: UIImage] = [:]

  /// The glyph at `codepoint` of `asset` as a square template image `size`
  /// points on a side.
  ///
  /// **Both halves of that pair come from Dart, and they have to.** The two
  /// Phosphor weights do not share a codepoint space — a duotone glyph is a
  /// pair of layers, so `Phosphor-Duotone.ttf` maps 3025 codepoints where
  /// `Phosphor-Regular.ttf` maps 1543, at different positions — so the codepoint
  /// only means anything alongside the file it is a codepoint *in*. Sending an
  /// `AppIcons` constant straight here drew a missing-glyph box in every
  /// button, which is what `flatIcon()` on the Dart side exists to prevent.
  static func image(codepoint: Int, asset: String, size: CGFloat) -> UIImage? {
    let key = "\(asset)/\(codepoint)@\(size)"
    if let cached = cache[key] { return cached }
    guard
      let font = BundledFonts.font(asset: asset, size: size),
      let scalar = UnicodeScalar(codepoint)
    else { return nil }

    let string = String(scalar) as NSString
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
    let textSize = string.size(withAttributes: attributes)
    // A square box: the button centres one image, and glyphs of different
    // widths would otherwise sit on different centre lines inside a capsule.
    let box = CGSize(width: ceil(size), height: ceil(size))
    let image = UIGraphicsImageRenderer(size: box).image { _ in
      string.draw(
        at: CGPoint(x: (box.width - textSize.width) / 2, y: (box.height - textSize.height) / 2),
        withAttributes: attributes
      )
    }.withRenderingMode(.alwaysTemplate)
    cache[key] = image
    return image
  }
}

/// One or more **real** `UIButton`s wearing iOS 26's Liquid Glass
/// configuration — `.glass()`, or `.prominentGlass()` for an accent.
///
/// ## Why this exists beside `GlassPlatformView`
///
/// `GlassPlatformView` embeds the raw material (`UIGlassEffect` on a
/// `UIVisualEffectView`) and is the right thing for a *surface*: the nav bar's
/// backing capsule, the floating pill, the `Mehr` shelf. It is the wrong thing
/// for a **button**, and the header buttons were built out of it — a piece of
/// material with a Flutter glyph laid over it, a Flutter shadow underneath and
/// a Flutter gesture detector on top. That is an app re-implementing a control
/// the system ships, and it showed: no press response the system would
/// recognise, a drop shadow the material then refracted, and a rim that read as
/// painted rather than lensed.
///
/// Apple's guidance for the new design is "prefer system views and controls",
/// and for a button the system control is `UIButton` with a glass
/// configuration. It brings its own material, its own press behaviour, its own
/// shadow, its own metrics and its own accessibility — the same bargain the
/// bottom bar already makes by being a real `UITabBar` and every menu makes by
/// being a real `UIMenu`.
///
/// ## Grouping: one background, several buttons
///
/// A group is **one** `UIGlassEffect` capsule with plain buttons inside its
/// `contentView` — which is what UIKit's own grouped `UIBarButtonItem`s are:
/// image buttons *share* a background with the image buttons beside them.
///
/// It was `UIGlassContainerEffect` first, on the reading that "adjacent glass
/// merges" was the way to build a grouped capsule. It is not. That effect is
/// for glass that comes *apart and back together* — a toolbar that splits as it
/// moves — and at rest, two 50×40 capsules two points apart do not union into a
/// 100×40 one: each keeps its own round ends and the pair renders as a peanut
/// with a pinched waist. (Overlapping them by a full height would close it, at
/// the cost of hit regions that no longer match what is drawn.) The merge was
/// working exactly as designed; it was the wrong effect for a control that
/// never moves.
///
/// The glyphs still sit inside the material's `contentView`, so they get its
/// vibrancy, and each button is still a real `UIButton` with a real highlight,
/// a real tap target and real accessibility. What a grouped segment gives up
/// against a lone button is the material's own per-press lensing, because the
/// glass is the group's rather than the segment's — which is also true of
/// Apple's grouped bar buttons.
/// The platform view's own box. Flutter sizes it directly rather than through
/// Auto Layout, so `layoutSubviews` is the only moment the buttons can learn
/// how wide they are.
final class GlassButtonContainer: UIView {
  var onLayout: (() -> Void)?

  override func layoutSubviews() {
    super.layoutSubviews()
    onLayout?()
  }
}

class GlassButtonPlatformView: NSObject, FlutterPlatformView {
  private let container: GlassButtonContainer
  private let channel: FlutterMethodChannel
  private var buttons: [UIButton] = []

  /// The group's shared glass. Nil for a single button, which carries its own.
  private var glassContainer: UIVisualEffectView?

  /// Whether this is a group. A segment of one is a plain button on borrowed
  /// glass; a lone button is a glass button.
  private var grouped = false

  /// Held so `setItems` can rebuild a configuration without being re-sent the
  /// two numbers that never change under a live view. The defaults mirror
  /// `AppGlyph.button` and `kNavBarSymbolPointSize` on the Dart side; Dart
  /// always sends both, so these only stand in if a param goes missing.
  private var iconSize: CGFloat = 26
  private var symbolSize: CGFloat = 17
  private var symbolWeightName = "medium"

  /// Whether the buttons wear the accent (`.prominentGlass()`) or the plain
  /// material. Held because `setProminent` swaps it on a sheet's save button
  /// the moment its name field stops being empty.
  private var prominent: Bool


  init(frame: CGRect, viewId: Int64, arguments args: [String: Any]?, messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "aporah/glass_buttons_\(viewId)", binaryMessenger: messenger)

    let items = (args?["items"] as? [[String: Any]]) ?? []
    let iconSize = (args?["iconSize"] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 26
    let symbolSize = (args?["symbolSize"] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 17
    self.iconSize = iconSize
    self.symbolSize = symbolSize
    self.symbolWeightName = (args?["symbolWeight"] as? String) ?? "medium"
    let tintARGB = (args?["tint"] as? NSNumber)?.int64Value
    prominent = (args?["prominent"] as? NSNumber)?.boolValue ?? false

    container = GlassButtonContainer(frame: frame)
    container.backgroundColor = .clear

    super.init()

    container.onLayout = { [weak self] in self?.layout() }

    // A group wears one piece of glass and the segments sit on it; a lone
    // button *is* the glass. See the note above the class.
    grouped = items.count > 1
    var host: UIView = container
    if grouped {
      let effectView = UIVisualEffectView(effect: GlassButtonPlatformView.groupEffect())
      effectView.frame = CGRect(origin: .zero, size: frame.size)
      effectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      if #available(iOS 26.0, *) {
        // Set on the effect view itself, so the material renders its edge
        // lensing for the real shape — an external clip only crops the output
        // of what the glass still thinks is a rectangle.
        effectView.cornerConfiguration = .capsule()
      }
      container.addSubview(effectView)
      glassContainer = effectView
      host = effectView.contentView
    }

    for (index, item) in items.enumerated() {
      let button = UIButton(type: .system)
      button.tag = index
      button.configuration = GlassButtonPlatformView.configuration(
        prominent: prominent,
        grouped: grouped,
        codepoint: (item["glyph"] as? NSNumber)?.intValue,
        fontAsset: item["font"] as? String,
        symbol: item["symbol"] as? String,
        iconSize: iconSize,
        symbolSize: symbolSize,
        symbolWeightName: symbolWeightName,
        title: item["title"] as? String,
        titleFont: item["titleFont"] as? String,
        titleSize: (item["titleSize"] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 15,
        titleARGB: (item["titleColor"] as? NSNumber)?.int64Value,
        iconTrailing: (item["iconTrailing"] as? NSNumber)?.boolValue ?? false,
        glyphARGB: (item["glyphColor"] as? NSNumber)?.int64Value,
        dots: item["dots"] as? [String: Any]
      )
      button.accessibilityLabel = item["label"] as? String
      if let argb = tintARGB {
        // Prominent glass takes its fill from the view's tint; a plain glass
        // button, and a segment sitting on the group's glass, take their glyph
        // colour from the same place.
        button.tintColor = GlassButtonPlatformView.color(fromARGB: argb)
      }
      button.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
      host.addSubview(button)
      buttons.append(button)
    }

    // The material derives its appearance from the trait collection, i.e. the
    // *device's* light/dark setting — and Aporah's dark mode is its own switch
    // in Settings. Same contract as the tab bar, the search field, the switch
    // and `GlassPlatformView`: Dart passes the app's brightness at creation and
    // pushes changes over "setBrightness".
    container.overrideUserInterfaceStyle = (args?["dark"] as? Bool == true) ? .dark : .light

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterMethodNotImplemented)
        return
      }
      let args = call.arguments as? [String: Any]
      switch call.method {
      case "setBrightness":
        self.container.overrideUserInterfaceStyle = (args?["dark"] as? Bool == true) ? .dark : .light
        result(nil)
      case "setProminent":
        // A create sheet's save button is plain glass while its name field is
        // empty and accent once it isn't, and a `UiKitView` reads its
        // creationParams exactly once — so the change has to arrive here or
        // typing a title would appear to do nothing.
        self.setProminent((args?["prominent"] as? NSNumber)?.boolValue ?? false)
        result(nil)
      case "setTint":
        let argb = (args?["tint"] as? NSNumber)?.int64Value
        let color = argb.map { GlassButtonPlatformView.color(fromARGB: $0) }
        for button in self.buttons { button.tintColor = color }
        result(nil)
      case "setItems":
        // Everything an item carries, not just its word. A `UiKitView` reads
        // its `creationParams` once, and two of these change under a live
        // view: the label follows the language picked in Settings, and the
        // title's *colour* follows the palette — `AppColors.ink` is near-black
        // in a light app and near-white in a dark one. Baked in at creation,
        // "Fertig" stayed black in a dark app until something tore the view
        // down. One push for both, so they cannot fall out of step.
        self.setItems((args?["items"] as? [[String: Any]]) ?? [])
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func view() -> UIView {
    return container
  }

  /// Laid out by hand rather than by Auto Layout: Flutter owns this view's box
  /// and resizes it directly, so there is one rule — equal widths across
  /// whatever width we were given, with [mergeGap] between.
  private func layout() {
    let bounds = container.bounds
    glassContainer?.frame = CGRect(origin: .zero, size: bounds.size)
    guard !buttons.isEmpty else { return }
    // Equal segments across the capsule, edge to edge. No gap: they are tap
    // targets on one background, not pieces of glass that have to be kept
    // apart — and a gap here would only make the outer glyphs sit off-centre
    // in their halves.
    let width = bounds.width / CGFloat(buttons.count)
    for (index, button) in buttons.enumerated() {
      button.frame = CGRect(x: CGFloat(index) * width, y: 0, width: width, height: bounds.height)
    }
  }

  /// Rebuilds each button from a fresh set of item params. A count that no
  /// longer matches means the Dart side replaced the control rather than
  /// updating it, and Flutter will have given us a new view for that — so this
  /// leaves the old one alone rather than half-applying.
  private func setItems(_ items: [[String: Any]]) {
    guard items.count == buttons.count else { return }
    for (button, item) in zip(buttons, items) {
      button.configuration = GlassButtonPlatformView.configuration(
        prominent: prominent,
        grouped: grouped,
        codepoint: (item["glyph"] as? NSNumber)?.intValue,
        fontAsset: item["font"] as? String,
        symbol: item["symbol"] as? String,
        iconSize: iconSize,
        symbolSize: symbolSize,
        symbolWeightName: symbolWeightName,
        title: item["title"] as? String,
        titleFont: item["titleFont"] as? String,
        titleSize: (item["titleSize"] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 15,
        titleARGB: (item["titleColor"] as? NSNumber)?.int64Value,
        iconTrailing: (item["iconTrailing"] as? NSNumber)?.boolValue ?? false,
        glyphARGB: (item["glyphColor"] as? NSNumber)?.int64Value,
        dots: item["dots"] as? [String: Any]
      )
      button.accessibilityLabel = item["label"] as? String
    }
  }

  private func setProminent(_ value: Bool) {
    guard value != prominent, !grouped else { return }
    prominent = value
    for button in buttons {
      var configuration = GlassButtonPlatformView.glassConfiguration(prominent: prominent, grouped: false)
      configuration.image = button.configuration?.image
      configuration.attributedTitle = button.configuration?.attributedTitle
      configuration.imagePadding = GlassButtonPlatformView.imagePadding
      configuration.imagePlacement = button.configuration?.imagePlacement ?? .leading
      configuration.contentInsets = .zero
      // Animated, because an accent that snaps on the instant a character is
      // typed reads as a flicker rather than as the button waking up.
      UIView.animate(withDuration: 0.2) { button.configuration = configuration }
    }
  }

  /// Gap between a glyph and the word beside it, where a button carries both.
  private static let imagePadding: CGFloat = 7

  /// An SF Symbol at a **type** size, which is the unit symbols are drawn in.
  ///
  /// **`pointSize` is not a box**, and treating it as one is what made the
  /// `Mehr` shelf's glyphs tower over the identical ones on the tab bar
  /// underneath: `kNavRowIconSize` is 28 because that is the em size a
  /// *Phosphor* glyph is drawn at, and an icon font puts well under an em of
  /// ink inside that. A symbol fills its own metrics, so the same 28 came back
  /// as a 35×35 image for `shippingbox` and 40×28 for `creditcard` — measured,
  /// not guessed — before `.semibold` added weight on top.
  ///
  /// So a symbol takes its size in its own unit, and the default is the number
  /// UIKit itself uses. `TabBarPlatformView` passes **no** configuration at
  /// all, so the bar's symbols are drawn at the system default; matching that
  /// number here makes the shelf's glyph the same size as the bar's by
  /// construction rather than by a tuned constant.
  ///
  /// Weight is the one thing that does *not* follow the bar, and is a
  /// parameter for that reason — see `NativeGlassButtons.symbolWeight`.
  private static func symbolImage(_ name: String, pointSize: CGFloat, weight: String) -> UIImage? {
    return UIImage(
      systemName: name,
      withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: symbolWeight(weight))
    )
  }

  private static func symbolWeight(_ name: String) -> UIImage.SymbolWeight {
    switch name {
    case "light": return .light
    case "regular": return .regular
    case "medium": return .medium
    case "semibold": return .semibold
    case "bold": return .bold
    default: return .medium
    }
  }

  private static func configuration(
    prominent: Bool,
    grouped: Bool,
    codepoint: Int?,
    fontAsset: String?,
    symbol: String?,
    iconSize: CGFloat,
    symbolSize: CGFloat,
    symbolWeightName: String,
    title: String?,
    titleFont: String?,
    titleSize: CGFloat,
    titleARGB: Int64?,
    iconTrailing: Bool,
    glyphARGB: Int64?,
    dots: [String: Any]?
  ) -> UIButton.Configuration {
    var configuration = glassConfiguration(prominent: prominent, grouped: grouped)
    if let symbol = symbol {
      // **An SF Symbol where the row it belongs to is already SF.** The `Mehr`
      // shelf stands a finger's width above a real `UITabBar` drawing real
      // symbols, and `navRowIcon` already swaps the Phosphor set out for
      // Apple's there so the two don't read as subtly different boxes. Flutter
      // reaches that set through the `CupertinoIcons` font, which is a package
      // asset with no path this side can load — and it does not need one,
      // because a `UIButton` takes the symbol by name.
      configuration.image = symbolImage(symbol, pointSize: symbolSize, weight: symbolWeightName)
    } else if let codepoint = codepoint, let fontAsset = fontAsset {
      configuration.image = PhosphorGlyphs.image(codepoint: codepoint, asset: fontAsset, size: iconSize)
    }
    // A glyph normally reaches UIKit as a *template* and takes the button's
    // tint. One that has to share its image with something coloured cannot —
    // see `NativeGlassDots` on the Dart side — so it is baked instead.
    if let glyphARGB = glyphARGB, let image = configuration.image {
      configuration.image = image.withTintColor(color(fromARGB: glyphARGB), renderingMode: .alwaysOriginal)
    }
    if let dots = dots {
      configuration.image = dotStack(dots, glyph: configuration.image, glyphTrailing: iconTrailing)
    }
    if let title = title {
      // **The app's own typeface, not the system's.** A native button that
      // said "Fertig" in SF Pro beside a screen set in Poppins would be the
      // one place the app changed voice, which is a worse trade than the one
      // the material is being adopted for. Poppins is a Flutter asset like the
      // icon font, so it is loaded the same way.
      var attributed = AttributedString(title)
      if let font = titleFont.flatMap({ BundledFonts.font(asset: $0, size: titleSize) }) {
        attributed.font = font
      }
      // Its own colour, not the button's tint. On "Heute" and "Rückgängig" the
      // tint is the *accent* and it belongs to the glyph alone — the word beside
      // it is ink, exactly as the Flutter drawing sets it. One `tintColor` for
      // both would repaint the label accent and make the pill read as a filled
      // accent control rather than a neutral one carrying an accent mark.
      if let argb = titleARGB {
        attributed.foregroundColor = color(fromARGB: argb)
      }
      configuration.attributedTitle = attributed
      configuration.imagePadding = imagePadding
      // A dropdown's caret trails the word it opens — Kalender's collapsed
      // calendar filter.
      configuration.imagePlacement = iconTrailing ? .trailing : .leading
    }
    // Flutter has already sized the box this button fills, padding included —
    // see `NativeGlassButtons.sizer`. UIKit's own insets on top of that would
    // squeeze the content or force a minimum the header has not reserved.
    configuration.contentInsets = .zero
    return configuration
  }

  /// The overlap between two dots is cleared out of the image rather than
  /// filled: what shows through it is the glass the button is made of.
  private static let dotGap: CGFloat = 2

  /// A row of overlapping colour dots, with the button's glyph beside them, as
  /// one image — a `UIButton.Configuration` has a single image slot, so the two
  /// travel together or not at all. See `NativeGlassDots` in Dart.
  ///
  /// The result is **not** a template: each dot carries its own colour, and a
  /// template is a single-colour mask.
  private static func dotStack(_ spec: [String: Any], glyph: UIImage?, glyphTrailing: Bool) -> UIImage? {
    let colors = ((spec["colors"] as? [NSNumber]) ?? []).map { color(fromARGB: $0.int64Value) }
    guard !colors.isEmpty else { return glyph }
    let size = (spec["size"] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 11
    let overlap = (spec["overlap"] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 4
    let step = size - overlap
    let dotsWidth = size + step * CGFloat(colors.count - 1)
    let glyphSize = glyph?.size ?? .zero
    let gap: CGFloat = glyph == nil ? 0 : imagePadding
    let box = CGSize(width: dotsWidth + gap + glyphSize.width, height: max(size, glyphSize.height))
    return UIGraphicsImageRenderer(size: box).image { context in
      let originX = glyphTrailing ? 0 : glyphSize.width + gap
      for (index, dot) in colors.enumerated() {
        let rect = CGRect(
          x: originX + step * CGFloat(index),
          y: (box.height - size) / 2,
          width: size,
          height: size
        )
        // Each dot cuts its own edge out of the one it covers, so the two read
        // as two circles rather than as one blob.
        if index > 0 {
          context.cgContext.setBlendMode(.clear)
          context.cgContext.fillEllipse(in: rect.insetBy(dx: -dotGap, dy: -dotGap))
          context.cgContext.setBlendMode(.normal)
        }
        dot.setFill()
        context.cgContext.fillEllipse(in: rect)
      }
      glyph?.draw(
        at: CGPoint(
          x: glyphTrailing ? dotsWidth + gap : 0,
          y: (box.height - glyphSize.height) / 2
        )
      )
    }.withRenderingMode(.alwaysOriginal)
  }

  /// The iOS 26 glass configurations.
  ///
  /// A **grouped** segment gets `.plain()` and no background of its own: the
  /// glass under it belongs to the group, and a glass button on glass would be
  /// the one thing Apple's guidance for this material rules out — glass over
  /// glass. A lone button gets the real thing.
  ///
  /// The pre-26 fallback is only ever reached on a device too old for the
  /// material at all. `.gray()` there, since drawing an imitation by hand is
  /// exactly what this file exists to stop doing.
  private static func glassConfiguration(prominent: Bool, grouped: Bool) -> UIButton.Configuration {
    if grouped { return .plain() }
    if #available(iOS 26.0, *) {
      var configuration = prominent ? UIButton.Configuration.prominentGlass() : UIButton.Configuration.glass()
      // Every glass control in this app is a capsule, and a capsule is what
      // the material renders its edge lensing for.
      configuration.cornerStyle = .capsule
      return configuration
    }
    var configuration = UIButton.Configuration.gray()
    configuration.cornerStyle = .capsule
    return configuration
  }

  /// The material a *group* wears. Never tinted: a forced `tintColor` is only
  /// ever the deliberate accent, and no group in the app is one — a group's
  /// `tint` colours its *glyphs*. So the real glass's own adaptive appearance
  /// applies, which is the rule the rest of the app follows.
  private static func groupEffect() -> UIVisualEffect {
    guard #available(iOS 26.0, *) else { return UIBlurEffect(style: .systemUltraThinMaterial) }
    let glass = UIGlassEffect(style: .regular)
    glass.isInteractive = true
    return glass
  }

  @objc private func tapped(_ sender: UIButton) {
    channel.invokeMethod("tapped", arguments: ["index": sender.tag])
  }

  private static func color(fromARGB value: Int64) -> UIColor {
    let a = CGFloat((value >> 24) & 0xff) / 255.0
    let r = CGFloat((value >> 16) & 0xff) / 255.0
    let g = CGFloat((value >> 8) & 0xff) / 255.0
    let b = CGFloat(value & 0xff) / 255.0
    return UIColor(red: r, green: g, blue: b, alpha: a)
  }
}
