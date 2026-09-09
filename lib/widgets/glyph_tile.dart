import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import '../theme/tokens.dart';

/// The square a glyph occupies in a settings row, a masthead or a provider
/// list — the footprint only, with the icon centred in it.
///
/// **Not `IconTile` (`icon_picker.dart`)**, which is the other half of the
/// naming and does a different job: that one takes an `iconKey` string and
/// works out whether it names a merchant logo, a grocery photograph or a
/// symbol. This one is handed the glyph already and only reserves its space.
///
/// ## This used to be a glass lens, and the duotone icons took its job
///
/// It was a drawn glass disc: a near-clear tinted body, the glyph's colour
/// bleeding into it, thickness shading at the far edge, a specular, and a
/// bright bevel just inside the rim, with the glyph painted *between* the
/// passes so it read as sitting inside the material. All of that existed to
/// give a flat stroke icon some depth and some weight on a white card.
///
/// A Phosphor duotone glyph brings its own. The under-layer is already a mass
/// behind the strokes, and putting that inside a lit disc was two depth cues
/// arguing over 34 points: the lens said "this is a lit object", the glyph said
/// "this is a flat shape with a shadow in it", and neither won. Dropping the
/// disc is what made the icons read at all, so the whole lens went and this is
/// what is left of it.
///
/// ## What is left is still worth a widget
///
/// The **footprint**, which is the part five call sites have to agree on. A row
/// whose glyph is 22pt and a row whose glyph is 25pt must still start their
/// text at the same place, and the avatar rows beside them reserve their own
/// square. Sizing the box from the row rather than from the drawing is what
/// keeps that column straight — it is the reason this did not simply become a
/// bare `AppIcon` at each call site.
///
/// [iconSize] defaults to [size] × 0.66. That ratio, not the 0.5 the lens used:
/// with no disc around it the glyph is free to take the space the material was
/// occupying, and at 0.5 it floats in a hole.
///
/// **Never `const`-construct this** — like every widget that reads a token in
/// `build`, a canonicalised instance would keep the palette it was born with.
class GlyphTile extends StatelessWidget {
  final IconData icon;
  final double size;
  final double? iconSize;

  /// Null means the app's ink. Pass a colour to tint a glyph to the thing it
  /// belongs to — a box's tone, a list's brand colour.
  final Color? tone;

  const GlyphTile({super.key, required this.icon, this.size = 34, this.iconSize, this.tone});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: AppIcon(icon, size: iconSize ?? size * 0.66, color: tone ?? AppColors.ink),
      ),
    );
  }
}
