/// Turns a household's goal into a [ListPlan].
///
/// ## This file is the test path, and it is not how this ships
///
/// **It calls Mistral straight from the device, and the plan says never to do
/// that.** See the "Legal, and it is not a footnote" section of
/// [docs/list-planner.md](../../docs/list-planner.md): a direct call puts the
/// household's IP in front of the provider *and* the API key in the build,
/// where anybody who unzips the `.ipa` can read it. The shipping version is an
/// Edge Function (`list-plan`) holding the key as a function secret, checking
/// the plan cap and the daily rate limit, and writing the usage row.
///
/// It exists in this shape for exactly one reason: **you cannot judge whether
/// the answers are any good until you have seen twenty of them**, and there is
/// no `deno` or Supabase CLI on this machine to deploy the real route with. So
/// the seam is deliberately one function — [planList] — and moving to the Edge
/// Function replaces its body and nothing else.
///
/// **Do not ship a build with a key in it.** [plannerConfigured] is false when
/// none was defined, and a *release* build then hides the entry points on Listen
/// entirely. Debug keeps them, so an unconfigured build says so rather than
/// looking like one where the feature was never written — see [plannerAvailable].
///
/// Run it with the key out of the git-ignored `.env`:
///
/// ```sh
/// flutter run --dart-define=MISTRAL_API_KEY=$(grep '^MISTRAL_API_KEY=' .env | cut -d= -f2-)
/// ```
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../l10n/l10n.dart';
import '../models/grocery_unit.dart';
import '../models/list_plan.dart';

/// The key, supplied at build time and **absent by default**.
///
/// `String.fromEnvironment` rather than a package that reads `.env` at runtime:
/// the app already configures Supabase this way (`lib/services/supabase.dart`),
/// and an asset-bundled `.env` would be a plaintext file inside the shipped app
/// rather than a compile-time constant — worse, for a key that should not be in
/// either.
const _apiKey = String.fromEnvironment('MISTRAL_API_KEY');

/// Overridable so a bad answer can be re-tried against a bigger model without a
/// code change: `--dart-define=MISTRAL_MODEL=mistral-large-latest`.
const _model = String.fromEnvironment('MISTRAL_MODEL', defaultValue: 'mistral-small-latest');

const _host = 'api.mistral.ai';
const _path = '/v1/chat/completions';

/// A goal is one sentence. The cap is on the request rather than on the field so
/// a paste of an entire recipe cannot quietly become a 4,000-token prompt.
const plannerGoalMaxLength = 300;

/// Whether a request can actually be sent.
bool get plannerConfigured => _apiKey.isNotEmpty;

/// Whether the entry points are drawn at all.
///
/// Deliberately a separate question from "may this household use it", the same
/// split `spendAvailable` makes for Ausgaben: this one is about the binary, and
/// the plan cap is about the plan.
///
/// **In debug it is drawn even with no key**, and that is not laziness. Hidden,
/// an unconfigured build is indistinguishable from one where the feature was
/// never added — you look at Listen, see nothing, and have no way to tell which.
/// So the way in stays, the request fails at once, and the sheet says *why* in
/// the reader's own language. A release build with no key still hides it: there
/// the sentence would be about a mistake nobody using the app could fix.
bool get plannerAvailable => plannerConfigured || kDebugMode;

/// Why a Vorhaben failed, in the only three shapes the sheet draws differently.
enum PlannerFailure {
  /// No key in this build, or the provider rejected it.
  notConfigured,

  /// Reached the provider and it said no — rate limit, outage, a 500.
  unavailable,

  /// Got an answer and could not make a list out of it. Distinct from
  /// [unavailable] because retrying the same goal will probably fail the same
  /// way, so the copy asks for a rephrase rather than for patience.
  unusable,
}

class PlannerException implements Exception {
  final PlannerFailure failure;

  const PlannerException(this.failure);
}

/// One request, one answer, no conversation.
///
/// There is no second turn by design — see "The one decision everything follows
/// from" in the doc. A chat invites another paid call and has no finished
/// state; this returns an object and is done.
Future<ListPlan> planList(String goal, {http.Client? client}) async {
  if (!plannerConfigured) throw const PlannerException(PlannerFailure.notConfigured);

  final trimmed = goal.trim();
  if (trimmed.isEmpty) throw const PlannerException(PlannerFailure.unusable);

  final http.Client web = client ?? http.Client();
  try {
    final res = await web
        .post(
          Uri.https(_host, _path),
          headers: {
            'Authorization': 'Bearer $_apiKey',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'model': _model,
            // Low but not zero: a household asking the same thing twice in a
            // week should not get a byte-identical list, and the schema keeps
            // the shape fixed whatever the temperature does to the words.
            'temperature': 0.3,
            'max_tokens': 2000,
            'response_format': {'type': 'json_object'},
            'messages': [
              {'role': 'system', 'content': _systemPrompt()},
              {
                'role': 'user',
                'content': trimmed.length > plannerGoalMaxLength
                    ? trimmed.substring(0, plannerGoalMaxLength)
                    : trimmed,
              },
            ],
          }),
        )
        .timeout(const Duration(seconds: 45));

    if (res.statusCode == 401 || res.statusCode == 403) {
      throw const PlannerException(PlannerFailure.notConfigured);
    }
    if (res.statusCode != 200) throw const PlannerException(PlannerFailure.unavailable);

    // `utf8.decode` rather than `res.body`: http falls back to latin-1 when the
    // response carries no charset, and "Hähnchenbrust" then arrives as mojibake
    // on a list whose whole point is that it looks right.
    final envelope = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final content = (envelope['choices'] as List?)?.firstOrNull as Map<String, dynamic>?;
    final text = (content?['message'] as Map<String, dynamic>?)?['content'] as String?;
    if (text == null || text.trim().isEmpty) throw const PlannerException(PlannerFailure.unusable);

    final plan = ListPlan.fromJson(jsonDecode(text) as Map<String, dynamic>);
    if (!plan.isUsable) throw const PlannerException(PlannerFailure.unusable);
    return plan;
  } on PlannerException {
    rethrow;
  } catch (_) {
    // Timeout, socket, malformed JSON — all the same thing to the reader, who
    // gets an honest sentence and a retry rather than a class name.
    throw const PlannerException(PlannerFailure.unavailable);
  } finally {
    if (client == null) web.close();
  }
}

/// The rules, rebuilt per call because they name the live language.
///
/// **The grocery catalog is deliberately not in here.** Sending 544 article
/// names would multiply the input cost and buy a worse result than
/// `suggestIcon`, which already matches all four languages with the umlauts
/// optional and already strips quantities off a line. What the prompt gives
/// instead is the *style* that makes the matcher work: supermarket labelling,
/// one head noun, no brands.
String _systemPrompt() {
  final units = GroceryUnit.values.map((u) => u.key).join('", "');
  return '''
You turn a household's goal into a shopping list. You answer once, with JSON, and never ask a question back.

Answer entirely in this language: ${L.s.localeCode}. Every title, step and article name must be in it.

Return exactly this object and nothing else:
{
  "title": string,
  "kind": "grocery" | "other",
  "steps": string[],
  "items": [{ "name": string, "quantity": string | null, "unit": string | null }]
}

title: what the list should be called, short, in the user's own words where possible.

kind: "grocery" if the articles are bought in a supermarket, "other" for a hardware store, a chemist, a stationer or anything else.

steps: how to actually do it, in order, one sentence or two each. At most 12. Put recipe measures HERE ("2 EL Butter"), never in the items. Return an empty array when the goal is only about shopping and there is nothing to do.

items: what to BUY. This is the important part.
- Shop quantities, never recipe measures: one pack of butter, not two tablespoons.
- Name each article the way a supermarket or a hardware store labels it: one head noun, no brand names, no descriptions. "Hähnchenbrustfilet", not "boneless skinless chicken breast, about 600g".
- Leave out what every kitchen already has (water, salt, pepper) unless the goal is clearly about stocking up.
- quantity is the number only, as text: "500", "2". Null when it is simply one.
- unit is one of exactly: "$units". Use null for single items. Anything you cannot express with those, put into quantity as text.
- Between 3 and 25 articles.

Never invent a link, a price, a shop or a brand. If the goal is unclear, make the most ordinary assumption a parent would make and answer anyway.
''';
}
