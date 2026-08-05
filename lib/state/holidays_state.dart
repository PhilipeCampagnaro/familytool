import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/german_holidays.dart';
import 'calendar_connections_state.dart';
import 'settings_state.dart';

/// Which Feiertage Kalender marks, for this household.
///
/// Two questions, in this order:
///
/// 1. **Is there a Bundesland?** The Ferien subscription carries one, and it is
///    the only place the app has ever asked for it. A household with it
///    connected gets its state's full list — Fronleichnam in Bayern,
///    Reformationstag in Niedersachsen, Buß- und Bettag in Sachsen.
/// 2. **Otherwise, is this a German household at all?** The interface language
///    is the only signal left, so German means the nine nationwide Feiertage —
///    incomplete, but never wrong — and English means none at all rather than a
///    guess. Device GPS and the household address are deliberately not
///    consulted: neither is worth a network call for a decoration, and the
///    address is free text that may name no country.
///
/// Not a notifier: nothing here is owned or mutated, it is derived. It lives in
/// its own file because it reads the *connections* — putting it in
/// `calendar_state.dart` would point that file back at the one that already
/// imports it.
final germanHolidaysProvider = Provider<GermanHolidays>((ref) {
  for (final connection in ref.watch(calendarConnectionsProvider).connections) {
    final code = connection.ferienBundesland;
    if (code != null) return GermanHolidays(bundesland: code);
  }
  final german = ref.watch(settingsProvider.select((s) => s.language)) == AppLanguage.de;
  return german ? const GermanHolidays() : GermanHolidays.off;
});
