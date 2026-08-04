/// Outbound HTTP: timeouts, and the SSRF guard for URLs a user typed.
///
/// Two rules, one place:
///
///   * **Every outbound fetch has a deadline.** Deno's fetch has none, and an
///     Edge Function that reaches a municipal waste server which accepts the
///     connection and then never answers stays open until the platform kills it
///     — burning the whole invocation, and in `calendar-events`, which reads
///     connections one after another, taking every other calendar down with it.
///
///   * **A URL the user typed is re-checked on every hop.** Validating only the
///     address they entered is not enough: `fetch` follows redirects by default,
///     so a host that passes the check and then answers `302 -> http://10.0.0.1`
///     walks straight past it.
///
/// The private-range check resolves DNS rather than pattern-matching the
/// hostname, because the real vector is a public-looking name pointing at a
/// private address, not somebody typing `http://127.0.0.1` into the IServ field.

/// Long enough for a slow school CalDAV server on a bad day, short enough that a
/// hung upstream cannot eat a whole invocation.
export const UPSTREAM_TIMEOUT_MS = 15_000;

/// How many hops an untrusted URL may redirect through. iCloud and DAViCal both
/// redirect once or twice during discovery; ten is far past anything legitimate.
const MAX_REDIRECTS = 5;

// ---------------------------------------------------------------------------
// Private-address detection
// ---------------------------------------------------------------------------

/// Is a resolved IP in a private / loopback / link-local / reserved range?
/// Catches the hostname that RESOLVES to one — a public-looking domain pointing
/// at 169.254.169.254, 127.0.0.1, 10.x, etc.
export function isPrivateIp(ip: string): boolean {
  const s = ip.toLowerCase();
  // IPv4-mapped IPv6 (::ffff:10.0.0.1) — check the embedded v4.
  const mapped = s.match(/^::ffff:(\d+\.\d+\.\d+\.\d+)$/);
  const v4 = mapped ? mapped[1] : (/^\d+\.\d+\.\d+\.\d+$/.test(s) ? s : null);
  if (v4) {
    const [a, b] = v4.split(".").map(Number);
    if (a === 10 || a === 127 || a === 0) return true;
    if (a === 172 && b >= 16 && b <= 31) return true;
    if (a === 192 && b === 168) return true;
    if (a === 169 && b === 254) return true; // link-local (cloud metadata)
    if (a === 100 && b >= 64 && b <= 127) return true; // CGNAT
    if (a >= 224) return true; // multicast / reserved
    return false;
  }
  // IPv6
  if (s === "::1" || s === "::") return true; // loopback / unspecified
  if (s.startsWith("fc") || s.startsWith("fd")) return true; // unique-local fc00::/7
  if (/^fe[89ab]/.test(s)) return true; // link-local fe80::/10
  return false;
}

/// Resolve a hostname and refuse if it points at a private/reserved address.
///
/// Fails OPEN when the resolver itself is unavailable: the literal checks in
/// `assertPublicUrl` already stop the obvious cases, and a resolver hiccup must
/// not break a legitimate connection.
export async function assertPublicHost(hostname: string): Promise<void> {
  let ips: string[] = [];
  try {
    const [a, aaaa] = await Promise.allSettled([
      Deno.resolveDns(hostname, "A"),
      Deno.resolveDns(hostname, "AAAA"),
    ]);
    if (a.status === "fulfilled") ips = ips.concat(a.value);
    if (aaaa.status === "fulfilled") ips = ips.concat(aaaa.value);
  } catch {
    return; // resolver unavailable — don't hard-fail a real connection
  }
  if (ips.some(isPrivateIp)) throw new Error("Diese Adresse ist nicht erreichbar.");
}

/// Literal checks on a URL the user typed, before a socket is ever opened.
/// German, because these messages reach the UI verbatim.
///
/// `assertPublicUrl` is the synchronous half; `fetchUntrusted` adds the DNS
/// resolution, on every hop. Callers that go on to fetch should use the latter
/// and can treat this as the input validator.
export function assertPublicUrl(raw: unknown): URL {
  if (typeof raw !== "string" || !raw.trim()) throw new Error("Ungültige Adresse.");

  let url: URL;
  try {
    url = new URL(raw.trim());
  } catch {
    throw new Error("Ungültige Adresse.");
  }

  if (url.protocol !== "https:") throw new Error("Nur HTTPS-Adressen sind erlaubt.");
  if (url.username || url.password) throw new Error("Ungültige Adresse.");

  const host = url.hostname.toLowerCase().replace(/^\[|\]$/g, "");
  const blockedSuffix = [".local", ".internal", ".localhost"];
  if (host === "localhost" || blockedSuffix.some((s) => host.endsWith(s))) {
    throw new Error("Diese Adresse ist nicht erreichbar.");
  }
  if (host === "::1" || host === "::" || /^(fe80|fc|fd)/.test(host)) {
    throw new Error("Diese Adresse ist nicht erreichbar.");
  }
  if (
    /^\d{1,3}(\.\d{1,3}){3}$/.test(host) &&
    /^(0\.|10\.|127\.|169\.254\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)/.test(host)
  ) {
    throw new Error("Diese Adresse ist nicht erreichbar.");
  }

  return url;
}

// ---------------------------------------------------------------------------
// Fetch
// ---------------------------------------------------------------------------

/// A fetch with a deadline. For upstreams we chose ourselves — Google,
/// Microsoft, Resend, OpenHolidays — where the host needs no checking but the
/// timeout still does.
export function fetchWithTimeout(
  input: string | URL,
  init: RequestInit = {},
  ms = UPSTREAM_TIMEOUT_MS,
): Promise<Response> {
  return fetch(input, { ...init, signal: init.signal ?? AbortSignal.timeout(ms) });
}

/// A fetch to an address the user supplied: the IServ server field, a pasted ICS
/// link, a CalDAV collection URL discovered from one of those.
///
/// Redirects are followed by hand so that every hop is validated, not just the
/// first. `Authorization` is dropped when a redirect crosses to another origin —
/// the same rule the fetch spec applies, restated here because we are the ones
/// following the chain now, and a CalDAV request carries the user's password.
export async function fetchUntrusted(
  input: string | URL,
  init: RequestInit = {},
  ms = UPSTREAM_TIMEOUT_MS,
): Promise<Response> {
  const signal = init.signal ?? AbortSignal.timeout(ms);
  let url = new URL(typeof input === "string" ? input : input.href);
  let headers = new Headers(init.headers);
  const origin = url.origin;

  for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
    await assertPublicHost(url.hostname);

    const res = await fetch(url, {
      ...init,
      headers,
      signal,
      redirect: "manual",
    });

    const location = res.headers.get("location");
    if (!isRedirect(res.status) || !location) return res;

    const next = new URL(location, url);
    if (next.protocol !== "https:" && next.protocol !== "http:") {
      throw new Error("Diese Adresse ist nicht erreichbar.");
    }
    // Cross-origin hop: never carry the credential onward.
    if (next.origin !== origin) {
      headers = new Headers(headers);
      headers.delete("authorization");
    }
    // Drain the redirect body so the connection can be reused.
    await res.body?.cancel();
    url = next;
  }

  throw new Error("Diese Adresse ist nicht erreichbar.");
}

function isRedirect(status: number): boolean {
  return status === 301 || status === 302 || status === 303 ||
    status === 307 || status === 308;
}
