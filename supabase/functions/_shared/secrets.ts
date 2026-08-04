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
/// Rotating the key invalidates every stored credential. That degrades to "every
/// connection asks to be reconnected", which is exactly the state the
/// `reconnect_required` status already models.

const VERSION = "v1";

let cachedKey: CryptoKey | null = null;

/// The raw key material is 32 bytes, base64 (`openssl rand -base64 32`).
async function key(): Promise<CryptoKey> {
  if (cachedKey) return cachedKey;

  const raw = Deno.env.get("CALENDAR_SECRET_KEY");
  if (!raw) throw new Error("CALENDAR_SECRET_KEY is not configured");

  const bytes = Uint8Array.from(atob(raw), (c) => c.charCodeAt(0));
  if (bytes.length !== 32) {
    throw new Error("CALENDAR_SECRET_KEY must be 32 bytes of base64");
  }

  cachedKey = await crypto.subtle.importKey("raw", bytes, "AES-GCM", false, [
    "encrypt",
    "decrypt",
  ]);
  return cachedKey;
}

export async function seal(plaintext: string): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = new Uint8Array(
    await crypto.subtle.encrypt(
      { name: "AES-GCM", iv },
      await key(),
      new TextEncoder().encode(plaintext),
    ),
  );
  return `${VERSION}.${b64url(iv)}.${b64url(ct)}`;
}

/// Returns null for anything that is not a well-formed envelope we can open —
/// a value written under a rotated key, a truncated column, a tampered row.
/// Every caller treats null the same way it treats a missing credential, which
/// is what turns key rotation into a reconnect prompt instead of a crash.
export async function open(envelope: string | null | undefined): Promise<string | null> {
  if (!envelope) return null;

  const parts = envelope.split(".");
  if (parts.length !== 3 || parts[0] !== VERSION) return null;

  try {
    const plain = await crypto.subtle.decrypt(
      { name: "AES-GCM", iv: unb64url(parts[1]) },
      await key(),
      unb64url(parts[2]),
    );
    return new TextDecoder().decode(plain);
  } catch {
    return null;
  }
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
