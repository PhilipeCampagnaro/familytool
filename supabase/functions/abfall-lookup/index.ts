/// Setup-time lookups for the Abfall (German waste-collection) connection, plus
/// the address autocomplete the calendar's Ort field uses.
///
///   POST { action: "search", query, worldwide? }  -> { addresses: GeoAddress[] }
///   POST { action: "resolve", address }           -> { result: ResolveResult }
///   POST { action: "ics-check", url }             -> { ok, count }
///
/// Autocomplete is nationwide (Photon/OSM); vendor coverage is only checked on
/// `resolve`. That split is deliberate: matching against the vendors' own street
/// lists while typing made every uncovered address look broken.
///
/// Every vendor request goes through here rather than the app, for two reasons:
/// none of these APIs send CORS headers, and an iOS WebView/app origin is not
/// something a municipal waste server has ever heard of.
///
/// No function secrets. Photon, zippopotam and all six waste vendors are free
/// and keyless — which is why Abfall and Ferien are the two providers a user can
/// connect before anything has been registered with Google or Microsoft.

import { callerId, corsHeaders, fail, json } from "../_shared/http.ts";
import { geocode, type GeoAddress, readIcsUrl, resolveAddress } from "../_shared/abfall.ts";

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
        return json({ result: await resolveAddress(body.address) });
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
