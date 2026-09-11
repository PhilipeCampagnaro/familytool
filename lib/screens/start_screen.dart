import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/auth_state.dart';
import '../state/family_state.dart';
import '../theme/tokens.dart';
import '../widgets/avatar.dart';
import 'calendar_screen.dart';
import 'home/day_island.dart';
import 'home/first_steps.dart';
import 'home/home_sections.dart';
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
/// **This screen is the assembly, not the drawing.** [CalendarWeekScreen] owns
/// the header, the day strip and the day card; everything else fills one of its
/// four slots, and each piece lives under `lib/screens/home/` so that the
/// calendar's `part` library never learns what a tracker or a shopping list is.
///
/// Read top to bottom, Home is:
///
/// - the profile avatar ([_ProfileButton]), which is this app's only entry point
///   into Settings — the old web app's "tap your avatar on the dashboard"
///   pattern, see CLAUDE.md's "Ported feature knowledge" -> Settings;
/// - the status island ([DayIsland]), where Kalender names the month;
/// - the day card, which is the calendar's;
/// - and [HomeSections] under its bottom edge.
///
/// The edge between the last two is a boundary in meaning, not only in paint:
/// above it is the day the strip is on, below it is the household right now.
///
/// [FirstStepsCard] sits between the first two, inside the header: it folds out
/// of the island and pushes the day down, and the header grows by exactly the
/// height this screen works out for it.
class StartScreen extends ConsumerWidget {
  const StartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // **The panel's height is worked out here, not measured down there.** The
    // header is a collapsing sliver laid out against a single extent, so it has
    // to be told how much room the checklist needs before the checklist is
    // built; `firstStepsPanelHeight` is arithmetic over a fixed row height for
    // exactly that reason.
    final open = ref.watch(firstStepsOpenProvider);
    final steps = ref.watch(firstStepsProvider);

    // None of the three below may be `const`: each reads a design token while
    // it builds, and a const instance is canonical, so the parent handing back
    // an identical widget is how one keeps painting the palette it was born
    // with. See `tool/check_const_palette.dart`.
    return CalendarWeekScreen(
      trailing: _ProfileButton(),
      label: DayIsland(),
      underLabel: FirstStepsCard(),
      underLabelHeight: open ? firstStepsPanelHeight(steps.length) : 0,
      belowDay: HomeSections(),
    );
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
