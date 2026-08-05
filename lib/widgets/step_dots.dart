import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// One dot per step, the current one drawn as a pill: the mark that says "there
/// is more after this" on a flow that asks more than one question.
///
/// A sheet is a single question by default in this app, so a stepped one has to
/// declare itself — otherwise the first step reads as the whole thing and the
/// accent button in the header looks like it will finish rather than continue.
/// Steps already taken keep a mid-gray, so the row also says how far in you are
/// without a "2 von 3" anybody has to read.
///
/// **Gray, deliberately — not the accent.** This is a position indicator, not a
/// control: nothing about it can be tapped, and the accent in this app is the
/// colour of the thing you act on (the confirm check, the primary pill). Drawn
/// in blue it competed with that button for the eye on every step of every
/// connect flow, and on onboarding's own bar it sat between two glass controls
/// looking like a third one.
///
/// Sits at the top of the sheet's gray body, above whatever the step asks, and
/// centred in the onboarding wizard's top bar.
class StepDots extends StatelessWidget {
  final int count;

  /// Zero-based.
  final int index;

  const StepDots({super.key, required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
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
              // Three steps of gray, so "where I am" reads at a glance without
              // any of them being loud: the current one carries the text
              // colour's weight, the ones behind it a mid-gray, the ones ahead
              // the same hairline every empty track in the app is drawn in.
              color: i == index
                  ? AppColors.muted
                  : i < index
                  ? AppColors.mutedLight
                  : AppColors.hairline,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}
