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
    if (filter == null || filter.isEmpty) return AppColors.muted;
    // The first *listed* calendar in the filter rather than the first in the
    // set: a Set has no order, so reading one out of it would repaint the dot a
    // different colour on an unrelated rebuild.
    for (final src in state.calendars) {
      if (filter.contains(src.id)) return src.color;
    }
    return AppColors.muted;
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
class _FilterMenuRoute extends PopupRoute<Set<String>> {
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
class _FilterMenuSurface extends ConsumerWidget {
  static const width = 244.0;

  final CalendarScreenState state;

  const _FilterMenuSurface({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                  _FilterMenuRow(
                    label: L.s.all,
                    color: AppColors.muted,
                    active: state.calendarFilter == null,
                    value: const {},
                  ),
                  // The collapsed stand-in lists the same accounts the chip row
                  // does, and indents an account's calendars underneath it —
                  // so the one place a calendar can be picked individually
                  // survives the header scrolling away.
                  for (final group in state.activeGroups) ...[
                    // Hairline, inset past the dot the way a UIKit menu insets
                    // separators past the row's leading icon.
                    Padding(
                      padding: EdgeInsets.only(left: 16),
                      child: Divider(height: 0.5, thickness: 0.5, color: AppColors.menuSeparator),
                    ),
                    _FilterMenuRow(
                      label: _groupLabel(ref, group),
                      color: group.color,
                      active: _isWholeFilter(state, group.ids),
                      value: group.ids,
                    ),
                    if (group.hasChoices)
                      for (final src in group.calendars)
                        _FilterMenuRow(
                          label: src.name,
                          color: src.color,
                          active: _isWholeFilter(state, {src.id}),
                          value: {src.id},
                          indent: true,
                        ),
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

/// Whether [ids] is exactly what the calendar is filtered to — the check that
/// puts the tick beside a row. Not "contains": an account row is ticked when
/// the whole account is showing and nothing else, which is what tapping it does.
bool _isWholeFilter(CalendarScreenState state, Set<String> ids) {
  final filter = state.calendarFilter;
  return filter != null && filter.length == ids.length && filter.containsAll(ids);
}

class _FilterMenuRow extends StatelessWidget {
  final String label;
  final Color color;
  final bool active;
  final Set<String> value;

  /// A calendar listed under its account, rather than a row in its own right.
  final bool indent;

  const _FilterMenuRow({
    required this.label,
    required this.color,
    required this.active,
    required this.value,
    this.indent = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(value),
      child: Padding(
        padding: EdgeInsets.only(left: indent ? 32 : 16, right: 16, top: indent ? 10 : 13, bottom: indent ? 10 : 13),
        child: Row(
          children: [
            Container(
              width: indent ? 7 : 9,
              height: indent ? 7 : 9,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            SizedBox(width: indent ? 12 : 10),
            Expanded(
              child: Text(
                label,
                style: active
                    ? AppText.itemTitle
                    : (indent ? AppText.caption : AppText.input),
              ),
            ),
            if (active) Icon(LucideIcons.check, size: 16, color: AppColors.ink),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The chip's own calendar list
// ---------------------------------------------------------------------------

/// The popup that hangs off an account chip: its calendars, each tickable.
///
/// Distinct from [_FilterMenuRoute] in what it is for. That one stands in for
/// the whole chip row once the header has collapsed, and picking from it
/// *replaces* the filter. This one belongs to one chip and refines what is
/// already showing inside that account, so it stays open while rows are ticked
/// — narrowing three calendars to two is one gesture, not two round trips
/// through a menu.
///
/// It borrows [_FilterMenuSurface]'s material rather than a [GlassSurface], for
/// the reason recorded there: UIKit's own menus are a near-opaque vibrant
/// material, and real glass over the month grid let the day numbers read
/// straight through the rows.
class _CalendarPickerRoute extends PopupRoute<void> {
  /// The chip's rect in global coordinates.
  final Rect anchor;
  final CalendarGroup group;
  final void Function(String calendarId) onToggle;

  _CalendarPickerRoute({
    required this.anchor,
    required this.group,
    required this.onToggle,
  });

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
    final maxLeft =
        (size.width - _FilterMenuSurface.width - AppSpacing.screenPad)
            .clamp(AppSpacing.screenPad, double.infinity);
    return Stack(
      children: [
        Positioned(
          left: anchor.left.clamp(AppSpacing.screenPad, maxLeft),
          top: anchor.bottom + 6,
          child: _CalendarPickerSurface(group: group, onToggle: onToggle),
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

/// The picker's panel. A [ConsumerWidget] rather than a plain one because the
/// route stays up while rows are ticked: it has to redraw its own checkmarks
/// from the filter it is changing.
class _CalendarPickerSurface extends ConsumerWidget {
  final CalendarGroup group;
  final void Function(String calendarId) onToggle;

  const _CalendarPickerSurface({required this.group, required this.onToggle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(calendarProvider).calendarFilter;
    // No filter at all means every calendar is showing, including all of these.
    final shown = filter == null ? group.ids : filter.intersection(group.ids);

    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: [...AppShadows.menu],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              width: _FilterMenuSurface.width,
              color: AppColors.menuSurface,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The account's name as a caption over its calendars, so the
                  // panel says whose three these are once it has covered the
                  // chip it came out of.
                  Padding(
                    padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 6),
                    child: Text(_groupLabel(ref, group), style: AppText.microLabel),
                  ),
                  for (final src in group.calendars)
                    _CalendarPickerRow(
                      source: src,
                      checked: shown.contains(src.id),
                      onTap: () => onToggle(src.id),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CalendarPickerRow extends StatelessWidget {
  final CalendarSource source;
  final bool checked;
  final VoidCallback onTap;

  const _CalendarPickerRow({required this.source, required this.checked, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: source.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                source.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: checked ? AppText.itemTitle : AppText.input,
              ),
            ),
            // Drawn either way rather than only when ticked: an unticked row
            // with nothing on the right reads as a label, and the whole point
            // of this panel is that every row is a switch.
            //
            // Round and accent-blue, the shape a multiple-choice tick has on
            // iOS — and deliberately *not* the calendar's own colour, which is
            // already saying which calendar this is in the dot on the left. A
            // box that changed hue per row would read as a second piece of
            // information rather than as "on".
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: checked ? AppColors.accent : Colors.transparent,
                border: checked
                    ? null
                    : Border.all(color: AppColors.inkTertiary, width: 1.5),
              ),
              child: checked
                  ? const Icon(LucideIcons.check, size: 13, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
