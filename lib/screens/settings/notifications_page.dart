import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../models/entitlements.dart';
import '../../services/local_notifications.dart';
import '../../services/spend_intent.dart';
import '../../state/entitlement_state.dart';
import '../../state/family_state.dart';
import '../../state/notification_state.dart';
import '../../theme/app_icons.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/native_switch.dart';
import '../../widgets/settings_chrome.dart';

/// Settings → Mitteilungen: the kinds of notice a household switches on as a
/// whole, and the OS grant under all of them.
///
/// **Appointment reminders are not here**, and the note at the bottom says so:
/// a reminder belongs to one appointment and is set on it. What is here is what
/// has no single appointment to hang off — the brief, the bins, to-dos with an
/// hour, Ausgaben's budgets. See docs/notifications.md for why the list is this
/// short.
///
/// The budgets card is the only one that is not always here; see `showBudgets`.
class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.read(notificationSettingsProvider.notifier).refreshAccess();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Coming back from the system settings page is the ordinary way the grant
  /// changes, and the row at the top has to agree with it straight away.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(notificationSettingsProvider.notifier).refreshAccess();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(notificationSettingsProvider);
    final notifier = ref.read(notificationSettingsProvider.notifier);

    // **Three questions, and the card is absent unless all three say yes.** The
    // platform (Ausgaben does not ship everywhere), the plan (it is a Plus
    // feature), and the role — `spends` is admin-only in RLS, so a member has
    // no budget to be told about and would be offered a switch that could never
    // fire. Absent rather than disabled: a row that cannot do anything is a
    // question the user has to answer for themselves — and absent here costs
    // nothing, because the row it sits under is a card on its own without it.
    final showBudgets =
        spendAvailable &&
        ref.watch(entitlementProvider).allows(Feature.spend) &&
        ref.watch(isAdminProvider);

    return SettingsDetailPage(
      icon: AppIcons.bell,
      title: L.s.notificationsTitle,
      description: L.s.notificationsPageDesc,
      estimatedHeroHeight: 190,
      children: [
        if (s.loaded && s.access != NotificationAccess.authorized) ...[
          SectionCard(radius: AppRadii.card, children: [_accessRow(s.access, notifier)]),
          const SizedBox(height: AppSpacing.blockGap),
        ],
        // One card per kind: the switch and the hour it fires at are the same
        // thing, so they share a card and the gap between cards says where one
        // ends. In one flat card a bare "Uhrzeit" row sat between two switches
        // and belonged to neither.
        _group([
          SettingsRow(
            key: const ValueKey('brief'),
            icon: AppIcons.sun,
            title: L.s.notifyBriefTitle,
            subtitle: L.s.notifyBriefSubtitle,
            trailing: NativeSwitch(value: s.brief, onChanged: notifier.setBrief),
          ),
          if (s.brief)
            SettingsRow(
              key: const ValueKey('brief-time'),
              icon: AppIcons.clock,
              title: L.s.notifyTime,
              value: _clock(s.briefMinutes),
              onTap: () => _pickTime(s.briefMinutes, notifier.setBriefMinutes),
            ),
        ]),
        const SizedBox(height: AppSpacing.blockGap),
        _group([
          SettingsRow(
            key: const ValueKey('abfall'),
            icon: AppIcons.trash,
            title: L.s.notifyAbfallTitle,
            subtitle: L.s.notifyAbfallSubtitle,
            trailing: NativeSwitch(value: s.abfall, onChanged: notifier.setAbfall),
          ),
          if (s.abfall)
            SettingsRow(
              key: const ValueKey('abfall-time'),
              icon: AppIcons.clock,
              title: L.s.notifyTime,
              value: _clock(s.abfallMinutes),
              onTap: () => _pickTime(s.abfallMinutes, notifier.setAbfallMinutes),
            ),
        ]),
        const SizedBox(height: AppSpacing.blockGap),
        // **The two that name no hour, in one card.** A card here exists to bind
        // a switch to the time it fires at; these two have none to bind — a
        // to-do brings its own, and a budget goes out when it is crossed — so a
        // card each would have been two cards saying nothing by being apart.
        _group([
          SettingsRow(
            key: const ValueKey('tasks'),
            icon: AppIcons.checkCircle,
            title: L.s.notifyTaskTimesTitle,
            subtitle: L.s.notifyTaskTimesSubtitle,
            trailing: NativeSwitch(value: s.taskTimes, onChanged: notifier.setTaskTimes),
          ),
          if (showBudgets)
            SettingsRow(
              key: const ValueKey('budgets'),
              icon: AppIcons.chartPieSlice,
              title: L.s.notifyBudgetsTitle,
              subtitle: L.s.notifyBudgetsSubtitle,
              trailing: NativeSwitch(value: s.budgets, onChanged: notifier.setBudgets),
            ),
        ]),
        SettingsNote(L.s.notificationsEventNote),
      ],
    );
  }

  /// A switch and, while it is on, the hour it fires at — one card, so the
  /// time row can only read as belonging to the switch above it. Switches with
  /// no hour of their own share the last card instead.
  Widget _group(List<Widget> rows) => SectionCard(
    radius: AppRadii.card,
    children: rows.length == 1 ? rows : dividedRows(inset: true, rows),
  );

  /// The OS grant, in the one shape that lets the user act on it: ask while it
  /// can still be asked, send them to system settings once only that can help,
  /// and offer to promote iOS's quiet grant.
  Widget _accessRow(NotificationAccess access, NotificationSettingsNotifier notifier) {
    return switch (access) {
      NotificationAccess.denied => SettingsRow(
        icon: AppIcons.bell,
        title: L.s.notificationsAllowTitle,
        subtitle: L.s.notificationsDeniedBody,
        value: L.s.notificationsOpenSettings,
        onTap: notifier.openSystemSettings,
      ),
      NotificationAccess.provisional => SettingsRow(
        icon: AppIcons.bell,
        title: L.s.notificationsQuietTitle,
        subtitle: L.s.notificationsQuietBody,
        value: L.s.notificationsAllow,
        onTap: notifier.ensureAccess,
      ),
      _ => SettingsRow(
        icon: AppIcons.bell,
        title: L.s.notificationsAllowTitle,
        subtitle: L.s.notificationsAllowBody,
        value: L.s.notificationsAllow,
        onTap: notifier.ensureAccess,
      ),
    };
  }

  String _clock(int minutes) => formatTimeOfDay(minutes ~/ 60, minutes % 60);

  Future<void> _pickTime(int minutes, void Function(int) apply) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
    );
    if (picked != null) apply(picked.hour * 60 + picked.minute);
  }
}
