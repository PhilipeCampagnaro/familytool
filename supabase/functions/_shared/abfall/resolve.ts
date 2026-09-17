// abfall/resolve.ts — the vendor-agnostic half: town aggregation, street search,
// address resolution and the event read.
//
// Nothing in this file names a waste vendor. Every branch that used to read
// `if (town.vendor === 'bsr')` now asks the adapter whether it can do the job, so
// a new city is a new file in vendors/ plus a line in registry.ts — and there is
// no longer a way to add a vendor to three dispatch chains out of four.

import { ABFALL_PROVIDERS } from "../abfall_providers.ts";
import {
  type AbfallConfig, fetchWithTimeout, type GeoAddress, JSON_HEADERS, normStreet,
  type ResolveResult, type StreetOption, streetStem, type SyncedEvent, type Town,
  townMatches,
} from "./core.ts";
import { cityState, PROVIDER_STATE, stateCode } from "./geo.ts";
import { adapterFor } from "./registry.ts";

// Cheap in-memory cache so the provider fan-out only runs once per warm instance.
let _townCache: { at: number; towns: Town[] } | null = null

// Every town across every provider in the map, flattened for a single search box.
// WHICH towns a provider contributes is the adapter's business, not this file's:
// regioit fetches them live, awgbassum reads a static city list, a city vendor
// returns exactly one. One dead provider never sinks the whole list (allSettled).
export async function aggregateTowns(): Promise<Town[]> {
  if (_townCache && Date.now() - _townCache.at < 6 * 60 * 60 * 1000) return _townCache.towns
  const results = await Promise.allSettled(
    ABFALL_PROVIDERS.map(async (p): Promise<Town[]> => {
      const adapter = adapterFor(p.family)
      if (!adapter?.towns) return []
      return await adapter.towns(p)
    }),
  )
  const towns: Town[] = []
  for (const r of results) if (r.status === 'fulfilled') towns.push(...r.value)
  towns.sort((a, b) => a.name.localeCompare(b.name, 'de'))
  _townCache = { at: Date.now(), towns }
  return towns
}

// Street autocomplete inside one town. A vendor with no street list to offer
// (C-Trace validates the street server-side instead) simply has no
// `searchStreets`, and answers with nothing rather than with a special case here.
export async function searchStreets(
  town: Town, query: string, hint?: string,
): Promise<StreetOption[]> {
  const adapter = adapterFor(town.vendor)
  if (!adapter?.searchStreets) return []
  return await adapter.searchStreets(town, query, hint)
}

// Given a geocoded address, decide whether a known vendor serves it. Matches the
// geocoded town to a covered town (by name), then fuzzy-matches the geocoded
// street against that vendor's street list. The geocoder often names the
// DISTRICT (Ortsteil) where the vendor lists the MUNICIPALITY ("Bernbach" vs
// "Freigericht") — when the direct name fails, the postcode is resolved to the
// canonical municipality (zippopotam, free/no-key) and the match retried.
// Returns { supported:false } if every attempt fails, so the UI can say
// "not supported in <town> yet".
export async function resolveAddress(addr: GeoAddress): Promise<ResolveResult> {
  const townName = (addr.town || '').trim()
  if (!townName || !addr.street) return { supported: false, town: townName }
  const towns = await aggregateTowns()

  const direct = await matchTownAndStreet(towns, townName, addr)
  if (direct) return direct

  if (addr.postcode) {
    try {
      const res = await fetchWithTimeout(
        `https://api.zippopotam.us/de/${encodeURIComponent(addr.postcode)}`,
        { headers: JSON_HEADERS },
      )
      if (res.ok) {
        const data = await res.json() as { places?: Array<{ 'place name'?: string }> }
        const names = new Set<string>()
        for (const p of data.places || []) {
          const n = (p['place name'] || '').trim()
          if (n && n.toLowerCase() !== townName.toLowerCase()) names.add(n)
        }
        for (const n of names) {
          const viaPlz = await matchTownAndStreet(towns, n, addr)
          if (viaPlz) return viaPlz
        }
      }
    } catch { /* fall through to unsupported */ }
  }
  return { supported: false, town: townName }
}

// One match attempt: find covered towns named like `townName`, then a street in
// one of them matching the geocoded street. Returns null when nothing matches.
async function matchTownAndStreet(
  towns: Town[], townName: string, addr: GeoAddress,
): Promise<ResolveResult | null> {
  const tl = townName.toLowerCase()
  // The Bundesland the address is in, from the geocoder or — for the three
  // city-states, where Photon names none — from the city itself.
  const addrState = stateCode(addr.state) ?? stateCode(cityState(addr.town))
  const wrongState = (t: Town): boolean => {
    const provider = PROVIDER_STATE.get(t.provider)
    return !!addrState && !!provider && provider !== addrState
  }
  const candidates = towns
    .filter((t) => townMatches(t.name.toLowerCase(), tl))
    // **A town in another Bundesland is a different town with the same name.**
    // 37 names in the registry are served in more than one state, and where the
    // vendor publishes one schedule for the whole town it accepts any street,
    // so the match succeeds and the household is handed a stranger's bin days.
    // See the note on PROVIDER_STATES in abfall_providers.ts.
    .filter((t) => !wrongState(t))
    // Exact town-name matches first.
    .sort((a, b) => Number(b.name.toLowerCase() === tl) - Number(a.name.toLowerCase() === tl))
    .slice(0, 6)
  if (!candidates.length) return null

  const target = normStreet(addr.street)
  const stem = streetStem(addr.street)
  // The geocoder's town is often the district; vendors tag multi-district
  // streets with it ("Ahornweg (Bernbach)"), so prefer that exact variant.
  const district = (addr.town || '').trim().toLowerCase()
  for (const town of candidates) {
    // A vendor that needs the house number to name a schedule at all resolves the
    // whole address in one go; its probe REPLACES the street-list match below.
    const adapter = adapterFor(town.vendor)
    if (adapter?.probe) {
      const probed = await adapter.probe(town, addr).catch(() => null)
      if (probed) return probed
      continue
    }
    let streets: StreetOption[]
    try {
      streets = await searchStreets(town, stem, addr.town)
    } catch { continue }
    const townNorm = normStreet(town.name)
    const best =
      streets.find((s) =>
        normStreet(s.name) === target && district &&
        s.name.toLowerCase().includes(district) && s.name.toLowerCase() !== district) ||
      streets.find((s) => normStreet(s.name) === target) ||
      streets.find((s) => {
        const n = normStreet(s.name)
        return n !== townNorm && (n.includes(target) || target.includes(n))
      }) ||
      // Whole-town schedule: some vendors publish ONE calendar for the entire
      // municipality (jumomind has_streets=false; AWIDO city-grouped clients).
      // Their "street" list then holds an entry named like the town itself —
      // every street in that town is covered by it.
      streets.find((s) => normStreet(s.name) === townNorm)
    if (best) {
      let hausNrList = best.hausNrList
      // Some vendors keep the house numbers behind a further call, so they are
      // fetched for the one matched street only. Nothing back = a street-level
      // schedule, which is fine.
      if (adapter?.houseNumbers) {
        try {
          const hnrs = await adapter.houseNumbers(best)
          if (hnrs?.length) hausNrList = hnrs
        } catch { /* street-level schedule is fine */ }
      }
      return {
        supported: true,
        town: town.name,
        street: best.name,
        hausNrList,
        config: best.config,
      }
    }
  }
  return null
}

// `config` is jsonb, so it arrives as an object. A connection saved before its
// address was resolved has no vendor at all — that is a reconnect, not a
// transient failure, and the caller turns it into "Bitte erneut verbinden."
export async function readAbfallEvents(raw: unknown): Promise<SyncedEvent[]> {
  if (!raw || typeof raw !== 'object') throw new Error('reconnect_required')
  const cfg = raw as AbfallConfig
  const adapter = adapterFor(cfg.vendor)
  if (!adapter) throw new Error('reconnect_required')
  return await adapter.read(cfg)
}
