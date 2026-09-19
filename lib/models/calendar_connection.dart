import 'package:flutter/widgets.dart';
import '../l10n/l10n.dart';
import '../theme/app_icons.dart';

/// The ten calendar sources, spelled exactly as `calendar_connections.provider`
/// and `calendars.provider` store them.
///
/// `outlook` — not `microsoft`. The old web app carried both spellings and
/// needed an `isMicrosoft()` helper in five files to keep them agreeing.
///
/// `ical` is the one without a company behind it: any published ICS link. It
/// shares every line of machinery with the two school providers — the tile
/// exists so that a household with a Verein's fixture list is not told this app
/// only does Google, Outlook and school.
/// `gmx` and `webde` are one system with two brands: 1&1 Mail & Media runs both
/// mailboxes on the same CalDAV server, so they share every line of code and
/// differ in a base URL, a name and a colour. They are here because Google and
/// Apple are not where a German family's calendar necessarily lives.
enum CalendarProvider { google, outlook, icloud, gmx, webde, iserv, webuntis, ical, ferien, abfall }

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

  /// iCloud: an app-specific password typed into the app.
  password,

  /// IServ, WebUntis and any other published feed: a calendar link the user
  /// creates at the source and pastes here.
  ///
  /// "No credential" is how this reads and not what it is — the token in the
  /// URL is the whole capability, which is why it is sealed exactly like a
  /// password (see `calendar_connection_secrets.feed_urls`). What is true is
  /// that there is no login, nothing to expire, and nothing we hold that could
  /// be replayed against the user's account rather than against one calendar.
  ///
  /// This is how school calendars actually work, as opposed to how they look
  /// like they should. IServ's plugin calendars — Aufgaben, Klausuren,
  /// Geburtstage — are module-generated views rather than CalDAV collections,
  /// so a login enumerates the pupil's own empty calendar and the school-wide
  /// `+public` feed and nothing else worth reading. The link the user creates
  /// under Kalender → Einstellungen → Plugins returns exactly the right events.
  /// WebUntis's "Kalender publizieren" mints the same shape of thing.
  ///
  /// There is no API to mint or list those links, so one is pasted per
  /// calendar — which is why a link connection holds several and why the setup
  /// sheet can be re-entered to add another.
  link,

  /// Ferien and Abfall: public feeds, nothing to authenticate with.
  feed,
}

extension CalendarProviderMeta on CalendarProvider {
  String get wire => name;

  String get label => switch (this) {
    CalendarProvider.google => 'Google',
    CalendarProvider.outlook => 'Outlook',
    CalendarProvider.icloud => 'iCloud',
    CalendarProvider.gmx => 'GMX',
    CalendarProvider.webde => 'WEB.DE',
    CalendarProvider.iserv => 'IServ',
    CalendarProvider.webuntis => 'WebUntis',
    CalendarProvider.ical => L.s.providerIcalLabel,
    CalendarProvider.ferien => L.s.providerHolidaysLabel,
    CalendarProvider.abfall => L.s.providerWasteLabel,
  };

  String get blurb => switch (this) {
    CalendarProvider.google => L.s.providerGoogleDesc,
    CalendarProvider.outlook => L.s.providerOutlookDesc,
    CalendarProvider.icloud => L.s.providerIcloudDesc,
    CalendarProvider.gmx => L.s.providerGmxDesc,
    CalendarProvider.webde => L.s.providerWebdeDesc,
    CalendarProvider.iserv => L.s.providerIservDesc,
    CalendarProvider.webuntis => L.s.providerWebuntisDesc,
    CalendarProvider.ical => L.s.providerIcalDesc,
    CalendarProvider.ferien => L.s.providerHolidaysDesc,
    CalendarProvider.abfall => L.s.providerWasteDesc,
  };

  ConnectKind get kind => switch (this) {
    CalendarProvider.google || CalendarProvider.outlook => ConnectKind.oauth,
    CalendarProvider.icloud || CalendarProvider.gmx || CalendarProvider.webde => ConnectKind.password,
    CalendarProvider.iserv || CalendarProvider.webuntis || CalendarProvider.ical => ConnectKind.link,
    CalendarProvider.ferien || CalendarProvider.abfall => ConnectKind.feed,
  };

  /// True where the household connects by pasting a link, which is also where
  /// one account can hold several calendars added one at a time.
  bool get isLinkProvider => kind == ConnectKind.link;

  /// Where the user goes to create the link, in their own words. Rendered as
  /// the numbered steps on the paste screen.
  List<String> get linkSteps => switch (this) {
    CalendarProvider.iserv => L.s.iservLinkSteps,
    CalendarProvider.webuntis => L.s.webuntisLinkSteps,
    // No steps for the generic one, on purpose: there is no single place to
    // send somebody. The paste screen falls back to a sentence about what kind
    // of link is wanted, which is all that can honestly be said.
    _ => const [],
  };

  /// The logo shipped in `assets/calendar_providers/`, or null for the three
  /// providers that are a feed or a link rather than a company.
  String? get asset => switch (this) {
    CalendarProvider.google => 'assets/calendar_providers/google_calendar.png',
    CalendarProvider.outlook => 'assets/calendar_providers/outlook.png',
    CalendarProvider.icloud => 'assets/calendar_providers/icloud_calendar.png',
    CalendarProvider.iserv => 'assets/calendar_providers/iserv.jpg',
    CalendarProvider.webuntis => 'assets/calendar_providers/webuntis.png',
    CalendarProvider.gmx => 'assets/calendar_providers/gmx.png',
    CalendarProvider.webde => 'assets/calendar_providers/webde.png',
    CalendarProvider.ical || CalendarProvider.ferien || CalendarProvider.abfall => null,
  };

  // -- the login step ---------------------------------------------------------
  //
  // Four providers connect by typing something in, and they disagree about
  // every field: what the username is called, what it looks like, whether the
  // password is the account's own, and where an application one is made. That
  // used to be an `isIserv` boolean in the step's build method, which worked
  // for two and would have needed a second boolean for each one after. It is
  // metadata here instead, so the step renders one shape and adding a CalDAV
  // provider is a line per question rather than a condition per field.

  /// What the account is called on the login step — "Apple-ID", "Benutzername",
  /// "E-Mail-Adresse".
  String get loginUserLabel => switch (this) {
    CalendarProvider.iserv => L.s.username,
    CalendarProvider.gmx || CalendarProvider.webde => L.s.emailAddress,
    _ => L.s.appleId,
  };

  /// The greyed example in the username field. A brand's own domain, because
  /// the one thing people get wrong here is typing the local part alone.
  String get loginUserHint => switch (this) {
    CalendarProvider.iserv => 'vorname.nachname',
    CalendarProvider.gmx => 'name@gmx.net',
    CalendarProvider.webde => 'name@web.de',
    _ => L.s.icloudEmailHint,
  };

  /// The sentence under the password field, or null where the account's own
  /// password is what is wanted.
  String? get loginPasswordNote => switch (this) {
    CalendarProvider.iserv => null,
    CalendarProvider.gmx || CalendarProvider.webde => L.s.oneAndOneAppPasswordHint,
    _ => L.s.appPasswordHint,
  };

  String get loginPasswordHint => switch (this) {
    CalendarProvider.iserv => L.s.iservPassword,
    // Apple's app passwords have a shape worth showing; 1&1's do not, so the
    // field says what to type rather than pretending to a format.
    CalendarProvider.gmx || CalendarProvider.webde => L.s.appPasswordPlaceholder,
    _ => 'xxxx-xxxx-xxxx-xxxx',
  };

  /// Where the household goes to mint an application-specific password, or null
  /// for a provider that has none.
  ///
  /// GMX and WEB.DE both file it under Zwei-Faktor-Authentifizierung, so the
  /// link is to the instructions rather than to a settings page that only
  /// exists once 2FA is on.
  String? get appPasswordUrl => switch (this) {
    CalendarProvider.icloud => 'https://appleid.apple.com/account/manage',
    CalendarProvider.gmx => 'https://hilfe.gmx.net/sicherheit/2fa/anwendungsspezifisches-passwort.html',
    CalendarProvider.webde => 'https://hilfe.web.de/sicherheit/2fa/anwendungsspezifisches-passwort.html',
    _ => null,
  };

  /// Whether the login step asks for a server address. IServ alone: every other
  /// provider's is known and is in the CalDAV base-URL table server-side.
  bool get needsServerField => this == CalendarProvider.iserv;

  IconData get icon => switch (this) {
    CalendarProvider.ferien => AppIcons.graduationCap,
    CalendarProvider.abfall => AppIcons.recycle,
    CalendarProvider.webuntis => AppIcons.clock,
    CalendarProvider.ical => AppIcons.calendar,
    _ => AppIcons.calendarDots,
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

  /// The last day an uploaded calendar file has an event on. Null for every
  /// calendar that is fetched rather than held — a link, an account, a public
  /// feed — because those keep themselves current and have no such day.
  ///
  /// It is the one honest thing a snapshot can say about itself: the household
  /// handed us a file, and on this date it stops. Without it the calendar
  /// simply goes quiet and nothing on screen explains why.
  final DateTime? coversTo;

  const RemoteCalendar({required this.externalId, required this.name, this.readOnly = false, this.coversTo});

  static RemoteCalendar? fromMap(Map<String, dynamic> map) {
    final id = map['external_id'] as String?;
    if (id == null || id.isEmpty) return null;
    final name = (map['name'] as String?)?.trim();
    return RemoteCalendar(
      externalId: id,
      name: name == null || name.isEmpty ? id : name,
      readOnly: map['read_only'] == true,
      coversTo: switch (map['covers_to']) {
        final String date when date.isNotEmpty => DateTime.tryParse(date),
        _ => null,
      },
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

  /// True where this account is a set of pasted calendar links rather than a
  /// login — `calendar_connections.auth_type = 'public'`.
  ///
  /// It is what tells the two kinds of IServ connection apart: the older CalDAV
  /// one enumerates the school's collections and cannot be added to, while this
  /// one holds a list the user grows a link at a time. Only the second gets the
  /// "+ Kalender hinzufügen" row.
  final bool isLinked;

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

  /// Provider id -> whose calendar that is: `'family'`, `'member:<user id>'` or
  /// `'person:<Name>'`, with `'*'` standing for every calendar on the account.
  ///
  /// The same grammar the chip row is keyed on, so the value written here is the
  /// chip the calendar lands under. Only the people **without** an account keep
  /// their capitalisation in it — `person:Mia` becomes the `person:mia` group —
  /// because the same child typed twice with different capitals has to end up on
  /// one chip.
  ///
  /// Empty means nobody has decided, and the account's own owner stands: a
  /// WebUntis key scanned for Alice makes her timetable hers with nothing here.
  /// `calendar-events` is what copies the decision onto `calendars.owner_*`; see
  /// the migration for why it does not live on that table directly.
  final Map<String, String> calendarOwners;

  /// Provider id -> the colour this household chose for that calendar, as an
  /// ARGB int, with `'*'` standing for every calendar on the account.
  ///
  /// **Empty is the normal state and means the account's own colour stands.** A
  /// calendar's colour is what a family recognises it by, in their own calendar
  /// app as much as in this one, so the app never picks a different one on their
  /// behalf — not even for Apple's system grey, which iCloud gives "Familie" and
  /// which is nearly invisible on the day grid. That is what this column is for:
  /// the household says so, or nobody does.
  ///
  /// `calendar-events` copies the choice onto `calendars.color` on the next
  /// read; see the migration for why it cannot be written there directly.
  final Map<String, int> calendarColors;

  /// The account's own owner — the default every calendar it produces starts
  /// with, and what [ownerOf] falls back to.
  ///
  /// Set by the connect flow where the flow knows the answer: a WebUntis key is
  /// scanned for one pupil, so [ownerLabel] is that child's given name and every
  /// calendar the key returns is theirs before anybody visits this page. Both
  /// null means the household.
  final String? ownerMemberId;
  final String? ownerLabel;

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
    this.isLinked = false,
    this.selectedCalendars,
    this.calendarNames = const {},
    this.calendarOwners = const {},
    this.calendarColors = const {},
    this.ownerMemberId,
    this.ownerLabel,
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
          name: calendarNames[id]?.trim().isNotEmpty == true ? calendarNames[id]!.trim() : displayName,
        ),
    ];
  }

  /// Whose calendar one of this account's calendars is, in the same grammar the
  /// chip row uses: `'family'`, `'member:<user id>'` or `'person:<Name>'`.
  ///
  /// Three places to look, in the order a decision overrides a default: what the
  /// household chose for this calendar, what they chose for the whole account,
  /// and failing both the account's own owner. Never null — a calendar nobody
  /// has assigned belongs to the household, which is the honest answer and the
  /// one the chip row already shows.
  ///
  /// [externalId] is null for a row that stands for the whole connection.
  String ownerOf(String? externalId) {
    final chosen = calendarOwners[externalId ?? '*'] ?? calendarOwners['*'];
    if (chosen != null && chosen.isNotEmpty) return chosen;

    final member = ownerMemberId;
    if (member != null && member.isNotEmpty) return 'member:$member';

    final label = ownerLabel?.trim();
    return label == null || label.isEmpty ? 'family' : 'person:$label';
  }

  static List<String>? _selectedFrom(Object? raw) {
    if (raw is! List) return null;
    return [
      for (final id in raw)
        if (id is String && id.isNotEmpty) id,
    ];
  }

  /// The same shape as [_namesFrom], for the one map whose values are numbers.
  /// Postgres hands a `jsonb` number back as an `int` or a `double` depending on
  /// how it was written, so both are accepted and anything else is dropped
  /// rather than crashing a screen over one bad row.
  static Map<String, int> _colorsFrom(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        if (entry.key is String && entry.value is num) entry.key as String: (entry.value as num).toInt(),
    };
  }

  static Map<String, String> _namesFrom(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        if (entry.key is String && entry.value is String) entry.key as String: entry.value as String,
    };
  }

  /// The `external_account` of the household's **Abfall file**: the waste
  /// calendar of a town whose provider we may not fetch from, uploaded as a
  /// file. It is Abfall, so it is free and is not counted against the plan's
  /// calendar accounts — here or in `canAddCalendarAccount` on the server,
  /// which holds the same string as `BIN_FILE_ACCOUNT`.
  static const binFileAccount = 'abfall:datei';

  /// Whether this is the Abfall file — see [binFileAccount].
  bool get isBinFile => account == binFileAccount;

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
      isLinked: map['auth_type'] == 'public',
      selectedCalendars: _selectedFrom(map['selected_calendars']),
      calendarNames: _namesFrom(map['calendar_names']),
      calendarOwners: _namesFrom(map['calendar_owners']),
      calendarColors: _colorsFrom(map['calendar_colors']),
      ownerMemberId: map['owner_member_id'] as String?,
      ownerLabel: map['owner_label'] as String?,
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
      // A feed is one calendar, so its owner lives in a column pair on the
      // subscription rather than in a map keyed by the provider's calendar ids
      // — and [ownerOf] falls through to exactly this pair when the map is
      // empty, which for a feed it always is.
      ownerMemberId: map['owner_member_id'] as String?,
      ownerLabel: map['owner_label'] as String?,
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

  const ConnectedCalendar({required this.connection, required this.name, this.externalId});

  /// Unique across the list — a connection id alone repeats once an account
  /// contributes more than one row.
  String get key => externalId == null ? connection.id : '${connection.id}#$externalId';

  /// The colour this household picked for this calendar, or null where they
  /// have not picked one and the account's own stands.
  ///
  /// Falls back to the `'*'` entry the way [CalendarConnection.ownerOf] does:
  /// a connection that yields one calendar is coloured from the row that stands
  /// for the whole account.
  int? get chosenColor => connection.calendarColors[externalId ?? '*'] ?? connection.calendarColors['*'];

  /// True when removing this row means disconnecting the whole account: either
  /// it stands for the connection, or it is the last calendar left on it.
  bool get isWholeConnection => externalId == null || (connection.selectedCalendars?.length ?? 0) <= 1;
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

  /// The two lines a suggestion is drawn in: the street and number, then the
  /// postcode and town. One line of "Adlerstraße 12, 69123 Heidelberg" was cut
  /// off before the town on a phone, and the town is what tells two
  /// Hauptstraßen apart. A bare postcode reads as the postcode over its town.
  String get streetLine {
    if (prefix) return postcode ?? label;
    final line = [street, ?houseNumber].join(' ').trim();
    return line.isEmpty ? label : line;
  }

  String get townLine => prefix ? town : [?postcode, town].join(' ').trim();

  /// Whether the geocoder named the house. A street without one is not an
  /// answer yet: the pickers ask for the number on the spot, because a vendor
  /// that plans per house cannot name a schedule without it.
  bool get hasHouseNumber => (houseNumber ?? '').trim().isNotEmpty;

  /// This street with the number the household typed, labelled as the geocoder
  /// would have labelled it.
  GeoAddress withHouseNumber(String nr) {
    final at = nr.trim();
    return GeoAddress(
      label: [[street, at].join(' '), townLine].where((s) => s.trim().isNotEmpty).join(', '),
      street: street,
      town: town,
      houseNumber: at,
      postcode: postcode,
      state: state,
    );
  }

  /// This address without its house — for handing the number field back.
  GeoAddress get withoutHouseNumber => GeoAddress(
    label: [street, townLine].where((s) => s.trim().isNotEmpty).join(', '),
    street: street,
    town: town,
    postcode: postcode,
    state: state,
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

/// Whether [typed] reads as a German house number: "12", "12a", "12 a",
/// "12-14", "53/1". Checked before the lookup so a slip of the thumb is told
/// about under the field rather than by a vendor that knows no such house.
bool isHouseNumber(String typed) =>
    RegExp(r'^\d{1,4}\s*[a-zA-Z]?(\s*[-/]\s*\d{1,4}\s*[a-zA-Z]?)?$').hasMatch(typed.trim());

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

/// A bin whose collection rhythm the household has to name, because the vendor
/// prints every rhythm side by side and leaves that to the bin sticker —
/// Freiburg's "Restabfalltonne" weekly, fortnightly or four-weekly, Neuss's grey
/// and pink lids. [options] are the ones this address has dates for, never the
/// vendor's full menu. [bin] and each option's [RhythmOption.id] are the
/// vendor's own German words (market data, like the bin keywords) and go back
/// to the server untouched.
class RhythmChoice {
  final String bin;
  final List<RhythmOption> options;

  const RhythmChoice({required this.bin, required this.options});

  /// Null for anything that is not a bin with at least two options: a question
  /// with one answer is not a question.
  static RhythmChoice? fromMap(Map<String, dynamic> map) {
    final bin = map['bin'];
    final raw = map['options'];
    if (bin is! String || bin.isEmpty || raw is! List) return null;
    final options = <RhythmOption>[
      for (final o in raw)
        if (o is Map && o['id'] is String && (o['id'] as String).isNotEmpty)
          RhythmOption(id: o['id'] as String, every: (o['every'] as num?)?.toInt()),
    ];
    return options.length < 2 ? null : RhythmChoice(bin: bin, options: options);
  }
}

/// One answer: the vendor's words, and how many days apart its dates really
/// fall (7, 14, 28) — measured by the server, because "Grau" says nothing.
class RhythmOption {
  final String id;
  final int? every;

  const RhythmOption({required this.id, this.every});
}

/// One Bezirk or Tour of a printed waste plan: a PDF usually holds the whole
/// town, so the household says which one is theirs, helped by the next few
/// dates of each — the same question [RhythmChoice] asks of a bin. [id] goes
/// back to the server as it came.
class PdfDistrict {
  final String id;
  final String label;
  final List<DateTime> next;

  const PdfDistrict({required this.id, required this.label, this.next = const []});

  static List<PdfDistrict> listFrom(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final entry in raw)
        if (entry is Map && entry['id'] != null && entry['label'] is String)
          PdfDistrict(
            id: '${entry['id']}',
            label: entry['label'] as String,
            next: [
              for (final d in (entry['next'] is List ? entry['next'] as List : const []))
                if (d is String && DateTime.tryParse(d) != null) DateTime.parse(d),
            ],
          ),
    ];
  }
}

/// What a town's own calendar page hands out, per the Abfuhrkalender Atlas:
/// a calendar file, a printable PDF plan, dates shown only on the page, or
/// dates only in the town's own app.
enum TownPageFormat {
  ics,
  pdf,
  html,
  app;

  static TownPageFormat? fromWire(Object? raw) => switch (raw) {
    'ics' => ics,
    'pdf' => pdf,
    'html' => html,
    'app' => app,
    _ => null,
  };
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

  /// The vendor plans per house and the address came without a usable house
  /// number — Berlin's BSR, where Karl-Marx-Allee 1, 3 and 12 are three
  /// calendars. [config] is the street and cannot be read yet: the row asks
  /// for the number rather than connecting a calendar that would fail on its
  /// first sync, or show the neighbour's bins. [houseNumbers] may still carry
  /// the choices when the number exists in more than one postcode.
  final bool needsHouseNumber;

  /// Not [supported], and the calendar comes in as a file: the household
  /// downloads it from the town and adds it through the `ical` tile's upload.
  /// Two reasons land here — a provider whose terms or robots.txt rule out
  /// fetching its dates for us (`upload` in the server's `abfall_providers.ts`),
  /// or, with [atlas], a town nobody we read serves at all. [page] is where the
  /// town hands the file out, when known.
  final bool uploadOnly;
  final String? page;

  /// The answer came from the Abfuhrkalender Atlas rather than from a provider:
  /// no vendor refused us, the town simply publishes its own calendar.
  final bool atlas;

  /// What [page] hands out, where the atlas says. It is a researcher's reading
  /// of the page, not a promise, so it shapes the instructions and never takes
  /// a route away.
  final TownPageFormat? format;

  const AbfallCoverage({
    required this.supported,
    required this.town,
    this.street,
    this.houseNumbers = const [],
    this.config,
    this.needsHouseNumber = false,
    this.uploadOnly = false,
    this.page,
    this.atlas = false,
    this.format,
  });

  factory AbfallCoverage.fromMap(Map<String, dynamic> map) => AbfallCoverage(
    supported: map['supported'] == true,
    town: map['town'] as String? ?? '',
    street: map['street'] as String?,
    houseNumbers: _houseNumbers(map['hausNrList']),
    config: map['config'] is Map ? Map<String, dynamic>.from(map['config'] as Map) : null,
    needsHouseNumber: map['needsHouseNumber'] == true,
    uploadOnly: map['uploadOnly'] == true,
    page: _httpsUrl(map['page']),
    atlas: map['atlas'] == true,
    format: TownPageFormat.fromWire(map['format']),
  );

  /// Only an https link is opened from here — it came off the network.
  static String? _httpsUrl(Object? raw) =>
      raw is String && raw.startsWith('https://') && raw.length < 300 ? raw : null;

  /// Whether [config] can be connected as it stands.
  bool get connectable => supported && config != null && !needsHouseNumber;

  /// Both halves of a house number are load-bearing: `nr` is what the chip says
  /// and `id` is what goes back to the vendor, so an entry missing either is not
  /// something we can offer. Skipping it beats throwing — a street-level
  /// schedule is a perfectly good answer, and thirteen vendors' worth of upstream
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

String _foldBundesland(String value) => value.toLowerCase().replaceAll(RegExp(r'[^a-zäöüß]'), '');

/// The Bundesland behind a geocoded address, for the Ferien feed.
///
/// The geocoder's `state` first — and when it named none, the town, but only
/// for the three Stadtstaaten. Photon leaves `state` empty for Berlin and
/// Hamburg, which are one boundary with no admin level above the city to name,
/// so a Berlin address arrived here as "no Bundesland" and the onboarding
/// offered no school holidays for the capital. The lookup function fills the
/// gap on its side too; this is the belt to that suspender.
///
/// Deliberately *not* [bundeslandCodeFor] on the town: that matcher accepts a
/// state's name inside a longer word, and "Sachsenhausen" is in Brandenburg.
String? ferienStateOf(GeoAddress address) =>
    bundeslandCodeFor(address.state) ?? _cityStates[address.town.trim().toLowerCase()];

const _cityStates = <String, String>{
  'berlin': 'BE',
  'hamburg': 'HH',
  'bremen': 'HB',
  'bremerhaven': 'HB',
};
