import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import '../l10n/l10n.dart';
import '../services/spend_intent.dart';
import '../theme/tokens.dart';
import 'glass.dart';
import 'native_glass_buttons.dart';
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
///
/// **Five, and five is the ceiling.** Boxen used to hold the last slot and gave
/// it up to **Mehr**, which now carries Boxen and Ausgaben together — see
/// `MoreScreen` for why those two and not a sixth tab. A sixth item fits the
/// data structure on both bars and fits neither design: UIKit squeezes six
/// German labels into a floating capsule until they truncate, and the Figma
/// pill was drawn for five.
List<NavTab> get navTabs => [
  NavTab(
    L.s.navHome,
    AppIcons.house,
    cupertinoIcon: CupertinoIcons.house,
    sfSymbol: 'house',
    sfSymbolSelected: 'house.fill',
  ),
  NavTab(L.s.navCalendar, AppIcons.calendar, cupertinoIcon: CupertinoIcons.calendar, sfSymbol: 'calendar'),
  NavTab(
    L.s.navLists,
    AppIcons.listChecks,
    cupertinoIcon: CupertinoIcons.checkmark_square,
    sfSymbol: 'checklist',
  ),
  // `squares-four`, not Phosphor's `layout` — the panel-with-a-sidebar glyph
  // that was here said "dashboard" where the SF Symbol beside it on the iPhone
  // says four squares, and the two bars are meant to be one design drawn twice.
  NavTab(
    L.s.navBoard,
    AppIcons.squaresFour,
    cupertinoIcon: CupertinoIcons.square_grid_2x2,
    sfSymbol: 'square.grid.2x2',
    sfSymbolSelected: 'square.grid.2x2.fill',
  ),
  // A stack of cards seen end-on, not an ellipsis: the three dots said "more
  // options" — a menu of settings — where this tab is two *places*. The SF
  // Symbol is the picture; Phosphor's nearest is its layered `stack-simple`,
  // which says the same thing in the set's own hand, because the family has no
  // card-stack glyph (checked against all 1504 in the vendored font).
  //
  // **Where Ausgaben does not ship, the slot is simply Boxen** — see
  // `spendAvailable`. "Mehr" naming one place is a promise the menu cannot
  // keep: it would put up a menu of a single row, or open Boxen and leave the
  // reader wondering what the rest of "more" was.
  if (spendAvailable)
    NavTab(
      L.s.navMore,
      AppIcons.stackSimple,
      cupertinoIcon: CupertinoIcons.rectangle_stack,
      sfSymbol: 'rectangle.stack',
      sfSymbolSelected: 'rectangle.stack.fill',
    )
  else
    NavTab(
      L.s.navBox,
      AppIcons.package,
      cupertinoIcon: CupertinoIcons.cube_box,
      sfSymbol: 'shippingbox',
      sfSymbolSelected: 'shippingbox.fill',
    ),
];

/// iPhone/iPad gets the real system tab bar — an actual `UITabBar` embedded as
/// a platform view (`NativeTabBar`), which on iOS 26 is Apple's floating
/// Liquid Glass bar. Every other platform gets [AppBottomNav], which is that
/// same bar drawn in Flutter rather than Material's own.
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
double navContentInset(BuildContext context, {double pill = 130, double gap = 12}) =>
    useNativeTabBar ? nativeTabBarBottomInset(context) + kNativeTabBarHeight + gap : pill;

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
  final height = useNativeTabBar ? (barHeight ?? kNativeTabBarHeight) : kFlutterNavBarHeight;
  return bottom + (height - size) / 2;
}

/// Diameter of every circle standing on the nav row: the compacted nav button,
/// the `MoreShelf` buttons, and Kalender's "Heute" at the other end of it.
///
/// Sized against the bar rather than under it. The compacted button is the bar
/// with everything but the selected tab folded away, and the shelf's buttons
/// sit a finger's width above the bar with its five SF Symbols still on screen,
/// so a circle noticeably smaller than the thing it came out of reads as a
/// different, lesser control rather than as the same one drawn in. It was 54,
/// which was a low guess at an iOS 26 glass capsule.
const kCompactNavSize = 62.0;

/// Size of a glyph on the nav row, which is **UIKit's own tab-bar symbol size**
/// rather than a number of ours.
///
/// Everything that stands on this row is read against the bar's five SF Symbols
/// — the collapsed nav button is literally the selected one of them, and the
/// `MoreShelf` buttons sit a finger's width above them with the bar still on
/// screen. Anything else there reads as a smaller, quieter icon set beside the
/// system's. It is why those circles are sized to the bar rather than the glyph
/// shrunk to fit inside a smaller one.
const kNavRowIconSize = 28.0;

/// The bottom nav collapsed to a single glass circle, parked at the left edge.
/// Kalender scrolls into this so the grid has the whole width of the screen;
/// tapping it brings the bar back (see `AppShell`).
///
/// [tab] is the *active* one, straight off [navTabs], so the circle is the
/// bar's selected item with everything else folded away — which is what makes
/// the collapse read as one control shrinking rather than as a second one
/// taking over.
///
/// **On iOS it is a real `UIButton` on the glass configuration**
/// ([NativeGlassButtons]), the same control as the header buttons and the
/// `Mehr` shelf's circles, carrying the bar's own SF Symbol — it stands where a
/// real `UITabBar` just was, so it wears that bar's glyph and material rather
/// than a Flutter copy of either. The button brings its own press response and
/// shadow, so the Flutter scale and [AppShadows.navBar] are the fallback's only.
class CompactNavButton extends StatefulWidget {
  final NavTab tab;
  final VoidCallback onTap;

  const CompactNavButton({super.key, required this.tab, required this.onTap});

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
    if (nativeGlassActive(context)) {
      return Semantics(
        button: true,
        label: L.s.navExpand,
        excludeSemantics: true,
        child: SizedBox(
          width: kCompactNavSize,
          height: kCompactNavSize,
          child: NativeGlassButtons(
            buttons: [
              NativeGlassButton(
                symbol: widget.tab.sfSymbolSelected,
                label: L.s.navExpand,
                onTap: widget.onTap,
              ),
            ],
            tint: AppColors.accent,
            iconSize: kNavRowIconSize,
          ),
        ),
      );
    }
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
            // tint, so iOS's real glass adapts and the Flutter drawing takes
            // the default light material, where the icon stays legible.
            blurSigma: 24,
            boxShadow: AppShadows.navBar,
            child: SizedBox(
              width: kCompactNavSize,
              height: kCompactNavSize,
              child: AppIcon(
                widget.tab.compactIcon,
                size: kNavRowIconSize,
                color: AppColors.accent,
                flat: true,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Height of the Flutter-drawn bar, and so the radius its ends are rounded to.
///
/// Sized against [kCompactNavSize] and the glyph it carries rather than against
/// the handoff's 70: the compacted nav button *is* this bar with four items
/// folded away, the two hang off one centre line, and a 28pt glyph with a name
/// under it needs the room. See [navRowBottom], which reads this.
const kFlutterNavBarHeight = 68.0;

/// Padding between the glass rim and an item, all four sides. It is also what
/// the selection capsule is inset by, so it is the gap that keeps the capsule
/// off the rim — two rounded shapes sharing an edge read as one that failed to
/// draw.
const _barPad = 6.0;

/// The widest an item is allowed to get. Five of these plus [_barPad] twice
/// have to fit between the screen margins, so on a narrow display they come in
/// under this — see the `LayoutBuilder` in [AppBottomNav].
const _maxNavItemWidth = 70.0;

/// How long the selection capsule takes to slide to the tapped item. Long
/// enough to be a slide rather than a jump, short enough that the screen behind
/// has already changed by the time it lands.
const _selectionDuration = Duration(milliseconds: 320);

/// The bottom navigation everywhere the system has none of its own — Android,
/// web, desktop. iPhone and iPad get UIKit's instead; see [useNativeTabBar].
///
/// **It is an answer to iOS 26's floating tab bar, not to Material's.** Aporah
/// is one app with one shape language, and `NavigationBar`'s edge-to-edge
/// surface with its own selection indicator is a second one — the screens
/// above it are drawn to float clear of a capsule, not to end at a bar. So this
/// is the same control UIKit draws on the phone next to it: a glass capsule
/// hugging its five items, clear of the bottom of the display, with a rounded
/// highlight that **slides** to whatever was tapped.
///
/// **The material and the glyphs are the `MoreShelf` buttons', deliberately.**
/// [GlassSurface] is the same surface those two stand on (and on iOS it is the
/// real `UIGlassEffect`); the glyph is the same flat Phosphor Bold at
/// [kNavRowIconSize] through the same [navRowIcon] helper; and the colour is
/// the same `AppColors.ink` at rest with `AppColors.accent` on the one in
/// force. The shelf comes *out of* this bar, so anything else makes it read as
/// a control from somewhere else that happened to appear there. What it is not
/// is the handoff's pill, which showed a label on the selected item only and
/// filled its glyph's circle with the accent: four unlabelled dots and one
/// wide chip is a different control in each state, and the accent circle was
/// the loudest thing on any screen it floated over.
///
/// **Every item carries its name, and the names are why the width is measured.**
/// A tab bar that labels one item is asking the reader to recognise four
/// glyphs; iOS labels all five. That costs width, so the items take
/// [_maxNavItemWidth] where there is room for it and share out what there is
/// where there isn't, and the bar hugs the result rather than stretching — a
/// capsule pinned to both screen margins is a bar, and a bar is the Material
/// shape this exists instead of.
class AppBottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;

  const AppBottomNav({super.key, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tabs = navTabs;
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = math.min(_maxNavItemWidth, (constraints.maxWidth - _barPad * 2) / tabs.length);
        return GlassSurface(
          borderRadius: BorderRadius.circular(kFlutterNavBarHeight / 2),
          // No forced `tint`: it goes straight to `UIGlassEffect.tintColor` on
          // iOS, and a near-opaque one floods the material so the real glass
          // renders as a flat grey pill. The Flutter-drawn approximation takes
          // the default light material, which the dark labels stay legible on.
          blurSigma: 24,
          boxShadow: AppShadows.navBar,
          child: SizedBox(
            height: kFlutterNavBarHeight,
            width: itemWidth * tabs.length + _barPad * 2,
            child: Padding(
              padding: const EdgeInsets.all(_barPad),
              child: Stack(
                children: [
                  // Painted first, so it is the ground the tapped item stands
                  // on rather than a chip over it. It is positioned, so the
                  // `Row` below is what sizes the stack.
                  AnimatedPositioned(
                    duration: _selectionDuration,
                    curve: Curves.easeOutCubic,
                    left: index * itemWidth,
                    top: 0,
                    bottom: 0,
                    width: itemWidth,
                    child: _SelectionCapsule(),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < tabs.length; i++)
                        _NavItem(tab: tabs[i], width: itemWidth, active: i == index, onTap: () => onTap(i)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The highlight under the selected item.
///
/// `AppColors.surface` rather than the accent, which is what the iOS bar does
/// and what [MoreShelf] settled on for the same reason: the colour's one job
/// here is on the glyph and the word, and a filled accent capsule floating over
/// a photograph in a box or a list of Ausgaben is louder than the screen it is
/// sitting on. [AppShadows.glassButton] is the lift a control of about this
/// size takes elsewhere in the app.
///
/// **Not `const`**: it reads the palette in its own `build`, so a canonicalised
/// instance would keep the colours it was born with across a theme change —
/// see the note on [AppColors] and `tool/check_const_palette.dart`.
class _SelectionCapsule extends StatelessWidget {
  // ignore: prefer_const_constructors_in_immutables
  _SelectionCapsule();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular((kFlutterNavBarHeight - _barPad * 2) / 2),
        boxShadow: AppShadows.glassButton,
      ),
    );
  }
}

/// One tab: the glyph with its name under it, over whatever the capsule behind
/// it is doing.
class _NavItem extends StatefulWidget {
  final NavTab tab;
  final double width;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({required this.tab, required this.width, required this.active, required this.onTap});

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    // The shelf's rest/selected pair, and for the shelf's reasons:
    // `AppColors.muted` is one grey for both palettes and goes soft and
    // half-disabled on glass, where `ink` is near-black on the light palette
    // and near-white on the dark one.
    final color = widget.active ? AppColors.accent : AppColors.ink;
    return Semantics(
      button: true,
      selected: widget.active,
      label: widget.tab.label,
      // The glyph and the word are one thing to a reader and are already merged
      // into this label, so neither is a second node to land on.
      excludeSemantics: true,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        // Opaque, or the gaps around the glyph and above the word are holes in
        // the middle of the target.
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: widget.width,
          child: AnimatedScale(
            scale: _pressed ? 0.9 : 1.0,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppIcon(widget.tab.compactIcon, size: kNavRowIconSize, color: color, flat: true),
                const SizedBox(height: 2),
                // Clamped, and this is the one place in the app that clamps:
                // the item is a fixed box inside a bar whose height is what the
                // compacted nav button lines up against, so a name at 2× does
                // not push the bar taller — it pushes the glyph off the top of
                // it. The glyph carries the meaning at that point anyway.
                MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.2,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text(
                      widget.tab.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: AppText.navLabel.copyWith(color: color),
                    ),
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
