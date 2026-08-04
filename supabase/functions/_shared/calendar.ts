/// Shared calendar-connection plumbing: provider configuration, the household
/// lookup every calendar function starts with, OAuth token refresh, and the one
/// normalised event shape all four transports converge on.

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { open, seal } from "./secrets.ts";
import { fetchWithTimeout } from "./net.ts";

/// The provider vocabulary is shared verbatim with calendars.provider and
/// calendar_connections.provider. There is no second spelling anywhere — the
/// Microsoft endpoints below are reached under the name 'outlook'.
///
/// Only the four **personal** accounts. Ferien and Abfall used to be listed here
/// as connections too; they are public feeds shared by every household now and
/// live in `feeds.ts`, keyed by Bundesland or address rather than by family.
export type Provider = "google" | "outlook" | "icloud" | "iserv";

export interface OAuthConfig {
  label: string;
  authUrl: string;
  tokenUrl: string;
  revokeUrl: string | null;
  /// Deliberately minimal. Every extra scope is a permission the user has to
  /// read on the consent screen and a bigger blast radius if the token leaks.
  scope: string;
  clientId: string;
  clientSecret: string;
}

export function oauthConfig(provider: Provider): OAuthConfig {
  if (provider === "outlook") {
    return {
      label: "Outlook",
      authUrl: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
      tokenUrl: "https://login.microsoftonline.com/common/oauth2/v2.0/token",
      // Microsoft has no token-revocation endpoint. Disconnecting removes our
      // copy of the credential; the user revokes the app itself at
      // https://myaccount.microsoft.com/privacy. Say so in the UI.
      revokeUrl: null,
      scope: [
        "offline_access", // without this Microsoft returns no refresh token
        "openid",
        "email",
        "Calendars.ReadWrite",
      ].join(" "),
      clientId: Deno.env.get("MICROSOFT_CLIENT_ID") ?? "",
      clientSecret: Deno.env.get("MICROSOFT_CLIENT_SECRET") ?? "",
    };
  }

  return {
    label: "Google Kalender",
    authUrl: "https://accounts.google.com/o/oauth2/v2/auth",
    tokenUrl: "https://oauth2.googleapis.com/token",
    revokeUrl: "https://oauth2.googleapis.com/revoke",
    scope: [
      // Read and write events. Does NOT allow listing the account's calendars.
      "https://www.googleapis.com/auth/calendar.events",
      // Needed for calendarList.list — the sub-calendar checklist. The old web
      // app shipped without it, discovered every account fell back to the
      // primary calendar only, and had to force everyone to reconsent.
      "https://www.googleapis.com/auth/calendar.calendarlist.readonly",
      // The account label shown in the UI. Nothing else reads the profile.
      "https://www.googleapis.com/auth/userinfo.email",
      "openid",
    ].join(" "),
    clientId: Deno.env.get("GOOGLE_CLIENT_ID") ?? "",
    clientSecret: Deno.env.get("GOOGLE_CLIENT_SECRET") ?? "",
  };
}

/// The one shape every transport normalises to before anything is written to
/// public.events. Times are ISO-8601 in UTC; all-day events keep an exclusive
/// end, the way iCalendar and Google both express them.
export interface SyncedEvent {
  uid: string;
  title: string;
  notes: string | null;
  location: string | null;
  startsAt: string;
  endsAt: string;
  allDay: boolean;
  href?: string | null;
  etag?: string | null;
}

export interface RemoteCalendar {
  /// Google calendarId, Graph calendar id, or CalDAV collection URL.
  externalId: string;
  name: string;
  readOnly: boolean;
}

// ---------------------------------------------------------------------------
// Household lookup
// ---------------------------------------------------------------------------

export interface Membership {
  familyId: string;
  role: "admin" | "member" | "kid";
}

/// Every calendar function runs with service_role and therefore bypasses RLS.
/// This is the only tenant boundary those functions have: resolve the caller's
/// household once, then scope every single query by it. Forget it in one place
/// and a connection id from another family becomes readable.
export async function membershipOf(
  db: SupabaseClient,
  uid: string,
): Promise<Membership | null> {
  const { data } = await db
    .from("family_members")
    .select("family_id, role")
    .eq("user_id", uid)
    .maybeSingle();

  return data ? { familyId: data.family_id, role: data.role } : null;
}

// ---------------------------------------------------------------------------
// Tokens
// ---------------------------------------------------------------------------

/// Marks a connection as needing user action. The Flutter side turns
/// `reconnect_required` into the "Erneut verbinden" state on the provider detail
/// screen; `error` into a retry hint. Nothing else may write these columns —
/// they are revoked from `authenticated`.
export async function setStatus(
  db: SupabaseClient,
  connectionId: string,
  status: "active" | "reconnect_required" | "error",
  detail: string | null = null,
): Promise<void> {
  await db
    .from("calendar_connections")
    .update({ status, status_detail: detail })
    .eq("id", connectionId);
}

/// Stores a token response. Google only ever returns a refresh token on the
/// FIRST consent (and on a forced re-consent), so an absent refresh_token means
/// "keep the one you have" — overwriting it with null is how the old web app
/// silently bricked reconnected accounts.
export async function storeTokens(
  db: SupabaseClient,
  connectionId: string,
  tokens: { access_token?: string; refresh_token?: string; expires_in?: number },
): Promise<void> {
  const patch: Record<string, unknown> = {
    connection_id: connectionId,
    token_expires_at: new Date(Date.now() + (tokens.expires_in ?? 3600) * 1000).toISOString(),
    updated_at: new Date().toISOString(),
  };

  if (tokens.access_token) patch.access_token = await seal(tokens.access_token);
  if (tokens.refresh_token) patch.refresh_token = await seal(tokens.refresh_token);

  await db
    .from("calendar_connection_secrets")
    .upsert(patch, { onConflict: "connection_id" });
}

/// A usable access token for an OAuth connection, refreshed when it is within a
/// minute of expiry. Returns null when the refresh token is gone or rejected —
/// the caller's cue to flip the connection to `reconnect_required` rather than
/// to retry.
export async function freshAccessToken(
  db: SupabaseClient,
  connectionId: string,
  provider: Provider,
): Promise<string | null> {
  const { data: row } = await db
    .from("calendar_connection_secrets")
    .select("access_token, refresh_token, token_expires_at")
    .eq("connection_id", connectionId)
    .maybeSingle();

  if (!row) return null;

  const expiresSoon = !row.token_expires_at ||
    new Date(row.token_expires_at).getTime() - Date.now() < 60_000;

  if (!expiresSoon) {
    const token = await open(row.access_token);
    if (token) return token;
  }

  const refresh = await open(row.refresh_token);
  if (!refresh) return null;

  const cfg = oauthConfig(provider);
  if (!cfg.clientId || !cfg.clientSecret) return null;

  const res = await fetchWithTimeout(cfg.tokenUrl, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "refresh_token",
      refresh_token: refresh,
      client_id: cfg.clientId,
      client_secret: cfg.clientSecret,
      // Microsoft wants the scope repeated on refresh; Google rejects nothing
      // for having it, but we only send it where it is required.
      ...(provider === "outlook" ? { scope: cfg.scope } : {}),
    }),
  });

  if (!res.ok) {
    // Never log the body — a failed refresh response can echo the token back.
    console.error(`token refresh failed for ${connectionId}: ${res.status}`);
    return null;
  }

  const tokens = await res.json();
  await storeTokens(db, connectionId, tokens);
  return tokens.access_token ?? null;
}

/// The account label shown in the UI, and the `external_account` that dedups a
/// re-connect. Non-fatal: a connection without an e-mail still works, it just
/// reads "Google Kalender" instead of "Google (lea@example.com)".
export async function accountEmail(
  provider: Provider,
  accessToken: string,
): Promise<string | null> {
  const url = provider === "outlook"
    ? "https://graph.microsoft.com/v1.0/me"
    : "https://www.googleapis.com/oauth2/v2/userinfo";

  try {
    const res = await fetchWithTimeout(url, {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    if (!res.ok) return null;
    const body = await res.json();
    return body.email ?? body.mail ?? body.userPrincipalName ?? null;
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Misc
// ---------------------------------------------------------------------------

/// The window every read covers: the start of last year to the end of next year.
/// Wide enough for the Kalender screen's month paging and for Ferien, narrow
/// enough that a full reconcile stays one page per provider for most accounts.
export function syncWindow(): { from: Date; to: Date } {
  const year = new Date().getUTCFullYear();
  return {
    from: new Date(Date.UTC(year - 1, 0, 1)),
    to: new Date(Date.UTC(year + 2, 0, 1)),
  };
}

/// Re-exported so the calendar functions keep one import. The guard itself lives
/// in net.ts next to `fetchUntrusted`, which re-runs the same check on every
/// redirect hop — validating only the address the user typed is not enough when
/// the server on the other end can answer with a 302.
export { assertPublicUrl } from "./net.ts";
