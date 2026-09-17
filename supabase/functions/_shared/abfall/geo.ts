// abfall/geo.ts — nationwide address autocomplete, and the Bundesland guard.
//
// Separate from the vendors on purpose: this is how an address is FOUND, and that
// is the same for every vendor. stateCode/cityState/PROVIDER_STATE are the
// cross-check that stops a town name served in two Länder matching the wrong one
// (see the note on PROVIDER_STATES in abfall_providers.ts).

import { ABFALL_PROVIDERS } from "../abfall_providers.ts";
import { fetchWithTimeout, type GeoAddress, JSON_HEADERS, UA } from "./core.ts";

export type { GeoAddress };

const PHOTON = 'https://photon.komoot.io/api/'

// Photon hands the Stadtstaaten back with no `state` at all: Berlin and Hamburg
// are one boundary, so there is no admin level above the city to name, and
// Bremerhaven comes without its "Freie Hansestadt Bremen" now and then. The
// client reads `state` to offer the Ferien calendar, so without this a Berlin
// address was told there were no school holidays for it.
const BUNDESLAENDER: Record<string, string> = {
  'baden-württemberg': 'BW', 'bayern': 'BY', 'berlin': 'BE', 'brandenburg': 'BB',
  'bremen': 'HB', 'hamburg': 'HH', 'hessen': 'HE', 'mecklenburg-vorpommern': 'MV',
  'niedersachsen': 'NI', 'nordrhein-westfalen': 'NW', 'rheinland-pfalz': 'RP',
  'saarland': 'SL', 'sachsen': 'SN', 'sachsen-anhalt': 'ST',
  'schleswig-holstein': 'SH', 'thüringen': 'TH',
}

/// The two-letter code behind whatever the geocoder called the state. Photon
/// writes the plain name ("Bayern"), and dresses the Hanseatic ones up ("Freie
/// Hansestadt Bremen"), so the longest name contained in the string wins.
export function stateCode(name: string | undefined): string | undefined {
  const raw = (name || '').trim().toLowerCase()
  if (!raw) return undefined
  if (BUNDESLAENDER[raw]) return BUNDESLAENDER[raw]
  let best: string | undefined
  let bestLength = 0
  for (const [full, code] of Object.entries(BUNDESLAENDER)) {
    if (raw.includes(full) && full.length > bestLength) {
      best = code
      bestLength = full.length
    }
  }
  return best
}

/// Which Bundesland each provider serves, by provider id.
export const PROVIDER_STATE = new Map(
  ABFALL_PROVIDERS.filter((p) => p.state).map((p) => [p.id, p.state as string]),
)

export function cityState(city: string | undefined): string | undefined {
  switch ((city || '').trim().toLowerCase()) {
    case 'berlin': return 'Berlin'
    case 'hamburg': return 'Hamburg'
    case 'bremen': case 'bremerhaven': return 'Bremen'
  }
  return undefined
}

// OSM boundary names are sometimes administrative jargon rather than the name
// people use ("Stadtgebiet Bremen" -> "Bremen").
export function cleanTown(s: string): string {
  return (s || '').replace(/^stadtgebiet\s+/i, '').trim()
}

// Free-text address autocomplete. Default mode (Abfall's town/street picker):
// Germany only, street-level hits only, a bare postcode query ("28213" — PLZ-
// first entry is common in Germany) returns prefix suggestions naming the
// town(s) of that PLZ instead. `worldwide` mode (the calendar event Location
// field) drops the Germany filter and also accepts named places/venues (a
// restaurant, office, doctor's practice) — a calendar location doesn't need to
// resolve to a bare street the way a waste-pickup address does.
export async function geocode(query: string, opts: { worldwide?: boolean } = {}): Promise<GeoAddress[]> {
  const raw = (query || '').trim()
  if (raw.length < 3) return []
  const barePlz = !opts.worldwide && /^\d{4,5}$/.test(raw)
  const url = `${PHOTON}?q=${encodeURIComponent(raw)}&lang=de&limit=8`
  const res = await fetchWithTimeout(url, { headers: JSON_HEADERS })
  if (!res.ok) throw new Error(`abfall geocode ${res.status}`)
  const data = await res.json() as {
    features?: Array<{ properties?: Record<string, string> }>
  }
  const out: GeoAddress[] = []
  const seen = new Set<string>()
  for (const f of data.features || []) {
    const p = f.properties || {}
    if (!opts.worldwide && p.countrycode && p.countrycode !== 'DE') continue
    const town = cleanTown(p.city || p.town || p.village || p.county || '')
    if (barePlz) {
      if (p.osm_value !== 'postcode' || !p.name || !town) continue
      const label = `${p.name} ${town}`
      if (seen.has(label)) continue
      seen.add(label)
      out.push({ label, street: '', town, postcode: p.name, prefix: true })
      continue
    }
    // A street name is either an explicit `street`, or the feature name when the
    // hit itself is a street (osm_key=highway).
    const street = p.street || (p.osm_key === 'highway' ? p.name : '') || ''
    // Worldwide mode also keeps named places without a street (a venue name is a
    // perfectly good calendar location); the default mode skips them — Abfall
    // needs a resolvable street address, not a business name.
    const placeName = opts.worldwide && p.name && p.osm_key !== 'highway' ? p.name : ''
    if (!opts.worldwide && (!town || !street)) continue
    if (opts.worldwide && !street && !placeName) continue
    const addrPart = [street, p.housenumber].filter(Boolean).join(' ')
    const cityPart = [p.postcode, town].filter(Boolean).join(' ')
    const label = placeName
      ? [placeName, [addrPart, cityPart].filter(Boolean).join(', ')].filter(Boolean).join(', ')
      : [addrPart, cityPart].filter(Boolean).join(', ')
    if (!label || seen.has(label)) continue
    seen.add(label)
    out.push({
      label, street, houseNumber: p.housenumber, town, postcode: p.postcode,
      state: p.state || cityState(p.city),
      ...(placeName ? { name: placeName } : {}),
    })
  }
  return out
}
