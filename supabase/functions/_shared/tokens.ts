/// Invite and share tokens.
///
/// The raw token is handed to the caller exactly once, at creation, and is
/// never stored. Only its SHA-256 hash reaches the database, so a dump of
/// `family_invites` or `share_links` yields nothing usable.

const TOKEN_BYTES = 32;

/// 32 bytes of CSPRNG entropy, base64url — unguessable, URL-safe, and short
/// enough to paste into a chat message.
export function createToken(): string {
  const bytes = new Uint8Array(TOKEN_BYTES);
  crypto.getRandomValues(bytes);
  return base64UrlEncode(bytes);
}

export async function hashToken(token: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token));
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function base64UrlEncode(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}
