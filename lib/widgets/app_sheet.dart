import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import 'glass.dart';
import 'toast_chip.dart';
import '../l10n/l10n.dart';
import '../theme/app_icons.dart';

/// Shared bottom-sheet chrome: grab handle, header, then a scrolling body on
/// the F7F8FA sheet background. Matches every sheet/popup across Board,
/// Listen, Box and Kalender — including the calendar's event-detail sheet.
///
/// By default the header is the standard close (X) / [title] / save (check)
/// row. Pass [header] instead for a sheet whose header doesn't fit that
/// shape (e.g. a read-only detail view with no save action) — everything
/// else (backdrop, grab handle, outer chrome, scrolling body container)
/// still comes from this one shared widget.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  String? title,
  Widget? header,
  required Widget child,
  FutureOr<void> Function()? onSave,
  TextEditingController? requiredField,
  FocusNode? requiredFocus,
  double heightFactor = 0.92,
  SheetCollapsingHeader? collapsingHeader,
}) {
  assert(
    collapsingHeader != null || header != null || title != null,
    'showAppSheet needs a title (standard header), a custom header, or a collapsingHeader',
  );
  final navigator = Navigator.of(context);
  return navigator.push(
    _AppSheetRoute<T>(
      capturedThemes: InheritedTheme.capture(from: context, to: navigator.context),
      barrierLabel: MaterialLocalizations.of(context).scrimLabel,
      barrierOnTapHint: MaterialLocalizations.of(
        context,
      ).scrimOnTapHint(MaterialLocalizations.of(context).bottomSheetLabel),
      builder: (ctx) => _AppSheetBody(
        title: title,
        header: header,
        onSave: onSave,
        requiredField: requiredField,
        requiredFocus: requiredFocus,
        heightFactor: heightFactor,
        collapsingHeader: collapsingHeader,
        child: child,
      ),
    ),
  );
}

/// The route [showAppSheet] pushes, in place of `showModalBottomSheet`'s.
///
/// A subclass for one reason: [canTransitionTo] is what wires a route's
/// `secondaryAnimation`, and it is the only place a sheet can say **what** is
/// allowed to push it into the background (see [_CoveredSheet]). Left at the
/// default `true`, a sheet would scale itself back under an anchored menu, a
/// `showDatePicker` dialog or anything else that happens to be pushed over it
/// — none of which is a card laid on top of it.
class _AppSheetRoute<T> extends ModalBottomSheetRoute<T> {
  _AppSheetRoute({
    required super.builder,
    required super.capturedThemes,
    required super.barrierLabel,
    required super.barrierOnTapHint,
  }) : super(
         isScrollControlled: true,
         backgroundColor: Colors.transparent,
         modalBarrierColor: AppColors.scrim,
       );

  @override
  bool canTransitionTo(TransitionRoute<dynamic> nextRoute) => nextRoute is _AppSheetRoute;
}

/// Generic scroll-driven collapsing header for a pinned [SliverPersistentHeader]:
/// [builder] is called with a progress value `t` — 0 fully expanded, 1 fully
/// collapsed — tied directly to scroll offset, so the transition tracks the
/// user's finger instead of playing as a fixed-duration animation. Shared by
/// the Kalender week view's own header and any [SheetCollapsingHeader]-enabled
/// sheet, so both collapse the same way.
class CollapsingSliverHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double expandedHeight;
  final double collapsedHeight;
  final Widget Function(BuildContext context, double t) builder;

  const CollapsingSliverHeaderDelegate({required this.expandedHeight, required this.collapsedHeight, required this.builder});

  @override
  double get minExtent => collapsedHeight;

  @override
  double get maxExtent => expandedHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final currentExtent = (maxExtent - shrinkOffset).clamp(minExtent, maxExtent);
    final range = maxExtent - minExtent;
    final t = range <= 0 ? 1.0 : ((maxExtent - currentExtent) / range).clamp(0.0, 1.0);
    return SizedBox(height: currentExtent, child: builder(context, t));
  }

  @override
  bool shouldRebuild(covariant CollapsingSliverHeaderDelegate oldDelegate) => true;
}

/// Opts a [showAppSheet] sheet into a scroll-collapsing header (see
/// [CollapsingSliverHeaderDelegate]) instead of the fixed [header]/[title]
/// row — the header shrinks toward [collapsedHeight] as the sheet's body is
/// scrolled, letting the gray body grow up to cover it, matching the same
/// behavior as the Kalender week view.
///
/// **Nothing uses this today.** The calendar event-detail sheet did, and gave it
/// back: a sheet is not a screen, so a heading that grows to 23pt over the first
/// card reads as a second screen title, and the frosted backdrop the pinned
/// header needs sits badly under a native glass button inside a modal route.
/// Kept because the mechanism is right for a sheet whose header is more than a
/// title — but reach for [header] first.
class SheetCollapsingHeader {
  final double expandedHeight;
  final double collapsedHeight;
  final Widget Function(BuildContext context, double t) builder;

  const SheetCollapsingHeader({required this.expandedHeight, required this.collapsedHeight, required this.builder});
}

/// How far a covered sheet scales back, and how much of it is left showing
/// above the sheet that covers it.
///
/// The scale is Apple's own number, measured off iOS 18 by Flutter for
/// `CupertinoSheetRoute` (`_kSheetScaleFactor` in `cupertino/sheet.dart`): a
/// background card ends up about 8% narrower. The peek is ours — a strip deep
/// enough to show the 30pt shoulders and nothing else, so what is left of the
/// sheet behind is unmistakably a card edge rather than content somebody might
/// try to read or tap.
const double _coveredScaleBack = 0.0835;
const double _coveredPeek = 14;

/// Every [showAppSheet] sheet currently on screen, in the order they were
/// opened — so a covered sheet can find out how tall the one covering it is.
///
/// A plain module-level list rather than an inherited widget or a provider,
/// because the two sheets are **sibling routes**: neither is an ancestor of the
/// other, so there is no context to inherit through. Each entry is written by
/// its own sheet during layout and read by the sheet below during the covering
/// animation, which is the only time it matters.
final List<_OpenSheet> _openSheets = <_OpenSheet>[];

class _OpenSheet {
  double height = 0;
}

/// A sheet pushed into the background by a second sheet laid over it.
///
/// Two sheets used to sit at the same width, the same 30pt radius and the same
/// white, so a short sheet over a tall one read as two peers rather than as one
/// on top of the other: the back sheet still showed a legible title, a live X
/// and check and a second grab handle above the front one's header. The scrim
/// alone can't fix that — it dims both the same amount.
///
/// So the back sheet **drops until only [_coveredPeek] of it clears the front
/// sheet's top edge**, and scales toward its own top on the way down. What is
/// left is a rounded shoulder slightly narrower than the sheet in front of it:
/// the card-behind-a-card of a system sheet over a full-screen page, which is
/// the stack iOS actually reads as a stack. Scaling alone was tried first,
/// because that is literally what iOS does when a sheet covers a sheet — but
/// iOS is doing it to two sheets of similar height, and ours are 0.92 and 0.58,
/// so all it produced was the same tall sheet, slightly narrower, still showing
/// its whole header.
///
/// [covered] is the route's `secondaryAnimation`, which runs 0 → 1 exactly
/// while the sheet above slides in and reverses as it leaves, so this tracks a
/// drag-to-dismiss of the front sheet rather than playing on its own. Only
/// another [_AppSheetRoute] drives it; a menu or a dialog leaves it at 0.
class _CoveredSheet extends StatefulWidget {
  final Animation<double>? covered;

  /// This sheet's own height, and how tall the one covering it is — null until
  /// the covering sheet has laid itself out, which is a frame or two into the
  /// animation.
  final double height;
  final double? Function() frontHeight;
  final Widget child;

  const _CoveredSheet({
    required this.covered,
    required this.height,
    required this.frontHeight,
    required this.child,
  });

  @override
  State<_CoveredSheet> createState() => _CoveredSheetState();
}

class _CoveredSheetState extends State<_CoveredSheet> {
  /// The last height the sheet above reported. Kept because that sheet leaves
  /// the list the moment it is popped, while this one is still animating back
  /// up — without it the drop would snap to zero halfway through the return.
  double? _front;

  @override
  Widget build(BuildContext context) {
    final animation = widget.covered;
    if (animation == null) return widget.child;
    return AnimatedBuilder(
      animation: animation,
      child: widget.child,
      builder: (context, child) {
        // The curve is read per frame instead of through a `CurvedAnimation`,
        // which would have to be owned and disposed to keep from leaking its
        // status listener. Same pair of curves the Cupertino sheet uses in
        // each direction.
        final curve = animation.status == AnimationStatus.reverse ? Curves.easeInToLinear : Curves.linearToEaseOut;
        final t = curve.transform(animation.value.clamp(0.0, 1.0));
        final front = widget.frontHeight() ?? _front;
        if (front != null) _front = front;
        // Both sheets are anchored to the bottom of the screen, so the gap
        // between their top edges is just the difference in their heights.
        // Negative when the sheet on top is the taller one — it covers this one
        // completely, and there is nothing to move out of the way.
        final drop = front == null ? 0.0 : math.max(0.0, widget.height - front - _coveredPeek);
        // **The two transforms are built at rest as well**, identity, rather
        // than short-circuited with `if (t == 0) return child`. That shortcut
        // changed the *shape* of the tree the moment a second sheet began to
        // cover this one: the builder's slot went from holding the sheet itself
        // to holding a `Transform`, so Flutter unmounted the whole sheet and
        // built it again underneath. Everything the covered sheet had handed
        // out died with it — in particular the `WidgetRef` that the event
        // sheet's rows close over, so tapping the check on a list started from
        // an appointment threw "Cannot use ref after the widget was disposed"
        // before a single byte reached Supabase. Only `filterQuality` is
        // dropped at rest, which is a property change and keeps the element.
        return Transform.translate(
          offset: Offset(0, drop * t),
          child: Transform.scale(
            scale: 1 - _coveredScaleBack * t,
            alignment: Alignment.topCenter,
            filterQuality: t == 0 ? null : FilterQuality.medium,
            child: child,
          ),
        );
      },
    );
  }
}

/// Matches [GlassIconButton]'s default diameter — the sheet header's row height
/// and the room its title has to keep clear on either side.
const double _headerButtonSize = 40;

/// How much screen a sheet leaves above itself once the keyboard has pushed it
/// as tall as it will go — measured from below the status bar, not from the top
/// of the screen. Without it a grown sheet ends exactly on the safe-area line,
/// which reads as a page rather than as something laid over one.
const double _sheetTopGap = 12;

/// The header's blue check, inert while a required name is still empty.
///
/// A create sheet used to save on every tap: the write was refused for having
/// no text, but the chrome had already popped the sheet, so the whole thing
/// read as "I confirmed it and nothing was created". Worse, the placeholder
/// ("Listenname", "Was ist zu tun?") was dark enough to look like a name
/// somebody had already typed, so the tap was made in good faith.
///
/// Greyed rather than hidden: a missing button is a puzzle, a grey one is an
/// answer. Tapping it does nothing at all — the sheet stays open with the
/// field where the user can see it.
class _SaveButton extends StatelessWidget {
  final TextEditingController? requiredField;

  /// The field [requiredField] belongs to, so a tap on the greyed check can put
  /// the cursor in it. Without one the tap is inert, which is the failure this
  /// button was reported for: the sheet looked filled in, the check did nothing
  /// visible, and the tap read as a save.
  final FocusNode? requiredFocus;
  final VoidCallback onSave;
  final IconData icon;

  const _SaveButton({
    required this.requiredField,
    required this.onSave,
    this.requiredFocus,
    this.icon = AppIcons.check,
  });

  @override
  Widget build(BuildContext context) {
    final field = requiredField;
    if (field == null) return GlassConfirmButton(icon: icon, onTap: onSave);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: field,
      builder: (context, value, _) => GlassConfirmButton(
        icon: icon,
        onTap: onSave,
        enabled: value.text.trim().isNotEmpty,
        // The keyboard coming up on the empty name is the whole answer: it says
        // what is missing and puts the cursor there in one move, which no
        // amount of greying does on its own.
        onDisabledTap: () => requiredFocus?.requestFocus(),
      ),
    );
  }
}

class _AppSheetBody extends StatefulWidget {
  final String? title;
  final Widget? header;
  final FutureOr<void> Function()? onSave;
  final TextEditingController? requiredField;
  final FocusNode? requiredFocus;
  final Widget child;
  final double heightFactor;
  final SheetCollapsingHeader? collapsingHeader;

  const _AppSheetBody({
    required this.title,
    required this.header,
    required this.onSave,
    required this.requiredField,
    required this.requiredFocus,
    required this.child,
    required this.heightFactor,
    this.collapsingHeader,
  });

  @override
  State<_AppSheetBody> createState() => _AppSheetBodyState();
}

class _AppSheetBodyState extends State<_AppSheetBody> {
  /// Set by whatever is inside the sheet when it knows the sheet is about to
  /// dismiss itself — see [SheetCountdown].
  final ValueNotifier<Duration?> _countdown = ValueNotifier(null);

  /// This sheet's row in [_openSheets], for as long as it is on screen.
  final _OpenSheet _entry = _OpenSheet();

  @override
  void initState() {
    super.initState();
    _openSheets.add(_entry);
  }

  @override
  void dispose() {
    _openSheets.remove(_entry);
    _countdown.dispose();
    super.dispose();
  }

  /// How tall the sheet immediately above this one is, or null if this is the
  /// top one. Read by [_CoveredSheet] on each frame of the covering animation
  /// rather than pushed, so nothing has to notify a route that has already
  /// built this frame.
  double? _frontSheetHeight() {
    final i = _openSheets.indexOf(_entry);
    if (i < 0 || i + 1 >= _openSheets.length) return null;
    return _openSheets[i + 1].height;
  }

  /// Runs the caller's save and **makes a failure in it visible**.
  ///
  /// Every create sheet in the app hands this an `() async { … }`, and the
  /// chrome pops the moment it is tapped — so the returned Future used to be
  /// dropped on the floor. Anything that threw before the write started took
  /// the write with it and produced *nothing*: no row, no confirmation, no
  /// error. The sheet closing was the only feedback, and closing is what a
  /// successful save looks like — which is how a create that never reached the
  /// server (see [_CoveredSheet]) went unexplained for as long as it did. A
  /// silent failure is worse than the bug behind it.
  ///
  /// [Future.sync] catches both halves — a throw before the first `await` and a
  /// rejected Future after it — and the report goes to two places on purpose:
  /// the chip is what the person in front of the app sees, and
  /// [FlutterError.reportError] is what puts the stack in the console for
  /// whoever is looking.
  void _runSave() {
    final save = widget.onSave;
    if (save == null) return;
    // Taken before the save runs and defensively, because the sheet is popped
    // the instant this returns: after that there is no context to show anything
    // from. If even this throws there is nothing left to report *with*, so the
    // reporting falls back to the console rather than taking the save down.
    ConfirmChip? chip;
    try {
      chip = confirmChipOf(context, kind: ToastKind.error);
    } catch (_) {}
    Future.sync(save).catchError((Object error, StackTrace stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'app_sheet',
          context: ErrorDescription('while running a sheet\'s onSave'),
        ),
      );
      chip?.call(L.s.changeSaveFailed);
    });
  }

  /// Close / [title] / save row.
  ///
  /// A [Stack] with the title painted *first*, not a `Row` with the title as an
  /// `Expanded` sibling between the two buttons — that version shipped, and on
  /// iOS the title was simply invisible on device (it rendered fine in a widget
  /// test, where there are no platform views). [GlassIconButton] is a native
  /// `UIGlassEffect` platform view there, and Flutter content painted between
  /// two of them lands in a composited overlay layer that gets dropped. Painting
  /// the title before either button keeps it in the base layer, and spanning the
  /// full row also makes "centered" mean centered in the bar rather than in
  /// whatever the buttons left over — the same reason [CollapsingScreenTitle]
  /// is built this way (`collapsing_header.dart`).
  Widget _defaultHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: SizedBox(
        height: _headerButtonSize,
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                // Symmetric, so the title stays centered on the sheet even
                // though only one side carries the accent button.
                padding: const EdgeInsets.symmetric(horizontal: _headerButtonSize + 14),
                child: Center(
                  child: Text(widget.title!, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.sheetTitle),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: GlassIconButton(
                icon: AppIcons.x,
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: _SaveButton(
                requiredField: widget.requiredField,
                requiredFocus: widget.requiredFocus,
                onSave: () {
                  _runSave();
                  Navigator.of(context).pop();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // What the keyboard is covering. Flutter's `showModalBottomSheet` never
    // applies `viewInsets` to the sheet it builds, so without this a sheet with
    // a field in it keeps its full height while the keyboard is drawn over the
    // lower half: the field being typed into is underneath, and the body's
    // scroll view — which still believes it has the whole sheet to lay out in —
    // has nothing to scroll, so there is no way to bring the field back. Both
    // halves of the fix are needed. The scroll viewport has to *end* where the
    // keyboard starts (the padding below), or the field can't be scrolled clear
    // of it; and the sheet has to grow by what the keyboard took (the height
    // below), or an 0.92 sheet would be left showing about half of itself.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    // Runs 0 → 1 while a second sheet is laid over this one — see
    // [_CoveredSheet]. It is the same moment [occludedByRoute] reports to the
    // native chrome, which is what makes scaling this safe: by the time it
    // moves, every `UIGlassEffect` inside has already swapped itself for the
    // Flutter approximation, so there is no platform view being transformed.
    final covered = ModalRoute.of(context)?.secondaryAnimation;

    final grayBody = Container(
      // `width: double.infinity` is load-bearing: the enclosing Column centers
      // its children (loose width constraints), so without it the gray panel
      // is only as wide as whatever's inside it. Most sheets hide that — their
      // rows are max-width `Row`s that fill the sheet anyway — but a narrow
      // body (a centered empty state) left the panel floating as a too-narrow
      // slab with white either side.
      width: double.infinity,
      // The keyboard inset goes on the container rather than inside the scroll
      // view, so the gray still paints all the way down behind the keyboard
      // while the part that scrolls stops above it.
      padding: EdgeInsets.fromLTRB(18, 18, 18, 28 + keyboard),
      decoration: BoxDecoration(
        color: AppColors.screenBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [widget.child]),
      ),
    );

    return SheetCountdown(
      remaining: _countdown,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The notch, read off the view rather than the MediaQuery. A modal
          // bottom sheet is built inside
          // `MediaQuery.removePadding(removeTop: true)` — `useSafeArea`
          // defaults to false — so in here `padding.top` *and* `viewPadding.top`
          // are both 0, and a ceiling computed from them is simply the top of
          // the screen. That shipped: with the keyboard up the sheet grew until
          // the clock and the wifi bars sat on top of the grab handle and the X.
          // Read inside the [LayoutBuilder] so a rotation, which re-runs it,
          // brings the new inset with it.
          final topInset = MediaQueryData.fromView(View.of(context)).padding.top;
          // [heightFactor] of what is *visible*, not of the screen: with the
          // keyboard up, a sheet that kept its old height would be showing the
          // fraction of itself the keyboard left over. It grows by exactly what
          // was taken, so the sheet above the keyboard is the size it always
          // was — the same thing iOS does with its own sheets. Never past the
          // status bar, and never flush against it either: iOS leaves its own
          // sheets short of the top so the card is read as a card.
          final base = constraints.maxHeight * widget.heightFactor;
          final ceiling = constraints.maxHeight - topInset - _sheetTopGap;
          final height = math.max(base, math.min(ceiling, base + keyboard));
          // Published for whatever sheet is underneath this one, which needs it
          // to know how far to drop. A plain field write during layout: no
          // listeners, so no route gets marked dirty after it has built.
          _entry.height = height;
          return Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: height,
              // Inside the [SizedBox], so the scale is anchored to the top of
              // the *sheet* and the lift is a fraction of the sheet's own
              // height — outside it, both would be measured against the whole
              // screen the route covers.
              child: _CoveredSheet(
                covered: covered,
                height: height,
                frontHeight: _frontSheetHeight,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                    boxShadow: AppShadows.sheet,
                  ),
                  child: Column(
                    children: [
                      _GrabHandle(countdown: _countdown),
                      if (widget.collapsingHeader case final collapsing?)
                        Expanded(
                          child: NestedScrollView(
                            headerSliverBuilder: (context, _) => [
                              SliverPersistentHeader(
                                pinned: true,
                                delegate: CollapsingSliverHeaderDelegate(
                                  expandedHeight: collapsing.expandedHeight,
                                  collapsedHeight: collapsing.collapsedHeight,
                                  builder: collapsing.builder,
                                ),
                              ),
                            ],
                            body: Container(margin: const EdgeInsets.only(top: 14), child: grayBody),
                          ),
                        )
                      else ...[
                        widget.header ?? _defaultHeader(context),
                        Expanded(child: Container(margin: const EdgeInsets.only(top: 14), child: grayBody)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Lets whatever is *inside* a sheet tell the sheet's grab handle that the
/// sheet is about to dismiss itself, and how long it has: the handle then
/// drains over exactly that duration, so "this is going away in a moment" is
/// visible without a countdown number or a second control.
///
/// An inherited notifier rather than a `showAppSheet` argument because the
/// sheet does not know at open time — an auto-dismissing confirmation only
/// exists once the request it confirms has come back. Set from a post-frame
/// callback (see [ConfirmationView]); reading it where there is no sheet — the
/// same confirmation used as a page — yields null and nothing happens.
class SheetCountdown extends InheritedWidget {
  final ValueNotifier<Duration?> remaining;

  const SheetCountdown({super.key, required this.remaining, required super.child});

  static ValueNotifier<Duration?>? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SheetCountdown>()?.remaining;

  @override
  bool updateShouldNotify(SheetCountdown old) => old.remaining != remaining;
}

/// The 44x4 pill every sheet is grabbed by — unchanged, until somebody sets a
/// [SheetCountdown]. Then the pill's fill drains left to right over that
/// duration on the track it leaves behind, and the handle is still a handle
/// the whole time: same size, same place, nothing added around it.
class _GrabHandle extends StatefulWidget {
  final ValueNotifier<Duration?> countdown;

  const _GrabHandle({required this.countdown});

  @override
  State<_GrabHandle> createState() => _GrabHandleState();
}

/// The pill's width, and the span the countdown drains across.
const double _handleWidth = 44;

class _GrabHandleState extends State<_GrabHandle> with SingleTickerProviderStateMixin {
  late final AnimationController _drain = AnimationController(vsync: this, duration: Duration.zero);

  @override
  void initState() {
    super.initState();
    widget.countdown.addListener(_onCountdown);
  }

  void _onCountdown() {
    final remaining = widget.countdown.value;
    if (remaining == null || remaining <= Duration.zero) {
      _drain.stop();
      _drain.value = 0;
      return;
    }
    _drain.duration = remaining;
    _drain.forward(from: 0);
  }

  @override
  void dispose() {
    widget.countdown.removeListener(_onCountdown);
    _drain.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 2),
      child: SizedBox(
        width: _handleWidth,
        height: 4,
        child: AnimatedBuilder(
          animation: _drain,
          builder: (context, _) => Stack(
            children: [
              // The track only shows once something has drained off it, so a
              // sheet that never counts down looks exactly as it always did.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: shade(AppColors.grabHandle, 0.22),
                    borderRadius: const BorderRadius.all(Radius.circular(2)),
                  ),
                ),
              ),
              // `Positioned` with an explicit width and both edges, not an
              // `Align` + `FractionallySizedBox`: a Stack lays non-positioned
              // children out *loosely*, so the fill's `DecoratedBox` — which
              // has no size of its own — collapsed to zero height and the
              // handle only ever showed its track. This way both axes are
              // tight.
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: _handleWidth * (1 - _drain.value),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.grabHandle,
                    borderRadius: const BorderRadius.all(Radius.circular(2)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the right-hand side of a [SheetActionHeader] is currently offering.
enum SheetHeaderAction {
  /// The accent check: the sheet is a form and can be submitted.
  confirm,

  /// A spinner, and no close button — there is a request in flight that closing
  /// would not cancel.
  busy,

  /// Nothing at all, close button included: the sheet has become a confirmation
  /// that dismisses itself, and a X on it would race the dismissal for what the
  /// sheet pops with.
  none,

  /// The X alone: a sheet whose controls each act the moment they are used, so
  /// there is nothing to submit and the only thing left to say is "done". A
  /// check beside them would be a second way to commit what is already
  /// committed — see the connected calendar's sheet, where the name saves on
  /// its own tick and the owner saves on the tap that picks it.
  close,
}

/// The standard X / [title] / check header, for a sheet that submits **while it
/// stays open** and then shows what came back: `showAppSheet`'s built-in header
/// pops on the check, which is exactly what a sheet with a busy and a result
/// state must not do. The X is offered in [SheetHeaderAction.confirm] and
/// [SheetHeaderAction.close] — once a sheet has *acted*, there is nothing left
/// to cancel and the way out is whatever the result state decides (a beat that
/// dismisses itself, the action under a [ConfirmationView]).
///
/// Pass it as [showAppSheet]'s `header`, rebuilt (a `ValueListenableBuilder`
/// around it) as the phase changes. Shared by the calendar's connect-confirm
/// sheet and Settings' invite sheet, which is why it lives here rather than in
/// either.
///
/// Same Stack-before-buttons construction as the standard header; see
/// [showAppSheet] for why the title has to be painted first.
class SheetActionHeader extends StatelessWidget {
  final String title;
  final SheetHeaderAction action;
  final VoidCallback? onConfirm;

  /// A name the sheet cannot do without. While it is empty the accent button
  /// greys out and swallows its tap, exactly as in the standard header — see
  /// [showAppSheet]'s own `requiredField`.
  final TextEditingController? requiredField;

  /// What the X does. Defaults to popping the sheet with no result.
  final VoidCallback? onClose;

  /// The glyph on the left. A chevron rather than an X for a step that has a
  /// step behind it — a multi-step sheet whose first control still says "close"
  /// on page two is how a half-filled form gets thrown away by mistake.
  final IconData closeIcon;

  /// The glyph on the accent button. A right chevron for "weiter", where the
  /// check would promise that this is the last thing to do.
  final IconData confirmIcon;

  const SheetActionHeader({
    super.key,
    required this.title,
    required this.action,
    this.onConfirm,
    this.requiredField,
    this.onClose,
    this.closeIcon = AppIcons.x,
    this.confirmIcon = AppIcons.check,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: SizedBox(
        height: _headerButtonSize,
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: _headerButtonSize + 14),
                child: Center(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.sheetTitle,
                  ),
                ),
              ),
            ),
            if (action == SheetHeaderAction.confirm || action == SheetHeaderAction.close)
              Align(
                alignment: Alignment.centerLeft,
                child: GlassIconButton(
                  icon: closeIcon,
                  onTap: onClose ?? () => Navigator.of(context).pop(),
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: switch (action) {
                SheetHeaderAction.confirm => _SaveButton(
                  icon: confirmIcon,
                  requiredField: requiredField,
                  onSave: onConfirm ?? () {},
                ),
                SheetHeaderAction.busy => const SizedBox(
                  width: _headerButtonSize,
                  height: _headerButtonSize,
                  child: Center(
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                ),
                SheetHeaderAction.none ||
                SheetHeaderAction.close => const SizedBox(width: _headerButtonSize, height: _headerButtonSize),
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Close / [title], without the sheet's usual save check — for a sheet where
/// picking one of the options *is* the save, so a second confirmation would
/// only be a way to lose the choice. Pass it as [showAppSheet]'s `header`.
///
/// Same Stack-before-buttons construction as the standard header; see
/// [showAppSheet] for why the title has to be painted first.
class SheetPickerHeader extends StatelessWidget {
  final String title;

  const SheetPickerHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: SizedBox(
        height: _headerButtonSize,
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: _headerButtonSize + 14),
                child: Center(
                  child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.sheetTitle),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: GlassIconButton(icon: AppIcons.x, onTap: () => Navigator.of(context).pop()),
            ),
          ],
        ),
      ),
    );
  }
}

/// A white rounded card used to group form rows / list rows, matching the
/// `background:#FFFFFF;border-radius:20-22px;box-shadow:0 2px 10px rgba(17,26,43,.06)` pattern.
class SectionCard extends StatelessWidget {
  final List<Widget> children;
  final double radius;

  const SectionCard({super.key, required this.children, this.radius = AppRadii.cardSmall});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

/// A full-width bordered action at the foot of a sheet — "Teilen", "Löschen".
///
/// Not a [SectionCard] row: these are things done *to* the item rather than
/// fields of it, so they sit apart from the card that holds what you typed.
class OutlinedSheetAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool destructive;
  final VoidCallback onTap;

  const OutlinedSheetAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.danger : AppColors.ink;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.cardSmall),
          boxShadow: AppShadows.card,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIcon(icon, size: 17, color: color, flat: true),
            const SizedBox(width: 9),
            Text(
              label,
              style: AppText.rowTitle.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single divider-topped row used inside [SectionCard]s.
class CardDivider extends StatelessWidget {
  const CardDivider({super.key});

  @override
  Widget build(BuildContext context) => Divider(height: 1, thickness: 1, color: AppColors.divider);
}

/// [CardDivider] inset from the card's edges — the separator between
/// [FieldGroup]s and member rows, where a full-bleed rule cuts the card in
/// half.
class InsetDivider extends StatelessWidget {
  const InsetDivider({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: CardDivider(),
      );
}

/// [rows] with a divider dropped between every neighbouring pair — the body of
/// almost every [SectionCard] in the app.
///
/// Written out by hand this is a `for (var i = 0; …) if (i > 0) CardDivider()`
/// loop, which was copied into a dozen screens and is the kind of thing that
/// only ever goes wrong in one direction: a card that grows a second row and
/// keeps rendering it flush against the first. Passing an empty list yields an
/// empty card rather than a stray rule.
List<Widget> dividedRows(List<Widget> rows, {bool inset = false}) => [
      for (var i = 0; i < rows.length; i++) ...[
        if (i > 0) inset ? InsetDivider() : CardDivider(),
        rows[i],
      ],
    ];
