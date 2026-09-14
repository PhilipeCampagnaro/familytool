import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which of the More tab's two screens is showing.
///
/// The fifth tab holds Boxen and Ausgaben: both are things a household reaches
/// for now and then, and neither earns a slot beside Kalender and Listen in a
/// five-wide bar. They went here rather than onto Home because Home is
/// documented as *a day, not a summary* — a box of winter clothes in the attic
/// has nothing to do with Tuesday.
///
/// **There is no third value for a landing page, and that is the point.** The
/// tab was briefly a menu page listing the two, which cost a screen on the way
/// in and a back control on the way out of both. The choice is made on the nav
/// row itself, in the two buttons **Mehr** stands on the bar (`MoreShelf`), so
/// by the time this tab is on screen the question has already been answered.
enum MoreSection { box, spend }

/// A mode switch, not a route — the same shape as Listen opening a list and
/// Board opening a tracker.
///
/// Both screens stay mounted in an `IndexedStack` inside the tab, so switching
/// from one to the other and back keeps a scroll position and a half-typed
/// search.
class MoreNotifier extends StateNotifier<MoreSection> {
  MoreNotifier() : super(MoreSection.box);

  void open(MoreSection section) => state = section;
}

final moreProvider = StateNotifierProvider<MoreNotifier, MoreSection>((ref) => MoreNotifier());
