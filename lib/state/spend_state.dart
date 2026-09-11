import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/spend_repository.dart';
import '../data/spend_analysis.dart';
import '../l10n/l10n.dart';
import '../models/spend.dart';
import '../services/spend_intent.dart';
import '../services/supabase.dart';
import 'auth_state.dart';
import 'family_state.dart';
import 'realtime_state.dart';

/// Everything the Spend page renders, and nothing it doesn't.
///
/// The rows are held flat, exactly as the Board holds its tasks; every total,
/// line and bar on the page is a fold over them computed in [summariseRange].
/// Nothing derived is stored, because a stored total is a second source of
/// truth that the next edit silently contradicts.
class SpendState {
  /// Every row inside the loaded window, newest first.
  final List<Spend> spends;

  /// The stretch of time the page is adding up.
  final SpendRange range;

  /// Which rows are being counted — everything, the fixed ones, or the extras.
  /// It filters the whole page rather than one card, because it is the label on
  /// the headline total.
  final SpendMetric metric;

  /// The half-open range currently held in [spends]. It always reaches back
  /// over [SpendRange.previous] as well, because the comparison line needs the
  /// stretch before the one on screen; switching to a range inside it costs no
  /// round trip at all, which is what makes the slicer feel instant.
  final DateTime windowFrom;
  final DateTime windowTo;

  /// The phones allowed to file Apple Pay transactions into this household.
  final List<SpendDevice> devices;

  /// Whether *this* phone is one of them. Answered by the Keychain rather than
  /// by [devices]: the list says who may write, the Keychain says whether we
  /// hold the token to do it, and only the second question can be answered
  /// offline or distinguish this iPhone from the other parent's.
  final bool thisDeviceEnrolled;

  /// True while `spend-enroll` is in flight, so the button can say so.
  final bool enrolling;

  final bool loading;

  /// German, and safe to render verbatim.
  final String? error;

  const SpendState({
    this.spends = const [],
    required this.range,
    this.metric = SpendMetric.all,
    required this.windowFrom,
    required this.windowTo,
    this.devices = const [],
    this.thisDeviceEnrolled = false,
    this.enrolling = false,
    this.loading = true,
    this.error,
  });

  /// Starts on the month the user is living in — the cheapest range to fetch
  /// and the one a household asks about most.
  factory SpendState.initial() {
    final range = SpendRange.of(SpendPeriod.month);
    return SpendState(
      range: range,
      windowFrom: range.previous.from,
      windowTo: range.to,
    );
  }

  /// The whole page, folded. Recomputed on every read rather than cached: it is
  /// a pass over a few hundred rows, and a cache keyed on "the rows changed"
  /// would be the same pass plus a way to get it wrong.
  SpendSummary get summary => summariseRange(spends, range, metric: metric);

  /// Whether [spends] already reaches over everything [range] and its
  /// comparison need.
  bool covers(SpendRange other) =>
      !other.previous.from.isBefore(windowFrom) && !other.to.isAfter(windowTo);

  SpendState copyWith({
    List<Spend>? spends,
    SpendRange? range,
    SpendMetric? metric,
    DateTime? windowFrom,
    DateTime? windowTo,
    List<SpendDevice>? devices,
    bool? thisDeviceEnrolled,
    bool? enrolling,
    bool? loading,
    String? error,
    bool clearError = false,
  }) => SpendState(
    spends: spends ?? this.spends,
    range: range ?? this.range,
    metric: metric ?? this.metric,
    windowFrom: windowFrom ?? this.windowFrom,
    windowTo: windowTo ?? this.windowTo,
    devices: devices ?? this.devices,
    thisDeviceEnrolled: thisDeviceEnrolled ?? this.thisDeviceEnrolled,
    enrolling: enrolling ?? this.enrolling,
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
  );
}

class SpendNotifier extends StateNotifier<SpendState> {
  SpendNotifier(this._repo, this._intents, this._userId, this._familyId, this._isAdmin)
    : super(SpendState.initial()) {
    if (_userId != null && _isAdmin) {
      load();
    } else {
      // A member or a kid reaches the tab and is told why, rather than watching
      // a spinner over an empty list that RLS was always going to return.
      state = state.copyWith(loading: false);
    }
  }

  final SpendRepository _repo;
  final SpendIntents _intents;
  final String? _userId;
  final String? _familyId;
  final bool _isAdmin;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Loads the window around the selected range and checks whether this phone
  /// still holds a token.
  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final rows = await _repo.fetchRange(state.windowFrom, state.windowTo);
      if (!mounted) return;
      state = state.copyWith(spends: rows, loading: false);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(loading: false, error: L.s.spendLoadFailed);
    }

    await refreshDevices();
  }

  /// The device list and this phone's own enrolment, which move together: a
  /// token revoked from another phone should stop this one claiming to be
  /// active.
  Future<void> refreshDevices() async {
    if (!_isAdmin) return;
    try {
      final devices = await _repo.fetchDevices();
      final mine = await _intents.hasToken();
      if (!mounted) return;
      state = state.copyWith(devices: devices, thisDeviceEnrolled: mine);
    } catch (_) {
      // Silent on purpose. The device list is a Settings detail; failing to read
      // it must not put an error banner over a page full of correct numbers.
    }
  }

  // ---------------------------------------------------------------------------
  // Moving through time
  // ---------------------------------------------------------------------------

  /// Shows another stretch, fetching only when the loaded window does not
  /// already reach over it and the one before it.
  ///
  /// The range goes on screen **before** any fetch, so the slicer answers the
  /// tap immediately and the chart redraws from the rows already held; a wider
  /// range then fills in under it. Going from a year to a week never waits at
  /// all, because the week is inside the year.
  Future<void> showRange(SpendRange range) async {
    if (range == state.range) return;

    state = state.copyWith(range: range);
    if (state.covers(range)) return;

    final from = range.previous.from;
    final to = range.to;
    state = state.copyWith(windowFrom: from, windowTo: to, loading: true, clearError: true);
    try {
      final rows = await _repo.fetchRange(from, to);
      if (!mounted) return;
      state = state.copyWith(spends: rows, loading: false);
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(loading: false, error: L.s.spendLoadFailed);
    }
  }

  Future<void> showPeriod(SpendPeriod period) => showRange(SpendRange.of(period));

  /// Changes what is being counted. No fetch: the rows are already here and
  /// this is a filter over them.
  void showMetric(SpendMetric metric) => state = state.copyWith(metric: metric);

  // ---------------------------------------------------------------------------
  // Writing
  // ---------------------------------------------------------------------------

  /// Files one spend the user typed.
  ///
  /// No optimistic row here, unlike a new list or box. Leaving the category to
  /// the database is the whole point of the manual form's "automatisch" default,
  /// and the answer only exists on the row that comes back — an optimistic row
  /// would have to guess it in Dart, which is exactly the second copy of the
  /// merchant rules this design avoids.
  Future<bool> addSpend({
    required String merchant,
    required int amountCents,
    required DateTime occurredAt,
    String? payerId,
    SpendCategory? category,
    SpendKind? kind,
    String? note,
  }) async {
    final familyId = _familyId;
    if (familyId == null) return false;

    try {
      final spend = await _repo.createSpend(
        familyId: familyId,
        merchant: merchant,
        amountCents: amountCents,
        occurredAt: occurredAt,
        payerId: payerId,
        category: category,
        kind: kind,
        note: note,
      );
      if (!mounted) return true;
      _insert(spend);
      return true;
    } catch (_) {
      if (mounted) state = state.copyWith(error: L.s.spendSaveFailed);
      return false;
    }
  }

  /// Corrects a row, on screen first and on the server after. Rolls back on
  /// failure, so a row cannot end up saying something the database does not.
  Future<void> editSpend(Spend updated) async {
    final before = state.spends.firstWhere((s) => s.id == updated.id, orElse: () => updated);
    _replace(updated);
    try {
      final saved = await _repo.updateSpend(updated);
      if (mounted) _replace(saved);
    } catch (_) {
      if (!mounted) return;
      _replace(before);
      state = state.copyWith(error: L.s.spendSaveFailed);
    }
  }

  /// Removes a row and hands it back, so the caller can offer an undo that
  /// restores the same id rather than a copy of it.
  Future<Spend?> deleteSpend(String id) async {
    final index = state.spends.indexWhere((s) => s.id == id);
    if (index < 0) return null;
    final removed = state.spends[index];

    state = state.copyWith(spends: [for (final s in state.spends) if (s.id != id) s]);
    try {
      await _repo.deleteSpend(id);
      return removed;
    } catch (_) {
      if (!mounted) return null;
      _insert(removed);
      state = state.copyWith(error: L.s.spendDeleteFailed);
      return null;
    }
  }

  /// Puts a deleted row back. Answers whether it landed, because that is what
  /// `UndoRestore` is: the chip stays up and says so when an undo itself fails.
  Future<bool> undoDelete(Spend spend) async {
    _insert(spend);
    try {
      await _repo.restoreSpend(spend);
      return true;
    } catch (_) {
      if (!mounted) return false;
      state = state.copyWith(
        spends: [for (final s in state.spends) if (s.id != spend.id) s],
        error: L.s.spendSaveFailed,
      );
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // This phone's permission to file Apple Pay transactions
  // ---------------------------------------------------------------------------

  /// Mints a token for this device and hands it to the Keychain, where the App
  /// Intent will find it.
  ///
  /// The token never touches the UI, `shared_preferences` or a clipboard — the
  /// entire reason this replaces the old copy-and-paste flow is that the user no
  /// longer handles a credential.
  Future<bool> enrolThisDevice() async {
    if (!_intents.isSupported) {
      state = state.copyWith(error: L.s.spendWalletUnsupported);
      return false;
    }

    state = state.copyWith(enrolling: true, clearError: true);
    try {
      final device = await _intents.describeDevice();
      final enrolment = await _repo.enrolDevice(label: device.label, deviceUid: device.uid);
      await _intents.storeToken(
        token: enrolment.token,
        endpoint: '${AporahSupabase.url}/functions/v1/spend-ingest',
        apiKey: AporahSupabase.publishableKey,
      );
      if (!mounted) return true;
      state = state.copyWith(enrolling: false, thisDeviceEnrolled: true);
      await refreshDevices();
      return true;
    } on StateError catch (e) {
      if (mounted) state = state.copyWith(enrolling: false, error: e.message);
      return false;
    } catch (_) {
      if (mounted) state = state.copyWith(enrolling: false, error: L.s.spendEnrolFailed);
      return false;
    }
  }

  /// Stops a phone filing spends. When it is this one, the Keychain copy goes
  /// too — leaving it would mean a device that still holds a credential the
  /// household has taken back.
  Future<void> revokeDevice(String id, {required bool isThisDevice}) async {
    try {
      await _repo.revokeDevice(id);
      if (isThisDevice) await _intents.clearToken();
      if (!mounted) return;
      state = state.copyWith(
        devices: [for (final d in state.devices) if (d.id != id) d],
        thisDeviceEnrolled: isThisDevice ? false : state.thisDeviceEnrolled,
      );
    } catch (_) {
      if (mounted) state = state.copyWith(error: L.s.spendSaveFailed);
    }
  }

  void clearError() => state = state.copyWith(clearError: true);

  // ---------------------------------------------------------------------------
  // Row plumbing
  // ---------------------------------------------------------------------------

  /// Puts a row back in date order without re-sorting the whole list. The list
  /// is newest first, so the row goes before the first one older than it.
  void _insert(Spend spend) {
    final rows = [for (final s in state.spends) if (s.id != spend.id) s];
    var at = rows.indexWhere((s) => !s.occurredAt.isAfter(spend.occurredAt));
    if (at < 0) at = rows.length;
    rows.insert(at, spend);
    state = state.copyWith(spends: rows);
  }

  void _replace(Spend spend) {
    state = state.copyWith(
      spends: [for (final s in state.spends) s.id == spend.id ? spend : s],
    );
  }
}

final spendRepositoryProvider = Provider<SpendRepository>((ref) => SpendRepository(AporahSupabase.client));

final spendIntentsProvider = Provider<SpendIntents>((ref) => const SpendIntents());

/// Rebuilt when the signed-in user, their household or their role changes.
///
/// The role is watched rather than read once because a member promoted to admin
/// should see the page fill in without restarting the app — and, more to the
/// point, because a demotion must empty it.
final spendProvider = StateNotifierProvider<SpendNotifier, SpendState>((ref) {
  final notifier = SpendNotifier(
    ref.watch(spendRepositoryProvider),
    ref.watch(spendIntentsProvider),
    ref.watch(currentUserIdProvider),
    ref.watch(familyProvider.select((s) => s.household?.id)),
    ref.watch(isAdminProvider),
  );
  reloadOnFamilyChange(ref, const {'spends'}, notifier.load);
  return notifier;
});
