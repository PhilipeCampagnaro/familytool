import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// One dot per step, the current one drawn as an accent pill: the mark that
/// says "there is more after this" on a sheet that asks more than one question.
///
/// A sheet is a single question by default in this app, so a stepped one has to
/// declare itself — otherwise the first step reads as the whole thing and the
/// accent button in the header looks like it will finish rather than continue.
/// Steps already taken keep a faded accent, so the row also says how far in you
/// are without a "2 von 3" anybody has to read.
///
/// Sits at the top of the sheet's gray body, above whatever the step asks.
class StepDots extends StatelessWidget {
  final int count;

  /// Zero-based.
  final int index;

  const StepDots({super.key, required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == index ? 22 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == index
                  ? accent
                  : i < index
                  ? accent.withValues(alpha: 0.32)
                  : AppColors.hairline,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}
