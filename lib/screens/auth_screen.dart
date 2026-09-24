import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/auth_state.dart';
import 'auth/front_door_hero.dart';
import 'auth/greeting_hero.dart';
import '../theme/tokens.dart';
import '../widgets/action_bar.dart';
import '../widgets/app_sheet.dart';
import '../widgets/collapsing_header.dart';
import '../widgets/confirmation.dart';
import '../widgets/error_note.dart';
import '../widgets/glass.dart';
import '../widgets/settings_chrome.dart';
import '../widgets/step_page.dart';
import '../l10n/l10n.dart';
import '../theme/app_icons.dart';

/// Registration and sign-in — the app's front door, and the one part of the app
/// a stranger sees.
///
/// Three steps, on the welcome tour's own [StepPage] chrome, because the tour
/// starts the moment the last of them finishes and the two must not look like
/// two apps: the **front door** (the picture, the name, and the two ways in),
/// the **form** (a name where one is being created, an address), and
/// [_CodeEntry]. The back caret is the way between them, which is why the form
/// and the code screen carry one and the front door does not.
///
/// Registering is the primary action, and it is deliberately cheap: no
/// household to name, no members to add, nothing to choose. `handle_new_user`
/// creates the profile, a household and an admin membership server-side in the
/// same transaction as the account, so a brand-new user lands in a working
/// household immediately. Onboarding then only renames it.
///
/// There is no password anywhere on it: both ways in end in a code sent to the
/// address.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

/// Which of the three the visitor is standing at. Two of them are this
/// screen's own business; the third is the auth status', since the code screen
/// is where the session is and is not this widget's to leave.
enum _Door { landing, form, code }

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();

  /// Past the front door, and which way in was picked. Both survive the code
  /// screen — `changeEmail` comes back to the form the address was typed on,
  /// with the address still in it.
  bool _atForm = false;
  bool _register = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _openForm({required bool register}) {
    ref.read(authProvider.notifier).clearError();
    setState(() {
      _atForm = true;
      _register = register;
    });
  }

  void _backToDoor() {
    FocusScope.of(context).unfocus();
    ref.read(authProvider.notifier).clearError();
    setState(() => _atForm = false);
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    ref
        .read(authProvider.notifier)
        .requestCode(email: _emailController.text, displayName: _register ? _nameController.text : null);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final atCode = auth.status == AuthStatus.awaitingCode || auth.status == AuthStatus.codeAccepted;
    final door = atCode ? _Door.code : (_atForm ? _Door.form : _Door.landing);

    return Scaffold(
      backgroundColor: AppColors.surface,
      // **Neither edge, and both for the same reason: whatever is on them is
      // drawn by the page rather than fenced off from it.**
      //
      // `top: false` lets the frost in [StepPage] run to the notch instead of
      // stopping at a hard white band; each step leaves the room itself with
      // [stepTopInset]. `bottom: false` lets the front door's gray panel run to
      // the bottom of the display instead of stopping above the home indicator
      // and leaving a white strip under it — a panel with a band of the wrong
      // colour beneath it reads as a card that failed to reach, which is
      // exactly what it was. Nothing is lost: [PinnedActionBar] reads the
      // home-indicator height itself and keeps the pills off the glass edge,
      // which is what it already did on every screen that left the bottom to
      // it.
      body: SafeArea(
        top: false,
        bottom: false,
        child: AnimatedSwitcher(
          duration: _doorTransition,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero).animate(animation),
              child: child,
            ),
          ),
          child: KeyedSubtree(
            key: ValueKey(door),
            child: switch (door) {
              _Door.landing => _landing(context),
              _Door.form => _form(context, auth),
              _Door.code => _CodeEntry(email: auth.email ?? ''),
            },
          ),
        ),
      ),
    );
  }

  /// The front door: the picture, the name, and the two ways in.
  ///
  /// The name, then [FrontDoorHero] — the household using the app, played
  /// rather than photographed, and ending on the welcome illustration with the
  /// promise typing itself out underneath — on [AppColors.surface], with the
  /// app's own gray [ScreenBodyPanel] under both. That is the same two-surface
  /// split every other screen has under its header, and the panel is bare here
  /// because everything it used to say is now said by the picture. No logo: the
  /// cards in the picture are already the app, and a mark over them would turn
  /// the page into a splash screen.
  ///
  /// The name is a brand, so it is a literal rather than a string — the one
  /// piece of copy that is the same in all four languages, the way the shop
  /// names in `merchant_logos.dart` are.
  ///
  /// Both buttons are glass, and the accent one is the answer: a household
  /// arriving here has no account, and "Anmelden" is for the second phone.
  Widget _landing(BuildContext context) {
    return PinnedActionLayout(
      fadeInto: AppColors.screenBg,
      action: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StepButton(label: L.s.createAccount, onTap: () => _openForm(register: true)),
          const SizedBox(height: 10),
          // The neutral pill under the accent one, at the accent one's own
          // padding so the pair are one control's height — see
          // [stepButtonPadding].
          GlassPillButton(
            label: L.s.signIn,
            onTap: () => _openForm(register: false),
            expand: true,
            padding: stepButtonPadding,
          ),
        ],
      ),
      bodyBuilder: (context, bottomInset) => Column(
        children: [
          SizedBox(height: MediaQuery.paddingOf(context).top + 14),
          // The name sits over the picture rather than under it, in the
          // headroom the composition was leaving empty anyway. It is real text
          // out here and not part of the canvas, so it keeps its own type scale
          // — [FrontDoorHero] switches scaling off *inside* the drawing, which
          // is a fixed layout, and must not switch it off for a headline.
          Text('aporah', style: AppText.screenTitle),
          const SizedBox(height: 10),
          // **Whatever the column leaves over**, which is the paywall hero's
          // rule: the words and the two buttons are a fixed cost and the
          // picture gets the rest.
          Expanded(child: FrontDoorHero()),
          // The app's own gray body panel, doing here exactly what it does
          // under every other screen's header: it is the line between the thing
          // you are looking at and the thing you are reading. It runs to the
          // bottom of the display rather than stopping above the buttons, so
          // the pair of pills sit *on* it — which is why the body carries no
          // bottom padding of its own and the panel carries [bottomInset]
          // instead.
          //
          // **Empty, and that is the point.** It used to hold the tagline,
          // which put the promise a full panel away from the picture making it
          // — two separate claims on one page. The sentence now types itself
          // out under the illustration at the end of [FrontDoorHero], where it
          // is the caption of the thing it describes, and what is left here is
          // the ground the two pills stand on.
          ScreenBodyPanel(
            child: SizedBox(height: bottomInset + 4, width: double.infinity),
          ),
        ],
      ),
    );
  }

  /// The one form: a name when an account is being created, an address always.
  ///
  /// **The front door's picture carries on over it.** The same 'aporah' at the
  /// top, and under it the landing's own dot grid with the story replaced by
  /// the greeting — see [GreetingHero].
  ///
  /// **The fields are the app's own, not this page's.** They were a pair of
  /// bare rows in a card with a hint for a name and nothing above them —
  /// invented here and nowhere else in the app. They are now [FieldGroup] over
  /// [FieldBox], which is what every other form in the app is made of, from the
  /// welcome tour's address step to the profile page.
  Widget _form(BuildContext context, AuthScreenState auth) {
    return StepPage(
      onBack: _backToDoor,
      backLabel: L.s.back,
      // **The name, where the page before it puts the name.** It goes in the
      // bar's centre layer rather than at the top of the scroll because the
      // body passes *under* the frosted band — a title laid out there would be
      // blurred where it stands. [StepTopBar] is a `Stack` for exactly this
      // reason, so the caret sits over it rather than beside it.
      center: Text('aporah', style: AppText.screenTitle),
      body: PinnedActionLayout(
        fadeInto: AppColors.surface,
        // The Scaffold resizes for the keyboard, so the bar rides up with it
        // and the action a filled-in form is reaching for stays in view
        // instead of being the thing the keyboard covers.
        action: StepButton(
          label: _register ? L.s.createAccount : L.s.signIn,
          onTap: _submit,
          // Disabled rather than spinning while the code is asked for: on iOS
          // the accent pill is a native platform view and the tour settled this
          // the same way (see [StepButton.enabled]).
          enabled: !auth.busy,
        ),
        bodyBuilder: (context, bottomInset) => SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          // **No side padding on the scroll itself**: the dot field is paper
          // and runs edge to edge like the landing's does, so the screen
          // margin is carried by what sits below it instead.
          padding: EdgeInsets.only(top: stepTopInset(context), bottom: bottomInset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GreetingHero(greeting: _register ? L.s.greetingWelcome : L.s.greetingWelcomeBack),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPad),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Centred, under a centred greeting: it is the caption of
                    // the picture above it rather than the first line of the
                    // form below it.
                    Text(
                      _register ? L.s.signUpBlurb : L.s.signInBlurb,
                      style: AppText.body,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 22),

                    // `onSurface`, like the tour's cards: the page under it is
                    // [AppColors.surface], and on dark a surface card on a
                    // surface page is invisible.
                    SectionCard(
                      onSurface: true,
                      children: dividedRows(inset: true, onSurface: true, [
                        if (_register)
                          _Field(
                            controller: _nameController,
                            label: L.s.yourName,
                            hint: L.s.name,
                            textCapitalization: TextCapitalization.words,
                            autofillHints: const [AutofillHints.name],
                            scrollPadding: bottomInset,
                          ),
                        _Field(
                          controller: _emailController,
                          label: L.s.emailAddress,
                          hint: L.s.emailPlaceholder,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          textInputAction: TextInputAction.go,
                          onSubmitted: (_) => _submit(),
                          scrollPadding: bottomInset,
                        ),
                      ]),
                    ),

                    if (auth.error != null) ...[const SizedBox(height: 16), ErrorNote(message: auth.error!)],

                    // The way to the *other* form stays in the scroll rather
                    // than joining the button in the bar: it is the alternative
                    // to it, and a band carrying two stacked actions stops
                    // reading as one primary action at all. It is not the same
                    // as the caret above — that goes back out to the front
                    // door, this swaps the question, and the greeting on the
                    // dots changes to say which one was picked.
                    const SizedBox(height: 24),
                    Center(
                      child: GestureDetector(
                        onTap: () {
                          ref.read(authProvider.notifier).clearError();
                          setState(() => _register = !_register);
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                          child: Text(
                            _register ? L.s.haveAccountAlready : L.s.newHereCreateAccount,
                            style: AppText.rowTitle.copyWith(color: Theme.of(context).colorScheme.primary),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One step giving way to the next — the tour's own, so the two flows move the
/// same way.
const _doorTransition = Duration(milliseconds: 260);

/// How many digits the mailed code has. GoTrue's email OTP is six, and every
/// box, formatter and "is it complete?" below counts against this rather than
/// a literal of its own.
const _codeLength = 6;

/// The celebration, start to finish: the boxes' own 520ms of merging, and then
/// [drawnCheckDuration] for the mark itself. Deliberately shorter than
/// [codeAcceptedHold], so the finished mark stands still for a beat before the
/// app takes the screen rather than landing as it goes.
const _codeSuccess = Duration(milliseconds: 1200);

/// Slices of that one clock, overlapping on purpose so it reads as a single
/// movement rather than a queue: the page gets out of the way, the six boxes
/// slide into one another, what is left rounds off into the mark's own circle,
/// and [DrawnCheck] draws itself over the last stretch while the box it grew
/// out of gets out from under it.
///
/// [_drawMark] is linear because the mark carries its own curves — it is the
/// same two strokes, in the same order, at the same speed as every other "that
/// worked" in the app, just started later on a longer clock.
const _fadeChrome = Interval(0, 0.22, curve: Curves.easeOut);
const _mergeBoxes = Interval(0.03, 0.33, curve: Curves.easeInOutCubic);
const _roundOff = Interval(0.27, 0.45, curve: Curves.easeOutCubic);
const _drawMark = Interval(0.43, 1);
const _dissolveBox = Interval(0.47, 0.64, curve: Curves.easeOut);

double _lerp(double a, double b, double t) => a + (b - a) * t;

/// Asks for the code that was just mailed. Supabase has no session to give
/// until it is typed in, which is neither signed in nor signed out.
///
/// The code is taken in six boxes rather than one field, and they are drawn
/// over a single invisible [TextField] holding all six digits at once — not six
/// fields passing focus between them. One field is what iOS's "from Mail"
/// autofill fills, what a paste lands in whole, and what a backspace walks back
/// through without any of the focus bookkeeping six of them would need; the
/// boxes above it are a picture of its text.
///
/// The sixth digit submits on its own: with the code complete there is nothing
/// left to decide, and asking for a tap afterwards is a step that only ever has
/// one answer. The button stays anyway — it is the way out of the one case the
/// auto-submit skips, six digits finished while a resend is still in flight.
class _CodeEntry extends ConsumerStatefulWidget {
  final String email;

  const _CodeEntry({required this.email});

  @override
  ConsumerState<_CodeEntry> createState() => _CodeEntryState();
}

class _CodeEntryState extends ConsumerState<_CodeEntry> with SingleTickerProviderStateMixin {
  /// GoTrue refuses a second code to the same address inside a minute, so the
  /// link waits it out rather than offering a tap that can only fail.
  static const _resendAfter = 60;

  final _codeController = TextEditingController();
  final _codeFocus = FocusNode();
  Timer? _timer;
  int _wait = _resendAfter;

  late final AnimationController _success = AnimationController(vsync: this, duration: _codeSuccess);

  /// The code already sent to be checked. Kept so the auto-submit fires once
  /// per code rather than again on every rebuild that still has six digits in
  /// it.
  String? _submitted;

  @override
  void initState() {
    super.initState();
    _codeController.addListener(_onCodeChanged);
    _startCountdown();
    // Only reachable if this screen were rebuilt from scratch mid-celebration;
    // cheap insurance against a check that never arrives.
    if (ref.read(authProvider).status == AuthStatus.codeAccepted) _success.value = 1;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _success.dispose();
    _codeFocus.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _wait = _resendAfter);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_wait <= 1) timer.cancel();
      setState(() => _wait--);
    });
  }

  Future<void> _resend() async {
    if (await ref.read(authProvider.notifier).resendCode() && mounted) {
      _codeController.clear();
      _submitted = null;
      _codeFocus.requestFocus();
      _startCountdown();
    }
  }

  /// The boxes are drawn from the controller's text, so every keystroke is a
  /// rebuild — and the sixth one is also the submit.
  void _onCodeChanged() {
    setState(() {});
    final code = _codeController.text;
    if (code.length == _codeLength && code != _submitted) _verify();
  }

  void _verify() {
    final code = _codeController.text;
    if (code.length < _codeLength || ref.read(authProvider).busy) return;
    _submitted = code;
    FocusScope.of(context).unfocus();
    ref.read(authProvider.notifier).verifyCode(code);
  }

  void _celebrate() {
    if (_success.status != AnimationStatus.dismissed) return;
    HapticFeedback.mediumImpact();
    _success.forward();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final accent = Theme.of(context).colorScheme.primary;

    ref.listen(authProvider.select((s) => s.error), (_, error) {
      if (error == null) return;
      // Six boxes holding the wrong six digits offer no obvious first move, so
      // a refusal empties them and puts the keyboard back where it was.
      HapticFeedback.mediumImpact();
      _codeController.clear();
      _submitted = null;
      _codeFocus.requestFocus();
    });
    ref.listen(authProvider.select((s) => s.status), (_, status) {
      if (status == AuthStatus.codeAccepted) _celebrate();
    });

    return AnimatedBuilder(
      animation: _success,
      builder: (context, _) {
        // Everything that is not the boxes leaves first: a "type the code we
        // sent you" standing beside a check is a stale sentence, and the check
        // is the whole message by then anyway.
        final chrome = 1 - _fadeChrome.transform(_success.value);
        final done = _success.value > 0;
        final complete = _codeController.text.length == _codeLength;

        return StepPage(
          // The caret *is* "Andere E-Mail-Adresse" — it was a third link under
          // the resend one until the chrome arrived, and two controls doing one
          // thing is how a screen grows a list of ways back. It goes during the
          // celebration rather than fading with everything else: it is a glass
          // platform view, and those can only be removed, not faded.
          onBack: done ? null : () => ref.read(authProvider.notifier).changeEmail(),
          backLabel: L.s.useOtherEmail,
          body: PinnedActionLayout(
            fadeInto: AppColors.surface,
            // Same reason, same answer: the pill is taken away rather than
            // faded out. The body is top-anchored, so the bar going leaves
            // nothing to move.
            action: done
                ? null
                : StepButton(label: L.s.verifyCode, onTap: _verify, enabled: !auth.busy && complete),
            bodyBuilder: (context, bottomInset) => SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.screenPad,
                stepTopInset(context) + 12,
                AppSpacing.screenPad,
                bottomInset,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Opacity(
                    opacity: chrome,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 12),
                        Center(
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(color: shade(accent, .14), shape: BoxShape.circle),
                            alignment: Alignment.center,
                            child: AppIcon(AppIcons.envelopeOpen, size: 28, color: accent),
                          ),
                        ),
                        const SizedBox(height: 22),
                        Text(L.s.almostThere, style: AppText.screenTitle, textAlign: TextAlign.center),
                        const SizedBox(height: 10),
                        Text(L.s.codeSentTo(widget.email), style: AppText.body, textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  IgnorePointer(
                    ignoring: done,
                    child: _CodeBoxes(
                      controller: _codeController,
                      focusNode: _codeFocus,
                      error: auth.error != null,
                      progress: _success.value,
                    ),
                  ),

                  IgnorePointer(
                    ignoring: done,
                    child: Opacity(
                      opacity: chrome,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (auth.error != null) ...[
                            const SizedBox(height: 16),
                            ErrorNote(message: auth.error!),
                          ],
                          const SizedBox(height: 24),
                          Center(
                            child: GestureDetector(
                              onTap: _wait > 0 || auth.busy ? null : _resend,
                              behavior: HitTestBehavior.opaque,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                                child: Text(
                                  _wait > 0 ? L.s.resendCodeIn(_wait) : L.s.resendCode,
                                  style: AppText.rowTitle.copyWith(
                                    color: _wait > 0 ? AppColors.inkTertiary : accent,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Six boxes over one invisible field — and, on [progress], the one shape they
/// become.
///
/// The celebration is geometry rather than a swap: every box keeps travelling
/// to the same rectangle, so once they are stacked they *are* one box, and the
/// rounding, the fill and the check that follow happen to all six at once with
/// nothing to cross-fade. They are opaque for exactly that reason — six
/// translucent fills sliding through each other would darken as they met.
class _CodeBoxes extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool error;

  /// 0 → 1 over the whole celebration; the intervals above carve it up.
  final double progress;

  const _CodeBoxes({
    required this.controller,
    required this.focusNode,
    required this.error,
    required this.progress,
  });

  @override
  State<_CodeBoxes> createState() => _CodeBoxesState();
}

class _CodeBoxesState extends State<_CodeBoxes> with SingleTickerProviderStateMixin {
  /// Only the caret rides this, inside a [FadeTransition], so a blink repaints
  /// two pixels rather than the row.
  late final AnimationController _caret = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    _caret.dispose();
    super.dispose();
  }

  void _onFocus() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final code = widget.controller.text;
    final merge = _mergeBoxes.transform(widget.progress);
    final disc = _roundOff.transform(widget.progress);
    // What is left of the box once the mark has taken over drawing the circle.
    final box = 1 - _dissolveBox.transform(widget.progress);
    final mark = _drawMark.transform(widget.progress);

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final width = constraints.maxWidth;
        final boxW = ((width - gap * (_codeLength - 1)) / _codeLength).clamp(38.0, 54.0);
        final boxH = boxW + 12;
        final rowW = boxW * _codeLength + gap * (_codeLength - 1);
        final rowLeft = (width - rowW) / 2;
        final height = boxH > drawnCheckSize ? boxH : drawnCheckSize;

        final w = _lerp(boxW, drawnCheckSize, disc);
        final h = _lerp(boxH, drawnCheckSize, disc);
        // The digits are gone well before the boxes arrive — they would
        // otherwise pile up on top of one another in the last few pixels.
        final digitInk = (1 - merge * 3).clamp(0.0, 1.0);

        return SizedBox(
          height: height,
          child: Stack(
            children: [
              for (var i = 0; i < _codeLength; i++)
                Positioned(
                  left: _lerp(rowLeft + i * (boxW + gap), (width - w) / 2, merge),
                  top: _lerp((height - boxH) / 2, (height - h) / 2, merge),
                  width: w,
                  height: h,
                  child: _box(i, code, accent, disc, box, digitInk, boxW),
                ),
              if (mark > 0)
                // The app's one confirmation mark, drawn at the size and in the
                // order it is drawn everywhere else — the boxes only carry the
                // eye to where it happens.
                Positioned(
                  left: 0,
                  right: 0,
                  top: (height - drawnCheckSize) / 2,
                  height: drawnCheckSize,
                  child: Center(
                    child: DrawnCheck(progress: mark, color: accent),
                  ),
                ),
              // Last, so it takes the taps: the row is one field, and anywhere
              // in it means "put the keyboard up".
              Positioned.fill(child: _hiddenField()),
            ],
          ),
        );
      },
    );
  }

  Widget _box(int i, String code, Color accent, double disc, double box, double digitInk, double boxW) {
    final digit = i < code.length ? code[i] : '';
    final full = code.length == _codeLength;
    final active = widget.focusNode.hasFocus && i == code.length && !full;
    // A finished code takes the accent across all six. It is the only sign the
    // round trip is happening — the pill below is disabled by then, and on iOS
    // it cannot spin (see [StepButton.enabled]) — and it is honest either way:
    // six boxes with six digits in them are no longer waiting for anything.
    final resting = widget.error
        ? AppColors.danger
        : active || full
        ? accent
        : AppColors.hairline;

    return Container(
      decoration: BoxDecoration(
        // Opaque, or the stack of six would darken as they overlapped — and
        // then gone entirely, because the mark paints its own wash and two of
        // them would make one too strong.
        //
        // Both of these take the alpha off their own colour rather than being
        // lerped toward [Colors.transparent]: that constant is transparent
        // *black*, and lerping to it drags a grey through the fade (the same
        // trap `CelebrationGlow`'s end stops are written around).
        color: AppColors.surface.withValues(alpha: box),
        borderRadius: BorderRadius.circular(_lerp(16, drawnCheckSize / 2, disc)),
        // The border is handed to the ring rather than fading first: by the
        // time it is gone the arc has swept most of the way round the same
        // circle, so it reads as the outline being re-drawn by a pen.
        border: Border.all(
          color: Color.lerp(resting, accent, disc)!.withValues(alpha: box),
          width: active ? 1.8 : (full ? 1.5 : 1.2),
        ),
      ),
      alignment: Alignment.center,
      child: digit.isEmpty
          ? (active && widget.progress == 0
                ? FadeTransition(
                    opacity: _caret,
                    child: Container(
                      width: 2,
                      height: boxW * 0.46,
                      decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(1)),
                    ),
                  )
                : const SizedBox.shrink())
          : Opacity(
              opacity: digitInk,
              child: Text(digit, style: AppText.statValue),
            ),
    );
  }

  /// The field itself, invisible under the boxes: the keyboard, the autofill
  /// and the paste menu all talk to this, and nothing about it is drawn.
  Widget _hiddenField() {
    return TextSelectionTheme(
      // A selection highlight over text nobody can see is a blue rectangle
      // with no explanation. Paste still works — that is why the field keeps
      // its interactive selection at all.
      data: const TextSelectionThemeData(
        selectionColor: Colors.transparent,
        selectionHandleColor: Colors.transparent,
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        autofocus: true,
        keyboardType: TextInputType.number,
        // iOS offers the code from Mail above the keyboard, and fills all six
        // at once — which is the other reason this is one field and not six.
        autofillHints: const [AutofillHints.oneTimeCode],
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(_codeLength),
        ],
        autocorrect: false,
        showCursor: false,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.transparent, fontSize: 24),
        cursorColor: Colors.transparent,
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          // Invisible, but it is what VoiceOver reads off the row.
          hintText: L.s.codeHint,
          hintStyle: const TextStyle(color: Colors.transparent),
        ),
      ),
    );
  }
}

/// One field of the form, in the app's own shape: a [FieldGroup]'s label over a
/// [FieldBox]'s outline, which is what a form is made of everywhere else in the
/// app. It is a private wrapper only because the two call sites below would
/// otherwise repeat the same six lines of `TextField` decoration.
class _Field extends StatelessWidget {
  final TextEditingController controller;

  /// The caption above the box — what the field is.
  final String label;

  /// What stands in the box while it is empty. An example rather than a repeat
  /// of [label]: the label is already there, so a hint saying the same word
  /// twice is the one thing a labelled field must not do.
  final String hint;

  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;

  /// The room the field asks to be given when focus scrolls it into view. The
  /// default 20 knows nothing about a bar pinned over the bottom of the
  /// viewport, so the pill lands on the field; this is that bar's measured
  /// height plus a line, exactly as the tour's own name field does it.
  final double scrollPadding;

  /// What the keyboard's own return key says and does. The default walks to
  /// the next field; the last field of a form passes the action that submits
  /// it, so the return key and the button below agree.
  final TextInputAction textInputAction;

  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
    this.onSubmitted,
    this.scrollPadding = 0,
    this.textInputAction = TextInputAction.next,
  });

  @override
  Widget build(BuildContext context) {
    return FieldGroup(
      label: label,
      child: FieldBox(
        child: TextField(
          controller: controller,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          autofillHints: autofillHints,
          autocorrect: false,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          scrollPadding: EdgeInsets.only(bottom: scrollPadding + 16),
          style: AppText.searchInput,
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: hint,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }
}
