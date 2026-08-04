/// Public feeds: German school holidays and waste collection.
///
/// These two are unlike every other calendar Aporah touches. They hold no
/// personal data, they need no credentials, and — the part that matters here —
/// they are **the same feed for everybody**. Every household in Niedersachsen
/// gets byte-identical Schulferien; every household at one address gets
/// byte-identical Abfuhrtermine.
///
/// So a feed is stored once, globally, in public.public_feeds, and households
/// subscribe to it through public.family_feeds. The hundredth family in Bremen
/// costs one row, not a connection plus a calendar plus thirty events plus a
/// recurring fetch of a municipal website that would rather we did not.
///
/// No function secrets. OpenHolidays and every waste vendor are free and keyless.

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { readAbfallEvents } from "./abfall.ts";
import type { SyncedEvent } from "./calendar.ts";

export type FeedKind = "ferien" | "abfall";

/// Default ARGB per kind, matching what the Flutter side draws.
export const FEED_COLOR: Record<FeedKind, number> = {
  ferien: 0xfff59e0b,
  abfall: 0xff6d4c41,
};

/// How long a cached feed stays good.
///
/// Holidays for the next three years are published once and then essentially
/// never move. Bin days are firmer than that in principle but do get shifted
/// around public holidays, and being wrong about one costs somebody a week of
/// full bins — so they are re-read daily.
const TTL_MS: Record<FeedKind, number> = {
  ferien: 7 * 86_400_000,
  abfall: 86_400_000,
};

export interface PublicFeed {
  id: string;
  kind: FeedKind;
  feed_key: string;
  name: string;
  color: number;
  config: Record<string, unknown>;
  events: SyncedEvent[];
  synced_at: string | null;
}

/// A feed as one household sees it: the shared row, plus that household's own
/// name and colour for it.
export interface SubscribedFeed extends PublicFeed {
  displayName: string;
  displayColor: number;
  position: number;
}

// ---------------------------------------------------------------------------
// Identity
// ---------------------------------------------------------------------------

/// The deterministic key two households at the same address have to agree on.
///
/// Derived from the resolved config rather than from what was typed: "Hauptstr."
/// and "Hauptstraße" are the same street and resolve to the same vendor ids, and
/// it is those ids that decide whether this is the same bin schedule. Anything
/// purely presentational (`label`) is excluded for the same reason — one
/// household writing their address in caps must not fork the feed.
export async function feedKeyOf(
  kind: FeedKind,
  config: Record<string, unknown>,
): Promise<string> {
  if (kind === "ferien") {
    return `ferien:${String(config.state ?? "").toUpperCase()}`;
  }

  const { label: _label, ...identity } = config;
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(canonical(identity)),
  );
  const hex = Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return `abfall:${hex}`;
}

/// JSON with object keys sorted at every depth, so two callers who built the
/// same config in a different order still hash to the same key.
function canonical(value: unknown): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value) ?? "null";
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;

  const entries = Object.entries(value as Record<string, unknown>)
    .filter(([, v]) => v !== undefined)
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));

  return `{${entries.map(([k, v]) => `${JSON.stringify(k)}:${canonical(v)}`).join(",")}}`;
}

// ---------------------------------------------------------------------------
// Reading
// ---------------------------------------------------------------------------

export async function readFeedEvents(
  kind: FeedKind,
  config: Record<string, unknown>,
): Promise<SyncedEvent[]> {
  // readAbfallEvents validates its own input — it is reached with whatever came
  // out of jsonb, so it takes `unknown` and narrows rather than trusting a cast.
  return kind === "ferien"
    ? await readFerienEvents(String(config.state ?? ""))
    : await readAbfallEvents(config);
}

/// German school holidays per Bundesland, from OpenHolidays — free, no key, no
/// account. Not ferien-api.de: that one stopped publishing new years, which is a
/// silent failure (an empty list looks like "no holidays this year").
export async function readFerienEvents(stateCode: string): Promise<SyncedEvent[]> {
  const code = stateCode.toUpperCase().replace(/^DE-/, "");
  if (!/^[A-Z]{2}$/.test(code)) throw new Error("invalid Bundesland");

  // OpenHolidays caps a query at 1095 days, so this window is narrower than the
  // one every other provider gets.
  const from = new Date(Date.UTC(new Date().getUTCFullYear() - 1, 0, 1));
  const to = new Date(from.getTime() + 1090 * 86_400_000);

  const url = new URL("https://openholidaysapi.org/SchoolHolidays");
  url.searchParams.set("countryIsoCode", "DE");
  url.searchParams.set("subdivisionCode", `DE-${code}`);
  url.searchParams.set("languageIsoCode", "DE");
  url.searchParams.set("validFrom", from.toISOString().slice(0, 10));
  url.searchParams.set("validTo", to.toISOString().slice(0, 10));

  const res = await fetch(url, { headers: { Accept: "application/json" } });
  if (!res.ok) throw new Error(`OpenHolidays ${res.status}`);

  const out: SyncedEvent[] = [];
  for (const holiday of await res.json()) {
    if (!holiday?.startDate) continue;

    const startsAt = new Date(`${holiday.startDate}T00:00:00Z`);
    if (isNaN(startsAt.getTime())) continue;

    // OpenHolidays' endDate is the last day inclusive; an all-day event's end is
    // exclusive. Forgetting this is why holidays used to render one day short.
    const endsAt = new Date(`${holiday.endDate ?? holiday.startDate}T00:00:00Z`);
    endsAt.setUTCDate(endsAt.getUTCDate() + 1);

    const names: Array<{ language?: string; text?: string }> = holiday.name ?? [];
    const title = (names.find((n) => n.language === "DE")?.text ?? names[0]?.text ?? "Ferien").trim();

    out.push({
      uid: holiday.id || `ferien:${code}:${holiday.startDate}:${title}`,
      title: title || "Ferien",
      notes: null,
      location: null,
      startsAt: startsAt.toISOString(),
      endsAt: endsAt.toISOString(),
      allDay: true,
    });
  }
  return out;
}

// ---------------------------------------------------------------------------
// Cache
// ---------------------------------------------------------------------------

function isStale(feed: PublicFeed): boolean {
  if (!feed.synced_at) return true;
  return Date.now() - new Date(feed.synced_at).getTime() > TTL_MS[feed.kind];
}

/// Re-reads a feed from its source and stores the result.
///
/// Returns the events either way: a municipal website that is down today is not
/// a reason to blank a family's bin calendar, so a failed refresh keeps serving
/// the last good copy and records why on the row.
export async function refreshFeed(db: SupabaseClient, feed: PublicFeed): Promise<SyncedEvent[]> {
  try {
    const events = await readFeedEvents(feed.kind, feed.config);
    if (!events.length) throw new Error("feed returned no events");

    await db
      .from("public_feeds")
      .update({
        events,
        synced_at: new Date().toISOString(),
        status: "ok",
        status_detail: null,
      })
      .eq("id", feed.id);

    return events;
  } catch (e) {
    console.error(`feed refresh failed for ${feed.feed_key}: ${(e as Error).message}`);
    await db
      .from("public_feeds")
      .update({ status: "error", status_detail: "Die Quelle war nicht erreichbar." })
      .eq("id", feed.id);

    return feed.events ?? [];
  }
}

/// Every feed this household subscribes to, refreshed where stale.
///
/// The refresh is shared, not per household: whoever opens their calendar first
/// after the TTL pays for the fetch, and every other family on that feed reads
/// the row they just filled.
export async function subscribedFeeds(
  db: SupabaseClient,
  familyId: string,
): Promise<SubscribedFeed[]> {
  const { data } = await db
    .from("family_feeds")
    .select(
      "display_name, color, position, " +
        "public_feeds!inner (id, kind, feed_key, name, color, config, events, synced_at)",
    )
    .eq("family_id", familyId)
    .order("position");

  // The embedded relation is a foreign key to a primary key, so there is exactly
  // one feed per row — but PostgREST's generated types cannot know that from the
  // select string and offer a union, so the shape is stated here instead.
  const rows = (data ?? []) as unknown as Array<{
    display_name: string | null;
    color: number | null;
    position: number | null;
    public_feeds: PublicFeed | PublicFeed[] | null;
  }>;

  const out: SubscribedFeed[] = [];
  for (const row of rows) {
    const feed = Array.isArray(row.public_feeds) ? row.public_feeds[0] : row.public_feeds;
    if (!feed) continue;

    const events = isStale(feed) ? await refreshFeed(db, feed) : (feed.events ?? []);

    out.push({
      ...feed,
      events,
      displayName: row.display_name ?? feed.name,
      displayColor: row.color ?? feed.color,
      position: row.position ?? 0,
    });
  }
  return out;
}
