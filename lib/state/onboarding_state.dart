import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'family_state.dart';

class OnboardingInvite {
  final String email;
  final String name;
  final bool isChild;

  const OnboardingInvite({required this.email, required this.name, required this.isChild});
}

class OnboardingState {
  /// null while the persisted flag is still loading from disk, so the app
  /// shell doesn't flash the wizard for a returning user before it's known.
  final bool? done;

  final int step;
  final List<OnboardingInvite> invites;
  final String address;
  final bool trashCalendar;
  final bool ferienCalendar;

  const OnboardingState({
    this.done,
    this.step = 0,
    this.invites = const [],
    this.address = '',
    this.trashCalendar = true,
    this.ferienCalendar = true,
  });

  OnboardingState copyWith({
    bool? done,
    int? step,
    List<OnboardingInvite>? invites,
    String? address,
    bool? trashCalendar,
    bool? ferienCalendar,
  }) {
    return OnboardingState(
      done: done ?? this.done,
      step: step ?? this.step,
      invites: invites ?? this.invites,
      address: address ?? this.address,
      trashCalendar: trashCalendar ?? this.trashCalendar,
      ferienCalendar: ferienCalendar ?? this.ferienCalendar,
    );
  }
}

const _prefsDoneKey = 'onboarding_done';

/// Drives the wizard's steps. Whether the wizard runs at all is decided by
/// `families.onboarding_done` in `_RootGate`, not here — the local flag below
/// is kept only as an offline fallback, because "the household is set up" must
/// not be re-asked on a second device.
class OnboardingNotifier extends StateNotifier<OnboardingState> {
  OnboardingNotifier(this._ref) : super(const OnboardingState()) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final done = prefs.getBool(_prefsDoneKey) ?? false;
      if (!mounted) return;
      state = state.copyWith(done: done);
    } catch (_) {
      // No local storage available this session — treat as not-yet-onboarded.
      if (mounted) state = state.copyWith(done: false);
    }
  }

  void next() {
    if (state.step < 3) state = state.copyWith(step: state.step + 1);
  }

  void back() {
    if (state.step > 0) state = state.copyWith(step: state.step - 1);
  }

  void skipToEnd() => state = state.copyWith(step: 3);

  void setAddress(String value) => state = state.copyWith(address: value);

  void setTrashCalendar(bool value) => state = state.copyWith(trashCalendar: value);

  void setFerienCalendar(bool value) => state = state.copyWith(ferienCalendar: value);

  void addInvite(OnboardingInvite invite) => state = state.copyWith(invites: [...state.invites, invite]);

  /// Restarts the wizard from step 0 without touching the persisted "seen"
  /// flag, for Settings' "Willkommenstour wiederholen" row.
  void resetForReplay() => state = state.copyWith(step: 0, invites: const [], address: '');

  Future<void> complete() async {
    state = state.copyWith(done: true);
    // The one that actually closes the gate, for every device this household
    // signs in on.
    await _ref.read(familyProvider.notifier).markOnboardingDone();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsDoneKey, true);
    } catch (_) {
      // Best-effort — worst case the wizard reappears next launch.
    }
  }
}

final onboardingProvider = StateNotifierProvider<OnboardingNotifier, OnboardingState>(
  (ref) => OnboardingNotifier(ref),
);
