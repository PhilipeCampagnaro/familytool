import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/tokens.dart';
import 'glass.dart';

/// Shared bottom-sheet chrome: grab handle, header, then a scrolling body on
/// the F7F8FA sheet background. Matches every sheet/popup across Board,
/// Listen, Box and Kalender — including the calendar's event-detail sheet.
///
/// By default the header is the standard close (X) / [title] / save (check)
/// row. Pass [header] instead for a sheet whose header doesn't fit that
/// shape (e.g. a read-only detail view with no save action) — everything
/// else (backdrop, grab handle, outer chrome, scrolling body container)
/// still comes from this one shared widget.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  String? title,
  Widget? header,
  required Widget child,
  VoidCallback? onSave,
  double heightFactor = 0.92,
  SheetCollapsingHeader? collapsingHeader,
}) {
  assert(
    collapsingHeader != null || header != null || title != null,
    'showAppSheet needs a title (standard header), a custom header, or a collapsingHeader',
  );
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (ctx) => _AppSheetBody(
      title: title,
      header: header,
      onSave: onSave,
      heightFactor: heightFactor,
      collapsingHeader: collapsingHeader,
      child: child,
    ),
  );
}

/// Generic scroll-driven collapsing header for a pinned [SliverPersistentHeader]:
/// [builder] is called with a progress value `t` — 0 fully expanded, 1 fully
/// collapsed — tied directly to scroll offset, so the transition tracks the
/// user's finger instead of playing as a fixed-duration animation. Shared by
/// the Kalender week view's own header and any [SheetCollapsingHeader]-enabled
/// sheet, so both collapse the same way.
class CollapsingSliverHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double expandedHeight;
  final double collapsedHeight;
  final Widget Function(BuildContext context, double t) builder;

  const CollapsingSliverHeaderDelegate({required this.expandedHeight, required this.collapsedHeight, required this.builder});

  @override
  double get minExtent => collapsedHeight;

  @override
  double get maxExtent => expandedHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final currentExtent = (maxExtent - shrinkOffset).clamp(minExtent, maxExtent);
    final range = maxExtent - minExtent;
    final t = range <= 0 ? 1.0 : ((maxExtent - currentExtent) / range).clamp(0.0, 1.0);
    return SizedBox(height: currentExtent, child: builder(context, t));
  }

  @override
  bool shouldRebuild(covariant CollapsingSliverHeaderDelegate oldDelegate) => true;
}

/// Opts a [showAppSheet] sheet into a scroll-collapsing header (see
/// [CollapsingSliverHeaderDelegate]) instead of the fixed [header]/[title]
/// row — the header shrinks toward [collapsedHeight] as the sheet's body is
/// scrolled, letting the gray body grow up to cover it, matching the same
/// behavior as the Kalender week view. Most sheets don't need this; the
/// calendar event-detail sheet is the first (and so far only) user.
class SheetCollapsingHeader {
  final double expandedHeight;
  final double collapsedHeight;
  final Widget Function(BuildContext context, double t) builder;

  const SheetCollapsingHeader({required this.expandedHeight, required this.collapsedHeight, required this.builder});
}

/// Matches [GlassIconButton]'s default diameter — the sheet header's row height
/// and the room its title has to keep clear on either side.
const double _headerButtonSize = 40;

class _AppSheetBody extends StatelessWidget {
  final String? title;
  final Widget? header;
  final VoidCallback? onSave;
  final Widget child;
  final double heightFactor;
  final SheetCollapsingHeader? collapsingHeader;

  const _AppSheetBody({required this.title, required this.header, required this.onSave, required this.child, required this.heightFactor, this.collapsingHeader});

  /// Close / [title] / save row.
  ///
  /// A [Stack] with the title painted *first*, not a `Row` with the title as an
  /// `Expanded` sibling between the two buttons — that version shipped, and on
  /// iOS the title was simply invisible on device (it rendered fine in a widget
  /// test, where there are no platform views). [GlassIconButton] is a native
  /// `UIGlassEffect` platform view there, and Flutter content painted between
  /// two of them lands in a composited overlay layer that gets dropped. Painting
  /// the title before either button keeps it in the base layer, and spanning the
  /// full row also makes "centered" mean centered in the bar rather than in
  /// whatever the buttons left over — the same reason [CollapsingScreenTitle]
  /// is built this way (`collapsing_header.dart`).
  Widget _defaultHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: SizedBox(
        height: _headerButtonSize,
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                // Symmetric, so the title stays centered on the sheet even
                // though only one side carries the accent button.
                padding: const EdgeInsets.symmetric(horizontal: _headerButtonSize + 14),
                child: Center(
                  child: Text(title!, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.sheetTitle),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: GlassIconButton(
                icon: LucideIcons.x,
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: GlassConfirmButton(
                onTap: () {
                  onSave?.call();
                  Navigator.of(context).pop();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final grayBody = Container(
      // `width: double.infinity` is load-bearing: the enclosing Column centers
      // its children (loose width constraints), so without it the gray panel
      // is only as wide as whatever's inside it. Most sheets hide that — their
      // rows are max-width `Row`s that fill the sheet anyway — but a narrow
      // body (a centered empty state) left the panel floating as a too-narrow
      // slab with white either side.
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      decoration: BoxDecoration(
        color: AppColors.screenBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [child]),
      ),
    );

    return FractionallySizedBox(
      heightFactor: heightFactor,
      alignment: Alignment.bottomCenter,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          boxShadow: AppShadows.sheet,
        ),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(0, 10, 0, 2),
              child: SizedBox(
                width: 44,
                height: 4,
                child: DecoratedBox(decoration: BoxDecoration(color: AppColors.grabHandle, borderRadius: BorderRadius.all(Radius.circular(2)))),
              ),
            ),
            if (collapsingHeader case final collapsing?)
              Expanded(
                child: NestedScrollView(
                  headerSliverBuilder: (context, _) => [
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: CollapsingSliverHeaderDelegate(
                        expandedHeight: collapsing.expandedHeight,
                        collapsedHeight: collapsing.collapsedHeight,
                        builder: collapsing.builder,
                      ),
                    ),
                  ],
                  body: Container(margin: const EdgeInsets.only(top: 14), child: grayBody),
                ),
              )
            else ...[
              header ?? _defaultHeader(context),
              Expanded(child: Container(margin: const EdgeInsets.only(top: 14), child: grayBody)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Close / [title], without the sheet's usual save check — for a sheet where
/// picking one of the options *is* the save, so a second confirmation would
/// only be a way to lose the choice. Pass it as [showAppSheet]'s `header`.
///
/// Same Stack-before-buttons construction as the standard header; see
/// [showAppSheet] for why the title has to be painted first.
class SheetPickerHeader extends StatelessWidget {
  final String title;

  const SheetPickerHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: SizedBox(
        height: _headerButtonSize,
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: _headerButtonSize + 14),
                child: Center(
                  child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.sheetTitle),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: GlassIconButton(icon: LucideIcons.x, onTap: () => Navigator.of(context).pop()),
            ),
          ],
        ),
      ),
    );
  }
}

/// A white rounded card used to group form rows / list rows, matching the
/// `background:#FFFFFF;border-radius:20-22px;box-shadow:0 2px 10px rgba(17,26,43,.06)` pattern.
class SectionCard extends StatelessWidget {
  final List<Widget> children;
  final double radius;

  const SectionCard({super.key, required this.children, this.radius = AppRadii.cardSmall});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

/// A full-width bordered action at the foot of a sheet — "Teilen", "Löschen".
///
/// Not a [SectionCard] row: these are things done *to* the item rather than
/// fields of it, so they sit apart from the card that holds what you typed.
class OutlinedSheetAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool destructive;
  final VoidCallback onTap;

  const OutlinedSheetAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.danger : AppColors.ink;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.cardSmall),
          boxShadow: AppShadows.card,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 9),
            Text(
              label,
              style: AppText.rowTitle.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single divider-topped row used inside [SectionCard]s.
class CardDivider extends StatelessWidget {
  const CardDivider({super.key});

  @override
  Widget build(BuildContext context) => Divider(height: 1, thickness: 1, color: AppColors.divider);
}

/// [CardDivider] inset from the card's edges — the separator between
/// [FieldGroup]s and member rows, where a full-bleed rule cuts the card in
/// half.
class InsetDivider extends StatelessWidget {
  const InsetDivider({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: CardDivider(),
      );
}

/// [rows] with a divider dropped between every neighbouring pair — the body of
/// almost every [SectionCard] in the app.
///
/// Written out by hand this is a `for (var i = 0; …) if (i > 0) CardDivider()`
/// loop, which was copied into a dozen screens and is the kind of thing that
/// only ever goes wrong in one direction: a card that grows a second row and
/// keeps rendering it flush against the first. Passing an empty list yields an
/// empty card rather than a stray rule.
List<Widget> dividedRows(List<Widget> rows, {bool inset = false}) => [
      for (var i = 0; i < rows.length; i++) ...[
        if (i > 0) inset ? InsetDivider() : CardDivider(),
        rows[i],
      ],
    ];
