import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/weather.dart';
import '../../services/weather_cache.dart';

/// The only file that knows where the weather comes from.
///
/// **Two free sources that allow commercial use, both credited in the weather
/// card.** Open-Meteo, which this used to call, is free *only* for
/// non-commercial use — its terms name "apps that have subscriptions" as
/// commercial, and Aporah Plus is one — so it was swapped out rather than paid
/// for (checked 2026-09-18):
///
/// * **Forecast: Bright Sky** (`api.brightsky.dev`), a free JSON front for the
///   Deutscher Wetterdienst's open data. No key. The data is the DWD's, reusable
///   commercially under CC BY 4.0 with the DWD named as the source. It is the
///   official German forecast, which is also what a German household expects;
///   its reach is Germany and its surroundings, which is the launch market. If
///   the app ever ships further, MET Norway's `locationforecast` is the
///   worldwide equivalent on the same terms (CC BY 4.0, free, a User-Agent
///   required).
/// * **Place names: Photon** (`photon.komoot.io`), the geocoder the Abfall
///   address search already uses server-side. OpenStreetMap data (ODbL, credit
///   "OpenStreetMap"), free under fair use. Unlike Open-Meteo's geocoder it
///   knows *addresses*, not just towns.
///
/// Both are called straight from the app: a proxy would add a hop, a deploy and
/// a place for the household's addresses to be logged. What goes on the wire is
/// a place name or a coordinate and the phone's IP — the trade the weather
/// section of docs/ported-features.md describes, now with two providers to name
/// in the Datenschutzerklärung instead of one.
///
/// Being free is exactly why the caching in [WeatherCache] matters. A family
/// with a busy week must cost a couple of requests, not one per row per
/// rebuild, so a point is fetched once an hour and a place name is geocoded
/// once, ever — which is also what "fair use" asks of us.
class WeatherRepository {
  WeatherRepository({http.Client? client, WeatherCache? cache})
    : _http = client ?? http.Client(),
      _cache = cache ?? WeatherCache();

  final http.Client _http;
  final WeatherCache _cache;

  /// The DWD's horizon (MOSMIX runs 240 hours), and therefore the app's: an
  /// appointment further out than this gets no chip, because there is no
  /// forecast to give it.
  static const forecastHorizon = Duration(days: 10);

  static const _geocodeHost = 'photon.komoot.io';
  static const _forecastHost = 'api.brightsky.dev';

  /// Both services ask to be told who is calling, and fair use is easier to
  /// honour when the traffic is identifiable.
  static const _headers = {'User-Agent': 'Aporah (family organizer app)'};
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
        final candidates = _placeQueries(query);
        for (final (i, candidate) in candidates.indexed) {
          // The whole line must land in a town it names. Photon matches names
          // as well as addresses, so "Kita Sonnenschein, Stuhr" finds *a* Kita
          // Sonnenschein — in Berlin — and a wrong town's weather on the row is
          // worse than the next, town-only query.
          final towns = i == 0 ? candidates.skip(1).toList() : const <String>[];
          point = await _fetchPlace(candidate, inOneOf: towns);
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
  /// The whole line goes first, and Photon usually places it outright — street
  /// and house number included. But an event's "Ort" is as often "Kita
  /// Sonnenschein, Syke" as a clean address, so the town is tried next, two
  /// ways, because both spellings are ordinary:
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

  /// [inOneOf] non-empty means the hit only counts when its city, postcode,
  /// district or county mentions one of those towns. Empty means there is no
  /// town to check against, so the hit only counts when it *is* a town: a lone
  /// "Kita Sonnenschein" or "Hauptstraße" matches one somewhere in Germany, and
  /// the household's own town — the caller's fallback — is the better guess.
  Future<GeoPoint?> _fetchPlace(String query, {List<String> inOneOf = const []}) async {
    final uri = Uri.https(_geocodeHost, '/api/', {
      'q': query,
      'limit': '5',
      // Only the returned spelling — `Köln`, not `Cologne`. Everything looked
      // up is German, whatever the interface language.
      'lang': 'de',
    });

    final body = await _getJson(uri);
    final features = body?['features'];
    if (features is! List || features.isEmpty) return null;

    // Prefer the German hit: "Stuhr" and "Berlin" both exist several times over
    // on a world-wide geocoder, and the household is here.
    Map<String, dynamic>? hit;
    for (final f in features) {
      if (f is! Map<String, dynamic>) continue;
      hit ??= f;
      if ((f['properties'] as Map?)?['countrycode'] == 'DE') {
        hit = f;
        break;
      }
    }
    if (hit == null) return null;

    // GeoJSON order: longitude first.
    final coordinates = (hit['geometry'] as Map?)?['coordinates'];
    if (coordinates is! List || coordinates.length < 2) return null;
    final lon = coordinates[0];
    final lat = coordinates[1];
    if (lat is! num || lon is! num) return null;

    final props = hit['properties'] as Map? ?? const {};
    if (inOneOf.isEmpty) {
      // Photon's own classification: `city` is any town or village, `district`
      // a part of one. Not `locality` (a hamlet called "Raum" is how "Turnhalle,
      // Raum 2" once put Bad Boll's weather on a row), and not a country or a
      // state, which is what a bare "Deutschland" would otherwise be.
      if (!const {'city', 'district'}.contains(props['type'])) return null;
      // And it must be the town that was asked for. Photon matches fuzzily, so
      // "Raum" comes back as "Raumbach"; "München-Schwabing" still finds
      // München, because the query contains the name.
      final asked = query.toLowerCase();
      final named = [
        for (final k in const ['name', 'city'])
          if (props[k] case final String v when v.isNotEmpty) v.toLowerCase(),
      ];
      if (!named.any(asked.contains)) return null;
    } else {
      final where = [
        // Not `name`: that is the venue's own, and "Kita Sonnenschein" would
        // vouch for itself.
        for (final k in const ['city', 'postcode', 'district', 'county'])
          if (props[k] case final String v) v.toLowerCase(),
      ].join(' ');
      if (!inOneOf.any((town) => where.contains(town.toLowerCase()))) return null;
    }
    return GeoPoint(
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
      name: (props['city'] ?? props['name']) as String? ?? query,
    );
  }

  /// [forecastHorizon] of hourly forecast at one point, cached for an hour.
  Future<HourlyForecast?> hourly(GeoPoint point) async {
    final key = point.cacheKey;

    final cached = await _cache.forecast(key);
    if (cached != null) {
      final parsed = HourlyForecast.fromMap(cached);
      if (parsed != null) return parsed;
    }

    return _pendingForecasts[key] ??= () async {
      try {
        // From midnight today, not from now: an 11:00 appointment still shows
        // its weather at 17:00 (`WeatherNotifier._floor`), and for the hours
        // already gone Bright Sky answers with the observation instead.
        final today = DateTime.now();
        final from = DateTime(today.year, today.month, today.day);
        final to = DateTime(today.year, today.month, today.day + forecastHorizon.inDays);
        final uri = Uri.https(_forecastHost, '/weather', {
          'lat': point.latitude.toStringAsFixed(4),
          'lon': point.longitude.toStringAsFixed(4),
          // With the phone's own offset: a bare date is read as UTC midnight,
          // which in Germany drops the first two hours of today.
          'date': _isoMidnight(from),
          'last_date': _isoMidnight(to),
        });

        final body = await _getJson(uri);
        final hours = body?['weather'];
        if (hours is! List) return null;

        final parsed = brightSkyForecast(hours);
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

  static String _isoMidnight(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final offset = d.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final minutes = offset.inMinutes.abs();
    return '${d.year}-${two(d.month)}-${two(d.day)}T00:00:00'
        '$sign${two(minutes ~/ 60)}:${two(minutes % 60)}';
  }

  Future<Map<String, dynamic>?> _getJson(Uri uri) async {
    final res = await _http.get(uri, headers: _headers).timeout(_timeout);
    if (res.statusCode != 200) return null;
    final decoded = jsonDecode(res.body);
    return decoded is Map<String, dynamic> ? decoded : null;
  }
}
