import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'icon_image.dart';

/// A shop's mark on the white disc every brand in the app is drawn on — the
/// one place that knows how a logo is framed, for Listen, Box, Ausgaben and the
/// icon picker alike.
///
/// **The logo fills the disc rather than sitting inside it.** Brand marks share
/// no shape: REWE is a full-bleed red square, IKEA a wide wordmark, ALDI a tall
/// one. Drawn bare they normalise to nothing, so the disc is what gives all of
/// them the same footprint — but the disc used to hold the artwork at 0.68 of
/// its width, the square that fits inside a circle, and a red square floating
/// on a white circle reads as a sticker stuck to the row instead of as the
/// shop's own mark. Drawn edge to edge and clipped round, REWE *is* the disc.
///
/// **That works because the artwork is framed for it, not because the clip is
/// kind.** A circle keeps only 79% of its square, so a badge whose lettering
/// runs to its own edge would lose the ends of it — ALDI NORD did, AliExpress
/// lost two fifths of its logotype. `tool/icon_gen/frame_merchants.py` is the
/// pass that fixes that in the *asset*: a badge's flat colour is extended to
/// fill the frame and its logotype scaled to fit the inscribed circle, a mark
/// on transparency is scaled until its bounding box touches the circle (which
/// makes a wide wordmark bigger than it was), and a gradient with no flat
/// colour to extend is left fitting inside. Run it after dropping a logo into
/// `assets/merchants/` — the widget draws what it is given at full width and
/// has no per-logo inset to fall back on, by design: a table of those in Dart
/// is the thing a new PNG would silently miss (same reasoning as
/// `brand_colors.dart`).
///
/// The white ground stays in both palettes, because these logos are printed for
/// paper, and the hairline is what makes a white one visible on a white card —
/// a badge that now covers the disc simply hides it.
class BrandMark extends StatelessWidget {
  final double size;

  /// A file in `assets/merchants/`.
  final String? asset;

  /// What goes on the disc when there is no logo — a shop's initials, a
  /// category glyph. The disc is identical either way, which is the whole point
  /// of a column of them.
  final Widget? fallback;

  final bool border;

  const BrandMark({super.key, required this.size, this.asset, this.fallback, this.border = true});

  @override
  Widget build(BuildContext context) {
    final logo = asset;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.brandTile,
        shape: BoxShape.circle,
        border: border ? Border.all(color: AppColors.hairline) : null,
      ),
      alignment: Alignment.center,
      child: logo == null
          ? fallback
          : ClipOval(child: IconImage(asset: logo, size: size)),
    );
  }
}
