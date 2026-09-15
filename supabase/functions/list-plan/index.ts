/// Vorhaben: turn one household goal into a shopping-list plan.
///
/// **This function exists so the Mistral key is never in the app.** A key
/// compiled into a mobile build is readable by anyone who unzips the `.ipa` or
/// watches their own phone's traffic, and no obfuscation changes that. Here it
/// is `MISTRAL_API_KEY`, a function secret like `RESEND_API_KEY`, and the app
/// only ever holds the user's own session.
///
/// Ordinary `verify_jwt = true`: there is a real session behind every call, so
/// there is no entry in `config.toml`. The order of the checks is the point:
///
///   1. who is calling — `callerId`, never a user id from the body;
///   2. which household — their membership row, never a family id from the body;
///   3. the monthly plan cap — or, on a plan without one, the daily per-user
///      abuse limit — counted from `list_plan_runs`, which no client can write;
///   4. only then the paid call, and the usage row only after it answered, so a
///      failed generation is never charged.
///
/// **Two request shapes.** `{goal, locale}` makes a plan. `{mode: "usage"}`
/// makes nothing and costs nothing: it answers how much of the month is used,
/// so the card can print "noch 27 von 30" before anybody types. Every answer
/// that has the household in hand carries the same `usage` object, so the app
/// never counts for itself.
///
/// **`ignoreLimits: true` is a request, not a grant.** It is what the debug
/// switch in Settings sends, and it is honoured only for a caller listed in
/// `public.plan_limit_exemptions`, which no client can read or write. From
/// anybody else it is ignored without comment, so a patched build that sends it
/// gains nothing. The usage row is still written — the call still cost money.
/// `simulatePlan: "free" | "plus"` is the same kind of request, from the
/// Settings plan switch, so a tester sees the free household's 3 counted and
/// refused by the server rather than only relabelled by the app.
///
/// **Neither the goal nor the answer is stored or logged.** A household's
/// dinner plans are not ours to keep. Errors log the provider's status code and
/// nothing the household typed.
///
/// Refusals carry a machine-readable `code` beside the usual German `error`:
/// the app is in four languages and picks its own sentence from the code.

import { callerId, corsHeaders, json, serviceClient } from "../_shared/http.ts";
import { listPlanUsage } from "../_shared/entitlements.ts";
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

/// Abuse, not plan — and **only on a plan with no monthly cap.** Both plans
/// have one today, so this never answers; it is here so that a future unlimited
/// tier cannot ship without a ceiling.
///
/// It used to apply to everybody, and that was two limits doing one job. A
/// monthly cap already bounds what a stolen session can spend, so a lower daily
/// wall on top of it stopped only the household it was not for: a Plus family
/// allowed thirty a month met "enough for today" after ten, and could not have
/// been told why the thirty did not mean thirty.
const MAX_PLANS_PER_USER_PER_DAY = 10;

const DAY_MS = 24 * 60 * 60 * 1000;

/// A goal is one sentence. Capped here, not only in the field, so a patched
/// client cannot turn a pasted recipe into a 4,000-token prompt on our bill.
const GOAL_MAX_LENGTH = 300;

const LOCALES = new Set(["de", "en", "pt", "es"]);

/// Must match the keys of `GroceryUnit` in `lib/models/grocery_unit.dart`.
/// Validated here as well as asked for in the prompt, so a model that invents a
/// unit cannot put an eleventh value into a column that holds ten.
const UNITS = ["piece", "g", "kg", "ml", "l", "pack", "can", "bottle", "bunch", "glass"];

const MISTRAL_URL = "https://api.mistral.ai/v1/chat/completions";

type Code = "unauthenticated" | "bad_request" | "no_household" | "rate_limited" | "limit_reached"
  | "not_configured" | "unavailable" | "unusable";

function refuse(code: Code, error: string, status: number, extra: Record<string, unknown> = {}): Response {
  return json({ code, error, ...extra }, status);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return refuse("bad_request", "Ungültige Anfrage.", 405);

  const uid = await callerId(req);
  if (!uid) return refuse("unauthenticated", "Nicht angemeldet.", 401);

  let body: { goal?: unknown; locale?: unknown; mode?: unknown; ignoreLimits?: unknown; simulatePlan?: unknown };
  try {
    body = await req.json();
  } catch {
    return refuse("bad_request", "Ungültige Anfrage.", 400);
  }

  const usageOnly = body.mode === "usage";
  const goal = typeof body.goal === "string" ? body.goal.trim().slice(0, GOAL_MAX_LENGTH) : "";
  if (!usageOnly && !goal) return refuse("unusable", "Kein Vorhaben angegeben.", 400);
  const locale = typeof body.locale === "string" && LOCALES.has(body.locale) ? body.locale : "de";

  // Checked before any count, so a project without the secret answers the same
  // way for everybody and costs no database round trips. A usage question
  // needs no key.
  const apiKey = Deno.env.get("MISTRAL_API_KEY");
  if (!usageOnly && !apiKey) return refuse("not_configured", "Vorhaben ist nicht eingerichtet.", 503);

  const db = serviceClient();

  const { data: membership } = await db
    .from("family_members")
    .select("family_id")
    .eq("user_id", uid)
    .maybeSingle();
  if (!membership) return refuse("no_household", "Kein Haushalt gefunden.", 403);

  // Both test flags ride on the same list: from anybody not on it they are
  // ignored, and the table is only read when one was actually sent.
  const simulatePlan = body.simulatePlan === "free" || body.simulatePlan === "plus" ? body.simulatePlan : undefined;
  const tester = (body.ignoreLimits === true || simulatePlan !== undefined) && await isLimitExempt(db, uid);
  const exempt = tester && body.ignoreLimits === true;
  const usage = await listPlanUsage(db, membership.family_id, tester ? simulatePlan : undefined);
  const report = (used: number) => ({ used, limit: usage.limit, resetsAt: usage.resetsAt, exempt });

  if (usageOnly) return json({ usage: report(usage.used) });

  if (!exempt) {
    if (usage.limit !== null) {
      if (usage.used >= usage.limit) {
        return refuse("limit_reached", "Die Vorhaben für diesen Monat sind aufgebraucht.", 402, {
          usage: report(usage.used),
        });
      }
    } else {
      const since = new Date(Date.now() - DAY_MS).toISOString();
      // The oldest run in the window is when the first slot frees up — the
      // window rolls, so "tomorrow" would be a guess and this is the answer.
      const { data: oldest, count } = await db
        .from("list_plan_runs")
        .select("created_at", { count: "exact" })
        .eq("created_by", uid)
        .gte("created_at", since)
        .order("created_at", { ascending: true })
        .limit(1);
      if ((count ?? 0) >= MAX_PLANS_PER_USER_PER_DAY) {
        const first = oldest?.[0]?.created_at;
        return refuse("rate_limited", "Für heute sind es genug Vorhaben.", 429, {
          usage: report(usage.used),
          retryAt: first ? new Date(Date.parse(first) + DAY_MS).toISOString() : null,
        });
      }
    }
  }

  let res: Response;
  try {
    res = await fetch(MISTRAL_URL, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
      body: JSON.stringify({
        model: Deno.env.get("MISTRAL_MODEL") ?? "mistral-small-latest",
        // Low but not zero: the same goal twice in a week should not return a
        // byte-identical list, and the schema holds the shape whatever this does.
        temperature: 0.3,
        max_tokens: 2000,
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: systemPrompt(locale) },
          { role: "user", content: goal },
        ],
      }),
      signal: AbortSignal.timeout(45_000),
    });
  } catch (e) {
    console.error("list-plan: provider unreachable", e instanceof Error ? e.name : "unknown");
    return refuse("unavailable", "Das hat gerade nicht geklappt.", 502);
  }

  if (!res.ok) {
    // The status only — the body can echo the request, and the request is the
    // household's goal.
    console.error("list-plan: provider answered", res.status);
    // A rejected key is our misconfiguration, not the household's problem.
    if (res.status === 401 || res.status === 403) {
      return refuse("not_configured", "Vorhaben ist nicht eingerichtet.", 503);
    }
    return refuse("unavailable", "Das hat gerade nicht geklappt.", 502);
  }

  let envelope: {
    choices?: { message?: { content?: unknown } }[];
    usage?: { prompt_tokens?: unknown; completion_tokens?: unknown };
  };
  let plan: ReturnType<typeof sanitize>;
  try {
    envelope = await res.json();
    const content = envelope.choices?.[0]?.message?.content;
    if (typeof content !== "string") throw new Error("no content");
    plan = sanitize(JSON.parse(content));
  } catch {
    return refuse("unusable", "Daraus ließ sich keine Liste machen.", 422);
  }
  if (plan.items.length === 0) return refuse("unusable", "Daraus ließ sich keine Liste machen.", 422);

  // After the answer, never before: only a plan that reached the household
  // counts against it. A failed insert still returns the plan — the call is
  // already paid for — and is logged so a broken counter cannot go unnoticed.
  const { error } = await db.from("list_plan_runs").insert({
    family_id: membership.family_id,
    created_by: uid,
    prompt_tokens: intOrNull(envelope.usage?.prompt_tokens),
    completion_tokens: intOrNull(envelope.usage?.completion_tokens),
  });
  if (error) console.error("list-plan: usage row not written", error.code);

  return json({ plan, usage: report(usage.used + (error ? 0 : 1)) });
});

/// Whether this caller may lift the limits. Read with `service_role`; the table
/// has no grant for anybody else.
async function isLimitExempt(db: SupabaseClient, uid: string): Promise<boolean> {
  const { data } = await db
    .from("plan_limit_exemptions")
    .select("user_id")
    .eq("user_id", uid)
    .maybeSingle();
  return data !== null;
}

function intOrNull(v: unknown): number | null {
  return typeof v === "number" && Number.isFinite(v) ? Math.trunc(v) : null;
}

function text(v: unknown, max: number): string {
  return typeof v === "string" ? v.trim().slice(0, max) : "";
}

/// The model's answer, reduced to exactly the shape the app reads. Everything
/// the schema did not ask for is dropped, and every string is bounded, so what
/// leaves this function is data of a known size rather than whatever a model
/// happened to produce.
function sanitize(raw: unknown) {
  const o = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>;
  const items = (Array.isArray(o.items) ? o.items : []).flatMap((i) => {
    if (!i || typeof i !== "object") return [];
    const item = i as Record<string, unknown>;
    const name = text(item.name, 120);
    if (!name) return [];
    const quantity = typeof item.quantity === "number" && Number.isFinite(item.quantity)
      ? String(item.quantity)
      : text(item.quantity, 40) || null;
    const unit = typeof item.unit === "string" && UNITS.includes(item.unit) ? item.unit : null;
    return [{ name, quantity, unit }];
  });
  return {
    title: text(o.title, 120),
    kind: o.kind === "other" ? "other" : "grocery",
    steps: (Array.isArray(o.steps) ? o.steps : []).map((s) => text(s, 500)).filter(Boolean).slice(0, 12),
    items: items.slice(0, 25),
  };
}

/// The grocery catalog is deliberately not in here: `suggestIcon` on the device
/// already matches all four languages, and what the prompt gives it instead is
/// the naming *style* that makes that matcher work.
function systemPrompt(locale: string): string {
  const units = UNITS.join('", "');
  return `You turn a household's goal into a shopping list. You answer once, with JSON, and never ask a question back.

Answer entirely in this language: ${locale}. Every title, step and article name must be in it.

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
- unit is one of exactly: "${units}". Use null for single items. Anything you cannot express with those, put into quantity as text.
- Between 3 and 25 articles.

Never invent a link, a price, a shop or a brand. If the goal is unclear, make the most ordinary assumption a parent would make and answer anyway.`;
}
