import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/entitlements.dart';
import 'family_state.dart';

/// **The one question a screen asks about money.**
///
/// `ref.watch(entitlementProvider).allows(Feature.photos)` — and nothing else.
/// No screen reads `families.plan`, compares a date, or knows what Plus costs;
/// the whole free/paid line lives in `lib/models/entitlements.dart` so it can be
/// moved without touching a widget. See the rules in `docs/production-plan.md`.
///
/// Derived rather than fetched. The household row already carries `plan` and
/// `plan_expires_at`, and it is the load every screen waits behind, so there is
/// no second query and no second moment where the answer could be missing while
/// the rest of the family is on screen.
final entitlementProvider = Provider<Entitlements>((ref) {
  final override = ref.watch(planOverrideProvider);
  if (override != null) {
    return Entitlements(plan: override, overridden: true);
  }

  final household = ref.watch(familyProvider).household;
  // No household yet — signing in, or the row still in flight. `unknown` is
  // free, deliberately; see its doc comment for why that is the safe wrong
  // answer.
  if (household == null) return Entitlements.unknown;

  return Entitlements(plan: household.plan, expiresAt: household.planExpiresAt);
});

/// Run the whole app as free or as Plus without buying anything.
///
/// **This is a development tool and it is worth its weight.** Every screen from
/// here to launch has two states, and the alternative to a switch is a test
/// account per plan, a sandbox purchase to move between them, and a store
/// round trip to check a paywall's wording. Null means "use the real plan",
/// which is what it is in every build nobody has deliberately changed.
///
/// **It cannot grant anything, and that is what makes it safe to leave in a
/// release build.** It is a value in memory: it never touches `families.plan`,
/// which no client holds an update grant on at all. So flipping it to
/// [Plan.plus] shows what the screens look like on Plus — and any limit the
/// server enforces stays enforced, because the server asks the database, not
/// the app.
///
/// Which limits those are is the point: a gate that only exists in Dart is a
/// gate a patched build walks through, so the ones with a cost behind them —
/// calendar accounts above all — are re-checked in the Edge Function that is
/// their only write route. See the server-side item in Phase 0 of
/// `docs/production-plan.md` for which are done.
final planOverrideProvider = StateProvider<Plan?>((ref) => null);
