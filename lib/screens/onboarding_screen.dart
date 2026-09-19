import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/calendar_connection.dart';
import '../state/family_state.dart';
import '../state/onboarding_state.dart';
import '../theme/tokens.dart';
import '../widgets/rhythm_picker.dart';
import '../widgets/action_bar.dart';
import '../widgets/app_sheet.dart';
import '../widgets/confirmation.dart';
import '../widgets/error_note.dart';
import '../widgets/family_avatar_button.dart';
import '../widgets/glass.dart';
import '../widgets/inline_dropdown.dart';
import '../widgets/native_switch.dart';
import '../widgets/address_privacy_note.dart';
import '../widgets/house_number_field.dart';
import '../widgets/settings_chrome.dart';
import '../widgets/step_dots.dart';
import '../widgets/toast_chip.dart';
import 'calendar_connect_screen.dart';
import '../l10n/l10n.dart';
import '../theme/app_icons.dart';

/// First-run wizard: welcome -> family (invite) -> address (calendar
/// toggles) -> done. Mirrors the old web app's admin path (see CLAUDE.md's
/// "Ported feature knowledge" -> Onboarding flow) with the wallet step and
/// "Meet Kai" card dropped (out of scope). [replay] is set when reopened
/// from Settings' "Willkommenstour wiederholen" row, which pushes this
/// screen instead of it being the app's `home`.
class OnboardingScreen extends ConsumerWidget {
  final bool replay;

  const OnboardingScreen({super.key, this.replay = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final step = ref.watch(onboardingProvider.select((s) => s.step));

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(
        children: [
          // The last step's party light, outside the safe area on purpose so it
          // reaches the status bar, and outside the switcher so it isn't
          // rebuilt into existence with the step: it fades itself in once the
          // glyph has been read (see [CelebrationGlow]). Painted first, so the
          // wizard's content and its buttons still take every tap.
          if (step >= _stepCount)
            // Not `const`: the wash reads the live palette, and a canonicalised
            // widget would keep the one it was born in (see
            // tool/check_const_palette.dart).
            Positioned(top: 0, left: 0, right: 0, child: CelebrationGlow()),
          // **`top: false`**, so the frost in [_StepChrome] runs edge to edge
          // and an illustration scrolls away under the notch instead of
          // stopping at a hard white band — the same reasoning
          // `CollapsingHeaderScreen` absorbs its own status-bar strip for. Each
          // step leaves the room itself: [_stepTopInset], and the last step,
          // which has no nav row, the bare inset.
          SafeArea(
            top: false,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero).animate(animation),
                  child: child,
                ),
              ),
              child: KeyedSubtree(
                key: ValueKey(step),
                child: switch (step) {
                  0 => _WelcomeStep(replay: replay),
                  1 => _FamilyStep(),
                  2 => _AddressStep(),
                  _ => _DoneStep(replay: replay),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The steps that *ask* something, and so the length of the dot row. The
/// celebration at the end is the outcome, not a fourth question.
const _stepCount = 3;

/// Leaving the tour for good — the "Überspringen" on the first step, and both
/// ways the last one ends.
///
/// The pop is the half that used to be missing: `complete()` closes the gate in
/// `_RootGate`, which is enough on first run because the wizard *is* the app's
/// `home` there. Replayed from Settings it is a pushed route instead, so
/// nothing below it changes and the screen just sat there — the reason skipping
/// looked broken.
///
/// [then] is a page to open once the tour is out of the way, for the last
/// step's offer to connect a personal calendar. It is pushed *after* the pop so
/// it lands on the app rather than on a wizard that is already leaving.
Future<void> _leaveTour(BuildContext context, WidgetRef ref, bool replay, {Widget? then}) async {
  final navigator = Navigator.of(context);
  ref.read(onboardingProvider.notifier).complete();
  if (replay) await navigator.maybePop();
  if (then case final page?) {
    await navigator.push(MaterialPageRoute(builder: (_) => page));
  }
}

/// The wizard's nav bar: the way back, how far in you are, the way out. All
/// three are the app's glass — a bare `IconButton` and a `TextButton` read as
/// two grey words floating over the illustration rather than as controls.
///
/// A `Stack`, **not** a `Row` — the same rule the sheet header and
/// `CollapsingScreenTitle` follow (see docs/design-system.md): the glass
/// buttons are native platform views on iOS, and Flutter content laid out
/// *between* two of them in a row lands in a composited overlay that never
/// shows on device. The dots are therefore a full-width layer painted first,
/// with the two controls aligned over it — which also makes "centred" mean the
/// screen's centre rather than the centre of whatever space they left over.
class _TopBar extends StatelessWidget {
  final int step;
  final VoidCallback? onBack;
  final VoidCallback? onSkip;

  const _TopBar({required this.step, this.onBack, this.onSkip});

  /// The bar's own height — 6 above a 44pt row, 2 below — and the one number
  /// [_StepChrome] and every step's scroll padding have to agree on, since the
  /// body rests below the bar and scrolls *under* it. A constant rather than a
  /// measurement because it genuinely is one: the row is a fixed [SizedBox],
  /// and the dots and the pill are laid out inside it rather than setting it.
  static const height = 6 + 44 + 2.0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screenPad, 6, AppSpacing.screenPad, 2),
      child: SizedBox(
        height: 44,
        child: Stack(
          children: [
            Positioned.fill(
              child: Center(
                child: StepDots(count: _stepCount, index: step),
              ),
            ),
            if (onBack case final back?)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Center(
                  child: GlassIconButton(icon: AppIcons.caretLeft, onTap: back),
                ),
              ),
            if (onSkip case final skip?)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: Center(
                  child: GlassPillButton(label: L.s.skip, onTap: skip),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The room a step's scroll body leaves at the top: the status-bar strip the
/// wizard no longer hands to a `SafeArea`, plus the nav row standing on it.
///
/// Read at the call site rather than threaded through [_StepChrome] — every
/// `bodyBuilder` already has a `BuildContext`, and one number computed the same
/// way in both halves is what keeps the bar and the content it rests below in
/// step.
double _stepTopInset(BuildContext context) => MediaQuery.paddingOf(context).top + _TopBar.height;

/// The chrome every asking step wears: its scrolling body under the nav row,
/// on the same frosted material as every other screen in the app.
///
/// **The body runs to the top of the safe area, not to the bottom of the bar.**
/// Each step used to be a `Column` of [_TopBar] over its content, which meant
/// the scroll viewport began below the bar — so the illustration was sliced by
/// a hard white edge the moment anything scrolled, and the hero read as
/// cropped. Here the body fills the whole area and passes *under* the bar
/// blurred, which is both what the rest of the app does and what the dots and
/// "Überspringen" need in order to stay legible over a picture.
///
/// The band is exactly [_stepTopInset] tall — the notch strip plus the row —
/// because the blur ramps to nothing at its bottom edge (see
/// [FrostedHeaderBackground]): a taller one would put that vanishing point in
/// the middle of the content rather than on the bar's own edge, and a shorter
/// one would leave the status bar as the hard edge instead.
///
/// **Not `const`, like the material it stands on**: it reads [AppColors] inside
/// `build`, and a canonicalised instance would keep the palette it was born in.
/// See the rule on [AppColors] and `tool/check_const_palette.dart`.
class _StepChrome extends StatelessWidget {
  final int step;
  final VoidCallback? onBack;
  final VoidCallback? onSkip;

  /// The step's own [PinnedActionLayout], already built. It is handed over
  /// whole rather than assembled here because each step has its own rules about
  /// when its action is there at all.
  final Widget body;

  // ignore: prefer_const_constructors_in_immutables
  _StepChrome({required this.step, required this.body, this.onBack, this.onSkip});

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
          height: _stepTopInset(context),
          child: FrostedHeaderBackground(),
        ),
        // Last, so the glass pill and the caret are composited above the
        // material they refract rather than behind it.
        Positioned(
          top: statusBar,
          left: 0,
          right: 0,
          child: _TopBar(step: step, onBack: onBack, onSkip: onSkip),
        ),
      ],
    );
  }
}

/// The step's illustration.
///
/// **Fitted, not cropped.** The three PNGs are near-square (1.1–1.35:1) and
/// this used to be a fixed 200pt band at full width — an aspect of ~1.7 — so
/// `BoxFit.cover` cut a third off the top and bottom of every one of them.
/// `contain` shows the whole picture, and the cap is a share of the viewport
/// rather than a constant so the illustration gives way on a small phone
/// instead of pushing the button below the fold.
///
/// No rounded clip: they are cut-outs on transparency, not photos in a card, so
/// there are no corners to round and nothing to letterbox against — the empty
/// space beside a portrait one is simply the page.
class _Hero extends StatelessWidget {
  final String asset;

  const _Hero(this.asset);

  @override
  Widget build(BuildContext context) {
    final maxHeight = (MediaQuery.sizeOf(context).height * 0.32).clamp(150.0, 280.0);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Image.asset(asset, fit: BoxFit.contain),
    );
  }
}

/// The pill each step ends with: the app's accent glass, the same material as
/// every other primary action. It was a flat `Container` in the accent colour
/// (the old `PrimaryButton`), which was the one filled rectangle left in an app
/// whose every other button refracts what's behind it.
class _StepButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  /// False parks the step: the invite step holds it while an address sits
  /// unsent in the field. Drawn as a flat muted pill rather than the glass one
  /// faded out — on iOS the accent pill is a native platform view, and Flutter
  /// can't reliably fade or transform one of those (see docs/design-system.md),
  /// so "off" has to be a different widget rather than the same one at 40%.
  final bool enabled;

  const _StepButton({required this.label, required this.onTap, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    );
  }
}

/// The first step, and the one place the household gets its own name and face.
///
/// **Every signup already has a household**: `handle_new_user` creates one and
/// makes the new user its admin, so this step is not "create a family" — it is
/// the family that already exists being introduced to itself. That is why the
/// field arrives *prefilled* rather than empty, and why there is no save
/// button: the name is written on the way out of the step.
///
/// The avatar and the name are one row, the same row the Settings family page
/// draws (see `family_page.dart`) and for the same reason — a household's
/// picture and its name are one thing to change, not two places to find. It is
/// literally the same [FamilyAvatarButton], which uploads on the pick and needs
/// nothing from this step.
///
/// **And it says what to do if you are in the wrong place.** A second parent who
/// downloads the app and works through this wizard ends up admin of a household
/// of one, next to the household they meant to join — and nothing on screen
/// ever told them. Joining is somebody else's invitation, so the note points at
/// the person who can send one rather than at a control this screen could
/// offer.
class _WelcomeStep extends ConsumerStatefulWidget {
  final bool replay;

  const _WelcomeStep({required this.replay});

  @override
  ConsumerState<_WelcomeStep> createState() => _WelcomeStepState();
}

class _WelcomeStepState extends ConsumerState<_WelcomeStep> {
  late final TextEditingController _nameController;
  final _focusNode = FocusNode();

  /// Mirrors "the field has something in it", kept as state so the button
  /// follows the typing. An empty household name is worse than the default one
  /// it replaced — it is the label on the "Familie" chip in Kalender and on the
  /// Board — so the step holds rather than saving a blank.
  bool _hasName = false;

  /// The letters the circle beside the field is showing, held so that the step
  /// rebuilds on a keystroke that *changes* them and not on the dozen that
  /// don't. [initialsOf] is cheap; the row it sits in is a platform view and a
  /// photograph.
  String _initials = '';

  /// A rename is in flight. Holds the button so a second tap can't send the
  /// same name twice, and so the step can't be left mid-write.
  bool _saving = false;

  /// The field has the keyboard. See [build] for what the button does about it.
  bool _typing = false;

  @override
  void initState() {
    super.initState();
    // Read, not watched: this is the starting value of a field the user is
    // about to edit, and rebuilding it from the provider would fight their
    // typing. `handle_new_user` has always put something here.
    _nameController = TextEditingController(text: ref.read(familyProvider).household?.name ?? '');
    _hasName = _nameController.text.trim().isNotEmpty;
    _initials = initialsOf(_nameController.text);
    _nameController.addListener(_nameChanged);
    _focusNode.addListener(_focusChanged);
  }

  @override
  void dispose() {
    _nameController.removeListener(_nameChanged);
    _nameController.dispose();
    _focusNode.removeListener(_focusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  /// **This is what makes the circle follow the typing.** A household's
  /// `initials` are derived from its *saved* name, which does not change until
  /// the step is left — so without this the avatar sat on the old name's
  /// letters while a new one was being typed beside it, and only caught up
  /// after the write.
  ///
  /// Guarded on both counts, because it fires on every keystroke and almost
  /// none of them change either answer.
  void _nameChanged() {
    final text = _nameController.text;
    final has = text.trim().isNotEmpty;
    final initials = initialsOf(text);
    if (has == _hasName && initials == _initials) return;
    setState(() {
      _hasName = has;
      _initials = initials;
    });
  }

  void _focusChanged() {
    if (_focusNode.hasFocus != _typing) setState(() => _typing = _focusNode.hasFocus);
  }

  /// Writes the name, and answers whether the step may be left.
  ///
  /// [HouseholdNotifier.renameFamily] is optimistic and returns `true` when
  /// there is nothing to write — which is the common path, since the field
  /// arrives prefilled — so the round trip only happens for a name that was
  /// actually changed. It is also the only case worth holding the step for: a
  /// refused write reverts the household to the name the user just replaced,
  /// and advancing would lose what they typed without saying so.
  Future<bool> _saveName() async {
    if (_saving) return false;
    final name = _nameController.text.trim();
    if (name.isEmpty) return false;
    if (name == ref.read(familyProvider).household?.name) return true;

    setState(() => _saving = true);
    final ok = await ref.read(familyProvider.notifier).renameFamily(name);
    if (!mounted) return false;
    setState(() => _saving = false);
    if (!ok) showToast(context, L.s.familyRenameFailed, kind: ToastKind.error);
    return ok;
  }

  Future<void> _next() async {
    FocusScope.of(context).unfocus();
    if (await _saveName() && mounted) ref.read(onboardingProvider.notifier).next();
  }

  /// **Skipping the tour still keeps the name.** It says "skip the rest of
  /// this", not "throw away the one field I filled in", and unlike [_next] it
  /// leaves even if the write is refused — there is nowhere left to hold.
  Future<void> _skip() async {
    FocusScope.of(context).unfocus();
    await _saveName();
    if (mounted) await _leaveTour(context, ref, widget.replay);
  }

  @override
  Widget build(BuildContext context) {
    return _StepChrome(
      step: 0,
      onSkip: _skip,
      body: PinnedActionLayout(
        fadeInto: AppColors.surface,
        // **The accent pill steps aside while a field has the keyboard, and it
        // now does so on all three steps.** It is pinned to the bottom of a
        // viewport the keyboard has already shortened, and Flutter scrolls a
        // focused field into view by the *smallest* amount that works — which
        // parks the field exactly behind the button. The invitations and the
        // address step already gave that strip of screen back for the same
        // reason; this one held on to it because it is the control that
        // *saves* what you are typing, and the result was a blue pill sitting
        // on the field.
        //
        // Nothing the user still needs goes away with it: Return submits the
        // field (`onSubmitted` below), a drag on the body drops the focus and
        // brings the button back, and so does a tap on anything else.
        action: _typing ? null : _StepButton(label: L.s.letsGo, onTap: _next, enabled: _hasName && !_saving),
        bodyBuilder: (context, bottomInset) => SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            AppSpacing.screenPad,
            _stepTopInset(context) + 12,
            AppSpacing.screenPad,
            bottomInset,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Hero('assets/onboarding/hero_welcome.png'),
              const SizedBox(height: 28),
              Text(L.s.onboardSetUpFamily, style: AppText.screenTitle),
              const SizedBox(height: 10),
              Text(L.s.onboardSetUpFamilyBody, style: AppText.body),
              const SizedBox(height: 16),
              SectionCard(
                // The wizard's pages are `AppColors.surface`, so the card has to
                // take the lift on dark or it vanishes — see [SectionCard.onSurface].
                onSurface: true,
                children: [
                  // The Settings row's own metrics — 15/13 inset, a 40pt
                  // leading, 13 to the text — rather than `SettingsRow`
                  // itself, whose title is a `String` and cannot hold a
                  // field. The two rows are the same control either way.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                    child: Row(
                      children: [
                        // An admin by construction: `handle_new_user` makes
                        // the signing-up user their household's admin, and
                        // `_RootGate` only reaches this wizard through it.
                        // [previewName] is what makes the letters follow the
                        // keystrokes rather than the saved name — see
                        // [_nameChanged].
                        FamilyAvatarButton(canEdit: true, previewName: _nameController.text),
                        const SizedBox(width: 13),
                        Expanded(
                          child: TextField(
                            controller: _nameController,
                            focusNode: _focusNode,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _next(),
                            style: AppText.searchInput,
                            // **What keeps "Los geht's" off the field.**
                            // `scrollPadding` is the room the field asks
                            // to be given when it is scrolled into view on
                            // focus, and the default 20 knows nothing
                            // about a bar pinned over the bottom of the
                            // viewport. [bottomInset] is that bar's
                            // measured height, which is exactly the
                            // number, plus a line so the row clears it
                            // rather than touching it.
                            scrollPadding: EdgeInsets.only(bottom: bottomInset + 16),
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              hintText: L.s.familyName,
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _JoinHint(),
            ],
          ),
        ),
      ),
    );
  }
}

/// The answer to "I am not the first in my family", **folded to its question**.
///
/// It has to be on this step — a second parent who works through the wizard
/// ends up admin of a household of one, beside the household they meant to
/// join — but it is the one thing on the page that most readers do not need,
/// and spelled out in full it was three lines under a two-line title and a
/// two-line blurb. So the question is the row and the answer is behind it:
/// somebody in the wrong place recognises their own situation in one line, and
/// everybody else reads past it.
///
/// Guidance rather than a control, so it stays a line of text under the card
/// and not a second card competing with it — the caret is the only affordance
/// it needs. [AnimatedCrossFade] per the expand/collapse rule in
/// docs/design-system.md, with the collapsed side full-width so the block does
/// not shrink-wrap the answer's text.
class _JoinHint extends StatefulWidget {
  // ignore: prefer_const_constructors_in_immutables
  _JoinHint();

  @override
  State<_JoinHint> createState() => _JoinHintState();
}

class _JoinHintState extends State<_JoinHint> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final style = AppText.caption.copyWith(color: AppColors.inkTertiary);
    return GestureDetector(
      onTap: () => setState(() => _open = !_open),
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppIcon(AppIcons.info, size: 15, color: AppColors.mutedLight),
              const SizedBox(width: 7),
              Expanded(child: Text(L.s.onboardJoinExistingFamily, style: style)),
              const SizedBox(width: 6),
              AnimatedRotation(
                turns: _open ? -0.25 : 0.25,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: AppIcon(AppIcons.caretRight, size: 14, color: AppColors.mutedLight),
              ),
            ],
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              // Indented past the info glyph, so the answer hangs off the
              // question rather than starting a new column of text.
              padding: const EdgeInsets.only(left: 22, top: 6),
              child: Text(L.s.onboardJoinExistingFamilyBody, style: style),
            ),
            crossFadeState: _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
            sizeCurve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
          ),
        ],
      ),
    );
  }
}

class _FamilyStep extends ConsumerStatefulWidget {
  const _FamilyStep();

  @override
  ConsumerState<_FamilyStep> createState() => _FamilyStepState();
}

class _FamilyStepState extends ConsumerState<_FamilyStep> {
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();

  /// The role the invitation being typed will carry, and **Erwachsener is what
  /// it starts as** — the commonest invitation by far is the other parent.
  ///
  /// A [FamilyRole] rather than the `bool _isChild` this was, now that the
  /// control is a role dropdown: the two-way translation on every read was one
  /// more place for the row and the invitation to disagree about which of them
  /// meant "child".
  ///
  /// **Admin is deliberately not on the list.** The dropdown offers the two the
  /// chips did, because handing somebody full control of the household is a
  /// decision to take once the family is in it — Settings › Familie is where
  /// the third option lives, on a row that can also take it away again.
  FamilyRole _role = FamilyRole.member;

  /// One invitation is in flight. Holds the send button *and* "Weiter", so a
  /// second tap can't send the same address twice.
  bool _sending = false;

  /// Mirrors "the e-mail field is not empty", kept as state rather than read
  /// off the controller at build time so the button and the hint follow the
  /// typing. Only the e-mail counts: a name on its own can't be invited, so
  /// holding the step for one would be a trap with nothing behind it.
  bool _hasUnsentEmail = false;

  /// One of the two fields has the keyboard. "Weiter" stands down while it
  /// does — see [build] for why this step is the one that hides it.
  bool _typing = false;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_emailChanged);
  }

  @override
  void dispose() {
    _emailController.removeListener(_emailChanged);
    _emailController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _emailChanged() {
    final has = _emailController.text.trim().isNotEmpty;
    // Guarded: this fires on every keystroke, and only the first one of a word
    // changes anything.
    if (has != _hasUnsentEmail) setState(() => _hasUnsentEmail = has);
  }

  /// **The send button sends.** The invitation goes out on the tap, through the
  /// same [HouseholdNotifier.inviteMember] the Settings sheet uses, rather than
  /// being queued for the end of the wizard: the household exists by the time
  /// this step is on screen (`_RootGate` gates on it), so there is nothing to
  /// wait for — and a batch at the end would put every failure that matters
  /// ("nur Admins dürfen einladen", a typo'd address, no network) on the one
  /// screen that is already saying goodbye.
  ///
  /// The onboarding state keeps its own copy of what was sent, which is what
  /// the chips and the last step's recap count.
  Future<bool> _sendInvite() async {
    if (_sending) return false;
    final email = _emailController.text.trim();
    final name = _nameController.text.trim();
    // The same test `inviteMember` applies, said before the round trip: with
    // the button visible, a tap that does nothing reads as a broken button
    // rather than as an empty field.
    if (!email.contains('@')) {
      showToast(context, L.s.enterValidEmail, kind: ToastKind.error);
      return false;
    }

    setState(() => _sending = true);
    final outcome = await ref
        .read(familyProvider.notifier)
        .inviteMember(email: email, name: name, role: _role);
    if (!mounted) return false;
    setState(() => _sending = false);

    if (outcome.error case final message?) {
      // The Edge Function writes its refusals for the user, so its wording wins
      // over anything generic — see [HouseholdNotifier.inviteMember]. The
      // fields keep what was typed: the fix is usually one character.
      showToast(context, message, kind: ToastKind.error);
      return false;
    }

    ref
        .read(onboardingProvider.notifier)
        .addInvite(OnboardingInvite(email: email, name: name, isChild: _role == FamilyRole.kid));
    // Same distinction the Settings confirmation draws: an invitation whose
    // mail didn't go out is still an invitation, and it says so rather than
    // claiming a delivery that didn't happen.
    final sent = outcome.invite!.mailSent;
    showToast(context, sent ? L.s.invitedPerson(name.isNotEmpty ? name : email) : L.s.inviteCreatedTitle);
    // **The keyboard goes down with the invitation that was sent.** Tapping the
    // send button doesn't move the focus by itself, so without this the e-mail
    // field still holds it after a successful send — and "Weiter" hides for as
    // long as it does, leaving the step with no way forward but "Überspringen".
    // A failure keeps the focus on purpose: the fix is usually one character.
    FocusScope.of(context).unfocus();
    setState(() {
      _emailController.clear();
      _nameController.clear();
      _role = FamilyRole.member;
    });
    return true;
  }

  /// **A half-typed invitation holds the step.** The send button beside the
  /// field is easy to read as optional, so typing an address and reaching
  /// straight for "Weiter" used to leave it behind — and the household found
  /// out weeks later that a parent was never invited.
  ///
  /// Rather than guessing on the way out, the button says so *while* the
  /// address is being typed: it goes quiet the moment the field has anything
  /// in it, with one line underneath pointing at the send button. Emptying the
  /// field frees it again, and "Überspringen" was never held at all — neither
  /// of those needs explaining, but both are there for the address that simply
  /// won't send.
  void _goNext() => ref.read(onboardingProvider.notifier).next();

  @override
  Widget build(BuildContext context) {
    final invites = ref.watch(onboardingProvider.select((s) => s.invites));
    final accent = Theme.of(context).colorScheme.primary;

    return _StepChrome(
      step: 1,
      onBack: () => ref.read(onboardingProvider.notifier).back(),
      onSkip: () => ref.read(onboardingProvider.notifier).next(),
      body: PinnedActionLayout(
        fadeInto: AppColors.surface,
        // **"Weiter" steps aside while a field has the keyboard**, which is
        // the opposite of what the sign-in screen does — and the difference
        // is what the button is *for*. There, it submits the field being
        // typed, so keeping it above the keyboard is the same courtesy as
        // an iOS input accessory. Here it leaves the step, while the thing
        // that submits the address is the send button on the row itself. A
        // control that does not act on what you are typing has no claim on
        // the strip of screen the keyboard left over — and this one is
        // *disabled* for as long as the address is unsent, so it would be a
        // dead button holding the best real estate on the step. The hint
        // pointing at the send button lives in the scroll body, so nothing
        // the user still needs goes away with it.
        action: _typing
            ? null
            : _StepButton(label: L.s.next, onTap: _goNext, enabled: !_hasUnsentEmail && !_sending),
        bodyBuilder: (context, bottomInset) => SingleChildScrollView(
          // The second way back out of the keyboard, for the address that
          // won't send and the field that was tapped by mistake: a drag on
          // the body drops the focus, which brings "Weiter" back.
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            AppSpacing.screenPad,
            _stepTopInset(context) + 4,
            AppSpacing.screenPad,
            bottomInset,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Hero('assets/onboarding/hero_members.png'),
              const SizedBox(height: 24),
              Text(L.s.onboardInviteTitle, style: AppText.screenTitle),
              const SizedBox(height: 8),
              Text(L.s.onboardInviteBody, style: AppText.body),
              const SizedBox(height: 16),
              // **Name, Rolle, E-Mail — one card, in the order the sentence
              // is spoken.** The role was a pair of chips above the card, which
              // put the invitation's own property outside the form that holds
              // the rest of it and spent a full row of the step's height saying
              // what one row now says. It is the same [InlineDropdown] the
              // Settings invite sheet and the member rows use, so a role is
              // chosen the same way everywhere — see `family_page.dart`.
              //
              // Same fields as that sheet, too, so they are typed the same
              // way: [AppText.searchInput] in a 56pt row. [AppText.inputTitle]
              // belongs to the *headline* field of a create sheet — a task's
              // text, an event's title — not to an ordinary form field like
              // these.
              //
              // The [Focus] asks the focus tree rather than each field:
              // `hasFocus` on this node is true while anything under it holds
              // the keyboard, so moving from the name to the address is not a
              // moment with no focus in which the bar flickers back.
              Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onFocusChange: (has) {
                  if (has != _typing) setState(() => _typing = has);
                },
                child: SectionCard(
                  // The wizard's pages are `AppColors.surface`, so the card has to
                  // take the lift on dark or it vanishes — see [SectionCard.onSurface].
                  onSurface: true,
                  children: [
                    _InviteFieldRow(
                      child: TextField(
                        controller: _nameController,
                        textInputAction: TextInputAction.next,
                        style: AppText.searchInput,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: L.s.nameOptional,
                          isDense: true,
                        ),
                      ),
                    ),
                    CardDivider(onSurface: true),
                    _InviteFieldRow(
                      child: Row(
                        children: [
                          Expanded(child: Text(L.s.role, style: AppText.rowTitle)),
                          // Erwachsener/Kind rather than the role *names*: this
                          // is the first thing a household is asked about
                          // anybody, and "Mitglied" answers a question about
                          // permissions that nobody has been asked yet.
                          InlineDropdown<FamilyRole>(
                            value: _role,
                            menuTitle: L.s.role,
                            onChanged: (r) => setState(() => _role = r),
                            choices: [
                              DropdownChoice(
                                value: FamilyRole.member,
                                label: L.s.adult,
                                icon: AppIcons.user,
                                symbol: 'person',
                              ),
                              DropdownChoice(
                                value: FamilyRole.kid,
                                label: L.s.child,
                                icon: AppIcons.baby,
                                symbol: 'figure.child',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    CardDivider(onSurface: true),
                    _InviteFieldRow(
                      // Inset on the right for the send button, which is taller
                      // than the text it sits beside.
                      trailingPad: 8,
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              autocorrect: false,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _sendInvite(),
                              style: AppText.searchInput,
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                hintText: L.s.emailAddress,
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // The spinner takes the button's place rather than
                          // sitting over it, so the row doesn't reflow while an
                          // invitation is on its way out.
                          if (_sending)
                            const SizedBox(
                              width: 36,
                              height: 36,
                              child: Center(
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            )
                          else
                            GlassConfirmButton(
                              icon: AppIcons.paperPlaneTilt,
                              size: 36,
                              onTap: _sendInvite,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Points at the button that is being overlooked, in the accent
              // that button is drawn in, and only while there is something to
              // send. It says what to do rather than what went wrong: nothing
              // has gone wrong yet, which is the whole idea.
              if (_hasUnsentEmail) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    AppIcon(AppIcons.arrowUp, size: 14, color: accent),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(L.s.tapSendToInvite, style: AppText.caption.copyWith(color: accent)),
                    ),
                  ],
                ),
              ],
              if (invites.isNotEmpty) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final invite in invites)
                      Chip(label: Text(invite.name.isNotEmpty ? invite.name : invite.email)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One row of the invitation card, sized like the Settings invite sheet's
/// `_InviteRow` so the two forms are the same control in two places.
class _InviteFieldRow extends StatelessWidget {
  final Widget child;
  final double trailingPad;

  const _InviteFieldRow({required this.child, this.trailingPad = 16});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, trailingPad, 0),
        child: Center(child: child),
      ),
    );
  }
}

/// **One question, and two calendars out of it.**
///
/// The household types where they live — the same address picker the Abfall
/// connect flow uses, because it is the same lookup — and everything after that
/// is us doing the work: the waste vendor that serves the street and the
/// Bundesland whose school holidays apply both fall out of the picked address,
/// and both arrive already ticked. Nobody is asked to choose their own
/// Bundesland off a list of sixteen, and nobody has to know that "Abfall" is
/// even a thing you connect.
///
/// The lookup lives in [OnboardingNotifier], not here: this widget is swapped
/// out by the wizard's `AnimatedSwitcher` whenever a step is taken, and a
/// resolved address must survive a trip back to the invitations.
class _AddressStep extends ConsumerStatefulWidget {
  const _AddressStep();

  @override
  ConsumerState<_AddressStep> createState() => _AddressStepState();
}

class _AddressStepState extends ConsumerState<_AddressStep> {
  late final TextEditingController _addressController;
  final _houseNrController = TextEditingController();
  final _houseNrFocus = FocusNode();

  /// Whether the address field holds the keyboard. See the note on [action]
  /// below for why "Weiter" cares.
  bool _typing = false;

  @override
  void initState() {
    super.initState();
    _addressController = TextEditingController(text: ref.read(onboardingProvider).address);
  }

  @override
  void dispose() {
    _addressController.dispose();
    _houseNrController.dispose();
    _houseNrFocus.dispose();
    super.dispose();
  }

  OnboardingNotifier get _onboarding => ref.read(onboardingProvider.notifier);

  Future<void> _pick(GeoAddress found) async {
    // A bare postcode goes back into the field so the street can be typed after
    // it; a street without its house asks for the number under it; anything
    // else is the answer, and the lookup starts on the spot.
    final prefix = _onboarding.prefixQueryFor(found);
    if (prefix != null) {
      _addressController.text = prefix;
      _addressController.selection = TextSelection.collapsed(offset: prefix.length);
      return;
    }
    if (_onboarding.askHouseNumber(found)) {
      _addressController.text = found.label;
      _houseNrController.clear();
      _houseNrFocus.requestFocus();
      return;
    }
    FocusScope.of(context).unfocus();
    _addressController.text = found.label;
    await _onboarding.pickAddress(found);
    _backToNumberIfRefused(found.houseNumber);
  }

  Future<void> _confirmHouseNumber() async {
    final typed = _houseNrController.text;
    FocusScope.of(context).unfocus();
    await _onboarding.confirmHouseNumber(typed);
    _backToNumberIfRefused(typed);
  }

  /// The vendor knew the street and not the house: the number field is back,
  /// holding what was tried, with the keyboard up.
  void _backToNumberIfRefused(String? tried) {
    if (!mounted || ref.read(onboardingProvider).streetOnly == null) return;
    _houseNrController.text = tried?.trim() ?? '';
    _houseNrFocus.requestFocus();
  }

  /// The step's own way forward: file the address, create whatever is still
  /// ticked, then move on. A failed connect keeps the step — the error says
  /// what happened and the button retries — but "Überspringen" is still there,
  /// because nobody should be held in a wizard by a waste vendor being down.
  Future<void> _continue() async {
    final state = ref.read(onboardingProvider);
    if (state.connecting) return;
    // The waste questions are a stage of this step: "Weiter" puts them away
    // and shows the calendars, and only the next "Weiter" leaves.
    if (state.askingWaste) {
      _onboarding.finishWasteQuestions();
      return;
    }
    // A number typed and never sent — the keyboard dragged away before "Fertig"
    // — is sent now rather than left behind with the calendar it would find.
    if (state.streetOnly != null && _houseNrController.text.trim().isNotEmpty) {
      await _confirmHouseNumber();
      return;
    }
    if (await _onboarding.connectLocalCalendars()) _onboarding.next();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingProvider);

    return _StepChrome(
      step: 2,
      onBack: () => _onboarding.back(),
      onSkip: () => _onboarding.next(),
      body: PinnedActionLayout(
        fadeInto: AppColors.surface,
        // The lookup replaces the button with its spinner rather than
        // greying it out, same as it always did — the bar keeps the height
        // either way, so the step doesn't jump while an address resolves.
        //
        // **"Weiter" steps aside while the address field has the
        // keyboard**, for the same reason it does on the invitations: the
        // button leaves the step, while the thing that submits an address
        // is the suggestion row under the field. Held above the keyboard it
        // covered both the field and the first suggestions — the one strip
        // of screen the step still needed — so a control that does not act
        // on what is being typed gives it back.
        action: state.connecting
            ? _InlineBusy()
            : (_typing ? null : _StepButton(label: L.s.next, onTap: _continue)),
        bodyBuilder: (context, bottomInset) => SingleChildScrollView(
          // A drag on the body drops the focus, which brings "Weiter" back
          // for the address that was typed and never picked.
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            AppSpacing.screenPad,
            _stepTopInset(context) + 4,
            AppSpacing.screenPad,
            bottomInset,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // **The step becomes a search screen while the field has the
              // keyboard**, the way an iOS search field slides to the top of
              // its own screen and hands the rest of the display to the
              // results: the illustration, the title and the blurb fold up
              // under the header, the card rises to the top, and all six
              // suggestions the geocoder can return fit above the keyboard
              // instead of one and a half.
              //
              // They fold rather than vanish, and back down again when an
              // address is picked or the field is left, so the step the
              // household was reading is the step they come back to.
              //
              // [AnimatedCrossFade] rather than an `if`, per the
              // expand/collapse rule in docs/design-system.md — it keeps both
              // states around so the block sizes *and* fades in both
              // directions — and the collapsed side is a
              // `SizedBox(width: double.infinity)` so the stack it builds
              // keeps full width rather than shrink-wrapping the hero.
              AnimatedCrossFade(
                firstChild: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Hero('assets/onboarding/hero_address.png'),
                    const SizedBox(height: 24),
                    Text(L.s.onboardAddressTitle, style: AppText.screenTitle),
                    const SizedBox(height: 8),
                    Text(L.s.onboardAddressBody, style: AppText.body),
                    const SizedBox(height: 20),
                  ],
                ),
                secondChild: const SizedBox(width: double.infinity),
                // Folded, too, for everything the address still asks after the
                // pick — the house number, the lookup, the rhythm questions —
                // so those get the screen the suggestions had, and the hero
                // comes back only with the answer: the calendars and their
                // switches. Folding once and opening once, rather than opening
                // between a pick and the question it raises.
                crossFadeState: _typing || state.streetOnly != null || state.lookingUp || state.askingWaste
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 260),
                sizeCurve: Curves.easeOutCubic,
                // Bottom-aligned, so the block slides up out of sight under
                // the frosted header instead of collapsing towards its own
                // middle and squashing the illustration on the way.
                alignment: Alignment.bottomCenter,
              ),
              // Asks the focus tree rather than the field itself, exactly
              // as the invitations do: the card's rows come and go as the
              // lookup answers, and a rebuilt field must not read as a
              // moment with no focus in which the bar flickers back.
              Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onFocusChange: (has) {
                  if (has != _typing) setState(() => _typing = has);
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // **The group's name, once there is something to call it.**
                    // The card used to wear a `FieldGroup` heading reading
                    // "Adresse" over a row that was showing one — a whole
                    // block of the step's height spent labelling a house
                    // number with the word "address" — and the two feeds it
                    // produced then started a *second* labelled card below.
                    // One section, named for what it holds.
                    //
                    // Tied to [OnboardingState.found] rather than to the
                    // picked address, because "Für eure Adresse gefunden"
                    // over "Kalender werden gesucht…" would be a heading
                    // contradicting the row under it.
                    //
                    // An `else` rather than a bare `if`, so the card stays the
                    // Column's second child either way: a row list that slides
                    // from index 0 to index 1 is unmounted and rebuilt, which
                    // is the same trap [PinnedActionLayout] fell into with the
                    // body it sometimes wrapped in a `Stack`.
                    if (state.askingWaste)
                      GroupLabel(L.s.onboardRhythmTitle)
                    else if (state.found != null)
                      GroupLabel(L.s.onboardFoundForYou)
                    else
                      const SizedBox.shrink(),
                    SectionCard(
                      radius: AppRadii.card,
                      onSurface: true,
                      children: dividedRows(_addressRows(state), inset: true, onSurface: true),
                    ),
                  ],
                ),
              ),
              AddressPrivacyNote(),
              if (state.found case final found? when !state.askingWaste) ...[
                const SizedBox(height: 10),
                SettingsNote(found.any ? L.s.onboardRenameLater : L.s.onboardNothingForAddress),
              ],
              if (state.addressError case final message?) ...[
                const SizedBox(height: 12),
                ErrorNote(message: message),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// One card for the whole lookup — the field, the suggestions, and the
  /// address we settled on — so the step never grows a second half.
  List<Widget> _addressRows(OnboardingState state) {
    final picked = state.pickedAddress;
    final street = state.streetOnly;
    if (picked == null && street != null) {
      return [
        SettingsRow(
          icon: AppIcons.house,
          title: street.streetLine,
          subtitle: street.townLine,
          trailing: _clearButton(),
        ),
        FieldGroup(
          label: L.s.houseNumberAsk,
          hint: L.s.houseNumberAskHint,
          child: HouseNumberField(
            controller: _houseNrController,
            focusNode: _houseNrFocus,
            onSubmitted: _confirmHouseNumber,
          ),
        ),
      ];
    }
    if (picked == null) {
      return [
        FieldGroup(
          // No hint: the paragraph above the card already says what the address
          // is for, and repeating it here reads as two apps talking at once.
          label: L.s.yourAddress,
          child: FieldBox(
            child: TextField(
              controller: _addressController,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.search,
              style: AppText.searchInput,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: L.s.addressPlaceholder,
                isDense: true,
              ),
              onChanged: _onboarding.onAddressQueryChanged,
            ),
          ),
        ),
        if (state.searchingAddress)
          _BusyRow(L.s.searchingAddresses)
        else if (state.addressResults.isEmpty && state.address.trim().length >= 3)
          _MutedRow(L.s.noAddressFound),
        for (final found in state.addressResults)
          SettingsRow(
            icon: found.prefix ? AppIcons.mapPin : AppIcons.house,
            title: found.streetLine,
            subtitle: found.townLine,
            onTap: () => _pick(found),
          ),
      ];
    }

    return [
      SettingsRow(
        icon: AppIcons.house,
        title: picked.streetLine,
        subtitle: picked.townLine,
        trailing: _clearButton(),
      ),
      if (state.lookingUp) _BusyRow(L.s.onboardFindingCalendars),
      // **The questions first, the switches after.** Whatever the waste vendor
      // asks — the house off its list, a bin's rhythm — is asked on its own,
      // in the search layout. A question under the Müllabfuhr switch put a form
      // inside a list of toggles; the calendars it was for follow on "Weiter".
      if (state.found case final found? when state.askingWaste)
        ..._wasteQuestions(found)
      else if (state.found case final found?)
        ..._calendarRows(found, state),
    ];
  }

  /// Everything the waste vendor asks before its calendar can be connected, in
  /// the order it is asked: which house on its list, where the typed number
  /// did not settle that, then how often each bin is emptied — for that house.
  List<Widget> _wasteQuestions(LocalCalendars found) {
    final coverage = found.abfall!;
    return [
      if (coverage.houseNumbers.isNotEmpty)
        FieldGroup(
          label: L.s.houseNumber,
          hint: coverage.needsHouseNumber ? L.s.pickHouseNumberHint : L.s.multipleDistrictsHint,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final house in coverage.houseNumbers)
                AnswerChip(
                  label: house.nr,
                  selected: found.house?.id == house.id,
                  onTap: () => _onboarding.pickHouse(house),
                ),
            ],
          ),
        ),
      if (found.rhythms.isNotEmpty)
        RhythmPicker(choices: found.rhythms, picked: found.rhythm, onPick: _onboarding.pickRhythm),
    ];
  }

  /// The X on the address row: back to an empty field.
  Widget _clearButton() => GestureDetector(
    onTap: () {
      _addressController.clear();
      _houseNrController.clear();
      _onboarding.resetAddress();
    },
    behavior: HitTestBehavior.opaque,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: AppIcon(AppIcons.x, size: 17, color: AppColors.muted),
    ),
  );

  /// The two feeds the address produced — **rows of the address card, not a
  /// card of their own.**
  ///
  /// They were a `_FoundCalendars` widget with its own [GroupLabel] and
  /// [SectionCard], which meant the step answered one question with two
  /// labelled blocks: the address you gave, then the calendars found for it.
  /// They are one thing — this address, and what is available at it — so they
  /// are one card, and the address row above them is its first line.
  List<Widget> _calendarRows(LocalCalendars found, OnboardingState state) {
    final coverage = found.abfall;
    final where = coverage == null
        ? null
        : coverage.street == null
        ? coverage.town
        : '${coverage.street}, ${coverage.town}';

    return [
      _CalendarRow(
        icon: AppIcons.recycle,
        title: L.s.wasteCalendar,
        subtitle: found.hasAbfall
            ? where
            : coverage?.needsHouseNumber == true
            ? L.s.wasteNeedsHouseNumber
            : coverage?.uploadOnly == true
            ? L.s.wasteUploadOnlyLater
            : coverage?.requested == true
            ? L.s.wasteRequested
            : L.s.wasteRequestHint,
        value: found.hasAbfall ? state.trashCalendar : null,
        onChanged: _onboarding.setTrashCalendar,
        // The lookup ran and no vendor answered: the row offers to have us
        // find one. A lookup that *failed* (coverage null) offers nothing —
        // there is no town to file — and a vendor that only wants the house
        // number is not missing either.
        // A town served only by a file has nothing for us to set up either.
        missingAction: coverage == null || coverage.requested || coverage.needsHouseNumber || coverage.uploadOnly
            ? null
            : _MissingAction(
                label: L.s.wasteRequestAction,
                busy: state.requestingTrash,
                onTap: _onboarding.requestTrash,
              ),
        done: coverage?.requested == true,
      ),
      _CalendarRow(
        icon: AppIcons.graduationCap,
        title: L.s.holidayCalendar,
        subtitle: found.hasFerien ? bundeslaender[found.ferienState] : L.s.onboardNotFoundHere,
        value: found.hasFerien ? state.ferienCalendar : null,
        onChanged: _onboarding.setFerienCalendar,
      ),
    ];
  }
}

/// What a missing calendar's row offers instead of a switch: the one verb that
/// can still make it exist.
class _MissingAction {
  final String label;
  final bool busy;
  final VoidCallback onTap;

  const _MissingAction({required this.label, required this.busy, required this.onTap});
}

/// A calendar the lookup found, with its switch — or one it didn't, greyed and
/// carrying an X where the switch would be. A **disabled switch** is the thing
/// this deliberately isn't: it invites a tap that can't do anything, where the
/// X simply says there is nothing here to turn on.
///
/// The Müllabfuhr row is the exception with a way forward: no vendor of ours
/// serving the street is *our* gap, not the household's, so instead of the X
/// it carries [missingAction] — "Anfragen" — and, once tapped, a check and the
/// sentence saying we are on it ([done]).
class _CalendarRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  /// Null means the lookup found nothing for this one.
  final bool? value;
  final ValueChanged<bool> onChanged;

  final _MissingAction? missingAction;
  final bool done;

  const _CalendarRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.missingAction,
    this.done = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final missing = value == null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadii.iconTile),
            ),
            alignment: Alignment.center,
            child: AppIcon(icon, size: 17, color: missing ? AppColors.mutedLight : accent),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.rowTitle.copyWith(color: missing ? AppColors.muted : null)),
                if (subtitle case final line?)
                  // The request sentence is a sentence, and gets the second line
                  // an address never needs.
                  Text(
                    line,
                    maxLines: missing && !done ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.label,
                  ),
              ],
            ),
          ),
          if (value case final on?)
            NativeSwitch(value: on, onChanged: onChanged)
          else if (done)
            AppIcon(AppIcons.check, size: 16, color: AppColors.success)
          else if (missingAction case final action?)
            _SmallPill(label: action.label, busy: action.busy, onTap: action.onTap)
          else
            AppIcon(AppIcons.x, size: 16, color: AppColors.mutedLight),
        ],
      ),
    );
  }
}

/// The accent-tinted word at the end of a row — the same drawing as the
/// connect flow's house-number chips, selected — sized to a row's height. A
/// spinner takes the word's place while the tap is on its way, so the pill
/// cannot be tapped twice and nothing jumps.
class _SmallPill extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback onTap;

  const _SmallPill({required this.label, required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: busy ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadii.chip),
        ),
        child: busy
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: accent),
              )
            : Text(label, style: AppText.buttonSmall.copyWith(color: accent)),
      ),
    );
  }
}

class _BusyRow extends StatelessWidget {
  final String label;

  const _BusyRow(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      child: Row(
        children: [
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: AppText.body.copyWith(color: AppColors.muted)),
          ),
        ],
      ),
    );
  }
}

class _MutedRow extends StatelessWidget {
  final String text;

  const _MutedRow(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      child: Text(text, style: AppText.body.copyWith(color: AppColors.muted)),
    );
  }
}

/// Where the step's button sits while its calendars are being created — in its
/// place rather than over it, so nothing jumps and the button cannot be tapped
/// twice.
class _InlineBusy extends StatelessWidget {
  /// Not `const`, deliberately: it reads `L.s` and a palette colour inside its
  /// own `build`, and a canonicalised const instance would keep the language
  /// and the palette it was first built with. Same trade as
  /// `FrostedHeaderBackground`.
  // ignore: prefer_const_constructors_in_immutables
  _InlineBusy();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 12),
          Text(L.s.onboardConnectingCalendars, style: AppText.body.copyWith(color: AppColors.muted)),
        ],
      ),
    );
  }
}

/// The last step, and the app's one confirmation ([ConfirmationView]) in its
/// celebration shape — the household exists now, which happens exactly once
/// per family. Its content is the recap of what the wizard did set up, and its
/// way out is the same accent pill the earlier steps end with, so the flow
/// doesn't change its button on the last screen.
///
/// This one is a **page**, not a sheet, so it is given the viewport's full
/// height (`minHeight`) rather than hugging its content: the confetti falls
/// over whatever box the confirmation occupies, and on a page that box has to
/// be the page or the paper stops in mid-air above the fold.
class _DoneStep extends ConsumerWidget {
  final bool replay;

  const _DoneStep({required this.replay});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingProvider);
    final family = ref.watch(familyProvider);
    // **The recap reports what *this tour* did, and nothing else.** These two
    // used to fall back on `calendarConnectionsProvider` — "does the household
    // have an Abfall feed at all?" — which is a different question and answers
    // yes for reasons that have nothing to do with the last three screens: a
    // tour skipped outright, or an address with no waste vendor, still
    // finished by ticking both rows because a feed from some earlier address
    // was sitting in the list. [OnboardingNotifier.connectLocalCalendars] is
    // the only thing that may set these, and it credits an existing
    // subscription only when *this* lookup found the same calendar.
    final hasTrash = state.trashConnected;
    final hasFerien = state.ferienConnected;
    // This step carries no [_TopBar], so its share of [_stepTopInset] is the
    // status-bar strip alone — the wizard hands it to each step rather than to
    // a `SafeArea` (see [OnboardingScreen.build]). Held here because the
    // minimum height below has to subtract exactly what the padding added.
    final topPad = MediaQuery.paddingOf(context).top + 20;

    return PinnedActionLayout(
      fadeInto: AppColors.surface,
      // The celebration's own pill, moved out of the confirmation and onto the
      // bottom edge with the other three steps' — which is why the view is
      // asked for [ConfirmationAction.none] rather than an accent pill. The
      // recap cards are the content here; the way out of the tour is not part
      // of them.
      action: _StepButton(label: L.s.letsGo, onTap: () => _leaveTour(context, ref, replay)),
      bodyBuilder: (context, bottomInset) => LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(AppSpacing.screenPad, topPad, AppSpacing.screenPad, bottomInset),
          child: ConstrainedBox(
            // Minus the padding this scroll view already adds, so a screen that
            // exactly fits doesn't gain a scrollbar's worth of overflow.
            constraints: BoxConstraints(minHeight: constraints.maxHeight - topPad - bottomInset),
            child: ConfirmationView(
              mark: ConfirmationMark.celebration,
              headline: L.s.onboardReady,
              message: L.s.onboardReadyBody,
              action: ConfirmationAction.none,
              content: [
                SectionCard(
                  // The wizard's pages are `AppColors.surface`, so the card has to
                  // take the lift on dark or it vanishes — see [SectionCard.onSurface].
                  onSurface: true,
                  children: [
                    // **The household leads the recap, because it is the one
                    // thing the tour certainly did.** The first step gives the
                    // family its name and its picture, and until this row
                    // existed the celebration reported on three things that
                    // may all have been skipped and said nothing about the
                    // one that cannot be. Ticked for the same reason: a
                    // household always has a name by the time it gets here.
                    //
                    // Not editable — `canEdit: false`, so the circle carries
                    // no camera badge. This is a receipt, and the place to
                    // change either half is Settings › Familie, which the line
                    // above the card already points at.
                    if (family.household case final household?) ...[
                      _RecapRow(
                        leading: FamilyAvatarButton(canEdit: false, size: _RecapRow._leadingSlot),
                        label: household.name,
                        done: true,
                      ),
                      CardDivider(onSurface: true),
                    ],
                    _RecapRow(
                      icon: AppIcons.userPlus,
                      label: state.invites.isEmpty
                          ? L.s.noInvitesSent
                          : L.s.invitedCount(state.invites.length),
                      done: state.invites.isNotEmpty,
                    ),
                    CardDivider(onSurface: true),
                    _RecapRow(icon: AppIcons.recycle, label: L.s.wasteCalendar, done: hasTrash),
                    CardDivider(onSurface: true),
                    _RecapRow(icon: AppIcons.graduationCap, label: L.s.holidayCalendar, done: hasFerien),
                  ],
                ),
                // The personal accounts, offered exactly once and never as a
                // step. Google and Outlook consent happens in Safari and comes
                // back through a deep link — the most fragile minute in the app,
                // and no place for it is worse than the middle of a wizard. So
                // the tour finishes first and this lands on the connect page with
                // onboarding already behind it.
                SectionCard(
                  // The wizard's pages are `AppColors.surface`, so the card has to
                  // take the lift on dark or it vanishes — see [SectionCard.onSurface].
                  onSurface: true,
                  children: [
                    SettingsRow(
                      icon: AppIcons.calendarPlus,
                      title: L.s.connectCalendars,
                      subtitle: L.s.onboardConnectMoreHint,
                      onTap: () => _leaveTour(context, ref, replay, then: CalendarConnectionsPage()),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecapRow extends StatelessWidget {
  final IconData? icon;

  /// Stands in for [icon] on the row that has a *face* rather than a symbol:
  /// the household's own picture on the first line. Sized by the caller to
  /// [_leadingSlot], which is what keeps the four labels in one column.
  final Widget? leading;

  final String label;
  final bool done;

  const _RecapRow({this.icon, this.leading, required this.label, required this.done})
    : assert(icon != null || leading != null);

  /// The width the leading column reserves. Wide enough for the avatar, so a
  /// 18pt glyph centres in it rather than every label shifting by row.
  static const _leadingSlot = 26.0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: _leadingSlot,
            child: Center(child: leading ?? AppIcon(icon, size: 18, color: AppColors.muted)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: AppText.rowTitle)),
          AppIcon(
            done ? AppIcons.check : AppIcons.x,
            size: 16,
            color: done ? AppColors.success : AppColors.mutedLight,
          ),
        ],
      ),
    );
  }
}
