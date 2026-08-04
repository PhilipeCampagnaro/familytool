/// Subscribe the household to a public feed: German school holidays (Ferien) or
/// waste collection (Abfall).
///
///   POST { provider: "ferien", state: "NI" }
///     -> { feed_id, events }
///   POST { provider: "abfall", config: AbfallConfig, label }
///     -> { feed_id, events }
///
/// **Subscribe, not connect.** These feeds are the same for everybody: every
/// household in Niedersachsen gets identical Schulferien, every household on one
/// street gets identical Abfuhrtermine. So the feed is stored once in
/// public.public_feeds under a key derived from the resolved config, and this
/// function either creates it or — far more often, once the app has users —
/// finds the one somebody else already created and adds a row to
/// public.family_feeds.
///
/// A hundred families in Bremen therefore cost one feed row and one daily fetch
/// of the city's waste site, instead of a hundred of each. That is politeness
/// toward a municipal server as much as it is thrift.
///
/// Why a function rather than a client insert: neither table grants insert to
/// `authenticated`. Every calendar in this app is created by a server that first
/// proved the thing answers, and a keyless public feed is no exception. For
/// Abfall that proof is literal — a config resolving to no pickups is rejected
/// rather than stored, because otherwise the address picker would report success
/// for a schedule that silently yields an empty calendar forever.
///
/// No function secrets. OpenHolidays and every waste vendor are free and keyless.

import { callerId, corsHeaders, fail, json, serviceClient } from "../_shared/http.ts";
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { membershipOf } from "../_shared/calendar.ts";
import type { AbfallConfig } from "../_shared/abfall.ts";
import { FEED_COLOR, type FeedKind, feedKeyOf, readFeedEvents } from "../_shared/feeds.ts";

/// The sixteen Bundesländer, as OpenHolidays' ISO subdivision suffixes. An
/// allowlist rather than a regex: `DE-XX` is a well-formed code for a state that
/// does not exist, and OpenHolidays answers that with an empty list, which looks
/// exactly like "no school holidays this year".
const STATES: Record<string, string> = {
  BW: "Baden-Württemberg",
  BY: "Bayern",
  BE: "Berlin",
  BB: "Brandenburg",
  HB: "Bremen",
  HH: "Hamburg",
  HE: "Hessen",
  MV: "Mecklenburg-Vorpommern",
  NI: "Niedersachsen",
  NW: "Nordrhein-Westfalen",
  RP: "Rheinland-Pfalz",
  SL: "Saarland",
  SN: "Sachsen",
  ST: "Sachsen-Anhalt",
  SH: "Schleswig-Holstein",
  TH: "Thüringen",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const uid = await callerId(req);
  if (!uid) return fail("Nicht angemeldet.", 401);

  let body: { provider?: string; state?: string; config?: AbfallConfig; label?: string };
  try {
    body = await req.json();
  } catch {
    return fail("Ungültige Anfrage.");
  }

  const db = serviceClient();
  const membership = await membershipOf(db, uid);
  if (!membership) return fail("Kein Haushalt gefunden.", 403);
  if (membership.role === "kid") return fail("Kinder können keine Kalender verbinden.", 403);

  if (body.provider === "ferien") {
    const code = (body.state ?? "").trim().toUpperCase().replace(/^DE-/, "");
    const name = STATES[code];
    if (!name) return fail("Bitte ein Bundesland auswählen.");

    return await subscribe(db, {
      familyId: membership.familyId,
      uid,
      kind: "ferien",
      config: { state: code },
      name: `Schulferien ${name}`,
    });
  }

  if (body.provider === "abfall") {
    const config = body.config;
    if (!config || typeof config !== "object" || !config.vendor) {
      return fail("Diese Adresse konnte nicht übernommen werden.");
    }

    const label = (body.label ?? "").trim();
    if (!label) return fail("Es fehlt die Adresse.");

    return await subscribe(db, {
      familyId: membership.familyId,
      uid,
      kind: "abfall",
      config: { ...config, label },
      name: `Abfallkalender (${label})`.slice(0, 120),
    });
  }

  return fail("Unbekannter Anbieter.");
});

async function subscribe(
  db: SupabaseClient,
  args: {
    familyId: string;
    uid: string;
    kind: FeedKind;
    config: Record<string, unknown>;
    name: string;
  },
): Promise<Response> {
  const feedKey = await feedKeyOf(args.kind, args.config);

  const { data: existing } = await db
    .from("public_feeds")
    .select("id, events, synced_at")
    .eq("feed_key", feedKey)
    .maybeSingle();

  let feedId = existing?.id as string | undefined;
  let count = Array.isArray(existing?.events) ? existing.events.length : 0;

  // A feed somebody else already created is taken as-is: it was verified when
  // they added it and is refreshed on its own TTL. Re-reading a municipal site
  // just because a second family moved onto the street is the duplication this
  // whole table exists to remove.
  if (!feedId) {
    // The proof. A source that answers with nothing is not a feed worth
    // keeping — for Abfall it is usually a picker that matched the wrong town.
    let events;
    try {
      events = await readFeedEvents(args.kind, args.config);
    } catch (e) {
      console.error(`feed verify failed for ${feedKey}: ${(e as Error).message}`);
      return fail(errorFor(args.kind), 502);
    }
    if (!events.length) return fail(errorFor(args.kind));

    const { data: created, error } = await db
      .from("public_feeds")
      .insert({
        kind: args.kind,
        feed_key: feedKey,
        name: args.name,
        color: FEED_COLOR[args.kind] | 0,
        config: args.config,
        events,
        synced_at: new Date().toISOString(),
      })
      .select("id")
      .single();

    // Two households subscribing to a brand-new feed at the same moment: the
    // loser of the unique constraint takes the winner's row rather than failing.
    if (error?.code === "23505") {
      const { data: raced } = await db
        .from("public_feeds")
        .select("id, events")
        .eq("feed_key", feedKey)
        .single();
      feedId = raced?.id;
      count = Array.isArray(raced?.events) ? raced.events.length : 0;
    } else if (error || !created) {
      console.error(`feed insert failed for ${feedKey}: ${error?.message}`);
      return fail("Die Verbindung konnte nicht gespeichert werden.", 500);
    } else {
      feedId = created.id;
      count = events.length;
    }
  }

  if (!feedId) return fail("Die Verbindung konnte nicht gespeichert werden.", 500);

  const { error: subError } = await db
    .from("family_feeds")
    .upsert({
      family_id: args.familyId,
      feed_id: feedId,
      // The household's own label. Two families on the same street share the
      // feed but each keep the name they gave it.
      display_name: args.name,
      created_by: args.uid,
    }, { onConflict: "family_id,feed_id" });

  if (subError) {
    console.error(`feed subscribe failed for ${feedKey}: ${subError.message}`);
    return fail("Die Verbindung konnte nicht gespeichert werden.", 500);
  }

  return json({ feed_id: feedId, events: count });
}

function errorFor(kind: FeedKind): string {
  return kind === "abfall"
    ? "Für diese Adresse konnten keine Abfuhrtermine geladen werden."
    : "Für dieses Bundesland konnten keine Ferien geladen werden.";
}
