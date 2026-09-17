/// Setup-time lookups for the Abfall (German waste-collection) connection, plus
/// the address autocomplete the calendar's Ort field uses.
///
///   POST { action: "search", query, worldwide? }  -> { addresses: GeoAddress[] }
///   POST { action: "resolve", address }           -> { result: ResolveResult }
///   POST { action: "ics-check", url }             -> { ok, count }
///   POST { action: "request", address, state? }   -> { ok, requested: true }
///
/// `request` is the answer to `resolve` coming back unsupported: it files the
/// town in public.abfall_requests so the vendor map grows from what households
/// actually asked for, and `resolve` reports `requested: true` on a later visit
/// so the row says "angefragt" instead of offering the button twice. The row
/// carries the town, postcode and Bundesland — never the street; a vendor is
/// found per municipality and the street is already on families.address.
///
/// Autocomplete is nationwide (Photon/OSM); vendor coverage is only checked on
/// `resolve`. That split is deliberate: matching against the vendors' own street
/// lists while typing made every uncovered address look broken.
///
/// Every vendor request goes through here rather than the app, for two reasons:
/// none of these APIs send CORS headers, and an iOS WebView/app origin is not
/// something a municipal waste server has ever heard of.
///
/// No function secrets. Photon, zippopotam and all seven waste vendors are free
/// and keyless — which is why Abfall and Ferien are the two providers a user can
/// connect before anything has been registered with Google or Microsoft.

import { callerId, corsHeaders, fail, json, serviceClient } from "../_shared/http.ts";
import { geocode, type GeoAddress, readIcsUrl, resolveAddress } from "../_shared/abfall.ts";
import { escapeHtml, sendMail } from "../_shared/mail.ts";

/// The town as the queue keys it: what the geocoder called it, and its postcode
/// when it had one. A postcode alone is not an address and a town alone is a
/// large place, so both are kept and both are compared.
function requestKey(address: GeoAddress): { town: string; postcode: string | null } | null {
  const town = (address.town || "").trim();
  if (!town || town.length > 120) return null;
  const postcode = /^[0-9]{5}$/.test(address.postcode || "") ? address.postcode! : null;
  return { town, postcode };
}

/// The caller's household, or null. Every write here is scoped to it.
async function familyOf(uid: string): Promise<string | null> {
  const { data } = await serviceClient()
    .from("family_members")
    .select("family_id")
    .eq("user_id", uid)
    .maybeSingle();
  return data?.family_id ?? null;
}

/// Whether this household already asked for this town.
async function alreadyRequested(familyId: string, address: GeoAddress): Promise<boolean> {
  const key = requestKey(address);
  if (!key) return false;
  let query = serviceClient()
    .from("abfall_requests")
    .select("id")
    .eq("family_id", familyId)
    .ilike("town", key.town);
  query = key.postcode ? query.eq("postcode", key.postcode) : query.is("postcode", null);
  const { data } = await query.limit(1);
  return (data?.length ?? 0) > 0;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  // Gated on a real, verified session — not because the data is sensitive (it is
  // all public), but because an unauthenticated endpoint that fetches arbitrary
  // upstreams is an open proxy. The old web app decoded the JWT *body* here
  // without checking the signature, which anyone could forge.
  const uid = await callerId(req);
  if (!uid) return fail("Nicht angemeldet.", 401);

  let body: {
    action?: string;
    query?: string;
    address?: GeoAddress;
    url?: string;
    worldwide?: boolean;
    state?: string;
  };
  try {
    body = await req.json();
  } catch {
    return fail("Ungültige Anfrage.");
  }

  try {
    switch (body.action) {
      case "search":
        return json({
          addresses: await geocode(body.query ?? "", { worldwide: !!body.worldwide }),
        });

      case "resolve": {
        if (!body.address) return fail("Es fehlt die Adresse.");
        const result = await resolveAddress(body.address);
        if (result.supported) return json({ result });
        // Only the unsupported answer needs the household: it decides whether
        // the row offers "Anfragen" or already says "angefragt".
        const familyId = await familyOf(uid);
        const requested = familyId ? await alreadyRequested(familyId, body.address) : false;
        return json({ result: { ...result, requested } });
      }

      case "request": {
        if (!body.address) return fail("Es fehlt die Adresse.");
        const key = requestKey(body.address);
        if (!key) return fail("Es fehlt der Ort.");
        const familyId = await familyOf(uid);
        if (!familyId) return fail("Kein Haushalt gefunden.", 403);
        const state = /^[A-Z]{2}$/.test(body.state || "") ? body.state! : null;
        if (!(await alreadyRequested(familyId, body.address))) {
          const { error } = await serviceClient().from("abfall_requests").insert({
            family_id: familyId,
            created_by: uid,
            town: key.town,
            postcode: key.postcode,
            state,
          });
          // The unique index makes a second tap from two screens at once a
          // no-op rather than an error worth showing.
          if (error && error.code !== "23505") throw new Error(error.message);
          // A heads-up for us, when configured; the row is the record. Nothing
          // about the household but the town it lives in goes into the mail.
          const to = Deno.env.get("APORAH_REQUESTS_TO");
          if (to) {
            const where = escapeHtml([key.postcode, key.town].filter(Boolean).join(" "));
            await sendMail(
              to,
              `Abfall-Anfrage: ${[key.postcode, key.town].filter(Boolean).join(" ")}`,
              `<p>Ein Haushalt hat einen Müllabfuhr-Kalender für <b>${where}</b>` +
                `${state ? ` (${state})` : ""} angefragt.</p>` +
                `<p>Offene Anfragen: <code>select * from abfall_requests where status = 'open'</code></p>`,
            ).catch((e) => console.error(`abfall-lookup request mail failed: ${(e as Error).message}`));
          }
        }
        return json({ ok: true, requested: true });
      }

      case "ics-check": {
        if (!body.url) return fail("Es fehlt die Adresse des Kalenders.");
        // A link that parses but yields nothing is the common failure here — an
        // authority's landing page rather than its ICS export. Counting events
        // is the only check that tells those apart.
        const events = await readIcsUrl({ vendor: "ics", url: body.url });
        return json({ ok: events.length > 0, count: events.length });
      }

      default:
        return fail("Unbekannte Aktion.");
    }
  } catch (e) {
    // Vendor errors can echo the requested URL back, so they are logged and not
    // returned. The user gets something they can act on instead.
    console.error(`abfall-lookup ${body.action} failed: ${(e as Error).message}`);
    return fail("Die Adresssuche ist gerade nicht erreichbar.", 502);
  }
});
