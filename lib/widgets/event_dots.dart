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

  const EventDots({super.key, required this.colors, required this.overflowCount, this.dotSize = 8});

  @override
  Widget build(BuildContext context) {
    const overlap = 0.5;
    final total = colors.length + (overflowCount > 0 ? 1 : 0);
    if (total == 0) return const SizedBox.shrink();
    final step = dotSize - overlap;
    final width = dotSize + step * (total - 1);
    return SizedBox(
      width: width,
      height: dotSize,
      child: Stack(
        children: [
          for (var i = 0; i < colors.length; i++)
            Positioned(
              left: step * i,
              child: Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(color: colors[i], shape: BoxShape.circle, border: Border.all(color: AppColors.surface, width: 1.5)),
              ),
            ),
          if (overflowCount > 0)
            Positioned(
              left: step * colors.length,
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
