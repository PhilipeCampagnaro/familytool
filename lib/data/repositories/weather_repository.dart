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
        final point = await _fetchPlace(query);
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
