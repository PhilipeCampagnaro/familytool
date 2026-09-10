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
  private let mediaPicker = MediaPicker()
  private let mapSnapshot = MapSnapshot()
  private let nativeMenu = NativeMenu()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
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
      menuChannel = channel
    }
  }
}
