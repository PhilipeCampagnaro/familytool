import 'package:flutter/widgets.dart';

/// Whether a route now sits **above** the one [context] belongs to *and covers
/// it* — in which case nothing built here may be an iOS platform view.
///
/// Every piece of native chrome in this app is a `UiKitView`: the tab bar
/// ([NativeTabBar]), the search field ([NativeSearchField]), the switch
/// ([NativeSwitch]) and the real `UIGlassEffect` behind [GlassSurface]. A
/// `UiKitView` is a UIKit view *composited into* the Flutter scene rather than
/// painted by it, and Flutter is supposed to lift anything drawn above one into
/// an overlay layer stacked over it. Where that fails, the native view simply
/// stays on top of everything — including a whole route.
///
/// That is what emptied every sheet in the app. A `showAppSheet` is a
/// **non-opaque** modal route, so the screen underneath keeps painting, native
/// chrome and all: the Listen/Boxen search field and the tab bar punched
/// straight through the sheet, and with enough of them on screen at once the
/// sheet's entire body went with them — the two glass buttons in its header
/// were all that was left, being platform views themselves. The tell is a sheet
/// whose chrome is right and whose content isn't there, which is the same tell
/// [showAppSheet] and [NativeSwitch] already document at a smaller scale.
///
/// So a native view stands down for as long as it is covered, and every caller
/// already has the fallback to stand down *to*: the branch each of these
/// widgets takes off iOS. [ModalRoute.isCurrentOf] is false exactly while
/// another route sits on top of this one, and reading it subscribes this
/// context to that one aspect — so the swap happens as the sheet opens and
/// reverses as it closes, with no navigator observer.
///
/// **A dropdown is not a cover, and `isCurrentOf` alone called it one.** A menu
/// is a route too, so opening any of them stood the entire screen behind it
/// down: the bottom nav gave up its box and disappeared for as long as the menu
/// was open, and every glass control on the screen swapped to the approximation
/// and visibly changed colour — worst on dark, where the approximation sits
/// furthest from the real material. Nothing was being covered. A 236pt panel
/// hanging beside its anchor leaves the rest of the screen exactly as it was,
/// and it deliberately keeps clear of the nav bar — `_AnchoredMenuRoute`'s
/// geometry flips the panel above its anchor rather than let it reach under the
/// bar. So a dropdown goes up through [pushDropdownRoute], which exempts the
/// one route it opens over. That is the same distinction `_AppSheetRoute`
/// already draws with `canTransitionTo` for the sheet underneath: only a card
/// laid over a thing counts as covering it.
///
/// Null (no enclosing route at all) means nothing can be covering it.
bool occludedByRoute(BuildContext context) {
  // Subscribing to the "am I topmost" aspect is what rebuilds a native view
  // when anything is pushed or popped above it — dropdowns included, so the
  // exemption below is re-read at exactly the moments it can change.
  if (ModalRoute.isCurrentOf(context) != false) return false;
  return !_dropdownHosts.contains(ModalRoute.of(context));
}

/// The routes that have nothing over them **but a dropdown**.
///
/// A list rather than one route because a dropdown opened from inside a sheet
/// would otherwise un-exempt the screen below the sheet, which *is* covered.
/// (On iOS that case is a `showNativeMenu` for the separate reason
/// recorded on it, so in practice this holds one route or none.)
final List<ModalRoute<dynamic>?> _dropdownHosts = <ModalRoute<dynamic>?>[];

/// Pushes an anchored dropdown panel and exempts the route it opens over from
/// [occludedByRoute] for as long as the panel is up.
///
/// Every anchored popup in the app goes up through this rather than
/// `Navigator.push`: [showAnchoredMenu], Kalender's filter menu and its two
/// calendar pickers.
Future<T?> pushDropdownRoute<T>(BuildContext context, DropdownRoute<T> route) {
  route.host = ModalRoute.of(context);
  return Navigator.of(context).push(route);
}

/// Marks a [PopupRoute] as an anchored dropdown — a panel beside a control
/// rather than a card over the screen.
///
/// The exemption is entered and left with the route's own lifecycle. `dispose`
/// is the moment the navigator is finished with the entry, which is at or after
/// the moment the host's `isCurrent` goes back to true — so the exemption never
/// ends while the panel is still fading out, and outliving it by a frame is
/// invisible because [occludedByRoute] has already answered false by then.
mixin DropdownRoute<T> on PopupRoute<T> {
  /// The route this panel was opened over. Set by [pushDropdownRoute] before
  /// the push, so it is in place by the time [install] runs.
  ModalRoute<dynamic>? host;

  @override
  void install() {
    super.install();
    _dropdownHosts.add(host);
  }

  @override
  void dispose() {
    _dropdownHosts.remove(host);
    super.dispose();
  }
}
