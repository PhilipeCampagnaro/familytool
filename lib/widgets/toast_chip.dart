import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/l10n.dart';
import '../state/nav_state.dart';
import '../theme/tokens.dart';
import 'bottom_nav.dart';
import 'glass.dart';
import '../theme/app_icons.dart';

/// The app's transient feedback pill, in the **one** shape both halves of it
/// share: a liquid-glass capsule floating clear of the nav bar, a coloured ring
/// on the left, one line of copy, and — on a delete — the undo action.
///
/// Success and failure differ by the ring's colour and glyph and by nothing
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
///
/// [pending] is the odd one out and the reason the chip can now change while it
/// is up: it says a write is *in flight*, so it carries a spinner instead of a
/// mark and no timer at all. It leaves when the caller says it does — by
/// settling into a [confirm] or an [error] in the same capsule, which is what
/// makes the tick read as the answer to the spinner rather than as a second,
/// unrelated chip.
enum ToastKind { confirm, error, pending }

/// What "Rückgängig" runs. False means the restore failed, and nothing further
/// is shown here — the notifier has already put the reason on `state.error`,
/// which every screen turns into an error chip of its own.
typedef UndoRestore = Future<bool> Function();

/// How high the chip floats above the nav bar's own top edge.
///
/// Small on purpose: the chip is the bar's answer to what was just tapped, and
/// the gap is what says so. It used to be derived from [navContentInset], which
/// is the clearance *scrolling* content needs — a bar's height plus a generous
/// 22 — and which was also being added to the home indicator a second time. That
/// parked the capsule the better part of a bar's height clear of it, reading as
/// something that had drifted in from elsewhere on the screen.
const _chipGap = 14.0;

/// Where the chip sits when there is **no** bar to answer to — a sheet or a
/// pushed page covers the shell. The least room the home indicator leaves, on
/// a display that has one; see [NavBarState.onScreen].
const _chipFloor = 16.0;

/// Where the chip's bottom edge sits, measured from the bottom of the display.
///
/// Read at the moment the chip is *ordered* rather than when it is shown, like
/// everything else in this file: half the callers have no context left by then.
/// The bar's measured height comes off [navBarProvider] through the container
/// rather than a `ref`, because [confirmChipOf] is handed a bare context — the
/// callers that need it most are `Future`s in notifiers and menu handlers, and
/// the fallback constant is what put the chip *under* an iOS 26 capsule.
double _chipBottom(BuildContext context) =>
    navBarTop(
      context,
      barHeight: ProviderScope.containerOf(context, listen: false).read(navBarProvider).barHeight,
    ) +
    _chipGap;

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
  // Parked just clear of whichever nav bar is up — see [_chipBottom].
  final bottomInset = _chipBottom(context);

  void show(String message, {UndoRestore? undo}) => _show(overlay, bottomInset, message, kind, undo);

  return show;
}

/// Shows one from a context that is still around — the error path, and anything
/// whose result doesn't move the user off the screen.
void showToast(BuildContext context, String message, {ToastKind kind = ToastKind.confirm}) {
  _show(
    Overlay.maybeOf(context, rootOverlay: true),
    _chipBottom(context),
    message,
    kind,
    null,
  );
}

/// One line of chip, with everything the capsule draws.
///
/// A record rather than a built widget: swapping the *widget* would tear down
/// [GlassSurface] and build a second one, and on iOS that is a platform view —
/// two of them cross-fading in the same place is a flicker, not a transition.
/// The capsule stays put and only its contents change.
class _ToastContent {
  final String message;
  final ToastKind kind;
  final UndoRestore? undo;
  final VoidCallback? onUndo;

  /// The word on the action, when it is not "Rückgängig". An offer rather than
  /// a reversal — see [showActionToast].
  final String? actionLabel;

  /// Takes the chip down by hand. Non-null **only** on a chip with no timer:
  /// an X beside something that is leaving on its own is a race between the
  /// reader and the animation.
  final VoidCallback? onClose;

  const _ToastContent(
    this.message,
    this.kind, {
    this.undo,
    this.onUndo,
    this.actionLabel,
    this.onClose,
  });
}

/// A chip that is on screen **now**, with the write it describes still running.
///
/// Handed back by [showPendingChip] so a long write can say where it has got
/// to. Every method is safe once the chip is gone, and safe when there was no
/// overlay to put one in — a missing confirmation must never take the write
/// down with it.
class PendingChip {
  PendingChip._(this._handle, this._overlay, this._bottomInset);

  final _ToastHandle _handle;
  final OverlayState? _overlay;
  final double _bottomInset;

  /// Rewrites the line without taking the chip down or restarting anything —
  /// the spinner keeps turning through it. For a write that runs in stages the
  /// user can name.
  void step(String message) => _handle.swap(_ToastContent(message, ToastKind.pending));

  /// The write landed: the spinner becomes a tick, the line becomes the past
  /// tense, and the capsule starts the fade-out an ordinary confirmation gets.
  ///
  /// [undo] is for a delete, which is the write that most wants a spinner *and*
  /// an undo: the row leaves the grid immediately, the provider takes its
  /// seconds, and "Rückgängig" cannot be offered until there is something to
  /// undo. It settles into the same capsule for the same reason every other
  /// answer does — a fresh chip appearing beside the one that was already up
  /// reads as two writes.
  void done(String message, {UndoRestore? undo}) {
    final content = _confirmContent(_handle, _overlay, _bottomInset, message, undo);
    if (!_handle.swap(content, stay: undo != null ? _undoStay : _confirmStay)) {
      // Nothing up any more — the chip was displaced by another one, or never
      // got an overlay. The confirmation is still owed, so show a fresh one.
      _show(_overlay, _bottomInset, message, ToastKind.confirm, undo);
      return;
    }
    HapticFeedback.lightImpact();
  }

  /// Same swap, the other answer.
  void failed(String message) {
    if (!_handle.swap(_ToastContent(message, ToastKind.error), stay: _errorStay)) {
      _show(_overlay, _bottomInset, message, ToastKind.error, null);
    }
  }

  /// Takes it down with nothing in its place — for a write that ended without
  /// anything worth saying, such as one the user cancelled.
  void dismiss() => _handle.dismiss();
}

/// Puts a chip up and leaves it up. See [PendingChip].
///
/// Captures the overlay before the write starts, exactly as [confirmChipOf]
/// does and for the same reason: the sheet that started it is usually gone by
/// the time there is anything to report.
PendingChip showPendingChip(BuildContext context, String message) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  final bottomInset = _chipBottom(context);

  _current?.dismiss();
  final handle = _ToastHandle();
  _current = handle;

  if (overlay != null && overlay.mounted) {
    handle.insert(
      overlay,
      (context) => _ToastLayer(
        key: handle.key,
        bottomInset: bottomInset,
        // No timer: a spinner that times out would leave the user certain the
        // write had finished, at the one moment it demonstrably hasn't.
        stay: null,
        onGone: handle.remove,
        content: _ToastContent(message, ToastKind.pending),
      ),
    );
  }
  return PendingChip._(handle, overlay, bottomInset);
}

/// An **offer**, in the capsule the app already uses for answers.
///
/// Same shape as a confirmation with "Rückgängig" on it, and deliberately so:
/// there is one transient surface in this app and a second one for suggestions
/// would be a notification system. The difference is only the word on the
/// action and that nothing has happened yet.
///
/// **Use it sparingly.** A chip that appears without being asked for is an
/// interruption, and the only one worth making is the one the reader was
/// obviously about to do by hand.
void showActionToast(
  BuildContext context,
  String message, {
  required String actionLabel,
  required VoidCallback onAction,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  final bottomInset = _chipBottom(context);
  if (overlay == null || !overlay.mounted) return;

  _current?.dismiss();
  final handle = _ToastHandle();
  _current = handle;
  handle.insert(
    overlay,
    (context) => _ToastLayer(
      key: handle.key,
      bottomInset: bottomInset,
      // **No timer.** See the note on [_ToastContent.onClose]: this is a
      // question, and the reader closes it or answers it.
      stay: null,
      onGone: handle.remove,
      content: _ToastContent(
        message,
        ToastKind.confirm,
        actionLabel: actionLabel,
        onUndo: () {
          handle.dismiss();
          onAction();
        },
        onClose: handle.dismiss,
      ),
    ),
  );
}

/// How long a settled chip stays. Kept beside [_show]'s own figures so the two
/// ways of getting a confirmation on screen agree.
const _confirmStay = Duration(milliseconds: 1900);
const _errorStay = Duration(milliseconds: 4000);

/// Long enough to read the line *and* reach for "Rückgängig"; a bare
/// confirmation is gone before it can become clutter.
const _undoStay = Duration(milliseconds: 5000);

/// The settled line, with its undo wired up if it has one.
///
/// Shared by the two ways a confirmation reaches the screen — [_show] builds a
/// fresh chip, [PendingChip.done] rewrites a spinner into one — so that the undo
/// behaves identically either way. Tapping it keeps the capsule and turns it
/// back into a spinner: the restore is a write of its own, and the chip is the
/// only place its answer can land.
_ToastContent _confirmContent(
  _ToastHandle handle,
  OverlayState? overlay,
  double bottomInset,
  String message,
  UndoRestore? undo, {
  ToastKind kind = ToastKind.confirm,
}) {
  if (undo == null) return _ToastContent(message, kind);
  void onUndo() {
    // **The restore is a write, and it takes the same seconds the one it undoes
    // did.** So the capsule becomes a spinner in place rather than leaving
    // altogether — a chip that vanished on the tap and reappeared saying
    // "Wiederhergestellt" two seconds later left the tap looking like it had
    // done nothing. The swap drops the undo label with it, which is right: it
    // has already been used.
    final holding = handle.swap(_ToastContent(L.s.beingRestored, ToastKind.pending));
    undo().then((ok) {
      if (!ok) {
        // The notifier has already put the reason on `state.error` and every
        // screen draws that itself.
        handle.dismiss();
        return;
      }
      // Confirm regardless of [kind]: whatever the chip the undo hung off was
      // reporting, the restore landing is good news.
      if (!holding || !handle.swap(_ToastContent(L.s.restored, ToastKind.confirm), stay: _confirmStay)) {
        // The chip was gone or was displaced while the restore ran; the answer
        // is still owed, so it gets a fresh one — [_show] taps for itself.
        _show(overlay, bottomInset, L.s.restored, ToastKind.confirm, null);
        return;
      }
      HapticFeedback.lightImpact();
    });
  }

  return _ToastContent(message, kind, undo: undo, onUndo: onUndo);
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

  handle.insert(
    overlay,
    (context) => _ToastLayer(
      key: handle.key,
      bottomInset: bottomInset,
      stay: undo != null ? _undoStay : (kind == ToastKind.error ? _errorStay : _confirmStay),
      onGone: handle.remove,
      content: _confirmContent(handle, overlay, bottomInset, message, undo, kind: kind),
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

  /// Changes what the capsule says without taking it down, optionally starting
  /// the fade-out timer it has been doing without.
  ///
  /// False when there was nothing to change — no overlay, or the chip has
  /// already left or been displaced by a newer one. The caller decides what
  /// that means; a confirmation still owed puts up a fresh chip instead.
  bool swap(_ToastContent content, {Duration? stay}) {
    final layer = key.currentState;
    if (layer == null) return false;
    return layer.swap(content, stay: stay);
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
class _ToastLayer extends ConsumerStatefulWidget {
  final double bottomInset;

  /// How long it stays before fading out, or **null** for a chip that waits to
  /// be told — which is what [ToastKind.pending] is.
  final Duration? stay;

  final VoidCallback onGone;
  final _ToastContent content;

  const _ToastLayer({
    super.key,
    required this.bottomInset,
    required this.stay,
    required this.onGone,
    required this.content,
  });

  @override
  ConsumerState<_ToastLayer> createState() => _ToastLayerState();
}

class _ToastLayerState extends ConsumerState<_ToastLayer> with SingleTickerProviderStateMixin {
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

  /// What the capsule currently says. Held in the State rather than read off
  /// the widget because a pending chip changes it while the same overlay entry
  /// stays on screen.
  late _ToastContent _content = widget.content;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    final stay = widget.stay;
    if (stay != null) _timer = Timer(stay, hide);
  }

  /// See [_ToastHandle.swap]. False once the chip is on its way out — there is
  /// nothing left to rewrite, and reviving it mid-fade would look like a second
  /// chip appearing.
  bool swap(_ToastContent content, {Duration? stay}) {
    if (_leaving || !mounted) return false;
    setState(() => _content = content);
    _timer?.cancel();
    _timer = stay == null ? null : Timer(stay, hide);
    return true;
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
    //
    // **The two cases don't add up.** [bottomInset] is the room the nav bar
    // needs, and a keyboard covers the nav bar: stacking one on the other
    // parked the chip a bar's height and a home indicator above the keys,
    // floating in the middle of the list it had just changed. While the
    // keyboard is up it is the only thing to clear, and the chip sits just
    // above it — close enough to read as the answer to what was typed.
    //
    // **And [bottomInset] is already measured from the bottom of the display**,
    // which is the second thing that didn't add up: [_chipBottom] starts at the
    // same screen edge the bar itself is positioned from ([navRowBottom],
    // `barBottom` in `main.dart`) and counts the safe area in on the way past,
    // so adding `viewPadding.bottom` to it put the home indicator in twice. On
    // a 34pt indicator that is 34pt of daylight between the chip and the bar it
    // belongs to, and the chip read as floating loose over the screen rather
    // than as the bar's own answer.
    //
    // **And [bottomInset] only means something while the bar is there.** Over
    // a sheet or a pushed page the bar is gone, and a chip still parked above
    // where it would be hung in the middle of the page — over the very row the
    // next delete wanted, until it faded. So it drops to the bottom edge while
    // the bar is covered and rises back when it returns, read live rather than
    // at the order: a delete from an event's sheet orders the chip with the
    // sheet up and shows it after the sheet has gone. Eased rather than jumped,
    // and only that half — the keyboard's own animation drives the other.
    final keyboard = media.viewInsets.bottom;
    final barOnScreen = ref.watch(navBarProvider.select((s) => s.onScreen));
    final floor = math.max(media.viewPadding.bottom, _chipFloor);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: barOnScreen ? widget.bottomInset : floor),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, parked, child) => Positioned(
        left: 16,
        right: 16,
        bottom: keyboard > 0 ? keyboard + 12 : parked,
        child: child!,
      ),
      child: FadeTransition(
        opacity: _curve,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero).animate(_curve),
          // Read out the moment it appears, which the snack bar did for free.
          child: Semantics(
            liveRegion: true,
            container: true,
            // **The chip is the one text in the app with no [Material] over
            // it.** A raw overlay entry has none, and Flutter's fallback for
            // that case is its debug style: yellow, double-underlined. The
            // chip's own styles set the size, weight and colour but not the
            // decoration, so the underline came through under the message, the
            // undo and every word either carried. Declared once here rather
            // than on each [Text], so anything the chip grows later inherits
            // it too.
            child: DefaultTextStyle(
              style: AppText.buttonSmall.copyWith(decoration: TextDecoration.none),
              // The capsule hugs its text, and a pending chip's text changes
              // under it — "Termin wird in Familie angelegt" is not the width
              // of "Termin erstellt". Animated so the glass grows and shrinks
              // into place instead of stepping between two sizes.
              child: Center(
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: _ToastChip(content: _content),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToastChip extends StatelessWidget {
  final _ToastContent content;

  const _ToastChip({required this.content});

  String get message => content.message;
  ToastKind get kind => content.kind;
  UndoRestore? get undo => content.undo;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final mark = kind == ToastKind.error ? AppColors.danger : AppColors.success;
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
            // A ring rather than a bare glyph: at this size the icon alone
            // gets lost against the material, and the colour reads before the
            // text does. Outlined rather than filled, on a wash of its own
            // colour — the same mark the confirmation sheet draws, so the
            // capsule and the sheet are recognisably one family instead of a
            // solid dot and a drawn circle saying the same thing two ways.
            // Colour and glyph are the *only* thing that separates a
            // confirmation from a failure.
            //
            // While the write is still out there the slot holds a spinner
            // instead — the same 20 points, so the capsule doesn't jump when
            // the answer arrives and the tick takes the turning ring's place.
            // Cross-faded rather than swapped outright, which is what makes
            // the two read as one chip answering itself.
            SizedBox(
              width: 20,
              height: 20,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: kind == ToastKind.pending
                    ? SizedBox(
                        key: const ValueKey('pending'),
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 1.8, color: accent),
                      )
                    : Container(
                        key: ValueKey(kind),
                        decoration: BoxDecoration(
                          color: mark.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                          border: Border.all(color: mark, width: 1.5),
                        ),
                        alignment: Alignment.center,
                        child: AppIcon(
                          kind == ToastKind.confirm ? AppIcons.check : AppIcons.x,
                          size: 11,
                          color: mark,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 9),
            // Two lines, not one: a confirmation is two words and a failure is a
            // whole sentence, and ellipsising the sentence would cut off the
            // half that says what to do about it.
            Flexible(
              child: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.buttonSmall),
            ),
            // Gated on the callback rather than on [undo]: an offer has an
            // action and nothing to restore.
            if (content.onUndo != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: content.onUndo,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: Text(
                    content.actionLabel ?? L.s.undo,
                    style: AppText.buttonSmall.copyWith(color: accent),
                  ),
                ),
              ),
            ],
            // **An offer waits.** A confirmation reports something that already
            // happened and is right to leave on its own; an offer is a question,
            // and a question that withdraws itself after five seconds is one the
            // reader has to catch. So the chip with no timer carries the way out
            // instead — the same mark every sheet in the app closes with.
            if (content.onClose case final close?) ...[
              const SizedBox(width: 2),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: close,
                child: Padding(
                  padding: const EdgeInsets.only(left: 2, right: 10, top: 6, bottom: 6),
                  child: AppIcon(
                    AppIcons.x,
                    size: AppGlyph.caret,
                    color: AppColors.muted,
                    flat: true,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
