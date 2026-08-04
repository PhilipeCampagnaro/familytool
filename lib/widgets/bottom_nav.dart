import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../l10n/l10n.dart';
import '../theme/tokens.dart';
import 'glass.dart';

class NavTab {
  final String label;
  final IconData icon;

  /// SF Symbol names for the native iOS tab bar, which draws real
  /// `UITabBarItem`s and so needs symbol *names*, not Flutter [IconData].
  /// UIKit swaps to [sfSymbolSelected] on the active tab the way system apps
  /// do; where a symbol has no filled variant both are the same.
  final String sfSymbol;
  final String sfSymbolSelected;

  const NavTab(this.label, this.icon, {required this.sfSymbol, String? sfSymbolSelected})
    : sfSymbolSelected = sfSymbolSelected ?? sfSymbol;
}

/// Rebuilt on every read so the labels follow the interface language. The
/// native iOS bar re-sends these to UIKit when it rebuilds, so the system tab
/// bar changes language with the rest of the app.
List<NavTab> get navTabs => [
  NavTab(L.s.navHome, LucideIcons.home, sfSymbol: 'house', sfSymbolSelected: 'house.fill'),
  NavTab(L.s.navCalendar, LucideIcons.calendar, sfSymbol: 'calendar'),
  NavTab(L.s.navLists, LucideIcons.clipboardCheck, sfSymbol: 'checklist'),
  NavTab(L.s.navBoard, LucideIcons.layoutPanelLeft, sfSymbol: 'square.grid.2x2', sfSymbolSelected: 'square.grid.2x2.fill'),
  NavTab(L.s.navBox, LucideIcons.box, sfSymbol: 'shippingbox', sfSymbolSelected: 'shippingbox.fill'),
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
              child: Icon(
                tab.icon,
                size: 20,
                color: active ? Colors.white : AppColors.muted,
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
