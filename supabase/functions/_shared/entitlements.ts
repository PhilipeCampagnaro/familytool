/// The server's half of the free/Plus line.
///
/// **A gate that only exists in Dart is a gate a patched build walks through.**
/// Most of the limits in `lib/models/entitlements.dart` are enforced in the app
/// alone, and that is the right trade for them: a household that hacks its way
/// to a fourth Box costs us nothing and would not have paid anyway. The ones
/// that are re-checked here are the ones with somebody else's bill behind them
/// — a second connected calendar is a provider quota, an Edge Function
/// invocation every refresh and egress on every event it returns.
///
/// This is cheap to enforce because of a decision made long before any of it
/// was about money: **`authenticated` holds no INSERT grant on
/// `calendar_connections`, `public_feeds`, `family_feeds` or `share_links`.**
/// Every one of them is created by a function that first proved the thing
/// works, so there is exactly one place per resource where the count can be
/// checked, and no PostgREST call that goes around it.
///
/// The plan is read from `public.families` with `service_role`, which is the
/// only role that can write it either. Nothing the caller sends is trusted:
/// the household comes from their membership row, never from the request body.

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

/// Mirrors `Plan` in `lib/models/entitlements.dart`.
export type Plan = "free" | "plus";

/// The limits this file enforces. **A subset of the Dart table on purpose** —
/// see the note above about which gates are worth a round trip. The numbers
/// must match `Entitlements._limits`; they are duplicated rather than shared
/// because Deno and Flutter have no common module, and a mismatch shows up as
/// the app offering something the server then refuses, which is a visible bug
/// rather than a silent hole.
const LIMITS: Record<Plan, { calendarAccounts: number | null; shareLinks: number | null }> = {
  free: { calendarAccounts: 1, shareLinks: 2 },
  plus: { calendarAccounts: null, shareLinks: null },
};

/// Apple's billing retry runs up to 16 days and Google's up to 30, and a
/// household in one is still a paying customer whose card merely failed. The
/// webhook is what moves `plan` back to 'free'; this window only catches a
/// notification that never arrived at all. Same number as `_expiryGrace` in
/// `lib/models/entitlements.dart`, and for the same reason.
const EXPIRY_GRACE_MS = 35 * 24 * 60 * 60 * 1000;

export async function planOf(db: SupabaseClient, familyId: string): Promise<Plan> {
  const { data } = await db
    .from("families")
    .select("plan, plan_expires_at")
    .eq("id", familyId)
    .maybeSingle();

  if (data?.plan !== "plus") return "free";

  const until = data.plan_expires_at ? Date.parse(data.plan_expires_at) : null;
  // Null expiry is a manual grant, which never runs out.
  if (until === null || Number.isNaN(until)) return "plus";
  return Date.now() < until + EXPIRY_GRACE_MS ? "plus" : "free";
}

/// Whether this household may connect the account it is trying to connect.
///
/// Counts `calendar_connections` rows — the account, not the calendars inside
/// it. A Google account with a dozen calendars is one connection and one
/// provider quota, which is what the limit is actually about; counting
/// calendars would punish a household for how their school organises its feeds.
///
/// **Ferien and Abfall are not counted and must never be.** They are
/// `family_feeds` subscriptions to a shared `public_feeds` row — a hundred
/// households on one street cause one daily fetch between them — so they cost
/// nothing per family and are part of the free product.
///
/// **A reconnect is always allowed, and getting this wrong would be worse than
/// having no limit at all.** All three connect routes `upsert` on
/// `(family_id, provider, external_account)`, so repairing an expired token
/// writes no new row — but a naive count would see one connection against a
/// limit of one and refuse it. A free household would then be locked out of the
/// single calendar they are entitled to, by the button whose whole job is
/// getting them back in. So the account being connected is named here, and an
/// account that already exists is a repair rather than an addition.
export async function canAddCalendarAccount(
  db: SupabaseClient,
  familyId: string,
  account: { provider: string; externalAccount: string },
): Promise<boolean> {
  const limit = LIMITS[await planOf(db, familyId)].calendarAccounts;
  if (limit === null) return true;

  const { data: existing } = await db
    .from("calendar_connections")
    .select("id")
    .eq("family_id", familyId)
    .eq("provider", account.provider)
    .eq("external_account", account.externalAccount)
    .maybeSingle();
  if (existing) return true;

  const { count } = await db
    .from("calendar_connections")
    .select("id", { count: "exact", head: true })
    .eq("family_id", familyId);

  return (count ?? 0) < limit;
}

/// Whether this household may mint another share link.
///
/// **Live links, not links ever made.** Revoked and expired ones do not count,
/// so a free household that shares a list, revokes it and shares another never
/// meets the limit — which is the behaviour the growth argument for capping
/// rather than closing this depends on. A link is live when it has not been
/// revoked and has not expired; `max_uses` is deliberately not consulted,
/// because a link that has been used up can still be looked at by the guests
/// who already redeemed it.
export async function canAddShareLink(
  db: SupabaseClient,
  familyId: string,
): Promise<boolean> {
  const limit = LIMITS[await planOf(db, familyId)].shareLinks;
  if (limit === null) return true;

  const { count } = await db
    .from("share_links")
    .select("id", { count: "exact", head: true })
    .eq("family_id", familyId)
    .is("revoked_at", null)
    .or(`expires_at.is.null,expires_at.gt.${new Date().toISOString()}`);

  return (count ?? 0) < limit;
}
