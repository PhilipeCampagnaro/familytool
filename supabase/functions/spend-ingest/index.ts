/// Take one wallet transaction from a device and file it as a spend.
///
/// This is the only function in the project besides `calendar-connect` that runs
/// with `verify_jwt = false`, and for a comparable reason: the caller is an App
/// Intent woken by a Personal Automation while the phone is locked, or the
/// Android notification listener the system keeps alive with the app closed. In
/// neither case is there a session, and in neither case can there ever be one.
/// The per-device token from `spend-enroll` is the entire security boundary, and
/// it is checked here, in the function, rather than at the gateway.
///
/// What that buys and what it costs is worth stating plainly. The token
/// identifies a device, not a person at a keyboard, so anything it can do it can
/// do unattended: this endpoint therefore does exactly one thing, writes into
/// exactly one household, and cannot read anything back.
///
/// **Nothing here trusts the payload.** Apple's Transaction trigger is known to
/// hand a custom App Intent an empty merchant or an amount of zero — reported to
/// Apple DTS and unresolved. Android hands its listener a sentence written for a
/// human, which a parser can price correctly and still misname the shop in. A row
/// that arrives either way is still written, and flagged `needs_review`, because
/// the payment really happened and the user cannot see what we silently dropped.

import { corsHeaders, fail, json, serviceClient } from "../_shared/http.ts";
import { hashToken } from "../_shared/tokens.ts";

/// A household that taps its phones more than this in a day is not a household,
/// it is a loop or a stolen token. Both are better stopped than recorded.
/// Counted per family rather than per device, so a second stolen token cannot
/// simply spend a second allowance.
const MAX_WALLET_SPENDS_PER_DAY = 200;

/// **A row only spends the allowance if it claims to be a payment from today.**
/// Counting every wallet row *written* in the last day counted a backfill too: an
/// import of a household's own history from the old app wrote hundreds of rows in
/// one second and then refused every real tap for a day, with an error naming a
/// cause that was not true. What the cap is actually for is a loop or a stolen
/// token, and both of those report payments happening *now* — so the window is
/// applied to `occurred_at` as well, which no import of the past can fill.
const RECENT_SPEND_WINDOW_MS = 86_400_000;

/// An automation that fires twice — a retry, a double tap on the terminal —
/// produces two identical posts seconds apart. Same device, same merchant, same
/// amount inside this window is treated as the same payment. Two genuinely
/// separate payments of the same amount at the same shop within two minutes is
/// possible and would be swallowed; that is the cheaper mistake to make, because
/// a duplicate in a spending total is one nobody can spot afterwards.
const DEDUPE_WINDOW_MS = 120_000;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return fail("Method not allowed.", 405);

  // Read the body once and try both shapes. A Shortcut's "Get Contents of URL"
  // can send JSON, form-encoding or text/plain depending on how it was built,
  // and req.json() throws on anything that is not valid JSON. The App Intent we
  // ship always sends JSON, but this endpoint is reachable by whatever the user
  // wired up and a mis-shaped request should be a clean 400, not a 500 nobody
  // can read from a locked phone.
  const raw = await req.text();
  let body: Record<string, unknown> = {};
  try {
    body = raw ? JSON.parse(raw) : {};
  } catch {
    try {
      body = Object.fromEntries(new URLSearchParams(raw).entries());
    } catch { /* leave empty; the checks below reject it */ }
  }

  const token = typeof body.token === "string" ? body.token.trim() : "";
  if (!token) return fail("Kein Gerätetoken.", 401);

  const db = serviceClient();

  // Resolved by the hash, never the token, and read with service_role rather
  // than through an RPC — see the note on that in the migration.
  const { data: device, error: lookupErr } = await db
    .from("spend_ingest_devices")
    .select("id, family_id, user_id")
    .eq("token_hash", await hashToken(token))
    .is("revoked_at", null)
    .maybeSingle();

  if (lookupErr) {
    console.error("spend-ingest token lookup failed", lookupErr);
    return fail("Ausgabe konnte nicht gespeichert werden.", 500);
  }

  if (!device) {
    // Deliberately says no more than this. The caller is a background
    // automation; a token that no longer resolves is either revoked or never
    // existed, and telling the two apart helps nobody who is allowed to be here.
    console.warn("spend-ingest rejected: token resolved to no device");
    return fail("Gerät nicht aktiviert.", 401);
  }

  const dayAgo = new Date(Date.now() - RECENT_SPEND_WINDOW_MS).toISOString();
  const { count: todayCount } = await db
    .from("spends")
    .select("id", { count: "exact", head: true })
    .eq("family_id", device.family_id)
    .eq("source", "wallet")
    .gte("created_at", dayAgo)
    .gte("occurred_at", dayAgo);

  if ((todayCount ?? 0) >= MAX_WALLET_SPENDS_PER_DAY) {
    console.warn(`spend-ingest rate limit hit for family ${device.family_id}`);
    return fail("Zu viele Ausgaben heute.", 429);
  }

  // --- the payload, none of which is trusted -------------------------------

  const merchantRaw = typeof body.merchant === "string" ? body.merchant.trim() : "";
  const amountCents = readAmountCents(body);
  const occurredAt = readDate(body.occurred_at) ?? new Date();

  // Either failure means Shortcuts handed the intent a hole. The row is kept so
  // the user can see that *something* was paid and fix the rest in two seconds.
  //
  // A caller may **add** doubt and never remove it. Android's listener knows one
  // thing this function cannot see — whether the shop name was read out of the
  // notification or inferred from what was left of it — and says so; `false`
  // from a caller is simply not a value, so nothing on the wire can talk the
  // function out of the checks it makes for itself.
  const callerDoubts = body.needs_review === true;
  const needsReview = callerDoubts ||
    merchantRaw === "" || amountCents === null || amountCents === 0;

  const merchant = merchantRaw === "" ? "Unbekannt" : merchantRaw.slice(0, 200);
  const cents = amountCents ?? 0;

  const since = new Date(occurredAt.getTime() - DEDUPE_WINDOW_MS).toISOString();
  const until = new Date(occurredAt.getTime() + DEDUPE_WINDOW_MS).toISOString();
  const { data: twin } = await db
    .from("spends")
    .select("id")
    .eq("family_id", device.family_id)
    .eq("source", "wallet")
    .eq("merchant", merchant)
    .eq("amount_cents", cents)
    .gte("occurred_at", since)
    .lte("occurred_at", until)
    .limit(1)
    .maybeSingle();

  if (twin) {
    console.log("spend-ingest skipped a duplicate");
    // Answered as success on purpose: from the automation's side the payment is
    // recorded, which is true, and an error would only make it retry.
    return json({ ok: true, duplicate: true, spend_id: twin.id });
  }

  const { data: spend, error } = await db
    .from("spends")
    .insert({
      family_id: device.family_id,
      payer_id: device.user_id,
      merchant,
      amount_cents: cents,
      currency: readCurrency(body.currency),
      occurred_at: occurredAt.toISOString(),
      // category and kind are left out so the `spends_classify` trigger names
      // them — the same rules the app's own manual entry goes through.
      source: "wallet",
      card_label: typeof body.card_label === "string" && body.card_label.trim()
        ? body.card_label.trim().slice(0, 120)
        : null,
      needs_review: needsReview,
    })
    .select("id")
    .single();

  if (error) {
    console.error("spend-ingest insert failed", error);
    return fail("Ausgabe konnte nicht gespeichert werden.", 500);
  }

  // Best-effort: the spend is already filed, and failing the request because a
  // timestamp did not move would make the automation retry a write that worked.
  await db
    .from("spend_ingest_devices")
    .update({ last_used_at: new Date().toISOString() })
    .eq("id", device.id);

  return json({ ok: true, spend_id: spend.id, needs_review: needsReview });
});

/// Cents, from whatever the caller had to hand.
///
/// `amount_cents` is what our own App Intent sends, because an integer cannot
/// pick up a rounding error on the way. Everything else is a fallback for a
/// hand-built Shortcut: a JSON number in euros, or the string a Shortcuts
/// currency variable stringifies to, which in a German locale is "12,34 €" and
/// in an English one "$12.34".
function readAmountCents(body: Record<string, unknown>): number | null {
  if (typeof body.amount_cents === "number" && Number.isFinite(body.amount_cents)) {
    return Math.round(Math.abs(body.amount_cents));
  }

  const amount = body.amount;
  if (typeof amount === "number" && Number.isFinite(amount)) {
    return Math.round(Math.abs(amount) * 100);
  }

  if (typeof amount === "string") {
    // Strip the currency symbol, then decide where the decimal point is by **how
    // many digits follow the last separator**, not by which separator it is.
    //
    // "Whichever of `.` and `,` came last wins" is the obvious rule and it is
    // wrong on the one case that turns up: "1,234" is twelve hundred and
    // thirty-four in English and in German alike, because no currency here has
    // three decimal places. Read as a decimal point it becomes 1.23, and a shop
    // that charged twelve hundred euros lands in the month as one. One or two
    // digits after a separator is a decimal point; anything else is a thousands
    // separator. That settles "12,34", "1.234,56", "1,234.56", "1,234" and
    // "1.234" alike, and it is the same rule `WalletNotifications.kt` applies to
    // the text it reads off an Android notification.
    const cleaned = amount.replace(/[^\d.,]/g, "");
    if (!cleaned) return null;
    const lastSeparator = Math.max(cleaned.lastIndexOf(","), cleaned.lastIndexOf("."));
    const decimals = lastSeparator < 0 ? 0 : cleaned.length - lastSeparator - 1;
    const normalised = lastSeparator >= 0 && decimals >= 1 && decimals <= 2
      ? cleaned.slice(0, lastSeparator).replace(/\D/g, "") + "." +
        cleaned.slice(lastSeparator + 1)
      : cleaned.replace(/\D/g, "");
    const parsed = Number.parseFloat(normalised);
    if (!Number.isFinite(parsed)) return null;
    return Math.round(Math.abs(parsed) * 100);
  }

  return null;
}

function readDate(value: unknown): Date | null {
  if (typeof value !== "string" || !value.trim()) return null;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

/// Three uppercase letters or nothing. The column has the same check, and a
/// rejected insert here would read to the phone as "the payment was not
/// recorded" when the only wrong thing was a currency label.
function readCurrency(value: unknown): string {
  if (typeof value !== "string") return "EUR";
  const code = value.trim().toUpperCase();
  return /^[A-Z]{3}$/.test(code) ? code : "EUR";
}
