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
        // **A dated model, never `-latest`.** The alias moves when Mistral ships
        // the next Small, and the prompt below was tuned against this one — the
        // `#` title, whole `##` stages, `kind: "other"` for a tin of paint. A
        // moved alias would change all of that without a deploy, and the first
        // sign would be a broken card on somebody's phone. Upgrading is a probe
        // against the new model and then this line, or `MISTRAL_MODEL` to try one.
        model: Deno.env.get("MISTRAL_MODEL") ?? "mistral-small-2603",
        // Low but not zero: the same goal twice in a week should not return a
        // byte-identical list, and the schema holds the shape whatever this does.
        temperature: 0.3,
        // Headroom for `recipe`, which is the one unbounded field in the answer.
        // A truncated answer is not a short answer: the JSON stops mid-string,
        // `JSON.parse` throws, and the household gets "Daraus ließ sich keine
        // Liste machen" after waiting — having already been charged for the call.
        max_tokens: 4000,
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

/// **There is no emoji validator here any more, and that is the point.** An
/// emoji used to be a *field* — one per article, checked against
/// `Extended_Pictographic` because it was about to be stored in `icon_asset`
/// and drawn as a row's icon. It is now part of `steps` and `recipe`, which are
/// prose: bounded by `text()` like every other string, drawn as text, and
/// stored nowhere but the list's own method. Nothing needs validating, because
/// nothing is being resolved into a picture on a row.

/// The model's answer, reduced to exactly the shape the app reads. Everything
/// the schema did not ask for is dropped, and every string is bounded, so what
/// leaves this function is data of a known size rather than whatever a model
/// happened to produce.
function sanitize(raw: unknown) {
  const o = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>;
  const kind = o.kind === "other" ? "other" : "grocery";
  const items = (Array.isArray(o.items) ? o.items : []).flatMap((i) => {
    if (!i || typeof i !== "object") return [];
    const item = i as Record<string, unknown>;
    const name = text(item.name, 120);
    if (!name) return [];
    const quantity = typeof item.quantity === "number" && Number.isFinite(item.quantity)
      ? String(item.quantity)
      : text(item.quantity, 40) || null;
    const unit = typeof item.unit === "string" && UNITS.includes(item.unit) ? item.unit : null;
    // No `emoji` field to read: see the note above `sanitize` and the prompt.
    // **No picture on an article, deliberately, since 2026-09-16.** A Sonstige
    // article carried one emoji for a day: asked for in the prompt and forced
    // here so a list could not come back half emoji and half symbol. What that
    // fixed was the inconsistency, not the mistakes — 🧴 against a Dichtungsband
    // and 🔩 against a Dübel are each read before the word beside them, and a
    // wrong picture on a shopping row is the app being confidently wrong about
    // the household's own errand. The model still draws, in `steps` and
    // `recipe`, where a miss is decoration that missed rather than a label that
    // lies. A Lebensmittel article never had one: it has a photograph.
    return [{ name, quantity, unit }];
  });
  // Absent for every goal that is not cooking, and an empty string is the same
  // as absent — the card draws nothing rather than an empty disclosure.
  const recipe = text(o.recipe, 4000) || null;
  // A step is a titled block now — "## Wände reinigen" and a sentence under it
  // — so it carries a newline and needs the room for one. The cap is on the
  // whole block rather than on the sentence.
  //
  // **A backslash and an "n", not a newline.** The prompt shows the wanted
  // shape as a line of JSON, escapes and all, and the model copies it a little
  // too faithfully: `"## Wände reinigen\\nWische…"` arrives as one line with two
  // literal characters in the middle of it, which the heading rule then reads
  // as part of the heading. Undone here rather than in the prompt, because the
  // example is what made the model stop splitting a block in half and it is
  // worth keeping. No household step contains a literal `\n`.
  const entries = (Array.isArray(o.steps) ? o.steps : [])
    .map((s) => text(s, 600).replace(/\\r\\n|\\n/g, "\n"))
    .filter(Boolean);
  // **The model splits a block across two entries about half the time**, asked
  // for it or not: `["## Preparar o ambiente", "Retire os móveis…"]` rather
  // than one string with a newline in it. Drawn, both look the same; *counted*,
  // they do not, and the cap below would have taken a plan of seven stages and
  // cut it after the fourth title with its sentences missing. So a line that is
  // not a title joins the title above it, and the cap counts stages.
  //
  // A step from before 2026-09-16 is a bare sentence with no title anywhere —
  // those stay one block each, which is why this only ever appends to a block
  // that opened with a heading.
  const steps: string[] = [];
  for (const entry of entries) {
    const last = steps.length - 1;
    if (!entry.startsWith("#") && last >= 0 && steps[last].startsWith("#")) {
      steps[last] += `\n${entry}`;
    } else {
      steps.push(entry);
    }
  }
  // The opening "# " line names the whole method and is not a stage, so it is
  // held out of the cap — counted in, a plan would lose its last stage to its
  // own heading. A model that skipped the title simply has none: the label on
  // the disclosure ("So geht's") still says what the block is, and inventing
  // one here would be us writing the household's heading for it.
  const head = steps.length > 0 && /^#(?!#)/.test(steps[0]) ? steps.slice(0, 1) : [];
  return {
    title: text(o.title, 120),
    kind,
    // **Five when there is a recipe, eight when there is not** — cut here as
    // well as asked for in the prompt, the same belt-and-braces as `UNITS`.
    // The model obeys "a short overview" for most dishes and then returns
    // twelve steps for a paella, which is the whole method written twice: once
    // on the card and once again inside the disclosure under it. The numbers
    // came down with the titles: a titled block is three lines on a phone, so
    // twelve of them is a page nobody folds open twice.
    steps: [...head, ...steps.slice(head.length, head.length + (recipe ? 5 : 8))],
    recipe,
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
  "recipe": string | null,
  "items": [{ "name": string, "quantity": string | null, "unit": string | null }]
}

title: what the list should be called, short, in the user's own words where possible.

kind: where the articles are bought. "grocery" ONLY when they are food, drink or the everyday goods beside them in a supermarket. "other" for everything else — a hardware or DIY store, a garden centre, a chemist, a pharmacy, a stationer, a toy shop. Paint, brushes, tools, screws, timber, plants, craft materials, party decorations and school supplies are all "other", even when a large supermarket happens to stock some of them.

steps: how to actually do it, in order. An array of strings that together make one small document. The first string is the title of the whole method; every string after it is one whole stage — its "## " heading, a newline, then one or two sentences in the same string. Exactly like this:

"steps": [
  "# 🏠 Wohnzimmer streichen",
  "## Wände reinigen\\nWische Wände und Decken mit einem feuchten Tuch ab und lass sie vollständig trocknen.",
  "## Kanten abkleben\\nKlebe Sockelleisten, Türrahmen und Schalter sorgfältig mit Malerband ab.",
  "## Erster Anstrich\\nStreiche zuerst die Decke, dann die Wände, immer von oben nach unten. Warte **4 Stunden** bis zum zweiten Anstrich."
]

- At most 8 stages after the title.
- **The first stage is already the work.** Never write a stage about buying, fetching, collecting or preparing the articles — "Materialien besorgen", "Zutaten vorbereiten", "Einkaufen gehen". The list of what to buy is printed right beside these stages, so such a stage tells the reader to read the other half of the answer.
- **Never split a heading and its sentences into two strings**, and never put two stages into one string.
- **There is exactly ONE emoji in the whole answer: the one on the "# " line.** No emoji on a stage heading, none inside a sentence, none on an article, none anywhere else. One picture over the whole plan is right; a picture on every stage is five guesses about somebody else's job, and they are wrong more often than they are right.
- The "# " title is two to five words naming the goal as a whole — "Wohnzimmer streichen", "Regal fürs Kinderzimmer bauen". Its emoji pictures that goal.
- A stage heading is two to four words naming that stage — "Wände reinigen", "Kanten abkleben" — never a whole sentence and never the same words as another stage.
- The sentences are plain: no bullets, no numbering, no headings of your own beyond the "## " line, and at most one "**...**" for a temperature, a time or a measurement that must not be missed.
- Put recipe measures in these sentences ("2 EL Butter"), never in the items.

Return an empty array when the goal is only about shopping and there is nothing to do. When you also write a "recipe", keep to four or five stages as an overview — the detail belongs there, not here, and the two must not repeat each other.

recipe: the full method, and ONLY when the goal is a dish to cook or to bake. Null for everything else — a hardware run, a party, a trip, a week's shopping.
- Lay it out like a page in a cookbook: open with a "# " line naming the dish, then a "## " heading for the ingredients, with the exact quantities for the number of people asked for, then a "## " heading for the method with the working steps in order. Write every heading in the answer's language.
- **Exactly ONE emoji, at the start of the "# " line**, picturing the dish — like "# 🍝 Lasagne al forno". None on the "## " headings, none on an ingredient line, none inside a working step, none in the middle of a sentence. A list of ingredients each wearing a picture is a list nobody can read down.
- Give oven temperatures, times, tin and pan sizes, and say what to do while something else is cooking.
- Say how to tell it is ready by looking at it, not only by the clock.
- Use ONLY this markup, and nothing else in it is markdown: "# " on the first line for the dish, "## " at the start of a line for a heading, "- " for a listed ingredient, "1. " for a numbered working step, "**...**" around what must not be missed — a temperature, a time, a tin size. One blank line between blocks.
- No tables, no links, no images, no code, no block quotes, no nested lists, no second "# " line, no bold on a whole line or a whole paragraph.

items: what to BUY. This is the important part.
- Shop quantities, never recipe measures: one pack of butter, not two tablespoons.
- Name each article the way a supermarket or a hardware store labels it: one head noun, no brand names, no descriptions. "Hähnchenbrustfilet", not "boneless skinless chicken breast, about 600g".
- Leave out what every kitchen already has (water, salt, pepper) unless the goal is clearly about stocking up.
- quantity is the number only, as text: "500", "2". Null when it is simply one.
- unit is one of exactly: "${units}". Use null for single items. Anything you cannot express with those, put into quantity as text.
- No emoji and no icon on an article, ever — not in the name, not beside it. The one picture in the answer is on the "# " title of "steps" or "recipe". An article is a word on a shopping list.
- Between 3 and 25 articles.

Never invent a link, a price, a shop or a brand. If the goal is unclear, make the most ordinary assumption a parent would make and answer anyway.`;
}
