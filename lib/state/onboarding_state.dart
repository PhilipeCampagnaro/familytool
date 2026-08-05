import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';
import '../models/calendar_connection.dart';
import 'calendar_connections_state.dart';
import 'family_state.dart';

class OnboardingInvite {
  final String email;
  final String name;
  final bool isChild;

  const OnboardingInvite({required this.email, required this.name, required this.isChild});
}

/// What one address turned out to be worth: the two calendars that exist
/// because of *where* a family lives rather than because of an account they
/// hold.
///
/// Both are looked up from the same picked address and neither is guaranteed —
/// a vendor may not serve the street, and the geocoder may not name the state —
/// so each half is nullable and the step renders what it got.
class LocalCalendars {
  /// The waste vendor's answer for the address. Present but unsupported is a
  /// real outcome: "we asked, nobody collects here that we can read".
  final AbfallCoverage? abfall;

  /// The Bundesland code behind the address, for the Schulferien feed.
  final String? ferienState;

  const LocalCalendars({this.abfall, this.ferienState});

  bool get hasAbfall => abfall?.supported == true && abfall?.config != null;
  bool get hasFerien => ferienState != null;
  bool get any => hasAbfall || hasFerien;

  String get ferienName => L.s.schoolHolidaysOf(bundeslaender[ferienState] ?? '');
}

class OnboardingState {
  /// null while the persisted flag is still loading from disk, so the app
  /// shell doesn't flash the wizard for a returning user before it's known.
  final bool? done;

  final int step;
  final List<OnboardingInvite> invites;

  /// Whatever is in the address field — the raw query while it is being typed,
  /// the picked address's label afterwards.
  final String address;

  /// Whether each found calendar is still ticked. They start on the moment the
  /// lookup finds them (that is the whole point of looking), and end up as what
  /// the last step reports as connected.
  final bool trashCalendar;
  final bool ferienCalendar;

  // -- the address lookup
  final List<GeoAddress> addressResults;
  final bool searchingAddress;
  final GeoAddress? pickedAddress;

  /// The spinner between picking an address and knowing what lives there.
  final bool lookingUp;

  /// Non-null once the lookup has run — even when it found nothing, which is
  /// how the step tells "we haven't asked yet" from "we asked, and this is all
  /// there is".
  final LocalCalendars? found;

  final bool connecting;
  final String? addressError;

  const OnboardingState({
    this.done,
    this.step = 0,
    this.invites = const [],
    this.address = '',
    this.trashCalendar = true,
    this.ferienCalendar = true,
    this.addressResults = const [],
    this.searchingAddress = false,
    this.pickedAddress,
    this.lookingUp = false,
    this.found,
    this.connecting = false,
    this.addressError,
  });

  OnboardingState copyWith({
    bool? done,
    int? step,
    List<OnboardingInvite>? invites,
    String? address,
    bool? trashCalendar,
    bool? ferienCalendar,
    List<GeoAddress>? addressResults,
    bool? searchingAddress,
    GeoAddress? pickedAddress,
    bool? lookingUp,
    LocalCalendars? found,
    bool? connecting,
    String? addressError,
    bool clearPickedAddress = false,
    bool clearFound = false,
    bool clearAddressError = false,
  }) {
    return OnboardingState(
      done: done ?? this.done,
      step: step ?? this.step,
      invites: invites ?? this.invites,
      address: address ?? this.address,
      trashCalendar: trashCalendar ?? this.trashCalendar,
      ferienCalendar: ferienCalendar ?? this.ferienCalendar,
      addressResults: addressResults ?? this.addressResults,
      searchingAddress: searchingAddress ?? this.searchingAddress,
      pickedAddress: clearPickedAddress ? null : (pickedAddress ?? this.pickedAddress),
      lookingUp: lookingUp ?? this.lookingUp,
      found: clearFound ? null : (found ?? this.found),
      connecting: connecting ?? this.connecting,
      addressError: clearAddressError ? null : (addressError ?? this.addressError),
    );
  }
}

const _prefsDoneKey = 'onboarding_done';

/// Drives the wizard's steps. Whether the wizard runs at all is decided by
/// `families.onboarding_done` in `_RootGate`, not here — the local flag below
/// is kept only as an offline fallback, because "the household is set up" must
/// not be re-asked on a second device.
///
/// It also owns the address step's lookup, rather than a controller inside the
/// step widget: the wizard's steps are swapped by an `AnimatedSwitcher`, so a
/// widget's own `State` dies the moment you step back to the invitations — and
/// a household that walked back one screen would have to find its address, its
/// waste vendor and its Bundesland all over again.
class OnboardingNotifier extends StateNotifier<OnboardingState> {
  OnboardingNotifier(this._ref) : super(const OnboardingState()) {
    _load();
  }

  final Ref _ref;
  Timer? _addressDebounce;

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

  void setTrashCalendar(bool value) => state = state.copyWith(trashCalendar: value);

  void setFerienCalendar(bool value) => state = state.copyWith(ferienCalendar: value);

  void addInvite(OnboardingInvite invite) => state = state.copyWith(invites: [...state.invites, invite]);

  /// Restarts the wizard from step 0 without touching the persisted "seen"
  /// flag, for Settings' "Willkommenstour wiederholen" row.
  void resetForReplay() => state = OnboardingState(done: state.done);

  // -- the address step -------------------------------------------------------

  /// Typing. Debounced, and short queries are not sent at all — the geocoder
  /// has nothing useful to say about "Am".
  void onAddressQueryChanged(String typed) {
    _addressDebounce?.cancel();
    state = state.copyWith(address: typed, clearAddressError: true);

    final query = typed.trim();
    if (query.length < 3) {
      state = state.copyWith(addressResults: const [], searchingAddress: false);
      return;
    }
    state = state.copyWith(searchingAddress: true);
    _addressDebounce = Timer(const Duration(milliseconds: 300), () => _searchAddresses(query));
  }

  Future<void> _searchAddresses(String query) async {
    try {
      final found = await _ref.read(calendarConnectionRepositoryProvider).searchAddresses(query);
      // The field has moved on while this was in flight — its own search is
      // already on the way, and these results are about a shorter word.
      if (!mounted || state.address.trim() != query) return;
      state = state.copyWith(addressResults: found, searchingAddress: false);
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(searchingAddress: false, addressError: L.s.noAddressFound);
    }
  }

  /// A bare postcode is a prefix, not an address: it goes back into the field so
  /// the street can be typed after it. Returns the text the field should now
  /// hold, or null when the pick was a real address and the lookup has started.
  String? prefixQueryFor(GeoAddress found) {
    if (!found.prefix) return null;
    final text = '${found.postcode ?? ''} ${found.town} ';
    state = state.copyWith(address: text, addressResults: const []);
    return text;
  }

  /// Picking an address *is* the question this step asks. Everything else — the
  /// waste vendor, the Bundesland, both calendars — follows from it without
  /// anybody being asked a second time.
  ///
  /// A vendor lookup that fails is not an error the user can do anything about,
  /// so it is recorded as "no waste calendar for this address" and the Ferien
  /// half still stands: half an answer beats a dead end in a wizard nobody
  /// asked to be in.
  Future<void> pickAddress(GeoAddress found) async {
    _addressDebounce?.cancel();
    state = state.copyWith(
      pickedAddress: found,
      address: found.label,
      addressResults: const [],
      searchingAddress: false,
      lookingUp: true,
      clearFound: true,
      clearAddressError: true,
    );

    AbfallCoverage? coverage;
    try {
      coverage = await _ref.read(calendarConnectionRepositoryProvider).resolveAddress(found);
    } catch (_) {
      coverage = null;
    }
    if (!mounted) return;

    final result = LocalCalendars(abfall: coverage, ferienState: bundeslandCodeFor(found.state));
    state = state.copyWith(
      lookingUp: false,
      found: result,
      // Ticked because they were found. A calendar nobody has to go looking for
      // is the entire reason this step exists.
      trashCalendar: result.hasAbfall,
      ferienCalendar: result.hasFerien,
    );
  }

  /// Back to an empty field, from the X on the address row.
  void resetAddress() {
    _addressDebounce?.cancel();
    state = state.copyWith(
      address: '',
      addressResults: const [],
      searchingAddress: false,
      lookingUp: false,
      clearPickedAddress: true,
      clearFound: true,
      clearAddressError: true,
    );
  }

  /// Creates the feeds that are still ticked, and files the address on the
  /// household. Returns false only when something the user could retry went
  /// wrong; the step stays put on false, and every other outcome moves on.
  ///
  /// Each feed is connected on its own, so a waste vendor having a bad morning
  /// does not cost the family their school holidays. Whichever half fails is
  /// switched off before the last step recaps it — the recap has to say what
  /// actually happened, not what was ticked a moment ago.
  ///
  /// Anything the household already subscribes to is skipped rather than
  /// created again: the tour can be replayed from Settings at any time, and a
  /// second Schulferien row for the same state is not a second calendar.
  Future<bool> connectLocalCalendars() async {
    final address = state.pickedAddress;
    if (address != null) {
      unawaited(_ref.read(familyProvider.notifier).saveAddress(address.label));
    }

    final found = state.found;
    if (found == null || state.connecting) return true;

    final existing = _ref.read(calendarConnectionsProvider);
    final hasFerienAlready = existing
        .of(CalendarProvider.ferien)
        .any((c) => c.ferienBundesland == found.ferienState);
    final hasAbfallAlready = existing.of(CalendarProvider.abfall).isNotEmpty;

    final wantFerien = state.ferienCalendar && found.hasFerien && !hasFerienAlready;
    final wantAbfall = state.trashCalendar && found.hasAbfall && !hasAbfallAlready;
    if (!wantFerien && !wantAbfall) return true;

    state = state.copyWith(connecting: true, clearAddressError: true);
    final connections = _ref.read(calendarConnectionsProvider.notifier);

    var ferienOk = true;
    var abfallOk = true;
    String? error;

    if (wantFerien) {
      try {
        await connections.connectFerien(found.ferienState!, displayName: found.ferienName);
      } catch (_) {
        ferienOk = false;
        error = L.s.calendarsConnectFailed;
      }
    }
    if (wantAbfall) {
      try {
        await connections.connectAbfall(
          config: found.abfall!.config!,
          label: address!.label,
          displayName: _wasteName(address, found.abfall!),
        );
      } catch (_) {
        abfallOk = false;
        error = L.s.calendarsConnectFailed;
      }
    }

    if (!mounted) return error == null;
    state = state.copyWith(
      connecting: false,
      ferienCalendar: state.ferienCalendar && ferienOk,
      trashCalendar: state.trashCalendar && abfallOk,
      addressError: error,
      clearAddressError: error == null,
    );
    return error == null;
  }

  /// The same name the connect sheet would have suggested — the street it
  /// collects from, which is what makes two of them tellable apart.
  String _wasteName(GeoAddress address, AbfallCoverage coverage) {
    final street = coverage.street ?? (address.street.isNotEmpty ? address.street : address.town);
    final number = address.houseNumber;
    return L.s.wasteFor('$street${number == null || number.isEmpty ? '' : ' $number'}');
  }

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

  @override
  void dispose() {
    _addressDebounce?.cancel();
    super.dispose();
  }
}

final onboardingProvider = StateNotifierProvider<OnboardingNotifier, OnboardingState>(
  (ref) => OnboardingNotifier(ref),
);
