import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/repositories/calendar_connection_repository.dart';
import '../models/calendar_connection.dart';
import '../services/external_links.dart';
import '../state/calendar_connections_state.dart';
import '../state/family_state.dart';
import '../theme/tokens.dart';
import '../widgets/anchored_menu.dart';
import '../widgets/app_sheet.dart';
import '../widgets/connect_confirm_sheet.dart';
import '../widgets/error_note.dart';
import '../widgets/settings_chrome.dart';
import '../widgets/swipe_actions.dart';

/// Settings → Kalender. The six providers, each saying whether this household
/// has connected it.
///
/// Deliberately *only* the providers: the connected calendars themselves live
/// one tap down, on the page of the provider they belong to. A separate
/// "VERBUNDEN" list up here said the same thing twice — a household with the
/// bin calendar and two Bundesländer read its own name back three times before
/// reaching the list of things it could add.
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
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(calendarConnectionsProvider);
    final notifier = ref.read(calendarConnectionsProvider.notifier);
    final isKid = ref.watch(myRoleProvider) == FamilyRole.kid;

    return SettingsDetailPage(
      icon: LucideIcons.calendarDays,
      title: 'Kalender verbinden',
      description:
          'Sieh die Termine deiner Familie in der App — Schule, Abfallabfuhr und '
          'private Kalender an einem Ort.',
      children: [
        if (state.error case final message?) ...[
          ErrorNote(message: message, onRetry: notifier.load),
          const SizedBox(height: 14),
        ],

        // A kid may look, not connect — so they get the plain list of what the
        // household reads, without the six ways of adding another.
        if (isKid) ...[
          const _Note(
            'Kalender verbindet ein Erwachsener im Haushalt. Die verbundenen '
            'Termine siehst du danach ganz normal im Kalender.',
          ),
          if (state.connections.isNotEmpty) ...[
            const GroupLabel('VERBUNDEN'),
            SectionCard(
              radius: AppRadii.card,
              children: dividedRows(inset: true, [
                for (final connection in state.connections)
                  SettingsRow(
                    leading: _ProviderTile(connection.provider),
                    title: connection.displayName,
                    subtitle: lastSyncedLabel(connection.lastSyncedAt),
                    trailing: const _CheckBadge(),
                  ),
              ]),
            ),
          ],
        ] else ...[
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

          // No "Alle Kalender aktualisieren" here, and no per-provider one
          // either: opening Kalender already calls `calendar-events`, which is
          // the same read — it goes out to every account and feed and writes
          // back each connection's status. A button that repeats what the app
          // does on its own only teaches people that a connection needs
          // tending.
        ],

        // The one thing the list itself cannot say: an empty list may mean "not
        // loaded yet" rather than "nothing connected".
        if (!state.loaded) ...[
          const SizedBox(height: 16),
          Center(
            child: Text('Wird geladen …', style: AppText.body.copyWith(color: AppColors.muted)),
          ),
        ],
      ],
    );
  }
}

String lastSyncedLabel(DateTime? at) {
  if (at == null) return 'Noch nicht synchronisiert';
  final ago = DateTime.now().difference(at);
  if (ago.inMinutes < 2) return 'Gerade synchronisiert';
  if (ago.inHours < 1) return 'Vor ${ago.inMinutes} Minuten synchronisiert';
  if (ago.inDays < 1) return 'Vor ${ago.inHours} Stunden synchronisiert';
  return 'Vor ${ago.inDays} Tagen synchronisiert';
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
  return 'Das hat gerade nicht geklappt.';
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
    final label = attention
        ? 'Aktion nötig'
        : connections.length == 1
        ? 'Verbunden'
        : '${connections.length} Kalender';

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
// One provider
// ---------------------------------------------------------------------------

/// Everything about one provider on one page: what is connected (one card, one
/// row each, however many there are) and the single way of adding another.
class _ProviderPage extends ConsumerWidget {
  final CalendarProvider provider;
  const _ProviderPage(this.provider);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connections = ref.watch(calendarConnectionsProvider).of(provider);

    return SettingsDetailPage(
      icon: provider.icon,
      title: provider.label,
      description: provider.blurb,
      children: [
        if (connections.isNotEmpty) ...[
          const GroupLabel('VERBUNDEN'),
          SectionCard(
            radius: AppRadii.card,
            children: dividedRows(inset: true, [
              for (final connection in connections)
                _ConnectedRow(key: ValueKey(connection.id), connection: connection),
            ]),
          ),
          const SizedBox(height: 22),
        ],
        switch (provider.kind) {
          ConnectKind.oauth => _OAuthConnect(provider),
          ConnectKind.password => _CaldavConnect(provider),
          ConnectKind.feed when provider == CalendarProvider.ferien => const _FerienConnect(),
          ConnectKind.feed => const _AbfallConnect(),
        },
      ],
    );
  }
}

/// One connected calendar: its name, when it last synced, a blue tick — and the
/// two things you can do to it, behind the "…" or a swipe.
///
/// The actions used to be two extra rows under every single connection, which
/// is how a household with three Ferien-Kalendern ended up with nine rows for
/// three calendars. Renaming and removing are things done *to* a row, so they
/// belong on the row.
class _ConnectedRow extends ConsumerStatefulWidget {
  final CalendarConnection connection;

  const _ConnectedRow({super.key, required this.connection});

  @override
  ConsumerState<_ConnectedRow> createState() => _ConnectedRowState();
}

class _ConnectedRowState extends ConsumerState<_ConnectedRow> {
  CalendarConnection get _connection => widget.connection;

  Future<void> _rename() => showConnectConfirmSheet(
    context: context,
    icon: _connection.provider.icon,
    title: 'Kalender umbenennen',
    headline: _connection.displayName,
    message: 'Unter diesem Namen taucht der Kalender in Aporah auf — im Kalender, '
        'in den Filtern und hier.',
    initialName: _connection.displayName,
    fieldHint: 'Nur für euren Haushalt.',
    busyLabel: 'Wird gespeichert …',
    successLabel: 'Name geändert',
    errorText: connectErrorText,
    onConfirm: (name) =>
        ref.read(calendarConnectionsProvider.notifier).rename(_connection, name),
  );

  void _confirmRemove() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_connection.isFeed ? 'Kalender entfernen?' : 'Verbindung trennen?'),
        content: Text(
          '„${_connection.displayName}" verschwindet aus eurem Kalender. '
          '${switch (_connection.provider.kind) {
            ConnectKind.oauth => 'Der Zugriff wird auch beim Anbieter widerrufen.',
            // A feed is shared with every other household that wants the same
            // Bundesland or street, so leaving it removes nothing but this
            // household's subscription.
            ConnectKind.feed => 'Nur für euren Haushalt — andere behalten den Kalender.',
            ConnectKind.password => 'Eure Zugangsdaten werden gelöscht.',
          }}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () {
              ref.read(calendarConnectionsProvider.notifier).disconnect(_connection);
              Navigator.of(dialogContext).pop();
            },
            child: Text('Entfernen', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  List<AnchoredMenuItem> get _menuItems => [
    AnchoredMenuItem(label: 'Umbenennen', icon: LucideIcons.pencil, onSelected: _rename),
    AnchoredMenuItem(
      label: _connection.isFeed ? 'Entfernen' : 'Trennen',
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
          title: _connection.displayName,
          subtitle: attention
              ? (_connection.statusDetail ?? 'Die Verbindung braucht Aufmerksamkeit.')
              : refreshing
              ? 'Wird aktualisiert …'
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
// OAuth — Google, Outlook
// ---------------------------------------------------------------------------

class _OAuthConnect extends ConsumerStatefulWidget {
  final CalendarProvider provider;
  const _OAuthConnect(this.provider);

  @override
  ConsumerState<_OAuthConnect> createState() => _OAuthConnectState();
}

class _OAuthConnectState extends ConsumerState<_OAuthConnect> with WidgetsBindingObserver {
  bool _busy = false;
  bool _awaitingReturn = false;
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
      unawaited(_finish());
    }
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    _knownIds = {
      for (final c in ref.read(calendarConnectionsProvider).of(widget.provider)) c.id,
    };

    try {
      final url = await ref.read(calendarConnectionsProvider.notifier).oauthUrl(widget.provider);
      if (!mounted) return;

      if (url == null) {
        setState(() {
          _busy = false;
          _error = ref.read(calendarConnectionsProvider).error ??
              '${widget.provider.label} ist noch nicht eingerichtet.';
        });
        return;
      }

      final opened = await openExternalUrl(url);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _awaitingReturn = opened;
        _error = opened ? null : 'Der Browser konnte nicht geöffnet werden.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = connectErrorText(e);
      });
    }
  }

  /// Back from the browser: read the list, and if a connection appeared, end
  /// the flow the same way every other provider ends it — name it, confirm it,
  /// see that it worked.
  Future<void> _finish() async {
    final notifier = ref.read(calendarConnectionsProvider.notifier);
    await notifier.load();
    if (!mounted) return;

    final fresh = [
      for (final c in ref.read(calendarConnectionsProvider).of(widget.provider))
        if (!_knownIds.contains(c.id)) c,
    ];
    if (fresh.isEmpty) {
      // Cancelled at the consent screen, or the callback has not landed yet.
      setState(() {});
      return;
    }

    final connection = fresh.first;
    await showConnectConfirmSheet(
      context: context,
      icon: widget.provider.icon,
      title: '${widget.provider.label} verbinden',
      headline: connection.displayName,
      message:
          'Aporah darf jetzt die Kalender dieses Kontos lesen. Gib dem Kalender '
          'einen Namen, unter dem ihr ihn in Aporah wiedererkennt.',
      initialName: connection.displayName,
      busyLabel: 'Wird gespeichert …',
      errorText: connectErrorText,
      onConfirm: (name) => notifier.rename(connection, name),
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.provider == CalendarProvider.google ? 'Google' : 'Microsoft';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Note(
          'Du wirst zu $label weitergeleitet und meldest dich dort an. '
          'Aporah sieht nur deine Kalender — nie dein Passwort.',
        ),
        if (_error case final message?) ...[
          const SizedBox(height: 14),
          ErrorNote(message: message),
        ],
        const SizedBox(height: 14),
        AccentAction(
          icon: _busy ? LucideIcons.loaderCircle : LucideIcons.externalLink,
          label: _busy ? 'Wird geöffnet …' : 'Mit ${widget.provider.label} anmelden',
          onTap: _busy ? () {} : _start,
        ),
        if (_awaitingReturn) ...[
          const SizedBox(height: 14),
          const _Note(
            'Sobald du im Browser fertig bist, komm zurück zu Aporah — die '
            'Verbindung erscheint dann hier.',
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// CalDAV — iCloud, IServ
// ---------------------------------------------------------------------------

class _CaldavConnect extends ConsumerStatefulWidget {
  final CalendarProvider provider;
  const _CaldavConnect(this.provider);

  @override
  ConsumerState<_CaldavConnect> createState() => _CaldavConnectState();
}

class _CaldavConnectState extends ConsumerState<_CaldavConnect> {
  final _user = TextEditingController();
  final _password = TextEditingController();
  final _server = TextEditingController();

  bool _busy = false;
  String? _error;

  bool get _isIserv => widget.provider == CalendarProvider.iserv;

  @override
  void dispose() {
    _user.dispose();
    _password.dispose();
    _server.dispose();
    super.dispose();
  }

  /// The credentials are checked *here*, not in the confirm sheet: a wrong
  /// password belongs next to the password box. Only once the server has
  /// answered does the flow join the shared last step.
  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final notifier = ref.read(calendarConnectionsProvider.notifier);
      final result = await notifier.connectCaldav(
        provider: widget.provider,
        username: _user.text.trim(),
        password: _password.text,
        server: _isIserv ? _server.text : null,
      );
      if (!mounted) return;
      _password.clear();
      setState(() => _busy = false);

      final id = result.id;
      final connection = id == null
          ? null
          : _byId(ref.read(calendarConnectionsProvider).connections, id);
      if (connection == null) {
        showErrorSnack(context, 'Verbunden.');
        return;
      }

      await showConnectConfirmSheet(
        context: context,
        icon: widget.provider.icon,
        title: '${widget.provider.label} verbinden',
        headline: connection.displayName,
        message: result.calendars.isEmpty
            ? 'Die Anmeldung hat geklappt. Gib dem Kalender einen Namen, unter '
                  'dem ihr ihn in Aporah wiedererkennt.'
            : '${result.calendars.length} Kalender gefunden. Gib ihnen einen Namen, '
                  'unter dem ihr sie in Aporah wiedererkennt.',
        initialName: connection.displayName,
        busyLabel: 'Wird gespeichert …',
        errorText: connectErrorText,
        onConfirm: (name) => ref
            .read(calendarConnectionsProvider.notifier)
            .rename(connection, name),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = connectErrorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Note(
          _isIserv
              ? 'Gib die Adresse deiner Schule an (z. B. schule.de) und melde dich '
                    'mit deinem IServ-Zugang an. Schulkalender werden nur gelesen.'
              : 'iCloud verlangt ein app-spezifisches Passwort. Dein normales '
                    'Apple-ID-Passwort funktioniert hier nicht.',
        ),
        if (!_isIserv) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => openExternalUrl('https://appleid.apple.com/account/manage'),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Icon(LucideIcons.externalLink, size: 15, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'App-spezifisches Passwort erstellen',
                  style: AppText.body.copyWith(color: Theme.of(context).colorScheme.primary),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        SectionCard(
          radius: AppRadii.card,
          children: dividedRows(inset: true, [
            if (_isIserv)
              FieldGroup(
                label: 'Schule',
                hint: 'Die Adresse, unter der ihr IServ öffnet.',
                child: FieldBox(
                  child: TextField(
                    controller: _server,
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
              label: _isIserv ? 'Benutzername' : 'Apple-ID',
              child: FieldBox(
                child: TextField(
                  controller: _user,
                  keyboardType: _isIserv ? TextInputType.text : TextInputType.emailAddress,
                  autocorrect: false,
                  style: AppText.searchInput,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: _isIserv ? 'vorname.nachname' : 'name@icloud.com',
                    isDense: true,
                  ),
                ),
              ),
            ),
            FieldGroup(
              label: 'Passwort',
              child: FieldBox(
                child: TextField(
                  controller: _password,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: AppText.searchInput,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: _isIserv ? 'IServ-Passwort' : 'xxxx-xxxx-xxxx-xxxx',
                    isDense: true,
                  ),
                ),
              ),
            ),
          ]),
        ),
        if (_error case final message?) ...[
          const SizedBox(height: 14),
          ErrorNote(message: message),
        ],
        const SizedBox(height: 14),
        AccentAction(
          icon: _busy ? LucideIcons.loaderCircle : LucideIcons.link,
          label: _busy ? 'Wird geprüft …' : 'Verbinden',
          onTap: _busy ? () {} : _connect,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Ferien
// ---------------------------------------------------------------------------

/// Sixteen rows, one tap. What the tap opens — not what it connects — is the
/// shared confirm sheet, so picking a Bundesland by accident costs a swipe
/// down rather than a calendar you then have to find and remove.
class _FerienConnect extends ConsumerWidget {
  const _FerienConnect();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = {
      for (final c in ref.watch(calendarConnectionsProvider).of(CalendarProvider.ferien))
        c.account,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const GroupLabel('BUNDESLAND WÄHLEN'),
        const _Note(
          'Die Schulferien kommen von OpenHolidays — kostenlos und ohne Konto. '
          'Ihr könnt mehrere Bundesländer verbinden.',
        ),
        const SizedBox(height: 14),
        SectionCard(
          radius: AppRadii.card,
          children: dividedRows(inset: true, [
            for (final entry in bundeslaender.entries)
              SettingsRow(
                title: entry.value,
                trailing: connected.contains(entry.key) ? const _CheckBadge() : null,
                onTap: connected.contains(entry.key)
                    ? null
                    : () => _pick(context, ref, entry.key, entry.value),
              ),
          ]),
        ),
      ],
    );
  }

  Future<void> _pick(BuildContext context, WidgetRef ref, String code, String name) {
    return showConnectConfirmSheet(
      context: context,
      icon: CalendarProvider.ferien.icon,
      title: 'Ferien verbinden',
      headline: 'Schulferien $name',
      message:
          'Du hast $name ausgewählt. Die Ferientermine erscheinen danach in eurem '
          'Kalender — für alle im Haushalt.',
      initialName: 'Schulferien $name',
      errorText: connectErrorText,
      onConfirm: (label) => ref
          .read(calendarConnectionsProvider.notifier)
          .connectFerien(code, displayName: label),
    );
  }
}

// ---------------------------------------------------------------------------
// Abfall
// ---------------------------------------------------------------------------

/// One card, one address, one flow: type, pick, we look up the vendor, and the
/// same confirm sheet as every other provider finishes it.
///
/// Coverage is checked **after** the user picks, never while typing. Matching
/// against the vendors' own street lists as you type was the old app's first
/// design and it made every uncovered address look like a broken text field.
class _AbfallConnect extends ConsumerStatefulWidget {
  const _AbfallConnect();

  @override
  ConsumerState<_AbfallConnect> createState() => _AbfallConnectState();
}

class _AbfallConnectState extends ConsumerState<_AbfallConnect> {
  final _query = TextEditingController();
  final _icsUrl = TextEditingController();
  final _focus = FocusNode();

  Timer? _debounce;
  List<GeoAddress> _results = const [];
  bool _searching = false;

  GeoAddress? _picked;
  bool _resolving = false;
  AbfallCoverage? _coverage;
  HouseNumber? _houseNumber;

  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _icsUrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() => _error = null);
    _debounce?.cancel();

    final query = value.trim();
    if (query.length < 3) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }

    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(query));
  }

  Future<void> _search(String query) async {
    try {
      final results = await ref
          .read(calendarConnectionRepositoryProvider)
          .searchAddresses(query);
      if (!mounted || _query.text.trim() != query) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = connectErrorText(e);
      });
    }
  }

  Future<void> _pick(GeoAddress address) async {
    // A bare postcode is a prefix, not an address: refill the field and let the
    // user carry on typing the street.
    if (address.prefix) {
      _query.text = '${address.postcode ?? ''} ${address.town} ';
      _query.selection = TextSelection.collapsed(offset: _query.text.length);
      setState(() => _results = const []);
      _focus.requestFocus();
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _picked = address;
      _results = const [];
      _coverage = null;
      _houseNumber = null;
      _error = null;
      _resolving = true;
    });

    try {
      final coverage = await ref
          .read(calendarConnectionRepositoryProvider)
          .resolveAddress(address);
      if (!mounted) return;
      setState(() {
        _coverage = coverage;
        _resolving = false;
      });
      // Picking the address *is* the "weiter": the lookup has nothing more to
      // ask, so the sheet opens itself. Both endings go through it — a covered
      // street to be named, or the ICS link for a town no vendor serves.
      await _openSheet();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _error = connectErrorText(e);
      });
    }
  }

  /// Back to an empty field — after a connect, or when the X on the address row
  /// is tapped. The query goes too: leaving the old address in the field made
  /// the card claim "Keine Adresse gefunden" about the address it had just
  /// connected.
  void _reset() {
    _query.clear();
    _icsUrl.clear();
    setState(() {
      _picked = null;
      _coverage = null;
      _houseNumber = null;
      _results = const [];
      _error = null;
    });
  }

  String get _suggestedName {
    final address = _picked!;
    final nr = _houseNumber?.nr ?? address.houseNumber;
    final street = address.street.isNotEmpty ? address.street : address.town;
    return 'Abfall $street${nr == null || nr.isEmpty ? '' : ' $nr'}';
  }

  /// The end of the flow, whichever way the lookup went.
  ///
  /// One sheet, two contents: a covered street gets a name (and the
  /// Abfuhrbezirk chips, when the vendor publishes several plans for it); a town
  /// nobody serves gets the field for its own Kalender-Link. Neither is a page
  /// of its own — the user answered the only question this screen has when they
  /// tapped their address.
  Future<void> _openSheet() async {
    final coverage = _coverage;
    final address = _picked;
    if (coverage == null || address == null) return;

    final connected = coverage.supported && coverage.config != null
        ? await _confirmVendor(coverage, address)
        : await _confirmIcs(coverage, address);
    if (connected && mounted) _reset();
  }

  Future<bool> _confirmVendor(AbfallCoverage coverage, GeoAddress address) {
    return showConnectConfirmSheet(
      context: context,
      icon: CalendarProvider.abfall.icon,
      title: 'Abfall verbinden',
      headline: coverage.street == null
          ? coverage.town
          : '${coverage.street}, ${coverage.town}',
      message:
          'Restmüll, Bio, Papier und Gelbe Tonne kommen automatisch in euren '
          'Kalender — für alle im Haushalt.',
      initialName: _suggestedName,
      errorText: connectErrorText,
      extraFields: [
        if (coverage.houseNumbers.isNotEmpty)
          FieldGroup(
            label: 'Hausnummer',
            hint: 'Diese Straße hat mehrere Abfuhrbezirke. Ohne Auswahl gilt der '
                'Plan der ganzen Straße.',
            // The chips redraw inside the sheet, so the selection needs a
            // `setState` that reaches the sheet's own subtree — this screen's
            // would rebuild the page behind it and nothing else.
            child: StatefulBuilder(
              builder: (context, setSheetState) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final houseNumber in coverage.houseNumbers)
                    _Chip(
                      label: houseNumber.nr,
                      selected: _houseNumber?.id == houseNumber.id,
                      onTap: () => setSheetState(
                        () => _houseNumber =
                            _houseNumber?.id == houseNumber.id ? null : houseNumber,
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
      onConfirm: (label) => ref.read(calendarConnectionsProvider.notifier).connectAbfall(
        config: coverage.config!,
        label: address.label,
        houseNumber: _houseNumber,
        displayName: label,
      ),
    );
  }

  /// The manual fallback for a town no vendor of ours serves: a link the user
  /// fetches from their own municipality's site. It is checked when the blue
  /// check is tapped, so a dead link is reported right under the field it was
  /// typed into instead of closing the sheet on a lie.
  Future<bool> _confirmIcs(AbfallCoverage coverage, GeoAddress address) {
    final town = coverage.town.isNotEmpty ? coverage.town : address.town;
    return showConnectConfirmSheet(
      context: context,
      icon: CalendarProvider.abfall.icon,
      title: 'Abfall verbinden',
      headline: town,
      message:
          'Für $town kennen wir leider noch keinen Entsorger. Die meisten '
          'veröffentlichen ihre Termine selbst: such auf der Seite eures '
          'Entsorgers nach „Abfuhrkalender" oder „Kalender abonnieren" und setz '
          'den Link hier ein.',
      initialName: 'Abfall $town',
      busyLabel: 'Link wird geprüft …',
      errorText: connectErrorText,
      extraFields: [
        FieldGroup(
          label: 'Kalender-Link (ICS)',
          hint: 'Endet meist auf .ics — der Link hinter "Kalender abonnieren".',
          child: FieldBox(
            child: TextField(
              controller: _icsUrl,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              style: AppText.searchInput,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'https://…',
                isDense: true,
              ),
            ),
          ),
        ),
      ],
      onConfirm: (label) async {
        final url = _icsUrl.text.trim();
        if (url.isEmpty) {
          throw const CalendarConnectionException('Setz hier den Kalender-Link ein.');
        }
        final ok = await ref.read(calendarConnectionRepositoryProvider).checkIcsUrl(url);
        if (!ok) {
          throw const CalendarConnectionException(
            'Unter diesem Link wurden keine Termine gefunden. Ist es der Link '
            'zum Kalender selbst?',
          );
        }
        await ref
            .read(calendarConnectionsProvider.notifier)
            .connectIcs(url: url, label: address.label, displayName: label);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final coverage = _coverage;
    final supported = coverage?.supported == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const GroupLabel('ADRESSE'),
        const _Note(
          'Tipp eure Adresse ein und wähl sie aus — Aporah sucht den zuständigen '
          'Entsorger und fragt dann nur noch, wie der Kalender heißen soll.',
        ),
        const SizedBox(height: 14),

        // One card for the whole lookup: the field, the suggestions and the
        // address we settled on. Everything after that happens in the confirm
        // sheet, so the page never grows a second half.
        SectionCard(radius: AppRadii.card, children: dividedRows(inset: true, _cardRows(coverage, supported))),

        if (_error case final message?) ...[
          const SizedBox(height: 14),
          ErrorNote(message: message),
        ],
      ],
    );
  }

  List<Widget> _cardRows(AbfallCoverage? coverage, bool supported) {
    if (_picked == null) {
      return [
        FieldGroup(
          label: 'Eure Adresse',
          hint: 'Straße und Hausnummer, dann den Ort.',
          child: FieldBox(
            child: TextField(
              controller: _query,
              focusNode: _focus,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.words,
              style: AppText.searchInput,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Straße Hausnummer, Ort',
                isDense: true,
              ),
              onChanged: _onQueryChanged,
            ),
          ),
        ),
        if (_searching)
          const _BusyRow('Adressen werden gesucht …')
        else if (_results.isEmpty && _query.text.trim().length >= 3)
          const _MessageRow('Keine Adresse gefunden.'),
        for (final address in _results)
          SettingsRow(
            icon: address.prefix ? LucideIcons.mapPin : LucideIcons.house,
            title: address.label,
            onTap: () => _pick(address),
          ),
      ];
    }

    // The lookup either ran (coverage) or failed (the message sits in the
    // [ErrorNote] under the card). Either way the row is tappable: it reopens
    // the sheet the user closed, or runs the lookup again — nobody has to
    // retype an address that is already right.
    final failed = !_resolving && coverage == null;

    return [
      SettingsRow(
        icon: LucideIcons.house,
        title: _picked!.label,
        subtitle: _resolving
            ? 'Entsorger wird gesucht …'
            : failed
            ? 'Tippen, um es noch einmal zu versuchen'
            : supported
            ? 'Gefunden: ${coverage!.town}${coverage.street == null ? '' : ', ${coverage.street}'}'
            : 'Kein Entsorger gefunden — tippen für den Kalender-Link',
        onTap: _resolving ? null : (failed ? () => _pick(_picked!) : _openSheet),
        trailing: GestureDetector(
          onTap: _reset,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Icon(LucideIcons.x, size: 17, color: AppColors.muted),
          ),
        ),
      ),
      if (_resolving) const _BusyRow('Wir fragen die Entsorger der Umgebung …'),
    ];
  }
}

// ---------------------------------------------------------------------------
// Small shared pieces
// ---------------------------------------------------------------------------

class _Note extends StatelessWidget {
  final String text;
  const _Note(this.text);

  @override
  Widget build(BuildContext context) =>
      Text(text, style: AppText.body.copyWith(color: AppColors.muted));
}

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
