import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../l10n/l10n.dart';
import '../theme/tokens.dart';
import 'bottom_nav.dart';
import 'glass.dart';

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
ConfirmChip confirmChipOf(BuildContext context) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  // Parked clear of whichever nav bar is up, with the bigger gap a *stationary*
  // floating control needs — see [navContentInset]. Read here rather than at
  // show time, since the context may be gone by then.
  final bottomInset = navContentInset(context, pill: 108, gap: 22);

  void show(String message, {UndoRestore? undo}) =>
      _show(messenger, bottomInset, message, ToastKind.confirm, undo);

  return show;
}

/// Shows one from a context that is still around — the error path, and anything
/// whose result doesn't move the user off the screen.
void showToast(BuildContext context, String message, {ToastKind kind = ToastKind.confirm}) {
  _show(ScaffoldMessenger.maybeOf(context), navContentInset(context, pill: 108, gap: 22), message, kind, null);
}

void _show(ScaffoldMessengerState? messenger, double bottomInset, String message, ToastKind kind, UndoRestore? undo) {
  if (messenger == null || !messenger.mounted) return;
  if (kind == ToastKind.confirm) {
    // A light tap, the same weight iOS gives a completed action. Deliberately
    // not the heavy notification feedback: nothing here was risky enough. A
    // failure gets none at all — the message is the point, and buzzing over bad
    // news reads as a scolding.
    HapticFeedback.lightImpact();
  }

  void onUndo() {
    messenger.hideCurrentSnackBar();
    undo!().then((ok) {
      if (ok) _show(messenger, bottomInset, L.s.restored, ToastKind.confirm, null);
    });
  }

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        // The `SnackBar` is only the carrier — the visible thing is the capsule
        // below, which has to hug its text rather than span the display the way
        // a bar would. `width:` can't do that (it wants a number), so the bar
        // itself goes transparent and the chip centres inside it.
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        // Load-bearing, and the reason the pill used to sit in a rectangular
        // smudge: a `SnackBar` clips its child to its own (barely rounded)
        // shape by default, which cut the capsule's soft drop shadow off along
        // four straight edges. It would also crop the native glass view.
        clipBehavior: Clip.none,
        margin: EdgeInsets.fromLTRB(16, 0, 16, bottomInset),
        // Long enough to read the failure and to reach for "Rückgängig";
        // a bare confirmation is gone before it can become clutter.
        duration: Duration(milliseconds: undo != null ? 5000 : (kind == ToastKind.error ? 4000 : 1900)),
        content: Center(
          child: _ToastChip(message: message, kind: kind, undo: undo, onUndo: undo == null ? null : onUndo),
        ),
      ),
    );
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
      // and floods the material. The Flutter-drawn fallback needs a light one
      // to keep the dark label legible — the same tint the nav pill uses, so
      // the two floating surfaces read as one material.
      fallbackTint: AppColors.navPillTint,
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
              child: Icon(
                kind == ToastKind.confirm ? LucideIcons.check : LucideIcons.x,
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
