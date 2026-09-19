import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/calendar_connection.dart';
import '../../services/supabase.dart';
import '../../l10n/l10n.dart';

/// Raised for anything the user should read. The message is always German and
/// always something they can act on — the Edge Functions are written to return
/// exactly that, so this is usually the server's own wording passed through.
class CalendarConnectionException implements Exception {
  final String message;
  const CalendarConnectionException(this.message);

  @override
  String toString() => message;
}

/// The only file in the app that knows how calendar accounts are connected.
///
/// Every write here goes through an Edge Function rather than PostgREST, and
/// that is structural rather than stylistic: `authenticated` has **no INSERT
/// grant** on `calendar_connections` at all. A connection can only be created by
/// a server that has first proved the account works — an OAuth code exchanged,
/// a CalDAV password that answered a PROPFIND, an address that returned real
/// pickup dates. "Verbunden" in this app always means "we reached it just now".
///
/// Reads and deletes are plain PostgREST, because RLS already says exactly what
/// the household may see and remove.
class CalendarConnectionRepository {
  CalendarConnectionRepository([SupabaseClient? client]) : _db = client ?? AporahSupabase.client;

  final SupabaseClient _db;

  static const _columns =
      'id, provider, auth_type, external_account, display_name, status, status_detail, '
      'last_synced_at, created_by, position, selected_calendars, calendar_names, calendar_owners, '
      'calendar_colors, owner_member_id, owner_label';

  // -------------------------------------------------------------------------
  // Read
  // -------------------------------------------------------------------------

  /// Every calendar the household has set up: connected accounts and subscribed
  /// public feeds, in one list because the settings screen shows one list.
  ///
  /// No `family_id` filter on either — the select policies are already scoped to
  /// the caller's household, and the app must not second-guess them.
  Future<List<CalendarConnection>> fetchAll() async {
    final results = await Future.wait([
      _db.from('calendar_connections').select(_columns).order('position'),
      _db
          .from('family_feeds')
          .select(
            'display_name, created_by, position, owner_member_id, owner_label, '
            'public_feeds!inner (id, kind, feed_key, name, status, status_detail, synced_at)',
          )
          .order('position'),
    ]);

    return [
      for (final row in results[0]) ?CalendarConnection.fromMap(Map<String, dynamic>.from(row)),
      for (final row in results[1]) ?CalendarConnection.fromFeed(Map<String, dynamic>.from(row)),
    ];
  }

  // -------------------------------------------------------------------------
  // Connect — OAuth (Google, Outlook)
  // -------------------------------------------------------------------------

  /// The provider's consent URL, to be opened in the system browser.
  ///
  /// The `state` parameter inside it is an encrypted envelope naming the
  /// household, so the callback cannot be pointed at somebody else's family. It
  /// expires after ten minutes, which is also how long this URL stays good.
  Future<String> oauthUrl(CalendarProvider provider) async {
    final body = await _invoke(
      'calendar-connect',
      {'provider': provider.wire},
      query: const {'action': 'start'},
    );
    final url = body['url'] as String?;
    if (url == null || url.isEmpty) {
      throw CalendarConnectionException(L.s.connectionStartFailed);
    }
    return url;
  }

  /// The sub-calendars an *existing* connection offers, asked of the provider
  /// right now.
  ///
  /// CalDAV hands its list back on the connect call itself, but OAuth cannot:
  /// the account is created by the browser callback, which has nobody to answer
  /// to. So the app comes back from the consent screen with a connection and no
  /// idea what is in it, and this is the second round trip that fills the
  /// picker.
  ///
  /// Returns the empty list rather than throwing when the listing fails — the
  /// account is connected either way, and the setup flow simply skips the
  /// picker step and reads every calendar (`selected_calendars` stays null),
  /// which is exactly what it did before there was a picker at all.
  Future<List<RemoteCalendar>> listCalendars(String connectionId) async {
    try {
      final body = await _invoke(
        'calendar-connect',
        {'connection_id': connectionId},
        query: const {'action': 'calendars'},
      );
      return [
        for (final c in (body['calendars'] as List<dynamic>? ?? const []))
          ?RemoteCalendar.fromMap(Map<String, dynamic>.from(c as Map)),
      ];
    } catch (_) {
      return const [];
    }
  }

  // -------------------------------------------------------------------------
  // Connect — CalDAV (iCloud, IServ)
  // -------------------------------------------------------------------------

  /// Validates the credentials by listing the account's calendars, and only
  /// stores them if that worked. Returns the calendar names so the UI can show
  /// what was found without a second round trip.
  Future<({String? id, List<RemoteCalendar> calendars})> connectCaldav({
    required CalendarProvider provider,
    required String username,
    required String password,
    String? server,
  }) async {
    final body = await _invoke('calendar-caldav', {
      'provider': provider.wire,
      'username': username,
      'password': password,
      if (server != null && server.trim().isNotEmpty) 'server': server.trim(),
    });

    return (
      id: body['connection_id'] as String?,
      calendars: [
        for (final c in (body['calendars'] as List<dynamic>? ?? const []))
          ?RemoteCalendar.fromMap(Map<String, dynamic>.from(c as Map)),
      ],
    );
  }

  /// Which of an account's sub-calendars actually sync, and what the household
  /// calls each one.
  ///
  /// The two are written together because they are one decision, taken in one
  /// sheet, before any `calendars` row exists to hold either — see
  /// `calendar_connections.calendar_names`.
  ///
  /// Null and the empty list are **not** the same thing for [externalIds], and
  /// the column is documented that way: null means "never asked", so
  /// `calendar-events` reads everything; `[]` means the user ticked nothing off
  /// and wants none of it. Passing an empty list here therefore has to survive
  /// as an empty array rather than being helpfully turned back into null.
  ///
  /// Only ever a `calendar_connections` id — a feed has no sub-calendars to
  /// choose between.
  Future<void> setCalendarSelection({
    required String id,
    required List<String>? externalIds,
    Map<String, String>? names,
  }) async {
    // The names are left out of the payload entirely when the caller has none
    // to write, rather than sent as null: that is how a connection keeps the
    // names it already had.
    final patch = <String, dynamic>{'selected_calendars': externalIds};
    if (names != null) patch['calendar_names'] = names;

    await _db.from('calendar_connections').update(patch).eq('id', id);
  }

  /// Renames one calendar inside an account.
  ///
  /// A merge rather than a replace: the other calendars on this connection keep
  /// their names, and the map is small enough that reading it from the model the
  /// row was rendered from is honest — nobody else writes it.
  Future<void> renameCalendar({
    required CalendarConnection connection,
    required String externalId,
    required String name,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    await _db
        .from('calendar_connections')
        .update({
          'calendar_names': {...connection.calendarNames, externalId: trimmed},
        })
        .eq('id', connection.id);
  }

  /// Gives one calendar the colour this household wants it in.
  ///
  /// **The app never picks a colour on a household's behalf, so this is the only
  /// way one changes.** A calendar's colour belongs to the account it came from
  /// — it is what a family recognises the calendar by in their own calendar app
  /// as much as in ours — and that holds even when the account's answer is
  /// unhelpful: iCloud calls "Familie" Apple's system grey, which is nearly
  /// invisible on the day grid. Substituting something legible was tried and
  /// rejected; letting them choose is the honest fix.
  ///
  /// A merge into the same kind of map [renameCalendar] and [setCalendarOwner]
  /// write, for the same reason: the other calendars on this account keep their
  /// colour, and nobody else writes this column. [externalId] is null for a row
  /// that stands for the whole connection, stored under `'*'`.
  ///
  /// `calendar-events` copies it onto the `calendars` row — the app holds no
  /// grant on that table at all — so **the new colour appears on the next
  /// calendar read**, not on this call.
  Future<void> setCalendarColor({
    required CalendarConnection connection,
    required String? externalId,
    required int color,
  }) async {
    if (connection.isFeed) return _setFeedColor(connection, color);

    await _db
        .from('calendar_connections')
        .update({
          'calendar_colors': {...connection.calendarColors, externalId ?? '*': color},
        })
        .eq('id', connection.id);
  }

  /// The same for a Ferien or Abfall subscription, which has no connection row
  /// to hold a map.
  ///
  /// A feed is one calendar, so there is nothing to key on and the colour has a
  /// column of its own. It goes on **this household's** `family_feeds` row and
  /// never on the shared `public_feeds` one: the street reads that row too, and
  /// recolouring your bin calendar must not recolour it for the neighbours.
  ///
  /// Scoped by `feed_id` alone, exactly like [_setFeedOwner] beside it — RLS is
  /// what decides which family's subscription row this can reach, and a client
  /// filter would be the tenant check written twice in the weaker place.
  ///
  /// The column is a signed `integer`, and an opaque ARGB colour (`0xFF…`) is
  /// above its range, so the value is wrapped to signed 32-bit first — the same
  /// `| 0` `calendar-events` applies to the map above on its way to
  /// `calendars.color`. Written unwrapped, Postgres refuses every opaque colour.
  Future<void> _setFeedColor(CalendarConnection connection, int color) async {
    await _db.from('family_feeds').update({'color': color.toSigned(32)}).eq('feed_id', connection.id);
  }

  /// Says whose calendar one of an account's calendars is.
  ///
  /// A merge into the same kind of map [renameCalendar] writes, for the same
  /// reason: the other calendars on this account keep their owner, and nobody
  /// else writes this column. [externalId] is null for a row that stands for the
  /// whole connection, which is stored under `'*'` and covers every calendar it
  /// produces.
  ///
  /// [owner] is `'family'`, `'member:<user id>'` or `'person:<Name>'` — the chip
  /// grammar, unchanged, so what is written here is the chip the calendar lands
  /// under. `calendar-events` is what copies it onto the `calendars` row: the
  /// app holds no grant on that table at all, and the chips only change on the
  /// next read for that reason.
  Future<void> setCalendarOwner({
    required CalendarConnection connection,
    required String? externalId,
    required String owner,
  }) async {
    if (connection.isFeed) return _setFeedOwner(connection, owner);

    await _db
        .from('calendar_connections')
        .update({
          'calendar_owners': {...connection.calendarOwners, externalId ?? '*': owner},
        })
        .eq('id', connection.id);
  }

  /// Replaces the whole owner map at once — for renaming or removing a person
  /// without an account, which can touch several of an account's calendars.
  Future<void> setCalendarOwners({required CalendarConnection connection, required Map<String, String> owners}) async {
    await _db.from('calendar_connections').update({'calendar_owners': owners}).eq('id', connection.id);
  }

  /// The same decision for a Ferien or Abfall subscription, which has no
  /// connection row to hold a map.
  ///
  /// A feed is one calendar, so there is nothing to key on and the pair is
  /// written straight out into its own columns — the shape `calendar-events`
  /// copies onto `calendars` for everything else. It goes on **this
  /// household's** `family_feeds` row and never on the shared `public_feeds`
  /// one: the street reads that row too.
  Future<void> _setFeedOwner(CalendarConnection connection, String owner) async {
    final member = owner.startsWith('member:') ? owner.substring('member:'.length).trim() : '';
    final label = owner.startsWith('person:') ? owner.substring('person:'.length).trim() : '';

    await _db
        .from('family_feeds')
        .update({
          'owner_member_id': member.isEmpty ? null : member,
          // 60 characters is what the column's check constraint accepts, and
          // the field this comes from is not limited — a pasted paragraph
          // should file the calendar, not raise.
          'owner_label': label.isEmpty ? null : label.substring(0, label.length.clamp(0, 60)),
        })
        .eq('feed_id', connection.id);
  }

  // -------------------------------------------------------------------------
  // Connect — a pasted calendar link (IServ, WebUntis)
  // -------------------------------------------------------------------------

  /// Checks a pasted link without storing anything, so a typo is reported under
  /// the field it was typed into rather than on the step after it.
  ///
  /// Returns what the feed calls itself, where it says — WebUntis sets
  /// `X-WR-CALNAME`, IServ's plugin feeds do not — and how many events are in
  /// it, which is the one number that tells the user they pasted the right one
  /// of their four IServ links.
  /// [ics] is the other way in: the contents of a `.ics` file the household
  /// picked, for a calendar that is published as a download and not as a link.
  /// Exactly one of [url] and [ics] is sent, and everything after this point —
  /// the check, the sealing, the parse on every refresh — is the same road.
  ///
  /// [pdf] is a third way in, for a town that prints its plan: the file's bytes
  /// in base64, turned into a calendar by the server. A PDF usually holds every
  /// Bezirk or Tour of the town, so the answer lists them as [PdfDistrict]s and
  /// [addCalendarLink] is told which one is the household's. Only sent while
  /// `pdfUploadAvailable` says the server can read one.
  Future<({String? name, int events, DateTime? coversTo, List<PdfDistrict> choices})> checkCalendarLink({
    required CalendarProvider provider,
    String? url,
    String? ics,
    String? pdf,
    String? fileName,
    String? abfallTown,
  }) async {
    final body = await _invoke('calendar-link', {
      'action': 'check',
      'provider': provider.wire,
      if (pdf != null) 'pdf': pdf else if (ics != null) 'ics': ics else 'url': url?.trim() ?? '',
      if (pdf != null) 'file_name': ?fileName,
      'abfall_town': ?abfallTown,
    });
    return (
      name: body['name'] as String?,
      events: (body['events'] as num?)?.toInt() ?? 0,
      coversTo: _dateOrNull(body['covers_to']),
      choices: PdfDistrict.listFrom(body['choices']),
    );
  }

  /// The last day an uploaded calendar has an event on, which is the one thing
  /// a snapshot has to say about itself. Null for a link, which keeps itself
  /// current and has no such day.
  static DateTime? _dateOrNull(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  /// Adds one calendar link, to whichever account it belongs to.
  ///
  /// [account] names the person the account belongs to ("Alice"), and the school
  /// plus that name **is** the account: the function matches on the pair, so the
  /// second link typed under "Alice" joins the calendars already on her card and
  /// a link typed under "Bob" starts his. That is what makes two children at one
  /// school two connections rather than one, and what the chip in Kalender ends
  /// up saying. There is no id to pass — a client that had to know which
  /// connection a link belonged to would be answering a question the name
  /// already answers.
  ///
  /// [ics] replaces [url] for an uploaded file. Re-uploading a file the account
  /// already holds under the same name **replaces** it rather than adding a
  /// second calendar — which is how a household keeps a downloaded Abfuhrplan
  /// current when next year's comes out.
  ///
  /// [abfallTown] marks the file as the household's waste calendar, for a town
  /// whose provider we may not fetch from. The function checks the town and
  /// the file's contents and puts it on the free Abfall-file connection
  /// ([CalendarConnection.binFileAccount]), which the plan does not count.
  ///
  /// [pdf] with [choice] adds the one Bezirk of a printed plan that
  /// [checkCalendarLink] listed; from there it is an uploaded file like any
  /// other.
  Future<({String? connectionId, String? externalId})> addCalendarLink({
    required CalendarProvider provider,
    required String name,
    String? url,
    String? ics,
    String? pdf,
    String? choice,
    String? fileName,
    String? account,
    String? abfallTown,
  }) async {
    final body = await _invoke('calendar-link', {
      'action': 'add',
      'provider': provider.wire,
      if (pdf != null) 'pdf': pdf else if (ics != null) 'ics': ics else 'url': url?.trim() ?? '',
      if (pdf != null) 'choice': ?choice,
      'file_name': ?fileName,
      'name': name.trim(),
      if (account != null && account.trim().isNotEmpty) 'account': account.trim(),
      'abfall_town': ?abfallTown,
    });
    return (connectionId: body['connection_id'] as String?, externalId: body['external_id'] as String?);
  }

  /// Drops one link from an account, and the account with it when it was the
  /// last one.
  ///
  /// Not `setCalendarSelection`: the URL lives in `config`, which
  /// `authenticated` cannot write, so removing it is the function's job too.
  /// Deselecting alone would leave the link stored and the calendar back on the
  /// next tick of the picker.
  Future<void> removeCalendarLink({required String connectionId, required String externalId}) async {
    await _invoke('calendar-link', {
      'action': 'remove',
      'connection_id': connectionId,
      'external_id': externalId,
    });
  }

  // -------------------------------------------------------------------------
  // Subscribe — public feeds (Ferien, Abfall)
  // -------------------------------------------------------------------------

  /// These three subscribe rather than connect.
  ///
  /// Ferien and Abfall are the same data for everybody who wants that
  /// Bundesland or that street, so the function stores the feed once globally
  /// and adds this household to it. The hundredth family in Bremen costs a row,
  /// not another daily scrape of the city's waste site.
  ///
  /// Each returns the feed's id so the caller can refresh straight away — see
  /// [CalendarConnectionsNotifier].
  Future<String?> connectFerien(String stateCode) async {
    final body = await _invoke('calendar-feed', {'provider': 'ferien', 'state': stateCode});
    return body['feed_id'] as String?;
  }

  /// [config] is the vendor configuration the resolve step produced, passed back
  /// exactly as it arrived. [houseNumber] is merged in when the street has more
  /// than one collection zone, and [rhythm] — bin to option, see
  /// [RhythmChoice] — when the vendor makes the household name its own.
  Future<String?> connectAbfall({
    required Map<String, dynamic> config,
    required String label,
    HouseNumber? houseNumber,
    Map<String, String>? rhythm,
  }) async {
    final body = await _invoke('calendar-feed', {
      'provider': 'abfall',
      'label': label,
      'config': abfallConfig(config, houseNumber: houseNumber, rhythm: rhythm),
    });
    return body['feed_id'] as String?;
  }

  /// The config as it goes back to the server: the resolved one plus whatever
  /// the household picked on top of it.
  static Map<String, dynamic> abfallConfig(
    Map<String, dynamic> config, {
    HouseNumber? houseNumber,
    Map<String, String>? rhythm,
  }) => {
    ...config,
    if (houseNumber != null) 'hnrId': houseNumber.id,
    if (rhythm != null && rhythm.isNotEmpty) 'rhythm': rhythm,
  };

  /// The bins whose collection rhythm this address makes the household name,
  /// with only the options it has dates for. Asked once the config names a
  /// whole address — after the house number, where there was one to pick.
  /// Empty almost everywhere.
  Future<List<RhythmChoice>> abfallRhythms(Map<String, dynamic> config) async {
    final body = await _invoke('abfall-lookup', {'action': 'rhythms', 'config': config});
    return [
      for (final c in (body['rhythms'] as List<dynamic>? ?? const []))
        if (c is Map) ?RhythmChoice.fromMap(Map<String, dynamic>.from(c)),
    ];
  }

  // -------------------------------------------------------------------------
  // Abfall address lookup
  // -------------------------------------------------------------------------

  /// Nationwide address autocomplete. Coverage is deliberately *not* checked
  /// here: matching against the vendors' own street lists while typing made
  /// every uncovered address look broken.
  Future<List<GeoAddress>> searchAddresses(String query) async {
    final body = await _invoke('abfall-lookup', {'action': 'search', 'query': query});
    return [
      for (final a in (body['addresses'] as List<dynamic>? ?? const []))
        GeoAddress.fromMap(Map<String, dynamic>.from(a as Map)),
    ];
  }

  /// Is this address served by a vendor we can read? Slow by nature — it fans
  /// out across every provider in the registry — so callers show a spinner.
  Future<AbfallCoverage> resolveAddress(GeoAddress address) async {
    final body = await _invoke('abfall-lookup', {'action': 'resolve', 'address': address.toMap()});
    return AbfallCoverage.fromMap(Map<String, dynamic>.from(body['result'] as Map));
  }

  /// Validates a pasted ICS link by counting the events in it. A link that
  /// parses but yields nothing is the common failure — an authority's landing
  /// page rather than its calendar export.
  Future<bool> checkIcsUrl(String url) async {
    final body = await _invoke('abfall-lookup', {'action': 'ics-check', 'url': url});
    return body['ok'] == true;
  }

  /// The manual fallback for an area no vendor serves yet.
  Future<String?> connectIcs({required String url, required String label}) async {
    final body = await _invoke('calendar-feed', {
      'provider': 'abfall',
      'label': label,
      'config': {'vendor': 'ics', 'url': url},
    });
    return body['feed_id'] as String?;
  }

  // -------------------------------------------------------------------------
  // Refresh and disconnect
  // -------------------------------------------------------------------------

  /// Reads every connected account and every subscribed feed, and reports which
  /// ones failed.
  ///
  /// This does not *store* anything: `calendar-events` proxies the providers and
  /// hands the events straight to the app. What it does persist is each
  /// connection's status, which is what the "Erneut verbinden" banner reads —
  /// so it is still worth calling after a connect, and it is still what "Jetzt
  /// aktualisieren" runs.
  ///
  /// Never throws for a provider that failed. One dead account must not blank
  /// the calendar.
  Future<void> refresh() async {
    // Longer than the rest: this one call fans out across every account and
    // every feed the household has, so it is legitimately the slowest thing
    // here.
    await _invoke('calendar-events', const {}, timeout: const Duration(seconds: 90));
  }

  /// Removes a calendar from this household.
  ///
  /// For a connected account that means the Edge Function, which for OAuth also
  /// tells the provider to invalidate the token — deleting the row alone would
  /// leave a live grant on the user's Google account that the app claims is
  /// gone.
  ///
  /// For a feed it means deleting this household's subscription and nothing
  /// else. The feed row stays: other families are reading it, and it is not
  /// ours to delete. An unsubscribed feed simply stops being refreshed once
  /// nobody opens a calendar that wants it.
  Future<void> disconnect(CalendarConnection connection) async {
    if (connection.isFeed) {
      await _db.from('family_feeds').delete().eq('feed_id', connection.id);
      return;
    }
    await _invoke(
      'calendar-connect',
      {'connection_id': connection.id},
      query: const {'action': 'disconnect'},
    );
  }

  Future<void> rename(CalendarConnection connection, String displayName) =>
      renameById(id: connection.id, isFeed: connection.isFeed, name: displayName);

  /// Renaming by id rather than by [CalendarConnection], for the moment right
  /// after a connect: the connect functions hand back an id, and the row it
  /// names has not been read into a model yet.
  ///
  /// A feed's name is written on *this household's* subscription, never on the
  /// shared `public_feeds` row — calling your bin calendar "Tonne raus" must not
  /// rename it for the rest of the street.
  Future<void> renameById({required String id, required bool isFeed, required String name}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    if (isFeed) {
      await _db.from('family_feeds').update({'display_name': trimmed}).eq('feed_id', id);
      return;
    }
    await _db.from('calendar_connections').update({'display_name': trimmed}).eq('id', id);
  }

  // -------------------------------------------------------------------------

  /// One place where a function's error shape becomes a German message.
  ///
  /// `FunctionException.details` carries the JSON body, which is where every
  /// Aporah function puts its `error`. Without this the user would see
  /// "FunctionException: 400", which tells them nothing about the wrong
  /// password they just typed.
  /// Every call is bounded. A municipal waste server that accepts a connection
  /// and then never answers would otherwise leave the caller's spinner running
  /// for as long as the app is open, with nothing on screen to say so.
  Future<Map<String, dynamic>> _invoke(
    String name,
    Map<String, dynamic> body, {
    Map<String, dynamic>? query,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      final res = await _db.functions.invoke(name, body: body, queryParameters: query).timeout(timeout);
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return const {};
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map && details['error'] is String) {
        throw CalendarConnectionException(details['error'] as String);
      }
      throw CalendarConnectionException(L.s.somethingWentWrong);
    } on TimeoutException {
      throw CalendarConnectionException(L.s.serverTooSlow);
    } catch (_) {
      throw CalendarConnectionException(L.s.noServerConnection);
    }
  }
}
