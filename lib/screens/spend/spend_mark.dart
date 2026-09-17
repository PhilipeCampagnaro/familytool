import 'package:flutter/material.dart';

import '../../data/icon_suggestions.dart';
import '../../theme/app_icons.dart';
import '../../theme/tokens.dart';
import '../../widgets/icon_picker.dart';

/// The round mark at the head of every Ausgaben row.
///
/// **One disc, three fillings, and the disc never changes.** The page is a list
/// of payments over a list of categories over a list of shops, and when each of
/// those carried its own kind of tile — a tone-coloured square here, a filled
/// category colour there, a neutral circle on the third — the left edge of the
/// card read as three unrelated lists that happened to be stacked. A column of
/// identical discs is what lets the eye go down the *names*, which is what the
/// reader came for. The colours are not lost: they are in the donut, which is
/// the one place on the page a colour means something.
///
/// **The disc is white, because most of them have a logo on them.** Shop marks
/// are full-colour artwork drawn for paper, and a grey circle behind one reads
/// as a sticker on the wrong background — so the mark takes the same white tile
/// the app already gives a brand in Listen and on the calendar providers, with
/// the hairline that is the only reason a white circle is visible on a white
/// card. What is set on that tile is [AppColors.brandTileInk] rather than
/// `ink`: the tile does not follow the theme, so its contents cannot either.
///
/// **A business is drawn as itself where we know it.** A logo says "REWE"
/// faster than any word does, and `assets/merchants/` already holds two hundred
/// of them for Listen. Where the folder has none the shop gets its **initials**
/// rather than a generic shopfront glyph — one shopfront repeated down a column
/// of eight different shops names none of them, and two letters name every one.
class SpendMark extends StatelessWidget {
  final double size;

  /// The glyph, for a row that names a thing — a category, a fold of them.
  final IconData? icon;

  /// The shop, for a row that names a business. Takes precedence over [icon].
  final String? merchant;

  const SpendMark({super.key, required this.size, this.icon, this.merchant})
    : assert(icon != null || merchant != null, 'A mark has to be of something');

  @override
  Widget build(BuildContext context) {
    final shop = merchant?.trim();
    final asset = shop == null || shop.isEmpty ? null : merchantLogoAsset(shop);
    final initials = asset != null || shop == null ? null : initialsOf(shop);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.brandTile,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.hairline),
      ),
      alignment: Alignment.center,
      // The logos are drawn for paper and a few of them bleed to their own
      // edge; the clip is what keeps one of those a circle.
      clipBehavior: Clip.antiAlias,
      padding: asset == null ? EdgeInsets.zero : EdgeInsets.all(size * 0.16),
      child: switch ((asset, initials)) {
        (final logo?, _) => IconImage(asset: logo, size: AppText.markImage(size)),
        (_, final letters?) => Text(
          letters,
          // Sized against the circle, like an avatar's initials.
          style: AppText.itemTitle.copyWith(
            fontSize: AppText.markInitials(size),
            letterSpacing: 0.2,
            color: AppColors.brandTileInk,
          ),
        ),
        // Duotone: the over-layer is the black line and the under-layer the
        // grey fill behind it, which is the whole point of the icon set and is
        // what the tone-coloured tiles were flattening.
        _ => AppIcon(icon ?? AppIcons.receipt, size: AppText.markGlyph(size), color: AppColors.brandTileInk),
      },
    );
  }
}

/// A shop's first two letters, upper-cased, or null for a name with nothing to
/// take them from.
///
/// Letters **and digits**, because "Q1" and "o2" are shops and "Q" alone is
/// not; everything else — the spacing, punctuation and card noise an Apple Pay
/// merchant string arrives with — is stepped over rather than counted.
String? initialsOf(String name) {
  final buffer = StringBuffer();
  for (final unit in name.runes) {
    final char = String.fromCharCode(unit);
    if (!_letterOrDigit.hasMatch(char)) continue;
    buffer.write(char.toUpperCase());
    if (buffer.length == 2) break;
  }
  return buffer.isEmpty ? null : buffer.toString();
}

final _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);
