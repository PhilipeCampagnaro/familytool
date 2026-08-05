import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The round tile a Lucide glyph sits on — a small glass lens rather than the
/// flat gray disc every list row used to draw by hand.
///
/// ## Why this is drawn and not a [GlassSurface]
///
/// It looks like the app's glass material, but it deliberately shares none of
/// its machinery, for three reasons that all bite in a scrolling list:
///
/// - **A platform view per row is the wrong shape of thing.** `GlassSurface` on
///   iOS embeds a real `UIGlassEffect`, and a platform view composites *above*
///   everything Flutter paints — so a tile scrolling toward a collapsing header
///   would slide over the frosted bar instead of under it, and a Settings page
///   would carry eight of them at once.
/// - **There is nothing behind it to refract.** A settings row sits on a flat
///   white [SectionCard]. Real glass sampling a solid colour returns that solid
///   colour; every convincing cue here has to be *drawn* — the rim, the
///   specular arc, the thickness shading at the far edge.
/// - **No `BackdropFilter`, so no `saveLayer` per row.** The same reason: it
///   would cost a layer each and blur a flat white into flat white.
///
/// So the material is painted: a near-clear body, the glyph's own colour
/// bleeding into it, thickness shading at the far edge, a specular, and the
/// bevel just inside the rim — with the glyph *between* the passes (body and
/// specular underneath, rim on top), which is what makes the icon read as
/// sitting inside the lens rather than stamped on it.
///
/// Being drawn rather than embedded is also what makes it **identical on
/// Android**: no platform view, no `BackdropFilter`, nothing that resolves
/// differently per OS. One canvas, one result.
///
/// **Only the rim may paint over the glyph.** The specular started out over it
/// too, on the same "the glyph is under the glass" reasoning, and it cost the
/// icon its edges: aimed at the upper-left rim it still laid 42% white over the
/// glyph's upper-left and 21% over its centre, and a Lucide stroke is about
/// 1.5pt at this size, so it went visibly soft. The rim is the only part of the
/// treatment that never overlaps the glyph — it sits at `r`, the glyph reaches
/// `size * 0.25` — so it is the only part that can safely go last. A glyph you
/// have to squint at is a worse trade than a specular that stops at the icon.
///
/// [tone] defaults to the app accent. Pass a colour to tint a tile to the thing
/// it belongs to (a box's tone, a list's brand colour) when this rolls out
/// beyond Settings.
///
/// **Never `const`-construct this** — like every widget that reads a token in
/// `build`, a canonicalised instance would keep the palette it was born with.
class GlassIconTile extends StatelessWidget {
  final IconData icon;
  final double size;

  /// Defaults to a proportion of [size] — the 34/17 the settings rows shipped
  /// with, so a bigger tile doesn't need its glyph size worked out by hand.
  final double? iconSize;

  /// Null means the app accent.
  final Color? tone;

  const GlassIconTile({super.key, required this.icon, this.size = 34, this.iconSize, this.tone});

  @override
  Widget build(BuildContext context) {
    final color = tone ?? Theme.of(context).colorScheme.primary;
    final dark = AppColors.isDark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // The lift, and **neutral on light**. A tone-coloured shadow works on
        // dark, where it's really just black — on white it put a blue halo
        // around every tile, and a soft coloured glow around a soft coloured
        // fill is what made the first light version read as a plastic ball
        // instead of a lens. Tighter and fainter there too: on white the rim
        // does the separating, so the shadow only has to keep the tile off the
        // card.
        boxShadow: [
          BoxShadow(
            color: dark ? const Color(0x59000000) : shade(AppColors.ink, 0.055),
            blurRadius: size * (dark ? 0.20 : 0.12),
            offset: Offset(0, size * (dark ? 0.06 : 0.035)),
          ),
        ],
      ),
      child: CustomPaint(
        painter: _LensBody(tone: color, dark: dark),
        foregroundPainter: _LensRim(tone: color, dark: dark),
        child: Center(child: Icon(icon, size: iconSize ?? size * 0.5, color: color)),
      ),
    );
  }
}

/// Everything under the glyph: the tinted body of the lens, and the shading
/// where it thickens toward the far edge.
class _LensBody extends CustomPainter {
  final Color tone;
  final bool dark;

  const _LensBody({required this.tone, required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final centre = Offset(size.width / 2, size.height / 2);
    final bounds = Rect.fromCircle(center: centre, radius: r);

    // Pale on purpose. The obvious way to make a lens look like glass is a
    // deep tint with a white highlight over it, but at 34pt in a list of eight
    // that is a row of coloured buttons — and the accent glyph loses its
    // contrast against its own colour. The glass has to come from the edge
    // treatment below instead, which is also how a clear disc on a white table
    // actually looks: you see its rim, not its middle.
    canvas.drawCircle(
      centre,
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          // Light runs far flatter than dark. On dark the fill is the only
          // thing carrying the tone, so it can travel; on white, a fill that
          // ramps from near-white to a solid mid-blue is a shaded sphere, and
          // no amount of rim work reads as glass over the top of that.
          colors: dark
              ? [tint(tone, 0.74), tint(tone, 0.90)]
              : [tint(tone, 0.90), tint(tone, 0.83)],
        ).createShader(bounds),
    );

    // **The glyph's colour bleeding into the material around it.** Real glass
    // over a coloured thing picks that colour up and spreads it, and it is most
    // of what makes Apple's material look wet rather than frosted. Centred on
    // the glyph and short-range, so it reads as coming *from* the icon.
    //
    // On light it also does a structural job: it means the tone arrives from
    // the content instead of from the fill, which is why the fill can stay the
    // near-clear off-white that a bright bevel needs to show up against.
    //
    // It wants **less than it seems to**, and light needs about a third of what
    // dark does. On dark the bleed is a glow on a dark body and it can carry;
    // on light it lands on a body that is already tinted, so the two stack, and
    // at the 0.11 this first shipped with the blue pooled behind the glyph and
    // muddied it. Short range for the same reason — it should hug the icon, not
    // wash the middle of the tile.
    final bleed = shade(tone, dark ? 0.16 : 0.055);
    canvas.drawCircle(
      centre,
      r,
      Paint()
        ..shader = RadialGradient(
          radius: dark ? 0.52 : 0.44,
          colors: [bleed, bleed.withValues(alpha: 0)],
        ).createShader(bounds),
    );

    // Glass is thicker where you look through it at an angle, so the far edge
    // goes deeper rather than brighter. Skipping this was what made the first
    // version read as a flat coloured circle — but on light it has to stay a
    // hint, for the same reason the fill does.
    final depth = dark ? const Color(0x33000000) : shade(tone, 0.07);
    canvas.drawCircle(
      centre,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.35, 0.8),
          radius: dark ? 0.78 : 0.66,
          colors: [depth, depth.withValues(alpha: 0)],
        ).createShader(bounds),
    );

    // The specular, aimed at the upper-left rim rather than the middle: that is
    // where the curve is steepest, and it keeps the highlight off the glyph.
    // **Painted here, under the icon, not in the pass above it** — see the note
    // on [GlassIconTile]. It still lightens the fill the glyph sits on, so the
    // lens still reads lit; it simply no longer washes the strokes out.
    final sheen = Color(dark ? 0x1FFFFFFF : 0x99FFFFFF);
    canvas.drawCircle(
      centre,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.55, -0.75),
          radius: 0.72,
          colors: [sheen, sheen.withValues(alpha: 0)],
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(_LensBody old) => old.tone != tone || old.dark != dark;
}

/// The one pass that goes *over* the glyph — and the only one that may, since
/// the rim sits at the tile's edge and the glyph reaches a quarter of its width.
/// Last, so the icon reads as sitting inside the lens rather than on it.
class _LensRim extends CustomPainter {
  final Color tone;
  final bool dark;

  const _LensRim({required this.tone, required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final centre = Offset(size.width / 2, size.height / 2);
    final bounds = Rect.fromCircle(center: centre, radius: r);

    // ## The rim carries the effect, and the two palettes build it differently
    //
    // A sweep, not a flat border, in both — but the same recipe cannot serve
    // both, which is what the first version got wrong.
    //
    // On **dark** the tile is a lit object, and one bright ring is the whole
    // story: white catches the upper-left edge and returns weakly around the
    // lower-right, exactly under the specular, so one light source explains
    // both.
    final outerWidth = math.max(1.0, r * 0.055);
    if (dark) {
      canvas.drawCircle(
        centre,
        r - outerWidth / 2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = outerWidth
          ..shader = const SweepGradient(
            colors: [Color(0x54FFFFFF), Color(0x0FFFFFFF), Color(0x30FFFFFF), Color(0x0FFFFFFF), Color(0x54FFFFFF)],
            stops: [0, 0.22, 0.5, 0.78, 1],
            transform: GradientRotation(-math.pi * 0.75),
          ).createShader(bounds),
      );
      return;
    }

    // On **light** it takes two rings, and getting that wrong twice is what
    // kept the tiles from reading as glass at all.
    //
    // The mistake both earlier versions made was drawing an *outline* — first
    // an accent one, then a grey one — and glass has no outline. What it has
    // is a **bevel just inside the edge**, where the material is thickest and
    // light bends through it and concentrates. That bright band is the single
    // most recognisable thing about Apple's material, and it is why the grey
    // ring read as a bordered circle instead: an edge drawn *on* the boundary
    // says "shape", an edge drawn just *inside* it says "thickness".
    //
    // So: a whisper of dark contour on the boundary — only enough to seat the
    // tile on a white card — and a bright white bevel immediately inside it.
    // The fill above is near-clear off-white precisely so this bevel shows;
    // the tone reaches the tile through the glyph's colour bleed instead,
    // which is also the honest order (a clear material, coloured by what's in
    // it, not a coloured material).
    final contour = Color.lerp(AppColors.ink, tone, 0.18)!;
    canvas.drawCircle(
      centre,
      r - outerWidth / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = outerWidth
        ..shader = SweepGradient(
          // Far weaker than the ring it replaces (0.22 against 0.40): it is no
          // longer drawing the circle, only settling it onto the card.
          colors: [
            shade(contour, 0.22),
            shade(contour, 0.11),
            shade(contour, 0.05),
            shade(contour, 0.11),
            shade(contour, 0.22),
          ],
          stops: const [0, 0.26, 0.5, 0.74, 1],
          // Stop 0 at the lower-right: the far edge, opposite the specular.
          transform: const GradientRotation(math.pi * 0.25),
        ).createShader(bounds),
    );

    // The bevel. Wider than the contour — it is a band of material, not a
    // line — and brightest at the upper-left under the specular, with a weaker
    // return at the lower-right where light comes back through.
    final bevelWidth = math.max(1.0, r * 0.085);
    canvas.drawCircle(
      centre,
      r - outerWidth - bevelWidth / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = bevelWidth
        ..shader = const SweepGradient(
          colors: [Color(0xEBFFFFFF), Color(0x38FFFFFF), Color(0x8FFFFFFF), Color(0x38FFFFFF), Color(0xEBFFFFFF)],
          stops: [0, 0.24, 0.5, 0.76, 1],
          transform: GradientRotation(-math.pi * 0.75),
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(_LensRim old) => old.tone != tone || old.dark != dark;
}
