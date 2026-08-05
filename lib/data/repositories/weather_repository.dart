import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/weather.dart';
import '../../services/weather_cache.dart';

/// The only file that knows where the weather comes from.
///
/// **Open-Meteo, called straight from the app.** No API key, no quota to hide
/// behind a secret, and no personal data on the wire — a latitude and a
/// longitude, nothing about who asked. So unlike every calendar provider, this
/// one needs no Edge Function in front of it: a proxy here would add a hop, a
/// deploy and a place for the household's addresses to be logged, in exchange
/// for nothing.
///
/// Being free is exactly why the caching in [WeatherCache] matters. A family
/// with a busy week must cost a couple of requests, not one per row per
/// rebuild, so a point is fetched once an hour and a place name is geocoded
/// once, ever.
class WeatherRepository {
  WeatherRepository({http.Client? client, WeatherCache? cache})
    : _http = client ?? http.Client(),
      _cache = cache ?? WeatherCache();

  final http.Client _http;
  final WeatherCache _cache;

  /// Open-Meteo's horizon, and therefore the app's: an appointment further out
  /// than this gets no chip, because there is no forecast to give it.
  static const forecastHorizon = Duration(days: 16);

  static const _geocodeHost = 'geocoding-api.open-meteo.com';
  static const _forecastHost = 'api.open-meteo.com';
  static const _timeout = Duration(seconds: 8);

  /// In-flight de-duplication. A calendar refresh resolves every event at once,
  /// and a dozen appointments in the same town must not become a dozen
  /// simultaneous requests for it — the cache only helps once one has landed.
  final _pendingPlaces = <String, Future<GeoPoint?>>{};
  final _pendingForecasts = <String, Future<HourlyForecast?>>{};

  /// A place name -> a point, or null when the geocoder has nothing.
  ///
  /// Free text: this is the same string that already opens Maps from an event,
  /// so it is as likely to be "Kita Sonnenschein" as a town. A miss is normal
  /// and is remembered as one — the caller then falls back to the home town.
  Future<GeoPoint?> geocode(String query) async {
    final key = query.trim().toLowerCase();
    if (key.isEmpty) return null;

    final cached = await _cache.place(key);
    if (cached.hit) {
      final value = cached.value;
      return value == null ? null : GeoPoint.fromMap(value);
    }

    return _pendingPlaces[key] ??= () async {
      try {
        GeoPoint? point;
        for (final candidate in _placeQueries(query)) {
          point = await _fetchPlace(candidate);
          if (point != null) break;
        }
        await _cache.putPlace(key, point?.toMap());
        return point;
      } catch (_) {
        // A network failure is not an answer about the place, so it is *not*
        // cached — the next refresh tries again.
        return null;
      } finally {
        _pendingPlaces.remove(key);
      }
    }();
  }

  /// What to ask the geocoder for [query], most specific first.
  ///
  /// Open-Meteo's geocoder knows **places, not addresses**: "Syke" is a hit and
  /// "Amtshof 3, 28857 Syke" is nothing at all, which is why a household that
  /// typed a real street into an event saw no forecast on it. So an address is
  /// also tried town-first, two ways, because both spellings are ordinary:
  ///
  /// * **"Amtshof 3, 28857 Syke"** — the last comma-separated part, minus its
  ///   postal code, then the earlier parts minus their house numbers.
  /// * **"Amtshof 3 28857 Syke"** — no comma to split on, so the anchor is the
  ///   last number instead ([placeAfterNumber]). Without this the *only*
  ///   candidate was the whole line, and a one-line address never resolved.
  ///
  /// A town is the right granularity for weather anyway: nobody needs a
  /// forecast per street.
  ///
  /// Country names are dropped rather than tried, since "Deutschland" would
  /// otherwise geocode happily to a point in Hesse and put that weather on the
  /// row — a wrong answer being worse here than no answer, which falls back to
  /// the household's own town.
  static List<String> _placeQueries(String query) {
    final full = query.trim();
    if (full.isEmpty) return const [];

    final out = <String>[full];
    for (final part in full.split(',').reversed) {
      final stripped = part
          .trim()
          // A German postal code in front of the town, and a house number
          // (with its optional "a") behind a street.
          .replaceFirst(RegExp(r'^\d{4,6}\s+'), '')
          .replaceFirst(RegExp(r'\s+\d+\s*[a-zA-Z]?$'), '')
          .trim();
      for (final place in [stripped, placeAfterNumber(part)]) {
        if (place.length < 3) continue;
        if (countryWords.contains(place.toLowerCase())) continue;
        if (out.contains(place)) continue;
        out.add(place);
      }
      // Two extra lookups is the whole budget: past the town, the parts are
      // building names the geocoder was never going to place.
      if (out.length >= 3) break;
    }
    return out.length <= 3 ? out : out.sublist(0, 3);
  }

  Future<GeoPoint?> _fetchPlace(String query) async {
    final uri = Uri.https(_geocodeHost, '/v1/search', {
      'name': query,
      'count': '5',
      // The result language only affects the returned spelling. Everything the
      // app looks up is German, so this is about `Köln` not coming back as
      // `Cologne`, not about the interface language.
      'language': 'de',
      'format': 'json',
    });

    final body = await _getJson(uri);
    final results = body?['results'];
    if (results is! List || results.isEmpty) return null;

    // Prefer the German hit: "Stuhr" and "Berlin" both exist several times over
    // on a world-wide geocoder, and the household is here.
    Map<String, dynamic>? hit;
    for (final r in results) {
      if (r is! Map<String, dynamic>) continue;
      hit ??= r;
      if (r['country_code'] == 'DE') {
        hit = r;
        break;
      }
    }
    if (hit == null) return null;

    final lat = hit['latitude'];
    final lon = hit['longitude'];
    if (lat is! num || lon is! num) return null;

    return GeoPoint(
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
      name: hit['name'] as String? ?? query,
    );
  }

  /// 16 days of hourly forecast at one point, cached for an hour.
  Future<HourlyForecast?> hourly(GeoPoint point) async {
    final key = point.cacheKey;

    final cached = await _cache.forecast(key);
    if (cached != null) {
      final parsed = HourlyForecast.fromMap(cached);
      if (parsed != null) return parsed;
    }

    return _pendingForecasts[key] ??= () async {
      try {
        final uri = Uri.https(_forecastHost, '/v1/forecast', {
          'latitude': point.latitude.toStringAsFixed(4),
          'longitude': point.longitude.toStringAsFixed(4),
          'hourly': 'temperature_2m,weather_code,precipitation_probability,is_day',
          'forecast_days': '${forecastHorizon.inDays}',
          // Belt and braces for the hours *earlier today*: an 11:00 appointment
          // still shows its weather at 17:00 (`WeatherNotifier._floor`). The
          // series already starts at today 00:00, so this changes nothing today
          // — it only means the feature doesn't hang on that one detail of
          // somebody else's API staying as it is.
          'past_days': '1',
          // Hours come back local to the point, which is what an appointment's
          // start is too — see HourlyForecast.fromMap.
          'timezone': 'auto',
        });

        final body = await _getJson(uri);
        final hourly = body?['hourly'];
        if (hourly is! Map<String, dynamic>) return null;

        final parsed = HourlyForecast.fromMap(hourly);
        if (parsed == null || parsed.isEmpty) return null;

        await _cache.putForecast(key, parsed.toMap());
        return parsed;
      } catch (_) {
        return null;
      } finally {
        _pendingForecasts.remove(key);
      }
    }();
  }

  Future<Map<String, dynamic>?> _getJson(Uri uri) async {
    final res = await _http.get(uri).timeout(_timeout);
    if (res.statusCode != 200) return null;
    final decoded = jsonDecode(res.body);
    return decoded is Map<String, dynamic> ? decoded : null;
  }
}
