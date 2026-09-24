import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/grocery_catalog.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_icons.dart';
import '../../theme/tokens.dart';
import '../../widgets/dot_field.dart';
import '../../widgets/avatar.dart';
import '../../widgets/check_off.dart';
import '../../widgets/glyph_tile.dart';
import '../../widgets/icon_image.dart';

/// The front door's picture: **a household using the app, drawn live**.
///
/// One story, once, in three movements.
///
/// **The making.** Four pointers come in one after another, each with a face and
/// a name, and each one puts something into the app: an article on the shopping
/// list, an appointment in the calendar, a to-do that gets ticked, a tracker
/// with its week behind it. Four cards, four kinds of thing, which is the whole
/// product in one sentence.
///
/// **The clearing.** Mama — the one who put the first card there — comes back
/// and pushes the whole board off the left edge, the gesture a phone makes.
///
/// **What is left.** The welcome illustration rises into the room the cards
/// vacated, and the piece stops on it. It is the tour's own first picture, so
/// the sign-in page ends on the first frame of the place its button leads to.
///
/// **Why this and not a picture of a phone.** A screenshot says what the app
/// looks like; this says what it is *for*, which is the only claim a front door
/// has to make. It is also the one thing about Aporah that a still image cannot
/// show — that two people are in it at once — and it costs one asset the app
/// already ships, so it never goes stale against the screens it is advertising
/// and it is already in four languages.
///
/// **Everything in it is the app's own.** The cards are the app's card on the
/// app's shadow, the bread is the real article picture out of
/// `grocery_catalog.dart`, the glyphs are [GlyphTile]s wearing the app's own
/// marks — [AppIcons.circleDashed] for the tracker, the same open ring the
/// Board, Home and the paywall give one — the time goes through
/// [formatTimeOfDay] so it reads 16:00 in German and 4:00 PM in English, and
/// the to-do is ticked by [CheckOffButton], the same control playing the same
/// animation that Board and Listen tick a row with. Nothing here is a drawing
/// of a control that exists elsewhere.
///
/// **The arrow is Figma's, not the system's.** A thin hairline cursor is drawn
/// for a desktop at 1:1 and vanishes the moment it is one small thing inside a
/// picture of something else; a collaborative canvas draws a broad,
/// blunt-cornered, tilted one in somebody's colour, with a white rim and a
/// shadow holding it off the page. That is a sticker rather than a cursor, and
/// a sticker is what survives being 22 points tall behind two buttons. See
/// [_Pointer], which also records why a round touch blob was tried and
/// dropped.
///
/// **The dot field is the one piece of pure decoration**, and it earns its
/// place by carrying the movement — see [DotField].
class FrontDoorHero extends StatefulWidget {
  const FrontDoorHero({super.key});

  @override
  State<FrontDoorHero> createState() => _FrontDoorHeroState();
}

/// One pass, and there is only one: the controller is driven [forward], never
/// repeated.
///
/// **It ends somewhere rather than coming round again.** A loop is wallpaper —
/// you learn to ignore it, and the fifth time the same four cards land is the
/// time a reader stops seeing them. This tells a short story and then stops on
/// its last frame, which is a picture, so a page that has been open for a
/// minute is simply a page with a picture on it.
const _story = Duration(seconds: 14);

/// Where each beat sits in the pass. They do not overlap on purpose: two
/// pointers at once is a crowd, and the point of each beat is that you
/// can see what was added.
const _beats = [(0.02, 0.17), (0.17, 0.32), (0.32, 0.47), (0.47, 0.62)];

/// Inside one beat: the pointer travels, presses, the card arrives under it,
/// and the pointer leaves. The card's own slice is the app's arrival idiom — a fade
/// and a short rise on `easeOutCubic` — because that is how a row arrives
/// everywhere else.
const _travel = Interval(0, 0.42, curve: Curves.easeInOutCubic);
const _press = Interval(0.42, 0.56, curve: Curves.easeOutCubic);
const _arrive = Interval(0.48, 0.74, curve: Curves.easeOutCubic);
const _leave = Interval(0.80, 1, curve: Curves.easeInCubic);

/// A pointer fades up as it comes in. Without it one appears at full strength
/// outside the frame and is simply revealed by the clip, which reads as a
/// sprite being switched on rather than as somebody arriving.
const _enter = Interval(0, 0.12, curve: Curves.easeOut);

/// The to-do is ticked, and the tracker's last day closes, a moment after the
/// card has landed — a second action, not part of the card appearing.
const _tick = Interval(0.76, 1, curve: Curves.easeOutCubic);

/// **The clearing.** Mama comes back one last time and pushes the whole board
/// off the left edge. The cards move on [_swipeDrag] *exactly* — that is what
/// makes the hand look like it is carrying them rather than like two things
/// happening at the same time.
///
/// It is the same person who put the first card there, which is the joke and
/// also the point: one household, start to finish.
const _swipe = (0.64, 0.84);
const _swipeIn = Interval(0, 0.26, curve: Curves.easeInOutCubic);
const _swipePress = Interval(0.26, 0.36, curve: Curves.easeOutCubic);
const _swipeDrag = Interval(0.32, 0.84, curve: Curves.easeInOutCubic);
const _swipeOut = Interval(0.86, 1, curve: Curves.easeInCubic);

/// **Nothing says when the picture arrives**, because the swipe does. It rides
/// in from the right on [_swipeDrag] exactly as the board rides out to the
/// left, so one hand is pushing one page away and pulling the next one on —
/// which is a phone's own paging gesture, and the reason the two halves read as
/// one movement rather than as a gap with a picture after it.

/// The composition's own size. Everything is laid out against this and the
/// whole thing is then scaled to whatever the band gives it, so the picture
/// keeps its proportions on every phone instead of being re-flowed into a
/// different arrangement on each one. Tall enough to hold the last pointer's
/// name pill, which hangs below the arrow it belongs to.
const _canvas = Size(356, 330);

/// **It shrinks to fit and never grows past 1.** Scaling up is what made the
/// whole thing read as a blown-up screenshot: 320 into a 390-point phone is a
/// 1.22x enlargement of *everything*, so a 15-point row title was drawn at 18,
/// a 60-point card at 73 and the pointers to match — and the one thing in the
/// picture that is supposed to look like the app stopped looking like it. At 1
/// the cards are the size the app's own rows are, and the room left over is
/// dotted paper, which is a frame rather than waste.
const _maxScale = 1.0;

/// **Every box in the picture is measured, not guessed.** The app's face is
/// Poppins, whose line box is **1.5x** its point size — half again as tall as
/// the 1.2 a system face would give — so a two-line row that fits in 40 points
/// of most type is 42.75 here. A fixed-height card is therefore a card that
/// overflows unless somebody has done that sum.
///
/// The card: `microLabel` 17.25 over a 3pt gap over `rowTitle` 22.5 = 42.75,
/// inside [_Surface]'s 8pt of padding top and bottom.
const _cardHeight = 62.0;
const _cardGap = 12.0;
const _cardTop = 8.0;

/// The welcome illustration's box, at the asset's own 3:2, and where the
/// picture and the sentence under it stand in the canvas.
///
/// **The size the welcome tour draws it**, near enough: `StepHero` gives it the
/// step's full width and lets the aspect decide the height, which on a phone
/// comes to about 350 by 235. Drawn smaller here it read as a thumbnail of the
/// tour rather than as the tour's own first page, which is the whole point of
/// ending on it — the next thing a new household sees after the button under
/// this is that picture at that size.
const _welcomeSize = Size(348, 232);
const _welcomeTop = 10.0;

/// The sentence under the picture: where it sits, and how wide it may run.
///
/// Narrower than the picture, because a line of prose set to the full width of
/// a phone is a line the eye loses its place in — and because the four
/// languages are not the same length, and this is the width all four have to
/// wrap inside.
const _taglineTop = 258.0;
const _taglineWidth = 318.0;

/// It types itself out, starting once the picture has landed and finishing a
/// beat before the story stops — so the last thing that happens is the whole
/// page standing still with the promise finished on it.
const _type = Interval(0.83, 0.97);

/// How far a page travels to be off the canvas. Wider than the canvas, so a
/// card is fully gone — and the picture behind it fully arrived — before either
/// stops moving.
const _pageShift = 400.0;

double _lerp(double a, double b, double t) => a + (b - a) * t;

class _FrontDoorHeroState extends State<FrontDoorHero> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: _story)..forward();

  /// **"Bewegung reduzieren" gets the last frame, immediately.** Everywhere else
  /// in the app that setting costs the reader something — a reveal they do not
  /// get to watch. Here it costs nothing at all: the piece ends on a still
  /// picture, so skipping to it is the same page a minute early.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final tones = AppTones.list;

    // Three people and the four things they make. Built here rather than as a
    // file-level constant because every one of them reads a token or a string,
    // and neither survives being frozen into a `const`. Papa comes back for the
    // tracker: a household of three doing four things is one of them doing two,
    // and inventing a fourth name to avoid that would be worse.
    final mama = _Member(name: L.s.demoMemberMama, tone: tones[2]);
    final papa = _Member(name: L.s.demoMemberPapa, tone: tones[1]);
    final kid = _Member(name: L.s.demoMemberKid, tone: tones[4]);

    final cast = [
      _Beat(
        by: mama,
        // Bottom left, so the first pointer arrives from where a thumb is.
        from: const Offset(-0.22, 1.2),
        card: _CardSpec(
          kicker: L.s.demoListTitle,
          title: L.s.demoListItem,
          // The real article picture out of the grocery catalog, and the
          // catalog's own fallback if that file is ever renamed — a `!` here
          // would turn a renamed PNG into a crash on the login screen.
          //
          // A **rye** loaf rather than the pale one `suggestIcon('Brot')` would
          // pick: the card under it is white, and a white loaf on a white card
          // is a shadow with crumbs. The label stays the plain word a family
          // would actually write on a list.
          picture: groceryIconByAsset['${groceryAssetDir}Bread_Rye_Bread.png']?.asset ?? generalGroceryAsset,
        ),
      ),
      _Beat(
        by: papa,
        from: const Offset(1.3, -0.28),
        card: _CardSpec(
          kicker: L.s.today,
          title: L.s.demoEventTitle,
          detail: formatTimeOfDay(16, 0),
          icon: AppIcons.calendarDots,
        ),
      ),
      _Beat(
        by: kid,
        from: const Offset(1.25, 1.25),
        card: _CardSpec(kicker: kid.name, title: L.s.demoTaskTitle, check: true),
      ),
      _Beat(
        by: papa,
        from: const Offset(-0.25, -0.25),
        card: _CardSpec(
          // Its rhythm, not a date: a tracker is never overdue and has no due
          // day to name, so the line above it says what it asks for. The string
          // is the Board's own.
          kicker: L.s.rhythmDaily,
          title: L.s.demoTrackerTitle,
          // The open dashed ring, which is what a tracker wears everywhere
          // else in the app — the Board's row, Home's first steps, the day
          // island, the paywall's feature list. `repeat` was a guess at "a
          // rhythm" and it is the arrows the calendar uses for a recurring
          // appointment, which is the one thing a tracker is not.
          icon: AppIcons.circleDashed,
          week: true,
        ),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // `BoxFit.contain`, worked out here rather than handed to a `FittedBox`,
        // because the dots underneath are painted in the *band's* coordinates
        // while the sparks that light them are in the canvas' — so something
        // has to know the scale, and it may as well be the one place that also
        // applies it.
        final scale = math.min(
          math.min(constraints.maxWidth / _canvas.width, constraints.maxHeight / _canvas.height),
          _maxScale,
        );
        // Centred across, and **above centre down the page**: the drawing sits
        // between a title and a gray panel, and a picture centred in that gap
        // hangs too far from the word above it and crowds the panel below. A
        // third rather than a half is the optical centre — the same reason a
        // framed print is hung with more wall under it than over it.
        final origin = Offset(
          (constraints.maxWidth - _canvas.width * scale) / 2,
          (constraints.maxHeight - _canvas.height * scale) * 0.32,
        );

        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final frame = _compose(cast, mama, accent);
            return Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: DotField(
                      sparks: [for (final spark in frame.sparks) spark.toBand(origin: origin, scale: scale)],
                      shades: [for (final shade in frame.shades) shade.toBand(origin: origin, scale: scale)],
                      base: AppColors.hairline,
                      accent: accent,
                    ),
                  ),
                ),
                Positioned(
                  left: origin.dx,
                  top: origin.dy,
                  width: _canvas.width * scale,
                  height: _canvas.height * scale,
                  child: Transform.scale(
                    scale: scale,
                    alignment: Alignment.topLeft,
                    // **No text scaling inside the canvas.** The composition is
                    // a fixed 320x330 that is then scaled bodily, so a phone set
                    // to the largest type would not enlarge this — it would
                    // overflow the cards it is laid out inside. The words under
                    // the picture, and the buttons, are where the setting has to
                    // be honoured, and they still are.
                    child: MediaQuery.withNoTextScaling(
                      child: SizedBox(
                        width: _canvas.width,
                        height: _canvas.height,
                        // Clipped to the canvas, which is what lets a pointer
                        // travel in from outside it and a page leave through the
                        // side.
                        child: ClipRect(child: Stack(children: frame.layers)),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// One frame: the widgets to stack inside the canvas, and the sparks lighting
  /// the dots under it.
  _Frame _compose(List<_Beat> cast, _Member swiper, Color accent) {
    final t = _controller.value;

    final layers = <Widget>[];
    final pointers = <Widget>[];
    final sparks = <DotSpark>[];
    final shades = <DotSpark>[];

    // How far the board has been pushed off. One number, read by the cards, by
    // the hand pushing them and by the picture underneath — which is what keeps
    // the three in step without any of them owning a clock.
    final drag = _swipeDrag.transform(_local(t, _swipe));
    final boardX = -_pageShift * drag;

    // ------------------------------------------------------------- the making
    for (var i = 0; i < cast.length; i++) {
      final beat = cast[i];
      final local = _local(t, _beats[i]);

      // Where this beat's card sits, and so where its pointer is going.
      final top = _cardTop + i * (_cardHeight + _cardGap);
      final left = [18.0, 58.0, 32.0, 46.0][i];
      final width = [230.0, 252.0, 224.0, 244.0][i];

      final arrive = _arrive.transform(local);
      if (arrive > 0 && drag < 1) {
        layers.add(
          Positioned(
            key: ValueKey('card-$i'),
            left: left + boardX,
            top: top,
            width: width,
            child: Opacity(
              opacity: arrive,
              child: Transform.translate(
                offset: Offset(0, (1 - arrive) * 10),
                child: _Card(spec: beat.card, tick: _tick.transform(local), accent: accent),
              ),
            ),
          ),
        );
        // A card landing blooms the dots under it and is gone again by the time
        // it has settled: the light belongs to the *arrival*, not to the card.
        final bloom = math.sin(math.pi * arrive) * (1 - drag);
        if (bloom > 0.01) {
          sparks.add(
            DotSpark(
              at: Offset(left + boardX + width / 2, top + _cardHeight / 2),
              strength: bloom * 0.55,
              radius: 92,
            ),
          );
        }
      }

      // The pointer is only on screen for its own beat: it comes in, presses,
      // and goes. One at a time — see [_beats].
      if (local > 0 && local < 1) {
        final travel = _travel.transform(local);
        final gone = _leave.transform(local);
        // It lands just inside the card's leading edge, which is where the
        // press has to look like it landed on something.
        final target = Offset(left + width * 0.14, top + _cardHeight * 0.62);
        final from = Offset(beat.from.dx * _canvas.width, beat.from.dy * _canvas.height);
        final at = Offset(_lerp(from.dx, target.dx, travel), _lerp(from.dy, target.dy, travel));
        final press = _press.transform(local);
        final alive = _enter.transform(local) * (1 - gone);

        _light(sparks, at: at, alive: alive, press: press);
        pointers.add(_pointer(at: at, press: press, alive: alive, by: beat.by));
      }
    }

    // ----------------------------------------------------------- the clearing
    // The hand that does it — Mama again, the one who put the first card on the
    // board. It comes in from the right, takes hold, and then travels with what
    // it is carrying **and carries on off the left edge** rather than stopping.
    // A hand that halts mid-canvas while the board keeps going is two things
    // moving; one that flicks out of frame is a swipe. It covers less ground
    // than the board does (270 against [_pageShift]'s 400), which is the
    // inertia a real flick leaves behind it.
    final swipe = _local(t, _swipe);
    if (swipe > 0 && swipe < 1) {
      final press = _swipePress.transform(swipe);
      final alive = _swipeIn.transform(swipe) * (1 - _swipeOut.transform(swipe));
      final at = Offset(
        _lerp(_canvas.width + 30, 250, _swipeIn.transform(swipe)) - 270 * drag,
        _canvas.height * 0.42,
      );
      _light(sparks, at: at, alive: alive, press: press);
      pointers.add(_pointer(at: at, press: press, alive: alive, by: swiper));
    }

    // ------------------------------------------------------------ what is left
    // The illustration the board was standing in front of. It is the welcome
    // tour's own first picture, at the tour's own size, which is the point: the
    // next thing a new household sees after the button under this is that same
    // drawing, so the sign-in page ends on the first frame of where it is
    // sending them.
    if (drag > 0) {
      // Carried in on the swipe, the board's own number read the other way
      // round. One hand, one gesture, two pages.
      final x = _pageShift * (1 - drag);
      final at = Offset((_canvas.width - _welcomeSize.width) / 2 + x, _welcomeTop);
      layers.add(
        Positioned(
          key: const ValueKey('welcome'),
          left: at.dx,
          top: at.dy,
          width: _welcomeSize.width,
          height: _welcomeSize.height,
          // No clip and no card: it is a cut-out on transparency, exactly as
          // `StepHero` draws it three screens later, so there are no corners to
          // round and the space beside it is simply the page.
          child: Image.asset('assets/onboarding/hero_welcome.png', fit: BoxFit.contain),
        ),
      );
      // The promise, under the picture and travelling with it — one page, so
      // the sentence is never briefly stranded on the left of a picture still
      // arriving from the right.
      layers.add(
        Positioned(
          key: const ValueKey('tagline'),
          left: (_canvas.width - _taglineWidth) / 2 + x,
          top: _taglineTop,
          width: _taglineWidth,
          child: _Tagline(progress: _type.transform(t)),
        ),
      );
      // And the dots come up under it and stay up — the one spark in the whole
      // piece that does not fade back out. Everything before this was a flash
      // under something being done; this is the page settling with the picture
      // on it, which is where the story stops. It travels with the picture, or
      // the glow would be waiting on the left for something still arriving.
      sparks.add(
        DotSpark(
          at: at + _welcomeSize.center(Offset.zero),
          strength: drag * 0.42,
          // The picture's own ellipse: a core half its size at its own 3:2, so
          // the blue is even across it rather than pooling in the middle, and a
          // falloff that dies somewhere past its edges.
          core: 118,
          radius: 110,
          aspect: 1.5,
        ),
      );
      // And taken straight back off under the sentence. Wide and shallow,
      // because that is the shape of three lines of type; strong, because the
      // point is that the words end up on plain paper rather than on
      // slightly-less-blue paper.
      shades.add(
        DotSpark(
          at: Offset(_canvas.width / 2 + x, _taglineTop + 31),
          strength: 0.92,
          core: 48,
          radius: 42,
          aspect: 3.6,
        ),
      );
    }

    // Pointers last, so a hand is never behind the card it is pointing at.
    return _Frame(layers: [...layers, ...pointers], sparks: sparks, shades: shades);
  }

  /// Where [t] sits inside a window: 0 before it, 1 after.
  double _local(double t, (double, double) window) =>
      ((t - window.$1) / (window.$2 - window.$1)).clamp(0.0, 1.0);

  /// A pointer lights whatever it passes over, and its press throws a ring out
  /// from under it — this is what the dots are for.
  void _light(List<DotSpark> into, {required Offset at, required double alive, required double press}) {
    into.add(DotSpark(at: at, strength: alive, radius: 62));
    if (press > 0 && press < 1) {
      into.add(DotSpark(at: at, strength: (1 - press) * alive, radius: 62, ring: 18 + press * 86));
    }
  }

  /// One pointer at [at].
  ///
  /// **[at] is the arrow's tip, not the corner of its box.** The tip is what
  /// the arrow claims to be touching, and it sits a few points inside the
  /// painter so the white rim has room — so the box is offset by exactly that
  /// much. Leaving it out puts every press down and to the right of the thing
  /// being pressed, which reads as a hand missing.
  ///
  /// The name pill is left-aligned under the arrow rather than centred:
  /// centred, a pill three times the arrow's width would swing around whenever
  /// the name changed length, and "Mama" and "Papa" would sit in different
  /// places on the same card.
  Widget _pointer({required Offset at, required double press, required double alive, required _Member by}) {
    // Down and back up, so the press has weight rather than staying squeezed.
    final dip = press <= 0 ? 0.0 : (press < 0.5 ? press * 2 : (1 - press) * 2);
    return Positioned(
      left: at.dx - _arrowTip.dx,
      top: at.dy - _arrowTip.dy,
      child: Opacity(
        opacity: alive.clamp(0.0, 1.0),
        child: Transform.scale(
          // About the tip, so the arrow presses *into* what it is over rather
          // than sliding off it.
          scale: 1 - dip * 0.12,
          alignment: Alignment.topLeft,
          child: _Pointer(name: by.name, tone: by.tone),
        ),
      ),
    );
  }
}

class _Frame {
  final List<Widget> layers;
  final List<DotSpark> sparks;
  final List<DotSpark> shades;

  const _Frame({required this.layers, required this.sparks, required this.shades});
}

/// Somebody in the household: the two things a pointer shows about them.
class _Member {
  final String name;
  final Tone tone;

  const _Member({required this.name, required this.tone});
}

/// One person doing one thing.
class _Beat {
  final _Member by;

  /// Where the pointer comes in from, in fractions of the canvas — outside it on
  /// at least one axis, so it enters rather than appearing.
  final Offset from;

  final _CardSpec card;

  const _Beat({required this.by, required this.from, required this.card});
}

/// What one of the four cards holds. A picture *or* a glyph *or* a check —
/// the three things the app puts in front of a row, and each card uses the one
/// its own screen would.
class _CardSpec {
  final String kicker;
  final String title;
  final String? detail;
  final String? picture;
  final IconData? icon;
  final bool check;

  /// A tracker's week behind it, drawn where [detail] would go. **And no
  /// check**: a tracker is never overdue, and a day it was not kept is a gap in
  /// a record rather than a row following anybody around — so it gets a week of
  /// squares and no circle to tick. See the Board's own rules in CLAUDE.md.
  final bool week;

  const _CardSpec({
    required this.kicker,
    required this.title,
    this.detail,
    this.picture,
    this.icon,
    this.check = false,
    this.week = false,
  });
}

/// The one card shape everything in the picture sits on, so a chart and a
/// to-do are visibly the same app: [AppColors.cardOnSurface] and the palette's
/// card shadow, exactly as a `SectionCard` does on a page that is itself
/// [AppColors.surface].
///
/// Drawn here rather than reusing `SectionCard` because these are laid out to
/// the pixel inside a scaled canvas, and a shared card that changed its padding
/// would move the pointers off their targets.
class _Surface extends StatelessWidget {
  final double height;
  final Widget child;

  const _Surface({required this.height, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.cardOnSurface,
        borderRadius: BorderRadius.circular(AppRadii.cardSmall),
        boxShadow: AppShadows.card,
        // **A hairline of accent, which no card in the app itself wears.** On a
        // page the card's own shadow is the whole edge, and it is enough
        // because the card is the thing being looked at. Here it is a 62-point
        // white rectangle on a white band at the far end of a room, and the
        // shadow alone left it floating without an outline. A grey rule would
        // have read as a divider; the accent at a fifth strength reads as the
        // app's own line, and it is the only colour in the picture that is not
        // somebody's.
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.22)),
      ),
      child: child,
    );
  }
}

/// One of the four cards.
class _Card extends StatelessWidget {
  final _CardSpec spec;

  /// 0 → 1 as the to-do is ticked, or as the tracker's last day closes.
  final double tick;

  final Color accent;

  const _Card({required this.spec, required this.tick, required this.accent});

  @override
  Widget build(BuildContext context) {
    return _Surface(
      height: _cardHeight,
      child: Row(
        children: [
          _leading(),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spec.kicker,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.microLabel.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Flexible(
                      child: StrikeThrough(
                        // The to-do's label is struck through as it is ticked,
                        // which is what the row does on the Board.
                        progress: spec.check ? tick : 0,
                        color: AppColors.muted,
                        child: Text(
                          spec.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.rowTitle,
                        ),
                      ),
                    ),
                    if (spec.week) ...[
                      const SizedBox(width: 8),
                      _Week(progress: tick, accent: accent),
                    ] else if (spec.detail case final detail?) ...[
                      const SizedBox(width: 8),
                      Text(detail, style: AppText.caption.copyWith(color: AppColors.inkTertiary)),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _leading() {
    if (spec.check) {
      return CheckOffButton(progress: tick, accent: accent, onTap: () {}, size: 26, filled: true);
    }
    // **Neither the picture nor the glyph gets a tile.** The article photos are
    // cut out on white, so a grey square behind one is a grey square you can
    // see and a loaf you can't; and a Phosphor duotone already brings its own
    // mass, which is the whole argument on [GlyphTile]. Grey rather than a tone
    // for the glyph, because the colour in this picture belongs to the three
    // people in it.
    if (spec.picture case final asset?) {
      // [IconImage] rather than a bare `Image.asset`: it bounds the decode —
      // these are 512px files drawn at 36 — and it survives the asset being
      // renamed out from under it.
      return IconImage(asset: asset, size: 36);
    }
    return GlyphTile(icon: spec.icon ?? AppIcons.listChecks, size: 34, tone: AppColors.muted);
  }
}

/// A tracker's week, in the Board's own terms: a square per day, filled where
/// the rhythm was kept. The gap in the middle is deliberate — a day that was
/// missed is a hole in a record, not a failure to be coloured red — and the
/// last square is today, closing as the card is made.
class _Week extends StatelessWidget {
  final double progress;
  final Color accent;

  static const _kept = [true, true, false, true, true, true];

  const _Week({required this.progress, required this.accent});

  @override
  Widget build(BuildContext context) {
    final empty = AppColors.idleRing.withValues(alpha: 0.45);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final kept in _kept) ...[_square(kept ? accent : empty), const SizedBox(width: 3)],
        _square(Color.lerp(empty, accent, progress)!),
      ],
    );
  }

  Widget _square(Color color) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
  );
}

/// Somebody else's pointer: the arrow, and a pill under it with their face and
/// their name — the convention every shared canvas uses, and the fastest way to
/// say "this is not one person's app" without a sentence saying so.
///
/// **Figma's arrow, not the system's.** The one this replaced was the thin
/// hairline cursor an operating system draws, which is designed to sit over a
/// desktop at 1:1 and disappears the moment it is one small thing in a picture
/// of something else. A collaborative canvas draws a different arrow on
/// purpose: broad, blunt-cornered, filled in somebody's colour, with a thick
/// white rim and a shadow lifting it off the page. That is a *sticker* rather
/// than a cursor, and a sticker is what survives being 22 points tall on a
/// phone screen behind two buttons.
///
/// A round touch blob was tried in between, on the grounds that this is a phone
/// and arrows are desktop furniture. It is the better argument about *input*
/// and the worse one about *meaning*: a ring says "a finger pressed here", and
/// what this picture has to say is "somebody else is in here with you", which
/// is the one thing the arrow-with-a-name has meant since the first shared
/// document. The gesture is read from the cards moving, not from the shape of
/// the hand.
///
/// A [CustomPaint] rather than a glyph: it is a *shape*, not a control and not
/// a thing, so neither half of the icon rule fits it.
class _Pointer extends StatelessWidget {
  final String name;
  final Tone tone;

  const _Pointer({required this.name, required this.tone});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CustomPaint(
          size: _arrowBox,
          painter: _ArrowPainter(color: tone.fg),
        ),
        Padding(
          // Tucked under the arrow's tail, the way a real one hangs off its own
          // point rather than being centred on it.
          padding: const EdgeInsets.only(left: 6),
          child: Container(
            padding: const EdgeInsets.fromLTRB(3, 3, 10, 3),
            decoration: BoxDecoration(color: tone.fg, borderRadius: BorderRadius.circular(AppRadii.bar)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Avatar(
                  size: 18,
                  bg: tone.bg,
                  fg: tone.fg,
                  initials: name.characters.first.toUpperCase(),
                  fontSize: 9,
                ),
                const SizedBox(width: 6),
                Text(
                  name,
                  style: AppText.microLabel.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The painter's box, and where the tip sits inside it.
///
/// The tip is named rather than assumed: the shape leans, so the point it is
/// pointing with is not the top-left corner of anything, and [_pointer] has to
/// subtract it to put the arrow on its target. The padding round the rest is
/// the rim plus the shadow's blur, both of which reach outside the shape.
const _arrowBox = Size(29, 33);
const _arrowTip = Offset(3.5, 3.5);

class _ArrowPainter extends CustomPainter {
  final Color color;

  /// The rim's full width. Half of it lies outside the shape, which is the 2.4
  /// points of white that keep the arrow legible over a white card and over a
  /// lit dot field at once — the two things it spends the whole piece crossing.
  static const _rim = 4.8;

  const _ArrowPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final path = _path();

    // **Every layer is stroked *and* filled in one colour**, which is the whole
    // trick behind the blunt corners. A stroke with a round join grows the
    // outline outwards by half its width and rounds every vertex on the way;
    // filling the same path under it closes the middle. Two passes at two
    // widths therefore give a rounded shape inside a rounded rim, with no
    // second path to keep in step with the first.
    void solid(Paint paint, double width) {
      canvas.drawPath(path, Paint.from(paint)..style = PaintingStyle.fill);
      canvas.drawPath(
        path,
        Paint.from(paint)
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }

    // The shadow is what lifts it off the card. Without one the arrow is a
    // shape *in* the picture; with one it is a hand *over* the picture, which
    // is the entire claim.
    canvas.save();
    canvas.translate(0, 1.5);
    solid(
      Paint()
        ..color = const Color(0x33000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5)
        ..isAntiAlias = true,
      _rim,
    );
    canvas.restore();

    solid(
      Paint()
        ..color = Colors.white
        ..isAntiAlias = true,
      _rim,
    );
    solid(
      Paint()
        ..color = color
        ..isAntiAlias = true,
      1.6,
    );
  }

  /// The arrow, with its tip at [_arrowTip].
  ///
  /// **Four points, and one of them bends inwards.** This is the shape a
  /// collaborative canvas draws and it is not the operating system's cursor
  /// with rounder corners: the OS arrow has a *tail* — a narrow rectangle
  /// hanging off the foot of a triangle, drawn so that a 12-pixel glyph still
  /// has a recognisable stem. Here that stem is a small square stuck to the
  /// bottom of the shape, and at this size it is exactly what it looks like.
  ///
  /// So the tail is gone and the third corner is pulled *in* towards the tip
  /// instead. What is left is a dart: a long edge out to the right, a notch, a
  /// long edge back to the foot. The lean is in the points rather than in a
  /// rotation, because a shape this asymmetric has to be drawn leaning anyway
  /// and two ways of tilting it is one too many.
  Path _path() {
    const points = [
      Offset(0, 0),
      Offset(20.0, 11.8),
      // The notch — inside the line from the point above to the one below,
      // which is what makes it concave rather than a plain triangle.
      Offset(9.6, 15.2),
      Offset(4.8, 22.4),
    ];

    final path = Path();
    for (final (i, p) in points.indexed) {
      final at = _arrowTip + p;
      i == 0 ? path.moveTo(at.dx, at.dy) : path.lineTo(at.dx, at.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter old) => old.color != color;
}

/// The promise, typing itself out.
///
/// **The whole sentence is laid out from the first frame; the unwritten part is
/// simply invisible.** Revealing a growing substring instead would re-wrap the
/// text on nearly every frame — the last word on line one keeps falling to line
/// two and jumping back — so the sentence would jitter its way to the end
/// rather than appear. Two spans, one styled and one at zero alpha, measure
/// exactly the same as the finished line, which means the only thing that
/// changes between frames is the ink.
///
/// Nothing blinks after it. A caret is what a text field has because something
/// is expected of the reader, and nothing is expected here; this is a sentence
/// arriving the way somebody says it, not a form waiting to be filled in.
class _Tagline extends StatelessWidget {
  final double progress;

  const _Tagline({required this.progress});

  @override
  Widget build(BuildContext context) {
    final line = L.s.frontDoorTagline;
    // Characters, not code units, so an accented letter or an emoji is written
    // once rather than half-written — `é` is one thing a reader sees appear.
    final letters = line.characters;
    final written = (letters.length * progress).floor().clamp(0, letters.length);
    // A step up from [AppText.body], which is Poppins Light — a stroke drawn to
    // sit on flat white. The dot field steps back out from under the words (see
    // [DotField.shades]), so this is not doing the legibility work on its own;
    // it is the half of the answer that makes a short line read as a statement
    // rather than as a caption.
    final style = AppText.body.copyWith(color: AppColors.ink, fontWeight: FontWeight.w500, height: 1.45);

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: letters.take(written).toString()),
          TextSpan(
            text: letters.skip(written).toString(),
            style: const TextStyle(color: Colors.transparent),
          ),
        ],
      ),
      style: style,
      textAlign: TextAlign.center,
      maxLines: 3,
    );
  }
}
