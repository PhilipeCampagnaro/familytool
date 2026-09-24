/// The chrome a **full-page step** wears, and the three pieces that go inside
/// it: the illustration, the nav row and the pill at the foot.
///
/// Two flows in the app are stepped this way — the welcome tour's three
/// questions, and the sign-in flow's front door → form → code — and they are
/// the same page with different questions in it. This is that page, in one
/// place, because the alternative is the shape drifting: the tour's frosted
/// band and the login's would have been two stacks with two sets of insets, and
/// the one thing a user notices about the two screens either side of "Konto
/// erstellen" is that they are not the same screen.
///
/// A [StepPage] expects to sit inside a `Scaffold` with `SafeArea(top: false)`
/// around it — the band has to reach the top of the display, and each step
/// leaves the room for it with [stepTopInset] rather than being handed it.
library;

import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import 'glass.dart';

/// A step's nav row: the way back, whatever names the middle, the way out. All
/// three are the app's glass — a bare `IconButton` and a `TextButton` read as
/// two grey words floating over the illustration rather than as controls.
///
/// A `Stack`, **not** a `Row` — the same rule the sheet header and
/// `CollapsingScreenTitle` follow (see docs/design-system.md): the glass
/// buttons are native platform views on iOS, and Flutter content laid out
/// *between* two of them in a row lands in a composited overlay that never
/// shows on device. The middle is therefore a full-width layer painted first,
/// with the two controls aligned over it — which also makes "centred" mean the
/// screen's centre rather than the centre of whatever space they left over.
class StepTopBar extends StatelessWidget {
  /// What names where you are — the tour's `StepDots`. Null on a step that is
  /// one of one, which is every step of the sign-in flow.
  final Widget? center;

  final VoidCallback? onBack;

  /// The back button's accessible name, which an icon hasn't got — and it is
  /// not always "back": on the code screen the caret means "use a different
  /// address", which is what a screen reader should hear.
  final String? backLabel;

  /// The way out, where there is one: the tour's "Überspringen" pill.
  final Widget? trailing;

  const StepTopBar({super.key, this.center, this.onBack, this.backLabel, this.trailing});

  /// The bar's own height — 6 above a 44pt row, 2 below — and the one number
  /// [StepPage] and every step's scroll padding have to agree on, since the
  /// body rests below the bar and scrolls *under* it. A constant rather than a
  /// measurement because it genuinely is one: the row is a fixed [SizedBox],
  /// and whatever is in it is laid out inside that rather than setting it.
  static const height = 6 + 44 + 2.0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screenPad, 6, AppSpacing.screenPad, 2),
      child: SizedBox(
        height: 44,
        child: Stack(
          children: [
            if (center case final middle?) Positioned.fill(child: Center(child: middle)),
            if (onBack case final back?)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Center(
                  child: GlassIconButton(icon: AppIcons.caretLeft, onTap: back, label: backLabel),
                ),
              ),
            if (trailing case final action?)
              Positioned(right: 0, top: 0, bottom: 0, child: Center(child: action)),
          ],
        ),
      ),
    );
  }
}

/// The room a step's scroll body leaves at the top: the status-bar strip the
/// page no longer hands to a `SafeArea`, plus the nav row standing on it.
///
/// Read at the call site rather than threaded through [StepPage] — every
/// `bodyBuilder` already has a `BuildContext`, and one number computed the same
/// way in both halves is what keeps the bar and the content it rests below in
/// step.
double stepTopInset(BuildContext context) => MediaQuery.paddingOf(context).top + StepTopBar.height;

/// A step's scrolling body under the nav row, on the same frosted material as
/// every other screen in the app.
///
/// **The body runs to the top of the safe area, not to the bottom of the bar.**
/// Each step used to be a `Column` of [StepTopBar] over its content, which
/// meant the scroll viewport began below the bar — so the illustration was
/// sliced by a hard white edge the moment anything scrolled, and the hero read
/// as cropped. Here the body fills the whole area and passes *under* the bar
/// blurred, which is both what the rest of the app does and what the dots and
/// "Überspringen" need in order to stay legible over a picture.
///
/// The band is exactly [stepTopInset] tall — the notch strip plus the row —
/// because the blur ramps to nothing at its bottom edge (see
/// [FrostedHeaderBackground]): a taller one would put that vanishing point in
/// the middle of the content rather than on the bar's own edge, and a shorter
/// one would leave the status bar as the hard edge instead.
///
/// **Not `const`, like the material it stands on**: it reads [AppColors] inside
/// `build`, and a canonicalised instance would keep the palette it was born in.
/// See the rule on [AppColors] and `tool/check_const_palette.dart`.
class StepPage extends StatelessWidget {
  /// The step's own [PinnedActionLayout], already built. It is handed over
  /// whole rather than assembled here because each step has its own rules about
  /// when its action is there at all.
  final Widget body;

  final Widget? center;
  final VoidCallback? onBack;
  final String? backLabel;
  final Widget? trailing;

  // ignore: prefer_const_constructors_in_immutables
  StepPage({super.key, required this.body, this.center, this.onBack, this.backLabel, this.trailing});

  @override
  Widget build(BuildContext context) {
    final statusBar = MediaQuery.paddingOf(context).top;
    return Stack(
      // Expand rather than the loose default, for the same reason
      // [PinnedActionLayout] does it: the body is a scroll view, and a loose
      // stack would shrink-wrap it and leave the bar sitting on the content.
      fit: StackFit.expand,
      children: [
        body,
        // The band covers the status bar as well as the row, which is the whole
        // point: the blur has to reach the top of the display or the notch
        // strip becomes the hard white edge the frost was there to remove.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: stepTopInset(context),
          child: FrostedHeaderBackground(),
        ),
        // Last, so the glass pill and the caret are composited above the
        // material they refract rather than behind it.
        Positioned(
          top: statusBar,
          left: 0,
          right: 0,
          child: StepTopBar(center: center, onBack: onBack, backLabel: backLabel, trailing: trailing),
        ),
      ],
    );
  }
}

/// A step's illustration.
///
/// **Fitted, not cropped.** The PNGs are near-square (1.1–1.35:1) and this used
/// to be a fixed 200pt band at full width — an aspect of ~1.7 — so
/// `BoxFit.cover` cut a third off the top and bottom of every one of them.
/// `contain` shows the whole picture, and the cap is a share of the viewport
/// rather than a constant so the illustration gives way on a small phone
/// instead of pushing the button below the fold.
///
/// No rounded clip: they are cut-outs on transparency, not photos in a card, so
/// there are no corners to round and nothing to letterbox against — the empty
/// space beside a portrait one is simply the page.
class StepHero extends StatelessWidget {
  final String asset;

  /// The share of the display the picture may take, before the floor and
  /// ceiling below it. Left alone for a full illustration; the sign-in front
  /// door passes a smaller one, because its hero is a logo rather than a scene
  /// and a 280pt app mark is a splash screen.
  final double fraction;

  const StepHero(this.asset, {super.key, this.fraction = 0.32});

  @override
  Widget build(BuildContext context) {
    final maxHeight = (MediaQuery.sizeOf(context).height * fraction).clamp(150.0, 280.0);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Image.asset(asset, fit: BoxFit.contain),
    );
  }
}

/// The pill a step ends with: the app's accent glass, the same material as
/// every other primary action. It was a flat `Container` in the accent colour
/// (the old `PrimaryButton`), which was the one filled rectangle left in an app
/// whose every other button refracts what's behind it.
class StepButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  /// False parks the step: the invite step holds it while an address sits
  /// unsent in the field, and the sign-in form holds it while a code is being
  /// asked for. Drawn as a flat muted pill rather than the glass one faded out
  /// — on iOS the accent pill is a native platform view, and Flutter can't
  /// reliably fade or transform one of those (see docs/design-system.md), so
  /// "off" has to be a different widget rather than the same one at 40%.
  final bool enabled;

  const StepButton({super.key, required this.label, required this.onTap, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return Container(
        padding: stepButtonPadding,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadii.bar),
        ),
        child: Text(label, style: AppText.buttonLarge.copyWith(color: AppColors.mutedLight)),
      );
    }
    return GlassAccentButton(
      label: label,
      onTap: onTap,
      expand: true,
      fontSize: 16,
      padding: stepButtonPadding,
    );
  }
}

/// The padding that *is* a step pill's size — both the accent one and, where a
/// step offers a second way on, the neutral [GlassPillButton] stacked under it.
/// Shared so the pair are the same height: a glass button is measured from the
/// box its label sits in, so two different paddings are two different pills.
const stepButtonPadding = EdgeInsets.symmetric(horizontal: 24, vertical: 16);
