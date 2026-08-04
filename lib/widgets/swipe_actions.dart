import 'package:flutter/material.dart';

/// One action revealed behind a [SwipeActionsRow].
class SwipeAction {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  /// Whether the row slides shut again after [onTap]. Off for anything that
  /// removes the row outright — there'd be nothing left to close, and closing
  /// it fights the removal animation.
  final bool closesRow;

  const SwipeAction({required this.icon, required this.color, required this.onTap, this.closesRow = true});
}

/// iOS-style swipe-left reveal for row actions — so deleting an item or fixing
/// a title doesn't always mean opening its detail sheet first. Used by the
/// Kalender event cards and the Listen/Boxen item rows.
///
/// The reveal is tracked as a 0 (closed) to 1 (fully open) fraction on an
/// [AnimationController] rather than a raw pixel drag offset, so the live drag
/// and the release "snap open/closed" share one value and one curve. A tap
/// while open just closes the row instead of firing [onTap].
///
/// [child] has to be opaque: it slides *over* the actions, so a transparent row
/// (one relying on its [SectionCard] for a background) shows them through it —
/// wrap it in a `ColoredBox` where the surrounding card provides the fill.
class SwipeActionsRow extends StatefulWidget {
  final List<SwipeAction> actions;
  final Widget child;
  final VoidCallback? onTap;

  /// Corners of the revealed action strip. Zero for a row inside a
  /// [SectionCard] — the card clips its own corners — and the card's radius
  /// for a free-standing card like a Kalender event.
  final BorderRadius borderRadius;
  final double actionWidth;

  const SwipeActionsRow({
    super.key,
    required this.actions,
    required this.child,
    this.onTap,
    this.borderRadius = BorderRadius.zero,
    this.actionWidth = 64,
  });

  @override
  State<SwipeActionsRow> createState() => _SwipeActionsRowState();
}

class _SwipeActionsRowState extends State<SwipeActionsRow> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));

  double get _actionsWidth => widget.actionWidth * widget.actions.length;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close() => _controller.animateTo(0, curve: Curves.easeOutCubic);

  void _onDragUpdate(DragUpdateDetails details) {
    final next = _controller.value - details.delta.dx / _actionsWidth;
    _controller.value = next.clamp(0.0, 1.0);
  }

  void _onDragEnd(DragEndDetails details) {
    final v = details.primaryVelocity ?? 0;
    final target = v < -200 ? 1.0 : (v > 200 ? 0.0 : (_controller.value > 0.5 ? 1.0 : 0.0));
    _controller.animateTo(target, curve: Curves.easeOutCubic);
  }

  void _handleTap() {
    if (_controller.value > 0.01) {
      _close();
    } else {
      widget.onTap?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: widget.borderRadius,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  for (final action in widget.actions)
                    _SwipeActionButton(
                      action: action,
                      width: widget.actionWidth,
                      onTap: () {
                        action.onTap();
                        if (action.closesRow) _close();
                      },
                    ),
                ],
              ),
            ),
          ),
          // The slide is *outside* the detector, not inside it. Inside, the
          // detector kept the row's full untranslated width and — being opaque,
          // and painted after the actions — swallowed every tap over the
          // revealed strip: the buttons could be looked at but not pressed, and
          // hitting one only ran [_handleTap] and closed the row again.
          // Translating the detector itself moves its hit box out from over
          // them, so the strip belongs to the buttons and the rest of the row
          // still takes the tap that closes it.
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) => Transform.translate(
              offset: Offset(-_actionsWidth * _controller.value, 0),
              child: child,
            ),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: _onDragUpdate,
              onHorizontalDragEnd: _onDragEnd,
              onTap: _handleTap,
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}

class _SwipeActionButton extends StatelessWidget {
  final SwipeAction action;
  final double width;
  final VoidCallback onTap;

  const _SwipeActionButton({required this.action, required this.width, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        alignment: Alignment.center,
        color: action.color,
        child: Icon(action.icon, size: 18, color: Colors.white),
      ),
    );
  }
}
