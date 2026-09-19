import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/l10n.dart';
import '../services/biometric_lock.dart';

/// The app lock: Face ID, Touch ID, Optic ID or a fingerprint in front of the
/// household's data on *this phone*.
///
/// **It is a lock on the app, not a way to sign in.** The Supabase session is
/// untouched and stays in its own storage; this only decides whether the shell
/// may be drawn. Signing in with a face would mean keeping the password in the
/// Keychain to replay it, which is a credential at rest for no gain — the
/// session is already there.
///
/// **A device preference, not a profile setting**, so it lives in
/// SharedPreferences rather than on `profiles`: the other parent's phone has
/// its own sensor and its own opinion, and a lock switched on here must not
/// lock an iPad the child uses.
class AppLockState {
  /// False until the stored preference has been read. The cover stays up
  /// until then, or a locked app would show one frame of the household on
  /// every cold start.
  final bool loaded;
  final bool enabled;
  final BiometricKind kind;

  /// The cover is up. Only ever true while [enabled].
  final bool locked;

  /// A system prompt is on screen. Guards against a second one, and against
  /// the passcode screen Android opens as its own activity reading as the app
  /// going to the background.
  final bool busy;

  const AppLockState({
    this.loaded = false,
    this.enabled = false,
    this.kind = BiometricKind.none,
    this.locked = false,
    this.busy = false,
  });

  /// Whether this phone can keep a lock at all — the Settings row's condition.
  bool get available => kind != BiometricKind.none;

  AppLockState copyWith({bool? loaded, bool? enabled, BiometricKind? kind, bool? locked, bool? busy}) =>
      AppLockState(
        loaded: loaded ?? this.loaded,
        enabled: enabled ?? this.enabled,
        kind: kind ?? this.kind,
        locked: locked ?? this.locked,
        busy: busy ?? this.busy,
      );
}

const _prefsKey = 'app_lock_enabled';

/// How long the app may sit in the background before it locks again. Not
/// zero: connecting Google or Outlook sends the user through Safari and back,
/// and a lock on the way back from a sign-in page reads as the app having
/// forgotten them. Thirty seconds covers that and a glance at a message; a
/// phone left on the table is locked by the time anyone picks it up.
const _grace = Duration(seconds: 30);

class AppLockNotifier extends StateNotifier<AppLockState> with WidgetsBindingObserver {
  AppLockNotifier() : super(const AppLockState()) {
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  DateTime? _backgroundedAt;

  /// Set when the cover goes up, cleared when the prompt it asked for is
  /// fired. One automatic prompt per lock: the prompt itself makes the app
  /// inactive and then resumed, so without this a cancel would open the next
  /// prompt straight away, forever.
  bool _promptPending = false;

  /// The lock only guards a signed-in app. Over the sign-in screen it would be
  /// a lock in front of a lock — and after signing in fresh, a second question
  /// the user just answered.
  static bool get _signedIn => Supabase.instance.client.auth.currentSession != null;

  Future<void> _load() async {
    var enabled = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled = prefs.getBool(_prefsKey) ?? false;
    } catch (_) {
      // No storage this session: no lock, which the user can see in Settings.
    }
    final kind = await BiometricLock.kind();
    if (!mounted) return;
    final lock = enabled && kind != BiometricKind.none && _signedIn;
    state = state.copyWith(loaded: true, enabled: enabled, kind: kind, locked: lock);
    if (lock) _promptWhenActive();
  }

  Future<void> _persist(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, enabled);
    } catch (_) {
      // Best-effort, like every other preference in the app.
    }
  }

  /// Asks now if the app is in front, otherwise on the next `resumed` — a
  /// prompt raised from a cold start before the scene is active fails at once
  /// on iOS and would leave the user looking at a button for no reason.
  void _promptWhenActive() {
    _promptPending = true;
    if (SchedulerBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _promptPending = false;
      unawaited(unlock());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `state` is the framework's name for the lifecycle here; the lock's own
    // state is `this.state`.
    switch (state) {
      case AppLifecycleState.paused:
        if (!this.state.busy) _backgroundedAt ??= DateTime.now();
      case AppLifecycleState.resumed:
        unawaited(_onResumed());
      default:
        break;
    }
  }

  Future<void> _onResumed() async {
    final away = _backgroundedAt;
    _backgroundedAt = null;
    // Re-read: a face can be enrolled, or the passcode removed, in the phone's
    // Settings while the app is suspended.
    final kind = await BiometricLock.kind();
    if (!mounted) return;
    state = state.copyWith(kind: kind);
    if (state.locked) {
      if (_promptPending) {
        _promptPending = false;
        unawaited(unlock());
      }
      return;
    }
    if (!state.enabled || kind == BiometricKind.none || !_signedIn) return;
    if (away == null || DateTime.now().difference(away) < _grace) return;
    state = state.copyWith(locked: true);
    _promptPending = false;
    unawaited(unlock());
  }

  /// The system prompt, then the cover comes down on success. On failure it
  /// stays up with its button, which calls this again.
  Future<void> unlock() async {
    if (state.busy || !state.locked) return;
    state = state.copyWith(busy: true);
    final outcome = await BiometricLock.authenticate(L.s.appLockUnlockReason);
    if (!mounted) return;
    state = state.copyWith(
      busy: false,
      // `unavailable` opens the door too: the phone has no screen lock any
      // more, so there is nothing left to check against, and a household shut
      // out of its own lists by a setting it can no longer reach is the worse
      // of the two failures. The switch stays on and takes effect again once a
      // passcode is back.
      locked: outcome == BiometricOutcome.failed,
    );
  }

  /// The Settings switch. Both directions ask first: turning it on proves the
  /// sensor answers before the app starts depending on it, and turning it off
  /// is exactly the change somebody holding an unlocked phone should not be
  /// able to make in passing. The switch moves at once and moves back on a
  /// cancel, which is what makes the UIKit switch follow.
  Future<void> setEnabled(bool value) async {
    if (state.busy || value == state.enabled) return;
    state = state.copyWith(enabled: value, busy: true);
    final outcome = await BiometricLock.authenticate(
      value ? L.s.appLockEnableReason : L.s.appLockDisableReason,
    );
    if (!mounted) return;
    final ok = outcome == BiometricOutcome.ok;
    state = state.copyWith(enabled: ok ? value : !value, busy: false);
    if (ok) await _persist(value);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

final appLockProvider = StateNotifierProvider<AppLockNotifier, AppLockState>((ref) => AppLockNotifier());
