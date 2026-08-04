import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// The device's copy of what Open-Meteo has already answered.
///
/// Two things are worth keeping between launches, for opposite reasons:
///
/// * **Geocoded places** never change, so they are kept forever — including the
///   ones that resolved to *nothing*. A location somebody typed as "zu Hause"
///   will never geocode, and without a remembered null it would cost a request
///   every single time the calendar refreshes.
/// * **Hourly forecasts** change constantly, so they expire after an hour. What
///   they buy is the cold start: the chips are on the very first frame instead
///   of appearing a beat later and shifting the agenda.
///
/// One file, read once and rewritten whole, exactly like [CalendarCache] — and
/// like it, everything here fails soft. A cache that will not read or write
/// means more requests, never a broken screen.
class WeatherCache {
  WeatherCache({this.fileName = 'weather_cache.json'});

  final String fileName;

  /// How long a forecast is served before it is fetched again. Open-Meteo
  /// updates hourly, so anything shorter is requests for identical numbers.
  static const forecastTtl = Duration(hours: 1);

  /// A ceiling on the point cache, so a family that travels does not grow this
  /// file forever. The least recently written points fall out first.
  static const _maxPoints = 12;

  File? _file;
  Map<String, dynamic>? _memory;

  Future<File?> _resolve() async {
    if (_file != null) return _file;
    try {
      final dir = await getApplicationSupportDirectory();
      return _file = File('${dir.path}/$fileName');
    } catch (_) {
      // No writable directory (a test host, a locked container). Weather still
      // works; it just re-fetches on every cold start.
      return null;
    }
  }

  Future<Map<String, dynamic>> _load() async {
    final cached = _memory;
    if (cached != null) return cached;
    try {
      final file = await _resolve();
      if (file != null && await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) return _memory = decoded;
      }
    } catch (_) {
      // Unreadable or from an older shape — start over rather than guess.
    }
    return _memory = {'places': <String, dynamic>{}, 'points': <String, dynamic>{}};
  }

  Future<void> _flush() async {
    try {
      final file = await _resolve();
      if (file == null) return;
      await file.writeAsString(jsonEncode(_memory), flush: true);
    } catch (_) {
      // Out of space, or no container. The in-memory copy carries the session.
    }
  }

  Map<String, dynamic> _section(Map<String, dynamic> root, String name) {
    final section = root[name];
    if (section is Map<String, dynamic>) return section;
    return root[name] = <String, dynamic>{};
  }

  /// `(hit: false, value: null)` means "never looked up"; `(hit: true, value:
  /// null)` means "looked up and there is no such place" — the distinction is
  /// the whole point of caching failures.
  Future<({bool hit, Map<String, dynamic>? value})> place(String query) async {
    final places = _section(await _load(), 'places');
    if (!places.containsKey(query)) return (hit: false, value: null);
    final value = places[query];
    return (hit: true, value: value is Map<String, dynamic> ? value : null);
  }

  Future<void> putPlace(String query, Map<String, dynamic>? value) async {
    _section(await _load(), 'places')[query] = value;
    await _flush();
  }

  /// The forecast stored for [pointKey], or null when there is none or it has
  /// gone stale.
  Future<Map<String, dynamic>?> forecast(String pointKey) async {
    final entry = _section(await _load(), 'points')[pointKey];
    if (entry is! Map<String, dynamic>) return null;

    final written = DateTime.tryParse(entry['at'] as String? ?? '');
    if (written == null || DateTime.now().difference(written) > forecastTtl) return null;

    final data = entry['data'];
    return data is Map<String, dynamic> ? data : null;
  }

  Future<void> putForecast(String pointKey, Map<String, dynamic> data) async {
    final points = _section(await _load(), 'points');
    points[pointKey] = {'at': DateTime.now().toIso8601String(), 'data': data};

    // Insertion order is write order, so the oldest writes are simply the first
    // keys — no timestamps to sort.
    while (points.length > _maxPoints) {
      points.remove(points.keys.first);
    }
    await _flush();
  }
}
