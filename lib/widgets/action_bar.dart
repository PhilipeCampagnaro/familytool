import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A scrolling body with the screen's primary action pinned to the bottom edge,
/// the content running underneath it.
///
/// Why pinned rather than the last row of the scroll, which is where every one
/// of these used to be: on a short page — a provider with one calendar
/// connected, the welcome step on a big phone — the action landed a third of
/// the way down the screen with nothing under it, and on a long one it was
/// below the fold. The same button was in a different place on every screen,
/// and sometimes nowhere at all. The bottom edge is the one position that is
/// the same on all of them, and it is where the thumb already is.
///
/// The bar measures itself and hands its height back to [bodyBuilder], which
/// must add it to the scroll view's bottom padding — otherwise the last row
/// cannot be scrolled clear of the bar. Measured rather than computed: the bar
/// carries the home-indicator inset and a label that wraps at large text sizes,
/// and a constant would bury the last row on exactly the phones that can least
/// afford it. Same technique as `CollapsingHeaderScreen`'s `_measureExtra`.
class PinnedActionLayout extends StatefulWidget {
  /// The scrolling content. [bottomInset] is what the bar occupies; it is 0
  /// while [action] is null, so a screen that sometimes has no action needs no
  /// branch of its own.
  final Widget Function(BuildContext context, double bottomInset) bodyBuilder;

  /// The action itself, already in its final shape — an `AccentAction`, a
  /// step button, a small column of a note above one. Null draws no bar at
  /// all, so a page whose action is gated (a non-admin's Familienmitglieder)
  /// ends where its content ends rather than on an empty band.
  final Widget? action;

  /// What the content fades into behind the bar. Defaults to the gray body
  /// panel every Settings page uses; the onboarding steps sit on
  /// [AppColors.surface] and pass that.
  final Color? fadeInto;

  /// First-frame guess, replaced after one frame: a pill (about 52) plus the
  /// bar's own padding. Only ever visible for the frame before the measure.
  final double estimatedActionHeight;

  const PinnedActionLayout({
    super.key,
    required this.bodyBuilder,
    required this.action,
    this.fadeInto,
    this.estimatedActionHeight = 100,
  });

  @override
  State<PinnedActionLayout> createState() => _PinnedActionLayoutState();
}

class _PinnedActionLayoutState extends State<PinnedActionLayout> {
  final GlobalKey _barKey = GlobalKey();
  double? _barHeight;

  void _measureBar() {
    final box = _barKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final height = box.size.height;
    if (_barHeight != null && (height - _barHeight!).abs() < 0.5) return;
    setState(() => _barHeight = height);
  }

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    if (action == null) return widget.bodyBuilder(context, 0);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measureBar();
    });

    return Stack(
      // Expand, not the loose default: the body is a scroll view, and under
      // loose constraints a short one shrink-wraps its content — the Stack
      // would then be as tall as the text and the bar would sit under the last
      // paragraph rather than at the bottom of the screen, which is the whole
      // thing this is here to stop.
      fit: StackFit.expand,
      children: [
        widget.bodyBuilder(context, _barHeight ?? widget.estimatedActionHeight),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: PinnedActionBar(key: _barKey, fadeInto: widget.fadeInto, child: action),
        ),
      ],
    );
  }
}

/// The band a [PinnedActionLayout]'s action sits in, drawn on its own so a
/// screen that already owns its layout can place one directly.
///
/// The gradient, not a flat fill: a hard edge across the screen reads as the
/// end of the page, and the content would then appear to stop at a line it is
/// in fact still scrolling past. Fading into the background lets a row dissolve
/// into the band instead of being cut by it.
///
/// Nothing may be added *after* the action inside here. The accent pill is a
/// native `UIGlassEffect` platform view on iOS, and Flutter content painted
/// after one is composited into a separate overlay view that lags during a
/// route push — the gradient is painted first for that reason, not just for the
/// stacking order. See the glass section of docs/design-system.md.
class PinnedActionBar extends StatelessWidget {
  final Widget child;
  final Color? fadeInto;

  const PinnedActionBar({super.key, required this.child, this.fadeInto});

  @override
  Widget build(BuildContext context) {
    final ground = fadeInto ?? AppColors.screenBg;
    // Zero inside a `SafeArea` that has already taken it — the onboarding
    // steps — and the real home-indicator height on a page that left the
    // bottom to us. A phone without an indicator gets the full padding, which
    // is what keeps the pill off the glass edge.
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    // Transparent Material, painting nothing: the bar is often the one thing on
    // a route that sits outside the Scaffold's own subtree, and a `Text` with no
    // Material above it falls back to the debug style — yellow, double
    // underlined. Cheaper to guarantee here than to rediscover on device.
    return Material(
      type: MaterialType.transparency,
      child: Container(
        padding: EdgeInsets.fromLTRB(16, 24, 16, safeBottom > 0 ? safeBottom + 6 : 22),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [ground.withValues(alpha: 0), ground],
            stops: const [0, .55],
          ),
        ),
        child: child,
      ),
    );
  }
}
