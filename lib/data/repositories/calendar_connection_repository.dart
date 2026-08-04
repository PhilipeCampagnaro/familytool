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
  CalendarConnectionRepository([SupabaseClient? client])
    : _db = client ?? AporahSupabase.client;

  final SupabaseClient _db;

  static const _columns =
      'id, provider, external_account, display_name, status, status_detail, '
      'last_synced_at, created_by, position';

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
            'display_name, created_by, position, '
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

  // -------------------------------------------------------------------------
  // Connect — CalDAV (iCloud, IServ)
  // -------------------------------------------------------------------------

  /// Validates the credentials by listing the account's calendars, and only
  /// stores them if that worked. Returns the calendar names so the UI can show
  /// what was found without a second round trip.
  Future<({String? id, List<String> calendars})> connectCaldav({
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
          (c as Map)['name'] as String? ?? '',
      ]..removeWhere((n) => n.isEmpty),
    );
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
  /// than one collection zone.
  Future<String?> connectAbfall({
    required Map<String, dynamic> config,
    required String label,
    HouseNumber? houseNumber,
  }) async {
    final body = await _invoke('calendar-feed', {
      'provider': 'abfall',
      'label': label,
      'config': {...config, if (houseNumber != null) 'hnrId': houseNumber.id},
    });
    return body['feed_id'] as String?;
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
    final body = await _invoke('abfall-lookup', {
      'action': 'resolve',
      'address': address.toMap(),
    });
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
  Future<void> renameById({
    required String id,
    required bool isFeed,
    required String name,
  }) async {
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
      final res = await _db.functions
          .invoke(name, body: body, queryParameters: query)
          .timeout(timeout);
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
