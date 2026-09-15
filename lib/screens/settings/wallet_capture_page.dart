import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/spend_repository.dart';
import '../../l10n/l10n.dart';
import '../../services/external_links.dart';
import '../../services/spend_intent.dart';
import '../../state/spend_state.dart';
import '../../theme/app_icons.dart';
import '../../theme/tokens.dart';
import '../../widgets/anchored_menu.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/rename_sheet.dart';
import '../../widgets/settings_chrome.dart';
import '../../widgets/toast_chip.dart';

/// **Everything about automatic spend capture, in one place.** Switching this
/// phone on, the steps that finish the job outside Aporah, the phones the
/// household has already enrolled, and taking one back.
///
/// It used to be split: the activation card sat on the Ausgaben page because
/// that is where somebody is standing when they wish their payments arrived on
/// their own, and only the revoke list lived here. That split cost more than it
/// bought — the page in Settings had a button-shaped hole in it and a sentence
/// pointing at another screen, while a page about last month's groceries
/// carried a setup card with numbered steps under every full month of spending.
/// Setup is setup. Ausgaben keeps one row that leads here.
///
/// **One page, two mechanisms, and the copy is honest about which one you are
/// looking at.** [SpendCaptureRoute] decides, and it decides more than wording:
///
/// - **iOS.** Activating mints this device a token and puts it in the Keychain,
///   which is everything the app can do on its own. The automation itself is the
///   user's to create: **no app can install a Personal Automation** — there is
///   no API and there never has been. What the rebuild bought is that the action
///   is *already in the list* the moment Aporah is installed, so nothing is
///   downloaded, nothing is pasted, and no token is ever handled by a person.
/// - **Android.** There is no payment trigger to hand an action to, so capture
///   reads the notification the wallet posts instead. That needs a second
///   switch, in system Settings, that Aporah can open but cannot set — and it
///   needs saying, before the grant and on this page, that notification access
///   is all-or-nothing. The disclosure card is not decoration; it is what Google
///   Play requires and what anybody being asked for that switch is owed.
///
/// A revoked phone stops being able to post immediately: `spend-enroll` stores
/// only the SHA-256 of each token, and deleting the row is what makes the one on
/// the phone unrecognisable. Nothing it already filed is touched — money that was
/// spent stays spent.
class WalletCapturePage extends ConsumerStatefulWidget {
  /// The page this was pushed from, for the nav bar at rest. Null is the
  /// Settings root; Ausgaben passes its own title, since its row is the second
  /// way in.
  final String? parentTitle;

  const WalletCapturePage({super.key, this.parentTitle});

  @override
  ConsumerState<WalletCapturePage> createState() => _WalletCapturePageState();
}

class _WalletCapturePageState extends ConsumerState<WalletCapturePage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// **The one piece of state on this page the app cannot see change.**
  /// Notification access is granted and revoked on a system screen, so the only
  /// moment Aporah can find out is the moment it comes back. Without this the
  /// page would go on offering a grant the user has already given, or promising
  /// a capture they have since switched off.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(spendProvider.notifier).refreshNotificationAccess();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(spendProvider);
    final notifier = ref.read(spendProvider.notifier);
    final intents = ref.watch(spendIntentsProvider);
    // Off both phone platforms there is nothing here to switch on. The hero says
    // so and the page keeps only the device list, which is still worth reading —
    // the other parent's phone may well be in it.
    final supported = intents.isSupported;
    final needsAccess = intents.usesNotificationAccess;

    return SettingsDetailPage(
      icon: AppIcons.wallet,
      title: needsAccess ? L.s.settingsWalletCapture : L.s.settingsApplePay,
      description: !supported
          ? L.s.spendWalletUnsupported
          : needsAccess
          ? L.s.walletCapturePageDesc
          : L.s.applePayPageDesc,
      parentTitle: widget.parentTitle,
      estimatedHeroHeight: 210,
      // Pinned rather than the last thing in the list, the same trade the
      // provider pages make: it is the whole point of the page, and with one
      // phone enrolled it would otherwise sit halfway up the screen with nothing
      // under it.
      bottomAction: !supported
          ? null
          : _action(context, state, notifier, needsAccess: needsAccess),
      children: [
        if (supported) ...[
          _ThisDeviceCard(
            enrolled: state.thisDeviceEnrolled,
            access: state.notificationAccess,
            needsAccess: needsAccess,
          ),
          const SizedBox(height: AppSpacing.blockGap),
          if (needsAccess) ...[
            _DisclosureCard(),
            const SizedBox(height: AppSpacing.blockGap),
          ],
        ],
        GroupLabel(L.s.spendWalletDevicesLabel),
        SectionCard(
          radius: AppRadii.card,
          children: dividedRows(
            inset: true,
            state.devices.isEmpty
                // Not an error and not an empty box: the household has simply not
                // switched a phone on yet, and the sentence says where the switch
                // is rather than leaving a blank card to be puzzled at.
                ? [
                    SettingsRow(
                      icon: AppIcons.deviceMobile,
                      title: L.s.spendWalletNoDevices,
                      subtitle: !supported
                          ? null
                          : needsAccess
                          ? L.s.spendWalletAndroidNoDevicesHint
                          : L.s.spendWalletNoDevicesHint,
                    ),
                  ]
                : [
                    for (final device in state.devices)
                      _DeviceRow(
                        device: device,
                        isThisDevice:
                            state.thisDeviceEnrolled &&
                            device.deviceUid == state.thisDeviceUid,
                      ),
                  ],
          ),
        ),
      ],
    );
  }

  /// What is left to do, as one button.
  ///
  /// **Order matters and is not cosmetic.** Enrolment comes first on Android
  /// because it is ours to grant and instant; the system grant comes second
  /// because it costs the user a trip out of the app, and asking for it before
  /// the household has even decided to switch this phone on is asking for
  /// everybody's notifications on spec. When both are done there is no button:
  /// the page is finished, and a control that did nothing would only invite a
  /// tap looking for the rest of the setup.
  AccentAction? _action(
    BuildContext context,
    SpendState state,
    SpendNotifier notifier, {
    required bool needsAccess,
  }) {
    if (!state.thisDeviceEnrolled) {
      return AccentAction(
        // Named for what it does. It read "Fertig" once, which is what a form's
        // save says — so the one control on a setup page looked like the end of
        // the setup, and the steps it reveals looked like something that had gone
        // wrong afterwards.
        icon: state.enrolling ? AppIcons.spinnerGap : AppIcons.deviceMobile,
        label: needsAccess ? L.s.spendWalletAndroidEnable : L.s.spendWalletEnable,
        onTap: state.enrolling
            ? () {}
            : () async {
                final confirm = confirmChipOf(context);
                if (await notifier.enrolThisDevice()) confirm(L.s.spendWalletEnabled);
              },
      );
    }

    if (needsAccess) {
      if (state.notificationAccess) return null;
      return AccentAction(
        icon: AppIcons.bell,
        label: L.s.spendWalletGrantAccess,
        onTap: notifier.openNotificationAccess,
      );
    }

    // There is no deep link that creates an automation — `shortcuts://` has no
    // verb for it — so it opens the app and the user walks the four steps listed
    // above.
    return AccentAction(
      icon: AppIcons.arrowSquareOut,
      label: L.s.spendWalletOpenShortcuts,
      onTap: () => openExternalUrl('shortcuts://'),
    );
  }
}

/// This phone's own state, and what is left to do about it — the card the pinned
/// button at the bottom acts on.
///
/// Before activation it is the promise; after it, the steps the app cannot take
/// for the user. On Android those steps carry their own done marks, because
/// there are two of them and one lives outside the app: a reader who has granted
/// access and forgotten needs to see which half is missing, not a list that looks
/// the same before and after.
class _ThisDeviceCard extends StatelessWidget {
  final bool enrolled;
  final bool access;
  final bool needsAccess;

  const _ThisDeviceCard({
    required this.enrolled,
    required this.access,
    required this.needsAccess,
  });

  bool get _complete => needsAccess ? enrolled && access : enrolled;

  String get _title {
    if (!needsAccess) return enrolled ? L.s.spendWalletActive : L.s.spendWalletTitle;
    return _complete ? L.s.spendWalletAndroidActive : L.s.spendWalletAndroidTitle;
  }

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
                    _complete ? AppIcons.checkCircle : AppIcons.wallet,
                    size: 19,
                    color: _complete ? AppColors.success : AppColors.inkSecondary,
                  ),
                  const SizedBox(width: 9),
                  Expanded(child: Text(_title, style: AppText.sectionHeading)),
                ],
              ),
              const SizedBox(height: 12),
              if (needsAccess)
                ..._androidBody()
              else if (!enrolled)
                Text(
                  L.s.spendWalletIntro,
                  style: AppText.body.copyWith(color: AppColors.inkSecondary),
                )
              else
                ..._steps(L.s.spendWalletStepsTitle, [
                  (L.s.spendWalletStep1, null),
                  (L.s.spendWalletStep2, null),
                  (L.s.spendWalletStep3, null),
                  (L.s.spendWalletStep4, null),
                  (L.s.spendWalletStep5, null),
                ]),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _androidBody() {
    if (_complete) {
      return [
        Text(
          L.s.spendWalletAndroidSources,
          style: AppText.body.copyWith(color: AppColors.inkSecondary),
        ),
      ];
    }

    return [
      Text(
        L.s.spendWalletAndroidIntro,
        style: AppText.body.copyWith(color: AppColors.inkSecondary),
      ),
      // The one state worth calling out rather than listing: the token is here,
      // the grant is not, and every payment made in the meantime is gone for
      // good. Nothing else on this page is a warning.
      if (enrolled && !access) ...[
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppIcon(AppIcons.warning, size: 17, color: AppColors.danger),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                L.s.spendWalletAndroidDeaf,
                style: AppText.body.copyWith(color: AppColors.inkSecondary),
              ),
            ),
          ],
        ),
      ],
      const SizedBox(height: 14),
      ..._steps(L.s.spendWalletAndroidStepsTitle, [
        (L.s.spendWalletAndroidStep1, enrolled),
        (L.s.spendWalletAndroidStep2, access),
        (L.s.spendWalletAndroidStep3, null),
      ]),
    ];
  }

  /// A numbered list, where a step whose state we know shows that instead of its
  /// number. `null` means "there is nothing to check here" — the iOS steps
  /// happen inside Shortcuts, where the app cannot see whether they were taken.
  List<Widget> _steps(String title, List<(String, bool?)> steps) {
    return [
      Text(title, style: AppText.microLabel),
      const SizedBox(height: 8),
      for (final (index, step) in steps.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 20,
                child: step.$2 == true
                    ? AppIcon(AppIcons.checkCircle, size: 15, color: AppColors.success)
                    : Text(
                        '${index + 1}.',
                        style: AppText.body.copyWith(color: AppColors.inkTertiary),
                      ),
              ),
              Expanded(
                child: Text(
                  step.$1,
                  style: AppText.body.copyWith(color: AppColors.inkSecondary),
                ),
              ),
            ],
          ),
        ),
    ];
  }
}

/// **The prominent disclosure, and it sits above the grant on purpose.**
///
/// Google Play requires that a user being asked for notification access is told
/// in the app, before the ask, what is read and what is shared — not in a privacy
/// policy and not on a store listing. It is also simply the truth of the trade:
/// Android has no way to hand one app one other app's notifications, so this
/// switch gives Aporah the lot. The copy says that, says what is thrown away
/// unread, and names the four fields that leave the phone.
class _DisclosureCard extends StatelessWidget {
  const _DisclosureCard();

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      radius: AppRadii.card,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AppIcon(AppIcons.shieldCheck, size: 19, color: AppColors.inkSecondary),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      L.s.spendWalletDisclosureTitle,
                      style: AppText.sectionHeading,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                L.s.spendWalletDisclosureBody,
                style: AppText.body.copyWith(color: AppColors.inkSecondary),
              ),
              const SizedBox(height: 10),
              Text(
                L.s.spendWalletAndroidSources,
                style: AppText.body.copyWith(color: AppColors.inkTertiary),
              ),
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
          label: L.s.rename,
          icon: AppIcons.pencilSimple,
          symbol: 'pencil',
          onSelected: _rename,
        ),
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

  void _rename() {
    showRenameSheet(
      context: context,
      icon: AppIcons.deviceMobile,
      title: L.s.spendWalletRenameTitle,
      headline: widget.device.label,
      message: L.s.spendWalletRenameBody,
      initialName: widget.device.label,
      fieldHint: L.s.spendWalletDeviceNameHint,
      busyLabel: L.s.savingEllipsis,
      successLabel: L.s.nameChanged,
      onConfirm: (name) async {
        final ok = await ref.read(spendProvider.notifier).renameDevice(widget.device.id, name);
        // The sheet's contract: a throw keeps it open with the message under
        // the field.
        if (!ok) throw StateError('refused');
      },
    );
  }

  /// When the phone last filed a payment, which is the only thing on this page
  /// that says whether an enrolment is still doing anything. A phone that has
  /// never posted is the ordinary state right after activation *and* the state of
  /// a setup that was never finished — an automation left half-built in
  /// Shortcuts, or an Android grant never given — so it says so plainly rather
  /// than showing a dash.
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
      subtitle: widget.isThisDevice ? '${L.s.spendWalletThisDevice} · $_lastUsed' : _lastUsed,
      // Anchored on the dots rather than the row, so the menu grows out of the
      // thing that was tapped — which is the whole reason this app puts up a
      // `UIMenu` beside the control instead of a sheet at the bottom.
      trailing: KeyedSubtree(key: _anchorKey, child: RowMoreButton(onTap: _open)),
    );
  }
}
