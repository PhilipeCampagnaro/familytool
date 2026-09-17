import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../services/local_notifications.dart';
import '../../state/notification_state.dart';
import '../../theme/app_icons.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/native_switch.dart';
import '../../widgets/settings_chrome.dart';

/// Settings → Mitteilungen: the three kinds of notice a household switches on
/// as a whole, and the OS grant under all of them.
///
/// **Appointment reminders are not here**, and the note at the bottom says so:
/// a reminder belongs to one appointment and is set on it. What is here is what
/// has no single appointment to hang off — the brief, the bins, to-dos with an
/// hour. See docs/notifications.md for why the list is this short.
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
        SectionCard(
          radius: AppRadii.card,
          children: dividedRows(inset: true, [
            // Keyed: the time rows come and go between the switches, and a
            // native switch matched to the wrong row by position would show
            // the other category's state.
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
            SettingsRow(
              key: const ValueKey('tasks'),
              icon: AppIcons.checkCircle,
              title: L.s.notifyTaskTimesTitle,
              subtitle: L.s.notifyTaskTimesSubtitle,
              trailing: NativeSwitch(value: s.taskTimes, onChanged: notifier.setTaskTimes),
            ),
          ]),
        ),
        SettingsNote(L.s.notificationsEventNote),
      ],
    );
  }

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
