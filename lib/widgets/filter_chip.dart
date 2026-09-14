import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// **The app's chip**: a rounded, tappable word that either narrows what is on
/// screen or seeds a field with itself.
///
/// Kalender's people row is where the shape was drawn and where it is still
/// used most — a face, a name, a ring around the lit one — and Listen's
/// Vorhaben suggestions are the same chip with nothing in front of the word.
/// One widget rather than two that resemble each other: the second copy is
/// where a chip row starts having a different corner radius, a different lit
/// colour or a different height from the one beside it, and the two rows are
/// eight points apart on adjacent tabs.
///
/// **The lit ring sits outside the fill, not inside it.** The chip keeps its
/// size when it is selected — a border drawn *inside* would make the row twitch
/// as chips light and go out, and the outer ring is also what lets the fill stay
/// a pale accent rather than a solid one that the label then has to fight.
///
/// [leading] and [trailing] are drawn as they are given, gap included: the
/// calendar's face, colour dot and glyph each sit a different distance from the
/// word, and passing that distance as a number would be three knobs on this
/// class instead of one `Padding` at the call site.

/// How a chip is painted, which follows from **what the row is for**.
///
/// A filter row is a set of answers to one question, so it needs a difference
/// between the answer in force and the rest — [lit] and [muted] are that pair
/// and are only meaningful against each other. A suggestion row is not
/// answering anything: every chip is an offer, so there is no pair, and both
/// halves of it are wrong on their own. [muted] alone is four grey blobs that
/// read as disabled buttons; [lit] alone is four accent chips claiming a
/// selection nobody made. [outlined] is the third thing — paper white, ink
/// label, a hairline rim — which reads as *press me* without reading as *on*.
enum ChipTone {
  /// Not the one in force: grey fill, muted label. Only ever beside a [lit] one.
  muted,

  /// The one in force: accent ring, pale accent fill, ink label.
  lit,

  /// Not a filter at all: white, ink label, hairline rim.
  outlined,
}

class AppFilterChip extends StatelessWidget {
  final String label;

  final ChipTone tone;

  final VoidCallback onTap;

  /// Before the word — a face, a colour dot, a glyph. Include its own trailing
  /// gap.
  final Widget? leading;

  /// After the word — the calendar's "there are calendars inside this one"
  /// caret. Include its own leading gap.
  final Widget? trailing;

  /// Defaults to the plain word's inset. A chip whose [leading] sits closer to
  /// the edge than a word may (an avatar does) passes its own.
  final EdgeInsetsGeometry padding;

  const AppFilterChip({
    super.key,
    required this.label,
    required this.tone,
    required this.onTap,
    this.leading,
    this.trailing,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
  });

  /// What a row of these needs to be laid out in. Tall enough for a 26pt face
  /// plus the chip's own padding and its selected ring — the number lives here
  /// so a second row cannot be a point shorter than the first.
  static const rowHeight = 44.0;

  /// Between one chip and the next.
  static const gap = 8.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        // The ring's lane, kept whatever the tone, so a filter row does not
        // twitch as chips light and go out.
        padding: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(27),
          border: Border.all(color: tone == ChipTone.lit ? AppColors.accent : Colors.transparent, width: 1.5),
        ),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: switch (tone) {
              ChipTone.lit => tint(AppColors.accent, .82),
              ChipTone.muted => AppColors.surfaceAlt,
              ChipTone.outlined => AppColors.surface,
            },
            borderRadius: BorderRadius.circular(24),
            // The rim is what an outlined chip has instead of a fill to be read
            // against: on the card's own white, a white chip with no edge is
            // not a chip.
            border: tone == ChipTone.outlined ? Border.all(color: AppColors.hairline) : null,
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ?leading,
              Text(
                label,
                style: AppText.caption.copyWith(
                  fontWeight: tone == ChipTone.muted ? FontWeight.w400 : FontWeight.w600,
                  color: tone == ChipTone.muted ? AppColors.muted : AppColors.ink,
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}
