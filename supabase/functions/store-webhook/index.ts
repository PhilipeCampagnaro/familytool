/// App Store Server Notifications V2 — how a household learns, with nobody's
/// phone open, that its subscription renewed, lapsed, or was refunded.
///
/// **The source of truth for the subscription columns once a purchase exists.**
/// `store-verify` attaches a subscription at the moment it is bought; every
/// month after that, this is what keeps `families.plan` honest. Apple posts
/// `{ signedPayload }` with no session and no Authorization header, so the
/// function is pinned to `verify_jwt = false` in `config.toml` and verifies
/// Apple's own signature instead (`_shared/app_store.ts`).
///
/// **It answers 200 to anything it has read, including what it ignores.** A
/// non-2xx makes Apple retry for days; a notification for another product or
/// a household that no longer exists will never become actionable, so
/// retrying it is noise. Only an unverifiable body is refused.
///
/// Play Real-time Developer Notifications will land beside this as a second
/// branch on the body's shape.

import { json, serviceClient } from "../_shared/http.ts";
import {
  type AppleNotification,
  type AppleRenewalInfo,
  type AppleTransaction,
  BUNDLE_ID,
  FAMILY_PLAN_COLUMNS,
  type FamilyPlanRow,
  plusTransaction,
  verifyAppleJws,
  writePlan,
} from "../_shared/app_store.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ ok: true });

  let signedPayload: string | undefined;
  try {
    signedPayload = (await req.json())?.signedPayload;
  } catch {
    return json({ error: "bad body" }, 400);
  }
  if (typeof signedPayload !== "string") return json({ error: "bad body" }, 400);

  let note: AppleNotification;
  try {
    note = await verifyAppleJws<AppleNotification>(signedPayload);
  } catch (e) {
    console.warn("store-webhook: unverifiable notification", (e as Error).message);
    return json({ error: "unverifiable" }, 401);
  }

  const data = note.data;
  if (note.notificationType === "TEST" || !data || data.bundleId !== BUNDLE_ID || !data.signedTransactionInfo) {
    return json({ ok: true });
  }

  const txn = await plusTransaction(data.signedTransactionInfo);
  if (!txn) return json({ ok: true });

  let renewal: AppleRenewalInfo | null = null;
  if (data.signedRenewalInfo) {
    try {
      renewal = await verifyAppleJws<AppleRenewalInfo>(data.signedRenewalInfo);
    } catch {
      renewal = null;
    }
  }

  const db = serviceClient();
  const family = await findHousehold(db, txn);
  if (!family) {
    console.log("store-webhook: no household for", note.notificationType, txn.originalTransactionId);
    return json({ ok: true });
  }

  // A manual grant is somebody's deliberate decision; a store event about a
  // different line of payment does not overrule it.
  if (family.plan_source === "manual") return json({ ok: true });

  const decision = decide(note, txn, renewal);
  if (!decision) return json({ ok: true });

  // **Notifications can arrive out of order.** A late DID_RENEW for last month
  // must not pull the expiry back behind the one this month's already set;
  // the events that end Plus are taken as they come, because they are
  // authoritative whenever they arrive.
  if (decision.plan === "plus" && family.plan_original_txn_id === txn.originalTransactionId) {
    const known = family.plan_expires_at ? Date.parse(family.plan_expires_at) : 0;
    if (decision.expiresAt !== null && decision.expiresAt < known) return json({ ok: true });
  }

  const { error } = await writePlan(db, family.id, decision.plan, txn, decision.expiresAt);
  if (error) {
    console.error("store-webhook write failed", note.notificationType, error);
    // Worth a retry — this one is ours.
    return json({ error: "write failed" }, 500);
  }
  return json({ ok: true });
});

/// The household a notification is about.
///
/// By the stored `originalTransactionId` first — every purchase `store-verify`
/// saw. Failing that, by the `appAccountToken` the app sets to the family's id
/// on every purchase, which is what reaches a household whose own post never
/// arrived. That second route never takes a household already paying through
/// another subscription, or it could re-point a live one.
async function findHousehold(
  db: ReturnType<typeof serviceClient>,
  txn: AppleTransaction,
): Promise<FamilyPlanRow | null> {
  const { data: byTxn } = await db
    .from("families")
    .select(FAMILY_PLAN_COLUMNS)
    .eq("plan_original_txn_id", txn.originalTransactionId)
    .maybeSingle<FamilyPlanRow>();
  if (byTxn) return byTxn;

  const token = txn.appAccountToken;
  if (!token || !/^[0-9a-f-]{36}$/i.test(token)) return null;
  const { data: byToken } = await db
    .from("families")
    .select(FAMILY_PLAN_COLUMNS)
    .eq("id", token.toLowerCase())
    .maybeSingle<FamilyPlanRow>();
  if (!byToken) return null;
  const paying =
    byToken.plan === "plus" &&
    byToken.plan_original_txn_id !== null &&
    (!byToken.plan_expires_at || Date.parse(byToken.plan_expires_at) > Date.now());
  return paying ? null : byToken;
}

/// What a notification means for the household, or null for "nothing".
function decide(
  note: AppleNotification,
  txn: AppleTransaction,
  renewal: AppleRenewalInfo | null,
): { plan: "free" | "plus"; expiresAt: number | null } | null {
  switch (note.notificationType) {
    case "REFUND":
    case "REVOKE":
      // Money back, or Family Sharing withdrawn: Plus ends now.
      return { plan: "free", expiresAt: txn.revocationDate ?? Date.now() };

    case "EXPIRED":
    case "GRACE_PERIOD_EXPIRED":
      return { plan: "free", expiresAt: txn.expiresDate ?? Date.now() };

    case "DID_FAIL_TO_RENEW":
      // With a billing grace period configured Apple names its end; without
      // one the household is in billing retry, and `Entitlements.effectivePlan`
      // keeps it on Plus through the retry window on purpose — so the row
      // keeps `plus` and only the date moves.
      return {
        plan: "plus",
        expiresAt: note.subtype === "GRACE_PERIOD"
          ? renewal?.gracePeriodExpiresDate ?? txn.expiresDate ?? null
          : txn.expiresDate ?? null,
      };

    case "SUBSCRIBED":
    case "DID_RENEW":
    case "OFFER_REDEEMED":
    case "DID_CHANGE_RENEWAL_PREF":
    case "RENEWAL_EXTENDED":
    case "REFUND_REVERSED":
      if (txn.revocationDate || !txn.expiresDate || txn.expiresDate <= Date.now()) return null;
      return { plan: "plus", expiresAt: txn.expiresDate };

    // DID_CHANGE_RENEWAL_STATUS (auto-renew switched off — Plus runs to the
    // end of the period anyway), PRICE_INCREASE, CONSUMPTION_REQUEST and the
    // rest change nothing about what the household has today.
    default:
      return null;
  }
}
