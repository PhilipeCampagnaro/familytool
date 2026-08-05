import '../l10n/l10n.dart';
import '../theme/tokens.dart';
import 'calendar_event.dart';

/// The forecast at one appointment, and the pure helpers that decide which
/// forecast that is.
///
/// Nothing here fetches: `WeatherRepository` owns the network and
/// `WeatherNotifier` owns the wiring. This file is only the shape of a reading
/// plus the two rules the fetch layer and the render layer both have to agree
/// on — *when* an event is sampled ([eventSampleTime]) and *what to call* that
/// sample ([eventWeatherKey]). If those two ever disagree, every chip silently
/// disappears, so they live side by side.

/// The WMO code buckets, collapsed to the eight the app has an icon for.
enum WeatherCondition { clear, partlyCloudy, cloudy, fog, drizzle, rain, snow, storm }

/// Open-Meteo's `weather_code` (WMO 4677) narrowed to a [WeatherCondition].
///
/// The unlisted codes are all variations the buckets already cover (freezing
/// drizzle sits with drizzle, hail with the storm it falls out of), so an
/// unknown code answering "cloudy" is a safe default rather than a gap.
WeatherCondition conditionFromCode(int code) {
  if (code == 0) return WeatherCondition.clear;
  if (code == 1 || code == 2) return WeatherCondition.partlyCloudy;
  if (code == 3) return WeatherCondition.cloudy;
  if (code == 45 || code == 48) return WeatherCondition.fog;
  if (code >= 51 && code <= 57) return WeatherCondition.drizzle;
  if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) return WeatherCondition.rain;
  if ((code >= 71 && code <= 77) || code == 85 || code == 86) return WeatherCondition.snow;
  if (code >= 95) return WeatherCondition.storm;
  return WeatherCondition.cloudy;
}

/// One hour's forecast at one place — what a card actually renders.
class WeatherReading {
  /// The raw WMO code, kept rather than only its bucket so a later feature can
  /// draw a finer distinction without re-fetching.
  final int code;

  final double temperature;

  /// Chance of precipitation in percent, or null when the provider omitted it.
  final int? precipitation;

  /// Decides sun vs moon. Open-Meteo answers it per hour, which is the only
  /// honest way to do it — sunset moves by two hours across a German year.
  final bool isDay;

  const WeatherReading({
    required this.code,
    required this.temperature,
    required this.isDay,
    this.precipitation,
  });

  WeatherCondition get condition => conditionFromCode(code);

  /// `18°`. Rounded, because half a degree three days out is noise.
  String get temperatureLabel => L.s.temperature(temperature.round());

  String get label => switch (condition) {
    WeatherCondition.clear => L.s.weatherClear,
    WeatherCondition.partlyCloudy => L.s.weatherPartlyCloudy,
    WeatherCondition.cloudy => L.s.weatherCloudy,
    WeatherCondition.fog => L.s.weatherFog,
    WeatherCondition.drizzle => L.s.weatherDrizzle,
    WeatherCondition.rain => L.s.weatherRain,
    WeatherCondition.snow => L.s.weatherSnow,
    WeatherCondition.storm => L.s.weatherStorm,
  };

  /// The Meteocons file to draw, full-colour, through `flutter_svg`.
  ///
  /// **Not a [IconData] like the rest of the app, and that is the point.** A
  /// weather glyph in one flat colour is the one place Lucide could not carry
  /// its weight: tinted with the row's accent, drizzle, rain and overcast are
  /// three blue clouds a glance apart, and the icon stops being information.
  /// These carry the colour themselves — an amber sun, a grey overcast, a blue
  /// rain — so the condition is legible before the label under it is read.
  ///
  /// Ten of Meteocons' 535 are vendored, one per line below; anything else the
  /// set offers needs no code, only the file and a line here.
  ///
  /// Only the two clearest buckets have a night form: a rain cloud at 22:00 is
  /// still a rain cloud, but a sun is not.
  String get iconAsset => 'assets/weather/${switch (condition) {
    WeatherCondition.clear => isDay ? 'clear-day' : 'clear-night',
    WeatherCondition.partlyCloudy => isDay ? 'partly-cloudy-day' : 'partly-cloudy-night',
    WeatherCondition.cloudy => 'cloudy',
    WeatherCondition.fog => 'fog',
    WeatherCondition.drizzle => 'drizzle',
    WeatherCondition.rain => 'rain',
    WeatherCondition.snow => 'snow',
    WeatherCondition.storm => 'thunderstorms-rain',
  }}.svg';

  /// The wash behind the forecast card in the event sheet, and the ink on it.
  /// The agenda row deliberately has no skin — see [WeatherSkin].
  WeatherSkin get skin => switch (condition) {
    WeatherCondition.clear => isDay ? AppSkies.clearDay : AppSkies.clearNight,
    WeatherCondition.partlyCloudy => isDay ? AppSkies.partlyCloudyDay : AppSkies.partlyCloudyNight,
    WeatherCondition.cloudy => AppSkies.cloudy,
    WeatherCondition.fog => AppSkies.fog,
    WeatherCondition.drizzle => AppSkies.drizzle,
    WeatherCondition.rain => AppSkies.rain,
    WeatherCondition.snow => AppSkies.snow,
    WeatherCondition.storm => AppSkies.storm,
  };
}

/// A geocoded place. [name] is the geocoder's own spelling of the town, which
/// is what a heading should show rather than whatever the user typed.
class GeoPoint {
  final double latitude;
  final double longitude;
  final String name;

  const GeoPoint({required this.latitude, required this.longitude, this.name = ''});

  /// Two decimals ≈ 1 km, which is the resolution the forecast model has
  /// anyway — so two addresses on the same street share one fetch.
  String get cacheKey =>
      '${(latitude * 100).round() / 100},${(longitude * 100).round() / 100}';

  factory GeoPoint.fromMap(Map<String, dynamic> map) => GeoPoint(
    latitude: (map['lat'] as num).toDouble(),
    longitude: (map['lon'] as num).toDouble(),
    name: map['name'] as String? ?? '',
  );

  Map<String, dynamic> toMap() => {'lat': latitude, 'lon': longitude, 'name': name};
}

/// Open-Meteo's `hourly` block: parallel arrays, one entry per hour.
///
/// Kept in the provider's own shape rather than exploded into a list of
/// objects, because that is also how it is cached — and re-encoding 384 hours
/// into 384 maps to store them would be pure cost.
class HourlyForecast {
  final List<DateTime> times;
  final List<double?> temperature;
  final List<int?> codes;
  final List<int?> precipitation;
  final List<bool> isDay;

  const HourlyForecast({
    required this.times,
    required this.temperature,
    required this.codes,
    required this.precipitation,
    required this.isDay,
  });

  bool get isEmpty => times.isEmpty;

  /// The reading nearest [when], or null when [when] falls outside the forecast
  /// window — before it (a past appointment) or beyond its horizon.
  ///
  /// The 90-minute tolerance is what turns "no exact hour" into "no chip"
  /// instead of into a reading from the wrong day: hours are one apart, so
  /// anything inside the window always has a neighbour within 30 minutes and
  /// anything outside it is at least half a day away.
  WeatherReading? at(DateTime when) {
    var best = -1;
    var bestDiff = const Duration(days: 3650);
    for (var i = 0; i < times.length; i++) {
      final diff = times[i].difference(when).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = i;
      }
    }
    if (best < 0 || bestDiff > const Duration(minutes: 90)) return null;

    final code = codes.length > best ? codes[best] : null;
    final temp = temperature.length > best ? temperature[best] : null;
    if (code == null || temp == null) return null;

    return WeatherReading(
      code: code,
      temperature: temp,
      isDay: isDay.length > best ? isDay[best] : true,
      precipitation: precipitation.length > best ? precipitation[best] : null,
    );
  }

  /// [map] is the `hourly` object straight off the wire, or the same thing read
  /// back out of the cache. Returns null for anything that isn't one.
  static HourlyForecast? fromMap(Map<String, dynamic>? map) {
    final rawTimes = map?['time'];
    if (rawTimes is! List || rawTimes.isEmpty) return null;

    final times = <DateTime>[];
    for (final raw in rawTimes) {
      // `timezone=auto` means these arrive without a zone suffix, i.e. already
      // local to the forecast point — which is where the appointment is too.
      // DateTime.parse reads them as local, so they compare directly against an
      // event's own local start with no conversion at all.
      final parsed = DateTime.tryParse(raw as String? ?? '');
      if (parsed == null) return null;
      times.add(parsed);
    }

    List<T?> column<T>(String name, T? Function(Object?) read) {
      final raw = map?[name];
      if (raw is! List) return List<T?>.filled(times.length, null);
      return [for (final v in raw) read(v)];
    }

    return HourlyForecast(
      times: times,
      temperature: column('temperature_2m', (v) => v is num ? v.toDouble() : null),
      codes: column('weather_code', (v) => v is num ? v.toInt() : null),
      precipitation: column('precipitation_probability', (v) => v is num ? v.toInt() : null),
      // Missing `is_day` reads as day rather than as night: a sun on a cloudy
      // evening is a smaller lie than a moon at lunchtime.
      isDay: [for (final v in column('is_day', (v) => v is num ? v.toInt() : null)) v != 0],
    );
  }

  Map<String, dynamic> toMap() => {
    'time': [for (final t in times) t.toIso8601String()],
    'temperature_2m': temperature,
    'weather_code': codes,
    'precipitation_probability': precipitation,
    'is_day': [for (final d in isDay) d ? 1 : 0],
  };
}

// ---------------------------------------------------------------------------
// Which forecast belongs to which appointment
// ---------------------------------------------------------------------------

/// The moment an event is sampled at.
///
/// A timed event uses its own start. An all-day event has no hour, so it takes
/// local mid-day on [day] — and because [day] is passed in rather than derived
/// from the event, every day of a week-long Ferien block is sampled on its own
/// day instead of all seven sharing Monday's forecast.
DateTime eventSampleTime(CalendarEvent event, DateTime day) => event.allDay
    ? DateTime(day.year, day.month, day.day, 13)
    : event.startsAt;

/// The name of one reading: same place, same moment, same key.
///
/// The place is part of it because two appointments at the same hour in two
/// towns genuinely have different weather; it is normalised because it is free
/// text the user typed.
String eventWeatherKey(CalendarEvent event, DateTime day) =>
    '${event.loc.trim().toLowerCase()}@'
    '${eventSampleTime(event, day).millisecondsSinceEpoch}';

/// What follows the last number in an address line — which in German is the
/// town. `"Weyher Str 100 28816 Stuhr"` -> `"Stuhr"`.
///
/// Open-Meteo's geocoder searches place *names*: the whole line is a miss, and
/// so is `"28816 Stuhr"`, because a postal code is not a name either. Commas
/// are the obvious way to find the town in a line like that, but people write
/// an address on one line at least as often as with them, and then there is
/// nothing to split on — so the anchor is the last number instead, which covers
/// the house number and the postal code in one rule.
///
/// A location with no number in it — "Kita Sonnenschein", "Zuhause" — comes back
/// empty rather than guessed at from its last word: a wrong town's weather on a
/// row is worse than no icon on it.
String placeAfterNumber(String line) {
  final text = line.trim();
  // Greedy, so it runs to the *last* number; the optional letter is the "a" in
  // "12a", and the trailing space is what separates it from the town.
  final match = RegExp(r'.*\d+\s*[a-zA-ZäöüÄÖÜ]?\s+').firstMatch(text);
  return match == null ? '' : text.substring(match.end).trim();
}

/// The countries a German-language family app plausibly writes into an address,
/// in both spellings. Never a useful answer: "Deutschland" geocodes happily to
/// a point in Hesse, and that weather on a row is worse than no weather.
const countryWords = {
  'deutschland', 'germany', 'österreich', 'oesterreich', 'austria', //
  'schweiz', 'switzerland', 'suisse',
};

/// The town out of a free-text German address, for the geocoder.
///
/// `"Weyher Straße 100, 28816 Stuhr"` and `"Weyher Str 100 28816 Stuhr"` both
/// give `"Stuhr"` — see [placeAfterNumber] for why the house number rather than
/// the comma is the anchor. Returns null when there is nothing usable, and the
/// household then simply has no home forecast.
String? homeTownFrom(String? address) {
  final line = address?.trim() ?? '';
  if (line.isEmpty) return null;

  // From the end, because that is where the town is — but past a trailing
  // country, which is a part like any other and never the answer.
  for (final part in line.split(',').reversed) {
    final tail = part.trim();
    if (tail.isEmpty) continue;
    if (countryWords.contains(tail.toLowerCase())) continue;

    // A bare "Stuhr" has no number to anchor on and is left alone.
    final afterNumber = placeAfterNumber(tail);
    return afterNumber.isEmpty ? tail : afterNumber;
  }
  return null;
}
