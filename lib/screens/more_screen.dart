import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../services/spend_intent.dart';
import '../state/more_state.dart';
import '../theme/app_icons.dart';
import '../widgets/anchored_menu.dart';
import 'box_screen.dart';
import 'spend_screen.dart';

/// **Mehr** — the fifth tab, and two screens rather than a shelf.
///
/// Boxen used to be a tab of its own. It gave the slot up to make room for
/// Ausgaben, and the two now share this one: both are things a household opens
/// deliberately rather than daily, which is exactly what a fifth tab is for.
///
/// **Which of the two is showing was decided before this widget was built.**
/// Tapping **Mehr** on the nav bar puts up [showMoreMenu] — the system's own
/// menu, beside the bar item it grew out of — and the shell only switches tab
/// once a row has been picked. So there is no menu page on the way in and no
/// back control on the way out; the way to the other one is the same tap that
/// got you here.
///
/// The alternative that was considered and rejected was putting Boxen on Home
/// and giving Ausgaben the free tab. Home is the week view, and its own doc
/// comment says *Home is a day, not a summary*; a box in the attic is not part
/// of Tuesday, and the sections Home already carries are all things happening
/// on the selected day.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Where Ausgaben does not ship this tab is Boxen and nothing else, and the
    // spend screen is not merely unreachable but never built: it is always
    // mounted in this stack, so building it would have `spendProvider` querying
    // a table the household can never see the results of.
    if (!spendAvailable) return BoxScreen();

    // Both stay mounted, so switching to the other one and back lands where the
    // user left off rather than at the top of a rebuilt screen.
    return IndexedStack(
      index: ref.watch(moreProvider).index,
      children: [BoxScreen(), SpendScreen()],
    );
  }
}

/// The menu the **Mehr** nav item opens, anchored on the item itself.
///
/// Answers the section the user picked, or null if they backed out — which the
/// shell reads as "don't change tab", so a dismissed menu leaves the screen
/// they were already reading exactly where it was.
///
/// This is a menu and not a second bottom bar on purpose. The iOS bar is a real
/// `UITabBar` platform view, so there is no reshaping it into a two-icon
/// variant; anything drawn over it would be a Flutter approximation of Liquid
/// Glass sitting next to the real thing. A `UIMenu` *is* the real thing — the
/// same material, presented by UIKit above every platform view — and it is
/// already the rule everywhere else in the app that every menu is the system's
/// own where the system has one. Off iOS [showAnchoredMenuAt] draws the app's
/// dropdown instead, exactly as every "..." in the app already does.
Future<MoreSection?> showMoreMenu({
  required BuildContext context,
  required Rect anchor,
  MoreSection? current,
}) async {
  MoreSection? picked;

  await showAnchoredMenuAt(
    context: context,
    anchor: anchor,
    title: L.s.navMore,
    items: [
      AnchoredMenuItem(
        label: L.s.navBox,
        icon: AppIcons.package,
        symbol: 'shippingbox',
        selected: current == MoreSection.box,
        onSelected: () => picked = MoreSection.box,
      ),
      // Off iOS there is no second row, and the nav bar knows it: the last slot
      // is Boxen there, so nothing calls this at all. The row is dropped here
      // as well so the menu is honest read on its own.
      if (spendAvailable)
        AnchoredMenuItem(
          label: L.s.spendTitle,
          icon: AppIcons.wallet,
          symbol: 'creditcard',
          selected: current == MoreSection.spend,
          onSelected: () => picked = MoreSection.spend,
        ),
    ],
  );

  return picked;
}
