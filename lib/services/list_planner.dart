/// Turns a household's goal into a [ListPlan], by asking the `list-plan` Edge
/// Function.
///
/// ## The key is not in the app, and must never be again
///
/// The first version called Mistral straight from the device with the key
/// compiled in through `--dart-define`. A key inside a mobile build is readable
/// by anyone who unzips the `.ipa` or watches their own phone's traffic, and no
/// obfuscation changes that. So the key is `MISTRAL_API_KEY` in Supabase's
/// function secrets, and this file holds nothing but the user's own session.
///
/// The function also decides everything that costs money — the monthly plan
/// cap, whether the model's answer is usable, and whether a request may skip the
/// limits at all — because a check that only exists here is one a patched build
/// walks straight past. See `supabase/functions/list-plan/index.ts` and "What
/// the server does" in [docs/list-planner.md](../../docs/list-planner.md).
///
/// **Don't bring back a direct provider call** "for testing" — it is exactly how
/// a key ends up in a build that leaves the laptop.
library;

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

import '../l10n/l10n.dart';
import '../models/list_plan.dart';
import 'supabase.dart';

/// A goal is one sentence. The server enforces the same cap; this one only
/// keeps a pasted recipe from being uploaded to be cut there.
const plannerGoalMaxLength = 300;

/// Why a Vorhaben failed, in the shapes the card draws differently.
enum PlannerFailure {
  /// The project has no `MISTRAL_API_KEY` secret, or the provider rejected it.
  notConfigured,

  /// Reached nothing useful — offline, a timeout, the provider down.
  unavailable,

  /// Got an answer and could not make a list out of it. Distinct from
  /// [unavailable] because retrying the same goal will probably fail the same
  /// way, so the copy asks for a rephrase rather than for patience.
  unusable,

  /// The household's plan cap for this month is used up.
  monthlyLimit,

  /// This user's daily abuse limit is reached. Only a plan without a monthly
  /// cap has one, and no plan is like that today — see the server.
  dailyLimit,

  /// A page was handed over, was read, and had no recipe markup on it.
  ///
  /// **Never reached by a generated plan** — only by [PlannerNotifier.runImport].
  /// Distinct from [unusable] because the advice differs: a goal that confused
  /// the model is worth rephrasing, and a page with no recipe on it will not
  /// improve on a second reading, so the copy points at typing the dish
  /// instead.
  noRecipeOnPage,

  /// A YouTube video was handed over, the description was read, and it held no
  /// ingredient list.
  ///
  /// Its own value rather than [noRecipeOnPage] because the copy has to name
  /// the right thing. A recipe page that fails is a page we could not read; a
  /// video that fails is a channel that did not write its ingredients down,
  /// which is neither the reader's fault nor fixable by trying again — and
  /// telling them we "could not read that page" would send them looking for a
  /// problem at our end.
  noRecipeInVideo,
}

/// How much of this month's Vorhaben the household has used, **as the server
/// counts it**.
///
/// Never worked out in the app. The numbers are enforced in
/// `_shared/entitlements.ts`, and a copy of "3 free, 30 Plus" here would be the
/// copy that drifts — the card would promise a plan the function then refuses.
/// So `list-plan` hands this back with every answer and the card only prints it.
class PlannerUsage {
  final int used;

  /// Null when the plan has no monthly cap.
  final int? limit;

  /// When the count starts again: the first of next month, 00:00 **UTC**.
  ///
  /// Kept in UTC on purpose. Read `.day` off the local time and a household in
  /// São Paulo is told its plans come back on the 30th.
  final DateTime resetsAt;

  /// The limits were lifted for this request — the debug switch asked, and the
  /// server found the account in `plan_limit_exemptions`.
  final bool exempt;

  const PlannerUsage({required this.used, required this.limit, required this.resetsAt, this.exempt = false});

  /// Plans left this month; null when there is no cap to count down.
  int? get left => switch (limit) {
    null => null,
    final cap => used >= cap ? 0 : cap - used,
  };

  /// Whether the card should stop offering to send.
  bool get usedUp => !exempt && left == 0;

  static PlannerUsage? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final used = raw['used'];
    final limit = raw['limit'];
    final resetsAt = raw['resetsAt'] is String ? DateTime.tryParse(raw['resetsAt'] as String) : null;
    if (used is! int || (limit != null && limit is! int) || resetsAt == null) return null;
    return PlannerUsage(
      used: used,
      limit: limit as int?,
      resetsAt: resetsAt.toUtc(),
      exempt: raw['exempt'] == true,
    );
  }
}

class PlannerException implements Exception {
  final PlannerFailure failure;

  /// The household's count as the refusal saw it, when the function got that far.
  final PlannerUsage? usage;

  /// When a [PlannerFailure.dailyLimit] lifts, in local time. The window rolls,
  /// so this is the oldest run in it plus a day rather than midnight.
  final DateTime? retryAt;

  const PlannerException(this.failure, {this.usage, this.retryAt});
}

typedef PlannerResult = ({ListPlan plan, PlannerUsage? usage});

/// One request, one answer, no conversation.
///
/// There is no second turn by design — see "The one decision everything follows
/// from" in the doc. [ignoreLimits] and [simulatePlan] are the debug switches' requests; the server
/// decides whether they count.
Future<PlannerResult> planList(String goal, {bool ignoreLimits = false, String? simulatePlan}) async {
  final trimmed = goal.trim();
  if (trimmed.isEmpty) throw const PlannerException(PlannerFailure.unusable);

  try {
    final res = await AporahSupabase.client.functions
        .invoke(
          'list-plan',
          body: {
            'goal': trimmed.length > plannerGoalMaxLength
                ? trimmed.substring(0, plannerGoalMaxLength)
                : trimmed,
            // The answer is written in the interface language, which only the
            // device knows.
            'locale': L.s.localeCode,
            if (ignoreLimits) 'ignoreLimits': true,
            'simulatePlan': ?simulatePlan,
          },
        )
        // Longer than the function's own 45s provider timeout, so a slow model
        // comes back as the function's answer rather than as ours.
        .timeout(const Duration(seconds: 60));

    final data = res.data;
    final raw = data is Map ? data['plan'] : null;
    if (raw is! Map) throw const PlannerException(PlannerFailure.unusable);
    final plan = ListPlan.fromJson(Map<String, dynamic>.from(raw));
    if (!plan.isUsable) throw const PlannerException(PlannerFailure.unusable);
    return (plan: plan, usage: PlannerUsage.fromJson(data is Map ? data['usage'] : null));
  } on PlannerException {
    rethrow;
  } on FunctionException catch (e) {
    final details = e.details is Map ? e.details as Map : const {};
    final retryAt = details['retryAt'];
    throw PlannerException(
      switch (details['code']) {
        'not_configured' => PlannerFailure.notConfigured,
        'limit_reached' => PlannerFailure.monthlyLimit,
        'rate_limited' => PlannerFailure.dailyLimit,
        'unusable' => PlannerFailure.unusable,
        _ => PlannerFailure.unavailable,
      },
      usage: PlannerUsage.fromJson(details['usage']),
      retryAt: retryAt is String ? DateTime.tryParse(retryAt)?.toLocal() : null,
    );
  } catch (_) {
    // Timeout, socket, malformed JSON — all the same thing to the reader, who
    // gets an honest sentence and a retry rather than a class name.
    throw const PlannerException(PlannerFailure.unavailable);
  }
}

/// What the card prints under the field, before anything has been asked.
///
/// Free — the function answers from the database and calls no model. **Null on
/// any failure**: the line is information, and a count that did not arrive is
/// simply no line rather than an error about a number.
Future<PlannerUsage?> fetchPlannerUsage({bool ignoreLimits = false, String? simulatePlan}) async {
  try {
    final res = await AporahSupabase.client.functions
        .invoke(
          'list-plan',
          body: {'mode': 'usage', if (ignoreLimits) 'ignoreLimits': true, 'simulatePlan': ?simulatePlan},
        )
        .timeout(const Duration(seconds: 15));
    final data = res.data;
    return PlannerUsage.fromJson(data is Map ? data['usage'] : null);
  } catch (_) {
    return null;
  }
}
