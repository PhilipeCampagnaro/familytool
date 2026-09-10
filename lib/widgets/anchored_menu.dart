import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/tokens.dart';
import 'bottom_nav.dart';
import 'glass.dart';
import 'native_occlusion.dart';
import '../services/native_menu.dart';
import '../l10n/l10n.dart';
import '../theme/app_icons.dart';

/// One row of a [showAnchoredMenu] dropdown.
class AnchoredMenuItem {
  final String label;

  /// The row's trailing glyph, as a Lucide icon. Exactly one of this and
  /// [svgAsset] is given.
  final IconData? icon;

  /// A brand mark from `assets/` instead of an icon, e.g. Amazon's. Painted in
  /// the row's own colour like any other glyph — a menu row is a *label*, so a
  /// full-colour logo would be the one thing shouting on an otherwise
  /// monochrome list.
  final String? svgAsset;

  /// An **SF Symbol** name for the row's glyph *when the system draws the
  /// menu* — UIKit's menu takes UIKit's icons, and [icon]/[svgAsset] are
  /// Flutter's. A row without one simply has no glyph there, which is why the
  /// brand marks give none: `assets/merchants/` is a folder of SVGs and a
  /// `UIMenu` has nowhere to put one.
  final String? symbol;

  /// Puts a checkmark on the row — the system's way of showing which of a set
  /// of choices is the one in force. The panel Flutter draws has no such
  /// state, so a caller that wants the tick in both places also passes
  /// [icon] `AppIcons.check`.
  final bool selected;

  /// Draws the row in [AppColors.danger] — iOS's destructive menu action.
  final bool destructive;

  /// Runs *after* the menu has closed, so an action that opens a sheet isn't
  /// animating in behind a menu that's still on its way out.
  final VoidCallback onSelected;

  const AnchoredMenuItem({
    required this.label,
    this.icon,
    this.svgAsset,
    this.symbol,
    this.selected = false,
    this.destructive = false,
    required this.onSelected,
  }) : assert((icon == null) != (svgAsset == null), 'A menu row carries either an icon or an svgAsset');
}

/// Opens a menu anchored to whatever [anchorKey] is attached to — a row's
/// "..." button, a header control, a chip — and runs the picked item's
/// [AnchoredMenuItem.onSelected] once it has closed.
///
/// **The system draws it where the system has one to draw.** Every "..." in
/// the app comes through here, so this is the one place that decides: iOS gets
/// its own `UIMenu`, the glass bubble that grows out of the control, and
/// everything else gets the panel below. Same anchor rect either way, so the
/// two are one gesture drawn by two hands — see [showNativeMenu], which answers
/// null exactly when there is no system menu to be had.
///
/// What UIKit's costs: the rows carry SF Symbols rather than the app's Phosphor
/// glyphs ([AnchoredMenuItem.symbol]), and a brand mark can't come along at
/// all. What it buys is the material, the animation and the placement of the
/// menu the phone puts under every other app's controls.
///
/// The panel Flutter draws keeps the same route/animation shape as the Kalender
/// filter menu: a custom [PopupRoute] that lays the finished panel out beside
/// its anchor and scales it out of the nearest corner, rather than `showMenu` —
/// that grows the panel's height while staggering each item's fade, which over
/// dense content reads as a smeared, half-drawn slab.
///
/// [title] is the small grey caption UIKit puts above the rows; the panel has
/// no place for one and ignores it.
Future<void> showAnchoredMenu({
  required BuildContext context,
  required GlobalKey anchorKey,
  required List<AnchoredMenuItem> items,
  double width = AnchoredMenuSurface.defaultWidth,
  String? title,
}) async {
  final box = anchorKey.currentContext?.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return;
  final anchor = box.localToGlobal(Offset.zero) & box.size;

  final picked = await showNativeMenu(
    anchor: anchor,
    title: title,
    options: [
      for (final item in items)
        NativeMenuOption(
          item.label,
          symbol: item.symbol,
          destructive: item.destructive,
          selected: item.selected,
        ),
    ],
    cancelLabel: L.s.cancel,
    dark: AppColors.isDark,
  );
  // A menu the user backed out of is answered, not unanswered: falling through
  // to the panel here would reopen as a second menu the tap it just closed.
  if (picked == nativeMenuCancelled) return;
  if (picked != null) {
    items[picked].onSelected();
    return;
  }

  if (!context.mounted) return;
  final chosen = await pushDropdownRoute(context, _AnchoredMenuRoute(anchor: anchor, items: items, width: width));
  chosen?.onSelected();
}

class _AnchoredMenuRoute extends PopupRoute<AnchoredMenuItem> with DropdownRoute<AnchoredMenuItem> {
  /// Distance between the anchor and the panel's near edge.
  static const _gap = 6.0;

  /// How close the panel may come to the edges of the display.
  static const _screenMargin = 12.0;

  /// The anchor's rect in global coordinates.
  final Rect anchor;
  final List<AnchoredMenuItem> items;
  final double width;

  _AnchoredMenuRoute({required this.anchor, required this.items, required this.width});

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String get barrierLabel => L.s.close;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 200);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 140);

  /// Where the panel lands, plus the corner it therefore grows out of.
  ///
  /// The height is *computed*, not measured — every row is exactly
  /// [AnchoredMenuSurface.rowHeight] tall — so both the "does it still fit
  /// under the anchor" decision and the scale origin are known before layout,
  /// and [buildTransitions] can agree with [buildPage] without a second frame.
  ({double left, double top, Alignment origin}) _geometry(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final height = AnchoredMenuSurface.heightFor(items.length);

    // The bottom nav floats over every screen, and on iOS it's a native
    // platform view that composites *above* anything Flutter paints — a menu
    // that reaches under it is simply cut off, so it flips above its anchor
    // before it gets there.
    final bottomLimit = size.height - navContentInset(context, gap: 8) - _screenMargin;
    final below = anchor.bottom + _gap;
    final fitsBelow = below + height <= bottomLimit;
    final top = fitsBelow ? below : (anchor.top - _gap - height).clamp(media.padding.top + _screenMargin, below);

    // Hangs off whichever of the anchor's edges faces the middle of the
    // screen: a trailing "..." button in a row opens a menu to its left.
    final fromRight = anchor.center.dx > size.width / 2;
    final maxLeft = (size.width - width - _screenMargin).clamp(_screenMargin, double.infinity);
    final left = (fromRight ? anchor.right - width : anchor.left).clamp(_screenMargin, maxLeft);

    return (left: left, top: top, origin: Alignment(fromRight ? 1 : -1, fitsBelow ? -1 : 1));
  }

  /// The open/close animation is applied *here*, around the panel itself,
  /// rather than in [buildTransitions] — that wraps the whole page, so scaling
  /// there would grow a screen-sized layer out of a screen corner and drag the
  /// panel across the display with it instead of growing it out of its own
  /// corner, the way a UIKit menu opens.
  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    final g = _geometry(context);
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeIn);
    return Stack(
      children: [
        Positioned(
          left: g.left,
          top: g.top,
          child: FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
              alignment: g.origin,
              child: AnchoredMenuSurface(items: items, width: width),
            ),
          ),
        ),
      ],
    );
  }
}

/// The dropdown's panel. Positioned and dismissed by its route; this only
/// draws it.
///
/// Deliberately *not* a [GlassSurface]: UIKit's own menus aren't liquid glass,
/// they're a near-opaque vibrant material — a glass panel lets the content
/// underneath read straight through the rows. This matches the native menu
/// instead: an almost-solid fill, tight 14pt corners and hairline separators.
///
/// **And deliberately not a `BackdropFilter` any more.** It was one, sampling
/// what it opened over. Inside a sheet — where the app's native glass buttons
/// live — that read back the wrong backdrop on device and painted the card and
/// the buttons *over* the menu's own rows, so a two-item route menu showed one
/// item and a blue pill. The material was only 3% translucent to begin with, so
/// it is composited over the plain surface instead of sampled, and the panel is
/// now opaque wherever it opens.
class AnchoredMenuSurface extends StatelessWidget {
  static const defaultWidth = 236.0;

  /// Fixed so the route can compute the panel's height up front — see
  /// `_AnchoredMenuRoute._geometry`.
  static const rowHeight = 46.0;
  static const _separator = 0.5;

  /// Where a row's label starts: the row padding plus the glyph column.
  static const separatorInset = 16 + _glyphSize + _glyphGap;

  static double heightFor(int count) => count * rowHeight + (count - 1) * _separator;

  final List<AnchoredMenuItem> items;
  final double width;

  const AnchoredMenuSurface({super.key, required this.items, this.width = defaultWidth});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: AppShadows.menu,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: width,
            color: Color.alphaBlend(AppColors.menuSurface, AppColors.surface),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (i, item) in items.indexed) ...[
                  if (i > 0)
                    // Hairline inset past the glyph column, so it starts where
                    // the labels do — the way a UIKit menu insets its
                    // separators past a row's leading symbol.
                    Padding(
                      padding: EdgeInsets.only(left: separatorInset),
                      child: Divider(height: _separator, thickness: _separator, color: AppColors.menuSeparator),
                    ),
                  _AnchoredMenuRow(item: item),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Glyph box and the gap to the label. Together with the row's own 16pt
/// leading padding they give [AnchoredMenuSurface.separatorInset], so the
/// hairlines start where the labels do.
const double _glyphSize = 17;
const double _glyphGap = 12;

class _AnchoredMenuRow extends StatelessWidget {
  final AnchoredMenuItem item;

  const _AnchoredMenuRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final color = item.destructive ? AppColors.danger : AppColors.ink;
    return InkWell(
      onTap: () => Navigator.of(context).pop(item),
      child: SizedBox(
        height: AnchoredMenuSurface.rowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              // Leading glyph, in a fixed box so every label starts on the
              // same x no matter how wide the artwork is. A brand SVG is
              // tinted to the row's colour — `srcIn` throws the artwork's own
              // colours away and keeps only its coverage.
              SizedBox(
                width: _glyphSize,
                height: _glyphSize,
                child: switch (item.svgAsset) {
                  final asset? => SvgPicture.asset(asset, fit: BoxFit.contain, colorFilter: ColorFilter.mode(color, BlendMode.srcIn)),
                  _ => AppIcon(item.icon, size: _glyphSize, color: color),
                },
              ),
              const SizedBox(width: _glyphGap),
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.input.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "..." button that sits at the trailing edge of a list/box row and opens
/// [showAnchoredMenu] under itself. Stateful only to keep one [GlobalKey] for
/// the menu to anchor to across rebuilds.
/// [RowMenuButton]'s counterpart for a screen header: the glass "..." button a
/// detail screen carries in its title row, opening the same anchored menu.
/// Separate widget rather than a flag on [RowMenuButton] — that one is a bare
/// 15px glyph sized for a list row, this one is a full [GlassIconButton].
class GlassMenuButton extends StatefulWidget {
  final List<AnchoredMenuItem> items;
  final IconData icon;

  const GlassMenuButton({super.key, required this.items, this.icon = AppIcons.dotsThreeVertical});

  @override
  State<GlassMenuButton> createState() => _GlassMenuButtonState();
}

class _GlassMenuButtonState extends State<GlassMenuButton> {
  final GlobalKey _anchorKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _anchorKey,
      child: GlassIconButton(
        icon: widget.icon,
        onTap: () => showAnchoredMenu(context: context, anchorKey: _anchorKey, items: widget.items),
      ),
    );
  }
}

class RowMenuButton extends StatefulWidget {
  /// Rebuilt on every frame by the row, so the entries can close over whatever
  /// the row currently shows.
  final List<AnchoredMenuItem> items;
  final double menuWidth;

  const RowMenuButton({super.key, required this.items, this.menuWidth = AnchoredMenuSurface.defaultWidth});

  @override
  State<RowMenuButton> createState() => _RowMenuButtonState();
}

class _RowMenuButtonState extends State<RowMenuButton> {
  final GlobalKey _anchorKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _anchorKey,
      child: RowMoreButton(
        onTap: () => showAnchoredMenu(context: context, anchorKey: _anchorKey, items: widget.items, width: widget.menuWidth),
      ),
    );
  }
}

/// The three dots themselves, for a row whose "more" is not a menu.
///
/// The connected-calendar rows open a sheet instead: everything you can do to a
/// calendar is in it, so a menu in front of the sheet would be one tap and one
/// list of the same three words for nothing. The dots stay, because they are
/// what says a row has more behind it than the tap that opens it — but they
/// hang off this rather than off [RowMenuButton], so both kinds of row wear the
/// same mark at the same size and the geometry lives in one place.
class RowMoreButton extends StatelessWidget {
  final VoidCallback onTap;

  const RowMoreButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Without this only the glyph itself takes the tap — a 15px icon is a
      // hard target, so the padding around it has to count too.
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 32,
        height: 36,
        child: AppIcon(AppIcons.dotsThreeVertical, size: 15, color: AppColors.mutedLight),
      ),
    );
  }
}
