import 'package:flutter/material.dart';
import '../theme/tokens.dart';

/// Why a day is a day off, and therefore how its circle is filled.
///
/// Both are "nobody has to be anywhere", but they are not the same size of
/// fact, so they don't get the same weight: a Feiertag is one day and rare, a
/// Ferien block is six weeks in a row. Marking them identically was the old
/// bug in both directions — Ferien alone striped half of August, and dropping
/// Ferien entirely lost the one thing a family plans around. So the Feiertag
/// keeps the texture and the stronger wash, and Ferien is a plain, quieter
/// tint that a whole month of can sit under without shouting.
///
/// Precedence is the caller's, and there is only one sensible order: Karfreitag
/// falls inside the Osterferien and the 25th inside the Weihnachtsferien, so
/// [publicHoliday] wins wherever both are true.
enum DayHighlight { none, schoolHoliday, publicHoliday }

/// The day-number circle used in every day cell across Kalender (week strip,
/// month grid) and Board: a filled circle with an outline ring when selected
/// (same outline-then-fill language as the filter chips — the ring never
/// grows the circle's footprint, it's inset within [size]), an accent-coloured
/// outline ring when it's today but not selected, a wash (plus diagonal
/// stripes, for a Feiertag) when the day is off — see [DayHighlight] —
/// otherwise a flat circle. Shared so "today"/"selected" reads the same way
/// everywhere instead of drifting per-screen.
class DaySelectorCircle extends StatelessWidget {
  final int day;
  final bool selected;
  final bool today;

  /// Whether the day is off, and why. The two washes are worked out here from
  /// [accent] rather than passed in, so the week strip and the month grid
  /// cannot end up shading the same Feiertag differently.
  final DayHighlight highlight;

  final Color accent;
  final double size;
  final double fontSize;
  /// Null falls back to the palette (`surface` / `dayNumber`). They can't be
  /// const defaults any more — a default argument has to be a compile-time
  /// constant, and the tokens are getters over the installed palette.
  final Color? unselectedFill;
  final Color? unselectedTextColor;

  const DaySelectorCircle({
    super.key,
    required this.day,
    required this.selected,
    required this.today,
    required this.accent,
    this.highlight = DayHighlight.none,
    this.size = 34,
    this.fontSize = 14,
    this.unselectedFill,
    this.unselectedTextColor,
  });

  @override
  Widget build(BuildContext context) {
    final off = !selected && highlight != DayHighlight.none;
    final showStripes = !selected && highlight == DayHighlight.publicHoliday;
    final dayText = unselectedTextColor ?? AppColors.dayNumber;
    final offText = AppColors.holidayNumber;
    final textColor = selected ? Colors.white : (today ? accent : (off ? offText : dayText));
    final weight = (selected || today) ? FontWeight.w600 : (off ? FontWeight.w500 : FontWeight.w400);

    final fill = selected
        ? accent
        : switch (highlight) {
            DayHighlight.none => unselectedFill ?? AppColors.surface,
            DayHighlight.schoolHoliday => tint(accent, .93),
            DayHighlight.publicHoliday => tint(accent, .86),
          };

    // Both size and weight are the caller's / the day's own — a day number is
    // the one place where the *state* (selected, today, day off) is carried by
    // weight rather than colour alone. The family comes from the scale.
    final text = Text('$day', style: AppText.input.copyWith(fontSize: fontSize, fontWeight: weight, color: textColor));

    final fillCircle = Container(
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: showStripes
          ? ClipOval(
              child: Stack(
                alignment: Alignment.center,
                fit: StackFit.expand,
                children: [
                  CustomPaint(painter: DiagonalStripePainter(color: offText.withValues(alpha: 0.16))),
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

/// Light diagonal-hatch texture painted inside a Feiertag day-circle.
///
/// Public because the month view's legend swatch has to be painted with the
/// same hatch: a key that shows a flat colour for a striped day is not a key.
class DiagonalStripePainter extends CustomPainter {
  final Color color;

  const DiagonalStripePainter({required this.color});

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
  bool shouldRepaint(covariant DiagonalStripePainter oldDelegate) => oldDelegate.color != color;
}
