import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import 'app_sheet.dart';
import 'glass.dart';

/// The screen-level collapsing header, generalised out of the Kalender week
/// view so Board, Box and Listen scroll the same way: a title row that stays
/// pinned while everything below it (search field, stat tiles, week strip, a
/// detail screen's big name row) shrinks and fades away as the body scrolls,
/// over a [FrostedHeaderBackground] the content then passes under blurred.
///
/// The collapse is driven straight off scroll offset by
/// [CollapsingSliverHeaderDelegate] (`t`: 0 expanded → 1 collapsed), not by a
/// fixed-duration animation, so it tracks the user's finger.
///
/// Kalender deliberately still has its own copy of this plumbing: its header
/// carries a freely-scrolling day strip whose geometry the week view owns, and
/// its title row hosts a filter dropdown that only exists while collapsed.
/// Reworking it to route through here would mean widening this API to fit one
/// caller, so the two are kept apart on purpose — but they must stay in step,
/// so a change to how the collapse *feels* belongs in both.
class CollapsingHeaderScreen extends StatefulWidget {
  /// The pinned row. Rebuilt at every `t` so the title can morph — see
  /// [CollapsingScreenTitle], which is what every caller passes.
  final Widget Function(BuildContext context, double t) titleRowBuilder;

  /// Everything below the title row: shown at rest, clipped and faded to
  /// nothing as the header collapses.
  final Widget extra;

  /// First-frame guess at [extra]'s height, corrected to the real thing as soon
  /// as there's something laid out to measure (see [_CollapsingHeaderScreenState]).
  ///
  /// It exists only because a [SliverPersistentHeader] has to publish its
  /// extents *before* anything under it can be laid out, so frame one has
  /// nothing to go on. Being a few px out costs one frame and nothing else —
  /// which is the point of measuring rather than hardcoding: the app's type is
  /// Poppins, loaded at runtime by `google_fonts`, so the line heights a widget
  /// test measures aren't the ones the device renders and a constant tuned
  /// against a test would silently clip the last row on a phone.
  final double estimatedExtraHeight;

  /// The scrolling content. Must contain a scrollable (it picks up
  /// [NestedScrollView]'s inner controller through [PrimaryScrollController]),
  /// or there's nothing to drive the collapse.
  final Widget body;

  /// A screen-level tint (the detail screens' brand glow) drawn *over* the
  /// frosted material and under the title row.
  ///
  /// Over, not under, because the frost is 60%-odd white: a glow behind it
  /// washes out to nothing, which is exactly what happened when these screens
  /// first got a frosted header. On top, it tints the bar the way a colored nav
  /// bar does, and the content still passes under it blurred.
  ///
  /// It's given its natural height, anchored to the top of the header and
  /// clipped to whatever the header currently is — so the gradient keeps its
  /// geometry as the header collapses instead of being squashed into the
  /// shrinking bar, which would slide its colors around while you scroll.
  /// (Nothing is lost below: the body panel is opaque, so the header band is
  /// the only place a backdrop was ever visible.)
  final Widget? backdrop;

  final double titleRowHeight;
  final EdgeInsets extraPadding;

  const CollapsingHeaderScreen({
    super.key,
    required this.titleRowBuilder,
    required this.extra,
    required this.estimatedExtraHeight,
    required this.body,
    this.backdrop,
    this.titleRowHeight = 40,
    this.extraPadding = const EdgeInsets.symmetric(horizontal: AppSpacing.screenPad),
  });

  static const topPad = 8.0;

  /// Sits inside the *collapsed* height on purpose: it's the band of header
  /// that survives at t == 1, so the sharp gray body starts a little below the
  /// glass buttons instead of butting straight against them.
  static const collapsedGap = 14.0;

  @override
  State<CollapsingHeaderScreen> createState() => _CollapsingHeaderScreenState();
}

class _CollapsingHeaderScreenState extends State<CollapsingHeaderScreen> {
  final _extraKey = GlobalKey();
  double? _measured;

  /// The status-bar strip, absorbed into the header rather than left to a
  /// [SafeArea] above it, so the frost and [CollapsingHeaderScreen.backdrop]
  /// run edge to edge and content scrolls away under the notch instead of
  /// stopping at a hard white band. Screens still wrapped in a `SafeArea` read
  /// 0 here — the `SafeArea` has already consumed the inset — so this costs
  /// them nothing.
  double _topInset(BuildContext context) => MediaQuery.paddingOf(context).top;

  double _collapsedHeight(BuildContext context) => _topInset(context) + CollapsingHeaderScreen.topPad + widget.titleRowHeight + CollapsingHeaderScreen.collapsedGap;

  /// [extra] is laid out unbounded (see [_buildHeader]) so it always takes its
  /// natural height; this reads that back and re-publishes the sliver's extent
  /// to match. Runs after every frame so a change in the content — or in the
  /// platform text scale — re-settles instead of clipping.
  ///
  /// Zero is a legitimate measurement, not a "not laid out yet" one: a screen
  /// may drop its collapsing block entirely (Listen and Boxen do while their
  /// header is showing the search field), and treating 0 as garbage would leave
  /// the sliver holding the old block's height as empty space.
  void _measureExtra() {
    final box = _extraKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final height = box.size.height;
    if (_measured != null && (height - _measured!).abs() < 0.5) return;
    setState(() => _measured = height);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measureExtra();
    });
    final extraHeight = _measured ?? widget.estimatedExtraHeight;
    final collapsedHeight = _collapsedHeight(context);
    final topInset = _topInset(context);

    return NestedScrollView(
      headerSliverBuilder: (context, _) => [
        SliverPersistentHeader(
          pinned: true,
          delegate: CollapsingSliverHeaderDelegate(
            expandedHeight: collapsedHeight + extraHeight,
            collapsedHeight: collapsedHeight,
            builder: (context, t) => _buildHeader(context, t, extraHeight, topInset),
          ),
        ),
      ],
      body: widget.body,
    );
  }

  Widget _buildHeader(BuildContext context, double t, double extraHeight, double topInset) {
    final visible = (1 - t).clamp(0.0, 1.0);
    // Frosted rather than solid: NestedScrollView doesn't clip its body to
    // below a pinned header — the gray panel keeps sliding up until its top
    // reaches the top of the screen — so without a material of its own the
    // header has content rendering sharply behind the title and glass buttons.
    // The blur stops it reading as content while still showing it's there,
    // passing underneath.
    //
    // A Stack, not a wrapper around the Column, so the frost is a sibling layer
    // filling the header's *current* extent: as the sliver shrinks, so does the
    // blurred band.
    return Stack(
      children: [
        Positioned.fill(child: FrostedHeaderBackground()),
        if (widget.backdrop != null)
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRect(
                // Faded out at the header's *current* bottom edge, not just
                // clipped there: the wash still carries color that far down, and
                // a bare clip ended it in a hard colored line along the top of
                // the body panel — most visible collapsed, where the header is
                // at its shortest. The mask makes the edge the end of a falloff
                // instead of a cut, at every scroll position.
                child: ShaderMask(
                  shaderCallback: (rect) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white, Colors.white, Color(0x00FFFFFF)],
                    stops: [0, .45, 1],
                  ).createShader(rect),
                  blendMode: BlendMode.dstIn,
                  child: OverflowBox(alignment: Alignment.topCenter, minHeight: 0, maxHeight: double.infinity, child: widget.backdrop),
                ),
              ),
            ),
          ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(AppSpacing.screenPad, topInset + CollapsingHeaderScreen.topPad, AppSpacing.screenPad, 0),
              child: SizedBox(height: widget.titleRowHeight, child: widget.titleRowBuilder(context, t)),
            ),
            // The OverflowBox leaves the height unbounded so `extra` keeps its
            // natural size while the SizedBox around it shrinks: its rows slide
            // up under the title and get clipped, instead of being squeezed into
            // less and less space (which would re-flow them, and overflow once
            // there's no room left). It's also what makes the measurement above
            // meaningful — there's a real, unconstrained height to read.
            SizedBox(
              height: extraHeight * visible,
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  minHeight: 0,
                  maxHeight: double.infinity,
                  child: Opacity(
                    opacity: visible,
                    child: Padding(
                      padding: widget.extraPadding,
                      child: KeyedSubtree(key: _extraKey, child: widget.extra),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: CollapsingHeaderScreen.collapsedGap),
          ],
        ),
      ],
    );
  }
}

/// The title inside a [CollapsingHeaderScreen]'s pinned row, morphing from a
/// large left-aligned heading to a small centered one the way an iOS large-title
/// nav bar does.
///
/// Pass [collapsedTitle] on a detail screen, where the pinned row's label is a
/// generic one ("Box", "Liste") and the *item's* name lives in the collapsing
/// content below: the two crossfade, so the name takes over the bar exactly as
/// the big version scrolls out of sight.
class CollapsingScreenTitle extends StatelessWidget {
  final String title;
  final String? collapsedTitle;

  /// Rides along with [collapsedTitle] — the list's brand logo, the box's
  /// icon — so the bar carries the same badge/name pair the big row below it
  /// was showing, rather than dropping to a bare string. Sized by the caller;
  /// keep it around the collapsed cap height.
  final Widget? collapsedIcon;

  final double t;

  /// Controls pinned to the far left / right of the row. They're overlaid on
  /// the title layer rather than laid out beside it — see [build].
  final Widget? leading;
  final Widget? trailing;

  /// How much horizontal room each control needs *at rest*, including the gap
  /// to the title. Only used to keep the expanded title clear of them.
  final double leadingWidth;
  final double trailingWidth;

  /// Inset applied to **both** sides at t == 1, defaulting to whichever control
  /// is wider plus breathing room. Both sides get the same value even when only
  /// one has a control: an asymmetric inset is exactly what knocks a centered
  /// title off-center. Override it when a control shrinks away as the header
  /// collapses (Board's avatar stack), so the collapsed title isn't reserving
  /// room for something that's no longer there.
  final double? collapsedSideInset;

  final double expandedFontSize;
  final double collapsedFontSize;
  final FontWeight fontWeight;

  /// Where the title sits at rest. Overview screens start flush left (the large
  /// heading); detail screens are centered at both ends, since their pinned row
  /// is a back/label/menu nav bar rather than a heading.
  final Alignment expandedAlignment;

  const CollapsingScreenTitle({
    super.key,
    required this.title,
    required this.t,
    this.collapsedTitle,
    this.collapsedIcon,
    this.leading,
    this.trailing,
    this.leadingWidth = 0,
    this.trailingWidth = 0,
    this.collapsedSideInset,
    this.expandedFontSize = 26,
    this.collapsedFontSize = 17,
    this.fontWeight = FontWeight.w600,
    this.expandedAlignment = Alignment.centerLeft,
  });

  /// The crossfade between [title] and [collapsedTitle] is held back until the
  /// collapse is nearly done — the name only makes sense in the bar once the
  /// big version it's replacing has actually gone.
  double get _swap => ((t - 0.55) / 0.45).clamp(0.0, 1.0);

  double get _sideInset => collapsedSideInset ?? math.max(leadingWidth, trailingWidth) + 38;

  /// The inset each side gets *at rest*. A left-aligned heading wants the real
  /// per-side widths — it only has to clear the controls. A centered one wants
  /// them equal, for the same reason [collapsedSideInset] applies to both
  /// sides: reserving 48 on one side and 84 on the other centers the title in
  /// what's left over, which is visibly off-center by half the difference.
  double? get _expandedInset => expandedAlignment.x == 0 ? math.max(leadingWidth, trailingWidth) : null;

  @override
  Widget build(BuildContext context) {
    final swap = _swap;
    final inset = _sideInset;
    final expandedLeft = _expandedInset ?? leadingWidth;
    final expandedRight = _expandedInset ?? trailingWidth;
    final alignment = Alignment.lerp(expandedAlignment, Alignment.center, t)!;

    Widget label(String text, double fontSize, {Widget? icon}) {
      final text0 = Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontFamily: 'Poppins', fontWeight: fontWeight, letterSpacing: -0.3, fontSize: fontSize, color: AppColors.ink),
      );
      return Align(
        alignment: alignment,
        // The Flexible is load-bearing: in a min-width Row the label has to be
        // allowed to ellipsize, or a long name pushes the badge off-center and
        // overflows the row it's meant to be centered in.
        child: icon == null
            ? text0
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  icon,
                  const SizedBox(width: 8),
                  Flexible(child: text0),
                ],
              ),
      );
    }

    return Stack(
      children: [
        // The title is its own full-width layer rather than an `Expanded`
        // sibling of the controls: as a Row child its "center" would be the
        // center of whatever space they left over, so the collapsed title sat
        // visibly off-center by half a button's width. Spanning the whole row
        // makes centered mean centered, whatever flanks it.
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.only(left: expandedLeft + (inset - expandedLeft) * t, right: expandedRight + (inset - expandedRight) * t),
            child: collapsedTitle == null
                ? label(title, expandedFontSize + (collapsedFontSize - expandedFontSize) * t)
                : Stack(
                    children: [
                      Positioned.fill(
                        child: Opacity(opacity: 1 - swap, child: label(title, expandedFontSize)),
                      ),
                      Positioned.fill(
                        child: Opacity(
                          opacity: swap,
                          child: label(collapsedTitle!, collapsedFontSize, icon: collapsedIcon),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        // Overlaid rather than laid out inline for the same reason as the
        // title: reserving width for them in a Row would drag the expanded,
        // left-aligned heading sideways.
        if (leading != null) Positioned(left: 0, top: 0, bottom: 0, child: Center(child: leading!)),
        if (trailing != null) Positioned(right: 0, top: 0, bottom: 0, child: Center(child: trailing!)),
      ],
    );
  }
}

/// The colored wash a detail screen puts behind its header — the list's brand
/// color, the box's accent — as [CollapsingHeaderScreen.backdrop].
///
/// Anchored to the very top of the screen, status bar included: it's a tint on
/// the whole top edge, so stopping it at the safe area would leave a white band
/// above it and give away that the color is a rectangle rather than the surface
/// itself.
class HeaderBrandGlow extends StatelessWidget {
  final Color color;

  /// Peak alpha at the center of the wash. Deliberately low — it sits over the
  /// frosted material, where it reads as a tint on the bar, not as a fill.
  final double strength;

  /// Taller than any header it's clipped to, so the gradient's geometry is
  /// fixed on the screen instead of being derived from the collapsing bar.
  static const _height = 360.0;

  const HeaderBrandGlow({super.key, required this.color, this.strength = .17});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            // Centered above the top edge: only the lower arc of the falloff is
            // on screen, which is what makes it read as light spilling in from
            // off-screen rather than a blob sitting in the bar.
            center: const Alignment(0, -1.3),
            // Scaled so the falloff spans the full width of the bar and reaches
            // well past the collapsed header before it's gone: with a tighter
            // radius only the innermost arc landed inside the clip, and the
            // brand color read as a faint smudge instead of a wash.
            radius: 1.35,
            // The outer stop fades the brand hue out to nothing rather than out
            // to transparent *white* — Flutter lerps RGB and alpha separately,
            // so a white end stop drags a pale haze through the falloff, which
            // on a dark header shows up as a grey bloom around the wash.
            colors: [shade(color, strength), shade(color, strength * .32), shade(color, 0)],
            stops: const [0, .45, .8],
          ),
        ),
      ),
    );
  }
}

/// The rounded gray panel every screen's scrolling content sits on. Under a
/// [CollapsingHeaderScreen] its top corners slide up under the frosted header
/// as you scroll, which is what makes the two read as one surface.
class ScreenBodyPanel extends StatelessWidget {
  final Widget child;

  const ScreenBodyPanel({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.screenBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
