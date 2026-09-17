import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import '../theme/app_icons.dart';

/// The "there's nothing here yet" block: a tinted circle around an icon, with a
/// line of guidance under it, and optionally one action under that.
///
/// Listen and Box already carried two near-identical copies of this inline;
/// emptying the seed data made it needed in several more places, so it lives
/// here instead. Keep new empty states going through this rather than pasting
/// the circle again.
///
/// **A screen with nothing on it draws this bare, never inside a
/// [SectionCard].** A card is a container for rows, and an empty one is a box
/// drawn around the statement that there is no box — Listen is the shape every
/// screen follows. Settings pages are the exception and say so where they do
/// it: there the card holds the place its rows will take on a page that has
/// other cards around it, so the page keeps its shape once something connects.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  /// Defaults to the muted tone the "list is empty" states use. Pass the
  /// accent where the empty state is an invitation to act rather than a
  /// statement of fact.
  final Color? iconColor;

  /// One thing to press under the message — Board's "Aufgabe hinzufügen".
  /// Most empty states leave it null and point at the `+` in the header
  /// instead, which is where the gesture lives anyway; pass it where the
  /// screen has no other way in.
  final Widget? action;

  final double verticalPadding;
  final double gap;

  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.iconColor,
    this.action,
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
            child: AppIcon(icon, size: 26, color: iconColor ?? AppColors.mutedLight),
          ),
          SizedBox(height: gap),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(color: AppColors.inkTertiary),
          ),
          if (action case final action?) ...[SizedBox(height: gap + 2), action],
        ],
      ),
    );
  }
}
