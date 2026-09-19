import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import 'native_glass_buttons.dart';
import 'native_glass_view.dart';
import 'native_occlusion.dart';
import '../theme/app_icons.dart';

/// Whether a glass surface built in [context] will be the **real** native
/// `UIGlassEffect` rather than the Flutter-drawn approximation.
///
/// Public because the press depends on the answer: the material's own
/// [NativeGlassView] response belongs to UIKit, while the approximation is a
/// Flutter drawing whose caller has to detect the tap itself. Both sides ask
/// here so they can never disagree about which of the two is on screen.
bool nativeGlassActive(BuildContext context, {bool forceApproximation = false}) {
  if (forceApproximation || kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return false;
  // A glass control on the screen *behind* an open sheet would paint over it —
  // see [occludedByRoute]. The approximation is already the non-iOS look, so a
  // covered control simply wears it until the sheet closes.
  return !occludedByRoute(context);
}

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
  /// appearance applies. The Flutter-drawn approximation always needs a
  /// concrete color, so it substitutes [fallbackTint], or
  /// [AppColors.glassFallbackTint] if that's null too.
  ///
  /// Prefer null here: a forced tint is passed straight to `UIGlassEffect`'s
  /// `tintColor`. Only pass a colour for a deliberate accent — and for the
  /// blue confirm button that means [GlassConfirmButton], which owns that one
  /// treatment (and explains there why its accent is opaque).
  final Color? tint;

  /// Tint for the Flutter-drawn approximation only, ignored on iOS. Lets a
  /// control keep the real glass's adaptive appearance on iOS (`tint: null`)
  /// while drawing a *different* material everywhere else.
  ///
  /// **Almost nothing needs this.** The default, [AppColors.glassFallbackTint],
  /// is the light material every control here wants, and the approximation is
  /// not only the Android look: on iOS it is what a control wears for as long
  /// as a sheet or a full screen covers it (see [occludedByRoute]), so whatever
  /// this resolves to is a face the button shows on device, several times a
  /// session.
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

  /// The surface's tappable segments, as fractions of its own box — see
  /// [NativeGlassView.regions]. Empty means decoration, which takes no
  /// touches. Only ever reaches the real material; the approximation is a
  /// Flutter drawing and its caller keeps its own `GestureDetector`.
  final List<GlassTouchRegion> regions;

  /// A completed tap on segment `index` of [regions].
  final void Function(int index)? onTap;

  /// Touch-down / touch-up on segment `index` of [regions].
  final void Function(int index, bool pressed)? onPressed;

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
    this.regions = const <GlassTouchRegion>[],
    this.onTap,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final useNativeGlass = nativeGlassActive(context, forceApproximation: forceFlutterApproximation);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        // **Nothing may be painted underneath real glass**, and a drop shadow
        // is the easiest thing to forget that about. Flutter paints this into
        // the surface *below* the platform view, which is precisely what
        // `UIGlassEffect` samples and refracts — so a 35%-black blur sized to
        // sit behind the control gets pulled up through the material and
        // smeared across its rim, and the rest of it hangs outside the capsule
        // as a grey halo. That is what made the header buttons read as a
        // painted approximation rather than glass. The material carries its own
        // shadow; ours is for the Flutter drawing, which has none.
        boxShadow: useNativeGlass ? null : boxShadow,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          children: [
            Positioned.fill(
              child: useNativeGlass
                  ? NativeGlassView(
                      tint: tint,
                      interactive: interactive,
                      regions: regions,
                      onTap: onTap,
                      onPressed: onPressed,
                    )
                  : _FlutterGlassApproximation(
                      tint: tint ?? fallbackTint ?? AppColors.glassFallbackTint,
                      blurSigma: blurSigma,
                      borderRadius: borderRadius,
                      accent: tint != null,
                    ),
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

  /// The surface's own shape. The rim **has to** follow it: a `Border.all` on a
  /// `BoxDecoration` with no `borderRadius` is a *rectangle*, and the enclosing
  /// `ClipRRect` then throws away everything but the four points where that
  /// rectangle touches the curve — a bright fleck at each side of a circular
  /// button, and on a capsule the whole flat top and bottom with nothing
  /// joining them. Which is what made a covered control look like it had gone
  /// square at the left and right edges.
  final BorderRadius borderRadius;

  /// Whether [tint] is a deliberate accent ([GlassSurface.tint]) rather than
  /// the neutral material.
  ///
  /// The white lift, the specular and the rim are all sized for a near-opaque
  /// tone of the *surface*, where they read as curvature. Over an opaque accent
  /// they read as a wash: 30% white across the top of a blue pill under a 45%
  /// white highlight is the pale, milky blue the accent-filled glass rule
  /// above [GlassConfirmButton] exists to keep off the screen, because a
  /// washed-out fill is how a disabled control is drawn. The real
  /// `UIGlassEffect` holds an opaque `tintColor` at full chroma and adds only a
  /// faint sheen over it, so on an accent this does the same — otherwise every
  /// blue button in the app turned pale for as long as a sheet was open over
  /// it.
  final bool accent;

  const _FlutterGlassApproximation({
    required this.tint,
    required this.blurSigma,
    required this.borderRadius,
    required this.accent,
  });

  /// How far the top of the fill is lifted toward white. Dark already sits on
  /// a dark backdrop, so a 30% lift there turns the panel into a grey slab;
  /// an accent has even less room, being a colour rather than a neutral.
  double get _lift => accent ? 0.06 : (AppColors.isDark ? 0.10 : 0.3);

  /// The specular and the rim, dimmed to a sheen on an accent.
  Color _sheen(Color color, {required double factor}) => accent ? color.withValues(alpha: color.a * factor) : color;

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
              borderRadius: borderRadius,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                // Lightening toward the top is what sells the curvature —
                // see [_lift] for why an accent and a dark palette each get
                // far less of it than a light neutral does.
                colors: [Color.lerp(tint, Colors.white, _lift)!, tint],
              ),
              border: Border.all(color: _sheen(AppColors.glassRim, factor: 0.4), width: 1),
            ),
          ),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.6, -0.8),
                  radius: 1.2,
                  colors: [_sheen(AppColors.glassSpecular, factor: 0.3), AppColors.glassSpecular.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Loads the variable-blur kernel behind [FrostedHeaderBackground], once,
/// before the first frame.
///
/// The widget is built during layout on every screen in the app and cannot
/// await anything, so the program is fetched in `main` and read from here
/// synchronously afterwards. A null program — the shader failed to compile, or
/// this device is not on Impeller — is not an error: the bar falls back to the
/// banded approximation below.
FragmentProgram? _blurProgram;

Future<void> loadFrostedHeaderShader() async {
  if (!ImageFilter.isShaderFilterSupported) return;
  try {
    _blurProgram = await FragmentProgram.fromAsset('shaders/progressive_blur.frag');
  } catch (error, stack) {
    _blurProgram = null;
    FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack, library: 'aporah'));
  }
}

/// The material behind a collapsing header: a *variable* blur under a
/// translucent wash, both ramping to nothing at the bottom edge — the treatment
/// Apple's own `.soft` scroll-edge effect uses under a nav bar, rather than a
/// uniform frosted panel.
///
/// It exists because `NestedScrollView` does *not* clip its body to below a
/// pinned header: the scrolled content keeps sliding up until its top reaches
/// the top of the screen, so without a background of its own a header has the
/// agenda/sheet content rendering straight through the title and buttons. A
/// solid fill would hide that content outright; this washes it out instead, so
/// you can still see it passing underneath.
///
/// **The ramp has to be continuous, and that is what the shader buys.** This
/// shipped first as five stacked `BackdropFilter`s in hard `ClipRect`s, with
/// rising sigmas — and every one of those clips was an edge:
///
/// * blur **stepped** at each boundary, and the eye reads a step in blur as a
///   horizontal line drawn across the screen;
/// * the bottom-most band was still at sigma 3 when it simply stopped, so the
///   bar's own bottom edge was the sharpest line of the lot;
/// * a band's kernel was wider than the band was tall (sigma 11 inside a ~29pt
///   box), so it ran out of pixels to sample and **edge-clamped** — rows
///   stretched rather than blurred, which is the frozen, smeared look;
/// * and because each band filtered the output of the ones below it, the sigmas
///   compounded to √(3²+4.5²+6²+8²+11²) ≈ **15.8** where 11 was intended. The
///   bar was half again as strong as anybody had asked for.
///
/// A blur whose radius is a smooth function of y has no boundary to show,
/// nothing to clamp against, and applies exactly the sigma it is handed. It is
/// one `FragmentShader` run twice — vertically, then horizontally over that
/// result — because a separable pair of 17-tap passes is the same Gaussian as
/// one 289-tap kernel for a thirtieth of the work.
///
/// Deliberately *not* a [GlassSurface]: liquid glass has a specular highlight
/// and refracts at its edges, which reads as a floating control. A header is an
/// edge-to-edge bar, and a bar wants a plain material.
class FrostedHeaderBackground extends StatefulWidget {
  /// Peak white at the very top, eased to fully transparent at the bottom.
  /// Kept low: this app's content is white cards on #F7F8FA, so the blurred
  /// backdrop is already nearly white and a heavy tint just repaints the bar
  /// solid white — the effect runs, it simply has nothing left to show. Most of
  /// the visible contrast has to come from the content itself; the tint only
  /// carries enough white to keep the dark title legible over it.
  ///
  /// **It is also what the header's glass buttons have to refract, which is why
  /// it came down from 0.62.** A [GlassIconGroup] or [GlassIconButton] on the
  /// title row is real `UIGlassEffect` sitting on this bar, and glass shows you
  /// whatever is behind it: behind a near-opaque tint there is nothing left to
  /// lens, so the control rendered as a flat grey pill with a hard rim — the
  /// look of a painted approximation, not of the material. Apple's own
  /// scroll-edge effect is mostly *blur* with a very light tint for the same
  /// reason. Raise it if a title ever loses its footing over scrolled content,
  /// lower it if the buttons go flat again.
  final double tintOpacity;

  /// Blur sigma in logical pixels at the very top of the bar, falling to zero
  /// at its bottom edge.
  ///
  /// Lower than it looks next to the old stack's nominal 11 because that stack
  /// *compounded* to nearly 16 — this is the number that actually reaches the
  /// glass. It is the knob for "too strong / not enough": the ramp's shape
  /// lives in the shader and should stay there.
  final double peakSigma;

  /// **Deliberately not `const`, and the lint below is suppressed on purpose.**
  ///
  /// This widget reads [AppColors.frost] inside its own `build`, which makes it
  /// exactly the case the rule on [AppColors] warns about: a canonicalised
  /// `const` instance is skipped when its parent rebuilds, so the bar keeps the
  /// palette it was first built with and stays dark in a light app (or light in
  /// a dark one) until a hot reload rebuilds the world. That regressed once from
  /// a `const` slipping back into the header, which is a bug no reviewer spots
  /// and no test catches — every screen in the app has one of these bars, and
  /// the wrong one only shows up after a live theme flip.
  ///
  /// A non-const constructor turns that into a compile error at the call site,
  /// the same trade `AppStrings` makes for a missing translation.
  // ignore: prefer_const_constructors_in_immutables
  FrostedHeaderBackground({super.key, this.tintOpacity = 0.46, this.peakSigma = 12});

  /// How much colour survives at the top of the bar, where the blur is at full
  /// strength. Applied once, by the horizontal pass, and ramped down with the
  /// blur so it dies at the same edge.
  static const _peakSaturation = 1.45;

  @override
  State<FrostedHeaderBackground> createState() => _FrostedHeaderBackgroundState();
}

class _FrostedHeaderBackgroundState extends State<FrostedHeaderBackground> {
  /// One shader object per pass. They cannot be the same instance: an
  /// [ImageFilter.shader] holds on to the shader rather than to a copy of its
  /// uniforms, so a shared one would run both passes in whichever direction was
  /// written last.
  FragmentShader? _vertical;
  FragmentShader? _horizontal;

  @override
  void initState() {
    super.initState();
    final program = _blurProgram;
    if (program == null) return;
    _vertical = program.fragmentShader();
    _horizontal = program.fragmentShader();
  }

  @override
  void dispose() {
    _vertical?.dispose();
    _horizontal?.dispose();
    super.dispose();
  }

  /// Uniform indices follow the declaration order in the .frag, counting two
  /// floats per `vec2` and skipping samplers. 0–1 are `uTextureSize`, which the
  /// engine fills in.
  void _configure(
    FragmentShader shader, {
    required double heightPx,
    required double sigmaPx,
    required bool horizontal,
  }) {
    shader
      ..setFloat(2, heightPx)
      ..setFloat(3, sigmaPx)
      ..setFloat(4, horizontal ? 1 : 0)
      ..setFloat(5, horizontal ? 0 : 1)
      ..setFloat(6, horizontal ? FrostedHeaderBackground._peakSaturation : 1);
  }

  /// The wash over the blur.
  ///
  /// Five stops rather than three, following the same ease the shader ramps the
  /// blur on. A straight linear fade to zero ends in a corner — the alpha stops
  /// changing all at once — and that corner is visible as a faint band even
  /// though nothing is drawn there. Held near full under the title, then eased
  /// away over the lower half where there is nothing on top of the material
  /// that has to stay legible.
  Widget _wash() {
    final frost = AppColors.frost;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            frost.withValues(alpha: widget.tintOpacity),
            frost.withValues(alpha: widget.tintOpacity * 0.97),
            frost.withValues(alpha: widget.tintOpacity * 0.78),
            frost.withValues(alpha: widget.tintOpacity * 0.34),
            frost.withValues(alpha: widget.tintOpacity * 0.08),
            frost.withValues(alpha: 0),
          ],
          stops: const [0, 0.30, 0.55, 0.78, 0.92, 1],
        ),
      ),
      child: const SizedBox.expand(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vertical = _vertical;
    final horizontal = _horizontal;
    if (vertical == null || horizontal == null) return _BandedFrost(wash: _wash());

    final dpr = MediaQuery.devicePixelRatioOf(context);
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The shader measures its ramp against the bar's own height, not the
          // backdrop texture's — the engine is free to hand us a snapshot
          // larger than the box we are drawn into, and a collapsing header's
          // height changes on every frame of a scroll besides.
          final heightPx = constraints.maxHeight * dpr;
          final sigmaPx = widget.peakSigma * dpr;
          _configure(vertical, heightPx: heightPx, sigmaPx: sigmaPx, horizontal: false);
          _configure(horizontal, heightPx: heightPx, sigmaPx: sigmaPx, horizontal: true);
          return Stack(
            fit: StackFit.expand,
            children: [
              // Vertical first, horizontal painted over it: a `BackdropFilter`
              // samples whatever has already been written into the layer, so
              // the second pass filters the output of the first. That is what
              // makes the pair one separable 2-D blur instead of two
              // independent 1-D ones — and it is the *only* place in this
              // widget where stacking filters is wanted.
              BackdropFilter(filter: ImageFilter.shader(vertical), child: const SizedBox.expand()),
              BackdropFilter(filter: ImageFilter.shader(horizontal), child: const SizedBox.expand()),
              _wash(),
            ],
          );
        },
      ),
    );
  }
}

/// The pre-Impeller fallback: the stepped approximation, kept only for backends
/// where [ImageFilter.shader] does not exist (Skia, and the web).
///
/// Its seams are the ones described on [FrostedHeaderBackground] and they are
/// not fixable from here — a hard-clipped band *is* an edge. Don't tune it in
/// the hope of closing them, and don't copy it into anything new.
class _BandedFrost extends StatelessWidget {
  final Widget wash;

  const _BandedFrost({required this.wash});

  static const _bands = <({double fraction, double sigma})>[
    (fraction: 1.00, sigma: 2.0),
    (fraction: 0.88, sigma: 3.0),
    (fraction: 0.72, sigma: 4.0),
    (fraction: 0.52, sigma: 5.0),
    (fraction: 0.30, sigma: 6.5),
  ];

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
          wash,
        ],
      ),
    );
  }
}

/// A tappable [GlassSurface]: the press feedback every glass control shares.
///
/// **Which of the two materials is on screen decides who handles the press.**
/// Real `UIGlassEffect` has a response of its own — `isInteractive`, the
/// lensing that gathers under a finger — and it only runs for touches UIKit
/// delivers into the effect view, so on the native path the tap is a
/// [GlassSurface.regions] target and there is no `GestureDetector` here at all.
/// The Flutter-drawn approximation has no such response, so it keeps the
/// scale-down: an ink splash or highlight overlay would be composited *behind*
/// the surface and never seen, so the whole control moves instead.
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
    final native = nativeGlassActive(context);
    final surface = GlassSurface(
      borderRadius: widget.borderRadius,
      tint: widget.tint,
      fallbackTint: widget.fallbackTint,
      blurSigma: 16,
      boxShadow: widget.boxShadow ?? AppShadows.glassButton,
      regions: native ? oneGlassTouchRegion : const <GlassTouchRegion>[],
      onTap: native ? (_) => widget.onTap() : null,
      child: widget.child,
    );
    // The whole control is one target, so UIKit's press *is* the feedback.
    // Wrapping it in a Semantics node keeps VoiceOver a way in: the platform
    // view publishes no Flutter semantics of its own.
    if (native) return Semantics(button: true, child: surface);
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? 0.90 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: surface,
      ),
    );
  }
}

/// A circular glass button, e.g. the floating "+" on every screen header, the
/// X / check controls on a sheet, or the trash beside a [GlassAccentButton].
///
/// **On iOS this is a real `UIButton` wearing `.glass()`** — see
/// [NativeGlassButtons] for why the system's own control beats the material
/// with a glyph laid over it. The [GlassSurface] below is what it falls back
/// to: everywhere else, and on iOS for as long as a sheet covers the screen.
class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final double iconSize;

  /// Never drawn — the button's accessible name, which an icon hasn't got.
  /// UIKit publishes it on the native path; the Flutter fallback wraps itself
  /// in a `Semantics` node for it.
  final String? label;

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
    this.iconSize = AppGlyph.button,
    this.iconColor,
    this.tint,
    this.fallbackTint,
    this.boxShadow,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    if (nativeGlassActive(context)) {
      return SizedBox(
        width: size,
        height: size,
        child: NativeGlassButtons(
          buttons: [NativeGlassButton(icon: icon, label: label ?? '', onTap: onTap)],
          // A forced [tint] is only ever the deliberate accent — see the
          // accent-filled glass rule below — and the accent is what
          // `.prominentGlass()` is. Without one this is an ordinary glass
          // button and the colour goes to the glyph instead, which is how the
          // trash button stays red.
          prominent: tint != null,
          tint: tint ?? iconColor ?? AppColors.ink,
          iconSize: iconSize,
        ),
      );
    }
    return Semantics(
      label: label,
      child: _PressableGlass(
        onTap: onTap,
        borderRadius: BorderRadius.circular(size / 2),
        tint: tint,
        fallbackTint: fallbackTint,
        boxShadow: boxShadow,
        child: SizedBox(
          width: size,
          height: size,
          // Flat: the glyph on a glass button is the control, not a label for
          // one. See [AppIcon.flat].
          child: AppIcon(icon, size: iconSize, color: iconColor ?? AppColors.ink, flat: true),
        ),
      ),
    );
  }
}

/// Two or more icon buttons sharing **one** glass capsule — iOS 26's grouped
/// bar buttons. Kalender's header uses it for "verbinden" and "neuer Termin".
///
/// One capsule rather than two [GlassIconButton]s side by side, because two
/// pieces of real glass touching read as a mistake: each refracts its own
/// little rim and the pair looks like one button that failed to draw. The
/// group is also how iOS says these belong together — same row, same subject,
/// different verbs.
///
/// **No separator between the segments.** One was tried and it read as a
/// button that had cracked down the middle rather than as a group: on the real
/// material the glass carries no line of its own, so a hairline is the only
/// hard edge inside the capsule and the eye lands on it. Apple's own grouped
/// items have none either. Spacing is what says "two things" — hence the
/// [_hPad] at the ends, without which the outer icons sit against the capsule's
/// curve and the whole thing looks cramped.
///
/// Only the pressed segment reacts, and it is the *icon* that scales, not the
/// capsule: on iOS the capsule is a `UIGlassEffect` platform view, and
/// scaling one of those smears (see [GlassSurface.forceFlutterApproximation]).
class GlassIconGroup extends StatefulWidget {
  final List<GlassIconAction> actions;

  /// The capsule's height. Matches [GlassIconButton] so a header that mixes
  /// the two sits on one line.
  final double size;
  final double iconSize;

  const GlassIconGroup({super.key, required this.actions, this.size = 40, this.iconSize = AppGlyph.button});

  /// Each segment's tap target, wider than the capsule is tall: the icons are
  /// a finger's width apart in a control that is only 40pt high, and at the
  /// segment's own height the two are easy to mis-hit. 44 is Apple's floor.
  static const _segmentWidth = 44.0;

  /// Breathing room at each end of the capsule, so the outer icons aren't
  /// pressed against its round caps.
  static const _hPad = 6.0;

  /// What the group measures, for a header that has to reserve room for it.
  double get width => actions.length * _segmentWidth + 2 * _hPad;

  /// Each segment as a fraction of the capsule, for the real material's own
  /// touch handling ([GlassSurface.regions]). Derived from the same three
  /// numbers the `Row` is laid out from, so the target and the glyph under a
  /// finger can't drift apart.
  List<GlassTouchRegion> get _regions {
    final total = width;
    return [
      for (var i = 0; i < actions.length; i++)
        Rect.fromLTWH((_hPad + i * _segmentWidth) / total, 0, _segmentWidth / total, 1),
    ];
  }

  @override
  State<GlassIconGroup> createState() => _GlassIconGroupState();
}

/// One segment of a [GlassIconGroup]. [label] is never drawn — it is the
/// segment's accessible name, which an icon on its own hasn't got.
class GlassIconAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const GlassIconAction({required this.icon, required this.label, required this.onTap});
}

class _GlassIconGroupState extends State<GlassIconGroup> {
  int? _pressed;

  void _setPressed(int? index) {
    if (_pressed != index) setState(() => _pressed = index);
  }

  @override
  Widget build(BuildContext context) {
    final native = nativeGlassActive(context);
    if (native) {
      // **One capsule, several real buttons.** The native side hangs them in a
      // `UIGlassContainerEffect`, which is the documented way to make adjacent
      // glass merge into a single shape rather than sit beside each other as
      // separate pieces — exactly what this widget's doc above says a group
      // has to look like, now done by the system instead of by us drawing one
      // wide piece of material and putting two glyphs on it.
      return SizedBox(
        width: widget.width,
        height: widget.size,
        child: NativeGlassButtons(
          buttons: [
            for (final action in widget.actions)
              NativeGlassButton(icon: action.icon, label: action.label, onTap: action.onTap),
          ],
          tint: AppColors.ink,
          iconSize: widget.iconSize,
        ),
      );
    }
    return GlassSurface(
      borderRadius: BorderRadius.circular(widget.size / 2),
      // Same material arguments as the "Heute" pill, which is the shape this
      // is meant to match: no forced `tint`, so iOS's real `UIGlassEffect`
      // adapts and the Flutter drawing takes the default light material.
      blurSigma: 20,
      // Not `glassButton`: that lift is sized for a 40pt circle and reads as a
      // dark smudge under something this wide. See [AppShadows.floatingPill].
      // Dropped entirely under real glass — see [GlassSurface.build].
      boxShadow: AppShadows.floatingPill,
      regions: native ? widget._regions : const <GlassTouchRegion>[],
      onTap: native ? (i) => widget.actions[i].onTap() : null,
      onPressed: native ? (i, pressed) => _setPressed(pressed ? i : null) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: GlassIconGroup._hPad),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < widget.actions.length; i++)
              Semantics(
                button: true,
                label: widget.actions[i].label,
                onTap: native ? widget.actions[i].onTap : null,
                child: _segment(
                  i,
                  native: native,
                  child: SizedBox(
                    width: GlassIconGroup._segmentWidth,
                    height: widget.size,
                    child: AnimatedScale(
                      scale: _pressed == i ? 0.82 : 1.0,
                      duration: const Duration(milliseconds: 120),
                      curve: Curves.easeOut,
                      child: AppIcon(widget.actions[i].icon, size: widget.iconSize, color: AppColors.ink, flat: true),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The glyph, wrapped in its own gesture detector only where Flutter is the
  /// one detecting gestures. Under real glass a `GestureDetector` here would
  /// sit in the platform view's overlay layer and take nothing anyway — the
  /// touch has already been claimed by UIKit.
  Widget _segment(int index, {required bool native, required Widget child}) {
    if (native) return child;
    return GestureDetector(
      onTap: widget.actions[index].onTap,
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(index),
      onTapUp: (_) => _setPressed(null),
      onTapCancel: () => _setPressed(null),
      child: child,
    );
  }
}

/// The **neutral** labelled glass pill: a way *out* rather than the action —
/// Settings' "Fertig", the onboarding header's "Überspringen". A text-labelled
/// sibling of [GlassIconButton], so a header that mixes the two reads as one
/// material. For the accent-filled one use [GlassAccentButton].
///
/// Ellipsises rather than overflowing: it sits in headers that share their row
/// with other controls, and "Überspringen" is a long word on a small phone.
class GlassPillButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  /// Optional glyph before the label — "Kalenderdatei hochladen" carries the
  /// upload arrow, the header pills don't.
  final IconData? icon;

  /// Stretches to the width it's given, like [GlassAccentButton.expand] — for a
  /// pill stacked under an accent one, so the two read as one pair.
  final bool expand;

  /// The padding that, with the label inside it, *is* this pill's size — on
  /// both paths. The native button is handed the box this produces rather than
  /// measuring the word itself; see [NativeGlassButtons.sizer]. Pass
  /// [GlassAccentButton]'s own to match its height beside it.
  final EdgeInsetsGeometry padding;

  const GlassPillButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.expand = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
  });

  Widget get _body => Padding(
    padding: padding,
    child: SizedBox(width: expand ? double.infinity : null, child: _label),
  );

  Widget get _label {
    final text = Text(
      label,
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppText.rowTitle,
    );
    final glyph = icon;
    if (glyph == null) return text;
    return Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AppIcon(glyph, size: AppText.rowTitle.fontSize! * 1.4, color: AppColors.ink, flat: true),
        const SizedBox(width: 9),
        Flexible(child: text),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (nativeGlassActive(context)) {
      return NativeGlassButtons(
        buttons: [
          NativeGlassButton(icon: icon, label: label, title: label, titleStyle: AppText.rowTitle, onTap: onTap),
        ],
        tint: AppColors.ink,
        iconSize: AppText.rowTitle.fontSize! * 1.4,
        sizer: _body,
      );
    }
    return _PressableGlass(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.bar),
      child: _body,
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

  /// False while the sheet has nothing worth saving — a create form whose name
  /// is still empty. The button keeps its place and its shape and loses the
  /// accent, so it reads as "not yet" rather than disappearing; the tap is
  /// swallowed, because a confirm that closes the sheet and creates nothing is
  /// the worst of the three outcomes.
  final bool enabled;

  /// What a tap on the *disabled* button does instead of nothing.
  ///
  /// Swallowing it outright is what the [enabled] note above describes, and it
  /// is right about the save: a confirm that closes the sheet and creates
  /// nothing is the worst outcome. But a tap that produces no reaction at all
  /// is indistinguishable from a save that worked — people tap the check, the
  /// sheet looks the same, and they leave believing they filed something. So
  /// the tap is still not a save; it is an answer to "why not", and the sheet
  /// hands over one that points at the empty field.
  final VoidCallback? onDisabledTap;

  const GlassConfirmButton({
    super.key,
    required this.onTap,
    this.icon = AppIcons.check,
    this.size = 40,
    this.enabled = true,
    this.onDisabledTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final tint = enabled ? accent : AppColors.mutedLight;
    return GlassIconButton(
      icon: icon,
      onTap: enabled ? onTap : (onDisabledTap ?? () {}),
      size: size,
      tint: tint,
      fallbackTint: tint,
      iconColor: Colors.white,
      boxShadow: enabled ? AppShadows.accentGlass(accent) : null,
    );
  }
}

/// The labelled accent pill — the primary action of a sheet or an empty state
/// ("Bearbeiten", "Termin hinzufügen", "To-do hinzufügen"). Same opaque-accent
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

  /// False while the action cannot be taken yet — a save already in flight, an
  /// enrolment waiting on the server. Same bargain as [GlassConfirmButton]'s
  /// own [GlassConfirmButton.enabled]: the pill keeps its place and its shape,
  /// loses the accent and the glow, and swallows the tap, so it reads as "not
  /// yet" rather than vanishing mid-gesture.
  final bool enabled;

  const GlassAccentButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.expand = false,
    this.fontSize = 15,
    this.enabled = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
  });

  @override
  Widget build(BuildContext context) {
    final accent = enabled ? Theme.of(context).colorScheme.primary : AppColors.mutedLight;
    final titleStyle = AppText.rowTitle.copyWith(fontSize: fontSize, color: Colors.white);
    // Both paths are laid out from this one widget: the Flutter drawing *is*
    // it, and the native button is handed it as a [NativeGlassButtons.sizer] so
    // the two pills are the same size by construction. See [GlassPillButton],
    // which is the same bargain for the neutral one.
    final body = Padding(
      padding: padding,
      child: SizedBox(
        width: expand ? double.infinity : null,
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon case final glyph?) ...[
              // Tied to the word beside it rather than pinned, since
              // [fontSize] is a parameter — at its default this is exactly
              // [AppGlyph.row], the tier for a glyph sharing its space.
              AppIcon(glyph, size: fontSize * 1.4, color: Colors.white, flat: true),
              const SizedBox(width: 9),
            ],
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              ),
            ),
          ],
        ),
      ),
    );

    if (nativeGlassActive(context)) {
      // **A real `UIButton`, for the same reason the icon buttons are one** —
      // and here for one more: the surface path hangs an invisible `UIControl`
      // inside an *interactive* `UIGlassEffect`'s `contentView`, and the
      // material's own touch handling competes with that control for the
      // gesture. It won often enough that the primary action of a Settings page
      // — "Verbinden" at the bottom of a provider — had to be tapped several
      // times before one got through. A glass `UIButton` has no such contest:
      // the press response and the action are the same control's.
      return NativeGlassButtons(
        buttons: [
          NativeGlassButton(
            icon: icon,
            label: label,
            title: label,
            titleStyle: titleStyle,
            // Still swallowed rather than absent while disabled — see [enabled].
            onTap: enabled ? onTap : () {},
          ),
        ],
        // Always the filled treatment: this pill is the accent even when it is
        // grey, which is what "not yet" looks like rather than "not a button".
        prominent: true,
        tint: accent,
        iconSize: fontSize * 1.4,
        sizer: body,
      );
    }

    return _PressableGlass(
      onTap: enabled ? onTap : () {},
      // A capsule regardless of height: it's what iOS renders anyway (the
      // native effect view sets `cornerConfiguration = .capsule()`), so a
      // smaller radius would only disagree with the material's own edge
      // lensing on device.
      borderRadius: BorderRadius.circular(999),
      tint: accent,
      fallbackTint: accent,
      boxShadow: enabled ? AppShadows.accentGlass(accent) : null,
      child: body,
    );
  }
}
