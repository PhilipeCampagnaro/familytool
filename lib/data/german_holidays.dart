/// The German public holidays (*Feiertage*) — computed, never fetched.
///
/// Unlike the Schulferien, which move every year and are only knowable from
/// OpenHolidays, a Feiertag is fixed in law: nine of them nationwide, the rest
/// per Bundesland, and every single one is either a fixed calendar date or a
/// whole number of days from Easter Sunday. A feed for that would be a network
/// round-trip, a `public_feeds` row and a daily refresh in exchange for an
/// answer arithmetic already has — so this is the one calendar Aporah works out
/// itself. Nothing is stored, nothing is fetched, and it is right offline.
///
/// It carries no names: [GermanHoliday] is an enum and the label comes from
/// `L.s.germanHolidayName`, so this file stays free of the UI language.
library;

/// The Feiertage Aporah knows, in the order they fall in a year.
///
/// Only holidays that are *statutory in a whole Bundesland* are here. The
/// half-measures are deliberately left out: Mariä Himmelfahrt is a holiday in
/// the Catholic municipalities of Bayern and Fronleichnam in a handful of
/// Saxon and Thuringian ones, and both are decided per municipality rather
/// than per state. Marking them everywhere in Bayern would be wrong for most
/// of the state, and Aporah does not know which municipality a household is
/// in — the Bundesland is all it has.
enum GermanHoliday {
  neujahr,
  heiligeDreiKoenige,
  frauentag,
  karfreitag,
  ostersonntag,
  ostermontag,
  tagDerArbeit,
  christiHimmelfahrt,
  pfingstsonntag,
  pfingstmontag,
  fronleichnam,
  mariaeHimmelfahrt,
  weltkindertag,
  deutscheEinheit,
  reformationstag,
  allerheiligen,
  bussUndBettag,
  weihnachtstag1,
  weihnachtstag2,
}

// The Bundesländer each state-specific Feiertag is statutory in, by the same
// two-letter codes `bundeslaender` in models/calendar_connection.dart uses.
const _epiphany = {'BW', 'BY', 'ST'};
const _womensDay = {'BE', 'MV'};

/// Ostersonntag and Pfingstsonntag are ordinary Sundays everywhere except
/// Brandenburg, which names them in its holiday act.
const _sundayHolidays = {'BB'};
const _corpusChristi = {'BW', 'BY', 'HE', 'NW', 'RP', 'SL'};
const _assumption = {'SL'};
const _childrensDay = {'TH'};
const _reformation = {'BB', 'HB', 'HH', 'MV', 'NI', 'SN', 'ST', 'SH', 'TH'};
const _allSaints = {'BW', 'BY', 'NW', 'RP', 'SL'};
const _repentance = {'SN'};

/// Easter Sunday, by the anonymous Gregorian algorithm (Meeus/Jones/Butcher).
/// Every movable Feiertag is an offset from it.
DateTime _easterSunday(int year) {
  final a = year % 19;
  final b = year ~/ 100;
  final c = year % 100;
  final d = b ~/ 4;
  final e = b % 4;
  final f = (b + 8) ~/ 25;
  final g = (b - f + 1) ~/ 3;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4;
  final k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 22 * l) ~/ 451;
  final month = (h + l - 7 * m + 114) ~/ 31;
  final day = ((h + l - 7 * m + 114) % 31) + 1;
  return DateTime(year, month, day);
}

/// Buß- und Bettag: the Wednesday before the 23rd of November, so anywhere
/// from the 16th to the 22nd.
DateTime _repentanceDay(int year) {
  final anchor = DateTime(year, 11, 22);
  final back = (anchor.weekday - DateTime.wednesday + 7) % 7;
  return DateTime(year, 11, 22 - back);
}

/// One year's Feiertage, keyed `month * 100 + day`.
///
/// Date arithmetic goes through `DateTime(year, month, day + n)` rather than
/// `add(Duration(days: n))` on purpose: the latter adds 24-hour spans, so an
/// offset that crosses the March or October clock change lands an hour off and
/// can round to the neighbouring day.
Map<int, GermanHoliday> _computeYear(int year, String? bundesland) {
  final easter = _easterSunday(year);
  DateTime fromEaster(int days) => DateTime(year, easter.month, easter.day + days);

  final out = <int, GermanHoliday>{};
  void add(DateTime day, GermanHoliday holiday) => out[day.month * 100 + day.day] = holiday;
  void addIn(Set<String> states, DateTime day, GermanHoliday holiday) {
    if (bundesland != null && states.contains(bundesland)) add(day, holiday);
  }

  add(DateTime(year, 1, 1), GermanHoliday.neujahr);
  addIn(_epiphany, DateTime(year, 1, 6), GermanHoliday.heiligeDreiKoenige);
  addIn(_womensDay, DateTime(year, 3, 8), GermanHoliday.frauentag);
  add(fromEaster(-2), GermanHoliday.karfreitag);
  addIn(_sundayHolidays, easter, GermanHoliday.ostersonntag);
  add(fromEaster(1), GermanHoliday.ostermontag);
  add(DateTime(year, 5, 1), GermanHoliday.tagDerArbeit);
  add(fromEaster(39), GermanHoliday.christiHimmelfahrt);
  addIn(_sundayHolidays, fromEaster(49), GermanHoliday.pfingstsonntag);
  add(fromEaster(50), GermanHoliday.pfingstmontag);
  addIn(_corpusChristi, fromEaster(60), GermanHoliday.fronleichnam);
  addIn(_assumption, DateTime(year, 8, 15), GermanHoliday.mariaeHimmelfahrt);
  addIn(_childrensDay, DateTime(year, 9, 20), GermanHoliday.weltkindertag);
  add(DateTime(year, 10, 3), GermanHoliday.deutscheEinheit);
  addIn(_reformation, DateTime(year, 10, 31), GermanHoliday.reformationstag);
  addIn(_allSaints, DateTime(year, 11, 1), GermanHoliday.allerheiligen);
  addIn(_repentance, _repentanceDay(year), GermanHoliday.bussUndBettag);
  add(DateTime(year, 12, 25), GermanHoliday.weihnachtstag1);
  add(DateTime(year, 12, 26), GermanHoliday.weihnachtstag2);
  return out;
}

final _yearCache = <String, Map<int, GermanHoliday>>{};

/// Which Feiertage one household sees, and the lookup the calendar asks.
///
/// Built by `germanHolidaysProvider`; the month grid tints the days it names
/// and the day detail prints the name. [bundesland] null means "Germany, but
/// we don't know where" — then only the nine nationwide Feiertage are marked,
/// which is incomplete but never wrong, and a household that connects its
/// Ferien calendar upgrades itself to the full state list for free.
class GermanHolidays {
  /// A two-letter Bundesland code, or null for the nationwide set alone.
  final String? bundesland;

  /// False when Aporah has no reason to believe the household is in Germany,
  /// in which case nothing is marked at all — a Feiertag is a German fact, and
  /// tinting the 3rd of October for a family in Dublin is just noise.
  final bool enabled;

  const GermanHolidays({this.bundesland, this.enabled = true});

  /// Nothing marked, no legend, no tint.
  static const off = GermanHolidays(enabled: false);

  Map<int, GermanHoliday> _year(int year) =>
      _yearCache.putIfAbsent('${bundesland ?? ''}:$year', () => _computeYear(year, bundesland));

  /// The Feiertag falling on this date, or null.
  GermanHoliday? on(int year, int month, int day) => enabled ? _year(year)[month * 100 + day] : null;

  /// This month's Feiertage, keyed by day of the month.
  Map<int, GermanHoliday> inMonth(int year, int month) {
    if (!enabled) return const {};
    final out = <int, GermanHoliday>{};
    _year(year).forEach((key, holiday) {
      if (key ~/ 100 == month) out[key % 100] = holiday;
    });
    return out;
  }

  @override
  bool operator ==(Object other) =>
      other is GermanHolidays && other.bundesland == bundesland && other.enabled == enabled;

  @override
  int get hashCode => Object.hash(bundesland, enabled);
}
