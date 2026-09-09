/// Envelope encryption for the credentials in calendar_connection_secrets.
///
/// Those columns are already unreachable from `authenticated` — no policy, every
/// privilege revoked. This is the second barrier: what is stored is ciphertext,
/// so a database dump, a leaked service_role key or a mis-scoped backup still
/// yields nothing usable. The key lives in CALENDAR_SECRET_KEY, a function
/// secret, and never touches the database.
///
/// Format: "v1.<iv>.<ciphertext>", both parts base64url. AES-256-GCM, a fresh
/// 12-byte IV per value — so encrypting the same password twice produces two
/// different envelopes, and the tag makes tampering detectable.
///
/// **Rotation.** Sealing always uses CALENDAR_SECRET_KEY. Opening tries that key
/// first and then each key in CALENDAR_SECRET_KEY_RETIRED — a comma-separated
/// list of previously active keys. So replacing a key is a deploy rather than a
/// migration, and nothing has to be re-encrypted in a batch: move the outgoing
/// key into the retired list, put the new one in CALENDAR_SECRET_KEY, and every
/// stored credential keeps opening while new writes seal under the new key. A
/// retired key can be dropped once every connection sealed under it has been
/// written again; anything still on it then degrades to `reconnect_required`,
/// which is the state [open] returning null already models.
///
/// Trial decryption is sound here rather than merely convenient: GCM
/// authenticates, so a wrong key fails the tag check instead of returning
/// plausible-looking garbage. There is no oracle in trying the next one.
///
/// The envelope deliberately does **not** name which key sealed it. Storing a
/// key id next to the ciphertext would tell an attacker holding a database dump
/// which of several stolen keys to try, and buys nothing: with at most a handful
/// of keys, trying them all costs microseconds.

const VERSION = "v1";

let cachedKeys: CryptoKey[] | null = null;

/// Every key we may open with, active first. The raw material is 32 bytes,
/// base64 (`openssl rand -base64 32`).
async function keys(): Promise<CryptoKey[]> {
  if (cachedKeys) return cachedKeys;

  const active = Deno.env.get("CALENDAR_SECRET_KEY");
  if (!active) throw new Error("CALENDAR_SECRET_KEY is not configured");

  // An empty entry is what a trailing comma or an unset-but-present variable
  // looks like, and it must not become a "key" that throws on every open.
  const retired = (Deno.env.get("CALENDAR_SECRET_KEY_RETIRED") ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);

  // Built locally and published to `cachedKeys` only once complete. Assigning
  // the array first and pushing into it would let a second caller arriving
  // during one of the awaits below see a non-null but half-filled cache — and
  // an empty one is truthy, so `seal` would index `[0]` on nothing and every
  // `open` would report a credential we can hold perfectly well.
  const imported: CryptoKey[] = [];

  for (const [index, raw] of [active, ...retired].entries()) {
    const which = index === 0 ? "CALENDAR_SECRET_KEY" : `CALENDAR_SECRET_KEY_RETIRED[${index - 1}]`;

    // Typed `Uint8Array<ArrayBuffer>` rather than the wider `Uint8Array`: the
    // latter is `Uint8Array<ArrayBufferLike>`, which TypeScript refuses as a
    // BufferSource because it could in principle be backed by a
    // SharedArrayBuffer. Same reason `unb64url` is annotated that way.
    let bytes: Uint8Array<ArrayBuffer>;
    try {
      bytes = Uint8Array.from(atob(raw), (c) => c.charCodeAt(0));
    } catch {
      throw new Error(`${which} is not valid base64`);
    }
    if (bytes.length !== 32) throw new Error(`${which} must be 32 bytes of base64`);

    imported.push(
      await crypto.subtle.importKey("raw", bytes, "AES-GCM", false, ["encrypt", "decrypt"]),
    );
  }

  cachedKeys = imported;
  return cachedKeys;
}

/// Always seals under the active key — the first one [keys] returns.
export async function seal(plaintext: string): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = new Uint8Array(
    await crypto.subtle.encrypt(
      { name: "AES-GCM", iv },
      (await keys())[0],
      new TextEncoder().encode(plaintext),
    ),
  );
  return `${VERSION}.${b64url(iv)}.${b64url(ct)}`;
}

/// Returns null for anything that is not a well-formed envelope we can open with
/// any key we still hold — a value sealed under a key that has been dropped from
/// the retired list, a truncated column, a tampered row. Every caller treats null
/// the same way it treats a missing credential, which is what turns a retired key
/// into a reconnect prompt instead of a crash.
export async function open(envelope: string | null | undefined): Promise<string | null> {
  if (!envelope) return null;

  const parts = envelope.split(".");
  if (parts.length !== 3 || parts[0] !== VERSION) return null;

  const iv = unb64url(parts[1]);
  const ct = unb64url(parts[2]);

  for (const key of await keys()) {
    try {
      const plain = await crypto.subtle.decrypt({ name: "AES-GCM", iv }, key, ct);
      return new TextDecoder().decode(plain);
    } catch {
      // Wrong key: GCM's tag check rejected it. Try the next one.
    }
  }
  return null;
}

function b64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

/// Returns the bytes in a plain ArrayBuffer rather than the default
/// Uint8Array<ArrayBufferLike>, which TypeScript will not accept as a
/// BufferSource because it could in principle be backed by a SharedArrayBuffer.
function unb64url(s: string): Uint8Array<ArrayBuffer> {
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/");
  const raw = atob(b64);
  const out = new Uint8Array(new ArrayBuffer(raw.length));
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out;
}
