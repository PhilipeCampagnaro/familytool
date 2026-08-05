/// OAuth connect, callback and disconnect for Google and Outlook.
///
/// Three entry points on one function, because the middle one is not ours to
/// choose: the provider redirects the browser back to a fixed URI, so the
/// callback has to live at a URL we registered up front.
///
///   POST ?action=start       { provider }        -> { url }
///   GET  <redirect from provider, ?code&?state>  -> 302 back into the app
///   POST ?action=calendars   { connection_id }   -> { calendars: [...] }
///   POST ?action=disconnect  { connection_id }   -> { ok: true }
///
/// **This function must be deployed with `verify_jwt = false`** — the provider's
/// redirect carries no Authorization header and the gateway would reject it
/// before we ever see it. Everything except the callback therefore verifies the
/// caller itself, via callerId(), which validates the token against the auth
/// server rather than merely decoding it.
///
/// The callback is the interesting one. It has no session, so it has to be told
/// which household to attach the account to — and if that were a plain query
/// parameter, anyone could hand a connection to any family. Instead `state` is
/// an AES-GCM envelope sealed with CALENDAR_SECRET_KEY at start time: the
/// provider echoes it back verbatim, we open it, and a value we did not mint (or
/// one older than ten minutes) simply does not open. That is CSRF protection and
/// household binding in the same field.
///
/// Function secrets:
///   GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET
///   MICROSOFT_CLIENT_ID, MICROSOFT_CLIENT_SECRET
///   CALENDAR_SECRET_KEY        32 bytes, base64
///   CALENDAR_OAUTH_REDIRECT    this function's public URL, registered verbatim
///                              as an authorized redirect URI at both providers
///   APORAH_APP_REDIRECT        deep link the popup lands on, e.g.
///                              aporah://kalender/verbunden

import { callerId, corsHeaders, fail, json, serviceClient } from "../_shared/http.ts";
import { open, seal } from "../_shared/secrets.ts";
import { fetchWithTimeout } from "../_shared/net.ts";
import {
  accountEmail,
  membershipOf,
  oauthConfig,
  type Provider,
  storeTokens,
} from "../_shared/calendar.ts";
import { type Connection, listRemoteCalendars } from "../_shared/providers.ts";

const OAUTH_PROVIDERS: Provider[] = ["google", "outlook"];
const STATE_TTL_MS = 10 * 60 * 1000;

interface OAuthState {
  provider: Provider;
  familyId: string;
  userId: string;
  exp: number;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const url = new URL(req.url);
  const action = url.searchParams.get("action");

  // The provider's redirect is the only GET this function answers.
  if (url.searchParams.has("code") || url.searchParams.has("error")) {
    return await handleCallback(url);
  }

  const uid = await callerId(req);
  if (!uid) return fail("Nicht angemeldet.", 401);

  if (action === "start") return await handleStart(req, uid);
  if (action === "calendars") return await handleCalendars(req, uid);
  if (action === "disconnect") return await handleDisconnect(req, uid);

  return fail("Unbekannte Aktion.");
});

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------

async function handleStart(req: Request, uid: string): Promise<Response> {
  let body: { provider?: string };
  try {
    body = await req.json();
  } catch {
    return fail("Ungültige Anfrage.");
  }

  const provider = body.provider as Provider;
  if (!OAUTH_PROVIDERS.includes(provider)) return fail("Unbekannter Anbieter.");

  const cfg = oauthConfig(provider);
  const redirectUri = Deno.env.get("CALENDAR_OAUTH_REDIRECT");
  if (!cfg.clientId || !cfg.clientSecret || !redirectUri) {
    return fail(`${cfg.label} ist noch nicht eingerichtet.`, 503);
  }

  const db = serviceClient();
  const membership = await membershipOf(db, uid);
  if (!membership) return fail("Kein Haushalt gefunden.", 403);
  if (membership.role === "kid") {
    return fail("Kinder können keine Kalender verbinden.", 403);
  }

  const state: OAuthState = {
    provider,
    familyId: membership.familyId,
    userId: uid,
    exp: Date.now() + STATE_TTL_MS,
  };

  // A misconfigured CALENDAR_SECRET_KEY makes seal() throw, and an uncaught
  // throw here reaches the app as a bare 500 with no JSON body — which the
  // repository can only render as "Das hat gerade nicht geklappt.". Say what
  // actually happened instead.
  let sealedState: string;
  try {
    sealedState = await seal(JSON.stringify(state));
  } catch (e) {
    console.error("oauth state seal failed", (e as Error).message);
    return fail("Die Verbindung konnte nicht gestartet werden.", 500);
  }

  const authUrl = new URL(cfg.authUrl);
  authUrl.searchParams.set("client_id", cfg.clientId);
  authUrl.searchParams.set("redirect_uri", redirectUri);
  authUrl.searchParams.set("response_type", "code");
  authUrl.searchParams.set("scope", cfg.scope);
  authUrl.searchParams.set("state", sealedState);

  if (provider === "google") {
    // Without both of these Google returns an access token and no refresh
    // token, and the connection dies an hour later with no way back.
    authUrl.searchParams.set("access_type", "offline");
    authUrl.searchParams.set("prompt", "consent");
  }

  return json({ url: authUrl.toString() });
}

// ---------------------------------------------------------------------------
// Callback
// ---------------------------------------------------------------------------

async function handleCallback(url: URL): Promise<Response> {
  const state = await readState(url.searchParams.get("state"));
  // A state we cannot open is a forged or expired callback. There is nobody to
  // report an error to at this point, so it ends the same way as any failure:
  // back into the app with a status the UI can render.
  if (!state) return backToApp("error");

  if (url.searchParams.has("error")) return backToApp("error");

  const code = url.searchParams.get("code");
  if (!code) return backToApp("error");

  const cfg = oauthConfig(state.provider);
  const redirectUri = Deno.env.get("CALENDAR_OAUTH_REDIRECT") ?? "";
  if (!cfg.clientId || !cfg.clientSecret || !redirectUri) return backToApp("error");

  const tokenRes = await fetchWithTimeout(cfg.tokenUrl, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "authorization_code",
      code,
      client_id: cfg.clientId,
      client_secret: cfg.clientSecret,
      redirect_uri: redirectUri,
    }),
  });

  if (!tokenRes.ok) {
    console.error(`token exchange failed: ${tokenRes.status}`);
    return backToApp("error");
  }

  const tokens = await tokenRes.json();
  const email = tokens.access_token
    ? await accountEmail(state.provider, tokens.access_token)
    : null;

  const db = serviceClient();

  // The membership is re-read rather than trusted from the state: someone can
  // change household in the ten minutes a consent screen is open, and the token
  // must land where they are now, not where they were.
  const membership = await membershipOf(db, state.userId);
  if (!membership || membership.familyId !== state.familyId) return backToApp("error");

  const account = email ?? `${state.provider}:${state.userId}`;
  const label = email ? `${cfg.label} (${email})` : cfg.label;

  // Re-connecting the same account updates it in place — that is what makes
  // "Erneut verbinden" repair an expired token instead of producing a second
  // entry in the provider list.
  const { data: connection, error } = await db
    .from("calendar_connections")
    .upsert({
      family_id: membership.familyId,
      provider: state.provider,
      auth_type: "oauth",
      external_account: account,
      display_name: label,
      is_read_only: false,
      status: "active",
      status_detail: null,
      created_by: state.userId,
    }, { onConflict: "family_id,provider,external_account" })
    .select("id")
    .single();

  if (error || !connection) {
    console.error("connection upsert failed", error?.message);
    return backToApp("error");
  }

  await storeTokens(db, connection.id, tokens);

  return backToApp("ok", state.provider);
}

async function readState(raw: string | null): Promise<OAuthState | null> {
  const plain = await open(raw);
  if (!plain) return null;

  try {
    const state = JSON.parse(plain) as OAuthState;
    if (!state.familyId || !state.userId) return null;
    if (!OAUTH_PROVIDERS.includes(state.provider)) return null;
    if (!state.exp || state.exp < Date.now()) return null;
    return state;
  } catch {
    return null;
  }
}

/// The consent screen runs in a system browser sheet, so the last hop has to
/// leave that sheet. A deep link closes it and hands the result to the app; the
/// HTML fallback covers a desktop browser opened by hand.
function backToApp(status: "ok" | "error", provider?: string): Response {
  const target = Deno.env.get("APORAH_APP_REDIRECT");
  if (target) {
    const location = new URL(target);
    location.searchParams.set("status", status);
    if (provider) location.searchParams.set("provider", provider);
    return new Response(null, { status: 302, headers: { Location: location.toString() } });
  }

  const message = status === "ok"
    ? "Kalender verbunden. Du kannst dieses Fenster schließen."
    : "Die Verbindung hat nicht geklappt. Du kannst dieses Fenster schließen.";

  return new Response(
    `<!doctype html><meta charset="utf-8">` +
      `<body style="font-family:system-ui;text-align:center;padding:48px">` +
      `<p>${message}</p><script>try{window.close()}catch(e){}</script></body>`,
    { headers: { "Content-Type": "text/html; charset=utf-8" } },
  );
}

// ---------------------------------------------------------------------------
// Calendars
// ---------------------------------------------------------------------------

/// What an already-connected account offers, asked of the provider right now.
///
/// CalDAV answers this on the connect call itself, because the app is the one
/// holding the password. OAuth cannot: the account is created by the browser
/// callback, which has no session to hand anything back through — so the app
/// comes back from the consent screen with a connection and no idea what is in
/// it. This is the round trip that fills the setup sheet's picker.
///
/// Read-only, and it stores nothing: the choice the user then makes is written
/// to `selected_calendars` over PostgREST like any other setting.
async function handleCalendars(req: Request, uid: string): Promise<Response> {
  let body: { connection_id?: string };
  try {
    body = await req.json();
  } catch {
    return fail("Ungültige Anfrage.");
  }

  const connectionId = body.connection_id;
  if (!connectionId) return fail("Keine Verbindung angegeben.");

  const db = serviceClient();
  const membership = await membershipOf(db, uid);
  if (!membership) return fail("Kein Haushalt gefunden.", 403);

  // Service_role bypasses RLS, so this pair of filters is the entire tenant
  // boundary: a connection id from another household resolves to nothing.
  const { data: connection } = await db
    .from("calendar_connections")
    .select(
      "id, family_id, provider, auth_type, external_account, display_name, config, selected_calendars, is_read_only, created_by",
    )
    .eq("id", connectionId)
    .eq("family_id", membership.familyId)
    .maybeSingle();

  if (!connection) return fail("Verbindung nicht gefunden.", 404);

  try {
    const calendars = await listRemoteCalendars(db, connection as unknown as Connection);
    return json({
      calendars: calendars.map((c) => ({
        external_id: c.externalId,
        name: c.name,
        read_only: c.readOnly,
      })),
    });
  } catch (e) {
    // Never the provider's raw error, which can echo a token back.
    console.error(`listing calendars failed for ${connectionId}: ${(e as Error).message}`);
    return fail("Die Kalender konnten nicht geladen werden.", 502);
  }
}

// ---------------------------------------------------------------------------
// Disconnect
// ---------------------------------------------------------------------------

/// Deleting the row is something RLS already allows. This exists for the step
/// RLS cannot do: telling the provider to invalidate the token. Skipping it
/// would leave a live grant on the user's Google account that our UI claims is
/// gone.
async function handleDisconnect(req: Request, uid: string): Promise<Response> {
  let body: { connection_id?: string };
  try {
    body = await req.json();
  } catch {
    return fail("Ungültige Anfrage.");
  }

  const connectionId = body.connection_id;
  if (!connectionId) return fail("Keine Verbindung angegeben.");

  const db = serviceClient();
  const membership = await membershipOf(db, uid);
  if (!membership) return fail("Kein Haushalt gefunden.", 403);

  // Service_role bypasses RLS, so this pair of filters is the entire tenant
  // boundary: a connection id from another household resolves to nothing.
  const { data: connection } = await db
    .from("calendar_connections")
    .select("id, provider, auth_type, created_by")
    .eq("id", connectionId)
    .eq("family_id", membership.familyId)
    .maybeSingle();

  if (!connection) return fail("Verbindung nicht gefunden.", 404);
  if (connection.created_by !== uid && membership.role !== "admin") {
    return fail("Nur wer die Verbindung angelegt hat, kann sie trennen.", 403);
  }

  // Only an OAuth connection has anything to revoke. oauthConfig() answers with
  // the Google configuration for any provider it does not recognise, so asking
  // it about a CalDAV or public-feed connection would report a revocation that
  // never happened.
  const oauth = connection.auth_type === "oauth";
  const cfg = oauthConfig(connection.provider as Provider);
  if (oauth && cfg.revokeUrl) {
    const { data: secrets } = await db
      .from("calendar_connection_secrets")
      .select("refresh_token, access_token")
      .eq("connection_id", connectionId)
      .maybeSingle();

    const token = await open(secrets?.refresh_token) ?? await open(secrets?.access_token);
    if (token) {
      try {
        await fetchWithTimeout(cfg.revokeUrl, {
          method: "POST",
          headers: { "Content-Type": "application/x-www-form-urlencoded" },
          body: new URLSearchParams({ token }),
        });
      } catch {
        // Best effort. A provider that will not take the revoke must not stop us
        // deleting our copy — that is the half we are responsible for.
      }
    }
  }

  // Cascades the secrets row, every calendar the connection produced, and every
  // event in them.
  await db.from("calendar_connections").delete().eq("id", connectionId);

  return json({ ok: true, revoked: oauth && cfg.revokeUrl !== null });
}
