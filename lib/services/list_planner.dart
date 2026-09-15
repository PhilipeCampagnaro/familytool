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
/// The function also decides everything that costs money — the daily abuse
/// limit, the monthly plan cap, whether the model's answer is usable — because a
/// check that only exists here is one a patched build walks straight past. See
/// `supabase/functions/list-plan/index.ts` and "What the server does" in
/// [docs/list-planner.md](../../docs/list-planner.md).
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

  /// This user's daily abuse limit is reached.
  dailyLimit,
}

class PlannerException implements Exception {
  final PlannerFailure failure;

  const PlannerException(this.failure);
}

/// One request, one answer, no conversation.
///
/// There is no second turn by design — see "The one decision everything follows
/// from" in the doc.
Future<ListPlan> planList(String goal) async {
  final trimmed = goal.trim();
  if (trimmed.isEmpty) throw const PlannerException(PlannerFailure.unusable);

  try {
    final res = await AporahSupabase.client.functions
        .invoke(
          'list-plan',
          body: {
            'goal': trimmed.length > plannerGoalMaxLength ? trimmed.substring(0, plannerGoalMaxLength) : trimmed,
            // The answer is written in the interface language, which only the
            // device knows.
            'locale': L.s.localeCode,
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
    return plan;
  } on PlannerException {
    rethrow;
  } on FunctionException catch (e) {
    final details = e.details;
    throw PlannerException(switch (details is Map ? details['code'] : null) {
      'not_configured' => PlannerFailure.notConfigured,
      'limit_reached' => PlannerFailure.monthlyLimit,
      'rate_limited' => PlannerFailure.dailyLimit,
      'unusable' => PlannerFailure.unusable,
      _ => PlannerFailure.unavailable,
    });
  } catch (_) {
    // Timeout, socket, malformed JSON — all the same thing to the reader, who
    // gets an honest sentence and a retry rather than a class name.
    throw const PlannerException(PlannerFailure.unavailable);
  }
}
