import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/tokens.dart';

/// The idle ring colour Board and Listen already used for their unchecked
/// rows — kept here so both screens draw the same circle.


/// Whole "abhaken" gesture: strike, a short hold, then the collapse.
const _checkOffDuration = Duration(milliseconds: 520);

/// The line is drawn and the check fills over the first ~240ms…
const _strikeInterval = Interval(0, 0.46, curve: Curves.easeOutCubic);

/// …then, after a beat, the row folds away over the last ~200ms.
const _collapseInterval = Interval(0.62, 1, curve: Curves.easeInCubic);

/// Plays the check-off feedback *before* the item actually changes state:
/// tapping fills the check and strikes the text through, the row holds for a
/// beat so the change is readable, then it collapses out of the list — and only
/// then does [onCompleted] fire and move the item across (pair it with
/// [CheckOffArrival] on the receiving side).
///
/// [undo] runs the same thing backwards for a row in the "Erledigt" section:
/// the line retracts, the check empties back to its ring, and the row folds
/// *up* toward the open list.
///
/// [builder] gets the strike progress — 0 (open) → 1 (done), whichever way it's
/// travelling — to feed [CheckOffButton] and [StrikeThrough], plus the callback
/// that starts the whole thing. Always give this (or whatever wrapper sits
/// directly in the list) a `ValueKey(item.id)`: it holds animation state, so an
/// unkeyed row would inherit the previous item's progress when the list shifts.
class CheckOffRow extends StatefulWidget {
  final Widget Function(BuildContext context, double strike, VoidCallback toggle) builder;
  final VoidCallback onCompleted;
  final bool undo;

  const CheckOffRow({super.key, required this.builder, required this.onCompleted, this.undo = false});

  @override
  State<CheckOffRow> createState() => _CheckOffRowState();
}

class _CheckOffRowState extends State<CheckOffRow> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: _checkOffDuration)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onCompleted();
    });

  late final CurvedAnimation _strike = CurvedAnimation(parent: _controller, curve: _strikeInterval);
  late final CurvedAnimation _collapse = CurvedAnimation(parent: _controller, curve: _collapseInterval);

  @override
  void dispose() {
    _strike.dispose();
    _collapse.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_controller.status == AnimationStatus.dismissed) _controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final gone = _collapse.value;
        // An undone row starts struck through and unwinds back to nothing.
        final strike = widget.undo ? 1 - _strike.value : _strike.value;
        final child = widget.builder(context, strike, _toggle);
        if (gone == 0) return child;
        return ClipRect(
          child: Align(
            // Clip from the side it is leaving towards, so the row reads as
            // sliding out rather than shrinking in place.
            alignment: widget.undo ? Alignment.bottomCenter : Alignment.topCenter,
            heightFactor: 1 - gone,
            child: Opacity(
              opacity: 1 - gone,
              child: Transform.translate(offset: Offset(0, (widget.undo ? -gone : gone) * 12), child: child),
            ),
          ),
        );
      },
    );
  }
}

/// The other half of [CheckOffRow]: fades and slides the row that just moved
/// into this section in from the side it came from — from above for the
/// "Erledigt" section, [fromBelow] for a row travelling back up into the open
/// list. [animate] should only be true for the item that just moved —
/// everything else builds at rest.
class CheckOffArrival extends StatefulWidget {
  final bool animate;
  final bool fromBelow;
  final Widget child;

  const CheckOffArrival({super.key, required this.animate, required this.child, this.fromBelow = false});

  @override
  State<CheckOffArrival> createState() => _CheckOffArrivalState();
}

class _CheckOffArrivalState extends State<CheckOffArrival> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: widget.animate ? 0 : 1,
  );

  late final CurvedAnimation _t = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    if (widget.animate) _controller.forward();
  }

  @override
  void dispose() {
    _t.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Built the same way either way — a resting row just sits at value 1, so
    // flipping [animate] never reshapes the subtree under it.
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) => Opacity(
        opacity: _t.value,
        child: Transform.translate(
          offset: Offset(0, (1 - _t.value) * (widget.fromBelow ? 12 : -12)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// The round check itself: an idle ring that fills as [progress] runs 0 → 1
/// while the check pops in. [filled] picks the done look — Board's accent disc
/// with a white check, or Listen's bare accent check.
class CheckOffButton extends StatelessWidget {
  final double progress;
  final Color accent;
  final VoidCallback onTap;
  final double size;
  final bool filled;

  const CheckOffButton({super.key, required this.progress, required this.accent, required this.onTap, required this.size, this.filled = false});

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0);
    // The ring is gone by the time the check is fully in, so the two never
    // fight for the same pixels.
    final ring = (1 - p / 0.6).clamp(0.0, 1.0);
    final check = ((p - 0.3) / 0.7).clamp(0.0, 1.0);
    final pop = Curves.easeOutBack.transform(check);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (ring > 0)
              Opacity(
                opacity: ring,
                child: Icon(LucideIcons.circle, size: size, color: AppColors.idleRing),
              ),
            if (filled && p > 0)
              Transform.scale(
                scale: Curves.easeOutBack.transform(p.clamp(0.0, 1.0)),
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                ),
              ),
            if (check > 0)
              Opacity(
                opacity: check,
                child: Transform.scale(
                  scale: 0.5 + 0.5 * pop,
                  child: Icon(
                    LucideIcons.check,
                    size: filled ? size * 0.54 : size,
                    color: filled ? Colors.white : accent,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Draws a line across [child] as [progress] runs 0 → 1. The stack takes the
/// child's own size, so on a [Text] the line stops at the last glyph instead of
/// running the full row width.
class StrikeThrough extends StatelessWidget {
  final double progress;
  final Color color;
  final double thickness;
  final Widget child;

  const StrikeThrough({super.key, required this.progress, required this.color, required this.child, this.thickness = 1.4});

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0);
    if (p == 0) return child;
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: p,
              heightFactor: 1,
              child: Center(
                child: Container(
                  height: thickness,
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(thickness)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
