import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import '../widgets/app_sheet.dart';
import '../widgets/confirmation.dart';
import '../widgets/rename_sheet.dart';
import '../widgets/settings_chrome.dart';
import '../widgets/toast_chip.dart';

/// **Scaffolding, not a feature.** Every surface in the app that says "that
/// worked", on one page, so they can be looked at one after another and made
/// to agree — which is hard to do when the only way to see the create beat is
/// to create something and the only way to see the invite celebration is to
/// invite somebody.
///
/// It sits on Home because Home has no design yet ([StartScreen]); when it gets
/// one, this file and its `confirmLab*` strings go, and nothing else references
/// them.
///
/// The list below is deliberately the *complete* inventory. There is exactly
/// one confirmation widget ([ConfirmationView]) and one chip
/// (`toast_chip.dart`); what differs between rows is the shape each is asked
/// for, so a row that looks wrong is a settings problem rather than a widget
/// somebody has to go find.
class ConfirmationLab extends StatelessWidget {
  const ConfirmationLab({super.key});

  /// The everyday one, end to end and exactly as it ships: the create/rename
  /// sheet with its field, the header check turning into a spinner, and the
  /// beat that replaces the body while the grab handle drains. The `onConfirm`
  /// is a delay instead of a write, which is the only difference.
  void _flow(BuildContext context) {
    showRenameSheet(
      context: context,
      icon: AppIcons.shoppingCart,
      title: L.s.newList,
      headline: L.s.newList,
      message: L.s.confirmLabFlowHint,
      initialName: L.s.confirmLabSampleName,
      fieldHint: L.s.confirmLabNameHint,
      busyLabel: L.s.savingEllipsis,
      successLabel: L.s.listCreated,
      onConfirm: (name) => Future<void>.delayed(const Duration(milliseconds: 650)),
    );
  }

  /// The same beat with nothing in front of it — for judging the mark, the
  /// drawing and [confirmationBeat] on their own.
  void _beat(BuildContext context) {
    showConfirmationSheet(
      context: context,
      title: L.s.newList,
      headline: L.s.listCreated,
      message: L.s.confirmLabSampleName,
      dismissAfter: confirmationBeat,
    );
  }

  /// The rarer one: 🎉 and confetti instead of the disc, with the card of what
  /// just happened under it. This is the invite-sent shape (`family_page.dart`).
  void _celebration(BuildContext context) {
    showConfirmationSheet(
      context: context,
      title: L.s.newList,
      headline: L.s.listCreated,
      message: L.s.confirmLabSampleName,
      mark: ConfirmationMark.celebration,
      dismissAfter: const Duration(milliseconds: 3200),
      content: [
        SectionCard(
          children: dividedRows([
            SettingsRow(
              icon: AppIcons.shoppingCart,
              title: L.s.confirmLabSampleName,
              subtitle: L.s.newList,
            ),
          ]),
        ),
      ],
    );
  }

  /// The screen shape: no timer, and the way out is the bordered action at its
  /// foot. Nothing in the app asks for this yet — it is here because the widget
  /// offers it and the choice between "leaves by itself" and "waits" is the
  /// first thing to settle.
  void _waiting(BuildContext context) {
    showConfirmationSheet(
      context: context,
      title: L.s.newList,
      headline: L.s.listCreated,
      message: L.s.confirmLabSampleName,
    );
  }

  void _fullPage(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _ConfirmationPage()));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 20),
          child: Text(L.s.confirmLabBody, style: AppText.body.copyWith(color: AppColors.muted)),
        ),
        GroupLabel(L.s.confirmLabSheetsGroup),
        SectionCard(
          children: dividedRows([
            SettingsRow(
              icon: AppIcons.plus,
              title: L.s.confirmLabFlow,
              subtitle: L.s.confirmLabFlowHint,
              onTap: () => _flow(context),
            ),
            SettingsRow(
              icon: AppIcons.check,
              title: L.s.confirmLabBeat,
              subtitle: L.s.confirmLabBeatHint,
              onTap: () => _beat(context),
            ),
            SettingsRow(
              icon: AppIcons.sparkle,
              title: L.s.confirmLabCelebration,
              subtitle: L.s.confirmLabCelebrationHint,
              onTap: () => _celebration(context),
            ),
            SettingsRow(
              icon: AppIcons.clock,
              title: L.s.confirmLabWaiting,
              subtitle: L.s.confirmLabWaitingHint,
              onTap: () => _waiting(context),
            ),
            SettingsRow(
              icon: AppIcons.house,
              title: L.s.confirmLabFullPage,
              subtitle: L.s.confirmLabFullPageHint,
              onTap: () => _fullPage(context),
            ),
          ]),
        ),
        const SizedBox(height: 24),
        GroupLabel(L.s.confirmLabChipsGroup),
        SectionCard(
          children: dividedRows([
            SettingsRow(
              icon: AppIcons.check,
              title: L.s.confirmLabChipConfirm,
              subtitle: L.s.confirmLabChipConfirmHint,
              onTap: () => showToast(context, L.s.listCreated),
            ),
            SettingsRow(
              icon: AppIcons.trash,
              title: L.s.confirmLabChipUndo,
              subtitle: L.s.confirmLabChipUndoHint,
              // The restore always "succeeds", so the chip goes on to show
              // "Wiederhergestellt" — which is the second half of the shape and
              // the part nobody remembers is there.
              onTap: () => confirmChipOf(context)(L.s.listDeleted, undo: () async => true),
            ),
            SettingsRow(
              icon: AppIcons.x,
              title: L.s.confirmLabChipError,
              subtitle: L.s.confirmLabChipErrorHint,
              onTap: () => showToast(context, L.s.somethingWentWrong, kind: ToastKind.error),
            ),
            SettingsRow(
              icon: AppIcons.clock,
              title: L.s.confirmLabChipPending,
              subtitle: L.s.confirmLabChipPendingHint,
              // The one chip state that is otherwise only visible during a real
              // write to Google — two seconds of spinner, a line that changes
              // under it, then the tick. Faked here because the alternative is
              // reviewing it by creating appointments in somebody's calendar.
              onTap: () async {
                final chip = showPendingChip(context, L.s.eventBeingCreatedIn('Familie'));
                await Future<void>.delayed(const Duration(milliseconds: 1200));
                chip.step(L.s.calendarsUpdating);
                await Future<void>.delayed(const Duration(milliseconds: 1200));
                chip.done(L.s.eventCreated);
              },
            ),
          ]),
        ),
      ],
    );
  }
}

/// The onboarding shape, without the tour: a whole page, the glow spilling in
/// from above the status bar, and the accent pill at the foot. Kept faithful to
/// `_DoneStep` — the confetti has to fall over the page rather than over the
/// content's own box, so the confirmation is given the viewport's height.
class _ConfirmationPage extends StatelessWidget {
  // Not const-constructed: it paints from the live palette, so a canonicalised
  // instance would come back in the old one after a theme switch.
  // ignore: prefer_const_constructors_in_immutables
  _ConfirmationPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(
        children: [
          // Anchored to the very top of the display, status bar included — see
          // [CelebrationGlow] on why it can't start under the safe area.
          Positioned(top: 0, left: 0, right: 0, child: CelebrationGlow()),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.screenPad, 20, AppSpacing.screenPad, 28),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
                  child: ConfirmationView(
                    mark: ConfirmationMark.celebration,
                    headline: L.s.listCreated,
                    message: L.s.confirmLabSampleName,
                    action: ConfirmationAction.accentPill,
                    doneLabel: L.s.letsGo,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
