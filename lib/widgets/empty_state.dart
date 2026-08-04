import 'package:flutter/material.dart';
import '../theme/tokens.dart';

/// The "there's nothing here yet" block: a tinted circle around an icon, with a
/// line of guidance under it.
///
/// Listen and Box already carried two near-identical copies of this inline;
/// emptying the seed data made it needed in several more places, so it lives
/// here instead. Keep new empty states going through this rather than pasting
/// the circle again.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  /// Defaults to the muted tone the "list is empty" states use. Pass the
  /// accent where the empty state is an invitation to act rather than a
  /// statement of fact.
  final Color? iconColor;

  final double verticalPadding;
  final double gap;

  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.iconColor,
    this.verticalPadding = 52,
    this.gap = 14,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: verticalPadding, horizontal: 20),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: AppColors.surfaceAlt, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(icon, size: 26, color: iconColor ?? AppColors.mutedLight),
          ),
          SizedBox(height: gap),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(color: AppColors.inkTertiary),
          ),
        ],
      ),
    );
  }
}
