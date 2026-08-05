import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/weather_repository.dart';
import '../models/calendar_event.dart';
import '../models/weather.dart';
import 'calendar_state.dart';
import 'family_state.dart';

class WeatherState {
  /// Keyed by [eventWeatherKey], so a row looks its own forecast up with the
  /// same two facts the fetch used: where the event is, and when it is.
  final Map<String, WeatherReading> readings;

  const WeatherState({this.readings = const {}});

  /// The forecast to draw beside [event] on [day], or null — which is the
  /// normal answer for a past appointment, one beyond the forecast horizon, or
  /// a household that has not given an address and holds no geocodable event
  /// locations either.
  WeatherReading? forEvent(CalendarEvent event, DateTime day) =>
      readings[eventWeatherKey(event, day)];
}

/// Puts the forecast beside every appointment that has one.
///
/// **Weather is decoration, and this file is written to that.** Every failure —
/// no address, an unroutable location, a geocoder that times out, an aeroplane —
/// resolves to "no chip on that row" and never to an error the user has to read.
/// The calendar is the feature; the weather is a nicety on top of it, and a
/// nicety that can break the screen is worse than no nicety.
///
/// Where a reading comes from, in order: **the event's own location** — the same
/// free-text string that already opens Maps — and, when that is empty or the
/// geocoder cannot place it, **the household's address** from onboarding. A
/// swimming lesson two towns over is forecast where it happens, not where the
/// family sleeps.
class WeatherNotifier extends StateNotifier<WeatherState> {
  WeatherNotifier(this._repo) : super(const WeatherState());

  final WeatherRepository _repo;

  /// A calendar that has not changed must not be re-resolved — and it changes
  /// identity on every refresh even when nothing in it moved, so the guard is
  /// on content. It is paired with [_syncedAt] because an unchanged calendar
  /// still wants a fresh forecast eventually.
  String? _signature;
  DateTime? _syncedAt;
  bool _running = false;

  /// How long an unchanged calendar is left alone. Matches the forecast cache's
  /// own lifetime, so a sync just after one is a file read and no requests.
  static const _resyncAfter = Duration(hours: 1);

  /// Distinct places resolved per pass. A household with a dozen appointments
  /// in a dozen towns is not what this feature is for, and an unbounded fan-out
  /// on a free API is how a client gets blocked.
  static const _maxPlaces = 8;

  /// **Today is forecast whole**, from midnight — a timed appointment keeps its
  /// reading all day, not for a grace period after it started. The day you are
  /// looking at is the day you are living: at 17:00 the 11:00 appointment is
  /// still on the screen, and a row that shows the weather until 13:00 and then
  /// stops reads as broken rather than as tidy. It costs nothing — the hour is
  /// in the same series the rest of the day comes from (`past_days=1` in
  /// [WeatherRepository.hourly]).
  static DateTime _floor(DateTime now) => DateTime(now.year, now.month, now.day);

  /// [eventsByDay] is `CalendarScreenState.eventsByDay` — already expanded to
  /// one entry per day an event covers, which is exactly the granularity the
  /// forecast needs: each day of a week-long Ferien block is sampled on its own
  /// day rather than all seven sharing Monday's.
  Future<void> sync(Map<String, List<CalendarEvent>> eventsByDay, String? homeAddress) async {
    if (_running) return;

    final now = DateTime.now();
    final samples = _forecastable(eventsByDay, now);
    final town = homeTownFrom(homeAddress);

    final signature = '${town ?? ''}|${samples.map((s) => s.key).join(',')}';
    final syncedAt = _syncedAt;
    final fresh = syncedAt != null && now.difference(syncedAt) < _resyncAfter;
    if (signature == _signature && fresh) return;

    if (samples.isEmpty) {
      _signature = signature;
      _syncedAt = now;
      if (state.readings.isNotEmpty) state = const WeatherState();
      return;
    }

    _running = true;
    try {
      final readings = await _resolve(samples, town);
      if (!mounted) return;
      // A pass that resolved nothing at all is not recorded as done: it is
      // almost always the offline case, and the next refresh should retry
      // rather than sit on an empty answer for an hour.
      if (readings.isNotEmpty) {
        _signature = signature;
        _syncedAt = now;
        state = WeatherState(readings: readings);
      }
    } finally {
      _running = false;
    }
  }

  Future<Map<String, WeatherReading>> _resolve(List<_Sample> samples, String? town) async {
    // The home point is resolved first and once: it is the fallback for every
    // event without a placeable location of its own, which is most of them.
    final home = town == null ? null : await _repo.geocode(town);

    final points = <String, GeoPoint?>{};
    for (final sample in samples) {
      final location = sample.event.loc.trim();
      if (location.isEmpty) continue;

      final key = location.toLowerCase();
      if (points.containsKey(key)) continue;
      if (points.length >= _maxPlaces) break;
      points[key] = await _repo.geocode(location);
    }

    final forecasts = <String, HourlyForecast?>{};
    Future<HourlyForecast?> forecastAt(GeoPoint point) async {
      final key = point.cacheKey;
      if (forecasts.containsKey(key)) return forecasts[key];
      return forecasts[key] = await _repo.hourly(point);
    }

    final readings = <String, WeatherReading>{};
    for (final sample in samples) {
      // A location the geocoder could not place falls back to home rather than
      // dropping the row: "Zuhause" or "Turnhalle" is far more often the family's
      // own town than somewhere else.
      final point = points[sample.event.loc.trim().toLowerCase()] ?? home;
      if (point == null) continue;

      final forecast = await forecastAt(point);
      final reading = forecast?.at(sample.at);
      if (reading != null) readings[sample.key] = reading;
    }
    return readings;
  }

  /// The (event, day) pairs that could carry a chip: inside the forecast
  /// window, and not already over. Bounds the work on a busy calendar to the
  /// near term instead of every event the household has ever had.
  List<_Sample> _forecastable(Map<String, List<CalendarEvent>> eventsByDay, DateTime now) {
    final horizon = now.add(WeatherRepository.forecastHorizon);
    final floor = _floor(now);

    final seen = <String>{};
    final out = <_Sample>[];

    for (final entry in eventsByDay.entries) {
      final day = _dayFromKey(entry.key);
      if (day == null) continue;

      for (final event in entry.value) {
        final at = eventSampleTime(event, day);
        if (at.isAfter(horizon)) continue;
        if (at.isBefore(floor)) continue;

        final key = eventWeatherKey(event, day);
        // Two appointments at the same hour in the same place share one
        // reading, and a timed event listed under each day it spans keys on its
        // start either way — so this is a real de-duplication, not a formality.
        if (!seen.add(key)) continue;
        out.add(_Sample(event: event, day: day, at: at, key: key));
      }
    }
    return out;
  }

  /// `CalendarScreenState.key`'s `'y-m-d'`, back into a date.
  static DateTime? _dayFromKey(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }
}

class _Sample {
  final CalendarEvent event;
  final DateTime day;
  final DateTime at;
  final String key;

  const _Sample({required this.event, required this.day, required this.at, required this.key});
}

final weatherRepositoryProvider = Provider<WeatherRepository>((ref) => WeatherRepository());

/// Rebuilt for nothing: it holds no household id and no session of its own, so
/// it survives every profile save and every day the user taps.
///
/// The two `listen`s are deliberately narrow. Watching `calendarProvider` whole
/// would re-run this on the clock tick that drives the "now" line and on every
/// day selection — a resolve pass per tap. `eventsByDay` changes identity only
/// when a refresh lands, and the address only when somebody edits it.
final weatherProvider = StateNotifierProvider<WeatherNotifier, WeatherState>((ref) {
  final notifier = WeatherNotifier(ref.watch(weatherRepositoryProvider));

  void sync() => notifier.sync(
    ref.read(calendarProvider).eventsByDay,
    ref.read(familyProvider).household?.address,
  );

  ref.listen<Map<String, List<CalendarEvent>>>(
    calendarProvider.select((s) => s.eventsByDay),
    (_, _) => sync(),
    fireImmediately: true,
  );
  ref.listen<String?>(
    familyProvider.select((s) => s.household?.address),
    (_, _) => sync(),
  );

  return notifier;
});
