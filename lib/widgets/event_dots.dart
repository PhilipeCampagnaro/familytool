import 'package:flutter/material.dart';
import '../theme/tokens.dart';

/// Small source-colour dots shown under a day (week strip, month grid, board
/// day cell) marking that day's events/tasks, overlapping by 0.5px. When more
/// than fit, the last dot becomes a gray "+" badge instead of a plain dot.
/// Shared so every "day with dots" cell looks identical across the app.
class EventDots extends StatelessWidget {
  final List<Color> colors;
  final int overflowCount;
  final double dotSize;

  /// Draws an empty ring ahead of the dots: this day still owes a to-do.
  ///
  /// **A ring rather than another dot, and deliberately colourless.** Every
  /// filled dot in this row is a *calendar* of that colour, so a to-do drawn as
  /// one would claim to be a calendar the household hasn't got. The ring is the
  /// unticked circle the agenda card and the Board row already use for the same
  /// thing, shrunk to the size of a dot — it reads as an empty checkbox, which
  /// is what it is.
  ///
  /// First in the row, so a day carrying both starts with the thing that needs
  /// doing rather than ending with it.
  final bool todo;

  /// The ring's colour — the calendar's accent at the call sites that pass
  /// [todo]. Ignored otherwise.
  final Color? todoColor;

  const EventDots({
    super.key,
    required this.colors,
    required this.overflowCount,
    this.dotSize = 8,
    this.todo = false,
    this.todoColor,
  });

  @override
  Widget build(BuildContext context) {
    const overlap = 0.5;
    final lead = todo ? 1 : 0;
    final total = lead + colors.length + (overflowCount > 0 ? 1 : 0);
    if (total == 0) return const SizedBox.shrink();
    final step = dotSize - overlap;
    final width = dotSize + step * (total - 1);
    return SizedBox(
      width: width,
      height: dotSize,
      child: Stack(
        children: [
          if (todo)
            Positioned(
              left: 0,
              child: Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // Thick enough to read as a ring at 8px and thin enough to
                  // leave a hole — below about 1.6 it fills in on a 2x screen.
                  border: Border.all(color: todoColor ?? AppColors.ink, width: 1.8),
                ),
              ),
            ),
          for (var i = 0; i < colors.length; i++)
            Positioned(
              left: step * (lead + i),
              child: Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(color: colors[i], shape: BoxShape.circle, border: Border.all(color: AppColors.surface, width: 1.5)),
              ),
            ),
          if (overflowCount > 0)
            Positioned(
              left: step * (lead + colors.length),
              child: Container(
                width: dotSize,
                height: dotSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.mutedLight, shape: BoxShape.circle, border: Border.all(color: AppColors.surface, width: 1.5)),
                child: Text(
                  '+',
                  // Sized off the dot it sits in, and the one w800 in the app:
                  // a "+" this small only reads as a glyph at extra bold.
                  style: AppText.microLabel.copyWith(
                    fontSize: dotSize * 0.85,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
