import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/spend_repository.dart';
import '../../l10n/l10n.dart';
import '../../services/external_links.dart';
import '../../state/spend_state.dart';
import '../../theme/app_icons.dart';
import '../../theme/tokens.dart';
import '../../widgets/anchored_menu.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/settings_chrome.dart';
import '../../widgets/toast_chip.dart';

/// **Everything about Apple Pay capture, in one place.** Switching this phone
/// on, the four steps that finish the job in Shortcuts, the phones the
/// household has already enrolled, and taking one back.
///
/// It used to be split: the activation card sat on the Ausgaben page because
/// that is where somebody is standing when they wish their payments arrived on
/// their own, and only the revoke list lived here. That split cost more than it
/// bought — the page in Settings had a button-shaped hole in it and a sentence
/// pointing at another screen, while a page about last month's groceries
/// carried a setup card with four numbered steps under every full month of
/// spending. Setup is setup. Ausgaben keeps one row that leads here.
///
/// **What the app can and cannot do, stated plainly, because the copy has to be
/// honest about it.** Activating mints this device a token and puts it in the
/// Keychain, which is everything the app can do on its own. The automation
/// itself is the user's to create: **no app can install a Personal Automation**
/// — there is no API and there never has been. What the rebuild bought is that
/// the action is *already in the list* the moment Aporah is installed, so
/// nothing is downloaded, nothing is pasted, and no token is ever handled by a
/// person. The old web app needed a clipboard, an iCloud shortcut link and an
/// import prompt to reach the same place.
///
/// A revoked phone stops being able to post immediately: `spend-enroll` stores
/// only the SHA-256 of each token, and deleting the row is what makes the one
/// on the phone unrecognisable. Nothing it already filed is touched — money
/// that was spent stays spent.
class ApplePayPage extends ConsumerWidget {
  /// The page this was pushed from, for the nav bar at rest. Null is the
  /// Settings root; Ausgaben passes its own title, since its row is the second
  /// way in.
  final String? parentTitle;

  const ApplePayPage({super.key, this.parentTitle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(spendProvider);
    final notifier = ref.read(spendProvider.notifier);
    // Off iOS there is no Shortcuts app, no Transaction trigger and no App
    // Intent, so there is nothing here to switch on. The hero says so and the
    // page keeps only the device list, which is still worth reading — the
    // other parent's iPhone may well be in it.
    final supported = ref.watch(spendIntentsProvider).isSupported;

    return SettingsDetailPage(
      icon: AppIcons.wallet,
      title: L.s.settingsApplePay,
      description: supported ? L.s.applePayPageDesc : L.s.spendWalletUnsupported,
      parentTitle: parentTitle,
      estimatedHeroHeight: 210,
      // Pinned rather than the last thing in the list, the same trade the
      // provider pages make: it is the whole point of the page, and with one
      // phone enrolled it would otherwise sit halfway up the screen with
      // nothing under it.
      bottomAction: !supported
          ? null
          : state.thisDeviceEnrolled
          // There is no deep link that creates an automation — `shortcuts://`
          // has no verb for it — so it opens the app and the user walks the
          // four steps listed above.
          ? AccentAction(
              icon: AppIcons.arrowSquareOut,
              label: L.s.spendWalletOpenShortcuts,
              onTap: () => openExternalUrl('shortcuts://'),
            )
          : AccentAction(
              // Named for what it does. It read "Fertig" once, which is what a
              // form's save says — so the one control on a setup page looked
              // like the end of the setup, and the four steps it reveals looked
              // like something that had gone wrong afterwards.
              icon: state.enrolling ? AppIcons.spinnerGap : AppIcons.deviceMobile,
              label: L.s.spendWalletEnable,
              onTap: state.enrolling
                  ? () {}
                  : () async {
                      final confirm = confirmChipOf(context);
                      if (await notifier.enrolThisDevice()) confirm(L.s.spendWalletEnabled);
                    },
            ),
      children: [
        if (supported) ...[
          _ThisDeviceCard(enrolled: state.thisDeviceEnrolled),
          const SizedBox(height: AppSpacing.blockGap),
        ],
        GroupLabel(L.s.spendWalletDevicesLabel),
        SectionCard(
          radius: AppRadii.card,
          children: dividedRows(
            inset: true,
            state.devices.isEmpty
                // Not an error and not an empty box: the household has simply
                // not switched a phone on yet, and the sentence says where the
                // switch is rather than leaving a blank card to be puzzled at.
                ? [
                    SettingsRow(
                      icon: AppIcons.deviceMobile,
                      title: L.s.spendWalletNoDevices,
                      subtitle: supported ? L.s.spendWalletNoDevicesHint : null,
                    ),
                  ]
                : [
                    for (final device in state.devices)
                      _DeviceRow(
                        device: device,
                        isThisDevice: state.thisDeviceEnrolled && _isThisDevice(device, state),
                      ),
                  ],
          ),
        ),
      ],
    );
  }

  /// Best effort, and it only decides whether the local Keychain copy is also
  /// cleared. The server list cannot tell this iPhone from another one with the
  /// same name, so the answer is "this phone holds a token and exactly one row
  /// carries that name". Getting it wrong in one direction leaves a dead token
  /// on a phone whose row is gone — harmless, because the server refuses it —
  /// and in the other clears a token this phone was about to stop using anyway.
  static bool _isThisDevice(SpendDevice device, SpendState state) =>
      state.devices.where((d) => d.label == device.label).length == 1;
}

/// This phone's own state, and what is left to do about it — the card the
/// pinned button at the bottom acts on.
///
/// Before activation it is the promise; after it, the four steps in Shortcuts
/// that the app cannot take for the user.
class _ThisDeviceCard extends StatelessWidget {
  final bool enrolled;

  const _ThisDeviceCard({required this.enrolled});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      radius: AppRadii.card,
      children: [
        // Full width by hand: [SectionCard] is a bare `Column`, which centres
        // anything narrower than itself, and a step list that starts halfway
        // across the card is not a list.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AppIcon(
                    enrolled ? AppIcons.checkCircle : AppIcons.wallet,
                    size: 19,
                    color: enrolled ? AppColors.success : AppColors.inkSecondary,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      enrolled ? L.s.spendWalletActive : L.s.spendWalletTitle,
                      style: AppText.sectionHeading,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (!enrolled)
                Text(
                  L.s.spendWalletIntro,
                  style: AppText.body.copyWith(color: AppColors.inkSecondary),
                )
              else ...[
                Text(L.s.spendWalletStepsTitle, style: AppText.microLabel),
                const SizedBox(height: 8),
                for (final (index, step) in [
                  L.s.spendWalletStep1,
                  L.s.spendWalletStep2,
                  L.s.spendWalletStep3,
                  L.s.spendWalletStep4,
                ].indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 20,
                          child: Text(
                            '${index + 1}.',
                            style: AppText.body.copyWith(color: AppColors.inkTertiary),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            step,
                            style: AppText.body.copyWith(color: AppColors.inkSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DeviceRow extends ConsumerStatefulWidget {
  final SpendDevice device;
  final bool isThisDevice;

  const _DeviceRow({required this.device, required this.isThisDevice});

  @override
  ConsumerState<_DeviceRow> createState() => _DeviceRowState();
}

class _DeviceRowState extends ConsumerState<_DeviceRow> {
  final GlobalKey _anchorKey = GlobalKey();

  void _open() {
    showAnchoredMenu(
      context: context,
      anchorKey: _anchorKey,
      title: widget.device.label,
      items: [
        AnchoredMenuItem(
          label: L.s.spendWalletRevoke,
          icon: AppIcons.trash,
          symbol: 'trash',
          destructive: true,
          onSelected: () => ref
              .read(spendProvider.notifier)
              .revokeDevice(widget.device.id, isThisDevice: widget.isThisDevice),
        ),
      ],
    );
  }

  /// When the phone last filed a payment, which is the only thing on this page
  /// that says whether an enrolment is still doing anything. A phone that has
  /// never posted is the ordinary state right after activation *and* the state
  /// of an automation that was never finished in Shortcuts, so it says so
  /// plainly rather than showing a dash.
  String get _lastUsed {
    final at = widget.device.lastUsedAt?.toLocal();
    if (at == null) return L.s.spendWalletDeviceUnused;
    return L.s.spendWalletDeviceLastUsed(L.s.dayMonth(at.day, at.month));
  }

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      icon: AppIcons.deviceMobile,
      title: widget.device.label,
      subtitle: _lastUsed,
      // Anchored on the dots rather than the row, so the menu grows out of the
      // thing that was tapped — which is the whole reason this app puts up a
      // `UIMenu` beside the control instead of a sheet at the bottom.
      trailing: KeyedSubtree(key: _anchorKey, child: RowMoreButton(onTap: _open)),
    );
  }
}
