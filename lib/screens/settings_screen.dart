import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/entitlements.dart';
import '../services/spend_intent.dart';
import '../state/auth_state.dart';
import '../state/calendar_connections_state.dart';
import '../state/entitlement_state.dart';
import '../state/family_state.dart';
import '../state/onboarding_state.dart';
import '../state/settings_state.dart';
import '../state/spend_state.dart';
import '../theme/tokens.dart';
import '../widgets/app_sheet.dart';
import '../widgets/avatar.dart';
import '../widgets/collapsing_header.dart';
import '../widgets/glass.dart';
import '../widgets/native_search_field.dart';
import '../widgets/settings_chrome.dart';
import 'calendar_connect_screen.dart';
import '../widgets/native_switch.dart';
import 'onboarding_screen.dart';
import 'settings/apple_pay_page.dart';
import 'settings/family_page.dart';
import 'settings/language_page.dart';
import 'settings/profile_page.dart';
import '../l10n/l10n.dart';
import '../theme/app_icons.dart';

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
///   one card, everything the household configures (calendars, language, dark
///   mode, the tour) in the next, and signing out alone in the last — it is the
///   one destructive row, so it doesn't share a card with a preference.
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
                title: L.s.settingsTitle,
                t: t,
                expandedAlignment: Alignment.center,
                expandedFontSize: 17,
                leading: GlassIconButton(icon: AppIcons.caretLeft, onTap: () => Navigator.of(context).pop()),
                leadingWidth: 48,
                trailing: GlassPillButton(label: L.s.doneAction, onTap: () => Navigator.of(context).pop()),
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
              placeholder: L.s.searchSettings,
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
          terms: '${L.s.searchTermsProfile} ${displayName.toLowerCase()}',
          row: SettingsRow(
            leading: Avatar(
              size: 44,
              bg: tone.bg,
              fg: tone.fg,
              initials: me?.initials ?? initialsOf(state.name),
              fontSize: 15,
              imageUrl: me?.avatarUrl,
            ),
            title: displayName,
            subtitle: ref.watch(myRoleProvider).label,
            onTap: () => _push(context, ProfilePage()),
          ),
        ),
        (
          terms: L.s.searchTermsFamily,
          row: SettingsRow(
            icon: AppIcons.users,
            title: L.s.familyMembers,
            accessory: AvatarStack(
              avatarSize: 30,
              avatars: [
                for (final m in members.take(3))
                  Avatar(
                    size: 30,
                    bg: m.toneColors.bg,
                    fg: m.toneColors.fg,
                    initials: m.initials,
                    fontSize: 11,
                    imageUrl: m.imageUrl,
                  ),
              ],
            ),
            onTap: () => _push(context, FamilyPage()),
          ),
        ),
      ],
      [
        (
          terms: L.s.searchTermsCalendar,
          row: SettingsRow(
            icon: AppIcons.calendarDots,
            title: L.s.calendar,
            value: _connectionSummary(ref.watch(calendarConnectionsProvider)),
            onTap: () => _push(context, CalendarConnectionsPage()),
          ),
        ),
        // Admin only, and the row is simply absent for everyone else: spends are
        // admin-only in the policies, so a member tapping through to a list of
        // the household's phones would find a page they cannot act on. Absent
        // too where Ausgaben does not ship at all (`spendAvailable`) — there
        // the page would list the *other* parent's iPhones and offer to revoke
        // them, which is a confusing amount of power over a feature this phone
        // has never seen.
        if (spendAvailable && ref.watch(isAdminProvider))
          (
            terms: L.s.searchTermsApplePay,
            row: SettingsRow(
              icon: AppIcons.wallet,
              title: L.s.settingsApplePay,
              value: _deviceSummary(ref.watch(spendProvider).devices.length),
              onTap: () => _push(context, ApplePayPage()),
            ),
          ),
        (
          terms: L.s.searchTermsLanguage,
          row: SettingsRow(
            icon: AppIcons.translate,
            title: L.s.language,
            value: state.language.label,
            onTap: () => _push(context, LanguagePage()),
          ),
        ),
        (
          terms: L.s.searchTermsDarkMode,
          row: SettingsRow(
            icon: state.darkMode ? AppIcons.moon : AppIcons.sun,
            title: L.s.darkMode,
            trailing: NativeSwitch(
              value: state.darkMode,
              onChanged: (v) => ref.read(settingsProvider.notifier).setDarkMode(v),
            ),
          ),
        ),
        (
          terms: L.s.searchTermsTour,
          row: SettingsRow(
            icon: AppIcons.confetti,
            title: L.s.welcomeTour,
            value: L.s.repeat,
            onTap: () {
              ref.read(onboardingProvider.notifier).resetForReplay();
              _push(context, OnboardingScreen(replay: true));
            },
          ),
        ),
      ],
      [
        // **Debug builds only, and it grants nothing.** Every screen from here
        // to launch has a free state and a Plus state, and the alternative to
        // this row is a second test account, a sandbox purchase to move between
        // them and a store round trip to read a paywall's wording. It forces
        // the plan the *app* believes in and cannot write `families.plan`,
        // which no client holds an update grant on — so a server-enforced limit
        // stays enforced while it is on. See `planOverrideProvider`.
        if (kDebugMode)
          (
            terms: 'plus plan debug',
            row: SettingsRow(
              icon: AppIcons.sparkle,
              title: L.s.debugPlanTitle,
              value: switch (ref.watch(planOverrideProvider)) {
                null => L.s.debugPlanReal(ref.watch(entitlementProvider).isPlus ? 'Plus' : 'Free'),
                Plan.free => L.s.debugPlanSimulated('Free'),
                Plan.plus => L.s.debugPlanSimulated('Plus'),
              },
              // Cycles real -> free -> plus -> real. A menu would be three more
              // strings and a anchor key for a row that only ever exists on a
              // developer's phone.
              onTap: () {
                final notifier = ref.read(planOverrideProvider.notifier);
                notifier.state = switch (notifier.state) {
                  null => Plan.free,
                  Plan.free => Plan.plus,
                  Plan.plus => null,
                };
              },
            ),
          ),
        (
          terms: L.s.searchTermsSignOut,
          row: SettingsRow(
            icon: AppIcons.signOut,
            title: L.s.signOut,
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
          if (i > 0) const SizedBox(height: AppSpacing.blockGap),
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
            L.s.noSettingFoundFor(_query.trim()),
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

/// The "Apple Pay" row's status text: how many phones are filing payments,
/// which is the one thing about the page worth knowing before opening it.
String _deviceSummary(int count) => L.s.spendWalletDeviceCount(count);

/// The "Kalender" row's status text. Deliberately a count rather than a list of
/// names — the row has one line, and a household with a Google account, a school
/// calendar and the bin schedule would otherwise overflow it.
String _connectionSummary(CalendarConnectionsState state) {
  if (!state.loaded) return '';
  if (state.connections.isEmpty) return L.s.notConnected;
  if (state.anyNeedsAttention) return L.s.actionNeeded;
  final n = state.connections.length;
  return L.s.calendarCount(n);
}

