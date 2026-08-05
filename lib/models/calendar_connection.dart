import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../l10n/l10n.dart';

/// The six calendar sources, spelled exactly as `calendar_connections.provider`
/// and `calendars.provider` store them.
///
/// `outlook` — not `microsoft`. The old web app carried both spellings and
/// needed an `isMicrosoft()` helper in five files to keep them agreeing.
enum CalendarProvider { google, outlook, icloud, iserv, ferien, abfall }

CalendarProvider? providerFromWire(String value) {
  for (final p in CalendarProvider.values) {
    if (p.name == value) return p;
  }
  return null;
}

/// How a provider is connected, which is what decides the whole setup flow.
enum ConnectKind {
  /// Google and Outlook: a consent screen in the system browser.
  oauth,

  /// iCloud and IServ: a username and password typed into the app.
  password,

  /// Ferien and Abfall: public feeds, nothing to authenticate with.
  feed,
}

extension CalendarProviderMeta on CalendarProvider {
  String get wire => name;

  String get label => switch (this) {
    CalendarProvider.google => 'Google',
    CalendarProvider.outlook => 'Outlook',
    CalendarProvider.icloud => 'iCloud',
    CalendarProvider.iserv => 'IServ',
    CalendarProvider.ferien => L.s.providerHolidaysLabel,
    CalendarProvider.abfall => L.s.providerWasteLabel,
  };

  String get blurb => switch (this) {
    CalendarProvider.google => L.s.providerGoogleDesc,
    CalendarProvider.outlook => L.s.providerOutlookDesc,
    CalendarProvider.icloud => L.s.providerIcloudDesc,
    CalendarProvider.iserv => L.s.providerIservDesc,
    CalendarProvider.ferien => L.s.providerHolidaysDesc,
    CalendarProvider.abfall => L.s.providerWasteDesc,
  };

  ConnectKind get kind => switch (this) {
    CalendarProvider.google || CalendarProvider.outlook => ConnectKind.oauth,
    CalendarProvider.icloud || CalendarProvider.iserv => ConnectKind.password,
    CalendarProvider.ferien || CalendarProvider.abfall => ConnectKind.feed,
  };

  /// The logo shipped in `assets/calendar_providers/`, or null for the two
  /// providers that are a public feed rather than a company.
  String? get asset => switch (this) {
    CalendarProvider.google => 'assets/calendar_providers/google_calendar.png',
    CalendarProvider.outlook => 'assets/calendar_providers/outlook.png',
    CalendarProvider.icloud => 'assets/calendar_providers/icloud_calendar.png',
    CalendarProvider.iserv => 'assets/calendar_providers/iserv.jpg',
    CalendarProvider.ferien || CalendarProvider.abfall => null,
  };

  IconData get icon => switch (this) {
    CalendarProvider.ferien => LucideIcons.graduationCap,
    CalendarProvider.abfall => LucideIcons.recycle,
    _ => LucideIcons.calendarDays,
  };
}

/// What the sync function last made of a connection. Written only server-side —
/// `authenticated` holds no update grant on these columns.
enum ConnectionStatus { active, reconnectRequired, error }

ConnectionStatus _statusFrom(String? value) => switch (value) {
  'reconnect_required' => ConnectionStatus.reconnectRequired,
  'error' => ConnectionStatus.error,
  _ => ConnectionStatus.active,
};

/// One sub-calendar an account offers, as the connect functions report it.
///
/// Not a row in anything: this is what the provider said it has, on the one
/// round trip that proved the credentials work. Only the ones the user ticks
/// become `calendars` rows, and `calendar_connections.selected_calendars` is
/// where that choice is kept — by [externalId], because the row ids do not
/// exist yet at the moment the choice is made.
class RemoteCalendar {
  /// The provider's own identifier — a CalDAV collection URL, a Google calendar
  /// id. Exactly what goes into `selected_calendars`.
  final String externalId;

  final String name;

  /// Somebody else's system of record — a shared calendar we may read and must
  /// not write. Shown, and still selectable: a family wants to *see* the
  /// Kita's calendar far more often than it wants to write to it.
  final bool readOnly;

  const RemoteCalendar({
    required this.externalId,
    required this.name,
    this.readOnly = false,
  });

  static RemoteCalendar? fromMap(Map<String, dynamic> map) {
    final id = map['external_id'] as String?;
    if (id == null || id.isEmpty) return null;
    final name = (map['name'] as String?)?.trim();
    return RemoteCalendar(
      externalId: id,
      name: name == null || name.isEmpty ? id : name,
      readOnly: map['read_only'] == true,
    );
  }
}

/// One connected account, as the household sees it.
///
/// Deliberately carries no credential of any kind: tokens and CalDAV passwords
/// live in `calendar_connection_secrets`, which is revoked from `authenticated`
/// outright, so there is nothing for this class to accidentally hold.
class CalendarConnection {
  final String id;
  final CalendarProvider provider;

  /// The e-mail, CalDAV username, Bundesland code or resolved Abfall address.
  final String account;

  /// What the user sees and may rename.
  final String displayName;

  final ConnectionStatus status;

  /// German, already user-facing — the sync function writes it that way
  /// precisely so it can be rendered without translation.
  final String? statusDetail;

  final DateTime? lastSyncedAt;
  final String? createdBy;

  /// True for Ferien and Abfall, which are not connections at all but
  /// subscriptions to a feed shared by every household that wants the same
  /// Bundesland or the same street.
  ///
  /// The settings screen renders them identically on purpose — from the user's
  /// side "Abfallkalender verbunden" is the same idea either way — but [id] then
  /// names a `public_feeds` row rather than a `calendar_connections` one, and
  /// disconnecting means dropping this household's subscription, never touching
  /// the feed the rest of the town is reading.
  final bool isFeed;

  /// The provider ids of the sub-calendars this household picked, in the order
  /// it picked them.
  ///
  /// Null is **not** the empty list: null means nobody has been asked yet, and
  /// `calendar-events` reads every calendar the account offers. That is what a
  /// connection made before there was a picker still looks like, and what an
  /// account with nothing to choose between stays as.
  final List<String>? selectedCalendars;

  /// Provider id -> what this household calls that calendar.
  ///
  /// Written by the setup sheet at the same moment as [selectedCalendars],
  /// because a calendar has to be named *before* the first sync creates a row
  /// for it. `calendar-events` copies each name onto `calendars.name`, so this
  /// is what Kalender ends up showing too.
  final Map<String, String> calendarNames;

  const CalendarConnection({
    required this.id,
    required this.provider,
    required this.account,
    required this.displayName,
    required this.status,
    this.statusDetail,
    this.lastSyncedAt,
    this.createdBy,
    this.isFeed = false,
    this.selectedCalendars,
    this.calendarNames = const {},
  });

  bool get needsAttention => status != ConnectionStatus.active;

  /// The Bundesland behind a Ferien subscription, or null for anything else.
  ///
  /// A feed's [account] is its `feed_key` — `ferien:NI` — because the key is
  /// what makes one Schulferien feed shared by every household in that state.
  /// This is the only place in the app that knows a household's Bundesland, so
  /// the Feiertage read it from here; see `germanHolidaysProvider`.
  String? get ferienBundesland {
    if (provider != CalendarProvider.ferien) return null;
    final code = account.split(':').last.trim().toUpperCase();
    return bundeslaender.containsKey(code) ? code : null;
  }

  /// What this connection puts in the "Verbunden" list.
  ///
  /// One row per picked calendar where the household picked any — because two
  /// iCloud calendars are two calendars to the family, not one account — and a
  /// single row standing for the whole connection otherwise. Feeds, IServ
  /// accounts with one collection, and every connection made before the picker
  /// existed take that second path.
  List<ConnectedCalendar> get entries {
    final ids = selectedCalendars;
    if (ids == null || ids.isEmpty) {
      return [ConnectedCalendar(connection: this, name: displayName)];
    }
    return [
      for (final id in ids)
        ConnectedCalendar(
          connection: this,
          externalId: id,
          // A picked calendar is always named by the sheet that picked it. The
          // fallback is for a row written by an older build, where showing the
          // account's name beats showing a CalDAV URL.
          name: calendarNames[id]?.trim().isNotEmpty == true
              ? calendarNames[id]!.trim()
              : displayName,
        ),
    ];
  }

  static List<String>? _selectedFrom(Object? raw) {
    if (raw is! List) return null;
    return [for (final id in raw) if (id is String && id.isNotEmpty) id];
  }

  static Map<String, String> _namesFrom(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String,
    };
  }

  static CalendarConnection? fromMap(Map<String, dynamic> map) {
    final provider = providerFromWire(map['provider'] as String? ?? '');
    // A provider this build does not know about is skipped rather than rendered
    // as a broken row — the column has a check constraint, so this only happens
    // if the server gains one ahead of the app.
    if (provider == null) return null;

    final synced = map['last_synced_at'] as String?;
    return CalendarConnection(
      id: map['id'] as String,
      provider: provider,
      account: map['external_account'] as String? ?? '',
      displayName: map['display_name'] as String? ?? provider.label,
      status: _statusFrom(map['status'] as String?),
      statusDetail: map['status_detail'] as String?,
      lastSyncedAt: synced == null ? null : DateTime.tryParse(synced)?.toLocal(),
      createdBy: map['created_by'] as String?,
      selectedCalendars: _selectedFrom(map['selected_calendars']),
      calendarNames: _namesFrom(map['calendar_names']),
    );
  }

  /// A `family_feeds` row with its `public_feeds` parent embedded.
  ///
  /// The name and colour come from the subscription where the household set
  /// them and from the feed otherwise: renaming your bin calendar must not
  /// rename it for everyone else on the street.
  static CalendarConnection? fromFeed(Map<String, dynamic> map) {
    final feed = map['public_feeds'];
    if (feed is! Map) return null;

    final provider = providerFromWire(feed['kind'] as String? ?? '');
    if (provider == null) return null;

    final synced = feed['synced_at'] as String?;
    return CalendarConnection(
      id: feed['id'] as String,
      provider: provider,
      account: feed['feed_key'] as String? ?? '',
      displayName: (map['display_name'] as String?) ?? (feed['name'] as String?) ?? provider.label,
      // A feed only ever fails by being unreachable, and it keeps serving its
      // last good copy while that lasts — so there is no reconnect state here.
      status: feed['status'] == 'error' ? ConnectionStatus.error : ConnectionStatus.active,
      statusDetail: feed['status_detail'] as String?,
      lastSyncedAt: synced == null ? null : DateTime.tryParse(synced)?.toLocal(),
      createdBy: map['created_by'] as String?,
      isFeed: true,
    );
  }
}

/// One row of the "Verbunden" list: a calendar the household reads, and the
/// connection it came in on.
///
/// A household connects an *account*, but it thinks in calendars — "Familie"
/// and "Arbeit", not "iCloud (name@example.com)". So this is what the settings
/// list is built from, and [externalId] says which of the two kinds it is:
/// non-null for one calendar inside an account, null for a connection that
/// stands for itself (a feed, or an account nobody was asked to choose from).
class ConnectedCalendar {
  final CalendarConnection connection;

  /// The provider's own id, or null when this row *is* the connection.
  final String? externalId;

  final String name;

  const ConnectedCalendar({
    required this.connection,
    required this.name,
    this.externalId,
  });

  /// Unique across the list — a connection id alone repeats once an account
  /// contributes more than one row.
  String get key => externalId == null ? connection.id : '${connection.id}#$externalId';

  /// True when removing this row means disconnecting the whole account: either
  /// it stands for the connection, or it is the last calendar left on it.
  bool get isWholeConnection =>
      externalId == null || (connection.selectedCalendars?.length ?? 0) <= 1;
}

// ---------------------------------------------------------------------------
// Abfall
// ---------------------------------------------------------------------------

/// One address suggestion from the geocoder.
///
/// Opaque on purpose beyond [label]: it is handed straight back to the resolve
/// call, and the fields the vendors need are the geocoder's, not ours to
/// reinterpret.
class GeoAddress {
  final String label;
  final String street;
  final String? houseNumber;
  final String town;
  final String? postcode;

  /// The Bundesland, when the geocoder knows it — the one piece the app reads
  /// itself, to offer the matching Ferien calendar after an Abfall setup.
  final String? state;

  /// A bare postcode typed into the field ("28213") comes back as a suggestion
  /// naming its town rather than an address. Picking it refills the field so the
  /// user carries on typing their street; it can never be resolved.
  final bool prefix;

  const GeoAddress({
    required this.label,
    required this.street,
    required this.town,
    this.houseNumber,
    this.postcode,
    this.state,
    this.prefix = false,
  });

  factory GeoAddress.fromMap(Map<String, dynamic> map) => GeoAddress(
    label: map['label'] as String? ?? '',
    street: map['street'] as String? ?? '',
    town: map['town'] as String? ?? '',
    houseNumber: map['houseNumber'] as String?,
    postcode: map['postcode'] as String?,
    state: map['state'] as String?,
    prefix: map['prefix'] == true,
  );

  Map<String, dynamic> toMap() => {
    'label': label,
    'street': street,
    'town': town,
    if (houseNumber != null) 'houseNumber': houseNumber,
    if (postcode != null) 'postcode': postcode,
    if (state != null) 'state': state,
    if (prefix) 'prefix': true,
  };
}

/// One selectable house number on a resolved street.
class HouseNumber {
  /// Numeric only for regio-iT. AWIDO sends an addon GUID, abfall.io a form
  /// option value, jumomind a packed "nr|areaId" — so this stays whatever the
  /// vendor sent and is passed back untouched. Narrowing it to an int would
  /// silently drop every house number outside one vendor family.
  final Object id;
  final String nr;

  const HouseNumber({required this.id, required this.nr});
}

/// Whether a picked address is served by a waste vendor we can read.
class AbfallCoverage {
  final bool supported;

  /// The town actually looked up — for the "noch nicht unterstützt" line, which
  /// may name a different place than the user typed once the postcode fallback
  /// has resolved a district to its municipality.
  final String town;

  /// The vendor's canonical spelling of the street ("Weyher Str. [Brinkum]").
  final String? street;

  final List<HouseNumber> houseNumbers;

  /// The vendor configuration, opaque to the app and stored as-is on the
  /// connection. Nothing here is a credential — these APIs are all keyless.
  final Map<String, dynamic>? config;

  const AbfallCoverage({
    required this.supported,
    required this.town,
    this.street,
    this.houseNumbers = const [],
    this.config,
  });

  factory AbfallCoverage.fromMap(Map<String, dynamic> map) => AbfallCoverage(
    supported: map['supported'] == true,
    town: map['town'] as String? ?? '',
    street: map['street'] as String?,
    houseNumbers: _houseNumbers(map['hausNrList']),
    config: map['config'] is Map
        ? Map<String, dynamic>.from(map['config'] as Map)
        : null,
  );

  /// Both halves of a house number are load-bearing: `nr` is what the chip says
  /// and `id` is what goes back to the vendor, so an entry missing either is not
  /// something we can offer. Skipping it beats throwing — a street-level
  /// schedule is a perfectly good answer, and six vendors' worth of upstream
  /// JSON is not a contract. regio-iT does send entries without an `id`, and the
  /// cast that used to sit here threw a `TypeError` past the connect screen's
  /// `on CalendarConnectionException` handler, which left the address row
  /// spinning "Entsorger wird gesucht …" for ever.
  static List<HouseNumber> _houseNumbers(Object? raw) {
    if (raw is! List) return const [];
    final out = <HouseNumber>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final id = entry['id'];
      final nr = entry['nr'];
      if (id == null || nr is! String || nr.trim().isEmpty) continue;
      out.add(HouseNumber(id: id, nr: nr));
    }
    return out;
  }
}

/// The sixteen Bundesländer, keyed by the code OpenHolidays wants. Mirrors the
/// allowlist in the `calendar-feed` function — a well-formed code for a state
/// that does not exist comes back as an empty holiday list, which is
/// indistinguishable from "no holidays this year".
const bundeslaender = <String, String>{
  'BW': 'Baden-Württemberg',
  'BY': 'Bayern',
  'BE': 'Berlin',
  'BB': 'Brandenburg',
  'HB': 'Bremen',
  'HH': 'Hamburg',
  'HE': 'Hessen',
  'MV': 'Mecklenburg-Vorpommern',
  'NI': 'Niedersachsen',
  'NW': 'Nordrhein-Westfalen',
  'RP': 'Rheinland-Pfalz',
  'SL': 'Saarland',
  'SN': 'Sachsen',
  'ST': 'Sachsen-Anhalt',
  'SH': 'Schleswig-Holstein',
  'TH': 'Thüringen',
};

/// The [bundeslaender] code behind whatever the geocoder called the state, or
/// null when it named none of them — the step from a picked address to the
/// Schulferien feed that fits it, so onboarding never has to make somebody pick
/// their own Bundesland off a list of sixteen.
///
/// Deliberately forgiving about the spelling. Photon answers with the plain
/// German name ("Niedersachsen"), but the same field carries official forms
/// ("Freistaat Bayern", "Freie Hansestadt Bremen") depending on what OSM has
/// for that address, so the comparison ignores case, spaces and punctuation and
/// then falls back to containment.
///
/// The fallback matches the **longest** name it can, which is the whole reason
/// it is written that way: "Sachsen-Anhalt" contains "Sachsen", and picking the
/// first hit would subscribe half of Saxony-Anhalt to the wrong state's school
/// holidays.
String? bundeslandCodeFor(String? state) {
  final raw = state?.trim() ?? '';
  if (raw.isEmpty) return null;
  if (bundeslaender.containsKey(raw.toUpperCase())) return raw.toUpperCase();

  final needle = _foldBundesland(raw);
  if (needle.isEmpty) return null;

  String? best;
  var bestLength = 0;
  for (final entry in bundeslaender.entries) {
    final name = _foldBundesland(entry.value);
    if (name == needle) return entry.key;
    if (needle.contains(name) && name.length > bestLength) {
      best = entry.key;
      bestLength = name.length;
    }
  }
  return best;
}

String _foldBundesland(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-zäöüß]'), '');
