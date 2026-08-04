import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/tokens.dart';
import 'native_glass_view.dart';

/// Apple's "Liquid Glass" material. On iOS this embeds the real native
/// `UIGlassEffect` (iOS 26) via a platform view — genuine refraction/blur of
/// whatever's behind it, not a Flutter drawing. On every other platform
/// (Android, web, ...) there's no such material to embed, so it falls back to
/// a Flutter-drawn approximation: a blurred backdrop, translucent tint, and a
/// soft specular highlight so it still reads as glass even sitting on a flat
/// background. Used for the bottom nav, the floating "+" buttons and the
/// sheet header's close/save controls.
class GlassSurface extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;

  /// Null means "no forced tint" on iOS — the real glass's own adaptive
  /// appearance applies. The Flutter-approximation fallback (non-iOS) always
  /// needs a concrete color to draw, so it substitutes [fallbackTint], or a
  /// neutral default if that's null too.
  ///
  /// Prefer null here: a forced tint is passed straight to `UIGlassEffect`'s
  /// `tintColor`. Only pass a colour for a deliberate accent — and for the
  /// blue confirm button that means [GlassConfirmButton], which owns that one
  /// treatment (and explains there why its accent is opaque).
  final Color? tint;

  /// Tint for the Flutter-drawn approximation only, ignored on iOS. Lets a
  /// control keep the real glass's adaptive appearance on iOS (`tint: null`)
  /// while still drawing a legible light material everywhere else — the
  /// neutral default is dark, which would swallow dark-on-glass labels.
  final Color? fallbackTint;
  final double blurSigma;
  final List<BoxShadow>? boxShadow;
  final bool interactive;

  /// Skips the real native glass even on iOS. Platform views (the native
  /// `UIGlassEffect`) are a composited texture that Flutter can't transform
  /// cleanly — embedding one inside an animated `Transform`/`ScaleTransition`
  /// (e.g. a `showMenu` popup's open/close animation) renders as a smeared,
  /// blobby mess instead of scaling the way a plain Flutter-drawn layer
  /// would. Anything shown inside such a transition should set this `true`.
  final bool forceFlutterApproximation;

  const GlassSurface({
    super.key,
    required this.child,
    required this.borderRadius,
    this.tint,
    this.fallbackTint,
    this.blurSigma = 20,
    this.boxShadow,
    this.interactive = true,
    this.forceFlutterApproximation = false,
  });

  bool get _useNativeGlass => !forceFlutterApproximation && !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: boxShadow),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          children: [
            Positioned.fill(
              child: _useNativeGlass
                  ? NativeGlassView(tint: tint, interactive: interactive)
                  : _FlutterGlassApproximation(tint: tint ?? fallbackTint ?? AppColors.glassFallbackTint, blurSigma: blurSigma),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

class _FlutterGlassApproximation extends StatelessWidget {
  final Color tint;
  final double blurSigma;

  const _FlutterGlassApproximation({required this.tint, required this.blurSigma});

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
      // StackFit.expand is load-bearing: a childless DecoratedBox is a
      // RenderProxyBox, which sizes to `constraints.smallest`. Under the
      // default StackFit.loose that's zero, so the tint + border layer laid
      // out at Size.zero and never painted — leaving only the blur and the
      // specular highlight, which read as a washed-out, see-through panel no
      // matter how opaque `tint` was.
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                // Lightening toward the top is what sells the curvature. It
                // has to be far gentler on dark: the backdrop is already dark,
                // so a 30% white lift turns the panel into a grey slab.
                colors: [Color.lerp(tint, Colors.white, AppColors.isDark ? 0.10 : 0.3)!, tint],
              ),
              border: Border.all(color: AppColors.glassRim, width: 1),
            ),
          ),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.6, -0.8),
                  radius: 1.2,
                  colors: [AppColors.glassSpecular, AppColors.glassSpecular.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The material behind a collapsing header: a *progressive* blur under a
/// translucent white that both ramp to nothing at the bottom edge — the
/// variable-blur treatment Apple uses under nav bars, rather than a uniform
/// frosted panel.
///
/// It exists because `NestedScrollView` does *not* clip its body to below a
/// pinned header: the scrolled content keeps sliding up until its top reaches
/// the top of the screen, so without a background of its own a header has the
/// agenda/sheet content rendering straight through the title and buttons. A
/// solid fill would hide that content outright; this washes it out instead, so
/// you can still see it passing underneath.
///
/// The ramp is the whole point, and the reason this isn't one `BackdropFilter`
/// with one tint. A uniform bar ends in a hard step — sharp content and a flat
/// tone change, both at the same y — and that edge is what makes it read as a
/// separate rectangle sitting *over* the screen. Fading both to zero means
/// there is no edge to see: content simply gets blurrier the further it slides
/// under the title.
///
/// Deliberately *not* a [GlassSurface]: liquid glass has a specular highlight
/// and refracts at its edges, which reads as a floating control. A header is an
/// edge-to-edge bar, and a bar wants a plain material.
class FrostedHeaderBackground extends StatelessWidget {
  /// Peak white at the very top, ramped to fully transparent at the bottom.
  /// Kept low: this app's content is white cards on #F7F8FA, so the blurred
  /// backdrop is already nearly white and a heavy tint just repaints the bar
  /// solid white — the effect runs, it simply has nothing left to show. Most of
  /// the visible contrast has to come from the content itself; the tint only
  /// carries enough white to keep the dark title legible over it.
  final double tintOpacity;

  const FrostedHeaderBackground({super.key, this.tintOpacity = 0.62});

  /// Stacked top-anchored blur bands, each covering a *fraction* of the bar's
  /// height. Each one filters what the previous ones have already blurred, so
  /// the blur accumulates toward the top (roughly the root-sum-square of the
  /// sigmas covering a given row) and thins out to the single gentlest band at
  /// the bottom edge. Their fractions are spaced unevenly so the steps between
  /// them stay below what the eye picks up as banding.
  static const _bands = <({double fraction, double sigma})>[
    (fraction: 1.00, sigma: 3.0),
    (fraction: 0.88, sigma: 4.5),
    (fraction: 0.72, sigma: 6.0),
    (fraction: 0.52, sigma: 8.0),
    (fraction: 0.30, sigma: 11.0),
  ];

  /// Boosting saturation the way Apple's own materials do. On near-neutral
  /// content it does nothing; where a colored chip or source dot passes under
  /// the bar, it's what lets the color bleed through instead of washing out to
  /// the same gray as everything else. Applied once, on the full-height band —
  /// composing it onto every band would compound it five times over.
  static const _saturate = <double>[
    1.4722, -0.4290, -0.0432, 0, 0, //
    -0.1278, 1.1710, -0.0432, 0, 0, //
    -0.1278, -0.4290, 1.5568, 0, 0, //
    0, 0, 0, 1, 0, //
  ];

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (final (i, band) in _bands.indexed)
            FractionallySizedBox(
              alignment: Alignment.topCenter,
              heightFactor: band.fraction,
              // Each band needs its own ClipRect: a BackdropFilter's effect
              // otherwise reaches the whole enclosing layer, not just the box
              // it was laid out in, and every band would blur the entire bar.
              child: ClipRect(
                child: BackdropFilter(
                  filter: i == 0
                      ? ImageFilter.compose(
                          outer: const ColorFilter.matrix(_saturate),
                          inner: ImageFilter.blur(sigmaX: band.sigma, sigmaY: band.sigma),
                        )
                      : ImageFilter.blur(sigmaX: band.sigma, sigmaY: band.sigma),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.frost.withValues(alpha: tintOpacity),
                  AppColors.frost.withValues(alpha: tintOpacity * 0.82),
                  AppColors.frost.withValues(alpha: 0),
                ],
                // Held near full for most of the bar — the title needs it — then
                // dropped over the last third, where there's nothing on top of
                // the material that has to stay legible.
                stops: const [0, 0.62, 1],
              ),
            ),
            child: const SizedBox.expand(),
          ),
        ],
      ),
    );
  }
}

/// A tappable [GlassSurface]: the press feedback every glass control shares.
/// The scale-down exists because the real material is a native platform view —
/// a Flutter ink splash or highlight overlay would be composited *behind* it
/// and never seen, so the whole control moves instead.
class _PressableGlass extends StatefulWidget {
  final VoidCallback onTap;
  final BorderRadius borderRadius;
  final Color? tint;
  final Color? fallbackTint;
  final List<BoxShadow>? boxShadow;
  final Widget child;

  const _PressableGlass({
    required this.onTap,
    required this.borderRadius,
    required this.child,
    this.tint,
    this.fallbackTint,
    this.boxShadow,
  });

  @override
  State<_PressableGlass> createState() => _PressableGlassState();
}

class _PressableGlassState extends State<_PressableGlass> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? 0.90 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: GlassSurface(
          borderRadius: widget.borderRadius,
          tint: widget.tint,
          fallbackTint: widget.fallbackTint,
          blurSigma: 16,
          boxShadow: widget.boxShadow ?? AppShadows.glassButton,
          child: widget.child,
        ),
      ),
    );
  }
}

/// A circular glass button, e.g. the floating "+" on every screen header, the
/// X / check controls on a sheet, or the trash beside a [GlassAccentButton].
class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final double iconSize;

  /// Null falls back to [AppColors.ink] — it can't be a const default, since
  /// the token is a getter over the installed palette. Pass [AppColors.danger]
  /// for a destructive action (the trash button).
  final Color? iconColor;

  /// Null (the default) means no forced tint — plain icon buttons (X, +, trash)
  /// get the real glass's natural adaptive look. For a tinted accent button use
  /// [GlassConfirmButton] rather than passing a colour here, so the accent
  /// treatment stays in one place.
  final Color? tint;

  /// Tint for the Flutter-drawn approximation only — see [GlassSurface.fallbackTint].
  final Color? fallbackTint;

  /// Overrides the default subtle lift, e.g. the accent-tinted glow under
  /// [GlassConfirmButton].
  final List<BoxShadow>? boxShadow;

  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 40,
    this.iconSize = 19,
    this.iconColor,
    this.tint,
    this.fallbackTint,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    return _PressableGlass(
      onTap: onTap,
      borderRadius: BorderRadius.circular(size / 2),
      tint: tint,
      fallbackTint: fallbackTint,
      boxShadow: boxShadow,
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(icon, size: iconSize, color: iconColor ?? AppColors.ink),
      ),
    );
  }
}

/// ## The accent-filled glass rule
///
/// Both accent controls — [GlassConfirmButton] (the check in a sheet header)
/// and [GlassAccentButton] (the labelled pill: "Bearbeiten", "Termin
/// hinzufügen", …) — tint the glass with the **opaque** accent, never a
/// translucent one, and both live here so that stays true of all of them at
/// once.
///
/// A translucent accent is what both of them used to be, and it was wrong the
/// same way in both places: on iOS the colour is handed to `UIGlassEffect`'s
/// `tintColor`, which composites over whatever is behind the control, and the
/// glass then thins it further. Accent-at-55% over a white sheet header came
/// out a pale milky blue; accent-at-78% over a dark sheet came out a dull
/// periwinkle. Both read as *disabled*, because a washed-out fill is exactly
/// how a disabled control is drawn. Opaque keeps the blue at full chroma, and
/// the material still contributes its own specular highlight and edge lensing
/// over the top — so it stays glass, it just stops looking switched off. The
/// accent-tinted glow underneath ([AppShadows.accentGlass]) does the job the
/// old translucency was there for: separating the control from its background.
///
/// These are the two places [GlassSurface]'s "prefer a null tint" rule is
/// deliberately broken — they *are* the intentional accent that doc calls out.
class GlassConfirmButton extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  final double size;

  const GlassConfirmButton({super.key, required this.onTap, this.icon = LucideIcons.check, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GlassIconButton(
      icon: icon,
      onTap: onTap,
      size: size,
      tint: accent,
      fallbackTint: accent,
      iconColor: Colors.white,
      boxShadow: AppShadows.accentGlass(accent),
    );
  }
}

/// The labelled accent pill — the primary action of a sheet or an empty state
/// ("Bearbeiten", "Termin hinzufügen", "Aufgabe hinzufügen"). Same opaque-accent
/// rule as [GlassConfirmButton]; see the note above it.
///
/// Real glass, not a coloured `Container`: Board and Kalender each had their own
/// private copy that only *approximated* one (a translucent fill plus a white
/// hairline border), so the pill never refracted what it sat on the way the
/// icon buttons beside it did.
class GlassAccentButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  /// Optional glyph before the label — the Settings actions ("Mitglied
  /// einladen", "Verbinden") carry one; the empty-state pills don't.
  final IconData? icon;

  /// Stretches to the width it's given — for a pill sharing a row with a trash
  /// button, wrapped in an `Expanded`. Left false it hugs its label.
  final bool expand;

  final double fontSize;
  final EdgeInsetsGeometry padding;

  const GlassAccentButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.expand = false,
    this.fontSize = 15,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return _PressableGlass(
      onTap: onTap,
      // A capsule regardless of height: it's what iOS renders anyway (the
      // native effect view sets `cornerConfiguration = .capsule()`), so a
      // smaller radius would only disagree with the material's own edge
      // lensing on device.
      borderRadius: BorderRadius.circular(999),
      tint: accent,
      fallbackTint: accent,
      boxShadow: AppShadows.accentGlass(accent),
      child: Padding(
        padding: padding,
        child: SizedBox(
          width: expand ? double.infinity : null,
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon case final glyph?) ...[
                Icon(glyph, size: fontSize + 3, color: Colors.white),
                const SizedBox(width: 9),
              ],
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.rowTitle.copyWith(fontSize: fontSize, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
