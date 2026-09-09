import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/app_icons.dart';

/// One option in a [SegmentedControl].
class SegmentedOption<T> {
  final T value;
  final String label;
  final IconData icon;

  const SegmentedOption({required this.value, required this.label, required this.icon});
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

  const SegmentedControl({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          for (final option in options)
            Expanded(
              child: _SegButton(
                label: option.label,
                icon: option.icon,
                active: option.value == value,
                accent: accent,
                onTap: () => onChanged(option.value),
              ),
            ),
        ],
      ),
    );
  }
}

class _SegButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  const _SegButton({
    required this.label,
    required this.icon,
    required this.active,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: active ? AppColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          boxShadow: active ? AppShadows.thumb : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Flat: a segment is a control. See [AppIcon.flat].
            AppIcon(icon, size: 15, color: active ? accent : AppColors.muted, flat: true),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.buttonSmall.copyWith(color: active ? accent : AppColors.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
