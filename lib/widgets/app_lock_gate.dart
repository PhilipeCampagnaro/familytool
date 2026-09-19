import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../services/biometric_lock.dart';
import '../state/app_lock_state.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import 'glass.dart';
import 'glyph_tile.dart';

/// The app lock's cover, wrapped around the whole `Navigator` in
/// `AporahApp`'s builder — above every route and sheet, so the Settings page or
/// an open event can't show through.
///
/// **The app underneath stays mounted.** It is put `Offstage` rather than
/// swapped out: the five tabs live in one `IndexedStack`, and unmounting them
/// to lock would throw away every scroll position, open list and half-typed
/// article each time the phone came out of a pocket. `Offstage` also takes the
/// UIKit platform views (the tab bar, the glass buttons) off screen with it —
/// painting a cover *over* them is the order the design-system notes warn can
/// be dropped on device.
class AppLockGate extends ConsumerWidget {
  final Widget child;

  const AppLockGate({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(appLockProvider);
    final covered = !lock.loaded || lock.locked;
    return Stack(
      fit: StackFit.expand,
      children: [
        TickerMode(
          enabled: !covered,
          child: Offstage(offstage: covered, child: child),
        ),
        // Before the preference is read there is nothing to say yet — a plain
        // surface, the same one `_RootGate` shows while the session restores.
        if (!lock.loaded) ColoredBox(color: AppColors.surface),
        if (lock.loaded && lock.locked) _LockScreen(lock: lock),
      ],
    );
  }
}

class _LockScreen extends ConsumerWidget {
  final AppLockState lock;

  const _LockScreen({required this.lock});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: AppColors.surface,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GlyphTile(icon: AppIcons.lock, size: 72),
                const SizedBox(height: 20),
                Text(L.s.appLockLockedTitle, textAlign: TextAlign.center, style: AppText.sheetTitle),
                const SizedBox(height: 28),
                GlassAccentButton(
                  label: L.s.unlockWith(biometricMethodName(lock.kind)),
                  icon: biometricGlyph(lock.kind),
                  // Greyed while the system prompt is up, rather than gone: the
                  // prompt can be cancelled, and this is where the user lands.
                  enabled: !lock.busy,
                  onTap: () => ref.read(appLockProvider.notifier).unlock(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What the lock is called on this phone — the words after "Mit … entsperren".
/// Apple's three names read the same in every language, and still come through
/// `L.s` like every other word on screen.
String biometricMethodName(BiometricKind kind) => switch (kind) {
  BiometricKind.faceId => L.s.biometricFaceId,
  BiometricKind.touchId => L.s.biometricTouchId,
  BiometricKind.opticId => L.s.biometricOpticId,
  BiometricKind.fingerprint => L.s.biometricFingerprint,
  BiometricKind.face => L.s.biometricFace,
  BiometricKind.biometrics => L.s.biometricGeneric,
  BiometricKind.passcode || BiometricKind.none => L.s.biometricPasscode,
};

IconData biometricGlyph(BiometricKind kind) => switch (kind) {
  BiometricKind.faceId || BiometricKind.opticId || BiometricKind.face => AppIcons.scanSmiley,
  BiometricKind.touchId || BiometricKind.fingerprint => AppIcons.fingerprint,
  _ => AppIcons.lock,
};
