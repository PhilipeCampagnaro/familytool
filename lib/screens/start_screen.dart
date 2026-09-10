import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/auth_state.dart';
import '../state/family_state.dart';
import '../theme/tokens.dart';
import '../widgets/avatar.dart';
import 'calendar_screen.dart';
import 'settings_screen.dart';
import '../theme/app_icons.dart';

/// The "Home" tab: the calendar's week view — a scrolling day strip over the
/// selected day's agenda.
///
/// **Home is a day, not a summary.** The week view was one of two faces behind
/// a toggle on the Kalender tab, and it was the face a household wants nearly
/// every time it opens the app; the month grid answers a different, rarer
/// question and keeps that tab to itself. So the thing you open the app to see
/// is what the app opens on, and the toggle that used to swap them is gone —
/// the nav bar already switches between two screens.
///
/// This screen owns almost nothing. [CalendarWeekScreen] draws the view, and
/// what Home adds is the profile avatar, which is this app's only entry point
/// into Settings (the old web app's "tap your avatar on the dashboard" pattern;
/// see CLAUDE.md's "Ported feature knowledge" -> Settings). It sits opposite
/// the month/year label, in the space the view toggle left behind.
class StartScreen extends ConsumerWidget {
  const StartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CalendarWeekScreen(trailing: const _ProfileButton());
  }
}

/// The signed-in user's own face — their picture where they have one, their
/// initials on their tone otherwise. Neutral only until the roster has loaded:
/// no name, no initials, no tone to borrow yet.
///
/// Its own widget rather than built in [StartScreen], so watching the household
/// rebuilds one 40-point circle instead of the whole week view.
class _ProfileButton extends ConsumerWidget {
  const _ProfileButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(familyProvider).me(ref.watch(currentUserIdProvider));
    final tone = me == null ? null : AppTones.list[me.tone % AppTones.list.length];
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsScreen())),
      child: Avatar(
        size: 40,
        bg: tone?.bg ?? AppColors.surfaceAlt,
        fg: tone?.fg ?? AppColors.muted,
        initials: me?.initials,
        icon: me == null ? AppIcons.user : null,
        fontSize: 14,
        imageUrl: me?.avatarUrl,
      ),
    );
  }
}
