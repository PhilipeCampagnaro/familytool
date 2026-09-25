/// Apple's half of the subscription: checking what the App Store signed, and
/// turning it into `families.plan`.
///
/// **Everything Apple sends is a JWS, and nothing in one is believed until its
/// certificate chain ends at Apple's own root.** A StoreKit 2 transaction, a
/// renewal record and an App Store Server Notification are all ES256-signed
/// with a leaf certificate carried in the header's `x5c`, issued by Apple's
/// Worldwide Developer Relations CA, issued by Apple Root CA – G3. The root is
/// pinned below byte for byte; the header is attacker-controlled, so a chain
/// that merely *claims* to be Apple's proves nothing until it ends there.
///
/// Written against WebCrypto through `@peculiar/x509` rather than Apple's own
/// Node library, which leans on Node's crypto module and online OCSP checks —
/// two things an Edge Function is the wrong place to discover do not work.

import * as x509 from "npm:@peculiar/x509@1";
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

x509.cryptoProvider.set(crypto);

/// The app, as App Store Connect knows it. A transaction for any other bundle
/// is somebody else's receipt.
export const BUNDLE_ID = "com.aporah.aporah";

/// **Must match `plusProductIds` in `lib/services/store_billing.dart`** and
/// the products in App Store Connect, or a real purchase is refused here.
export const PLUS_PRODUCTS = new Set(["com.aporah.plus.monthly", "com.aporah.plus.yearly"]);

/// Apple Root CA – G3, DER, from apple.com/certificateauthority.
/// SHA-256 63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79,
/// valid to 2039-04-30.
const APPLE_ROOT_G3 =
  "MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA==";

/// Marker extensions Apple puts on the two certificates below its root, the
/// same check Apple's own server library makes: the leaf is a receipt-signing
/// certificate, the intermediate is the WWDR CA.
const OID_LEAF = "1.2.840.113635.100.6.11.1";
const OID_INTERMEDIATE = "1.2.840.113635.100.6.2.1";

const rootDer = base64ToBytes(APPLE_ROOT_G3);
const rootCert = new x509.X509Certificate(rootDer);

/// A StoreKit 2 transaction, as far as this app reads one. Dates are Unix
/// milliseconds, as Apple sends them.
export interface AppleTransaction {
  transactionId: string;
  originalTransactionId: string;
  bundleId: string;
  productId: string;
  purchaseDate?: number;
  expiresDate?: number;
  revocationDate?: number;
  appAccountToken?: string;
  environment?: string;
  signedDate?: number;
}

export interface AppleRenewalInfo {
  originalTransactionId?: string;
  autoRenewStatus?: number;
  gracePeriodExpiresDate?: number;
}

export interface AppleNotification {
  notificationType: string;
  subtype?: string;
  notificationUUID?: string;
  signedDate?: number;
  data?: {
    bundleId?: string;
    environment?: string;
    signedTransactionInfo?: string;
    signedRenewalInfo?: string;
  };
}

/// Verifies [jws] against Apple's chain and returns its payload, or throws.
export async function verifyAppleJws<T>(jws: string): Promise<T> {
  const parts = jws.split(".");
  if (parts.length !== 3) throw new Error("not a JWS");
  const [h, p, s] = parts;

  const header = JSON.parse(new TextDecoder().decode(base64UrlToBytes(h))) as { alg?: string; x5c?: string[] };
  if (header.alg !== "ES256") throw new Error("unexpected alg");
  const chain = header.x5c ?? [];
  if (chain.length !== 3) throw new Error("unexpected chain length");

  // The root the JWS carries must *be* the pinned one, not merely look like it.
  if (!bytesEqual(base64ToBytes(chain[2]), rootDer)) throw new Error("untrusted root");

  const payload = JSON.parse(new TextDecoder().decode(base64UrlToBytes(p))) as T & { signedDate?: number };
  // Validity is judged at the moment Apple signed, as Apple's own library
  // does offline: a year-old transaction handed back by a restore was signed
  // by a certificate that was valid then, and the signature still has to
  // verify with it.
  const date = typeof payload.signedDate === "number" ? new Date(payload.signedDate) : new Date();

  const leaf = new x509.X509Certificate(base64ToBytes(chain[0]));
  const intermediate = new x509.X509Certificate(base64ToBytes(chain[1]));
  if (!leaf.getExtension(OID_LEAF)) throw new Error("leaf is not a receipt signer");
  if (!intermediate.getExtension(OID_INTERMEDIATE)) throw new Error("intermediate is not Apple WWDR");
  if (!(await intermediate.verify({ publicKey: rootCert, date }))) throw new Error("intermediate not signed by root");
  if (!(await leaf.verify({ publicKey: intermediate, date }))) throw new Error("leaf not signed by intermediate");

  const key = await crypto.subtle.importKey(
    "spki",
    leaf.publicKey.rawData,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["verify"],
  );
  const ok = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    base64UrlToBytes(s),
    new TextEncoder().encode(`${h}.${p}`),
  );
  if (!ok) throw new Error("bad signature");
  return payload;
}

/// A verified transaction for one of *our* products, or null.
export async function plusTransaction(jws: string): Promise<AppleTransaction | null> {
  try {
    const txn = await verifyAppleJws<AppleTransaction>(jws);
    if (txn.bundleId !== BUNDLE_ID || !PLUS_PRODUCTS.has(txn.productId)) return null;
    if (!txn.originalTransactionId) return null;
    return txn;
  } catch (e) {
    console.warn("apple jws rejected", (e as Error).message);
    return null;
  }
}

/// Whether [txn] entitles its holder right now.
export function isActive(txn: AppleTransaction, now = Date.now()): boolean {
  return !txn.revocationDate && typeof txn.expiresDate === "number" && txn.expiresDate > now;
}

/// The household row as this file reads and writes it.
export interface FamilyPlanRow {
  id: string;
  plan: "free" | "plus";
  plan_source: "app_store" | "play_store" | "manual" | null;
  plan_expires_at: string | null;
  plan_original_txn_id: string | null;
}

export const FAMILY_PLAN_COLUMNS = "id, plan, plan_source, plan_expires_at, plan_original_txn_id";

/// The one write to the subscription columns. `service_role` only — no other
/// role holds an update grant on them (`20260911145010_entitlements.sql`).
export async function writePlan(
  db: SupabaseClient,
  familyId: string,
  plan: "free" | "plus",
  txn: AppleTransaction,
  expiresAt: number | null,
): Promise<{ error: { code?: string; message: string } | null }> {
  const { error } = await db
    .from("families")
    .update({
      plan,
      plan_source: "app_store",
      plan_expires_at: expiresAt ? new Date(expiresAt).toISOString() : null,
      plan_original_txn_id: txn.originalTransactionId,
    })
    .eq("id", familyId);
  return { error };
}

function base64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function base64UrlToBytes(b64url: string): Uint8Array {
  const b64 = b64url.replace(/-/g, "+").replace(/_/g, "/");
  return base64ToBytes(b64 + "=".repeat((4 - (b64.length % 4)) % 4));
}

function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}
