import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/app_icons.dart';

/// One option in a [SegmentedControl].
///
/// A segment carries a label, an icon, or both. Icon-only is for a control
/// whose choices are pictures of themselves — the Spend page's three charts —
/// and it still needs [label], which VoiceOver reads in place of the glyph.
class SegmentedOption<T> {
  final T value;
  final String label;
  final IconData? icon;

  /// False draws the glyph alone and leaves [label] to the screen reader.
  final bool showLabel;

  const SegmentedOption({required this.value, required this.label, this.icon, this.showLabel = true})
    : assert(icon != null || showLabel, 'A segment with no icon must show its label');
}

/// The app's two-or-three-way switch, as used at the top of the Listen sheet
/// ("Welche Art von Liste?") and the Board sheet ("Was möchtest du anlegen?").
///
/// **The track needs its hairline.** `surfaceAlt` is within a percent of the
/// sheet's own `screenBg` body on light, so without the border the control has
/// no visible edge at all and reads as two loose labels, one of which happens to
/// sit on a white pill. The border draws the control; the fill only separates
/// the inactive half from the white thumb.
///
/// Nothing here may be `const`-constructed by a caller: every colour comes from
/// [AppColors], which is swapped when the palette changes — see
/// `tool/check_const_palette.dart` for what that costs when it is got wrong.
class SegmentedControl<T> extends StatelessWidget {
  final List<SegmentedOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  /// The fully rounded variant, and the one the Spend page's two slicers wear.
  ///
  /// It is a different control rather than a skin: the thumb is a capsule, the
  /// track has no border of its own — a pill inside a pill reads as a button
  /// with a button in it — and the segments are parted by hairlines instead,
  /// which is the mark iOS uses to say "these are alternatives" once the border
  /// is gone. The hairline is only ever drawn between two *inactive* segments,
  /// because a rule against the thumb's edge reads as a seam in the thumb.
  final bool pill;

  const SegmentedControl({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.pill = false,
  });

  /// How long the thumb takes to travel, and how long a label takes to go from
  /// muted to chosen.
  ///
  /// **The thumb is one object that moves, not one that is repainted in a new
  /// place.** Redrawn, the control answered a tap by having the white capsule
  /// vanish from under one word and appear under another, which says nothing
  /// about which way the choice went — on a range slicer, where the four
  /// segments are an ordered scale, that is the one thing the movement is for.
  static const _travel = Duration(milliseconds: 240);

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final chosen = options.indexWhere((option) => option.value == value);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(pill ? 100 : 18),
        border: pill ? null : Border.all(color: AppColors.hairline),
      ),
      child: Stack(
        children: [
          // **Placed by fraction, not by measurement.** A `LayoutBuilder` here
          // would be the obvious way to get the segment width — and it cannot
          // answer an intrinsic query, which is exactly what the Spend page's
          // range slicer asks of it from inside an `IntrinsicHeight`. The
          // segments are all flex 1, so a thumb one-nth wide aligned on a
          // fraction lands on the same arithmetic without anyone having to
          // measure anything. The hairlines between them are a point each, and
          // that is the whole of the error.
          //
          // `Positioned.fill` rather than a plain child: only the row below may
          // give the stack its size, or a control in a column would be asked to
          // fill a height that has no end.
          if (chosen >= 0)
            Positioned.fill(
              child: AnimatedAlign(
                duration: _travel,
                curve: Curves.easeOutCubic,
                alignment: Alignment(options.length < 2 ? 0 : -1 + 2 * chosen / (options.length - 1), 0),
                child: FractionallySizedBox(
                  widthFactor: 1 / options.length,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(pill ? 100 : 14),
                      boxShadow: AppShadows.thumb,
                    ),
                  ),
                ),
              ),
            ),
          // First in the stack after the thumb, so the labels are drawn over
          // it: a capsule painted on top would carry the text of the segment it
          // is leaving across the ones it passes.
          Row(
            children: [
              for (final (index, option) in options.indexed) ...[
                if (pill && index > 0)
                  _Separator(
                    visible: options[index - 1].value != value && option.value != value,
                    duration: _travel,
                  ),
                Expanded(
                  child: _SegButton(
                    label: option.showLabel ? option.label : null,
                    semanticLabel: option.label,
                    icon: option.icon,
                    active: option.value == value,
                    accent: accent,
                    pill: pill,
                    duration: _travel,
                    onTap: () => onChanged(option.value),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// The hairline between two neighbouring choices, kept in the layout when it is
/// invisible so the segments do not shuffle sideways as the thumb moves.
///
/// It fades rather than blinks, on the thumb's own clock: the rule beside a
/// segment the thumb is arriving at has to be gone by the time it gets there,
/// and switched off a frame after the tap it reads as a flicker in a control
/// that is otherwise gliding.
class _Separator extends StatelessWidget {
  final bool visible;
  final Duration duration;

  const _Separator({required this.visible, required this.duration});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 1,
      height: 18,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: duration,
        curve: Curves.easeOutCubic,
        child: DecoratedBox(decoration: BoxDecoration(color: AppColors.hairline)),
      ),
    );
  }
}

/// One segment's label and glyph. **The capsule behind it is not drawn here** —
/// it is the one thumb in the stack above, which is what lets it slide.
class _SegButton extends StatelessWidget {
  final String? label;
  final String semanticLabel;
  final IconData? icon;
  final bool active;
  final Color accent;
  final bool pill;
  final Duration duration;
  final VoidCallback onTap;

  const _SegButton({
    required this.label,
    required this.semanticLabel,
    required this.icon,
    required this.active,
    required this.accent,
    required this.pill,
    required this.duration,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // On the pill the chosen segment is the app's ink rather than its accent:
    // the thumb already says which one is chosen, and a blue label on top of it
    // made the control compete with the figure it is there to qualify.
    final ink = active ? (pill ? AppColors.ink : accent) : AppColors.muted;

    return Semantics(
      button: true,
      selected: active,
      label: semanticLabel,
      child: GestureDetector(
        // Opaque, because the segment no longer paints anything of its own and
        // a transparent child is not a target.
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: pill ? 8 : 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Flat: a segment is a control. See [AppIcon.flat].
              if (icon case final glyph?)
                TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: ink),
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  builder: (context, tone, _) =>
                      AppIcon(glyph, size: AppGlyph.row, color: tone ?? ink, flat: true),
                ),
              if (icon != null && label != null) const SizedBox(width: 7),
              if (label case final text?)
                Flexible(
                  // The label crosses over while the thumb is on its way, so
                  // the two segments trade weight instead of swapping it at the
                  // end of the slide.
                  child: AnimatedDefaultTextStyle(
                    duration: duration,
                    curve: Curves.easeOutCubic,
                    style: AppText.buttonSmall.copyWith(color: ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: Text(text),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
