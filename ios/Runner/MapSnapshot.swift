import CoreLocation
import Flutter
import MapKit
import UIKit

/// The real map behind the event-detail sheet's location card, and the
/// as-you-type place search behind the event form's "Ort" field: CoreLocation
/// turns the event's free-text place into a coordinate, MapKit renders a still
/// image of it and completes what is being typed.
///
/// All of it already ships with the device — no API key, no tile server, no
/// pod, and nothing about where a family is going leaves the phone. Same trade
/// as the native tab bar and the media picker: a little UIKit instead of a
/// plugin. See lib/services/map_snapshot.dart for the Flutter side.
final class MapSnapshot: NSObject {
  /// Geocoding is rate-limited per app by Apple, and a household opens the same
  /// three or four places over and over. Definitive misses are remembered too
  /// (as `.some(nil)`), so a hall the geocoder simply doesn't know costs one
  /// request per launch rather than one per tap. A *transient* failure — no
  /// network, a throttle — is deliberately not remembered, so the next open
  /// tries again.
  private var places: [String: CLLocationCoordinate2D?] = [:]

  private let search = PlaceSearch()

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "snapshot":
      snapshot(call, result: result)
    case "search":
      complete(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Completing a typed place

  /// Answers the "Ort" field with what MapKit thinks is being typed.
  ///
  /// `near` is the household's own address, biasing the results towards the
  /// town the family lives in — without it, "Rossmann" is a chain with two
  /// thousand branches and the first one offered is nowhere near them. It is
  /// resolved through the same cache the snapshot uses, so the bias costs one
  /// geocode per launch rather than one per keystroke.
  private func complete(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let query = args["query"] as? String
    else {
      result(FlutterMethodNotImplemented)
      return
    }
    let near = (args["near"] as? String) ?? ""
    if near.isEmpty {
      search.suggest(query, near: nil, completion: result)
      return
    }
    resolve(near) { [search] coordinate in
      search.suggest(query, near: coordinate, completion: result)
    }
  }

  // MARK: - Snapshotting

  private func snapshot(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let query = args["query"] as? String,
          let width = args["width"] as? Double,
          let height = args["height"] as? Double
    else {
      result(FlutterMethodNotImplemented)
      return
    }
    let scale = args["scale"] as? Double ?? 2
    let dark = args["dark"] as? Bool ?? false
    let meters = args["meters"] as? Double ?? 700

    resolve(query) { [weak self] coordinate in
      guard let self, let coordinate else {
        result(nil)
        return
      }
      self.render(
        coordinate: coordinate, width: width, height: height,
        scale: scale, dark: dark, meters: meters
      ) { data in
        guard let data else {
          result(nil)
          return
        }
        result([
          "image": FlutterStandardTypedData(bytes: data),
          "latitude": coordinate.latitude,
          "longitude": coordinate.longitude,
        ])
      }
    }
  }

  // MARK: - Geocoding

  private func resolve(_ query: String, completion: @escaping (CLLocationCoordinate2D?) -> Void) {
    let key = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if key.isEmpty {
      completion(nil)
      return
    }
    if let cached = places[key] {
      completion(cached)
      return
    }

    // A fresh geocoder per request, captured by its own completion block: one
    // CLGeocoder handles a single request at a time and cancels the previous
    // one if asked again, which would drop the map of whichever event the user
    // opened first.
    let geocoder = CLGeocoder()
    geocoder.geocodeAddressString(query) { [weak self] placemarks, error in
      let coordinate = placemarks?.first?.location?.coordinate
      if let self {
        // Only a real "there is no such place" is cached. Everything else
        // (offline, throttled, cancelled) stays unknown so it can be retried.
        let definitive = (error as? CLError)?.code == .geocodeFoundNoResult
        if coordinate != nil || definitive {
          self.places[key] = coordinate
        }
      }
      DispatchQueue.main.async { completion(coordinate) }
    }
  }

  // MARK: - Rendering

  private func render(
    coordinate: CLLocationCoordinate2D,
    width: Double, height: Double, scale: Double, dark: Bool, meters: Double,
    completion: @escaping (Data?) -> Void
  ) {
    let options = MKMapSnapshotter.Options()
    options.region = MKCoordinateRegion(
      center: coordinate, latitudinalMeters: meters, longitudinalMeters: meters
    )
    options.size = CGSize(width: width, height: height)
    options.scale = CGFloat(scale)
    // Maps follows the app's own light/dark setting rather than the system's —
    // the setting is in Aporah's Settings, and a light map in a dark sheet is
    // the one thing on the screen still glowing.
    options.traitCollection = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)

    MKMapSnapshotter(options: options).start(with: .global(qos: .userInitiated)) { snapshot, _ in
      // JPEG, not PNG: the card is opaque and its corners are clipped on the
      // Flutter side, so there is no transparency to keep — and a @3x map is
      // several times smaller this way.
      let data = snapshot?.image.jpegData(compressionQuality: 0.9)
      DispatchQueue.main.async { completion(data) }
    }
  }
}

/// The suggestions under the event form's "Ort" field.
///
/// `MKLocalSearchCompleter` rather than `MKLocalSearch`: it is the API built for
/// a field being typed into — cheap, incremental, and it answers with both
/// addresses and points of interest, which is the whole point here. A family
/// adding an appointment types "Rossmann" or "Aldi" far more often than they
/// type a street, and a geocoder alone would find neither.
final class PlaceSearch: NSObject, MKLocalSearchCompleterDelegate {
  private let completer = MKLocalSearchCompleter()

  /// The Flutter call waiting for an answer. The completer is a delegate rather
  /// than a completion handler, so the reply has to be parked here — and a
  /// method-channel call must be answered **exactly once**, which is why a
  /// superseded one is closed out with an empty list before it is replaced.
  private var pending: FlutterResult?

  /// The fragment [pending] was asked for, with what it produced. Typing back to
  /// a query that was already answered (a backspace) is common, and the
  /// completer does not necessarily re-fire for a fragment it has already seen —
  /// so a repeat is answered from here instead of hanging.
  private var fragment = ""
  private var last: [[String: String]]?

  override init() {
    super.init()
    completer.delegate = self
    completer.resultTypes = [.address, .pointOfInterest]
  }

  func suggest(
    _ query: String,
    near: CLLocationCoordinate2D?,
    completion: @escaping FlutterResult
  ) {
    let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty {
      pending?([])
      pending = nil
      fragment = ""
      last = nil
      completion([])
      return
    }

    // Set before the fragment: the completer reads the region when the query
    // changes, and a bias applied afterwards would only reach the next keystroke.
    if let near {
      completer.region = MKCoordinateRegion(
        center: near, latitudinalMeters: 60_000, longitudinalMeters: 60_000
      )
    }
    if text == fragment, let last {
      completion(last)
      return
    }

    pending?([])
    pending = completion
    fragment = text
    last = nil
    completer.queryFragment = text
  }

  // MARK: - MKLocalSearchCompleterDelegate

  func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
    // Six: enough that the right branch of a chain is usually among them,
    // few enough that the list does not push the rest of the form off screen
    // with the keyboard up.
    let rows: [[String: String]] = completer.results.prefix(6).compactMap { row -> [String: String]? in
      let title = row.title.trimmingCharacters(in: .whitespacesAndNewlines)
      if title.isEmpty { return nil }
      return [
        "title": title,
        "subtitle": row.subtitle.trimmingCharacters(in: .whitespacesAndNewlines),
      ]
    }
    last = rows
    answer(rows)
  }

  func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
    // Offline, throttled, or a fragment MapKit refuses. Nothing is cached, so
    // the next keystroke asks again; the field simply shows no list.
    answer([])
  }

  /// The completer keeps updating for a fragment after the first answer. Only
  /// the first update replies — the rest land here with nothing waiting, and are
  /// kept in [last] for a repeat of the same query.
  private func answer(_ rows: [[String: String]]) {
    guard let pending else { return }
    self.pending = nil
    pending(rows)
  }
}
