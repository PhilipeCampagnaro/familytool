import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../theme/tokens.dart';
import 'bottom_nav.dart';
import 'glass.dart';
import '../theme/app_icons.dart';

/// A liquid-glass pill parked above the bottom nav that comes and goes with the
/// state behind it — the calendar's "Heute" button, Board's and Listen's
/// "Rückgängig". It slides up out of the bar and fades in, and presses like the
/// other floating glass controls.
///
/// It only draws itself: the caller owns the position, which is always
/// `Positioned(left: 0, right: 0, bottom: navContentInset(context, pill: 106,
/// gap: 36))` around a [Center] — the bigger `gap:` a *parked* control needs so
/// it doesn't read as hiding behind the bar (see `bottom_nav.dart`).
class FloatingGlassPill extends StatefulWidget {
  final bool visible;

  /// Null draws the label on its own. That is what "Heute" does: it sits a
  /// finger's width from the nav bar's calendar icon, and a second calendar
  /// glyph beside that one reads as a duplicate of it rather than as a
  /// different offer.
  final IconData? icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  /// Sizes the capsule to the nav bar's row — the height of `CompactNavButton`
  /// at the other end of it — instead of the smaller shape that parks above
  /// the bar.
  final bool onNavRow;

  const FloatingGlassPill({
    super.key,
    required this.visible,
    this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
    this.onNavRow = false,
  });

  @override
  State<FloatingGlassPill> createState() => _FloatingGlassPillState();
}

class _FloatingGlassPillState extends State<FloatingGlassPill> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  /// Icon (when there is one), then label. The row shape gets the larger type:
  /// it is a taller capsule standing beside the nav bar, not a small pill
  /// floating over the content.
  Widget _content({required bool rowShape}) {
    final icon = widget.icon;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          AppIcon(icon, size: rowShape ? 18 : 15, color: widget.accent, flat: true),
          const SizedBox(width: 7),
        ],
        Text(
          widget.label,
          // The row shape keeps [AppText.rowTitle]'s own weight: at 15pt in a
          // capsule this tall, the semibold the small pill uses reads as
          // shouting.
          style: rowShape ? AppText.rowTitle : AppText.buttonSmall.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      child: IgnorePointer(
        ignoring: !widget.visible,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          offset: widget.visible ? Offset.zero : const Offset(0, 0.7),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            opacity: widget.visible ? 1 : 0,
            child: GestureDetector(
              onTap: widget.onTap,
              onTapDown: (_) => _setPressed(true),
              onTapUp: (_) => _setPressed(false),
              onTapCancel: () => _setPressed(false),
              child: AnimatedScale(
                scale: _pressed ? 0.92 : 1.0,
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                child: GlassSurface(
                  borderRadius: BorderRadius.circular(widget.onNavRow ? kCompactNavSize / 2 : 22),
                  // Same reasoning as _CalendarFilterButton: let the real
                  // UIGlassEffect adapt on iOS, tint only the fallback so the
                  // dark label stays legible off-iOS.
                  fallbackTint: AppColors.navPillTint,
                  blurSigma: 20,
                  boxShadow: AppShadows.floatingPill,
                  child: widget.onNavRow
                      ? SizedBox(
                          height: kCompactNavSize,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 22),
                            child: _content(rowShape: true),
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                          child: _content(rowShape: false),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// How long "Rückgängig" stays reachable after a row has been ticked off — the
/// same window the toast chip's undo gets, since it is the same offer.
const _undoWindow = Duration(seconds: 5);

/// The undo half of check-off: a [FloatingGlassPill] that appears for
/// [_undoWindow] whenever a row moves into "Erledigt", and puts it back.
///
/// Driven by [token] — the id of the row that just travelled *down*, or `''` for
/// "nothing to undo". The screens read that off `state.justMoved` plus the
/// row's `done` flag rather than calling anything imperatively, so a check-off
/// made anywhere on the screen raises the pill. Undoing (from the pill or from
/// the "Erledigt" row itself) clears the token, which takes the pill with it —
/// the offer is gone because it has been taken.
///
/// A token that is already up when this mounts shows nothing: Listen's detail
/// view is built fresh every time a list is opened, and a pill for an article
/// ticked off ten minutes ago would be an undo the user never asked about.
class UndoPill extends StatefulWidget {
  final String token;
  final Color accent;
  final VoidCallback onUndo;

  const UndoPill({super.key, required this.token, required this.accent, required this.onUndo});

  @override
  State<UndoPill> createState() => _UndoPillState();
}

class _UndoPillState extends State<UndoPill> {
  bool _visible = false;
  Timer? _timer;

  @override
  void didUpdateWidget(UndoPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only a *change* of token is an event. Rebuilds carrying the same one
    // (every keystroke in the add row, every arriving reload) must not restart
    // the countdown on a pill that is already on its way out.
    if (widget.token == oldWidget.token) return;
    _timer?.cancel();
    if (widget.token.isEmpty) {
      _hide();
      return;
    }
    setState(() => _visible = true);
    _timer = Timer(_undoWindow, _hide);
  }

  void _hide() {
    if (!mounted || !_visible) return;
    setState(() => _visible = false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _undo() {
    _timer?.cancel();
    // Taken, so it goes at once rather than after the write — which is what the
    // row's own animation does too.
    setState(() => _visible = false);
    HapticFeedback.lightImpact();
    widget.onUndo();
  }

  @override
  Widget build(BuildContext context) {
    return FloatingGlassPill(
      visible: _visible,
      icon: AppIcons.arrowUUpLeft,
      label: L.s.undo,
      accent: widget.accent,
      onTap: _undo,
    );
  }
}
