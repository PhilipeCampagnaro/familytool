import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import '../l10n/l10n.dart';
import '../theme/tokens.dart';
import 'glass.dart';
import '../theme/app_icons.dart';

class NavTab {
  final String label;
  final IconData icon;

  /// The same glyph from Apple's own set, for the Flutter-drawn controls that
  /// sit beside the native bar — see [navRowIcon]. Not a second icon set for
  /// the app: it is used on the nav row and nowhere else.
  final IconData cupertinoIcon;

  /// SF Symbol names for the native iOS tab bar, which draws real
  /// `UITabBarItem`s and so needs symbol *names*, not Flutter [IconData].
  /// UIKit swaps to [sfSymbolSelected] on the active tab the way system apps
  /// do; where a symbol has no filled variant both are the same.
  final String sfSymbol;
  final String sfSymbolSelected;

  const NavTab(
    this.label,
    this.icon, {
    required this.cupertinoIcon,
    required this.sfSymbol,
    String? sfSymbolSelected,
  }) : sfSymbolSelected = sfSymbolSelected ?? sfSymbol;

  /// What the compacted nav button wears for this tab.
  IconData get compactIcon => navRowIcon(lucide: icon, cupertino: cupertinoIcon);
}

/// Picks the icon for a Flutter-drawn control on the nav row.
///
/// The iOS bar draws real SF Symbols, so a Lucide calendar in the button that
/// replaces it reads as a *second*, subtly different calendar — different
/// corner radius, little hanging ears the SF one hasn't got. [CupertinoIcons]
/// is Apple's own set, so on iOS the whole row is drawn from it and the
/// handoff's Lucide set is used everywhere else, where the bar is the Lucide
/// pill anyway.
IconData navRowIcon({required IconData lucide, required IconData cupertino}) =>
    useNativeTabBar ? cupertino : lucide;

/// Rebuilt on every read so the labels follow the interface language. The
/// native iOS bar re-sends these to UIKit when it rebuilds, so the system tab
/// bar changes language with the rest of the app.
List<NavTab> get navTabs => [
  NavTab(L.s.navHome, AppIcons.house, cupertinoIcon: CupertinoIcons.house, sfSymbol: 'house', sfSymbolSelected: 'house.fill'),
  NavTab(L.s.navCalendar, AppIcons.calendar, cupertinoIcon: CupertinoIcons.calendar, sfSymbol: 'calendar'),
  NavTab(L.s.navLists, AppIcons.listChecks, cupertinoIcon: CupertinoIcons.checkmark_square, sfSymbol: 'checklist'),
  NavTab(L.s.navBoard, AppIcons.layout, cupertinoIcon: CupertinoIcons.square_grid_2x2, sfSymbol: 'square.grid.2x2', sfSymbolSelected: 'square.grid.2x2.fill'),
  NavTab(L.s.navBox, AppIcons.package, cupertinoIcon: CupertinoIcons.cube_box, sfSymbol: 'shippingbox', sfSymbolSelected: 'shippingbox.fill'),
];

/// iPhone/iPad gets the real system tab bar — an actual `UITabBar` embedded as
/// a platform view (`NativeTabBar`), which on iOS 26 is Apple's floating
/// Liquid Glass bar. Every other platform keeps the custom pill
/// ([AppBottomNav]) from the Figma handoff.
bool get useNativeTabBar => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// Fallback height for the native bar until it reports its own (~49–56pt).
/// Only used for content clearance, never to size the bar itself — UIKit does
/// that.
const kNativeTabBarHeight = 56.0;

/// Gap between the bottom of the native bar and the bottom of the screen. iOS
/// 26's floating bar clears the home indicator without sitting on top of the
/// safe-area line, so this is the safe area pulled in a little, with a floor
/// for devices that have none.
double nativeTabBarBottomInset(BuildContext context) =>
    math.max(MediaQuery.paddingOf(context).bottom - 16, 10);

/// Bottom padding a scrolling screen needs so its last row clears the nav bar.
/// Both bars float over the content (the glass needs something behind it to
/// refract), so neither takes part in layout and the clearance has to be
/// computed: the native bar from its own geometry, the pill from the constant
/// [pill] — which a few screens nudge up to sit a card further clear of it.
///
/// [gap] is the breathing room left above the native bar. Scrolling content can
/// sit close to it — it slides under the glass and reads as intended — but
/// anything *parked* just above the bar (the calendar's floating "Heute"
/// button) needs a bigger gap, or the two glass surfaces touch and the button
/// looks like it's hiding behind the bar.
double navContentInset(BuildContext context, {double pill = 130, double gap = 12}) => useNativeTabBar
    ? nativeTabBarBottomInset(context) + kNativeTabBarHeight + gap
    : pill;

/// How long the bar takes to collapse into [CompactNavButton] and back. Shared
/// with anything that has to travel with it — Kalender's "Heute" button drops
/// onto the nav row as the bar leaves it.
const kNavSwapDuration = Duration(milliseconds: 380);

/// Bottom offset that puts a [size]-tall control on the nav bar's own centre
/// line: the compacted nav button on the left, "Heute" on the right.
///
/// [barHeight] is what UIKit reported through [NativeTabBar.onHeight], because
/// nothing in Dart can predict it — an iOS 26 capsule is a good deal taller
/// than [kNativeTabBarHeight], and falling back to the constant drops a
/// control visibly below the line the bar is sitting on.
double navRowBottom(BuildContext context, {double? barHeight, double size = kCompactNavSize}) {
  final bottom = useNativeTabBar ? nativeTabBarBottomInset(context) : 22.0;
  final height = useNativeTabBar ? (barHeight ?? kNativeTabBarHeight) : 70.0;
  return bottom + (height - size) / 2;
}

/// Diameter of the compacted nav button — a little under the bar's own height
/// so the swap reads as the bar drawing itself in rather than a control of a
/// different family appearing.
const kCompactNavSize = 54.0;

/// The bottom nav collapsed to a single glass circle, parked at the left edge.
/// Kalender scrolls into this so the agenda has the whole width of the screen;
/// tapping it brings the bar back (see `AppShell`).
///
/// [icon] is the *active* tab's, straight off [navTabs], so the circle is the
/// bar's selected item with everything else folded away — which is what makes
/// the collapse read as one control shrinking rather than as a second one
/// taking over.
class CompactNavButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;

  const CompactNavButton({super.key, required this.icon, required this.onTap});

  @override
  State<CompactNavButton> createState() => _CompactNavButtonState();
}

class _CompactNavButtonState extends State<CompactNavButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: L.s.navExpand,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: AnimatedScale(
          scale: _pressed ? 0.92 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: GlassSurface(
            borderRadius: BorderRadius.circular(kCompactNavSize / 2),
            // Same bargain as the pill and the floating buttons: no forced
            // tint, so iOS's real glass adapts, and a light fallback so the
            // icon stays legible where it is drawn by Flutter.
            fallbackTint: AppColors.navPillTint,
            blurSigma: 24,
            boxShadow: AppShadows.navBar,
            child: SizedBox(
              width: kCompactNavSize,
              height: kCompactNavSize,
              child: AppIcon(widget.icon, size: 22, color: AppColors.accent, flat: true),
            ),
          ),
        ),
      ),
    );
  }
}

/// The floating pill bottom navigation shared by all five tabs.
class AppBottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;

  const AppBottomNav({super.key, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      borderRadius: BorderRadius.circular(35),
      // No forced `tint`: it goes straight to `UIGlassEffect.tintColor` on
      // iOS, and a near-opaque one floods the material so the real glass
      // renders as a flat grey pill. The Flutter-drawn fallback still needs a
      // light colour for the dark labels to stay legible.
      fallbackTint: AppColors.navPillTint,
      blurSigma: 24,
      boxShadow: AppShadows.navBar,
      child: Container(
        height: 70,
        padding: const EdgeInsets.all(7),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < navTabs.length; i++) _NavItem(
              tab: navTabs[i],
              active: i == index,
              onTap: () => onTap(i),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final NavTab tab;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({required this.tab, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dotSize = active ? 42.0 : 40.0;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 56,
        padding: EdgeInsets.all(active ? 7 : 0),
        decoration: BoxDecoration(
          color: active ? AppColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(28),
          boxShadow: active ? AppShadows.glassButton : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: dotSize,
              height: dotSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? AppColors.accent : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: AppIcon(
                tab.icon,
                size: 20,
                color: active ? Colors.white : AppColors.muted,
                flat: true,
              ),
            ),
            if (active) ...[
              const SizedBox(width: 9),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  tab.label,
                  style: AppText.rowTitle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
