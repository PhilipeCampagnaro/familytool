/// Attach an App Store subscription to the caller's household.
///
/// Called by the app right after a purchase, after "Kauf wiederherstellen",
/// and on every start for any transaction StoreKit still holds unfinished —
/// which makes it the retry for a purchase whose first post never arrived. It
/// is therefore **idempotent**: the same transaction posted twice writes the
/// same row twice.
///
/// **Nothing the caller says is believed but Apple's signature.** The body is a
/// list of StoreKit 2 JWS strings; each is verified against Apple's root in
/// `_shared/app_store.ts`, and the household comes from the caller's membership
/// row, never from the request. Together with `store-webhook` this is the only
/// writer of `families.plan` — no client role holds an update grant on it.
///
/// Errors carry a `code` as well as the usual German `error`, because the app
/// speaks four languages and turns the code into its own sentence.

import { callerId, corsHeaders, json, serviceClient } from "../_shared/http.ts";
import {
  type AppleTransaction,
  FAMILY_PLAN_COLUMNS,
  type FamilyPlanRow,
  isActive,
  plusTransaction,
  writePlan,
} from "../_shared/app_store.ts";

function refuse(code: string, error: string, status: number): Response {
  return json({ code, error }, status);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const uid = await callerId(req);
  if (!uid) return refuse("unauthenticated", "Nicht angemeldet.", 401);

  let body: { source?: string; transactions?: unknown };
  try {
    body = await req.json();
  } catch {
    return refuse("invalid", "Ungültige Anfrage.", 400);
  }
  // Play Billing arrives as a second source; until then this is Apple only.
  if (body.source !== "app_store") return refuse("invalid", "Unbekannter Store.", 400);
  const signed = Array.isArray(body.transactions)
    ? body.transactions.filter((t): t is string => typeof t === "string" && t.length < 20000).slice(0, 20)
    : [];
  if (signed.length === 0) return refuse("invalid", "Keine Transaktion.", 400);

  const db = serviceClient();

  // Any member may carry the purchase in: the store has already charged
  // whoever tapped, and refusing to record a payment that happened is the
  // worst answer there is. The household is theirs, never the body's.
  const { data: membership } = await db
    .from("family_members")
    .select("family_id")
    .eq("user_id", uid)
    .maybeSingle();
  if (!membership) return refuse("no_household", "Kein Haushalt gefunden.", 403);
  const familyId = membership.family_id as string;

  const verified: AppleTransaction[] = [];
  for (const jws of signed) {
    const txn = await plusTransaction(jws);
    if (txn) verified.push(txn);
  }
  if (verified.length === 0) return refuse("invalid", "Der Kauf konnte nicht bestätigt werden.", 400);

  // The one that matters: the latest-running live subscription, else the
  // latest of any — a restore can hand back several renewals of one line.
  const byExpiry = [...verified].sort((a, b) => (b.expiresDate ?? 0) - (a.expiresDate ?? 0));
  const best = byExpiry.find((t) => isActive(t)) ?? byExpiry[0];

  const { data: family, error: readError } = await db
    .from("families")
    .select(FAMILY_PLAN_COLUMNS)
    .eq("id", familyId)
    .single<FamilyPlanRow>();
  if (readError || !family) return refuse("failed", "Haushalt nicht lesbar.", 500);

  const answer = (row: Pick<FamilyPlanRow, "plan" | "plan_expires_at">, extra: Record<string, unknown> = {}) =>
    json({ plan: row.plan, expires_at: row.plan_expires_at, ...extra });

  // **One payment, one household.** The unique index on
  // `plan_original_txn_id` would refuse the write anyway; asking first turns a
  // constraint error into an answer the app can put into words.
  const { data: holder } = await db
    .from("families")
    .select("id")
    .eq("plan_original_txn_id", best.originalTransactionId)
    .neq("id", familyId)
    .maybeSingle();

  if (!isActive(best)) {
    // Nothing live to attach. If it is the household's own subscription that
    // ended or was refunded, say so on the row; otherwise change nothing.
    if (family.plan_source === "app_store" && family.plan_original_txn_id === best.originalTransactionId) {
      await writePlan(db, familyId, "free", best, best.revocationDate ?? best.expiresDate ?? null);
      return answer({ plan: "free", plan_expires_at: null });
    }
    return answer(family);
  }

  if (holder) {
    return refuse("owned_elsewhere", "Dieses Abo gehört schon zu einem anderen Haushalt.", 409);
  }

  // A manual grant is left alone — somebody decided it on purpose, and a
  // purchase on top of it will take over when the grant is removed and the
  // next renewal arrives.
  if (family.plan === "plus" && family.plan_source === "manual") {
    return answer(family, { duplicate: true });
  }

  // **Two members, two subscriptions, one household.** The household keeps the
  // one it already had; the second is reported so the app can point its buyer
  // at the store's own cancel button rather than silently charging twice.
  const current = family.plan_expires_at ? Date.parse(family.plan_expires_at) : 0;
  if (
    family.plan === "plus" &&
    family.plan_original_txn_id &&
    family.plan_original_txn_id !== best.originalTransactionId &&
    current > Date.now()
  ) {
    return answer(family, { duplicate: true });
  }

  const { error } = await writePlan(db, familyId, "plus", best, best.expiresDate ?? null);
  if (error) {
    // 23505: the index caught a race the check above lost.
    if (error.code === "23505") {
      return refuse("owned_elsewhere", "Dieses Abo gehört schon zu einem anderen Haushalt.", 409);
    }
    console.error("store-verify write failed", error);
    return refuse("failed", "Plus konnte nicht freigeschaltet werden.", 500);
  }

  return json({ plan: "plus", expires_at: new Date(best.expiresDate!).toISOString() });
});
