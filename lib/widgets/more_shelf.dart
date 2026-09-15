import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/spend_intent.dart';
import '../state/more_state.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import 'bottom_nav.dart';
import 'glass.dart';
import 'native_glass_buttons.dart';

/// The two places **Mehr** leads, offered as glass buttons standing on the bar
/// item that opened them.
///
/// This replaced a `UIMenu` anchored on the same item. The menu was the
/// system's own material and the right layer, and it was still the wrong
/// control for this one tap: every other menu in the app hangs off a "..." and
/// lists *verbs* for the row beside it, where **Mehr** names two **places** and
/// is the only nav item that opens one. A list of two labelled rows read as a
/// settings menu growing out of the tab bar, and it put a text list where the
/// other four tabs answer with a glyph — the bar's own language. Two buttons
/// the size of the bar are that language: same shape, same material, same row,
/// and each one a thumb-sized target instead of a 30pt-tall menu line.
///
/// The buttons are the compacted nav button's twins on purpose
/// ([AppShadows.navBar], a flat glyph on untinted glass, and the same
/// [kCompactNavSize] diameter) — the app already puts a glass circle of exactly
/// that size on the nav row when Kalender collapses the bar, so this reads as
/// the same family of control rather than a second one. They stand a finger's
/// width above the bar with its five SF Symbols still on screen underneath, and
/// a circle noticeably smaller than the thing it came out of reads as a lesser
/// control that appeared rather than as the bar itself. The glyph is
/// [kNavRowIconSize] for the same reason and `AppColors.ink` at rest —
/// black on the light palette, white on the dark one, the same weight as the
/// label beside it — and `AppColors.accent` only for the section in force.
///
/// **Always mounted, never removed.** Each button is a real `UIGlassEffect`
/// platform view on iOS, so the shelf goes [Offstage] when it is fully closed
/// rather than dropping out of the tree: a platform view left at zero opacity
/// is still a UIKit view over the pixels and the touches behind it, and one
/// torn down and rebuilt on every tap costs a view creation the user waits for.
/// Same bargain as `_NavShape` in `main.dart`.
///
/// **They stack upwards, not across.** A column out of the item is the shape
/// the gesture already has — the thumb is on the bar and the offer comes up to
/// meet it — and it is what keeps the buttons *on* the item rather than beside
/// it: a row of two would be twice the width of the slot it grew out of and,
/// Mehr being the outermost item on both bars, would have to be pushed inward
/// to stay on the display. The nearest button is the first one
/// ([VerticalDirection.up]), the way UIKit reverses a menu it has to present
/// above its anchor.
///
/// **The name rides in front of the button, on glass of its own.** Two glyphs
/// are legible enough between themselves, but they float over whatever screen
/// the reader was on, and "the icons will explain themselves" is a bet that
/// only pays for the reader who has already been here. A label *under* a glyph
/// would turn the pair back into the list of menu rows this replaced; beside it
/// the column is still two buttons, each one read left to right. It is its own
/// capsule rather than bare text for the same reason everything else on this
/// row is glass: plain letters over a photograph in a box or a list of
/// Ausgaben are unreadable exactly when the shelf is open over them. The whole
/// pair is one target — a label you can see and can't press is a bug people
/// report.
///
/// **It moves and fades; it does not scale.** Scaling a platform view smears it
/// — see `GlassSurface.forceFlutterApproximation` — so the entrance is a rise
/// plus a fade, staggered from the bar upwards, and the press feedback is the
/// only scale anywhere near it (small enough, and on a circle, which is what
/// `CompactNavButton` already does).
class MoreShelf extends StatefulWidget {
  /// Whether the shelf is being offered. False while it animates away, which is
  /// why this is not the same question as "is it in the tree".
  final bool open;

  /// The section already on screen, or null when the reader is on another tab —
  /// on any other tab neither of the two is "the one in force", exactly as the
  /// menu's tick used to work.
  final MoreSection? current;

  final ValueChanged<MoreSection> onPick;

  const MoreShelf({
    super.key,
    required this.open,
    required this.current,
    required this.onPick,
  });

  @override
  State<MoreShelf> createState() => _MoreShelfState();
}

/// Gap between the top of the nav bar and the bottom of the shelf.
///
/// Bigger than the clearance scrolling content gets under the bar, and for the
/// reason `navContentInset`'s own `gap:` argument gives: two pieces of glass
/// that touch read as one shape that failed to draw, and this one is parked
/// rather than sliding past.
const kMoreShelfGap = 14.0;

/// Between the two buttons. Enough that they are two circles and not one
/// cracked capsule — the failure `GlassIconGroup` exists to avoid — while
/// staying close enough to read as one offer.
///
/// The labels make the shelf wider than that, but they run *left* off the
/// buttons, so the column of circles still stands centred on the bar item —
/// see `_NavLayer` in `main.dart`.
const kMoreShelfSpacing = 12.0;

/// Distance from the bottom of the screen to the top of the open shelf — for
/// whatever else parks above the bar on its side and has to clear it
/// (Kalender's "Heute").
double moreShelfTop(BuildContext context, {double? barHeight}) {
  final barTop = useNativeTabBar
      ? nativeTabBarBottomInset(context) + (barHeight ?? kNativeTabBarHeight)
      : 22.0 + kFlutterNavBarHeight;
  final n = _entries.length;
  return barTop + kMoreShelfGap + n * kCompactNavSize + (n - 1) * kMoreShelfSpacing;
}

/// How far each button rises into place. Generous, because the rise is all the
/// entrance there is: the one thing a piece of real glass may not do on its way
/// in is scale.
const _rise = 30.0;

/// Fraction of the animation each button waits before starting, counted from
/// the one nearest the bar item.
const _stagger = 0.18;

/// How far into a button's own arrival its label starts unfurling. Late enough
/// that the circle has visibly landed first, so the capsule reads as coming out
/// from *under* it rather than the two arriving as one slab.
const _labelDelay = 0.32;

class _ShelfEntry {
  final MoreSection section;
  final String label;
  final IconData icon;

  /// What the **native** button draws instead of [icon] — see
  /// [NativeGlassButton.symbol]. Same reasoning as [navRowIcon]'s Cupertino
  /// swap, one step further: on iOS the circle is a real `UIButton` sitting
  /// over a real `UITabBar`, so it may as well carry the bar's own glyph rather
  /// than Flutter's copy of it. `shippingbox` is what the Boxen tab itself uses
  /// when Ausgaben doesn't ship; both names were checked against the runtime's
  /// symbol list.
  final String sfSymbol;

  const _ShelfEntry(this.section, this.label, this.icon, this.sfSymbol);
}

/// Rebuilt on every read so the labels follow the interface language, the same
/// way `navTabs` is.
///
/// The glyphs go through [navRowIcon] like everything else Flutter draws on
/// this row: the bar underneath is real SF Symbols, so an app-set box sitting a
/// finger's width above the SF one reads as a second, subtly different box.
List<_ShelfEntry> get _entries => [
  _ShelfEntry(
    MoreSection.box,
    L.s.navBox,
    navRowIcon(lucide: AppIcons.package, cupertino: CupertinoIcons.cube_box),
    'shippingbox',
  ),
  // Where Ausgaben does not ship there is no second place, so the nav item is
  // plain Boxen and nothing opens this at all. Dropped here as well so the shelf
  // is honest read on its own.
  if (spendAvailable)
    _ShelfEntry(
      MoreSection.spend,
      L.s.spendTitle,
      navRowIcon(lucide: AppIcons.wallet, cupertino: CupertinoIcons.creditcard),
      'creditcard',
    ),
];

class _MoreShelfState extends State<MoreShelf> with SingleTickerProviderStateMixin {
  /// Out faster than in, matching the anchored menu this replaced: an opening
  /// control is worth watching and a dismissed one is in the way.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    reverseDuration: const Duration(milliseconds: 260),
  );

  /// Starts at zero and is driven forward from here even when it is born open,
  /// which it always is the **first** time: the shell has nowhere to stand the
  /// shelf until it has measured the bar item, so it mounts this widget in the
  /// same breath as it opens it. Seeding the controller at 1 for that case is
  /// what made the first tap of every session snap the buttons on with no
  /// animation at all, while every tap after it animated — which reads as a
  /// dropped frame rather than as a design.
  @override
  void initState() {
    super.initState();
    if (widget.open) _controller.forward();
  }

  @override
  void didUpdateWidget(MoreShelf oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open != oldWidget.open) {
      widget.open ? _controller.forward() : _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// How far through its own arrival button [i] is, before any curve: 0 to 1.
  ///
  /// Button zero — the one nearest the bar, at the bottom of the column — has
  /// the whole span and the rest start progressively later, so going in they
  /// unfold upward out of the tap and coming out the top one is the first to
  /// reach zero. One window, read in both directions; there is no separate
  /// closing sequence to keep in step with the opening one.
  double _raw(int i) {
    final start = i * _stagger;
    return ((_controller.value - start) / (1 - start)).clamp(0.0, 1.0);
  }

  /// Whether the shelf is on its way out, which is the one thing the two
  /// directions do not share. Going in the buttons overshoot and settle, the
  /// way something with a bit of weight to it arrives; coming out they fall
  /// back the way they came, because an overshoot on the way to nowhere is a
  /// wobble.
  bool get _closing => _controller.status == AnimationStatus.reverse;

  double _riseCurve(double u) =>
      _closing ? Curves.easeInCubic.transform(u) : Curves.easeOutBack.transform(u);

  double _fadeCurve(double u) =>
      _closing ? Curves.easeInCubic.transform(u) : Curves.easeOutCubic.transform(u);

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Offstage(
        offstage: _controller.value == 0,
        // Nothing is tappable while it is on its way out, so a tap chasing a
        // button that is already leaving can't land on it.
        child: IgnorePointer(
          ignoring: !widget.open,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            // The labels are different lengths, so the rows have to hang off
            // their trailing edge or the circles wander left and right.
            crossAxisAlignment: CrossAxisAlignment.end,
            // Bottom-up, so entry zero is the one the thumb is already on.
            verticalDirection: VerticalDirection.up,
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                if (i > 0) const SizedBox(height: kMoreShelfSpacing),
                Builder(builder: (context) {
                  final u = _raw(i);
                  final label = ((u - _labelDelay) / (1 - _labelDelay)).clamp(0.0, 1.0);
                  return Opacity(
                    opacity: _fadeCurve(u).clamp(0.0, 1.0),
                    child: Transform.translate(
                      // `easeOutBack` passes 1 and comes back, so this goes
                      // negative for a moment: the button rises a little past
                      // where it lands and settles onto it.
                      offset: Offset(0, (1 - _riseCurve(u)) * _rise),
                      child: _ShelfButton(
                        entry: entries[i],
                        selected: widget.current == entries[i].section,
                        reveal: _fadeCurve(label).clamp(0.0, 1.0),
                        onTap: () => widget.onPick(entries[i].section),
                      ),
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One label capsule and one circle, pressed as a single control.
///
/// Only the circle takes the press scale. It is the target the finger is on,
/// and both pieces are `UIGlassEffect` platform views on iOS — scaling one of
/// those smears it, which is survivable on a circle this size (`CompactNavButton`
/// has always done it) and is what the grouped-glass rule in `glass.dart`
/// warns about on anything wider.
class _ShelfButton extends StatefulWidget {
  final _ShelfEntry entry;
  final bool selected;
  final VoidCallback onTap;

  /// How much of the label capsule is out, 0 to 1. It unfurls leftward from
  /// behind the circle rather than fading in beside it: the circle is the
  /// control that grew out of the tap, and the name is the thing it is carrying.
  ///
  /// The width is what animates, not an offset, so the circle never moves —
  /// the column hangs off its trailing edge and the capsule takes whatever room
  /// it has claimed so far to the left of it.
  final double reveal;

  const _ShelfButton({
    required this.entry,
    required this.selected,
    required this.reveal,
    required this.onTap,
  });

  @override
  State<_ShelfButton> createState() => _ShelfButtonState();
}

/// The label capsule's padding. Shared, because on the native path it is what
/// sizes the platform view too — see [NativeGlassButtons.sizer].
const _labelPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 9);

class _ShelfButtonState extends State<_ShelfButton> {
  bool _pressed = false;

  Widget get _labelText => Text(widget.entry.label, maxLines: 1, style: AppText.rowTitle);

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  /// The label capsule, wound in to [_ShelfButton.reveal] of its width.
  ///
  /// `Align` sizes the box to a fraction of the child while the child goes on
  /// painting at full size, so the clip is what actually hides the rest.
  ///
  /// **Both stay in the tree at full reveal, and only the clip switches off.**
  /// Returning the bare capsule instead is the obvious optimisation — a clip
  /// over a platform view is a mask UIKit reapplies every frame, and this one
  /// spends its life at rest — and it costs a **visible flash** at the end of
  /// every open. The capsule is a real `UIGlassEffect` platform view, so
  /// changing the widgets above it changes its element's position in the tree,
  /// the view is torn down and recreated, and for the frame in between there is
  /// nothing there: the screen behind shows through where the label was and is
  /// then covered again. `Clip.none` keeps the render objects exactly where they
  /// are and does no clipping, which is the same saving without the swap.
  Widget _reveal(Widget capsule) {
    return ClipRect(
      clipBehavior: widget.reveal >= 1 ? Clip.none : Clip.hardEdge,
      child: Align(
        alignment: Alignment.centerRight,
        widthFactor: widget.reveal.clamp(0.0, 1.0),
        child: capsule,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // `AppColors.ink` at rest: near-black in the light palette, near-white in
    // the dark one, and the same weight as the label beside it. The bar's own
    // `unselectedTint` was tried here and is wrong on glass — `AppColors.muted`
    // is one grey for *both* palettes, which works on the bar's own material
    // and goes soft and half-disabled on a glass circle floating over a screen.
    // Only the section you are on is the accent, which is the bar's `tint`
    // doing the one job a colour has here; the accent-*filled* circle this
    // started as was louder than anything on the screen it stands over.
    final color = widget.selected ? AppColors.accent : AppColors.ink;
    // Both halves are real `UIButton`s on the glass configuration where the
    // material is real — see [NativeGlassButtons]. They carry the *same*
    // action, because the pair has always been one control; the outer detector
    // below stays for the gap between them, which UIKit knows nothing about.
    final native = nativeGlassActive(context);
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.entry.label,
      // One control, so the label is not a second thing to read and fail to
      // press; the glyph and the word are already merged for VoiceOver above.
      excludeSemantics: true,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        // Opaque, or the gap between the capsule and the circle is a hole in
        // the middle of a control the user reads as one thing.
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _reveal(
              native
                  ? NativeGlassButtons(
                      buttons: [
                        NativeGlassButton(
                          label: widget.entry.label,
                          title: widget.entry.label,
                          titleStyle: AppText.rowTitle,
                          onTap: widget.onTap,
                        ),
                      ],
                      tint: AppColors.ink,
                      sizer: Padding(padding: _labelPadding, child: _labelText),
                    )
                  : GlassSurface(
                      borderRadius: BorderRadius.circular(AppRadii.bar),
                      blurSigma: 24,
                      // Softer than the circle's: this one is wide, and
                      // `navBar`'s lift is sized for something round and
                      // smudges under a capsule.
                      boxShadow: AppShadows.floatingPill,
                      child: Padding(padding: _labelPadding, child: _labelText),
                    ),
            ),
            const SizedBox(width: 10),
            if (native)
              SizedBox(
                width: kCompactNavSize,
                height: kCompactNavSize,
                child: NativeGlassButtons(
                  buttons: [
                    NativeGlassButton(
                      symbol: widget.entry.sfSymbol,
                      label: widget.entry.label,
                      onTap: widget.onTap,
                    ),
                  ],
                  tint: color,
                  iconSize: kNavRowIconSize,
                ),
              )
            else
              AnimatedScale(
                scale: _pressed ? 0.92 : 1.0,
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                child: GlassSurface(
                  borderRadius: BorderRadius.circular(kCompactNavSize / 2),
                  blurSigma: 24,
                  boxShadow: AppShadows.navBar,
                  child: SizedBox(
                    width: kCompactNavSize,
                    height: kCompactNavSize,
                    child: AppIcon(
                      widget.entry.icon,
                      size: kNavRowIconSize,
                      color: color,
                      flat: true,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
