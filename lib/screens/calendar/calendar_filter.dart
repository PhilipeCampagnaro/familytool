part of '../calendar_screen.dart';

// Filtering the visible calendars down to one: the glass dropdown that
// replaces the chip row once the header has collapsed, and the popup route
// behind it. The chips themselves live with the header in calendar_screen.dart.

/// Compact "liquid glass" dropdown standing in for the filter chip row once
/// the header has collapsed — the chips don't fit a collapsed header, so this
/// pins a small dot (the active source's colour, or muted for "Alle") +
/// chevron in the title row itself, opening a native-feeling glass menu (dot
/// + full name per calendar) to pick a filter from. Only visible while
/// collapsed; see [_TitleRow.leading].
class _CalendarFilterButton extends ConsumerWidget {
  final CalendarScreenState state;

  const _CalendarFilterButton({required this.state});

  Color get _dotColor {
    final filter = state.calendarFilter;
    if (filter == null) return AppColors.muted;
    return state.sourceById(filter)?.color ?? AppColors.muted;
  }

  Future<void> _openMenu(BuildContext context, WidgetRef ref) async {
    final button = context.findRenderObject() as RenderBox;
    final anchor = button.localToGlobal(Offset.zero) & button.size;
    final selected = await Navigator.of(context).push(_FilterMenuRoute(anchor: anchor, state: state));
    if (selected == null) return;
    if (selected.isEmpty) {
      ref.read(calendarProvider.notifier).clearCalendarFilter();
    } else {
      ref.read(calendarProvider.notifier).setCalendarFilter(selected);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAll = state.calendarFilter == null;
    return GestureDetector(
      onTap: () => _openMenu(context, ref),
      child: SizedBox(
        height: 40,
        child: Center(
          child: GlassSurface(
            borderRadius: BorderRadius.circular(18),
            // No forced `tint`: on iOS this is a real UIGlassEffect, and
            // pinning its tintColor to a near-opaque grey made it render as a
            // flat pill instead of glass. The Flutter approximation still
            // needs a light colour to keep the chevron legible.
            fallbackTint: AppColors.navPillTint,
            blurSigma: 16,
            boxShadow: AppShadows.glassButton,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: isAll ? 13 : 12, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // "Alle" is spelled out — a plain gray dot doesn't read as
                  // "everything" the way a source's own colour reads as that
                  // source. Once a specific calendar is picked, its dot alone
                  // is unambiguous, so the label drops back to just that.
                  if (isAll)
                    Text(L.s.all, style: AppText.caption)
                  else
                    Container(width: 9, height: 9, decoration: BoxDecoration(color: _dotColor, shape: BoxShape.circle)),
                  const SizedBox(width: 7),
                  Icon(LucideIcons.chevronDown, size: 15, color: AppColors.inkTertiary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Anchored dropdown route for [_CalendarFilterButton]. This used to be
/// `showMenu` + a single disabled `PopupMenuItem`, but that route animates by
/// growing the panel's height while staggering each item's own fade — behind
/// a translucent glass surface that read as a smeared, half-drawn slab
/// overlapping the grid rather than a menu. This instead lays the finished
/// panel out under the button and scales + fades it out of its anchor corner,
/// the way a UIKit menu opens.
class _FilterMenuRoute extends PopupRoute<String> {
  /// The filter button's rect in global coordinates.
  final Rect anchor;
  final CalendarScreenState state;

  _FilterMenuRoute({required this.anchor, required this.state});

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

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    final size = MediaQuery.sizeOf(context);
    return Stack(
      children: [
        Positioned(
          // Left-aligned with the button, nudged back inside the screen if a
          // wide menu would otherwise run off the right edge.
          left: anchor.left.clamp(AppSpacing.screenPad, (size.width - _FilterMenuSurface.width - AppSpacing.screenPad).clamp(AppSpacing.screenPad, double.infinity)),
          top: anchor.bottom + 6,
          child: _FilterMenuSurface(state: state),
        ),
      ],
    );
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeIn);
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
        alignment: Alignment.topLeft,
        child: child,
      ),
    );
  }
}

/// The [_CalendarFilterButton]'s dropdown content — listing "Alle" plus every
/// calendar source (dot + full name), checkmarking whichever is active.
/// Positioned and dismissed by [_FilterMenuRoute]; this only draws the panel.
///
/// Deliberately *not* a [GlassSurface]: UIKit's own menus aren't liquid glass,
/// they're a near-opaque vibrant material, and a glass panel over the dense
/// month grid just let the day numbers read through the rows. This matches the
/// native menu instead — a blurred backdrop under an almost-solid fill, tight
/// 14pt corners and hairline separators.
class _FilterMenuSurface extends StatelessWidget {
  static const width = 244.0;

  final CalendarScreenState state;

  const _FilterMenuSurface({required this.state});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            ...AppShadows.menu,
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              width: width,
              // Only the last 3% of translucency, so the material still picks
              // up a hint of what's behind it without anything reading through.
              color: AppColors.menuSurface,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _FilterMenuRow(label: L.s.all, color: AppColors.muted, active: state.calendarFilter == null, value: ''),
                  for (final src in state.activeSources) ...[
                    // Hairline, inset past the dot the way a UIKit menu insets
                    // separators past the row's leading icon.
                    Padding(
                      padding: EdgeInsets.only(left: 16),
                      child: Divider(height: 0.5, thickness: 0.5, color: AppColors.menuSeparator),
                    ),
                    _FilterMenuRow(label: src.name, color: src.color, active: state.calendarFilter == src.id, value: src.id),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterMenuRow extends StatelessWidget {
  final String label;
  final Color color;
  final bool active;
  final String value;

  const _FilterMenuRow({required this.label, required this.color, required this.active, required this.value});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: active ? AppText.itemTitle : AppText.input,
              ),
            ),
            if (active) Icon(LucideIcons.check, size: 16, color: AppColors.ink),
          ],
        ),
      ),
    );
  }
}
