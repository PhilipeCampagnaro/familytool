import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/tokens.dart';
import 'settings_chrome.dart';

/// The house number, typed under a street that was picked without one — the
/// same field in the onboarding's address card and the Abfall connect sheet.
///
/// **The keyboard is iOS's numbers-and-punctuation one**, which is what
/// `numberWithOptions(signed: true)` asks UIKit for: digits on the first plane,
/// and an ABC key for the "a" in "12a". The plain number pad has no way to type
/// that letter at all, and the full keyboard makes the digits the second tap.
///
/// **Never `const`-construct this**: it reads the palette and [L.s] in build.
class HouseNumberField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final VoidCallback onSubmitted;

  const HouseNumberField({super.key, required this.controller, this.focusNode, required this.onSubmitted});

  @override
  Widget build(BuildContext context) {
    return FieldBox(
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: const TextInputType.numberWithOptions(signed: true),
        textInputAction: TextInputAction.done,
        maxLength: 12,
        style: AppText.searchInput,
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: L.s.houseNumberPlaceholder,
          isDense: true,
          counterText: '',
        ),
        onSubmitted: (_) => onSubmitted(),
      ),
    );
  }
}
