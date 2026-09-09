import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/repositories/calendar_connection_repository.dart';
import '../models/calendar_connection.dart';
import '../models/who.dart';
import '../services/code_scanner.dart';
import '../services/external_links.dart';
import '../state/calendar_connections_state.dart';
import '../state/family_state.dart';
import '../theme/tokens.dart';
import '../widgets/anchored_menu.dart';
import '../widgets/app_sheet.dart';
import '../widgets/avatar.dart';
import '../widgets/confirmation.dart';
import '../widgets/rename_sheet.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_note.dart';
import '../widgets/icon_tile.dart';
import '../widgets/settings_chrome.dart';
import '../widgets/step_dots.dart';
import '../widgets/swipe_actions.dart';
import '../widgets/toast_chip.dart';
import '../l10n/l10n.dart';

/// Settings → Kalender. The six providers, each saying whether this household
/// has connected it.
///
/// Deliberately *only* the providers: the connected calendars themselves live
/// one tap down, on the page of the provider they belong to, and the badge on
/// the row already says how many that is. A "Verbunden" list up here as well
/// said the same thing twice — a household with the bin calendar and two
/// Bundesländer read its own calendars back before reaching the list of what it
/// could add.
///
/// Two providers — Ferien and Abfall — need no credentials at all, which makes
/// them the only ones testable before anything has been registered with Google
/// or Microsoft. They are listed first for that reason.
class CalendarConnectionsPage extends ConsumerWidget {
  const CalendarConnectionsPage({super.key});

  static const _order = [
    CalendarProvider.abfall,
    CalendarProvider.ferien,
    CalendarProvider.google,
    CalendarProvider.outlook,
    CalendarProvider.icloud,
    CalendarProvider.iserv,
    CalendarProvider.webuntis,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(calendarConnectionsProvider);
    final notifier = ref.read(calendarConnectionsProvider.notifier);
    final isKid = ref.watch(myRoleProvider) == FamilyRole.kid;

    return SettingsDetailPage(
      icon: LucideIcons.calendarDays,
      title: L.s.connectCalendars,
      description: L.s.connectCalendarsIntro,
      children: [
        if (state.error case final message?) ...[
          ErrorNote(message: message, onRetry: notifier.load),
          const SizedBox(height: AppSpacing.blockGap),
        ],

        // A kid may look, not connect — so they get the plain list of what the
        // household reads, without the six ways of adding another.
        if (isKid) ...[
          GroupLabel(L.s.connected),
          SectionCard(
            radius: AppRadii.card,
            children: !state.loaded
                // An empty list may mean "not loaded yet" rather than "nothing
                // connected", and the card is the only place that can tell the
                // two apart without a second block on the page.
                ? [_BusyRow(L.s.loadingEllipsis)]
                : state.connections.isEmpty
                ? [
                    EmptyState(
                      icon: LucideIcons.calendarPlus,
                      message: L.s.noCalendarsConnected,
                      verticalPadding: 34,
                    ),
                  ]
                : dividedRows(inset: true, [
                    // Same rows the admin sees on the provider pages, minus the
                    // menu: a calendar each, not an account each.
                    for (final connection in state.connections)
                      for (final entry in connection.entries)
                        SettingsRow(
                          leading: _ProviderTile(connection.provider),
                          title: entry.name,
                          subtitle: lastSyncedLabel(connection.lastSyncedAt),
                          trailing: const _CheckBadge(),
                        ),
                  ]),
          ),
          const SizedBox(height: AppSpacing.blockGap),
          SettingsNote(L.s.connectCalendarsAdminNote),
        ] else
          SectionCard(
            radius: AppRadii.card,
            children: dividedRows(inset: true, [
              for (final provider in _order)
                SettingsRow(
                  leading: _ProviderTile(provider),
                  title: provider.label,
                  subtitle: provider.blurb,
                  accessory: _ProviderStatus(state.of(provider)),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => _ProviderPage(provider)),
                  ),
                ),
            ]),
          ),

        // No "Alle Kalender aktualisieren" anywhere in here: opening Kalender
        // already calls `calendar-events`, which is the same read — it goes out
        // to every account and feed and writes back each connection's status. A
        // button that repeats what the app does on its own only teaches people
        // that a connection needs tending.
      ],
    );
  }
}

/// One provider: its hero, what this household has connected of it, and the one
/// button that adds another.
///
/// Every provider page is that same three-part shape, however differently the
/// six actually connect. The button **starts the provider's own first step**
/// rather than opening something that then offers to start it: for Google and
/// Outlook that first step is the consent screen, so the button says "Mit
/// Google anmelden" and goes straight there — the sheet it used to open held
/// one button and nothing else, which is a popup asking permission to ask.
/// The other three have a real question (a login, a Bundesland, an address),
/// and that is what [showCalendarConnectSheet] is for.
///
/// So the OAuth half of the flow lives here rather than in the sheet: the trip
/// out to Safari, the wait for the app to come back, and the reading of what
/// came with it. Only once there *is* an account does the sheet open, on the
/// first thing left to ask.
class _ProviderPage extends ConsumerStatefulWidget {
  final CalendarProvider provider;
  const _ProviderPage(this.provider);

  @override
  ConsumerState<_ProviderPage> createState() => _ProviderPageState();
}

class _ProviderPageState extends ConsumerState<_ProviderPage> with WidgetsBindingObserver {
  CalendarProvider get _provider => widget.provider;
  bool get _isOAuth => _provider.kind == ConnectKind.oauth;

  bool _opening = false;
  bool _awaitingReturn = false;

  /// Between coming back from the consent screen and the sheet opening there is
  /// a round trip to the provider for its calendar list, and it is the slowest
  /// part of the whole flow — a Google account with a dozen calendars takes a
  /// moment. Without this the button sits there saying "Mit Google anmelden" as
  /// if nothing had happened.
  bool _loadingCalendars = false;

  String? _error;

  /// The connections that existed before we sent the user to the consent
  /// screen, so what came back can be told apart from what was already there.
  Set<String> _knownIds = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The consent screen runs in Safari, so the app has no callback to await.
  /// Coming back to the foreground *after* we sent someone out is the signal
  /// that something may have changed — re-read rather than guess.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingReturn) {
      _awaitingReturn = false;
      unawaited(_afterConsent());
    }
  }

  void _openSheet({
    CalendarConnection? connection,
    List<RemoteCalendar> calendars = const [],
    String? addToConnectionId,
  }) {
    showCalendarConnectSheet(
      context,
      ref,
      _provider,
      connection: connection,
      calendars: calendars,
      addToConnectionId: addToConnectionId,
    );
  }

  /// The CalDAV login, for the one provider that still has one.
  ///
  /// Reached only from the note under the link flow, never as the first thing
  /// on the page: a school that has enabled CalDAV publishes its class and
  /// group collections there, but never the plugin calendars — Aufgaben,
  /// Klausuren, Geburtstage are module views with no collection behind them —
  /// so a login alone is exactly the empty calendar this whole flow replaced.
  void _openLoginSheet() {
    showCalendarConnectSheet(context, ref, _provider, useCaldavLogin: true);
  }

  /// The pasted link, for the one provider whose main route is a scan.
  ///
  /// Reached only from the note at the bottom, because it is the lesser of the
  /// two: "Kalender publizieren" hands out a flat ICS feed, so a lesson that was
  /// cancelled arrives looking exactly like a lesson that was not. It exists for
  /// the school that has turned Untis Mobile access off, where there is no QR
  /// code to show.
  void _openLinkSheet() {
    showCalendarConnectSheet(context, ref, _provider, useLinkFallback: true);
  }

  Future<void> _start() async {
    if (!_isOAuth) {
      _openSheet();
      return;
    }

    setState(() {
      _opening = true;
      _error = null;
    });

    _knownIds = {for (final c in ref.read(calendarConnectionsProvider).of(_provider)) c.id};

    try {
      final url = await ref.read(calendarConnectionsProvider.notifier).oauthUrl(_provider);
      if (!mounted) return;

      if (url == null) {
        setState(() {
          _opening = false;
          _error = ref.read(calendarConnectionsProvider).error ??
              L.s.providerNotSetUp(_provider.label);
        });
        return;
      }

      final opened = await openExternalUrl(url);
      if (!mounted) return;
      setState(() {
        _opening = false;
        _awaitingReturn = opened;
        _error = opened ? null : L.s.browserCouldNotOpen;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _opening = false;
        _error = connectErrorText(e);
      });
    }
  }

  /// Back from the browser: read the list, and if a connection appeared, hand
  /// it to the sheet with whatever calendars the account offers.
  ///
  /// The calendar list is a second round trip here, where CalDAV gets it back
  /// from the connect call itself: an OAuth account is created by the browser
  /// callback, which has no way to hand anything to the app. It is allowed to
  /// come back empty — the sheet then simply has one step fewer.
  Future<void> _afterConsent() async {
    final notifier = ref.read(calendarConnectionsProvider.notifier);
    await notifier.load();
    if (!mounted) return;

    final fresh = [
      for (final c in ref.read(calendarConnectionsProvider).of(_provider))
        if (!_knownIds.contains(c.id)) c,
    ];
    // Cancelled at the consent screen, or the callback has not landed yet.
    if (fresh.isEmpty) return;

    final connection = fresh.first;
    setState(() => _loadingCalendars = true);
    final calendars = await notifier.listCalendars(connection.id);
    if (!mounted) return;
    setState(() => _loadingCalendars = false);

    _openSheet(connection: connection, calendars: calendars);
  }

  @override
  Widget build(BuildContext context) {
    final connections = ref.watch(calendarConnectionsProvider).of(_provider);
    final working = _opening || _loadingCalendars;

    return SettingsDetailPage(
      icon: _provider.icon,
      title: _provider.label,
      description: _provider.blurb,
      // The only Settings page pushed from something other than the root.
      parentTitle: L.s.connectCalendars,
      // Pinned rather than the last thing in the list: this is the whole point
      // of the page, and on a provider with one calendar connected it used to
      // sit halfway up the screen with nothing under it.
      bottomAction: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The footer iOS puts under a control, saying where the button leads
          // — and, once it has led there, what to do about it. Above the pill
          // now that the pill is against the bottom edge, which is where a
          // disclaimer about what a button does belongs anyway.
          if (_isOAuth) ...[
            SettingsNote(
              _awaitingReturn
                  ? L.s.comeBackWhenDone
                  : L.s.redirectNotice(
                      _provider == CalendarProvider.google ? 'Google' : 'Microsoft',
                    ),
            ),
            const SizedBox(height: AppSpacing.blockGap),
          ],
          AccentAction(
            icon: _isOAuth
                ? (working ? LucideIcons.loaderCircle : LucideIcons.externalLink)
                : LucideIcons.plus,
            label: _isOAuth
                ? (_opening
                      ? L.s.openingEllipsis
                      : _loadingCalendars
                      ? L.s.loadingCalendarsEllipsis
                      : L.s.signInWithProvider(_provider.label))
                : L.s.connect,
            onTap: working ? () {} : _start,
          ),
        ],
      ),
      children: [
        if (connections.isEmpty)
          // Not "nothing at all until you connect one": a hero, a lot of gray
          // and a button reads as a page that failed to load. The card holds
          // the same place the connections will, so the page keeps its shape
          // once there is one, and the glyph is accent because this state is an
          // invitation to press the button under it.
          SectionCard(
            radius: AppRadii.card,
            children: [
              EmptyState(
                icon: LucideIcons.calendarPlus,
                iconColor: Theme.of(context).colorScheme.primary,
                message: L.s.noProviderCalendarYet(_provider.label),
                verticalPadding: 40,
              ),
            ],
          )
        else if (_provider.isLinkProvider || connections.any((c) => c.isLinked))
          // One card per *account*, because that is what a link provider is:
          // Alice's IServ holds her Aufgaben, her Klausurplan and her
          // Klassenkalender, and each of them was pasted separately. A flat
          // list would say "IServ" six times for two children and give the
          // "+ Kalender hinzufügen" row nothing to belong to.
          //
          // Keyed off the connections as well as the provider, because WebUntis
          // is now two kinds at once: an account connected by its app secret
          // holds one timetable and nothing to add to it, while a link account
          // made before that existed still grows a calendar at a time. The
          // second condition is what keeps those older accounts whole.
          for (final connection in connections) ...[
            GroupLabel(connection.displayName),
            SectionCard(
              radius: AppRadii.card,
              children: dividedRows(inset: true, [
                for (final entry in connection.entries)
                  _ConnectedRow(key: ValueKey(entry.key), entry: entry),
                if (connection.isLinked)
                  SettingsRow(
                    icon: LucideIcons.plus,
                    title: L.s.addAnotherCalendar,
                    subtitle: L.s.addAnotherCalendarBody,
                    onTap: () => _openSheet(addToConnectionId: connection.id),
                  ),
              ]),
            ),
            const SizedBox(height: AppSpacing.blockGap),
          ]
        else ...[
          GroupLabel(L.s.connected),
          SectionCard(
            radius: AppRadii.card,
            children: dividedRows(inset: true, [
              // One row per *calendar*, so an account with two of them ticked
              // reads as the two calendars the household picked rather than as
              // the account it reached them through.
              for (final connection in connections)
                for (final entry in connection.entries)
                  _ConnectedRow(key: ValueKey(entry.key), entry: entry),
            ]),
          ),
        ],
        if (_error case final message?) ...[
          const SizedBox(height: AppSpacing.blockGap),
          ErrorNote(message: message),
        ],
        if (_provider.hasCaldavFallback) ...[
          const SizedBox(height: AppSpacing.blockGap),
          SectionCard(
            radius: AppRadii.card,
            children: dividedRows(inset: true, [
              SettingsRow(
                icon: LucideIcons.keyRound,
                title: L.s.connectWithLogin,
                subtitle: L.s.connectWithLoginBody,
                onTap: _openLoginSheet,
              ),
            ]),
          ),
        ] else if (_provider.hasLinkFallback) ...[
          const SizedBox(height: AppSpacing.blockGap),
          SectionCard(
            radius: AppRadii.card,
            children: dividedRows(inset: true, [
              SettingsRow(
                icon: LucideIcons.link,
                title: L.s.connectWithLink,
                subtitle: L.s.connectWithLinkBody,
                onTap: _openLinkSheet,
              ),
            ]),
          ),
        ],
      ],
    );
  }
}

String lastSyncedLabel(DateTime? at) {
  if (at == null) return L.s.notSyncedYet;
  final ago = DateTime.now().difference(at);
  if (ago.inMinutes < 2) return L.s.syncedJustNow;
  if (ago.inHours < 1) return L.s.syncedMinutesAgo(ago.inMinutes);
  if (ago.inDays < 1) return L.s.syncedHoursAgo(ago.inHours);
  return L.s.syncedDaysAgo(ago.inDays);
}

/// One place where a failed connect becomes a German sentence, for the confirm
/// sheet — which is generic and knows nothing about calendars.
///
/// Every `catch` on this screen goes through here, and catches everything rather
/// than naming [CalendarConnectionException]: a handler that names one exception
/// type is how a spinner ends up running for ever, because the one error nobody
/// predicted — a vendor's JSON in a shape the parser didn't expect, say — walks
/// straight past it and leaves the busy flag set.
String connectErrorText(Object error) {
  if (error is CalendarConnectionException) return error.message;
  debugPrint('Kalender-Verbindung: unerwarteter Fehler — $error');
  return L.s.somethingWentWrong;
}

/// The pupil's own name out of what WebUntis calls them, for the suggested
/// calendar name.
///
/// The **last** word, not the first: Untis writes `displayName` surname-first —
/// "Boff Campagnaro Alice" is Alice, with two surnames — which is the German
/// school convention and what a live account shows. A school that has
/// configured it the other way round gets the surname suggested instead, which
/// is odd rather than wrong, and the field it lands in is a text field the
/// parent is already looking at.
String _pupilShortName(String displayName) {
  final parts = displayName.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  return parts.isEmpty ? displayName : parts.last;
}

CalendarConnection? _byId(List<CalendarConnection> connections, String id) {
  for (final connection in connections) {
    if (connection.id == id) return connection;
  }
  return null;
}

/// The circular logo tile, matching the family avatars in size and border.
class _ProviderTile extends StatelessWidget {
  final CalendarProvider provider;
  const _ProviderTile(this.provider);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: AppColors.brandTile,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.hairline),
      ),
      alignment: Alignment.center,
      child: provider.asset != null
          ? ClipOval(child: Image.asset(provider.asset!, width: 24, height: 24, fit: BoxFit.cover))
          : Icon(provider.icon, size: 17, color: AppColors.inkSecondary),
    );
  }
}

/// What a provider row says about itself: nothing at all when there is nothing
/// connected, a count when there is more than one, and the warning when the
/// sync function has flagged one of them.
class _ProviderStatus extends StatelessWidget {
  final List<CalendarConnection> connections;
  const _ProviderStatus(this.connections);

  @override
  Widget build(BuildContext context) {
    if (connections.isEmpty) return const SizedBox.shrink();

    final accent = Theme.of(context).colorScheme.primary;
    final attention = connections.any((c) => c.needsAttention);
    final color = attention ? AppColors.danger : accent;
    // Calendars, not accounts: one Apple ID with "Familie" and "Arbeit" ticked
    // is two rows on the page this badge introduces, so a badge counting
    // accounts would promise one and open on two.
    final count = connections.fold(0, (total, c) => total + c.entries.length);
    final label = attention
        ? L.s.actionNeeded
        : count == 1
        ? L.s.connected
        : L.s.calendarCount(count);

    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadii.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(attention ? LucideIcons.triangleAlert : LucideIcons.check, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppText.microLabel.copyWith(color: color, letterSpacing: 0.1),
          ),
        ],
      ),
    );
  }
}

/// The blue tick beside a calendar that is connected and healthy.
class _CheckBadge extends StatelessWidget {
  const _CheckBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: const Icon(LucideIcons.check, size: 13, color: Colors.white),
    );
  }
}

// ---------------------------------------------------------------------------
// Adding one — one sheet, one flow
// ---------------------------------------------------------------------------

/// Everything a provider still has to ask, in **one** sheet: a login, a
/// Bundesland, an address, which calendars, what to call it, and the beat that
/// says it worked. The dots at the top say how many of those there are, so the
/// first question never reads as the last one.
///
/// One sheet is the rule, not a preference. Every flow in here used to end by
/// opening a *second* sheet over the first — the address sheet with the "Abfall
/// verbinden" sheet on top of it — which stacked two grab handles, two headers
/// and two X's, and left the question behind still showing through the gap. A
/// step is not a new surface: [_ConnectFlow] moves the sheet from one to the
/// next, and the only thing that ever opens over this is nothing.
///
/// [connection] and [calendars] are for the providers whose first step happens
/// before the sheet exists: Google and Outlook come back from the consent
/// screen with an account already made, so their sheet opens on the picker.
/// The other four start at their own first question and fill these in on the
/// way — or, for the two feeds, never: a feed has no account, and the last step
/// is what creates it.
Future<void> showCalendarConnectSheet(
  BuildContext context,
  WidgetRef ref,
  CalendarProvider provider, {
  CalendarConnection? connection,
  List<RemoteCalendar> calendars = const [],
  String? addToConnectionId,
  bool useCaldavLogin = false,
  bool useLinkFallback = false,
}) async {
  final flow = _ConnectFlow(
    provider: provider,
    notifier: ref.read(calendarConnectionsProvider.notifier),
    repository: ref.read(calendarConnectionRepositoryProvider),
    // What the CalDAV login gets back is an id; the row it names is in state,
    // which is the page's to read, not the flow's.
    findConnection: (id) => _byId(ref.read(calendarConnectionsProvider).connections, id),
    // Read once, when the sheet opens: the roster is only consulted to see
    // whether the child being connected already has an account here.
    members: ref.read(householdMembersProvider),
    connection: connection,
    calendars: calendars,
    addToConnectionId: addToConnectionId,
    useCaldavLogin: useCaldavLogin,
    useLinkFallback: useLinkFallback,
  );

  await showAppSheet<void>(
    context: context,
    // Tall enough for a dozen calendar rows, and for the name field to clear
    // the keyboard on the step after them.
    heightFactor: 0.86,
    header: _ConnectHeader(flow: flow, title: L.s.connectProvider(provider.label)),
    child: _ConnectBody(flow: flow),
  );

  // Not disposed on the spot: the sheet's own widgets are still mounted — and
  // still reading the controllers — while the route animates out.
  unawaited(Future<void>.delayed(const Duration(milliseconds: 400), flow.dispose));
}

/// One connected calendar: its name, when it last synced, a blue tick — and the
/// two things you can do to it, behind the "…" or a swipe.
///
/// A *calendar*, not an account. An Apple ID with "Familie" and "Arbeit" ticked
/// is two rows here, because that is what the household connected and how it
/// thinks about them — one row saying "iCloud (name@example.com)" answered a
/// question nobody asked. [ConnectedCalendar] is what does the splitting; a feed
/// and an account nobody had anything to pick from stay one row, as they always
/// were.
///
/// The actions used to be two extra rows under every single connection, which
/// is how a household with three Ferien-Kalendern ended up with nine rows for
/// three calendars. Renaming and removing are things done *to* a row, so they
/// belong on the row.
class _ConnectedRow extends ConsumerStatefulWidget {
  final ConnectedCalendar entry;

  const _ConnectedRow({super.key, required this.entry});

  @override
  ConsumerState<_ConnectedRow> createState() => _ConnectedRowState();
}

class _ConnectedRowState extends ConsumerState<_ConnectedRow> {
  ConnectedCalendar get _entry => widget.entry;
  CalendarConnection get _connection => _entry.connection;

  Future<void> _rename() => showRenameSheet(
    context: context,
    icon: _connection.provider.icon,
    title: L.s.renameCalendar,
    headline: _entry.name,
    message: L.s.renameCalendarBody,
    initialName: _entry.name,
    fieldHint: L.s.householdOnly,
    busyLabel: L.s.savingEllipsis,
    successLabel: L.s.nameChanged,
    errorText: connectErrorText,
    onConfirm: (name) {
      final notifier = ref.read(calendarConnectionsProvider.notifier);
      // A calendar's name lives on the connection that carries it, keyed by the
      // provider's id; a row that *is* the connection renames the connection.
      final externalId = _entry.externalId;
      return externalId == null
          ? notifier.rename(_connection, name)
          : notifier.renameCalendar(_connection, externalId, name);
    },
  );

  void _confirmRemove() {
    // Removing one calendar of an account leaves the account connected, so it
    // is a much smaller promise than disconnecting — and it must not be
    // described with the sentence about deleting credentials. Taking the last
    // one away *is* disconnecting, and says so.
    final externalId = _entry.externalId;
    final wholeConnection = _entry.isWholeConnection;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          !wholeConnection
              ? L.s.removeCalendarQuestion
              : _connection.isFeed
              ? L.s.removeCalendarQuestion
              : L.s.disconnectQuestion,
        ),
        content: Text(
          L.s.removeCalendarBody(_entry.name) +
              (!wholeConnection
                  ? L.s.accountStaysConnected
                  : switch (_connection.provider.kind) {
                      ConnectKind.oauth => L.s.accessRevokedToo,
                      // A feed is shared with every other household that wants
                      // the same Bundesland or street, so leaving it removes
                      // nothing but this household's subscription.
                      ConnectKind.feed => L.s.householdOnlyOthersKeep,
                      ConnectKind.password => L.s.credentialsDeleted,
                      // Nothing to revoke and no credential to delete: the link
                      // was only ever a URL we held, and it keeps working in
                      // the school platform for anyone who still has it.
                      ConnectKind.link => L.s.linkStaysAtSchool,
                      // The key is deleted here and stays valid at Untis, where
                      // it was minted and where it can be re-issued — which is
                      // also how you revoke it for good, and worth saying to
                      // somebody disconnecting because they want it gone.
                      ConnectKind.secret => L.s.untisKeyStaysValid,
                    }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(L.s.cancel),
          ),
          TextButton(
            onPressed: () {
              final notifier = ref.read(calendarConnectionsProvider.notifier);
              if (wholeConnection || externalId == null) {
                notifier.disconnect(_connection);
              } else {
                notifier.removeCalendar(_connection, externalId);
              }
              Navigator.of(dialogContext).pop();
            },
            child: Text(L.s.remove, style: AppText.rowTitle.copyWith(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  /// Ferien and Abfall are deliberately absent from this: a public feed is the
  /// household's by definition — everyone's Bundesland, everyone's bin day —
  /// and offering to file the rubbish collection under one child would be a
  /// question with no right answer.
  Future<void> _assign() => showCalendarOwnerSheet(
    context: context,
    connection: _connection,
    externalId: _entry.externalId,
    calendarName: _entry.name,
  );

  List<AnchoredMenuItem> get _menuItems => [
    AnchoredMenuItem(label: L.s.rename, icon: LucideIcons.pencil, onSelected: _rename),
    if (!_connection.isFeed)
      AnchoredMenuItem(label: L.s.assignCalendar, icon: LucideIcons.userRound, onSelected: _assign),
    AnchoredMenuItem(
      label: _connection.isFeed || !_entry.isWholeConnection ? L.s.remove : L.s.disconnect,
      icon: LucideIcons.unlink,
      destructive: true,
      onSelected: _confirmRemove,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final refreshing = ref.watch(calendarConnectionsProvider).refreshing;
    final attention = _connection.needsAttention;

    return SwipeActionsRow(
      actions: [
        SwipeAction(
          icon: LucideIcons.pencil,
          color: Theme.of(context).colorScheme.primary,
          onTap: _rename,
        ),
        SwipeAction(icon: LucideIcons.trash2, color: AppColors.danger, onTap: _confirmRemove),
      ],
      // Opaque: the row slides over the actions, and the card behind it is what
      // would otherwise show them through.
      child: ColoredBox(
        color: AppColors.surface,
        child: SettingsRow(
          leading: _ProviderTile(_connection.provider),
          title: _entry.name,
          subtitle: attention
              ? (_connection.statusDetail ?? L.s.connectionNeedsAttention)
              : refreshing
              ? L.s.refreshingEllipsis
              : lastSyncedLabel(_connection.lastSyncedAt),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (attention)
                Icon(LucideIcons.triangleAlert, size: 18, color: AppColors.danger)
              else
                const _CheckBadge(),
              const SizedBox(width: 4),
              RowMenuButton(items: _menuItems),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Who a calendar belongs to
// ---------------------------------------------------------------------------

/// The sheet behind "Zuordnen" on a connected calendar: the household, everyone
/// in it, everyone already named on another calendar, and a field to type
/// somebody new.
///
/// **This is not a visibility picker, and must never become one.** Calendars in
/// Aporah are never private and never shared outward — everybody in the
/// household sees every one of them, before and after this sheet. What it sets
/// is whose *day* the calendar counts as, which is the chip it appears under in
/// Kalender and on the Board. Two axes, exactly as `tasks.assignee_id` is
/// separate from `tasks.visibility`; the old single `who` string conflated them
/// and had to be taken back out.
///
/// The free-text row is the point of the whole sheet. A household's calendars
/// belong to people, and the people they belong to are frequently not members:
/// members join by e-mail invitation, and a four-year-old with a Kindergarten
/// calendar has no e-mail address. Typing "Mia" gives her a chip; typing it
/// again on the next calendar puts both under that same chip, because the group
/// is keyed on the lower-cased name.
Future<void> showCalendarOwnerSheet({
  required BuildContext context,
  required CalendarConnection connection,
  required String? externalId,
  required String calendarName,
}) {
  return showAppSheet<void>(
    context: context,
    // Tall enough that the "andere Person" field clears the keyboard: the sheet
    // is anchored to the bottom, so a shorter one puts the field exactly where
    // the keyboard comes up.
    heightFactor: 0.8,
    header: SheetActionHeader(
      title: L.s.assignCalendar,
      action: SheetHeaderAction.none,
    ),
    child: _OwnerSheetBody(
      connection: connection,
      externalId: externalId,
      calendarName: calendarName,
    ),
  );
}

class _OwnerSheetBody extends ConsumerStatefulWidget {
  final CalendarConnection connection;
  final String? externalId;
  final String calendarName;

  const _OwnerSheetBody({
    required this.connection,
    required this.externalId,
    required this.calendarName,
  });

  @override
  ConsumerState<_OwnerSheetBody> createState() => _OwnerSheetBodyState();
}

class _OwnerSheetBodyState extends ConsumerState<_OwnerSheetBody> {
  final _newName = TextEditingController();

  /// The owner currently being written, so the row that was tapped can say so
  /// while `calendar-events` re-reads. Null when nothing is in flight.
  String? _saving;

  String? _error;

  @override
  void dispose() {
    _newName.dispose();
    super.dispose();
  }

  Future<void> _pick(String owner) async {
    if (_saving != null) return;
    setState(() {
      _saving = owner;
      _error = null;
    });

    try {
      await ref
          .read(calendarConnectionsProvider.notifier)
          .setCalendarOwner(widget.connection, widget.externalId, owner);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = null;
        _error = L.s.assignCalendarFailed;
      });
      return;
    }

    if (mounted) Navigator.of(context).pop();
  }

  /// Everybody who already owns a calendar somewhere in this household but has
  /// no account — the child a WebUntis key was scanned for, the toddler whose
  /// Kindergarten calendar was assigned last week.
  ///
  /// Case-insensitively deduplicated, and keeping the capitalisation it was
  /// first typed with: "mia" and "Mia" are one chip, and the row should read as
  /// the name somebody meant rather than as whatever they last typed.
  List<String> _knownPeople(List<CalendarConnection> connections) {
    final seen = <String, String>{};
    for (final c in connections) {
      final own = c.ownerLabel?.trim();
      if (own != null && own.isNotEmpty) seen.putIfAbsent(own.toLowerCase(), () => own);
      for (final value in c.calendarOwners.values) {
        if (!value.startsWith('person:')) continue;
        final label = value.substring('person:'.length).trim();
        if (label.isNotEmpty) seen.putIfAbsent(label.toLowerCase(), () => label);
      }
    }
    final names = seen.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  @override
  Widget build(BuildContext context) {
    final household = ref.watch(familyProvider).household;
    final members = ref.watch(householdMembersProvider);
    final connections = ref.watch(calendarConnectionsProvider).connections;
    final current = widget.connection.ownerOf(widget.externalId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
          child: Text(
            L.s.assignCalendarBody(widget.calendarName),
            style: AppText.body.copyWith(color: AppColors.muted),
          ),
        ),
        SectionCard(
          radius: AppRadii.card,
          children: dividedRows(inset: true, [
            _OwnerRow(
              face: _ownerFace(household: household),
              name: household?.name ?? L.s.family,
              // The one row that needs saying out loud: every other row is a
              // person, and "Familie" could otherwise be read as a fourth
              // person rather than as "this one is everybody's".
              subtitle: L.s.assignCalendarFamilyHint,
              selected: current == 'family',
              busy: _saving == 'family',
              onTap: () => _pick('family'),
            ),
            for (final m in members)
              _OwnerRow(
                face: _ownerFace(member: m),
                name: m.name,
                selected: current == 'member:${m.id}',
                busy: _saving == 'member:${m.id}',
                onTap: () => _pick('member:${m.id}'),
              ),
            for (final name in _knownPeople(connections))
              _OwnerRow(
                face: _ownerFace(label: name),
                name: name,
                // Said out loud, because without it these rows are
                // indistinguishable from the members above them — and somebody
                // reading this list would reasonably conclude the household has
                // members it does not have.
                subtitle: L.s.noAccountYet,
                selected: current.toLowerCase() == 'person:${name.toLowerCase()}',
                busy: _saving == 'person:$name',
                onTap: () => _pick('person:$name'),
              ),
          ]),
        ),
        const SizedBox(height: AppSpacing.blockGap),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(L.s.assignCalendarNewPerson, style: AppText.microLabel),
        ),
        SectionCard(
          radius: AppRadii.card,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newName,
                      enabled: _saving == null,
                      textCapitalization: TextCapitalization.words,
                      style: AppText.searchInput,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: L.s.assignCalendarNewPersonHint,
                        isDense: true,
                      ),
                      onSubmitted: (value) {
                        final name = value.trim();
                        if (name.isNotEmpty) _pick('person:$name');
                      },
                    ),
                  ),
                  // Listens to the field rather than reading it in `build`, so
                  // the button lights up as the name is typed without the whole
                  // sheet rebuilding on every keystroke.
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _newName,
                    builder: (context, value, _) {
                      final name = value.text.trim();
                      final ready = name.isNotEmpty && _saving == null;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: ready ? () => _pick('person:$name') : null,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Icon(
                            LucideIcons.arrowRight,
                            size: 20,
                            color: ready
                                ? Theme.of(context).colorScheme.primary
                                : AppColors.inkTertiary,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_error case final message?) ...[
          const SizedBox(height: 12),
          ErrorNote(message: message),
        ],
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            L.s.assignCalendarNotVisibility,
            style: AppText.label.copyWith(fontSize: 12),
          ),
        ),
      ],
    );
  }

  /// The circle beside a row. Exactly one of the three is passed.
  ///
  /// The same three cases the chip row draws, in the same order, so the sheet
  /// and the chip a household ends up with are recognisably the same face.
  Widget _ownerFace({Household? household, FamilyMember? member, String? label}) {
    if (member != null) {
      final tone = AppTones.list[member.tone % AppTones.list.length];
      return Avatar(
        size: 40,
        bg: tone.bg,
        fg: tone.fg,
        initials: member.initials,
        fontSize: 14,
        imageUrl: member.imageUrl,
      );
    }
    if (label != null) {
      final tone = AppTones.list[label.hashCode.abs() % AppTones.list.length];
      return Avatar(
        size: 40,
        bg: tone.bg,
        fg: tone.fg,
        initials: label.isEmpty ? '?' : label.substring(0, 1).toUpperCase(),
        fontSize: 14,
      );
    }
    final tone = AppTones.list[(household?.tone ?? 0) % AppTones.list.length];
    return Avatar(
      size: 40,
      bg: tone.bg,
      fg: tone.fg,
      initials: household?.initials ?? '?',
      fontSize: 14,
      imageUrl: household?.avatarUrl,
    );
  }
}

/// One candidate owner: their face, their name, and a tick when the calendar is
/// already theirs.
class _OwnerRow extends StatelessWidget {
  final Widget face;
  final String name;
  final String? subtitle;
  final bool selected;

  /// True while this row's write is in flight. The tick's place is held by a
  /// spinner rather than left empty, so the row does not jump as it lands.
  final bool busy;

  final VoidCallback onTap;

  const _OwnerRow({
    required this.face,
    required this.name,
    required this.selected,
    required this.busy,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            face,
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.rowTitle),
                  if (subtitle case final line?) ...[
                    const SizedBox(height: 2),
                    Text(line, style: AppText.caption.copyWith(color: AppColors.inkTertiary)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 20,
              height: 20,
              child: busy
                  ? const CircularProgressIndicator(strokeWidth: 2)
                  : selected
                  ? Icon(LucideIcons.check, size: 19, color: Theme.of(context).colorScheme.primary)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The flow — which question the sheet is on, and what each answer does
// ---------------------------------------------------------------------------

/// Which question the sheet is showing.
///
/// No provider asks all of them; [_ConnectFlow.steps] is the list a given flow
/// actually walks, and the dots count that rather than this enum.
enum _Step {
  /// iCloud: the login, checked before the flow moves on.
  login,

  /// IServ and WebUntis: the calendar link, pasted from the school platform and
  /// fetched before the flow moves on.
  link,

  /// WebUntis: the app secret, scanned off the QR code in the pupil's profile
  /// or typed from the four lines printed under it. Checked by logging in
  /// before the flow moves on, exactly as the link is fetched.
  untis,

  /// Ferien: one of the sixteen Bundesländer.
  region,

  /// Abfall: the household's address, and the vendor lookup it sets off.
  address,

  /// Abfall: the one thing left to know about that address — which Abfuhrbezirk
  /// it belongs to, or, for a town no vendor of ours serves, the link to the
  /// town's own calendar.
  details,

  /// Accounts: which of the account's calendars belong in Aporah.
  pick,

  /// All six: what the household calls this one here.
  name,

  /// All six: that it worked.
  done,
}

/// The whole "add a calendar" conversation, for whichever of the six providers
/// the sheet was opened for.
///
/// Everything the sheet knows lives here rather than in its steps: a step is a
/// view of this, so an answer given on one is simply read by the next, and a
/// step that has scrolled out of existence takes nothing with it. It is also
/// what lets the *header* drive the flow — the header and the body are siblings
/// inside [showAppSheet]'s own Column, so neither can `setState` the other, but
/// both can listen to this.
///
/// The two feeds have no account until the very end: [_submit] is what creates
/// a Ferien or Abfall subscription, where an account provider was already
/// connected before its sheet opened. That asymmetry is the reason this class
/// switches on the provider in exactly two places (the last step, and the name
/// it suggests) and nowhere else.
class _ConnectFlow extends ChangeNotifier {
  _ConnectFlow({
    required this.provider,
    required this.notifier,
    required this.repository,
    required this.findConnection,
    this.members = const [],
    this.connection,
    this.calendars = const [],
    this.addToConnectionId,
    this.useCaldavLogin = false,
    this.useLinkFallback = false,
  }) {
    // Everything the account offers, all ticked. Starting from "all" rather
    // than "none" matches what the connection already means the moment it
    // exists — `selectedcalendars` is null until this sheet writes it, and
    // null is "read them all".
    selected.addAll(calendars.map((c) => c.externalId));
    step = steps.first;
    if (step == _Step.name) _suggestName();
  }

  final CalendarProvider provider;
  final CalendarConnectionsNotifier notifier;
  final CalendarConnectionRepository repository;
  final CalendarConnection? Function(String id) findConnection;

  /// The household, for matching the child a school account belongs to against
  /// somebody who already has a face here.
  final List<FamilyMember> members;

  /// The member whose name is [label], or null.
  ///
  /// A plain case-insensitive match on the display name, which is the whole
  /// check on purpose: with an account the child's homework and their chores
  /// end up on one face, and without one the name alone still makes a chip. A
  /// household where two people are both called Alex gets no match rather than
  /// the wrong one — the first of the two would have been a coin toss.
  String? memberIdFor(String label) {
    final needle = label.trim().toLowerCase();
    if (needle.isEmpty) return null;
    final hits = [for (final m in members) if (m.name.trim().toLowerCase() == needle) m.id];
    return hits.length == 1 ? hits.first : null;
  }

  /// The account, once there is one: made by the consent screen before this
  /// sheet opened, or by the login step inside it. Stays null for the two
  /// feeds, which have no account at all.
  CalendarConnection? connection;
  List<RemoteCalendar> calendars;

  // -- login (iCloud)
  final user = TextEditingController();
  final password = TextEditingController();
  final server = TextEditingController();

  // -- link (IServ, WebUntis)
  final linkUrl = TextEditingController();

  /// Who the account belongs to — "Alice". Only asked when a new account is
  /// being made; adding a second calendar to one already knows.
  final account = TextEditingController();

  /// Set when the sheet was opened from "+ Kalender hinzufügen" on an account
  /// that already exists, which is what turns the flow from two questions into
  /// one.
  final String? addToConnectionId;

  /// IServ's second route: the CalDAV login, reached from the note at the
  /// bottom of its page rather than from the button. The flow is otherwise
  /// unchanged — it is the same login step iCloud uses, and it ends on the same
  /// picker, because a school that publishes collections has a list to choose
  /// from.
  final bool useCaldavLogin;

  /// WebUntis's second route: the pasted link, reached from the note at the
  /// bottom of its page. Turns this flow back into the link flow IServ uses —
  /// same step, same function, same shape — for the school that has switched
  /// Untis Mobile access off and therefore has no QR code to show.
  final bool useLinkFallback;

  // -- untis (WebUntis app secret)

  /// The whole `untis://setschool?...` payload, once something has been
  /// scanned. Kept verbatim rather than split into the four fields: the server
  /// parses either, and handing on exactly what Untis wrote is one fewer place
  /// for a transcription to go wrong.
  String? scannedQr;

  final untisServer = TextEditingController();
  final untisSchool = TextEditingController();
  final untisUser = TextEditingController();
  final untisKey = TextEditingController();

  /// True once the user has asked for the form — because they tapped "Stattdessen
  /// abtippen", or because the scan could not happen at all. The scan is the
  /// front door and the form is behind it, so that a household that can scan
  /// never reads four field labels first.
  bool typingByHand = false;

  /// Who the key turned out to belong to, from the check. Shown on the naming
  /// step, because "Boff Campagnaro Alice · 60 Stunden" is what tells a parent
  /// they scanned the right child's code.
  String? probedStudent;
  String? probedSchool;
  int probedLessons = 0;

  /// What the fetched feed said about itself: the name it carries, if any, and
  /// how many events are in it. Shown on the naming step, because "37 Termine
  /// gefunden" is what tells somebody they pasted the right one of their four
  /// IServ links.
  String? probedName;
  int probedEvents = 0;

  // -- region (Ferien)
  String? region;

  // -- address (Abfall)
  final query = TextEditingController();
  final icsUrl = TextEditingController();
  final searchFocus = FocusNode();
  Timer? _debounce;
  List<GeoAddress> results = const [];
  bool searching = false;
  GeoAddress? address;
  bool resolving = false;
  AbfallCoverage? coverage;
  HouseNumber? houseNumber;

  // -- pick (accounts)
  final Set<String> selected = {};

  /// One name field per calendar the account offers, keyed by the provider's
  /// own id and made on the way into the name step.
  ///
  /// Kept for calendars that were unticked afterwards rather than thrown away:
  /// a name typed for "Arbeit", then a trip back to the picker and forward
  /// again, is still there. Only the ticked ones are read on submit.
  final Map<String, TextEditingController> calendarNames = {};

  // -- shared
  final name = TextEditingController();
  late _Step step;
  bool busy = false;
  String? error;

  /// The name we last put in the field ourselves, so a name the *user* typed
  /// can be told apart from one they merely left alone.
  String _suggested = '';

  /// The sheet can be swiped away mid-call — the request carries on, but there
  /// is nothing left to tell about it.
  bool _disposed = false;

  bool get isFerien => provider == CalendarProvider.ferien;
  bool get isAbfall => provider == CalendarProvider.abfall;
  /// True on the pasted-link flow, however it was reached: IServ's own, and
  /// WebUntis's when the fallback note was tapped. Everything downstream — the
  /// account name, the naming step, the submit — is the same conversation.
  bool get isLink =>
      (provider.kind == ConnectKind.link && !useCaldavLogin) ||
      (provider.kind == ConnectKind.secret && useLinkFallback);

  /// True on the WebUntis app-secret flow, which is the front door for it.
  bool get isUntis => provider.kind == ConnectKind.secret && !useLinkFallback;

  /// True while this flow is making a *new* account rather than adding a
  /// calendar to one — the only case that has to ask whose it is.
  bool get needsAccountName => isLink && addToConnectionId == null;

  /// The steps this flow walks, in order.
  ///
  /// Recomputed rather than fixed, because two of them only exist once an
  /// earlier answer says so: a CalDAV account that turns out to offer a list of
  /// calendars grows a picker, an address on a street with several Abfuhrbezirke
  /// grows a details step. The dot row grows with it at the moment the answer
  /// lands, which is the honest thing for it to do — the alternative is
  /// promising a step that may not exist.
  List<_Step> get steps => [
    ...switch (provider.kind) {
      // Google and Outlook did their asking in Safari, before the sheet.
      ConnectKind.oauth => const <_Step>[],
      ConnectKind.password => const [_Step.login],
      ConnectKind.link => useCaldavLogin ? const [_Step.login] : const [_Step.link],
      ConnectKind.secret => useLinkFallback ? const [_Step.link] : const [_Step.untis],
      ConnectKind.feed => isFerien ? const [_Step.region] : const [_Step.address],
    },
    if (_needsDetails) _Step.details,
    if (calendars.isNotEmpty) _Step.pick,
    _Step.name,
    _Step.done,
  ];

  bool get _needsDetails {
    final found = coverage;
    return isAbfall && found != null && (!found.supported || found.houseNumbers.isNotEmpty);
  }

  int get index => steps.indexOf(step);
  int get count => steps.length;
  bool get canGoBack => index > 0 && step != _Step.done;

  /// What the last two steps are about, over their heading: the account, the
  /// Bundesland, or the street the bins are collected from.
  String get headline {
    if (isFerien) {
      final code = region;
      return code == null ? provider.label : L.s.schoolHolidaysOf(bundeslaender[code]!);
    }
    if (isAbfall) {
      final found = coverage;
      final at = address;
      if (found == null) return at?.label ?? provider.label;
      if (!found.supported) return found.town.isNotEmpty ? found.town : (at?.town ?? provider.label);
      return found.street == null ? found.town : '${found.street}, ${found.town}';
    }
    if (isLink) {
      final typed = account.text.trim();
      if (typed.isNotEmpty) return '${provider.label} · $typed';
      return findConnection(addToConnectionId ?? '')?.displayName ?? provider.label;
    }
    // Nobody is asked whose account this is: the key says, and the check has
    // read it back off WebUntis by the time this line is shown.
    if (isUntis) {
      final pupil = probedStudent?.trim() ?? '';
      return pupil.isEmpty ? provider.label : '${provider.label} · $pupil';
    }
    return connection?.displayName ?? provider.label;
  }

  /// The line under it: what connecting this will actually do.
  String get intro {
    if (isLink) return L.s.linkedCalendarsNote;
    if (isUntis) return L.s.untisConnectedNote;
    if (isFerien) {
      final code = region;
      return code == null ? '' : L.s.holidaysSelectedBody(bundeslaender[code]!);
    }
    if (isAbfall) return L.s.wasteIntro;
    return hasPicker ? L.s.nameEachCalendarBody : L.s.nameYourCalendarBody;
  }

  /// True when this account had calendars to choose between — which is also
  /// what decides whether the last step asks for one name or for one per
  /// calendar.
  bool get hasPicker => calendars.isNotEmpty;

  /// The calendars the household ticked, in the order the provider listed them.
  List<RemoteCalendar> get picked => [
    for (final c in calendars)
      if (selected.contains(c.externalId)) c,
  ];

  List<String> get pickedNames => [for (final c in picked) c.name];

  /// The line under the success beat: what the household will now find in
  /// Kalender, in the words it just chose. Null rather than an empty string
  /// when there is nothing to add — the beat stands on its own.
  String? get connectedSummary {
    if (hasPicker) {
      final names = [for (final c in picked) _nameFor(c)];
      if (names.isEmpty) return null;
      return names.length <= 3 ? names.join(' · ') : L.s.calendarsSelected(names.length);
    }
    final typed = name.text.trim();
    return typed.isEmpty ? null : typed;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Redraw for a field the *header* reads. The account name is typed on the
  /// naming step and shown in the headline above it, and the two are siblings
  /// under [showAppSheet]'s own Column — neither can setState the other, so the
  /// flow is what carries the change across.
  void refreshHeadline() => _notify();

  void _fail(String message) {
    error = message;
    _notify();
  }

  // -- moving between steps ---------------------------------------------------

  /// The accent button in the header, whatever it is pointing at. Each step
  /// answers for itself whether it has been answered; the ones that need the
  /// network say so by going busy rather than by blocking the tap, so nothing
  /// here silently does nothing.
  Future<void> next(BuildContext context) async {
    if (busy) return;
    switch (step) {
      case _Step.login:
        await _login(context);
      case _Step.link:
        await _checkLink(context);
      case _Step.untis:
        await _checkUntis(context);
      case _Step.region:
        if (region == null) {
          _fail(L.s.pickABundesland);
          return;
        }
        _advance();
      case _Step.address:
        if (coverage == null) {
          _fail(L.s.pickYourAddressFirst);
          return;
        }
        _advance();
      case _Step.details:
        FocusScope.of(context).unfocus();
        if (coverage?.supported == true) {
          _advance();
        } else {
          await _checkIcs();
        }
      case _Step.pick:
        if (selected.isEmpty) {
          // A connection that syncs nothing is not a connection. Said here
          // rather than at the end, where it would reject a form whose broken
          // half is two steps behind you.
          _fail(L.s.pickAtLeastOneCalendar);
          return;
        }
        _advance();
      case _Step.name:
        await _submit(context);
      case _Step.done:
        break;
    }
  }

  void back() {
    final list = steps;
    final at = list.indexOf(step);
    if (at <= 0) return;
    error = null;
    step = list[at - 1];
    _notify();
  }

  void _advance() {
    error = null;
    final list = steps;
    final at = list.indexOf(step);
    if (at >= 0 && at + 1 < list.length) step = list[at + 1];
    if (step == _Step.name) _suggestName();
    _notify();
  }

  /// Re-suggest only while the field still holds the suggestion we made: a name
  /// the user typed survives a trip back and forward again.
  ///
  /// With a picker there is no single field to suggest into — there is one per
  /// ticked calendar, each starting as what the provider calls it, which is
  /// very often the name the household will keep.
  void _suggestName() {
    if (hasPicker) {
      for (final c in picked) {
        calendarNames.putIfAbsent(c.externalId, () => TextEditingController(text: c.name));
      }
      return;
    }
    final fresh = _nameSuggestion();
    if (name.text.trim() == _suggested.trim()) name.text = fresh;
    _suggested = fresh;
  }

  String _nameSuggestion() {
    // What the feed calls itself, where it says. WebUntis sets X-WR-CALNAME;
    // IServ's plugin feeds do not, so this is usually empty and the user names
    // the calendar — which is the honest outcome, since only they know whether
    // this link is the Klausurplan or the Aufgaben.
    if (isLink) return probedName?.trim() ?? '';
    // The pupil's own name, which WebUntis gave us and nobody had to type:
    // "Stundenplan Alice" is what a household with two children needs the
    // filter to say.
    // The **child's** name, not the calendar's. WebUntis already told us who
    // the key belongs to, so this is usually right without anybody typing: the
    // calendar name and the person chip both come out of this one word.
    if (isUntis) {
      final pupil = probedStudent?.trim() ?? '';
      return pupil.isEmpty ? '' : _pupilShortName(pupil);
    }
    // "Schulferien Niedersachsen" is both the heading and the name.
    if (isFerien) return headline;
    if (isAbfall) {
      final at = address;
      if (at == null) return provider.label;
      if (coverage?.supported != true) {
        final town = coverage?.town.isNotEmpty == true ? coverage!.town : at.town;
        return L.s.wasteForTown(town);
      }
      final nr = houseNumber?.nr ?? at.houseNumber;
      final street = at.street.isNotEmpty ? at.street : at.town;
      return L.s.wasteFor('$street${nr == null || nr.isEmpty ? '' : ' $nr'}');
    }
    // Only reached without a picker — an account that offered one collection,
    // or a listing that came back empty. The calendars of an account that *did*
    // offer a list are named one by one, in [calendarNames].
    return connection?.displayName ?? provider.label;
  }

  // -- login ------------------------------------------------------------------

  /// The credentials are checked *here*, on the step that asked for them: a
  /// wrong password belongs next to the password box, not on the step after it.
  Future<void> _login(BuildContext context) async {
    FocusScope.of(context).unfocus();
    busy = true;
    error = null;
    _notify();

    try {
      final result = await notifier.connectCaldav(
        provider: provider,
        username: user.text.trim(),
        password: password.text,
        server: provider == CalendarProvider.iserv ? server.text : null,
      );
      if (_disposed) return;
      password.clear();
      busy = false;

      final id = result.id;
      final row = id == null ? null : findConnection(id);
      if (row == null) {
        // "Verbunden." — the CalDAV login worked, we just can't find the row to
        // put a name to, so there is nothing left to ask. Good news, and it
        // went out through the *error* surface until the two shared a widget.
        _notify();
        if (context.mounted) {
          showToast(context, L.s.connectedDot);
          Navigator.of(context).pop();
        }
        return;
      }

      connection = row;
      calendars = result.calendars;
      _advance();
    } catch (e) {
      if (_disposed) return;
      busy = false;
      _fail(connectErrorText(e));
    }
  }

  // -- Ferien -----------------------------------------------------------------

  void pickRegion(String code) {
    region = region == code ? null : code;
    error = null;
    _notify();
  }

  // -- Abfall -----------------------------------------------------------------

  void onQueryChanged(String value) {
    error = null;
    _debounce?.cancel();

    final typed = value.trim();
    if (typed.length < 3) {
      results = const [];
      searching = false;
      _notify();
      return;
    }

    searching = true;
    _notify();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(typed));
  }

  Future<void> _search(String typed) async {
    try {
      final found = await repository.searchAddresses(typed);
      if (_disposed || query.text.trim() != typed) return;
      results = found;
      searching = false;
      _notify();
    } catch (e) {
      if (_disposed) return;
      searching = false;
      _fail(connectErrorText(e));
    }
  }

  /// Picking the address *is* the answer to this step, so a resolved one walks
  /// on by itself — there is nothing left to tap here. Coming back leaves the
  /// address where it is; only a fresh pick moves the flow again.
  ///
  /// Coverage is checked **after** the pick, never while typing. Matching
  /// against the vendors' own street lists as you type was the old app's first
  /// design and it made every uncovered address look like a broken text field.
  Future<void> pickAddress(BuildContext context, GeoAddress found) async {
    if (found.prefix) {
      // A bare postcode is a prefix, not an address: refill the field and let
      // the user carry on typing the street.
      query.text = '${found.postcode ?? ''} ${found.town} ';
      query.selection = TextSelection.collapsed(offset: query.text.length);
      results = const [];
      _notify();
      searchFocus.requestFocus();
      return;
    }

    FocusScope.of(context).unfocus();
    address = found;
    results = const [];
    coverage = null;
    houseNumber = null;
    error = null;
    resolving = true;
    _notify();

    try {
      final resolved = await repository.resolveAddress(found);
      if (_disposed) return;
      coverage = resolved;
      resolving = false;
      _advance();
    } catch (e) {
      if (_disposed) return;
      resolving = false;
      _fail(connectErrorText(e));
    }
  }

  /// Back to an empty field, from the X on the address row. The query goes too:
  /// leaving the old address in the field made the card claim "Keine Adresse
  /// gefunden" about the address it had just resolved.
  void resetAddress() {
    query.clear();
    icsUrl.clear();
    address = null;
    coverage = null;
    houseNumber = null;
    results = const [];
    error = null;
    _notify();
  }

  void pickHouseNumber(HouseNumber picked) {
    houseNumber = houseNumber?.id == picked.id ? null : picked;
    error = null;
    _notify();
  }

  // -- link -------------------------------------------------------------------

  /// The pasted link is fetched *here*, on the step that asked for it — the
  /// same rule the password follows. A revoked link, a browser URL pasted
  /// instead of the ICS one, a typo: all of them belong under the field.
  ///
  /// This is also the whole "connect" for these two providers. There is no
  /// credential to check, so proving the link answers with a calendar is the
  /// only thing "verbunden" can honestly mean.
  Future<void> _checkLink(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final url = linkUrl.text.trim();
    if (url.isEmpty) {
      _fail(L.s.pasteLinkHere);
      return;
    }

    busy = true;
    error = null;
    _notify();

    try {
      final probe = await notifier.checkCalendarLink(provider: provider, url: url);
      if (_disposed) return;
      busy = false;
      probedName = probe.name;
      probedEvents = probe.events;
      _advance();
    } catch (e) {
      if (_disposed) return;
      busy = false;
      _fail(connectErrorText(e));
    }
  }

  // -- untis -------------------------------------------------------------------

  /// Opens the camera, and treats every way it can fail as "then type it in":
  /// the form is one tap away on this same step, so a refused permission is a
  /// sentence above it rather than a dead end.
  Future<void> scan() async {
    if (busy) return;
    final result = await scanCode(
      cancelLabel: L.s.cancel,
      dark: AppColors.palette.isDark,
      title: L.s.scanUntisCode,
      hint: L.s.untisFieldsHint,
    );
    if (_disposed) return;

    switch (result.outcome) {
      case ScanOutcome.cancelled:
        // They know they backed out. Saying so would be the app talking to
        // itself.
        return;
      case ScanOutcome.denied:
        typingByHand = true;
        _fail(L.s.cameraDenied);
      case ScanOutcome.unavailable:
        typingByHand = true;
        _fail(L.s.cameraNotAvailable);
      case ScanOutcome.scanned:
        final payload = result.value ?? '';
        // Rejected here rather than at the server for the one mis-scan that is
        // worth its own sentence: a QR code that is simply some other app's.
        if (!payload.trimLeft().toLowerCase().startsWith('untis://')) {
          _fail(L.s.notAnUntisCode);
          return;
        }
        scannedQr = payload;
        error = null;
        _notify();
    }
  }

  /// Reverting a scan: back to the form, with the four fields empty.
  void clearScan() {
    scannedQr = null;
    typingByHand = true;
    error = null;
    _notify();
  }

  /// The key is checked *here*, on the step that asked for it — the same rule
  /// the password and the pasted link follow. A revoked key, a school that has
  /// switched mobile access off, a mistyped Schlüssel: all of them belong under
  /// the field, not on the step after it.
  ///
  /// This is also the whole "connect" for WebUntis. Logging in and reading a
  /// fortnight of lessons is the only thing "verbunden" can honestly mean, and
  /// it is what fills in whose timetable this turned out to be.
  Future<void> _checkUntis(BuildContext context) async {
    FocusScope.of(context).unfocus();

    final qr = scannedQr?.trim() ?? '';
    if (qr.isEmpty &&
        [untisServer, untisSchool, untisUser, untisKey].any((c) => c.text.trim().isEmpty)) {
      typingByHand = true;
      _fail(L.s.untisFieldsMissing);
      return;
    }

    busy = true;
    error = null;
    _notify();

    try {
      final probe = await notifier.checkUntis(
        qr: qr.isEmpty ? null : qr,
        server: untisServer.text,
        school: untisSchool.text,
        user: untisUser.text,
        secret: untisKey.text,
      );
      if (_disposed) return;
      busy = false;
      probedStudent = probe.student;
      probedSchool = probe.school;
      probedLessons = probe.lessons;
      _advance();
    } catch (e) {
      if (_disposed) return;
      busy = false;
      _fail(connectErrorText(e));
    }
  }

  /// The link is checked on the way *off* the details step, so a dead one is
  /// reported under the field it was typed into rather than on the step after.
  Future<void> _checkIcs() async {
    final url = icsUrl.text.trim();
    if (url.isEmpty) {
      _fail(L.s.pasteLinkHere);
      return;
    }

    busy = true;
    error = null;
    _notify();
    try {
      final ok = await repository.checkIcsUrl(url);
      if (_disposed) return;
      busy = false;
      if (!ok) {
        _fail(L.s.noEventsAtThatLink);
        return;
      }
      _advance();
    } catch (e) {
      if (_disposed) return;
      busy = false;
      _fail(connectErrorText(e));
    }
  }

  // -- picking calendars ------------------------------------------------------

  void toggle(RemoteCalendar calendar) {
    if (!selected.remove(calendar.externalId)) selected.add(calendar.externalId);
    error = null;
    _notify();
  }

  void toggleAll() {
    if (selected.length == calendars.length) {
      selected.clear();
    } else {
      selected.addAll(calendars.map((c) => c.externalId));
    }
    error = null;
    _notify();
  }

  // -- the last step ----------------------------------------------------------

  /// What one picked calendar ends up called: whatever is in its field, and the
  /// provider's own name where the field was cleared. An empty name would leave
  /// a nameless row in Kalender's chip bar, which is worse than "Calendar".
  String _nameFor(RemoteCalendar calendar) {
    final typed = calendarNames[calendar.externalId]?.text.trim() ?? '';
    return typed.isEmpty ? calendar.name : typed;
  }

  /// What every flow ends with. A feed is *created* here — connecting a Ferien
  /// or Abfall calendar is one call and it has everything it needs by now — and
  /// an account, which has existed since its own first step, is told which
  /// calendars to read and what to be called.
  Future<void> _submit(BuildContext context) async {
    FocusScope.of(context).unfocus();
    busy = true;
    error = null;
    _notify();

    final label = name.text.trim();

    // Both names are checked here rather than server-side, because both are
    // things the user is looking at: a calendar with no name becomes a nameless
    // chip in Kalender, and an account with none becomes "IServ (kgs-sb.de)",
    // which is exactly the row nobody can tell from their other child's.
    if (isLink) {
      if (label.isEmpty) {
        busy = false;
        _fail(L.s.nameThisCalendarFirst);
        return;
      }
      if (needsAccountName && account.text.trim().isEmpty) {
        busy = false;
        _fail(L.s.whoseCalendarFirst);
        return;
      }
    }
    // No account name to ask for — WebUntis told us whose key it is — but the
    // child's name is what the calendar is named after and what both filter
    // rows are built from, so it cannot be blank.
    if (isUntis && label.isEmpty) {
      busy = false;
      _fail(L.s.untisPupilMissing);
      return;
    }

    try {
      if (isFerien) {
        await notifier.connectFerien(region!, displayName: label);
      } else if (isAbfall && coverage?.supported == true && coverage?.config != null) {
        await notifier.connectAbfall(
          config: coverage!.config!,
          label: address!.label,
          houseNumber: houseNumber,
          displayName: label,
        );
      } else if (isAbfall) {
        await notifier.connectIcs(
          url: icsUrl.text.trim(),
          label: address!.label,
          displayName: label,
        );
      } else if (isUntis) {
        // One call again, and for the same reason: the sealed key, the one
        // timetable and its name are a single decision, and not one of the
        // three is a column a client may write.
        await notifier.connectUntis(
          pupil: label,
          // The child as a household member where the name matches one — their
          // timetable then lands on the same face as their chores, instead of
          // beside it under a second chip with the same name on it.
          memberId: memberIdFor(label),
          qr: scannedQr,
          server: untisServer.text,
          school: untisSchool.text,
          user: untisUser.text,
          secret: untisKey.text,
        );
      } else if (isLink) {
        // One call does the lot: the function stores the link, ticks it and
        // names it, because all three are the same decision and none of the
        // three is a column a client may write.
        await notifier.addCalendarLink(
          provider: provider,
          url: linkUrl.text.trim(),
          name: label,
          account: account.text.trim(),
          connectionId: addToConnectionId,
        );
      } else if (hasPicker) {
        // The picked calendars and what to call each of them: one write,
        // because they are one decision. It has to land before the follow-up
        // sync, which is what turns each of them into a `calendars` row — under
        // the name written here.
        //
        // The account itself is not renamed. It is an account, and
        // "iCloud (name@example.com)" is what it is called; the rows the
        // household sees in "Verbunden" are the calendars.
        await notifier.selectCalendars(
          connection!.id,
          [for (final c in picked) c.externalId],
          names: {for (final c in picked) c.externalId: _nameFor(c)},
        );
      } else if (label.isNotEmpty) {
        await notifier.rename(connection!, label);
      }
      if (_disposed) return;
      busy = false;
      step = _Step.done;
      _notify();
    } catch (e) {
      if (_disposed) return;
      busy = false;
      _fail(connectErrorText(e));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    user.dispose();
    password.dispose();
    server.dispose();
    query.dispose();
    icsUrl.dispose();
    linkUrl.dispose();
    untisServer.dispose();
    untisSchool.dispose();
    untisUser.dispose();
    untisKey.dispose();
    account.dispose();
    for (final controller in calendarNames.values) {
      controller.dispose();
    }
    searchFocus.dispose();
    name.dispose();
    super.dispose();
  }
}

/// Close-or-back on the left, the accent button on the right — a chevron while
/// there is a step after this one, the check on the last thing to answer.
///
/// The accent button is never hidden and never greyed: a step that has not been
/// answered says so in its own error line when the chevron is tapped, which
/// tells the user *what* is missing. A disabled button only says "no".
class _ConnectHeader extends StatelessWidget {
  final _ConnectFlow flow;
  final String title;

  const _ConnectHeader({required this.flow, required this.title});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: flow,
      builder: (context, _) {
        // Something is in flight that closing would not cancel.
        if (flow.busy) {
          return SheetActionHeader(title: title, action: SheetHeaderAction.busy);
        }
        // The confirmation dismisses itself, and an X racing it would decide
        // what the sheet closes on.
        if (flow.step == _Step.done) {
          return SheetActionHeader(title: title, action: SheetHeaderAction.none);
        }

        final back = flow.canGoBack;
        return SheetActionHeader(
          title: title,
          action: SheetHeaderAction.confirm,
          closeIcon: back ? LucideIcons.chevronLeft : LucideIcons.x,
          confirmIcon: flow.step == _Step.name ? LucideIcons.check : LucideIcons.chevronRight,
          onConfirm: () => flow.next(context),
          onClose: back ? flow.back : () => Navigator.of(context).pop(),
        );
      },
    );
  }
}

/// The dots, then whichever step the flow is on.
class _ConnectBody extends StatelessWidget {
  final _ConnectFlow flow;

  const _ConnectBody({required this.flow});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: flow,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StepDots(count: flow.count, index: flow.index),
          const SizedBox(height: 20),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            child: switch (flow.step) {
              _Step.login => _LoginStep(key: const ValueKey('login'), flow: flow),
              _Step.link => _LinkStep(key: const ValueKey('link'), flow: flow),
              _Step.untis => _UntisStep(key: const ValueKey('untis'), flow: flow),
              _Step.region => _RegionStep(key: const ValueKey('region'), flow: flow),
              _Step.address => _AddressStep(key: const ValueKey('address'), flow: flow),
              _Step.details => _DetailsStep(key: const ValueKey('details'), flow: flow),
              _Step.pick => _PickStep(key: const ValueKey('pick'), flow: flow),
              _Step.name => _NameStep(key: const ValueKey('name'), flow: flow),
              // The app's one confirmation, in its beat shape: there is nothing
              // to read here beyond the word, so it plays and takes the sheet
              // with it.
              _Step.done => ConfirmationView(
                key: const ValueKey('done'),
                headline: L.s.calendarConnected,
                // What was just connected, under its new name — the calendars
                // where there were several to name, the one name otherwise.
                message: flow.connectedSummary,
                dismissAfter: const Duration(milliseconds: 1100),
                onDone: () => Navigator.of(context).pop(),
              ),
            },
          ),
        ],
      ),
    );
  }
}

/// A step's spinner and its line of text, under the card it is waiting on.
class _StepBusyRow extends StatelessWidget {
  final String label;

  const _StepBusyRow(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 12),
          Text(label, style: AppText.body.copyWith(color: AppColors.muted)),
        ],
      ),
    );
  }
}

/// The error a step reports about itself, under its card.
class _StepError extends StatelessWidget {
  final String? message;

  const _StepError(this.message);

  @override
  Widget build(BuildContext context) {
    final text = message;
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.blockGap),
      child: ErrorNote(message: text),
    );
  }
}

// ---------------------------------------------------------------------------
// CalDAV — iCloud, IServ
// ---------------------------------------------------------------------------

/// Step 1 for the two password providers: the login, and nothing above it — the
/// sheet's header already says what is being connected, so the paragraph that
/// used to repeat it (and the loose link under that) became the password
/// field's own hint and a row in the card.
///
/// No "Verbinden" button of its own: the chevron in the header is what checks
/// the credentials, the same control that moves every other step on.
/// The paste step for IServ and WebUntis: where to find the link, and the field
/// to put it in.
///
/// The instructions are half the screen on purpose. Neither platform can be
/// asked for this link — IServ's plugin calendars are module views rather than
/// CalDAV collections, and WebUntis publishes a per-student iCal URL only once
/// the student has pressed the button — so the user has to go and make one, and
/// a field with a hint under it would leave them guessing which of the several
/// URLs in a school platform is the right one.
class _LinkStep extends StatelessWidget {
  final _ConnectFlow flow;

  const _LinkStep({super.key, required this.flow});

  @override
  Widget build(BuildContext context) {
    final steps = flow.provider.linkSteps;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          radius: AppRadii.card,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (index, line) in steps.indexed) ...[
                    if (index > 0) const SizedBox(height: 10),
                    _LinkHowToRow(number: index + 1, text: line),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Divider(height: 0.5, thickness: 0.5, color: AppColors.hairline),
            ),
            FieldGroup(
              label: L.s.pasteCalendarLink,
              hint: L.s.pasteCalendarLinkHint,
              child: FieldBox(
                child: TextField(
                  controller: flow.linkUrl,
                  enabled: !flow.busy,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  // A tokenised feed URL is long and nobody types one; two
                  // lines is what makes it possible to see that what landed in
                  // the field is the whole thing.
                  maxLines: 2,
                  minLines: 1,
                  textInputAction: TextInputAction.done,
                  style: AppText.searchInput,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'https://…',
                    isDense: true,
                  ),
                  onSubmitted: (_) => flow.next(context),
                ),
              ),
            ),
          ],
        ),
        _StepError(flow.error),
        if (flow.busy) _StepBusyRow(L.s.checkingLinkEllipsis),
      ],
    );
  }
}

/// One numbered instruction: the circle, then the sentence.
class _LinkHowToRow extends StatelessWidget {
  final int number;
  final String text;

  const _LinkHowToRow({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: AppText.microLabel.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(text, style: AppText.body.copyWith(color: AppColors.muted)),
          ),
        ),
      ],
    );
  }
}

/// WebUntis's first step: scan the code, or type what is printed under it.
///
/// The scan is the whole screen's proposal and the form sits behind one tap,
/// rather than the two being offered side by side. A household that can hold a
/// phone up to a laptop is done in four seconds, and showing them four field
/// labels first makes the easy path look like the hard one. The form is one row
/// away, and every way the camera can fail lands them on it with a sentence
/// saying why.
class _UntisStep extends StatelessWidget {
  final _ConnectFlow flow;

  const _UntisStep({super.key, required this.flow});

  @override
  Widget build(BuildContext context) {
    final steps = flow.provider.secretSteps;
    final scanned = flow.scannedQr != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          radius: AppRadii.card,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (index, line) in steps.indexed) ...[
                    if (index > 0) const SizedBox(height: 10),
                    _LinkHowToRow(number: index + 1, text: line),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Divider(height: 0.5, thickness: 0.5, color: AppColors.hairline),
            ),
            if (scanned)
              // What was scanned, in the one word off the payload that means
              // anything to a person — the school. Tapping it scans again,
              // which is what somebody who held up the wrong child's code
              // wants and the only thing they could want here.
              SettingsRow(
                icon: LucideIcons.circleCheckBig,
                title: L.s.codeScanned,
                subtitle: _scannedSchool(flow.scannedQr!) ?? L.s.scanAgain,
                onTap: flow.busy ? () {} : flow.scan,
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      L.s.scanUntisCodeBody,
                      style: AppText.body.copyWith(color: AppColors.muted),
                    ),
                    const SizedBox(height: 14),
                    AccentAction(
                      icon: LucideIcons.qrCode,
                      label: L.s.scanUntisCode,
                      onTap: flow.busy ? () {} : flow.scan,
                    ),
                  ],
                ),
              ),
          ],
        ),
        // The form: asked for, or arrived at because the camera could not be
        // used. Never shown next to a scan that has already succeeded — the two
        // would be answering the same question twice.
        if (!scanned) ...[
          const SizedBox(height: AppSpacing.blockGap),
          if (flow.typingByHand)
            SectionCard(
              radius: AppRadii.card,
              children: dividedRows(inset: true, [
                _UntisField(
                  flow: flow,
                  label: L.s.untisServerField,
                  hint: L.s.untisFieldsHint,
                  controller: flow.untisServer,
                  placeholder: 'schule.webuntis.com',
                  keyboardType: TextInputType.url,
                ),
                _UntisField(
                  flow: flow,
                  label: L.s.untisSchoolField,
                  controller: flow.untisSchool,
                  placeholder: 'kgs-musterstadt',
                ),
                _UntisField(
                  flow: flow,
                  label: L.s.untisUserField,
                  controller: flow.untisUser,
                  placeholder: '2026042111083880',
                ),
                _UntisField(
                  flow: flow,
                  label: L.s.untisKeyField,
                  controller: flow.untisKey,
                  placeholder: 'N777WOCPNMHOYS4R',
                  last: true,
                ),
              ]),
            )
          else
            SectionCard(
              radius: AppRadii.card,
              children: dividedRows(inset: true, [
                SettingsRow(
                  icon: LucideIcons.keyboard,
                  title: L.s.enterManually,
                  subtitle: L.s.untisFieldsHint,
                  onTap: () {
                    flow.typingByHand = true;
                    flow.refreshHeadline();
                  },
                ),
              ]),
            ),
        ],
        _StepError(flow.error),
        if (flow.busy) _StepBusyRow(L.s.checkingAccessEllipsis),
      ],
    );
  }

  /// The `school=` out of a scanned payload, for the confirmation row. Display
  /// only — the server parses the payload itself, and a null here costs nothing
  /// but a slightly duller subtitle.
  static String? _scannedSchool(String payload) {
    final at = payload.indexOf('?');
    if (at < 0) return null;
    final school = Uri.splitQueryString(payload.substring(at + 1))['school']?.trim();
    return school == null || school.isEmpty ? null : school;
  }
}

/// One of the four lines printed under the QR code.
///
/// Autocorrect and suggestions off on all of them: three are identifiers and
/// the fourth is a base32 key, and a keyboard that helpfully capitalises the
/// first letter of "kgs-musterstadt" costs somebody ten minutes.
class _UntisField extends StatelessWidget {
  final _ConnectFlow flow;
  final String label;
  final String? hint;
  final TextEditingController controller;
  final String placeholder;
  final TextInputType? keyboardType;
  final bool last;

  const _UntisField({
    required this.flow,
    required this.label,
    required this.controller,
    required this.placeholder,
    this.hint,
    this.keyboardType,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return FieldGroup(
      label: label,
      hint: hint,
      child: FieldBox(
        child: TextField(
          controller: controller,
          enabled: !flow.busy,
          keyboardType: keyboardType,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.none,
          textInputAction: last ? TextInputAction.done : TextInputAction.next,
          style: AppText.searchInput,
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: placeholder,
            isDense: true,
          ),
          onSubmitted: last ? (_) => flow.next(context) : null,
        ),
      ),
    );
  }
}

class _LoginStep extends StatelessWidget {
  final _ConnectFlow flow;

  const _LoginStep({super.key, required this.flow});

  @override
  Widget build(BuildContext context) {
    final isIserv = flow.provider == CalendarProvider.iserv;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          radius: AppRadii.card,
          children: dividedRows(inset: true, [
            if (isIserv)
              FieldGroup(
                label: L.s.school,
                hint: L.s.schoolAddressHint,
                child: FieldBox(
                  child: TextField(
                    controller: flow.server,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    style: AppText.searchInput,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'schule.de',
                      isDense: true,
                    ),
                  ),
                ),
              ),
            FieldGroup(
              label: isIserv ? L.s.username : L.s.appleId,
              child: FieldBox(
                child: TextField(
                  controller: flow.user,
                  keyboardType: isIserv ? TextInputType.text : TextInputType.emailAddress,
                  autocorrect: false,
                  style: AppText.searchInput,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: isIserv ? 'vorname.nachname' : L.s.icloudEmailHint,
                    isDense: true,
                  ),
                ),
              ),
            ),
            FieldGroup(
              label: L.s.password,
              // The one thing an iCloud user has to be told, said where it is
              // needed instead of in a paragraph at the top of the page.
              hint: isIserv ? null : L.s.appPasswordHint,
              child: FieldBox(
                child: TextField(
                  controller: flow.password,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  style: AppText.searchInput,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: isIserv ? L.s.iservPassword : 'xxxx-xxxx-xxxx-xxxx',
                    isDense: true,
                  ),
                  onSubmitted: (_) => flow.next(context),
                ),
              ),
            ),
            if (!isIserv)
              SettingsRow(
                icon: LucideIcons.externalLink,
                title: L.s.createAppPassword,
                onTap: () => openExternalUrl('https://appleid.apple.com/account/manage'),
              ),
          ]),
        ),
        _StepError(flow.error),
        if (flow.busy) _StepBusyRow(L.s.checkingEllipsis),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// The steps every provider shares — pick, name
// ---------------------------------------------------------------------------

/// What the step is about, at the top of it: the accent disc every connect
/// surface opens with, and the account's, Bundesland's or street's name beside
/// it — capped at two lines, because that name is routinely
/// "iCloud (vorname.nachname@example.com)" and left to wrap it pushed the card
/// under it off the sheet.
class _StepHeadline extends StatelessWidget {
  final CalendarProvider provider;
  final String name;

  const _StepHeadline({required this.provider, required this.name});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GlassIconTile(icon: provider.icon, size: 44, iconSize: 21),
        const SizedBox(width: 14),
        Expanded(
          child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.cardTitle),
        ),
      ],
    );
  }
}

/// Step 1: which of the account's calendars belong in Aporah.
///
/// An account is not one calendar — an Apple ID typically carries "Privat",
/// "Arbeit", a shared family one and whatever a partner shared last year, and
/// syncing the lot is how Kalender fills up with things nobody asked for.
class _PickStep extends StatelessWidget {
  final _ConnectFlow flow;

  const _PickStep({super.key, required this.flow});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepHeadline(provider: flow.provider, name: flow.headline),
        const SizedBox(height: 14),
        Text(
          L.s.calendarsFoundPickThem(flow.calendars.length),
          style: AppText.body.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 18),
        SectionCard(
          radius: AppRadii.card,
          children: dividedRows(inset: true, [
            FieldGroup(label: L.s.whichCalendars, hint: L.s.whichCalendarsHint),
            // Only where it earns its row: with three calendars, ticking them
            // by hand is faster than reading what this does.
            if (flow.calendars.length > 3) _SelectAllRow(flow: flow),
            for (final calendar in flow.calendars)
              SettingsRow(
                title: calendar.name,
                subtitle: calendar.readOnly ? L.s.readOnlyCalendar : null,
                trailing: flow.selected.contains(calendar.externalId)
                    ? const _CheckBadge()
                    // Not const: the border below is a palette colour, and a
                    // const instance would keep painting the palette it was
                    // born with. `_CheckBadge` may stay const — it reads its
                    // colour off `Theme.of(context)`, which rebuilds on its own.
                    : _EmptyBadge(),
                onTap: () => flow.toggle(calendar),
              ),
          ]),
        ),
        _StepError(flow.error),
      ],
    );
  }
}

/// "Alle auswählen" and the running count, for an account with enough calendars
/// that starting from none is the shorter way round.
class _SelectAllRow extends StatelessWidget {
  final _ConnectFlow flow;

  const _SelectAllRow({required this.flow});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final all = flow.selected.length == flow.calendars.length;

    return GestureDetector(
      onTap: flow.toggleAll,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Text(
                all ? L.s.deselectAll : L.s.selectAll,
                style: AppText.rowTitle.copyWith(color: accent),
              ),
            ),
            Text(L.s.calendarsSelected(flow.selected.length), style: AppText.label),
          ],
        ),
      ),
    );
  }
}

/// The last thing every one of the six asks: what the household calls this
/// here. Also the step that does the connecting — see [_ConnectFlow._submit].
///
/// **One row per calendar** where the step before it picked several. Two
/// iCloud calendars are two calendars in Kalender, so asking for one name and
/// putting it on the account was answering a different question — the household
/// picks "Familie" and "Trabalho" and then finds neither of those words
/// anywhere. Each row starts as what the provider calls that calendar, which
/// is usually the right answer already.
///
/// It is the same *card* the step before it ticked, with the names now typed
/// into the rows: a caption and a boxed field per calendar stacked four blocks
/// of chrome for four words of content, and the list stopped looking like the
/// list it was a moment ago. Here the row is the field.
class _NameStep extends StatelessWidget {
  final _ConnectFlow flow;

  const _NameStep({super.key, required this.flow});

  @override
  Widget build(BuildContext context) {
    final picked = flow.picked;
    final last = picked.isEmpty ? null : picked.last.externalId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepHeadline(provider: flow.provider, name: flow.headline),
        const SizedBox(height: 14),
        Text(flow.intro, style: AppText.body.copyWith(color: AppColors.muted)),
        const SizedBox(height: 18),
        if (flow.isLink) ...[
          _LinkFoundNote(flow: flow),
          const SizedBox(height: 14),
        ],
        // The same reassurance, counting lessons: "60 Stunden in den nächsten
        // zwei Wochen" under the pupil's own name is what confirms the right
        // child's code was held up. A timetable that is legitimately empty —
        // the holidays — reads as working, for the same reason an empty
        // Klausurplan does.
        if (flow.isUntis) ...[
          _UntisFoundNote(flow: flow),
          const SizedBox(height: 14),
        ],
        SectionCard(
          radius: AppRadii.card,
          children: dividedRows(
            inset: true,
            flow.hasPicker
                ? [
                    for (final calendar in picked)
                      _CalendarNameRow(
                        calendar: calendar,
                        controller: flow.calendarNames[calendar.externalId]!,
                        enabled: !flow.busy,
                        // Every row but the last hands on to the next one,
                        // which is what a form of names should do.
                        isLast: calendar.externalId == last,
                        onSubmitted: () => flow.next(context),
                      ),
                  ]
                : [
                    // A new school account is named twice over, and the two
                    // names do different jobs: the account's is the chip in
                    // Kalender ("IServ · Alice"), the calendar's is the row
                    // inside it ("Klausuren"). Adding a second calendar to an
                    // account already has the first, so it only asks the second.
                    if (flow.needsAccountName)
                      FieldGroup(
                        label: L.s.whoseCalendar,
                        hint: L.s.whoseCalendarHint,
                        child: FieldBox(
                          child: TextField(
                            controller: flow.account,
                            enabled: !flow.busy,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            style: AppText.searchInput,
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              hintText: L.s.whoseCalendarPlaceholder,
                              isDense: true,
                            ),
                            // The headline above reads "IServ · Alice" as it is
                            // typed, so the name is shown where it will be used
                            // rather than described.
                            onChanged: (_) => flow.refreshHeadline(),
                          ),
                        ),
                      ),
                    FieldGroup(
                      label: flow.isLink
                          ? L.s.linkedCalendarName
                          : flow.isUntis
                          ? L.s.untisPupilName
                          : L.s.name,
                      hint: flow.isLink
                          ? L.s.linkedCalendarNameHint
                          : flow.isUntis
                          ? L.s.untisPupilNameHint
                          : L.s.calendarNameInAporah,
                      child: FieldBox(
                        child: TextField(
                          controller: flow.name,
                          enabled: !flow.busy,
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: TextInputAction.done,
                          style: AppText.searchInput,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          onSubmitted: (_) => flow.next(context),
                        ),
                      ),
                    ),
                  ],
          ),
        ),
        _StepError(flow.error),
        if (flow.busy) _StepBusyRow(L.s.connectingEllipsis),
      ],
    );
  }
}

/// What the fetched link turned out to contain, over the naming step.
///
/// The event count is the point of it: a family has three or four IServ links
/// and no way to tell them apart by their URLs, so "37 Termine gefunden" is
/// what confirms this is the Klausurplan and not the empty Geburtstage feed
/// they copied last week. An empty feed is reported as working rather than as a
/// problem — a Klausurplan is legitimately empty over the summer, and refusing
/// it then would send the user back to IServ to fix a link that is already
/// right.
class _LinkFoundNote extends StatelessWidget {
  final _ConnectFlow flow;

  const _LinkFoundNote({required this.flow});

  @override
  Widget build(BuildContext context) {
    final none = flow.probedEvents == 0;
    final color = none ? AppColors.muted : Theme.of(context).colorScheme.primary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(none ? LucideIcons.info : LucideIcons.circleCheck, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            none ? L.s.noEventsAtLinkYet : L.s.eventsFoundAtLink(flow.probedEvents),
            style: AppText.caption.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// What the WebUntis key turned out to reach, over the naming step.
///
/// The count answers the question a parent actually has at this moment — is
/// this the right child? — together with the headline above it, which is the
/// name Untis gave back rather than one anybody typed. An empty fortnight is
/// reported as working: a timetable is legitimately empty over the holidays,
/// and calling that a failure would send somebody back to WebUntis to fix a key
/// that is already right.
class _UntisFoundNote extends StatelessWidget {
  final _ConnectFlow flow;

  const _UntisFoundNote({required this.flow});

  @override
  Widget build(BuildContext context) {
    final none = flow.probedLessons == 0;
    final color = none ? AppColors.muted : Theme.of(context).colorScheme.primary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(none ? LucideIcons.info : LucideIcons.circleCheck, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            none ? L.s.noLessonsYet : L.s.lessonsFound(flow.probedLessons),
            style: AppText.caption.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// One calendar's name, typed into the row itself.
///
/// Geometry copied from [SettingsRow] on purpose — same 15/13 padding, same
/// round leading tile, same title size — because this *is* the row the step
/// before it ticked, and a name is edited where it is read rather than in a
/// boxed field under a caption repeating it.
///
/// The provider's own name does double duty: it is the placeholder, so an
/// emptied row shows the name it will fall back to (which is what [_nameFor]
/// then writes), and it reappears as the subtitle once the household types
/// something else, so "Familie" renamed to "Zuhause" still says which calendar
/// at Apple it came from. Unchanged, it would only say the same word twice.
class _CalendarNameRow extends StatelessWidget {
  final RemoteCalendar calendar;
  final TextEditingController controller;
  final bool enabled;
  final bool isLast;
  final VoidCallback onSubmitted;

  const _CalendarNameRow({
    required this.calendar,
    required this.controller,
    required this.enabled,
    required this.isLast,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: AppColors.surfaceAlt, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(LucideIcons.calendar, size: 17, color: accent),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, field) {
                final typed = value.text.trim();
                final note = [
                  if (typed.isNotEmpty && typed != calendar.name) calendar.name,
                  if (calendar.readOnly) L.s.readOnlyCalendar,
                ];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    field!,
                    if (note.isNotEmpty)
                      Text(
                        note.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.label,
                      ),
                  ],
                );
              },
              // Built once and handed to the builder: rebuilding a focused
              // TextField on every keystroke is how a field loses its caret.
              child: TextField(
                controller: controller,
                enabled: enabled,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: isLast ? TextInputAction.done : TextInputAction.next,
                style: AppText.rowTitle,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  hintText: calendar.name,
                  hintStyle: AppText.rowTitle.copyWith(color: AppColors.mutedLight),
                ),
                onSubmitted: (_) {
                  if (isLast) onSubmitted();
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          // The one thing the row's shape doesn't say by itself: that it can be
          // typed in. Muted, because it is a hint and not a button — the field
          // beside it is already the target.
          Icon(LucideIcons.pencil, size: 15, color: AppColors.mutedLight),
        ],
      ),
    );
  }
}

/// The unticked half of [_CheckBadge] — same 22pt circle, so a list of them
/// does not shift by a pixel as they are tapped.
class _EmptyBadge extends StatelessWidget {
  const _EmptyBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.hairline, width: 1.5),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ferien
// ---------------------------------------------------------------------------

/// Sixteen rows, one tick. Picking is not connecting: the Bundesland travels to
/// the name step and is subscribed there, so a mis-tap costs another tap rather
/// than a calendar you then have to find and remove.
///
/// The ones this household already reads stay in the list, ticked and
/// untappable. Hiding them would make "Niedersachsen" missing from the sixteen
/// look like a bug, and a household on a Länder border needs to see which of
/// the two it already has.
class _RegionStep extends ConsumerWidget {
  final _ConnectFlow flow;

  const _RegionStep({super.key, required this.flow});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = {
      for (final c in ref.watch(calendarConnectionsProvider).of(CalendarProvider.ferien))
        c.account,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          radius: AppRadii.card,
          children: dividedRows(inset: true, [
            FieldGroup(label: L.s.bundesland, hint: L.s.holidaysIntro),
            for (final entry in bundeslaender.entries)
              if (connected.contains(entry.key))
                SettingsRow(
                  title: entry.value,
                  subtitle: L.s.connected,
                  trailing: Icon(LucideIcons.check, size: 18, color: AppColors.muted),
                )
              else
                SettingsRow(
                  title: entry.value,
                  trailing: flow.region == entry.key
                      ? const _CheckBadge()
                      // Not const: the border is a palette colour, and a const
                      // instance would keep painting the palette it was born
                      // with.
                      : _EmptyBadge(),
                  onTap: () => flow.pickRegion(entry.key),
                ),
          ]),
        ),
        _StepError(flow.error),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Abfall
// ---------------------------------------------------------------------------

/// Step 1 for Abfall: type an address, tap it, and the vendor lookup runs on
/// the spot. A resolved address moves the flow on by itself — see
/// [_ConnectFlow.pickAddress].
class _AddressStep extends StatelessWidget {
  final _ConnectFlow flow;

  const _AddressStep({super.key, required this.flow});

  @override
  Widget build(BuildContext context) {
    // One card for the whole lookup: the field, the suggestions and the address
    // we settled on, so the step never grows a second half.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(radius: AppRadii.card, children: dividedRows(inset: true, _rows(context))),
        _StepError(flow.error),
      ],
    );
  }

  List<Widget> _rows(BuildContext context) {
    final address = flow.address;
    if (address == null) {
      return [
        FieldGroup(
          label: L.s.yourAddress,
          hint: L.s.yourAddressHint,
          child: FieldBox(
            child: TextField(
              controller: flow.query,
              focusNode: flow.searchFocus,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.words,
              style: AppText.searchInput,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: L.s.addressPlaceholder,
                isDense: true,
              ),
              onChanged: flow.onQueryChanged,
            ),
          ),
        ),
        if (flow.searching)
          _BusyRow(L.s.searchingAddresses)
        else if (flow.results.isEmpty && flow.query.text.trim().length >= 3)
          _MessageRow(L.s.noAddressFound),
        for (final found in flow.results)
          SettingsRow(
            icon: found.prefix ? LucideIcons.mapPin : LucideIcons.house,
            title: found.label,
            onTap: () => flow.pickAddress(context, found),
          ),
      ];
    }

    // The lookup either ran (coverage) or failed (its message sits under the
    // card). Either way the row is tappable: it carries the flow on, or runs
    // the lookup again — nobody has to retype an address that is already right.
    final coverage = flow.coverage;
    final failed = !flow.resolving && coverage == null;

    return [
      FieldGroup(label: L.s.yourAddress),
      SettingsRow(
        icon: LucideIcons.house,
        title: address.label,
        subtitle: flow.resolving
            ? L.s.searchingVendor
            : failed
            ? L.s.tapToRetry
            : coverage!.supported
            ? L.s.foundVendor(
                '${coverage.town}${coverage.street == null ? '' : ', ${coverage.street}'}',
              )
            : L.s.noVendorFoundTapForLink,
        onTap: flow.resolving
            ? null
            : failed
            ? () => flow.pickAddress(context, address)
            : () => flow.next(context),
        trailing: GestureDetector(
          onTap: flow.resetAddress,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Icon(LucideIcons.x, size: 17, color: AppColors.muted),
          ),
        ),
      ),
      if (flow.resolving) _BusyRow(L.s.askingNearbyVendors),
    ];
  }
}

/// The one thing a resolved address can still leave open — and only then does
/// this step exist at all.
///
/// Two shapes, one question: a street the vendor publishes several plans for
/// asks which Abfuhrbezirk, and a town no vendor of ours serves asks for the
/// link to the town's own calendar. Both are about the address on the step
/// before, which is why they are one step and not two.
class _DetailsStep extends StatelessWidget {
  final _ConnectFlow flow;

  const _DetailsStep({super.key, required this.flow});

  @override
  Widget build(BuildContext context) {
    final coverage = flow.coverage!;
    final supported = coverage.supported;
    final town = coverage.town.isNotEmpty ? coverage.town : (flow.address?.town ?? '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepHeadline(provider: flow.provider, name: flow.headline),
        const SizedBox(height: 14),
        Text(
          supported ? L.s.wasteIntro : L.s.noVendorForTown(town),
          style: AppText.body.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 18),
        SectionCard(
          radius: AppRadii.card,
          children: dividedRows(inset: true, [
            if (supported)
              FieldGroup(
                label: L.s.houseNumber,
                hint: L.s.multipleDistrictsHint,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final houseNumber in coverage.houseNumbers)
                      _Chip(
                        label: houseNumber.nr,
                        selected: flow.houseNumber?.id == houseNumber.id,
                        onTap: () => flow.pickHouseNumber(houseNumber),
                      ),
                  ],
                ),
              )
            else
              FieldGroup(
                label: L.s.calendarLinkIcs,
                hint: L.s.calendarLinkHint,
                child: FieldBox(
                  child: TextField(
                    controller: flow.icsUrl,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    style: AppText.searchInput,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'https://…',
                      isDense: true,
                    ),
                    onSubmitted: (_) => flow.next(context),
                  ),
                ),
              ),
          ]),
        ),
        _StepError(flow.error),
        if (flow.busy) _StepBusyRow(L.s.checkingLinkEllipsis),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Small shared pieces
// ---------------------------------------------------------------------------

/// A spinner and a line of text, shaped like a row so it can sit inside a card
/// between the field it belongs to and whatever it is about to produce.
class _BusyRow extends StatelessWidget {
  final String label;
  const _BusyRow(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      child: Row(
        children: [
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: AppText.body.copyWith(color: AppColors.muted))),
        ],
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  final String text;
  const _MessageRow(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      child: Text(text, style: AppText.body.copyWith(color: AppColors.muted)),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.12) : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.iconTile),
          border: Border.all(color: selected ? accent : AppColors.hairline2),
        ),
        child: Text(
          label,
          style: AppText.body.copyWith(color: selected ? accent : AppColors.ink),
        ),
      ),
    );
  }
}
