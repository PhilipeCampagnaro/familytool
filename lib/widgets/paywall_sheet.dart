import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../models/calendar_connection.dart';
import '../models/entitlements.dart';
import '../services/app_review.dart';
import '../state/entitlement_state.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import 'dissolve_edge.dart';
import 'action_bar.dart';
import 'app_sheet.dart';
import 'glass.dart';

/// **A gate never hides a feature, it explains it.**
///
/// The one rule this widget exists to keep. A control that is simply missing,
/// or greyed out with nothing beside it, reads as a bug — the household
/// concludes the app is broken rather than that they have reached the end of
/// what free covers. So every limit in `lib/models/entitlements.dart` ends
/// here, at a sheet that says what they ran into, what Plus does about it and
/// what it costs.
///
/// **A sheet, not a screen**, like `showRenameSheet` and the share sheet: it
/// stacks over wherever the reader already was, and dismissing it puts them
/// back exactly there. Someone who tapped "+" on a fourth box wanted a box, not
/// a trip to a shop; the way out has to be one gesture.
///
/// It is told which [Feature] was reached, and that is the only thing it takes.
/// The copy comes from [paywallTitle] and [paywallBody], so a paywall that
/// names the wrong feature is not expressible.
///
/// **The header carries no save check.** The standard [showAppSheet] header
/// ends in the accent check, and on a price sheet that is the largest, bluest,
/// most confirming control on screen — sitting above a "Plus holen" it has
/// nothing to do with, and popping the sheet without buying anything if it is
/// tapped. [SheetPickerHeader] is the same header with that button left off:
/// here the buying happens at the bottom, so the top only needs a way out.
Future<void> showPaywallSheet(BuildContext context, Feature feature) {
  // Somebody who has just been shown a price is not who to ask for a rating.
  reviewPrompt.notePaywall();
  return showAppSheet<void>(
    context: context,
    header: SheetPickerHeader(title: L.s.plusName),
    // Both gates are short sheets. A price is a small question and a
    // near-full-height card asks it as if it were a screen; what the picture
    // needs is a *share* of the sheet, not a taller one to sit in — see
    // [_PlusHero], which takes everything this furniture leaves over.
    heightFactor: _heroAsset(feature) == null ? 0.72 : _heroSheetFactor,
    // The picture is sized by what the sheet has left over, which is a
    // question only a bounded body can answer — see [showAppSheet]'s
    // `scrollBody`. The gates without a picture keep the scroll.
    scrollBody: _heroAsset(feature) == null,
    // **The one control being sold does not scroll.** Pinned to the foot of
    // the sheet with the body sliding under it, so a small phone, a long
    // translation or a big picture can cost the reader a scroll but never the
    // button. See [showAppSheet]'s `footer`.
    footer: _PlusActions(),
    child: _PaywallBody(feature: feature),
  );
}

/// **The one line a screen writes to put a gate up.**
///
/// `if (!await requireFeature(context, ref, Feature.photos)) return;` — true
/// means carry on, false means the paywall is already on screen and the caller
/// is done. Returning a bool rather than taking a callback keeps the action
/// where it was: the code that adds a photograph stays in the method that adds
/// a photograph, with one guard above it.
///
/// Use this for a feature the household either has or does not — Ausgaben,
/// photographs. For one they have a number of, use [requireAnother].
Future<bool> requireFeature(BuildContext context, WidgetRef ref, Feature feature) async {
  if (ref.read(entitlementProvider).allows(feature)) return true;
  await showPaywallSheet(context, feature);
  return false;
}

/// The same guard for a counted limit: [current] is how many the household has
/// now, and the paywall goes up only when one more would be too many.
///
/// **The count is the caller's because only the caller knows what counts.**
/// Members are people plus invitations still outstanding; share links are the
/// ones still live rather than every one ever made. A shared helper reaching
/// for a count would get one of those wrong.
Future<bool> requireAnother(BuildContext context, WidgetRef ref, Feature feature, int current) async {
  if (ref.read(entitlementProvider).allowsAnother(feature, current)) return true;
  await showPaywallSheet(context, feature);
  return false;
}

/// How much of the screen a paywall with a picture on it takes.
///
/// Short, like every other sheet that asks one question — and read by
/// [_PlusHero] as well as by the sheet, because the picture is sized from the
/// card it is in rather than from the display behind it.
const double _heroSheetFactor = 0.78;

/// How much taller than its band the device is drawn — see the note at the
/// picture itself. High enough to be a phone rather than an icon of one, and
/// low enough that the cut still falls below the month grid.
///
/// **This is the number that makes the phone bigger, not the sheet's height.**
/// The mockup is twice as tall as it is wide, so the band's height is what
/// decides the width and the width is where the picture is still leaving room
/// on the card — raising this spends the leftover width and pays for it at the
/// bottom of the screenshot, which is the part that says the least.
const double _heroOverflow = 1.62;

/// How far the strip is allowed out of the body's column on each side: the
/// paywall's own 20 points plus the sheet body's 18. Written down rather than
/// measured because the two paddings are static, and a band that guessed would
/// either stop short of the card's edge or overhang it.
const double _heroBleed = 38;

/// **A photograph of the app doing the thing, where we have one.**
///
/// The calendar gate is the one most households meet first — a second Google
/// account, the school's feed — and "alle eure Kalender" is a sentence about a
/// screen they have not seen yet. A phone showing the month grid with four
/// families' worth of coloured dots on it says the same thing before the
/// paragraph under it is read.
///
/// **Ausgaben needs it more than any other gate, because it is the one feature
/// nobody has seen at all.** Every other limit is reached inside a screen the
/// household already uses — a fourth Box, a second calendar — so the paywall
/// interrupts something they were doing and they know what they are buying
/// more of. Ausgaben is off entirely on free: the row is tapped out of
/// curiosity and, without a picture, a sentence about Apple Pay is the whole
/// pitch. The rings, the curve and a month's real total answer "what would I
/// actually be looking at" in the time it takes to read the title.
///
/// Null for every other feature on purpose, rather than a stand-in: a picture
/// of the *calendar* over a paragraph about boxes would be a screenshot of the
/// wrong app, and the glyph tile it falls back to ([_FeatureMark]) is honest
/// about being a symbol. Add a shot here as each one is taken, never a generic.
///
/// **One shot per language, and it is not decoration that it is.** The whole
/// argument of the picture is that this is your app, already running — and an
/// English household shown "Kalender", "Termine je Kalender" and a 24-hour
/// clock is being shown somebody else's. The file name carries
/// [AppStrings.localeCode], which only ever holds the four `stringsFor`
/// answers, so there is a file behind every value it can take; all eight are
/// the same pixel size, which is what lets [_heroOverflow] crop them all in
/// the same place.
String? _heroAsset(Feature feature) => switch (feature) {
  Feature.calendarAccounts => 'assets/paywall/hero_calendar_${L.s.localeCode}.png',
  Feature.spend => 'assets/paywall/hero_spend_${L.s.localeCode}.png',
  _ => null,
};

class _PaywallBody extends StatelessWidget {
  final Feature feature;

  const _PaywallBody({required this.feature});

  @override
  Widget build(BuildContext context) {
    final hero = _heroAsset(feature);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: hero == null ? MainAxisSize.min : MainAxisSize.max,
        children: [
          // **The picture takes everything the words leave.** Expanded, not a
          // height: the lines below it are the same on every phone and the
          // photograph is the one thing that can be any size, so it is the one
          // thing that should be measured last. This replaced a constant that
          // estimated the rest of the sheet and was 20 points out — which read
          // as a gap over the button and a trial note nobody could see.
          //
          // The one thing it gives up is a body that could scroll: at an
          // accessibility text size past roughly 200% the words stop fitting
          // and the column clips instead of scrolling. That is why the least
          // important line — the trial note — is the last one, and why the
          // sentence carrying the price sits above it.
          if (hero != null) Expanded(child: _PlusHero(hero)) else _FeatureMark(icon: _icon),
          const SizedBox(height: 14),

          // **The marks come before the claim, not after it.** "Mehr als ein
          // Kalender" is the sentence the row is evidence for, and evidence
          // read first makes the sentence land as a summary of something
          // already seen rather than as a promise waiting to be backed up.
          // Calendar only: there is no such row behind "mehr Boxen", and
          // inventing one would be decoration pretending to be evidence.
          if (feature == Feature.calendarAccounts) ...[_ProviderStrip(), const SizedBox(height: 14)],

          Text(paywallTitle(feature), style: AppText.cardTitle, textAlign: TextAlign.center),
          const SizedBox(height: 8),

          // **The price is a clause, not a pair of tiles.**
          //
          // Two cards side by side made choosing the plan the question this
          // sheet asked, and that is not the question — the reader has not
          // decided they want Plus at all yet, and a picker is a thing you put
          // in front of somebody who has. So the sheet says what Plus does and
          // what the cheapest way in costs, in one sentence under the picture,
          // and leaves the monthly/yearly choice to the place it actually gets
          // made: the store's own sheet, once "Plus holen" is pressed.
          // [AppStrings.plusPriceYearly] and the saving are still written down
          // for that screen; they are simply not this sheet's business.
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '${paywallBody(feature)} '),
                TextSpan(
                  text: L.s.plusForOnly(L.s.plusPriceMonthly),
                  style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            style: AppText.caption.copyWith(
              color: AppColors.inkSecondary,
              fontWeight: FontWeight.w400,
              height: 1.45,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 10),
          Text(L.s.plusTrialNote, style: AppText.label, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  /// The same glyph the feature wears everywhere else in the app, so the sheet
  /// is recognisably about the thing they just tapped.
  IconData get _icon => switch (feature) {
    Feature.calendarAccounts => AppIcons.calendarDots,
    Feature.trackers => AppIcons.circleDashed,
    Feature.boxes => AppIcons.package,
    Feature.members => AppIcons.users,
    Feature.photos => AppIcons.image,
    Feature.spend => AppIcons.wallet,
  };
}

/// The glyph tile a gate leads with when it has no [_heroAsset] — the feature's
/// own mark, big enough to be the first thing read.
class _FeatureMark extends StatelessWidget {
  final IconData icon;

  /// Not `const`: it reads [AppColors] inside its own `build`, and a
  /// canonicalised const instance would keep painting the palette it was first
  /// built with after a theme flip — the one failure
  /// `tool/check_const_palette.dart` exists to catch. A non-const constructor
  /// makes that a compile error at the call site instead.
  // ignore: prefer_const_constructors_in_immutables
  _FeatureMark({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Center(
        child: Container(
          width: 62,
          height: 62,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadii.iconTile + 5),
          ),
          child: AppIcon(icon, size: 30, color: AppColors.accent),
        ),
      ),
    );
  }
}

/// The device shot, standing in its own light.
///
/// Two soft accent glows behind the phone and nothing else — no card, no
/// border, no shadow under the frame. The picture is a cut-out of a phone on
/// transparency, so a panel behind it would draw a rectangle nobody asked for;
/// what it needs instead is for the grey sheet to stop being flat where the
/// phone stands. That is what the glows are: light spilling off the screen,
/// which is also the one place in the app an accent wash is not competing with
/// a control for the reader's attention.
///
/// **Gradients, not a blur.** An `ImageFilter.blur` over a coloured circle is a
/// full-screen-width saved layer on a sheet that opens on a slide animation,
/// and it renders as the same soft ball a radial gradient draws for free.
class _PlusHero extends StatelessWidget {
  final String asset;

  /// Non-const for the same reason [_FeatureMark] is — it reads [AppColors]
  /// in `build`.
  // ignore: prefer_const_constructors_in_immutables
  _PlusHero(this.asset);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // **Whatever the column left over**, which is why this is a
        // [LayoutBuilder] inside an `Expanded` rather than a share of the
        // screen: the sheet is already a fraction of the display, the words
        // under the picture are a fixed cost, and the only honest answer to
        // "how big" is what is actually still there.
        //
        // The floor is where it stops being a picture of a phone and becomes a
        // stamp. Below that the picture is simply cut shorter, which costs the
        // foot of the screenshot and nothing that matters.
        final height = constraints.maxHeight;
        return SizedBox(
          height: height,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              _Glow(
                color: AppColors.accent,
                alignment: const Alignment(0.1, -0.5),
                diameter: height * 1.25,
                opacity: AppColors.isDark ? 0.34 : 0.26,
              ),
              _Glow(
                // The violet the calendar draws a family's own events in — so the
                // second glow is a colour the screenshot above it actually
                // contains, rather than a decorator's purple.
                color: AppCalendarColors.choices[9],
                alignment: const Alignment(-0.75, 0.55),
                diameter: height * 0.8,
                opacity: AppColors.isDark ? 0.26 : 0.2,
              ),
              // **The phone is drawn taller than the band it stands in, and the
              // band keeps the top of it.**
              //
              // A whole device fitted into a short sheet is a *small* device: the
              // mockup is twice as tall as it is wide, so fitting its height
              // leaves it using two fifths of the width with grey either side.
              // Overflowing it instead and cutting the bottom away draws the phone
              // half again as large — the title, the filter chips and the whole
              // month grid, which is what the sentence underneath is about — and
              // gives up the timeline card at the foot of the screenshot, which is
              // the part that says the least at this size.
              //
              // The last of it dissolves rather than being sliced: a hard edge
              // across a phone reads as a rendering fault, while a fade reads as a
              // picture continuing past the frame. Same reasoning as
              // [PinnedActionBar]'s gradient, one axis down.
              DissolveBottom(
                child: OverflowBox(
                    alignment: Alignment.topCenter,
                    maxHeight: height * _heroOverflow,
                    child: Image.asset(
                      asset,
                      height: height * _heroOverflow,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// **Every calendar the app can connect, drifting past under the title.**
///
/// The claim over it is "mehr als ein Kalender", and the honest way to back
/// that up is to show *which* ones. A row rather than a sentence, because the
/// marks are recognised faster than their names are read — and moving rather
/// than a static line, because seven logos do not fit across a phone and a
/// grid of them would be a comparison table on a sheet that is not asking
/// anybody to compare anything. It drifts instead, slowly, and whichever four
/// are showing is not a claim about ranking.
///
/// **Edge to edge on purpose.** The strip runs out of the body's column and
/// across the whole card ([_heroBleed]), so it reads as a band passing behind
/// the sheet rather than as a row that stops in two places. That is also why
/// both ends dissolve instead of ending: a logo cut in half at a hard edge
/// reads as a layout fault, while one fading out reads as more of them coming.
///
/// The list is [CalendarProvider]'s own, filtered to the ones with a mark, so
/// this cannot drift out of step with what the connect screen actually offers
/// — a provider added there appears here on its next build. The three without
/// a logo (iCal, Ferien, Abfall) are a link and two feeds rather than a
/// company, and there is nothing to draw for them.
class _ProviderStrip extends StatefulWidget {
  /// Not `const`: [AppColors] is read in `build` for the fade.
  // ignore: prefer_const_constructors_in_immutables
  _ProviderStrip();

  @override
  State<_ProviderStrip> createState() => _ProviderStripState();
}

class _ProviderStripState extends State<_ProviderStrip> with SingleTickerProviderStateMixin {
  /// Points a second the row travels. Slow enough to be read as drifting
  /// rather than scrolling — a strip that hurries looks like an advert, and
  /// the reader is meant to be looking at the phone above it.
  static const double _speed = 26;

  static const double _gap = 14;

  /// The marks, in the order the connect screen lists them.
  static final List<String> _assets = [for (final provider in CalendarProvider.values) ?provider.asset];

  late final AnimationController _drift;

  /// One full pass of the list. The row is drawn three times over, so whatever
  /// the band's width, there is always a copy arriving before the one leaving
  /// has gone — and after exactly this distance the row is identical to where
  /// it started, which is what makes the loop invisible.
  double get _cycle => _assets.length * (_ProviderChip.size + _gap);

  @override
  void initState() {
    super.initState();
    _drift = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (_cycle / _speed * 1000).round()),
    )..repeat();
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Someone who has asked the system to stop animations gets the row
    // standing still rather than a slower one — the same answer the charts and
    // the progress bar give (`MediaQuery.disableAnimationsOf`).
    final still = MediaQuery.disableAnimationsOf(context);

    return SizedBox(
      height: _ProviderChip.size,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth + _heroBleed * 2;
          // Enough copies of the list to cover the band *plus* the cycle the
          // row travels before it wraps. Derived rather than fixed at the two
          // a phone needs, so a wide sheet — an iPad — does not run out of row
          // halfway through a pass and show a gap where the loop restarts.
          final passes = (width / _cycle).ceil() + 1;
          final row = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var pass = 0; pass < passes; pass++)
                for (final asset in _assets)
                  Padding(
                    padding: const EdgeInsets.only(right: _gap),
                    child: _ProviderChip(asset: asset),
                  ),
            ],
          );
          return OverflowBox(
            minWidth: width,
            maxWidth: width,
            alignment: Alignment.center,
            child: ClipRect(
              child: ShaderMask(
                // The ends dissolve into the sheet, which is what "edge to
                // edge" has to mean for a row that is longer than the card.
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
                  stops: [0, 0.12, 0.88, 1],
                ).createShader(rect),
                blendMode: BlendMode.dstIn,
                child: SizedBox(
                  width: width,
                  // The row is several times wider than the band it runs in,
                  // which is the whole idea — but a `Row` handed the band's
                  // width lays out inside it and paints the debug overflow
                  // stripes across the strip. The [OverflowBox] hands it the
                  // width it actually wants; the [ClipRect] above is what
                  // decides where it stops being visible.
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: 0,
                    maxWidth: double.infinity,
                    child: still
                        ? row
                        : AnimatedBuilder(
                            animation: _drift,
                            child: row,
                            builder: (context, child) => Transform.translate(
                              // One cycle back, so the copy behind it has
                              // taken its place by the time the controller
                              // wraps.
                              offset: Offset(-_drift.value * _cycle, 0),
                              child: child,
                            ),
                          ),
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

/// A service's mark, on the app's own white chip.
///
/// The same circle a member's avatar or a shop's logo wears elsewhere — white,
/// card shadow, the mark inset — so seven foreign brands sit on the sheet as
/// Aporah furniture rather than as seven different design languages in a row.
class _ProviderChip extends StatelessWidget {
  final String asset;

  /// Big enough to recognise a mark at arm's length, small enough that five of
  /// them cross a phone.
  static const double size = 46;

  /// Not `const`: [AppColors] and [AppShadows] are read in `build`.
  // ignore: prefer_const_constructors_in_immutables
  _ProviderChip({required this.asset});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(color: AppColors.surface, shape: BoxShape.circle, boxShadow: AppShadows.card),
      child: Image.asset(asset, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
    );
  }
}

/// One ball of coloured light: opaque-ish at the middle, gone by the rim, so it
/// has no edge to read as a shape.
class _Glow extends StatelessWidget {
  final Color color;
  final Alignment alignment;
  final double diameter;
  final double opacity;

  const _Glow({required this.color, required this.alignment, required this.diameter, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: IgnorePointer(
        child: Container(
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [shade(color, opacity), shade(color, opacity * 0.42), shade(color, 0)],
              stops: const [0, 0.5, 1],
            ),
          ),
        ),
      ),
    );
  }
}

/// **What the sheet is actually asking**, pinned to its foot by
/// [showAppSheet]'s `footer` so the body scrolls under it.
///
/// One control, and only one. A "Später" sat here under the button for a
/// while, which gave the sheet two ways out a thumb's width apart — the close
/// button in the header is already the way out, it is where every other sheet
/// in the app keeps it, and a second one in the bottom corner only made the
/// button being offered easier to miss by accident.
///
/// **Nothing may be added after the glass button** — see [PinnedActionBar],
/// which explains what the native `UIGlassEffect` does to Flutter content
/// painted over it.
class _PlusActions extends ConsumerWidget {
  /// Not `const`: it reads [AppColors] in its build, which a canonicalised
  /// const instance would freeze at the palette it was born with — see
  /// `tool/check_const_palette.dart`.
  // ignore: prefer_const_constructors_in_immutables
  _PlusActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entitlements = ref.watch(entitlementProvider);
    return PinnedActionBar(
      // The body under this one is measured to fit, not scrolled, so the fade
      // has nothing to fade and its usual band is simply a blank row over the
      // button. What it gives up goes to the picture, which is the only thing
      // in the column that can use it.
      fadeHeight: 10,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Only while the developer switch is forcing a plan. It is here
          // rather than in a corner of Settings because this is the screen a
          // screenshot gets taken of, and a simulated plan that looks real in a
          // store listing is the mistake worth making impossible.
          if (entitlements.overridden) ...[
            Text(
              L.s.plusDebugOverride,
              style: AppText.caption.copyWith(color: AppColors.danger),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
          ],
          // **Nothing is wired to a store yet** — StoreKit 2 and Play Billing
          // land in Phase 4, behind one Dart interface. Until then this is
          // deliberately inert rather than absent: every screen that gates
          // something needs somewhere real to send the reader while the rest of
          // the app is built, and a button that is missing would hide the one
          // thing this sheet exists to say.
          //
          // The app's own accent glass, like every other primary action —
          // [OutlinedSheetAction], which this was, is the white row a sheet
          // ends with for things done *to* an item ("Teilen", "Löschen"), and
          // it left the one thing being sold looking like the least important
          // control on the sheet.
          GlassAccentButton(icon: AppIcons.sparkle, label: L.s.plusUpgrade, expand: true, onTap: () {}),
        ],
      ),
    );
  }
}
