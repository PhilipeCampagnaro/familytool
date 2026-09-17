import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import 'anchored_menu.dart';

/// One option in an [InlineDropdown].
///
/// It carries both glyphs on purpose, the way [AnchoredMenuItem] does: a
/// Phosphor [icon] for the panel Flutter draws off iOS, and an SF Symbol
/// [symbol] for UIKit's own menu, which takes nothing else. See the menu
/// section of CLAUDE.md — and validate a symbol name against the runtime's
/// list before using one.
class DropdownChoice<T> {
  final T value;
  final String label;
  final IconData icon;
  final String? symbol;

  const DropdownChoice({required this.value, required this.label, required this.icon, this.symbol});
}

/// The app's bordered dropdown: the option in force and a caret in a hairline
/// box, opening the system's own menu beside itself.
///
/// Goes through [showAnchoredMenu] like every other menu in the app, so on iOS
/// the choice is UIKit's glass menu growing out of this control rather than a
/// Material popup. **There is deliberately no `DropdownButton` anywhere in
/// this app** — it drops a Material overlay at the other end of the screen and
/// draws its own list in a second design language.
///
/// The option in force is the menu's ticked row ([AnchoredMenuItem.selected]),
/// which is the system's way of saying it; the panel Flutter draws off iOS has
/// no tick, so there the button's own label is what says which one is on.
///
/// Generalised out of the family page's role picker, which was the only one of
/// these and is now one caller of two: the onboarding invite step asks the same
/// question with a shorter list and its own wording (Erwachsener/Kind rather
/// than the role names), so the *choices* belong to the caller and only the
/// control belongs here.
class InlineDropdown<T> extends StatefulWidget {
  final T value;
  final List<DropdownChoice<T>> choices;
  final ValueChanged<T> onChanged;

  /// The heading above the menu's rows — what is being chosen, not which
  /// option is on.
  final String? menuTitle;

  /// Width of the panel Flutter draws off iOS. UIKit sizes its own.
  final double menuWidth;

  const InlineDropdown({
    super.key,
    required this.value,
    required this.choices,
    required this.onChanged,
    this.menuTitle,
    this.menuWidth = 200,
  });

  @override
  State<InlineDropdown<T>> createState() => _InlineDropdownState<T>();
}

class _InlineDropdownState<T> extends State<InlineDropdown<T>> {
  final GlobalKey _anchorKey = GlobalKey();

  void _open() {
    showAnchoredMenu(
      context: context,
      anchorKey: _anchorKey,
      title: widget.menuTitle,
      width: widget.menuWidth,
      items: [
        for (final choice in widget.choices)
          AnchoredMenuItem(
            label: choice.label,
            icon: choice.icon,
            symbol: choice.symbol,
            selected: choice.value == widget.value,
            onSelected: () {
              if (choice.value != widget.value) widget.onChanged(choice.value);
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // The option in force, by value rather than by index, so a caller may
    // rebuild its list without the label jumping to a different row. Falls
    // back to the first: a value with no choice behind it is a caller bug, and
    // an empty box would hide it.
    final current = widget.choices.firstWhere(
      (c) => c.value == widget.value,
      orElse: () => widget.choices.first,
    );
    return KeyedSubtree(
      key: _anchorKey,
      child: GestureDetector(
        onTap: _open,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.iconTile),
            border: Border.all(color: AppColors.hairline2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(current.label, style: AppText.rowTitle),
              const SizedBox(width: 8),
              AppIcon(AppIcons.caretUpDown, size: 14, color: AppColors.mutedLight),
            ],
          ),
        ),
      ),
    );
  }
}
