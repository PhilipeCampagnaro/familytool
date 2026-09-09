import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/l10n.dart';
import '../theme/tokens.dart';
import 'bottom_nav.dart';
import 'glass.dart';
import '../theme/app_icons.dart';

/// The app's transient feedback pill, in the **one** shape both halves of it
/// share: a liquid-glass capsule floating clear of the nav bar, a coloured disc
/// on the left, one line of copy, and — on a delete — the undo action.
///
/// Success and failure differ by the disc's colour and glyph and by nothing
/// else. They used to be two different objects (a hugging white pill vs. a
/// full-width grey bar with a red glyph), which read as two unrelated systems
/// for what is the same event: "the write you just made either landed or it
/// didn't".
///
/// The **message** always arrives resolved through `L.s`, because it says what
/// happened to a list or an appointment and only the notifier that did it knows
/// that. The chip's own two words — "Rückgängig" and "Wiederhergestellt" —
/// belong to the widget and are read here, the same way [ErrorNote] reads
/// "Erneut laden".
enum ToastKind { confirm, error }

/// What "Rückgängig" runs. False means the restore failed, and nothing further
/// is shown here — the notifier has already put the reason on `state.error`,
/// which every screen turns into an error chip of its own.
typedef UndoRestore = Future<bool> Function();

/// A confirmation bound to a context that may not survive the write.
typedef ConfirmChip = void Function(String message, {UndoRestore? undo});

/// Captures everything the chip needs **now**, so it can still be shown after
/// the `await`.
///
/// Deliberately not a plain `showToast(context, …)`: half the callers are
/// deletions that unmount the very widget they were tapped in — the row, the
/// menu, the whole detail view — so by the time the write returns there is no
/// context left to show anything from, and a `context.mounted` check would
/// swallow the confirmation in exactly the case that most deserves one. Take
/// this *before* starting the write, call it after.
ConfirmChip confirmChipOf(BuildContext context, {ToastKind kind = ToastKind.confirm}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  // Parked clear of whichever nav bar is up, with the bigger gap a *stationary*
  // floating control needs — see [navContentInset]. Read here rather than at
  // show time, since the context may be gone by then.
  final bottomInset = navContentInset(context, pill: 108, gap: 22);

  void show(String message, {UndoRestore? undo}) => _show(overlay, bottomInset, message, kind, undo);

  return show;
}

/// Shows one from a context that is still around — the error path, and anything
/// whose result doesn't move the user off the screen.
void showToast(BuildContext context, String message, {ToastKind kind = ToastKind.confirm}) {
  _show(
    Overlay.maybeOf(context, rootOverlay: true),
    navContentInset(context, pill: 108, gap: 22),
    message,
    kind,
    null,
  );
}

/// The chip that is currently up, if any. Showing a second one takes the first
/// down rather than stacking them — two capsules in the same place would cover
/// each other's undo.
_ToastHandle? _current;

/// **The root [Overlay], not the [ScaffoldMessenger] this used to be.**
///
/// A `SnackBar` is a slot in the `Scaffold`, and the `Scaffold` belongs to the
/// shell route — so anything opened over that route covers the chip and its
/// scrim dims what is left. Creating a list from an appointment is exactly that
/// case: the create sheet pops, the *event* sheet is still up, and "Liste
/// erstellt" was drawn behind it where nobody ever saw it. A confirmation has to
/// outrank whatever put the write in motion, so it goes in the root overlay,
/// above every route, and the same move is what lets a delete inside a sheet
/// offer its undo.
void _show(OverlayState? overlay, double bottomInset, String message, ToastKind kind, UndoRestore? undo) {
  if (overlay == null || !overlay.mounted) return;
  if (kind == ToastKind.confirm) {
    // A light tap, the same weight iOS gives a completed action. Deliberately
    // not the heavy notification feedback: nothing here was risky enough. A
    // failure gets none at all — the message is the point, and buzzing over bad
    // news reads as a scolding.
    HapticFeedback.lightImpact();
  }

  _current?.dismiss();
  final handle = _ToastHandle();
  _current = handle;

  void onUndo() {
    handle.dismiss();
    undo!().then((ok) {
      if (ok) _show(overlay, bottomInset, L.s.restored, ToastKind.confirm, null);
    });
  }

  handle.insert(
    overlay,
    (context) => _ToastLayer(
      key: handle.key,
      bottomInset: bottomInset,
      // Long enough to read the failure and to reach for "Rückgängig";
      // a bare confirmation is gone before it can become clutter.
      stay: Duration(milliseconds: undo != null ? 5000 : (kind == ToastKind.error ? 4000 : 1900)),
      onGone: handle.remove,
      child: _ToastChip(message: message, kind: kind, undo: undo, onUndo: undo == null ? null : onUndo),
    ),
  );
}

/// One shown chip, from insertion to the frame after it has faded out.
///
/// The handle is what an *outsider* can do to a chip — take it down — and the
/// [GlobalKey] is how: the layer owns the animation, so dismissing means asking
/// it to run that animation backwards rather than yanking the entry out from
/// under it.
class _ToastHandle {
  final GlobalKey<_ToastLayerState> key = GlobalKey<_ToastLayerState>();
  OverlayEntry? _entry;

  void insert(OverlayState overlay, WidgetBuilder builder) {
    _entry = OverlayEntry(builder: builder);
    overlay.insert(_entry!);
  }

  /// Nothing on screen yet (inserted this same frame) means there is no
  /// animation to reverse, so it goes straight out.
  void dismiss() {
    final layer = key.currentState;
    if (layer == null) {
      remove();
      return;
    }
    layer.hide();
  }

  void remove() {
    _entry?.remove();
    _entry = null;
    if (identical(_current, this)) _current = null;
  }
}

/// The chip's place on screen and its coming and going.
///
/// Positioned rather than laid out, because an overlay entry is a `Stack` child
/// with the whole screen to itself: the capsule hugs its text in the middle of
/// the strip and everything either side of it stays tappable.
class _ToastLayer extends StatefulWidget {
  final double bottomInset;
  final Duration stay;
  final VoidCallback onGone;
  final Widget child;

  const _ToastLayer({
    super.key,
    required this.bottomInset,
    required this.stay,
    required this.onGone,
    required this.child,
  });

  @override
  State<_ToastLayer> createState() => _ToastLayerState();
}

class _ToastLayerState extends State<_ToastLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    reverseDuration: const Duration(milliseconds: 170),
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  Timer? _timer;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _timer = Timer(widget.stay, hide);
  }

  /// Runs the entrance backwards and hands the entry back to be removed. Safe
  /// to call twice — the undo label calls it, and so does the timer that was
  /// already running when it was tapped.
  void hide() {
    if (_leaving || !mounted) return;
    _leaving = true;
    _timer?.cancel();
    // A cancelled ticker completes this future rather than failing it, so a
    // chip torn down mid-fade still gets its entry removed.
    _controller.reverse().whenComplete(widget.onGone);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // Above the keyboard while one is up and clear of the home indicator when
    // it isn't — the two cases the `Scaffold` used to handle for the floating
    // snack bar this replaced.
    final bottom = math.max(media.viewInsets.bottom, media.viewPadding.bottom) + widget.bottomInset;
    return Positioned(
      left: 16,
      right: 16,
      bottom: bottom,
      child: FadeTransition(
        opacity: _curve,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero).animate(_curve),
          // Read out the moment it appears, which the snack bar did for free.
          child: Semantics(
            liveRegion: true,
            container: true,
            child: Center(child: widget.child),
          ),
        ),
      ),
    );
  }
}

class _ToastChip extends StatelessWidget {
  final String message;
  final ToastKind kind;
  final UndoRestore? undo;
  final VoidCallback? onUndo;

  const _ToastChip({required this.message, required this.kind, this.undo, this.onUndo});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GlassSurface(
      // A capsule, like every other floating glass control — it's also what the
      // native effect view renders anyway (`cornerConfiguration = .capsule()`).
      borderRadius: BorderRadius.circular(999),
      // No forced `tint`: it goes straight to `UIGlassEffect.tintColor` on iOS
      // and floods the material. The Flutter-drawn approximation takes the
      // default light material instead — the same one the nav pill draws, so
      // the two floating surfaces read as one.
      blurSigma: 24,
      boxShadow: AppShadows.floatingPill,
      // `UIGlassEffect.isInteractive` is the material's own press reaction, and
      // this isn't a control: the chip appears and leaves by itself, and the one
      // thing in it you can press is a label. (Flutter hit-testing is
      // unaffected either way — the platform view never takes a touch.)
      interactive: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 9, undo == null ? 16 : 6, 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A filled disc rather than a bare glyph: at this size the icon
            // alone gets lost against the material, and the colour reads before
            // the text does. Colour and glyph are the *only* thing that
            // separates a confirmation from a failure.
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: kind == ToastKind.confirm ? AppColors.success : AppColors.danger,
                shape: BoxShape.circle,
              ),
              child: AppIcon(
                kind == ToastKind.confirm ? AppIcons.check : AppIcons.x,
                size: 13,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 9),
            // Two lines, not one: a confirmation is two words and a failure is a
            // whole sentence, and ellipsising the sentence would cut off the
            // half that says what to do about it.
            Flexible(
              child: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.buttonSmall),
            ),
            if (undo != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onUndo,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: Text(L.s.undo, style: AppText.buttonSmall.copyWith(color: accent)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
