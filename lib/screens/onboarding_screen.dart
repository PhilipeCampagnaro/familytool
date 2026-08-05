import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../models/calendar_connection.dart';
import '../state/family_state.dart';
import '../state/onboarding_state.dart';
import '../theme/tokens.dart';
import '../widgets/app_sheet.dart';
import '../widgets/confirmation.dart';
import '../widgets/error_note.dart';
import '../widgets/glass.dart';
import '../widgets/native_switch.dart';
import '../widgets/settings_chrome.dart';
import '../widgets/step_dots.dart';
import '../widgets/toast_chip.dart';
import 'calendar_connect_screen.dart';
import '../l10n/l10n.dart';

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
          SafeArea(
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screenPad, 6, AppSpacing.screenPad, 2),
      child: SizedBox(
        height: 44,
        child: Stack(
          children: [
            Positioned.fill(child: Center(child: StepDots(count: _stepCount, index: step))),
            if (onBack case final back?)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Center(child: GlassIconButton(icon: LucideIcons.chevronLeft, onTap: back)),
              ),
            if (onSkip case final skip?)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: Center(child: GlassPillButton(label: L.s.skip, onTap: skip)),
              ),
          ],
        ),
      ),
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
        child: Text(
          label,
          style: AppText.buttonLarge.copyWith(color: AppColors.mutedLight),
        ),
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

class _WelcomeStep extends ConsumerWidget {
  final bool replay;

  const _WelcomeStep({required this.replay});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TopBar(step: 0, onSkip: () => _leaveTour(context, ref, replay)),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.screenPad, 12, AppSpacing.screenPad, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Hero('assets/onboarding/hero_welcome.png'),
                const SizedBox(height: 28),
                Text(L.s.onboardSetUpFamily, style: AppText.screenTitle),
                const SizedBox(height: 10),
                Text(
                  L.s.onboardSetUpFamilyBody,
                  style: AppText.body,
                ),
                const SizedBox(height: 28),
                _StepButton(label: L.s.letsGo, onTap: () => ref.read(onboardingProvider.notifier).next()),
              ],
            ),
          ),
        ),
      ],
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
  bool _isChild = false;

  /// One invitation is in flight. Holds the send button *and* "Weiter", so a
  /// second tap can't send the same address twice.
  bool _sending = false;

  /// Mirrors "the e-mail field is not empty", kept as state rather than read
  /// off the controller at build time so the button and the hint follow the
  /// typing. Only the e-mail counts: a name on its own can't be invited, so
  /// holding the step for one would be a trap with nothing behind it.
  bool _hasUnsentEmail = false;

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
    final outcome = await ref.read(familyProvider.notifier).inviteMember(
          email: email,
          name: name,
          role: _isChild ? FamilyRole.kid : FamilyRole.member,
        );
    if (!mounted) return false;
    setState(() => _sending = false);

    if (outcome.error case final message?) {
      // The Edge Function writes its refusals for the user, so its wording wins
      // over anything generic — see [HouseholdNotifier.inviteMember]. The
      // fields keep what was typed: the fix is usually one character.
      showToast(context, message, kind: ToastKind.error);
      return false;
    }

    ref.read(onboardingProvider.notifier).addInvite(OnboardingInvite(email: email, name: name, isChild: _isChild));
    // Same distinction the Settings confirmation draws: an invitation whose
    // mail didn't go out is still an invitation, and it says so rather than
    // claiming a delivery that didn't happen.
    final sent = outcome.invite!.mailSent;
    showToast(context, sent ? L.s.invitedPerson(name.isNotEmpty ? name : email) : L.s.inviteCreatedTitle);
    setState(() {
      _emailController.clear();
      _nameController.clear();
      _isChild = false;
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TopBar(
          step: 1,
          onBack: () => ref.read(onboardingProvider.notifier).back(),
          onSkip: () => ref.read(onboardingProvider.notifier).next(),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.screenPad, 4, AppSpacing.screenPad, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Hero('assets/onboarding/hero_members.png'),
                const SizedBox(height: 24),
                Text(L.s.onboardInviteTitle, style: AppText.screenTitle),
                const SizedBox(height: 8),
                Text(L.s.onboardInviteBody, style: AppText.body),
                const SizedBox(height: 16),
                // The role is a property of the invitation being typed, so it
                // reads before the fields rather than under them — and moving
                // it out of the card lets the card's last row carry the send
                // button, which is what the separate "Hinzufügen" button used
                // to be. Two rows of the step's height come back that way.
                Row(
                  children: [
                    Expanded(child: _RoleChip(label: L.s.adult, selected: !_isChild, accent: accent, onTap: () => setState(() => _isChild = false))),
                    const SizedBox(width: 8),
                    Expanded(child: _RoleChip(label: L.s.child, selected: _isChild, accent: accent, onTap: () => setState(() => _isChild = true))),
                  ],
                ),
                const SizedBox(height: 12),
                // Same two fields as the Settings invite sheet, so they are
                // typed the same way: [AppText.searchInput] in a 56pt row.
                // [AppText.inputTitle] belongs to the *headline* field of a
                // create sheet — a task's text, an event's title — not to an
                // ordinary form field like these.
                SectionCard(
                  children: [
                    _InviteFieldRow(
                      child: TextField(
                        controller: _nameController,
                        textInputAction: TextInputAction.next,
                        style: AppText.searchInput,
                        decoration: InputDecoration(border: InputBorder.none, hintText: L.s.nameOptional, isDense: true),
                      ),
                    ),
                    CardDivider(),
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
                              decoration: InputDecoration(border: InputBorder.none, hintText: L.s.emailAddress, isDense: true),
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
                              child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
                            )
                          else
                            GlassConfirmButton(icon: LucideIcons.send, size: 36, onTap: _sendInvite),
                        ],
                      ),
                    ),
                  ],
                ),
                // Points at the button that is being overlooked, in the accent
                // that button is drawn in, and only while there is something to
                // send. It says what to do rather than what went wrong: nothing
                // has gone wrong yet, which is the whole idea.
                if (_hasUnsentEmail) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(LucideIcons.arrowUp, size: 14, color: accent),
                      const SizedBox(width: 6),
                      Expanded(child: Text(L.s.tapSendToInvite, style: AppText.caption.copyWith(color: accent))),
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
                const SizedBox(height: 22),
                _StepButton(label: L.s.next, onTap: _goNext, enabled: !_hasUnsentEmail && !_sending),
              ],
            ),
          ),
        ),
      ],
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

class _RoleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _RoleChip({required this.label, required this.selected, required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? shade(accent, .12) : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadii.chip),
          border: Border.all(color: selected ? accent : Colors.transparent),
        ),
        child: Text(label, style: AppText.buttonSmall.copyWith(color: selected ? accent : AppColors.muted)),
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

  @override
  void initState() {
    super.initState();
    _addressController = TextEditingController(text: ref.read(onboardingProvider).address);
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  OnboardingNotifier get _onboarding => ref.read(onboardingProvider.notifier);

  void _pick(GeoAddress found) {
    // A bare postcode goes back into the field so the street can be typed after
    // it; anything else is the answer, and the lookup starts on the spot.
    final prefix = _onboarding.prefixQueryFor(found);
    if (prefix != null) {
      _addressController.text = prefix;
      _addressController.selection = TextSelection.collapsed(offset: prefix.length);
      return;
    }
    FocusScope.of(context).unfocus();
    _addressController.text = found.label;
    _onboarding.pickAddress(found);
  }

  /// The step's own way forward: file the address, create whatever is still
  /// ticked, then move on. A failed connect keeps the step — the error says
  /// what happened and the button retries — but "Überspringen" is still there,
  /// because nobody should be held in a wizard by a waste vendor being down.
  Future<void> _continue() async {
    final state = ref.read(onboardingProvider);
    if (state.connecting) return;
    if (await _onboarding.connectLocalCalendars()) _onboarding.next();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TopBar(
          step: 2,
          onBack: () => _onboarding.back(),
          onSkip: () => _onboarding.next(),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.screenPad, 4, AppSpacing.screenPad, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Hero('assets/onboarding/hero_address.png'),
                const SizedBox(height: 24),
                Text(L.s.onboardAddressTitle, style: AppText.screenTitle),
                const SizedBox(height: 8),
                Text(L.s.onboardAddressBody, style: AppText.body),
                const SizedBox(height: 20),
                SectionCard(radius: AppRadii.card, children: dividedRows(_addressRows(state), inset: true)),
                if (state.found case final found?) ...[
                  const SizedBox(height: 16),
                  _FoundCalendars(found: found, state: state),
                  const SizedBox(height: 10),
                  SettingsNote(found.any ? L.s.onboardRenameLater : L.s.onboardNothingForAddress),
                ],
                if (state.addressError case final message?) ...[
                  const SizedBox(height: 12),
                  ErrorNote(message: message),
                ],
                const SizedBox(height: 28),
                if (state.connecting)
                  _InlineBusy()
                else
                  _StepButton(label: L.s.next, onTap: _continue),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// One card for the whole lookup — the field, the suggestions, and the
  /// address we settled on — so the step never grows a second half.
  List<Widget> _addressRows(OnboardingState state) {
    final picked = state.pickedAddress;
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
            icon: found.prefix ? LucideIcons.mapPin : LucideIcons.house,
            title: found.label,
            onTap: () => _pick(found),
          ),
      ];
    }

    return [
      FieldGroup(label: L.s.yourAddress),
      SettingsRow(
        icon: LucideIcons.house,
        title: picked.label,
        trailing: GestureDetector(
          onTap: () {
            _addressController.clear();
            _onboarding.resetAddress();
          },
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Icon(LucideIcons.x, size: 17, color: AppColors.muted),
          ),
        ),
      ),
      if (state.lookingUp) _BusyRow(L.s.onboardFindingCalendars),
    ];
  }
}

/// What the address turned out to be worth. Both rows are always drawn, found
/// or not: a family that lives somewhere no vendor of ours serves is owed the
/// sentence saying so, and a missing row would just look like we never looked.
class _FoundCalendars extends ConsumerWidget {
  final LocalCalendars found;
  final OnboardingState state;

  const _FoundCalendars({required this.found, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(onboardingProvider.notifier);
    final coverage = found.abfall;
    final where = coverage == null
        ? null
        : coverage.street == null
        ? coverage.town
        : '${coverage.street}, ${coverage.town}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GroupLabel(L.s.onboardFoundForYou),
        SectionCard(
          radius: AppRadii.card,
          children: dividedRows([
            _CalendarRow(
              icon: LucideIcons.recycle,
              title: L.s.wasteCalendar,
              subtitle: found.hasAbfall ? where : L.s.onboardNotFoundHere,
              value: found.hasAbfall ? state.trashCalendar : null,
              onChanged: notifier.setTrashCalendar,
            ),
            _CalendarRow(
              icon: LucideIcons.graduationCap,
              title: L.s.holidayCalendar,
              subtitle: found.hasFerien ? bundeslaender[found.ferienState] : L.s.onboardNotFoundHere,
              value: found.hasFerien ? state.ferienCalendar : null,
              onChanged: notifier.setFerienCalendar,
            ),
          ]),
        ),
      ],
    );
  }
}

/// A calendar the lookup found, with its switch — or one it didn't, greyed and
/// carrying an X where the switch would be. A **disabled switch** is the thing
/// this deliberately isn't: it invites a tap that can't do anything, where the
/// X simply says there is nothing here to turn on.
class _CalendarRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  /// Null means the lookup found nothing for this one.
  final bool? value;
  final ValueChanged<bool> onChanged;

  const _CalendarRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
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
            decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(AppRadii.iconTile)),
            alignment: Alignment.center,
            child: Icon(icon, size: 17, color: missing ? AppColors.mutedLight : accent),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppText.rowTitle.copyWith(color: missing ? AppColors.muted : null),
                ),
                if (subtitle case final line?)
                  Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.label),
              ],
            ),
          ),
          if (value case final on?)
            NativeSwitch(value: on, onChanged: onChanged)
          else
            Icon(LucideIcons.x, size: 16, color: AppColors.mutedLight),
        ],
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
          Expanded(child: Text(label, style: AppText.body.copyWith(color: AppColors.muted))),
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

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.screenPad, 20, AppSpacing.screenPad, 24),
        child: ConstrainedBox(
          // Minus the padding this scroll view already adds, so a screen that
          // exactly fits doesn't gain a scrollbar's worth of overflow.
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 44),
          child: ConfirmationView(
            mark: ConfirmationMark.celebration,
            headline: L.s.onboardReady,
            message: L.s.onboardReadyBody,
            action: ConfirmationAction.accentPill,
            doneLabel: L.s.letsGo,
            onDone: () => _leaveTour(context, ref, replay),
            content: [
              SectionCard(
                children: [
                  _RecapRow(
                    icon: LucideIcons.userPlus,
                    label: state.invites.isEmpty ? L.s.noInvitesSent : L.s.invitedCount(state.invites.length),
                    done: state.invites.isNotEmpty,
                  ),
                  CardDivider(),
                  _RecapRow(icon: LucideIcons.recycle, label: L.s.wasteCalendar, done: state.trashCalendar),
                  CardDivider(),
                  _RecapRow(icon: LucideIcons.graduationCap, label: L.s.holidayCalendar, done: state.ferienCalendar),
                ],
              ),
              // The personal accounts, offered exactly once and never as a
              // step. Google and Outlook consent happens in Safari and comes
              // back through a deep link — the most fragile minute in the app,
              // and no place for it is worse than the middle of a wizard. So
              // the tour finishes first and this lands on the connect page with
              // onboarding already behind it.
              SectionCard(
                children: [
                  SettingsRow(
                    icon: LucideIcons.calendarPlus,
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
    );
  }
}

class _RecapRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool done;

  const _RecapRow({required this.icon, required this.label, required this.done});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.muted),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: AppText.rowTitle)),
          Icon(done ? LucideIcons.check : LucideIcons.x, size: 16, color: done ? AppColors.success : AppColors.mutedLight),
        ],
      ),
    );
  }
}
