import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../state/auth_state.dart';
import '../state/calendar_connections_state.dart';
import '../state/family_state.dart';
import '../state/onboarding_state.dart';
import '../state/settings_state.dart';
import '../theme/tokens.dart';
import '../widgets/app_sheet.dart';
import '../widgets/avatar.dart';
import '../widgets/collapsing_header.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_note.dart';
import '../widgets/glass.dart';
import '../widgets/native_search_field.dart';
import '../widgets/settings_chrome.dart';
import 'calendar_connect_screen.dart';
import '../widgets/native_switch.dart';
import 'onboarding_screen.dart';

/// Full-page settings hub, reached from the Start tab's avatar. No Figma
/// handoff exists for this screen (see docs/ported-features.md's "Settings"
/// section) — structure follows the old web app, styling follows this app's
/// own tokens/`SectionCard`/`CollapsingHeaderScreen` conventions.
///
/// Shape rules the whole screen family follows:
/// - Root and sub-pages all scroll under a [CollapsingHeaderScreen], the same
///   frosted, collapsing header Board/Box/Listen use — so Settings doesn't
///   read as a different app.
/// - The root list is *grouped by card*, not by caption: profile + family in
///   one card, connections in the next, app preferences in the last.
/// - Every sub-page's collapsing content introduces the page — a [HeroCard]
///   (icon → title → one sentence), or on the profile page the avatar itself —
///   and hands its title to the pinned bar once it scrolls away.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  /// Live query from the native search field. Empty means "show the normal
  /// grouped list"; anything else collapses every group into one card of hits.
  String _query = '';

  /// Gap between the floating search field and the bottom edge / keyboard.
  static const _searchGap = 10.0;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(settingsProvider);
    // The field is parked above the keyboard by hand rather than by letting
    // the Scaffold resize: the body is a NestedScrollView, and shrinking it
    // mid-scroll re-runs the collapsing header's measurement and makes the
    // bar jump while the keyboard animates in.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.surface,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: CollapsingHeaderScreen(
              // Small, centered title at every scroll position — no large
              // heading to collapse. The row already carries a back chevron
              // and a "Fertig" pill, which is a nav bar; an iOS large title
              // has no room to live beside them. Passing equal expanded and
              // collapsed font sizes (and no `extra`, so the header can't
              // collapse at all) keeps it fixed, while the header still gets
              // its frosted material and content still scrolls under it
              // blurred.
              titleRowBuilder: (context, t) => CollapsingScreenTitle(
                title: 'Einstellungen',
                t: t,
                expandedAlignment: Alignment.center,
                expandedFontSize: 17,
                leading: GlassIconButton(icon: LucideIcons.chevronLeft, onTap: () => Navigator.of(context).pop()),
                leadingWidth: 48,
                trailing: GlassPillButton(label: 'Fertig', onTap: () => Navigator.of(context).pop()),
                trailingWidth: 84,
                collapsedSideInset: 96,
              ),
              estimatedExtraHeight: 0,
              extra: const SizedBox.shrink(),
              body: ScreenBodyPanel(
                child: ListView(
                  // Last row clears the floating field the same way every
                  // other screen clears the nav bar.
                  padding: EdgeInsets.fromLTRB(16, 18, 16, safeBottom + kNativeSearchFieldHeight + 28),
                  children: _rows(context, state),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: (keyboard > 0 ? keyboard : safeBottom) + _searchGap,
            child: NativeSearchField(
              placeholder: 'Einstellungen durchsuchen',
              onChanged: (v) {
                if (v != _query) setState(() => _query = v);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Every root row paired with the words it should match on, so the grouped
  /// layout and the search results are built from one list instead of two
  /// that could drift. Terms are lowercase and include the synonyms a German
  /// speaker is likely to type for a row whose label doesn't contain them
  /// ("hell"/"nacht" for dark mode, provider names for the calendar row).
  List<Widget> _rows(BuildContext context, SettingsScreenState state) {
    final family = ref.watch(familyProvider);
    final me = family.me(ref.watch(currentUserIdProvider));

    // The signed-in user's own profile is the household's copy, not the local
    // settings copy — `profiles` is what every other member sees, so the two
    // must not be able to disagree. The local `state.name` stays as the draft
    // the profile page edits.
    final displayName = me?.name ?? state.displayName;
    final tone = AppTones.list[me?.tone ?? state.avatarTone];

    final members = ref.watch(householdMembersProvider);

    final groups = <List<({String terms, Widget row})>>[
      [
        (
          terms: 'profil konto account name anzeigename avatar farbe rolle admin ${displayName.toLowerCase()}',
          row: SettingsRow(
            leading: Avatar(
              size: 44,
              bg: tone.bg,
              fg: tone.fg,
              initials: me?.initials ?? _initials(state.name),
              fontSize: 15,
            ),
            title: displayName,
            subtitle: ref.watch(myRoleProvider).label,
            onTap: () => _push(context, _ProfilePage()),
          ),
        ),
        (
          terms: 'familie familienmitglieder mitglieder personen einladen rolle rollen kind kinder admin',
          row: SettingsRow(
            icon: LucideIcons.users,
            title: 'Familienmitglieder',
            accessory: AvatarStack(
              avatarSize: 30,
              avatars: [
                for (final m in members.take(3))
                  Avatar(size: 30, bg: m.toneColors.bg, fg: m.toneColors.fg, initials: m.initials, fontSize: 11),
              ],
            ),
            onTap: () => _push(context, _FamilyPage()),
          ),
        ),
      ],
      [
        (
          terms: 'kalender termine verbindungen verbinden google outlook icloud iserv ferien abfall schule',
          row: SettingsRow(
            icon: LucideIcons.calendarDays,
            title: 'Kalender',
            value: _connectionSummary(ref.watch(calendarConnectionsProvider)),
            onTap: () => _push(context, const CalendarConnectionsPage()),
          ),
        ),
      ],
      [
        (
          terms: 'sprache language deutsch english übersetzung',
          row: SettingsRow(
            icon: LucideIcons.languages,
            title: 'Sprache',
            value: state.language.label,
            onTap: () => _push(context, _LanguagePage()),
          ),
        ),
        (
          terms: 'dunkelmodus dark mode darstellung erscheinungsbild hell dunkel nacht theme',
          row: SettingsRow(
            icon: state.darkMode ? LucideIcons.moon : LucideIcons.sun,
            title: 'Dunkelmodus',
            trailing: NativeSwitch(
              value: state.darkMode,
              onChanged: (v) => ref.read(settingsProvider.notifier).setDarkMode(v),
            ),
          ),
        ),
        (
          terms: 'willkommenstour onboarding tour einführung wiederholen hilfe',
          row: SettingsRow(
            icon: LucideIcons.sparkles,
            title: 'Willkommenstour',
            value: 'Wiederholen',
            onTap: () {
              ref.read(onboardingProvider.notifier).resetForReplay();
              _push(context, OnboardingScreen(replay: true));
            },
          ),
        ),
      ],
      [
        (
          terms: 'abmelden logout ausloggen konto verlassen wechseln',
          row: SettingsRow(
            icon: LucideIcons.logOut,
            title: 'Abmelden',
            // Which account, spelled out — the whole point of signing out is
            // usually to get into a different one.
            subtitle: ref.watch(authProvider.select((s) => s.email)),
            onTap: () => ref.read(authProvider.notifier).signOut(),
          ),
        ),
      ],
    ];

    final query = _query.trim().toLowerCase();
    if (query.isEmpty) {
      return [
        for (final (i, group) in groups.indexed) ...[
          if (i > 0) const SizedBox(height: 14),
          SectionCard(children: dividedRows([for (final entry in group) entry.row])),
        ],
      ];
    }

    final hits = [
      for (final group in groups)
        for (final entry in group)
          if (entry.terms.contains(query)) entry.row,
    ];
    if (hits.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 40, 8, 0),
          child: Text(
            'Keine Einstellung gefunden für „${_query.trim()}"',
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(color: AppColors.muted),
          ),
        ),
      ];
    }
    return [SectionCard(children: dividedRows(hits))];
  }

  static void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }
}

/// The "Kalender" row's status text. Deliberately a count rather than a list of
/// names — the row has one line, and a household with a Google account, a school
/// calendar and the bin schedule would otherwise overflow it.
String _connectionSummary(CalendarConnectionsState state) {
  if (!state.loaded) return '';
  if (state.connections.isEmpty) return 'Nicht verbunden';
  if (state.anyNeedsAttention) return 'Aktion nötig';
  final n = state.connections.length;
  return n == 1 ? '1 Kalender' : '$n Kalender';
}

/// Initials for the signed-in user's avatar. The family members in
/// [Members.all] carry their own; only the editable profile name has to be
/// reduced on the fly.
String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
}


class _ProfilePage extends ConsumerStatefulWidget {
  const _ProfilePage();

  @override
  ConsumerState<_ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<_ProfilePage> {
  late final TextEditingController _nameController;

  static const _extraHeight = 84.0;

  @override
  void initState() {
    super.initState();
    // Seeded from the household's copy of the profile, which is what everyone
    // else sees, falling back to the local draft before the roster has loaded.
    final me = ref.read(familyProvider).me(ref.read(currentUserIdProvider));
    _nameController = TextEditingController(text: me?.name ?? ref.read(settingsProvider).name);
  }

  @override
  void dispose() {
    // Written once, on the way out, rather than on every keystroke — a request
    // per character would be both wasteful and racy.
    _householdNotifier.saveMyProfile(displayName: _nameController.text);
    _nameController.dispose();
    super.dispose();
  }

  /// Captured while the widget is still mounted: `dispose` must not touch
  /// `ref`, and the save above deliberately outlives this page.
  late final HouseholdNotifier _householdNotifier = ref.read(familyProvider.notifier);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(settingsProvider);
    final me = ref.watch(familyProvider).me(ref.watch(currentUserIdProvider));
    final displayName = me?.name ?? state.displayName;
    final tone = AppTones.list[me?.tone ?? state.avatarTone];
    final role = ref.watch(myRoleProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: false,
        // Hand-rolled rather than a [SettingsDetailPage]: the profile's own
        // avatar and name introduce the page better than a glyph and a
        // sentence, so the identity row *is* this page's hero.
        child: CollapsingHeaderScreen(
          titleRowBuilder: (context, t) => CollapsingScreenTitle(
            title: '',
            collapsedTitle: displayName,
            t: t,
            expandedAlignment: Alignment.center,
            leading: GlassIconButton(icon: LucideIcons.chevronLeft, onTap: () => Navigator.of(context).pop()),
            leadingWidth: 48,
            trailing: CloseSettingsButton(),
            trailingWidth: 48,
          ),
          estimatedExtraHeight: _extraHeight,
          extraPadding: const EdgeInsets.symmetric(horizontal: 20),
          extra: Column(
            children: [
              const SizedBox(height: 8),
              Row(
                children: [
                  Avatar(size: 64, bg: tone.bg, fg: tone.fg, initials: me?.initials ?? _initials(state.name), fontSize: 21),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.cardTitle),
                        const SizedBox(height: 2),
                        Text(role.label, style: AppText.body.copyWith(color: AppColors.muted)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
          body: ScreenBodyPanel(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
              children: [
                SectionCard(
                  radius: AppRadii.card,
                  children: dividedRows(
                    inset: true,
                    [
                      FieldGroup(
                        label: 'Anzeigename',
                        child: FieldBox(
                          child: TextField(
                            controller: _nameController,
                            style: AppText.searchInput,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              hintText: 'Name',
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onChanged: (v) => ref.read(settingsProvider.notifier).setName(v),
                          ),
                        ),
                      ),
                      FieldGroup(
                        label: 'Avatar-Farbe',
                        child: Row(
                          children: [
                            for (var i = 0; i < AppTones.list.length; i++) ...[
                              _ToneSwatch(
                                tone: AppTones.list[i],
                                selected: i == (me?.tone ?? state.avatarTone),
                                onTap: () {
                                  ref.read(settingsProvider.notifier).setAvatarTone(i);
                                  ref.read(familyProvider.notifier).saveMyProfile(tone: i);
                                },
                              ),
                              if (i != AppTones.list.length - 1) const SizedBox(width: 12),
                            ],
                          ],
                        ),
                      ),
                      FieldGroup(
                        label: 'Rolle',
                        hint: 'Admins verwalten die Familie und alle Verbindungen.',
                        child: FieldBox(
                          child: Row(
                            children: [
                              Icon(LucideIcons.shieldCheck, size: 17, color: AppColors.muted),
                              const SizedBox(width: 10),
                              Text(role.label, style: AppText.searchInput),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToneSwatch extends StatelessWidget {
  final Tone tone;
  final bool selected;
  final VoidCallback onTap;

  const _ToneSwatch({required this.tone, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Selection is an outer ring rather than a border on the swatch itself:
    // several tones are pale enough that an inset border reads as a shadow.
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: selected ? AppColors.ink : Colors.transparent, width: 1.5),
        ),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(color: tone.bg, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

class _FamilyPage extends ConsumerWidget {
  const _FamilyPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final family = ref.watch(familyProvider);
    final isAdmin = ref.watch(isAdminProvider);
    final me = ref.watch(currentUserIdProvider);

    // A refused write is reported once and forgotten. RLS is what actually
    // denies it — this only says so in German.
    ref.listen<String?>(familyProvider.select((s) => s.actionError), (_, message) {
      if (message == null) return;
      showErrorSnack(context, message);
      ref.read(familyProvider.notifier).clearActionError();
    });

    return SettingsDetailPage(
      icon: LucideIcons.users,
      title: 'Familienmitglieder',
      description: isAdmin
          ? 'Lege die Rolle jedes Familienmitglieds fest. Admins verwalten die Familie; '
              'Kinder sehen eine vereinfachte Ansicht.'
          : 'Wer zu eurem Haushalt gehört. Einladen und Rollen ändern können nur Admins.',
      children: [
        SectionCard(
          radius: AppRadii.card,
          children: family.members.isEmpty
              ? [
                  EmptyState(
                    icon: LucideIcons.users,
                    message: 'Noch niemand im Haushalt.\nLade jemanden ein, um Listen, Aufgaben und Termine zu teilen.',
                  ),
                ]
              : dividedRows(inset: true, [
                  for (final m in family.members) _MemberRow(member: m, isMe: m.userId == me, canManage: isAdmin),
                ]),
        ),
        // The gate is courtesy, not security: `invite-member` checks the role
        // itself and RLS refuses the writes regardless. Showing a control that
        // is going to be refused is just a worse way of saying no.
        if (isAdmin) ...[
          const SizedBox(height: 14),
          AccentAction(
            icon: LucideIcons.userPlus,
            label: 'Mitglied einladen',
            onTap: () => _openInviteSheet(context, ref),
          ),
        ],
        if (family.invites.isNotEmpty) ...[
          GroupLabel('Ausstehende Einladungen'),
          SectionCard(
            children: dividedRows([
              for (final invite in family.invites)
                SettingsRow(
                  icon: LucideIcons.mail,
                  title: invite.name.isNotEmpty ? invite.name : invite.email,
                  subtitle: '${invite.role.label} · ausstehend',
                  trailing: GestureDetector(
                    onTap: () => ref.read(familyProvider.notifier).revokeInvite(invite.id),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                      child: Icon(LucideIcons.x, size: 17, color: AppColors.mutedLight),
                    ),
                  ),
                ),
            ]),
          ),
        ],
      ],
    );
  }

  void _openInviteSheet(BuildContext context, WidgetRef ref) {
    final emailController = TextEditingController();
    final nameController = TextEditingController();
    final draft = _InviteDraft();
    showAppSheet(
      context: context,
      title: 'Familienmitglied einladen',
      heightFactor: 0.6,
      onSave: () => ref.read(familyProvider.notifier).inviteMember(
            email: emailController.text,
            name: nameController.text,
            role: draft.role,
          ),
      child: _InviteSheetBody(
        emailController: emailController,
        nameController: nameController,
        draft: draft,
      ),
    );
  }
}

/// The invited role, held by reference — the sheet's save button is handed its
/// callback before the body exists.
class _InviteDraft {
  FamilyRole role = FamilyRole.member;
}

class _InviteSheetBody extends StatefulWidget {
  final TextEditingController emailController;
  final TextEditingController nameController;
  final _InviteDraft draft;

  const _InviteSheetBody({
    required this.emailController,
    required this.nameController,
    required this.draft,
  });

  @override
  State<_InviteSheetBody> createState() => _InviteSheetBodyState();
}

class _InviteSheetBodyState extends State<_InviteSheetBody> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionCard(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: widget.emailController,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                style: AppText.searchInput,
                decoration: const InputDecoration(border: InputBorder.none, hintText: 'E-Mail-Adresse', isDense: true),
              ),
            ),
            CardDivider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: widget.nameController,
                style: AppText.searchInput,
                decoration: const InputDecoration(border: InputBorder.none, hintText: 'Name (optional)', isDense: true),
              ),
            ),
            CardDivider(),
            // The role is chosen when the invitation is sent, not afterwards:
            // it is written into the `family_invites` row and applied by
            // `accept-invite`, so inviting a child as an admin and demoting
            // them later would have given them full access in between.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Expanded(child: Text('Rolle', style: AppText.rowTitle)),
                  _RolePicker(
                    role: widget.draft.role,
                    onChanged: (r) => setState(() => widget.draft.role = r),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Die Einladung ist 14 Tage gültig. Wer sie annimmt, verlässt damit seinen bisherigen Haushalt.',
            style: AppText.label.copyWith(fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _MemberRow extends ConsumerWidget {
  final HouseholdMember member;
  final bool isMe;

  /// Whether the *viewer* is an admin. The row is rendered for everybody; only
  /// an admin gets the controls.
  final bool canManage;

  const _MemberRow({required this.member, required this.isMe, required this.canManage});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tone = AppTones.list[member.tone % AppTones.list.length];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Avatar(size: 40, bg: tone.bg, fg: tone.fg, initials: member.initials, fontSize: 13),
          const SizedBox(width: 13),
          Expanded(
            child: Row(
              children: [
                Flexible(child: Text(member.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.rowTitle)),
                if (isMe) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadii.iconTile),
                      border: Border.all(color: AppColors.hairline2),
                    ),
                    child: Text('DU', style: AppText.microLabel.copyWith(letterSpacing: 0.5)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Nobody demotes or removes themselves here. `enforce_last_admin`
          // would refuse it whenever they are the only admin, and when they
          // aren't, leaving a household is a different action with different
          // consequences than being removed from one.
          if (isMe || !canManage)
            Text(member.role.label, style: AppText.label)
          else ...[
            _RolePicker(
              role: member.role,
              onChanged: (r) => ref.read(familyProvider.notifier).setRole(member.userId, r),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => _confirmRemove(context, ref),
              behavior: HitTestBehavior.opaque,
              child: Icon(LucideIcons.trash2, size: 18, color: AppColors.mutedLight),
            ),
          ],
        ],
      ),
    );
  }

  void _confirmRemove(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Mitglied entfernen?'),
        // Says what actually happens, because it is not reversible:
        // `reassign_content_on_member_removal` hands their family-visible
        // content to an admin and deletes their private content outright —
        // there is no backdoor into it, by design.
        content: Text(
          '„${member.name}" verliert den Zugriff auf euren Haushalt. '
          'Gemeinsame Inhalte bleiben erhalten, private Inhalte werden gelöscht.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () {
              ref.read(familyProvider.notifier).removeMember(member.userId);
              Navigator.of(dialogContext).pop();
            },
            child: Text('Entfernen', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }
}

/// The bordered role dropdown on a member row. Deliberately a plain
/// [PopupMenuButton] rather than anything glass — see `glass.dart`: a native
/// glass platform view inside a popup's scale transition smears.
class _RolePicker extends StatelessWidget {
  final FamilyRole role;
  final ValueChanged<FamilyRole> onChanged;

  const _RolePicker({required this.role, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<FamilyRole>(
      onSelected: onChanged,
      position: PopupMenuPosition.under,
      color: AppColors.surface,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.iconTile)),
      itemBuilder: (_) => [
        for (final r in FamilyRole.values)
          PopupMenuItem(
            value: r,
            height: 42,
            child: Row(
              children: [
                Text(r.label, style: AppText.rowTitle),
                if (r == role) ...[
                  const SizedBox(width: 10),
                  Icon(LucideIcons.check, size: 15, color: Theme.of(context).colorScheme.primary),
                ],
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.iconTile),
          border: Border.all(color: AppColors.hairline2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(role.label, style: AppText.rowTitle),
            const SizedBox(width: 8),
            Icon(LucideIcons.chevronsUpDown, size: 14, color: AppColors.mutedLight),
          ],
        ),
      ),
    );
  }
}

class _LanguagePage extends ConsumerWidget {
  const _LanguagePage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(settingsProvider).language;

    return SettingsDetailPage(
      icon: LucideIcons.languages,
      title: 'Sprache',
      description: 'Bestimmt die Sprache der App. Die Oberfläche ist derzeit nur auf Deutsch '
          'übersetzt — weitere Sprachen folgen.',
      estimatedHeroHeight: 170,
      children: [
        SectionCard(
          radius: AppRadii.card,
          children: dividedRows(
            inset: true,
            [
              for (final language in AppLanguage.values)
                SettingsRow(
                  title: language.label,
                  subtitle: language.nativeSubtitle,
                  trailing: language == selected
                      ? Icon(LucideIcons.check, size: 18, color: Theme.of(context).colorScheme.primary)
                      : const SizedBox.shrink(),
                  onTap: () => ref.read(settingsProvider.notifier).setLanguage(language),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

