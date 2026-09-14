import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/spend_intent.dart';
import '../state/more_state.dart';
import 'box_screen.dart';
import 'spend_screen.dart';

/// **Mehr** — the fifth tab, and two screens rather than a shelf.
///
/// Boxen used to be a tab of its own. It gave the slot up to make room for
/// Ausgaben, and the two now share this one: both are things a household opens
/// deliberately rather than daily, which is exactly what a fifth tab is for.
///
/// **Which of the two is showing was decided before this widget was built.**
/// Tapping **Mehr** on the nav bar stands `MoreShelf` on the bar item — two
/// glass buttons, one per place — and the shell only switches tab once one of
/// them has been pressed. So there is no menu page on the way in and no back
/// control on the way out; the way to the other one is the same tap that got
/// you here.
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
