import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/emoji_colors.dart';
import '../theme/tokens.dart';
import 'app_sheet.dart';
import 'glass.dart';
import '../l10n/l10n.dart';

/// The party popper a [ConfirmationMark.celebration] is drawn with — named
/// because [CelebrationGlow] takes the wash behind it out of the same glyph,
/// and the two picking different emoji would be a colour that belongs to
/// nothing on screen.
const celebrationEmoji = '🎉';

/// The mark a confirmation opens with.
enum ConfirmationMark {
  /// The accent disc and its expanding ring — the everyday "that worked", for
  /// something the family will do again next week.
  check,

  /// 🎉 and falling confetti, for the handful of moments that only happen once:
  /// the household set up, somebody invited into it. Used sparingly on purpose —
  /// confetti on every write is confetti nobody sees.
  celebration,
}

/// How the way out is drawn: the bordered [OutlinedSheetAction] a sheet ends
/// with, or the accent glass pill a **full screen** ends with — a filled pill
/// inside a sheet would compete with the accent check in its header.
enum ConfirmationAction { sheetAction, accentPill }

/// **The** confirmation in this app: one mark, a headline, a line of detail,
/// and whatever content the thing that just happened left behind. Every "that
/// worked" surface is this widget with different content — a calendar
/// connected, an invitation sent, the household set up — because they are one
/// event with different nouns, and hand-built success screens drift apart the
/// moment one of them is touched.
///
/// Two shapes, chosen by [dismissAfter]:
/// - **A beat**: pass a duration and the confirmation plays and leaves, calling
///   [onDone] when it does. For a result with nothing left to do about it — a
///   calendar connected, an invitation the recipient's mail now carries.
/// - **A screen**: leave it null and it waits, with the action at its foot. For
///   a result the user still has to acknowledge or act on.
///
/// Not a sheet itself: it is the *body* of one, or of a screen. A flow that
/// already has a sheet open swaps its body for this, so the sheet that acted
/// becomes the sheet that confirms rather than stacking a second modal on the
/// first; [showConfirmationSheet] is only for a result that came from somewhere
/// other than a sheet.
class ConfirmationView extends StatefulWidget {
  final String headline;

  /// The muted line under the headline — what was connected, who was mailed.
  final String? message;

  /// Cards under the message: detail rows, a recap. They fade in with the text
  /// rather than appearing under a finished animation.
  final List<Widget> content;

  final ConfirmationMark mark;

  /// Only read for [ConfirmationMark.check].
  final IconData icon;

  /// Non-null makes this a beat that plays and leaves; null makes it a screen
  /// that waits. Measured from the moment it appears.
  final Duration? dismissAfter;

  /// What "done" means — dismissing the beat, or the tap on the action. The
  /// enclosing route is popped with no result when this is null.
  final VoidCallback? onDone;

  final ConfirmationAction action;

  /// Overrides the "Fertig" label on the action (screen shape only).
  final String? doneLabel;

  const ConfirmationView({
    super.key,
    required this.headline,
    this.message,
    this.content = const [],
    this.mark = ConfirmationMark.check,
    this.icon = LucideIcons.check,
    this.dismissAfter,
    this.onDone,
    this.action = ConfirmationAction.sheetAction,
    this.doneLabel,
  });

  @override
  State<ConfirmationView> createState() => _ConfirmationViewState();
}

/// The intro: the ring pops out from under the mark rather than the mark
/// bouncing, which keeps the motion in the same ease-out language as the rest
/// of the app.
class _ConfirmationViewState extends State<ConfirmationView> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 660),
  )..forward();

  late final CurvedAnimation _pop = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.5, curve: Curves.easeOutBack),
  );
  late final CurvedAnimation _ring = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.17, 0.92, curve: Curves.easeOutCubic),
  );
  late final CurvedAnimation _text = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.42, 1, curve: Curves.easeOutCubic),
  );

  Timer? _dismiss;

  @override
  void initState() {
    super.initState();
    // Timed from appearing, not from the end of the intro: how long a
    // confirmation stays readable is a property of the confirmation, not of how
    // long its animation happens to run.
    if (widget.dismissAfter case final delay?) {
      _dismiss = Timer(delay, _done);
      // And the sheet's grab handle drains over the same span, so the user can
      // see the sheet is on its way out instead of having it vanish under their
      // thumb. After the frame, because setting it during build would rebuild
      // the handle — a sibling that is already building — mid-pass. On a page
      // there is no sheet to tell, and this is a no-op.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) SheetCountdown.of(context)?.value = delay;
      });
    }
  }

  void _done() {
    if (!mounted) return;
    // The timer keeps running while the route it is on animates away — a swipe
    // down, or the action tapped a beat before the dismissal. Firing then would
    // pop whatever is *underneath*, which is a settings page disappearing for
    // no reason. `isCurrent` is false the moment this route starts leaving.
    if (ModalRoute.of(context)?.isCurrent == false) return;

    final onDone = widget.onDone;
    if (onDone != null) {
      onDone();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _dismiss?.cancel();
    _pop.dispose();
    _ring.dispose();
    _text.dispose();
    _controller.dispose();
    super.dispose();
  }

  Widget _mark(Color accent) {
    return SizedBox(
      width: 130,
      height: 130,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Stack(
          alignment: Alignment.center,
          children: [
            // No ring behind the emoji: the confetti is already the motion
            // around it, and two expanding things read as a glitch.
            if (widget.mark == ConfirmationMark.check)
              Opacity(
                opacity: (1 - _ring.value).clamp(0.0, 1.0) * 0.35,
                child: Container(
                  width: 78 + 52 * _ring.value,
                  height: 78 + 52 * _ring.value,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: accent, width: 2),
                  ),
                ),
              ),
            Transform.scale(
              scale: _pop.value,
              child: switch (widget.mark) {
                ConfirmationMark.check => Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                    boxShadow: AppShadows.accentGlass(accent),
                  ),
                  alignment: Alignment.center,
                  child: Icon(widget.icon, size: 38, color: Colors.white),
                ),
                // The emoji itself, at the disc's size — the party popper is
                // the illustration, so it doesn't need a plate under it.
                ConfirmationMark.celebration => const Text(celebrationEmoji, style: TextStyle(fontSize: 68)),
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final waits = widget.dismissAfter == null;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: waits ? 8 : 30),
        Center(child: _mark(accent)),
        const SizedBox(height: 22),
        FadeTransition(
          opacity: _text,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.headline,
                textAlign: TextAlign.center,
                // A celebration gets the full screen title: it is the headline
                // of the moment, not the label on a beat that is already
                // leaving.
                style: widget.mark == ConfirmationMark.celebration ? AppText.screenTitle : AppText.cardTitle,
              ),
              if (widget.message case final message?) ...[
                const SizedBox(height: 6),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: AppText.body.copyWith(color: AppColors.muted),
                ),
              ],
              for (final card in widget.content) ...[
                const SizedBox(height: 16),
                card,
              ],
              if (waits) ...[
                const SizedBox(height: 22),
                switch (widget.action) {
                  ConfirmationAction.sheetAction => OutlinedSheetAction(
                    icon: LucideIcons.check,
                    label: widget.doneLabel ?? L.s.doneAction,
                    onTap: _done,
                  ),
                  ConfirmationAction.accentPill => GlassAccentButton(
                    label: widget.doneLabel ?? L.s.doneAction,
                    onTap: _done,
                    expand: true,
                    fontSize: 16,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  ),
                },
              ],
            ],
          ),
        ),
        SizedBox(height: waits ? 8 : 30),
      ],
    );

    if (widget.mark != ConfirmationMark.celebration) return body;

    // Behind the content, sized by it: the confetti falls over the whole
    // confirmation and takes no hits, so a tap goes to the action under it.
    return Stack(
      children: [
        Positioned.fill(child: _Confetti()),
        body,
      ],
    );
  }
}

/// The light a [ConfirmationMark.celebration] spills in from the top edge, in
/// the party popper's own colours — the same trick the Listen header plays with
/// a shop's logo (`HeaderBrandGlow`), with three colours instead of one because
/// that is how many 🎉 has.
///
/// **Behind a whole screen, not inside the confirmation.** Like the brand glow
/// it is anchored to the very top of the display, status bar included: a wash
/// that started under the safe area would leave a white band above it and give
/// away that the colour is a rectangle rather than the surface itself. So it is
/// laid in at the foot of the screen's stack, under the content, rather than
/// being drawn by [ConfirmationView].
///
/// Nothing is painted until the glyph has been read (a frame or two after
/// first launch, instantly ever after) and then it fades in. There is
/// deliberately no accent-coloured stand-in: this is decoration that can afford
/// to arrive late, and a wash that snaps from blue to gold under a headline the
/// user is already reading looks like a bug.
class CelebrationGlow extends StatefulWidget {
  /// Taller than the content it sits behind, so the falloff is geometry on the
  /// screen rather than an outline around the headline.
  final double height;

  const CelebrationGlow({super.key, this.height = 340});

  @override
  State<CelebrationGlow> createState() => _CelebrationGlowState();
}

class _CelebrationGlowState extends State<CelebrationGlow> {
  /// Where each colour comes in from, strongest first: two upper corners and
  /// one higher up the middle, all centred *above* the top edge so only the
  /// lower arc of the falloff is on screen. Alpha drops down the ranking, so
  /// the glyph's main colour leads and the streamers tint it.
  static const _lamps = [
    (center: Alignment(-0.65, -1.15), radius: 1.15, strength: .17),
    (center: Alignment(0.7, -1.25), radius: 1.2, strength: .13),
    (center: Alignment(0.0, -1.5), radius: 1.3, strength: .11),
  ];

  @override
  void initState() {
    super.initState();
    if (emojiGlowKnown(celebrationEmoji)) return;
    loadEmojiGlow(celebrationEmoji).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = emojiGlowFor(celebrationEmoji);

    return AnimatedOpacity(
      opacity: colors.isEmpty ? 0 : 1,
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            for (final (i, color) in colors.indexed)
              if (i < _lamps.length)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: _lamps[i].center,
                        radius: _lamps[i].radius,
                        // Faded out to the hue at zero alpha rather than to
                        // transparent white: Flutter lerps RGB and alpha
                        // separately, so a white end stop drags a pale haze
                        // through the falloff — and with three of them
                        // overlapping, three hazes make a grey cloud.
                        colors: [
                          shade(color, _lamps[i].strength),
                          shade(color, _lamps[i].strength * .32),
                          shade(color, 0),
                        ],
                        stops: const [0, .45, .82],
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

/// A [ConfirmationView] as a sheet of its own — for a result that *wasn't*
/// produced by a sheet, so there is none to turn into the confirmation.
Future<void> showConfirmationSheet({
  required BuildContext context,
  required String title,
  required String headline,
  String? message,
  List<Widget> content = const [],
  ConfirmationMark mark = ConfirmationMark.check,
  IconData icon = LucideIcons.check,
  Duration? dismissAfter,
  String? doneLabel,
}) {
  return showAppSheet<void>(
    context: context,
    header: SheetPickerHeader(title: title),
    heightFactor: 0.6,
    child: ConfirmationView(
      headline: headline,
      message: message,
      content: content,
      mark: mark,
      icon: icon,
      dismissAfter: dismissAfter,
      doneLabel: doneLabel,
    ),
  );
}

/// Paper falling over a [ConfirmationMark.celebration]. Deliberately hand-drawn
/// rather than a package: it is 26 rounded rectangles on one controller, it
/// has to take its colours from the live palette like everything else, and a
/// dependency that ships a particle engine for this would be the tail wagging
/// the dog.
///
/// One pass, not a loop — it falls, it lands, it stops. Confetti that keeps
/// raining turns a confirmation into a screensaver.
class _Confetti extends StatefulWidget {
  @override
  State<_Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<_Confetti> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..forward();

  /// Fixed seed: the scatter should look random but be the *same* random on
  /// every rebuild, or a hot reload (or the palette flipping) reshuffles the
  /// paper mid-fall.
  late final List<_ConfettiPiece> _pieces = _ConfettiPiece.scatter(math.Random(7), 26);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _ConfettiPainter(
            progress: _controller,
            pieces: _pieces,
            // The family's own tone colours, so the paper belongs to this app
            // in either palette rather than to a party-supplies stock palette.
            colors: [
              for (final tone in AppTones.list) tone.fg,
              accent,
              AppColors.success,
            ],
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _ConfettiPiece {
  /// Where it starts, as a fraction of the width.
  final double x;

  /// How far into the animation it is released, and how long its fall takes —
  /// both fractions of the whole, so the paper doesn't come down as one sheet.
  final double delay;
  final double fall;

  final double width;
  final double height;

  /// Full turns over the fall, and the sway that keeps it from dropping on a
  /// rail.
  final double turns;
  final double swayAmplitude;
  final double swayPhase;

  final int color;

  const _ConfettiPiece({
    required this.x,
    required this.delay,
    required this.fall,
    required this.width,
    required this.height,
    required this.turns,
    required this.swayAmplitude,
    required this.swayPhase,
    required this.color,
  });

  static List<_ConfettiPiece> scatter(math.Random random, int count) => [
        for (var i = 0; i < count; i++)
          _ConfettiPiece(
            x: random.nextDouble(),
            delay: random.nextDouble() * 0.35,
            fall: 0.5 + random.nextDouble() * 0.3,
            width: 6 + random.nextDouble() * 5,
            height: 9 + random.nextDouble() * 7,
            turns: 0.6 + random.nextDouble() * 2.2,
            swayAmplitude: 8 + random.nextDouble() * 26,
            swayPhase: random.nextDouble() * math.pi * 2,
            color: random.nextInt(1 << 20),
          ),
      ];
}

class _ConfettiPainter extends CustomPainter {
  final Animation<double> progress;
  final List<_ConfettiPiece> pieces;
  final List<Color> colors;

  _ConfettiPainter({required this.progress, required this.pieces, required this.colors})
      : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    final paint = Paint();

    for (final piece in pieces) {
      final local = ((t - piece.delay) / piece.fall).clamp(0.0, 1.0);
      if (local <= 0) continue;

      // Starts above the box and ends below it, so nothing pops in or stops
      // mid-air at the bottom edge.
      final y = -30 + local * (size.height + 60);
      final x = piece.x * size.width + math.sin(piece.swayPhase + local * math.pi * 3) * piece.swayAmplitude;

      paint.color = colors[piece.color % colors.length]
          .withValues(alpha: (1 - local * local) * 0.85);

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(piece.turns * local * math.pi * 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: piece.width, height: piece.height),
          const Radius.circular(2),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) =>
      old.pieces != pieces || old.colors != colors;
}
