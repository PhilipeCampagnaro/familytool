import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';

/// The big name at the top of a detail screen — a list, a box, a tracker — that
/// **unfolds when it does not fit on one line**.
///
/// A household writes real names ("Devolver empréstimos biblioteca"), and the
/// header has one line and an icon's width less than the screen, so the end of
/// the name was simply gone: an ellipsis, no way to read past it, and the
/// pinned bar's copy of the name ellipsizes in the same place. The caret is the
/// answer the row itself can give — tap it and the name wraps to as many lines
/// as it needs, tap again and it folds back.
///
/// **The caret is only there when there is something behind it.** A name that
/// fits draws no control at all: an affordance that expands nothing is a
/// promise of hidden content that isn't hidden. Whether it fits is measured at
/// the width the row actually got, with the platform's text scale, so it is
/// still right on a large-text phone where a name that fits on one device
/// doesn't on another.
///
/// The whole row is the target, not just the caret — the name is what the
/// reader is looking at, and a 18pt glyph at the end of a line is a small thing
/// to ask them to hit.
///
/// It grows the header rather than overlaying it: the collapsing header
/// measures its own block every frame ([CollapsingHeaderScreen]), so an extra
/// line pushes the body down exactly as a second row would, and scrolling the
/// header away still works while the name is open.
class ExpandableTitle extends StatefulWidget {
  final String text;

  /// Defaults to [AppText.detailTitle], the 23pt name every detail header draws.
  final TextStyle? style;

  /// The ceiling once open. Long enough for any name somebody types, short
  /// enough that a pasted paragraph can't push the whole screen off the bottom.
  final int expandedMaxLines;

  const ExpandableTitle({super.key, required this.text, this.style, this.expandedMaxLines = 4});

  @override
  State<ExpandableTitle> createState() => _ExpandableTitleState();
}

class _ExpandableTitleState extends State<ExpandableTitle> {
  bool _open = false;

  static const _caretGap = 6.0;

  @override
  void didUpdateWidget(ExpandableTitle old) {
    super.didUpdateWidget(old);
    // A rename, or the same screen reused for another list: the reader never
    // asked for *this* name to be open.
    if (old.text != widget.text) _open = false;
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? AppText.detailTitle;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Measured against the *full* width, before any room is taken for the
        // caret: a name that overflows the whole row overflows the shortened
        // one too, so the two answers can't disagree and flicker the control in
        // and out as the layout settles.
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 1,
          textScaler: MediaQuery.textScalerOf(context),
          textDirection: Directionality.of(context),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;
        // The height of one line as this device renders it, which is what the
        // caret is centred on — not on the block, or it would drift to the
        // middle of a three-line name.
        final lineHeight = painter.height;
        painter.dispose();

        final label = Text(
          widget.text,
          maxLines: _open ? widget.expandedMaxLines : 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        );
        if (!overflows) return label;

        // A hint rather than a label, merged into the name's own node: the row
        // still reads as the name it shows, with what the tap would do said
        // after it.
        return MergeSemantics(
          child: Semantics(
            button: true,
            hint: _open ? L.s.hideFullName : L.s.showFullName,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _open = !_open),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: label),
                  const SizedBox(width: _caretGap),
                  SizedBox(
                    height: lineHeight,
                    child: Center(
                      child: AnimatedRotation(
                        turns: _open ? .5 : 0,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        // Flat: a caret is a control, not a name for a thing,
                        // and the duotone under-layer would draw it as a hollow
                        // triangle.
                        child: AppIcon(
                          AppIcons.caretDown,
                          size: AppGlyph.caret,
                          flat: true,
                          color: AppColors.mutedLight,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
