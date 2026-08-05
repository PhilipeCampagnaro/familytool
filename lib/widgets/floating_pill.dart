import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../l10n/l10n.dart';
import '../theme/tokens.dart';
import 'glass.dart';

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
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  const FloatingGlassPill({
    super.key,
    required this.visible,
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  @override
  State<FloatingGlassPill> createState() => _FloatingGlassPillState();
}

class _FloatingGlassPillState extends State<FloatingGlassPill> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
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
                borderRadius: BorderRadius.circular(22),
                // Same reasoning as _CalendarFilterButton: let the real
                // UIGlassEffect adapt on iOS, tint only the fallback so the
                // dark label stays legible off-iOS.
                fallbackTint: AppColors.navPillTint,
                blurSigma: 20,
                boxShadow: AppShadows.floatingPill,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(widget.icon, size: 15, color: widget.accent),
                      const SizedBox(width: 7),
                      Text(widget.label, style: AppText.buttonSmall.copyWith(fontWeight: FontWeight.w600)),
                    ],
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
      icon: LucideIcons.undo2,
      label: L.s.undo,
      accent: widget.accent,
      onTap: _undo,
    );
  }
}
