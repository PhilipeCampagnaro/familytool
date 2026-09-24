import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Held onto for the app's lifetime — a channel that goes out of scope stops
  /// answering.
  private var linksChannel: FlutterMethodChannel?
  private var mediaChannel: FlutterMethodChannel?
  private var mapChannel: FlutterMethodChannel?
  private var menuChannel: FlutterMethodChannel?
  private var spendChannel: FlutterMethodChannel?
  private var notificationsChannel: FlutterMethodChannel?
  private var reviewChannel: FlutterMethodChannel?
  private var shareChannel: FlutterMethodChannel?
  private var biometricsChannel: FlutterMethodChannel?
  private var calendarPageChannel: FlutterMethodChannel?
  private let localNotifications = LocalNotifications()
  private let mediaPicker = MediaPicker()
  private let calendarPageBrowser = CalendarPageBrowser()
  private let mapSnapshot = MapSnapshot()
  private let nativeMenu = NativeMenu()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Before launch finishes, or a tap on the notification that launched the
    // app is delivered to nobody.
    localNotifications.install()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "GlassPlatformView") {
      registrar.register(
        GlassPlatformViewFactory(messenger: registrar.messenger()),
        withId: "aporah/glass_view"
      )
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "GlassButtonPlatformView") {
      registrar.register(
        GlassButtonPlatformViewFactory(messenger: registrar.messenger()),
        withId: "aporah/glass_buttons"
      )
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TabBarPlatformView") {
      registrar.register(
        TabBarPlatformViewFactory(messenger: registrar.messenger()),
        withId: "aporah/tab_bar"
      )
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SearchFieldPlatformView") {
      registrar.register(
        SearchFieldPlatformViewFactory(messenger: registrar.messenger()),
        withId: "aporah/search_field"
      )
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SwitchPlatformView") {
      registrar.register(
        SwitchPlatformViewFactory(messenger: registrar.messenger()),
        withId: "aporah/switch"
      )
    }
    // Opening a link in Safari is the one thing Flutter has no built-in for.
    // A handful of lines of UIKit here beats taking on url_launcher (and a pod
    // install) for a single call — see lib/services/external_links.dart.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AporahLinks") {
      let channel = FlutterMethodChannel(name: "aporah/links", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        // Whether the pasteboard holds a link, **without reading it**.
        //
        // `hasURLs` is the whole point of this call: it answers the question
        // from the OS's own index of what was copied, so it does *not* trip
        // the "App möchte einfügen" banner that any real read of the
        // pasteboard trips on iOS 16 and later. That is what lets a button
        // appear only when there is something to paste — asking the same
        // question with `UIPasteboard.general.string` would put the banner in
        // front of the user once per visit to Listen, for a button they had
        // not pressed.
        //
        // The actual read still happens on the Flutter side, on the tap, and
        // still shows the banner once. That one is correct: the user asked.
        if call.method == "hasUrl" {
          result(UIPasteboard.general.hasURLs)
          return
        }
        // The same question plus **which copy this is**.
        //
        // `changeCount` increments every time anything is put on the
        // pasteboard, and reading it costs nothing and shows no banner. It is
        // the only way to tell "they copied a second recipe" from "that same
        // link is still sitting there" without looking at the contents — which
        // is exactly what we are not willing to do to decide whether to offer
        // something.
        //
        // Both values in one call because they are always wanted together and
        // a channel round trip is the expensive half.
        // The link itself. **This one reads, and iOS may put its paste banner
        // up for it** — which is correct here, because the user pressed a
        // button that says "Importieren".
        //
        // `url` before `string`: a pasteboard item written as `public.url`
        // (which is what a share sheet, a "Link kopieren" and `simctl pbcopy`
        // of an address all tend to produce) does not always answer to
        // `.string`, and Flutter's own `Clipboard.getData` asks only for plain
        // text. Asking for both here is the difference between "we could not
        // read the clipboard" and the feature working at all.
        if call.method == "pasteboardUrl" {
          let board = UIPasteboard.general
          result(board.url?.absoluteString ?? board.string)
          return
        }
        if call.method == "pasteboardState" {
          result([
            "hasUrl": UIPasteboard.general.hasURLs,
            "changeCount": UIPasteboard.general.changeCount,
          ])
          return
        }
        guard call.method == "open",
              let args = call.arguments as? [String: Any],
              let raw = args["url"] as? String,
              let url = URL(string: raw)
        else {
          result(FlutterMethodNotImplemented)
          return
        }
        UIApplication.shared.open(url, options: [:]) { opened in result(opened) }
      }
      linksChannel = channel
    }
    // Photo library / camera / Files pickers — see MediaPicker.swift and
    // lib/services/media_picker.dart.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AporahMedia") {
      let channel = FlutterMethodChannel(name: "aporah/media", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { [mediaPicker] call, result in
        mediaPicker.handle(call, result: result)
      }
      mediaChannel = channel
    }
    // CoreLocation + MapKit behind the event-detail sheet's location card —
    // see MapSnapshot.swift and lib/services/map_snapshot.dart.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AporahMap") {
      let channel = FlutterMethodChannel(name: "aporah/map", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { [mapSnapshot] call, result in
        mapSnapshot.handle(call, result: result)
      }
      mapChannel = channel
    }
    // The system's own anchored menu, for the choices offered from inside a
    // sheet — see NativeMenu.swift and lib/services/native_menu.dart.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AporahMenu") {
      let channel = FlutterMethodChannel(name: "aporah/menu", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { [nativeMenu] call, result in
        nativeMenu.handle(call, result: result)
      }
      // Handed the channel too, not just the calls: a menu row that keeps the
      // menu open has to report itself while its own request is still waiting.
      nativeMenu.channel = channel
      menuChannel = channel
    }
    // The Keychain slot the Apple Pay App Intent reads its ingest token out of.
    // Nothing about a *transaction* crosses this channel — the intent posts
    // straight to `spend-ingest` from Swift, because it runs on a locked phone
    // with no Flutter engine to ask. See SpendCapture.swift, SpendAppIntent.swift
    // and lib/services/spend_intent.dart.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AporahSpend") {
      let channel = FlutterMethodChannel(name: "aporah/spend", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        SpendChannel.handle(call, result)
      }
      spendChannel = channel
    }
    // Scheduled, on-device notifications — appointment reminders, the bins the
    // evening before, the morning brief. See LocalNotifications.swift and
    // lib/services/local_notifications.dart.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AporahNotifications") {
      let channel = FlutterMethodChannel(name: "aporah/notifications", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { [localNotifications] call, result in
        localNotifications.handle(call, result: result)
      }
      notificationsChannel = channel
    }
    // The system rating prompt — see AppReview.swift and
    // lib/services/app_review.dart, which decides who is asked and when.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AporahReview") {
      let channel = FlutterMethodChannel(name: "aporah/review", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        AppReview.handle(call, result: result)
      }
      reviewChannel = channel
    }
    // The system share sheet, for a list's invitation link — see
    // ShareSheet.swift and lib/services/share_out.dart.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AporahShare") {
      let channel = FlutterMethodChannel(name: "aporah/share", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        ShareSheet.handle(call, result: result)
      }
      shareChannel = channel
    }
    // The app lock — Face ID, Touch ID or Optic ID, with the passcode behind
    // them. See BiometricLock.swift and lib/state/app_lock_state.dart.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AporahBiometrics") {
      let channel = FlutterMethodChannel(name: "aporah/biometrics", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        BiometricLock.handle(call, result: result)
      }
      biometricsChannel = channel
    }
    // A town's waste-calendar page, opened in the app so its iCal export comes
    // back as a file rather than going to Apple Calendar — see
    // CalendarPageBrowser.swift and lib/services/calendar_page_browser.dart.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AporahCalendarPage") {
      let channel = FlutterMethodChannel(name: "aporah/calendarPage", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { [calendarPageBrowser] call, result in
        calendarPageBrowser.handle(call, result: result)
      }
      calendarPageChannel = channel
    }
  }
}
