import 'package:flutter/material.dart';
import '../theme/tokens.dart';

/// The day-number circle used in every day cell across Kalender (week strip,
/// month grid) and Board: a filled circle with an outline ring when selected
/// (same outline-then-fill language as the filter chips — the ring never
/// grows the circle's footprint, it's inset within [size]), an accent-coloured
/// outline ring when it's today but not selected, a diagonal-stripe fill for
/// holidays, otherwise a flat circle. Shared so "today"/"selected" reads the
/// same way everywhere instead of drifting per-screen.
class DaySelectorCircle extends StatelessWidget {
  final int day;
  final bool selected;
  final bool today;
  final bool holiday;
  final Color accent;
  final double size;
  final double fontSize;
  /// Null falls back to the palette (`surface` / `dayNumber` /
  /// `holidayNumber`). They can't be const defaults any more — a default
  /// argument has to be a compile-time constant, and the tokens are getters
  /// over the installed palette.
  final Color? unselectedFill;
  final Color? unselectedTextColor;
  final Color holidayFill;
  final Color? holidayTextColor;

  const DaySelectorCircle({
    super.key,
    required this.day,
    required this.selected,
    required this.today,
    required this.accent,
    this.holiday = false,
    this.size = 34,
    this.fontSize = 14,
    this.unselectedFill,
    this.unselectedTextColor,
    this.holidayFill = Colors.transparent,
    this.holidayTextColor,
  });

  @override
  Widget build(BuildContext context) {
    final showHolidayStripes = holiday && !selected;
    final fill = unselectedFill ?? AppColors.surface;
    final dayText = unselectedTextColor ?? AppColors.dayNumber;
    final holidayText = holidayTextColor ?? AppColors.holidayNumber;
    final textColor = selected ? Colors.white : (today ? accent : (holiday ? holidayText : dayText));
    final weight = (selected || today) ? FontWeight.w600 : (holiday ? FontWeight.w500 : FontWeight.w400);

    // Both size and weight are the caller's / the day's own — a day number is
    // the one place where the *state* (selected, today, holiday) is carried by
    // weight rather than colour alone. The family comes from the scale.
    final text = Text('$day', style: AppText.input.copyWith(fontSize: fontSize, fontWeight: weight, color: textColor));

    final fillCircle = Container(
      decoration: BoxDecoration(color: selected ? accent : (holiday ? holidayFill : fill), shape: BoxShape.circle),
      alignment: Alignment.center,
      child: showHolidayStripes
          ? ClipOval(
              child: Stack(
                alignment: Alignment.center,
                fit: StackFit.expand,
                children: [
                  CustomPaint(painter: _DiagonalStripePainter(color: holidayText.withValues(alpha: 0.16))),
                  Center(child: text),
                ],
              ),
            )
          : text,
    );

    // Selected state uses the same outline-ring-then-fill language as the
    // filter chips: the ring is inset within [size] via padding, instead of a
    // BoxShadow halo (which used to bleed a few px past the box and overlap
    // whatever sat above the circle in a Column).
    return Container(
      width: size,
      height: size,
      padding: selected ? const EdgeInsets.all(1.5) : EdgeInsets.zero,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: selected
            ? Border.all(color: accent, width: 1.5)
            : ((!selected && today) ? Border.all(color: accent, width: 2) : null),
      ),
      child: fillCircle,
    );
  }
}

/// Light diagonal-hatch texture painted inside a holiday day-circle.
class _DiagonalStripePainter extends CustomPainter {
  final Color color;

  const _DiagonalStripePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.3;
    const gap = 5.5;
    final span = size.width + size.height;
    for (double x = -size.height; x < span; x += gap) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DiagonalStripePainter oldDelegate) => oldDelegate.color != color;
}
