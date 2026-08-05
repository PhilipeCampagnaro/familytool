import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The filled accent pill a **full screen** ends with — onboarding's "Los
/// geht's", the confirmation screen's way out. A sheet ends with
/// [OutlinedSheetAction] instead: a bordered card sitting on the sheet's gray
/// body, where a filled pill would compete with the accent check in the header.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const PrimaryButton({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(AppRadii.pill)),
        child: Text(label, style: AppText.buttonLarge.copyWith(color: Colors.white)),
      ),
    );
  }
}
