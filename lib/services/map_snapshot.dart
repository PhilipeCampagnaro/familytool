import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A real map of a place, rendered by the device — and the search behind the
/// event form's location field.
///
/// The native side is `ios/Runner/MapSnapshot.swift`: CoreLocation geocodes the
/// event's free-text location, MapKit renders a still image of it and completes
/// what is being typed into it. No key, no tile server, no plugin — and no
/// address of a family's leaves the phone. Off iOS there is no handler, so this
/// answers null and the sheet simply shows no map, the same trade the native tab
/// bar, switch and media picker make.
const _channel = MethodChannel('aporah/map');

/// One line of the location field's suggestion list.
///
/// [name] is a business or a street ("Rossmann", "Hauptstraße 5"), [address] the
/// rest of where it is. They are kept apart because the row shows them
/// differently, and joined again only when one is picked.
class PlaceSuggestion {
  final String name;
  final String address;

  const PlaceSuggestion({required this.name, required this.address});

  /// What goes into the event's `loc`, and what [mapSnapshot] will later be
  /// asked to geocode — so it has to be the whole thing, not just the shop name.
  String get value => address.isEmpty ? name : '$name, $address';
}

/// Places matching [query], as MapKit completes it — **businesses as well as
/// addresses**, which is what an appointment usually needs.
///
/// [near] is the household's own address, used to bias the results towards the
/// town the family lives in; a chain like Rossmann or Aldi otherwise answers
/// with whichever branch MapKit reaches for first. An empty list is the ordinary
/// answer for "nothing matched", for a platform without the handler, and for
/// every failure — the field keeps working as free text either way.
Future<List<PlaceSuggestion>> searchPlaces({required String query, String? near}) async {
  final text = query.trim();
  if (text.isEmpty) return const [];
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return const [];

  try {
    final rows = await _channel.invokeListMethod<Map<Object?, Object?>>('search', {
      'query': text,
      'near': near?.trim() ?? '',
    });
    return [
      for (final row in rows ?? const <Map<Object?, Object?>>[])
        PlaceSuggestion(
          name: row['title'] as String? ?? '',
          address: row['subtitle'] as String? ?? '',
        ),
    ];
  } on PlatformException {
    return const [];
  } on MissingPluginException {
    return const [];
  }
}

/// What came back for one place: the picture, and where it turned out to be.
///
/// The coordinates are the half the route menu needs — handing Waze or Google
/// Maps a point rather than the words "Turnhalle" is the difference between
/// navigation starting and a search screen opening.
class MapView {
  final Uint8List image;
  final double latitude;
  final double longitude;

  const MapView({required this.image, required this.latitude, required this.longitude});
}

/// The rendered images, keyed by everything that would change one. Bounded
/// hard: a @3x card is a megabyte-ish of decoded pixels, and re-opening the
/// same event should not pay for a geocode and a render again.
final _cache = <String, MapView>{};
final _pending = <String, Future<MapView?>>{};
const _maxCached = 4;

/// Renders [query] — the event's location, as the user typed it — at
/// [width] × [height] logical points.
///
/// Null means "no map for this one", which is an ordinary answer: a place the
/// geocoder cannot place, no network on first open, or a platform without the
/// handler. Every caller draws nothing rather than an error.
Future<MapView?> mapSnapshot({
  required String query,
  required double width,
  required double height,
  required double scale,
  required bool dark,
}) async {
  final place = query.trim();
  if (place.isEmpty) return null;
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return null;

  final key = '$place|${width.round()}x${height.round()}@${scale.round()}|${dark ? 'dark' : 'light'}';
  final cached = _cache[key];
  if (cached != null) return cached;
  // Two rows of the same sheet, or a rebuild landing mid-flight, share the one
  // request instead of asking the geocoder twice for the same street.
  final inFlight = _pending[key];
  if (inFlight != null) return inFlight;

  final request = _render(key, place, width, height, scale, dark);
  _pending[key] = request;
  try {
    return await request;
  } finally {
    _pending.remove(key);
  }
}

Future<MapView?> _render(
  String key,
  String place,
  double width,
  double height,
  double scale,
  bool dark,
) async {
  try {
    final answer = await _channel.invokeMapMethod<String, dynamic>('snapshot', {
      'query': place,
      'width': width,
      'height': height,
      'scale': scale,
      'dark': dark,
    });
    final image = answer?['image'] as Uint8List?;
    final latitude = answer?['latitude'] as double?;
    final longitude = answer?['longitude'] as double?;
    if (image == null || latitude == null || longitude == null) return null;

    final view = MapView(image: image, latitude: latitude, longitude: longitude);
    if (_cache.length >= _maxCached) _cache.remove(_cache.keys.first);
    return _cache[key] = view;
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}
