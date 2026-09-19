// abfall/vendors/abfallplus.ts — AbfallPlus "publisher" widgets (v3) — a GraphQL
// API behind the same per-authority key the legacy abfall.io widget used.

import { ABFALL_PROVIDERS } from "../../abfall_providers.ts";
import {
  type AbfallConfig,
  type AbfallProvider,
  fetchWithTimeout,
  type GeoAddress,
  germanSpellings,
  normStreet,
  type ResolveResult,
  restRhythm,
  type StreetOption,
  streetStem,
  type SyncedEvent,
  type Town,
  townMatches,
  UA,
  type VendorAdapter,
} from "../core.ts";

// ── AbfallPlus publisher (PLATFORM family) ──────────────────────────────────
//
// The successor to the legacy widget `abfallio.ts` speaks. An authority's page
// embeds `<abfallplus-publisher key="<32 hex>">` and `api.abfall.io/widgets/v3/
// widgets.js`; the key is the same kind the legacy widget took, and posting it
// to the same `waction=init` now answers JSON rather than an HTML form — which
// is why these keys looked dead to the legacy adapter.
//
//   1. POST api.abfall.io/?key=<key>&modus=<widget constant>&waction=init
//      -> {"apiKey":"<base64 uuid:n>","settings":{"PUB_ABFALLTYPEN":[…]}}
//   2. POST widgets.abfall.io/graphql   x-abfallplus-api-key: <apiKey>
//        cities -> city(id){streets(query)} -> street(id){houseNumbers}
//        -> appointments(idHouseNumber, wasteTypes, dateMin, dateMax)
//
// The apiKey is minted from the public key on every init and is not stored: it
// is the widget's own session, and a stored one would be a thing to expire.
//
// **Which bins are this household's is the publisher's own setting.** A house
// number's `wasteTypes` is everything the authority publishes for it — in
// Essen that includes the Schadstoffmobil stop of **every district in the city**,
// twenty of them. `PUB_ABFALLTYPEN` marks the household's bins `checked` and
// puts the mobile stops in a pick-one `radiogroup`, unchecked, which is exactly
// what the widget shows by default. Only the checked ones are asked for —
// **except a radiogroup that has a checked member**: that is the widget
// pre-selecting one rhythm of a bin the household is meant to choose (Freiburg's
// "Restabfalltonne" wöchentlich / 14-täglich / vierwöchentlich, weekly ticked),
// so every member is read and the household's own pick keeps one (see
// RhythmChoice in core.ts). Essen's mobile stops sit in a group with nothing
// ticked, and stay out.
//
// A publisher that ticks nothing at all (Hagen) is read in full, less the
// wasteTypes its provider row lists in `skipTypes` — the city-wide stops no
// household's bin is part of.
//
// **The date range is ours to choose**, unlike every calendar-year vendor here:
// the read asks from the start of last month to the end of next year, so next
// year's dates arrive the day the authority publishes them.
//
// A schedule can hang off three levels, and the API says which by carrying an
// `idHouseNumber` at that level: the whole town (one schedule for everybody),
// the street, or the house. Only the last one asks the household for a number.
//
// Street search is a case-insensitive prefix match that folds nothing:
// "Rüttenscheider Straße" finds nothing where the city writes "Rüttenscheider
// Str.", and "Ruettenscheider" finds nothing at all. So the stem is asked in
// each written form and every row is checked against the geocoded street.

const API = 'https://api.abfall.io'
const GQL = 'https://widgets.abfall.io/graphql'
// The widget's public constant — the same one abfallio.ts posts.
const MODUS = 'd6c5855a62cf32a4dadbc2831f0f295f'

interface Publisher { apiKey: string; wasteTypes: string[] }

async function init(key: string): Promise<Publisher> {
  if (!/^[0-9a-f]{32}$/.test(key)) throw new Error('reconnect_required')
  const res = await fetchWithTimeout(`${API}/?key=${key}&modus=${MODUS}&waction=init`, {
    method: 'POST',
    headers: { 'User-Agent': UA, Accept: 'application/json, */*' },
  })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const val = await res.json().catch(() => null) as {
    apiKey?: string
    settings?: { PUB_ABFALLTYPEN?: Array<{ wasteType?: string; checked?: boolean; radiogroup?: string | null }> }
  } | null
  if (!val?.apiKey) throw new Error('abfall upstream: no AbfallPlus apiKey')
  const types = val.settings?.PUB_ABFALLTYPEN || []
  const chosen = new Set(types.filter((t) => t.checked && t.radiogroup).map((t) => t.radiogroup))
  const wasteTypes = types
    .filter((t) => t.wasteType && (t.checked || (t.radiogroup && chosen.has(t.radiogroup))))
    .map((t) => String(t.wasteType))
  return { apiKey: val.apiKey, wasteTypes }
}

async function gql<T>(pub: Publisher, query: string, variables: Record<string, unknown>): Promise<T> {
  const res = await fetchWithTimeout(GQL, {
    method: 'POST',
    headers: {
      'User-Agent': UA,
      'Content-Type': 'application/json',
      Accept: 'application/json',
      'x-abfallplus-api-key': pub.apiKey,
    },
    body: JSON.stringify({ query, variables }),
  })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const val = await res.json() as { data?: T; errors?: unknown[] }
  if (!val.data || val.errors?.length) throw new Error('abfall upstream: AbfallPlus query failed')
  return val.data
}

interface ApCity { id: string; name: string; idHouseNumber: string | null; districtsCount: number }
interface ApStreet { id: string; name: string; idHouseNumber: string | null; postcodes?: string[] }
interface ApHouse { id: string; name: string }

const Q_CITIES = 'query($q:String){cities(query:$q){id name idHouseNumber districtsCount}}'
const Q_STREETS = 'query($id:ID!,$q:String){city(id:$id){streets(query:$q){id name idHouseNumber postcodes}}}'
const Q_DISTRICTS = 'query($id:ID!){city(id:$id){districts(query:""){name}}}'
const Q_HOUSES = 'query($id:ID!){street(id:$id){houseNumbers(query:""){id name}}}'
const Q_APPTS =
  'query($h:ID!,$w:[ID],$a:Date,$b:Date){appointments(idHouseNumber:$h,wasteTypes:$w,dateMin:$a,dateMax:$b){id date wasteType{id name}}}'

async function streets(pub: Publisher, cityId: string, q: string): Promise<ApStreet[]> {
  if (q.trim().length < 2) return []
  const d = await gql<{ city: { streets: ApStreet[] } | null }>(pub, Q_STREETS, { id: cityId, q: q.trim() })
  return d.city?.streets || []
}

/// The vendor's row for this street, or null when there is none — or when there
/// are several and nothing says which.
///
/// `city.streets` searches the whole town, villages included, even where the
/// town is split into districts — so a Landkreis town can answer one name more
/// than once (a "Hauptstraße" in each Ortsteil). Each row carries its postcodes,
/// and the geocoded postcode picks between them. Where it cannot, the address
/// is refused rather than guessed: the wrong Ortsteil's row is a real calendar
/// for somebody else's bins, and nothing downstream would notice.
/// Publishers whose street postcodes are not the streets' own (see the provider
/// rows): the postcode says nothing there, so it is not asked.
const WRONG_POSTCODES = new Set(ABFALL_PROVIDERS.filter((p) => p.family === 'abfallplus' && p.wrongPostcodes).map((p) => p.key!))

async function findStreet(pub: Publisher, cityId: string, street: string, postcode?: string): Promise<ApStreet | null> {
  const target = normStreet(street)
  if (!target) return null
  const asked = new Set<string>()
  for (const spelling of germanSpellings(street)) {
    for (const q of [spelling, streetStem(spelling)]) {
      if (asked.has(q)) continue
      asked.add(q)
      const hits = (await streets(pub, cityId, q).catch(() => [] as ApStreet[]))
        .filter((r) => normStreet(r.name) === target)
        // **A street that names its postcodes and not this one is another
        // town's.** The resolver retries a town nobody serves under each
        // neighbour sharing its postcode, so "Torgauer Straße, 04838 Eilenburg"
        // (not ASG Nordsachsen's) arrived here as Mockrehna's Torgauer Straße —
        // same name, 04862, a village's bin days for a town it is not.
        .filter((r) => !postcode || !r.postcodes?.length || r.postcodes.includes(postcode))
      if (hits.length === 1) return hits[0]
      if (hits.length > 1) {
        const byPlz = postcode ? hits.filter((r) => (r.postcodes || []).includes(postcode)) : []
        return byPlz.length === 1 ? byPlz[0] : null
      }
    }
  }
  return null
}

async function houses(pub: Publisher, streetId: string): Promise<ApHouse[]> {
  const d = await gql<{ street: { houseNumbers: ApHouse[] } | null }>(pub, Q_HOUSES, { id: streetId })
  return d.street?.houseNumbers || []
}

// "1 a", "1a", "1A" are one house.
const nrKey = (s: string) => (s || '').trim().toLowerCase().replace(/\s+/g, '')

const iso = (d: Date) => d.toISOString().slice(0, 10)

/// Per publisher key, the wasteTypes that are nobody's bin (see above).
const SKIP = new Map(ABFALL_PROVIDERS.filter((p) => p.family === 'abfallplus' && p.key && p.skipTypes).map((p) => [p.key!, new Set(p.skipTypes)]))

async function appointments(pub: Publisher, idHouseNumber: string, key?: string) {
  const now = new Date()
  const from = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 1, 1))
  const to = new Date(Date.UTC(now.getUTCFullYear() + 1, 11, 31))
  const d = await gql<{ appointments: Array<{ id: string; date: string; wasteType?: { id?: string; name?: string } }> | null }>(
    pub, Q_APPTS,
    { h: idHouseNumber, w: pub.wasteTypes.length ? pub.wasteTypes : null, a: iso(from), b: iso(to) },
  )
  const skip = key ? SKIP.get(key) : undefined
  return (d.appointments || []).filter((a) => !skip?.has(String(a.wasteType?.id ?? '')))
}

/// Is this address in this city at all?
///
/// A publisher's cities are whole Gemeinden. The resolver, when the geocoded
/// town is served by nobody, retries it under every place sharing its postcode —
/// right when the geocoder named a district ("Hengen") and the vendor lists the
/// Gemeinde ("Bad Urach"), and badly wrong when it named a Gemeinde this
/// publisher does not serve: "Torgauer Straße, 04838 Eilenburg" came back as
/// Mockrehna's Torgauer Straße, a village 15 km away that shares the postcode
/// area and the street name. Nordsachsen's rows carry no postcodes to catch it.
/// So a city that is not the geocoded town is accepted only when the geocoded
/// town is one of its own districts.
async function inCity(pub: Publisher, town: Town, addr: GeoAddress): Promise<boolean> {
  const want = (addr.town || '').trim().toLowerCase()
  if (!want || townMatches(town.name.toLowerCase(), want)) return true
  const d = await gql<{ city: { districts: Array<{ name: string }> } | null }>(pub, Q_DISTRICTS, { id: town.cityId })
    .catch(() => null)
  return !!d?.city?.districts?.some((x) => townMatches(x.name.toLowerCase(), want))
}

async function probeAbfallplus(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  const key = town.key, cityId = town.cityId
  if (!key || !cityId) return null
  const pub = await init(key).catch(() => null)
  if (!pub) return null
  if (!await inCity(pub, town, addr)) return null
  const base = { vendor: 'abfallplus' as const, key }

  // One schedule for the whole town: any street in it is served.
  if (town.areaId) {
    return { supported: true, town: town.name, street: addr.street, config: { ...base, hnrId: town.areaId } }
  }
  if (!addr.street) return null
  const postcode = WRONG_POSTCODES.has(key) ? undefined : addr.postcode
  const hit = await findStreet(pub, cityId, addr.street, postcode).catch(() => null)
  if (!hit) return null
  if (hit.idHouseNumber) {
    return { supported: true, town: town.name, street: hit.name, config: { ...base, street: hit.name, hnrId: hit.idHouseNumber } }
  }

  const list = await houses(pub, hit.id).catch(() => [] as ApHouse[])
  if (!list.length) return null
  const want = nrKey(addr.houseNumber || '')
  const house = want ? list.find((h) => nrKey(h.name) === want) : undefined
  if (house) {
    // Listed is not the same as served; a house with nothing on it would
    // connect a calendar that stays empty.
    const appts = await appointments(pub, house.id, key).catch(() => [])
    if (appts.length) {
      return {
        supported: true,
        town: town.name,
        street: hit.name,
        config: { ...base, street: hit.name, hnrId: house.id, hnr: house.name },
      }
    }
  }
  return {
    supported: true,
    town: town.name,
    street: hit.name,
    needsHouseNumber: true,
    hausNrList: list.map((h) => ({ id: h.id, nr: h.name })),
    config: { ...base, street: hit.name },
  }
}

async function searchStreetsAbfallplus(town: Town, query: string): Promise<StreetOption[]> {
  if (!town.key || !town.cityId) return []
  const pub = await init(town.key)
  const rows = await streets(pub, town.cityId, query)
  return rows.map((r) => ({
    name: r.name,
    config: {
      vendor: 'abfallplus' as const,
      key: town.key,
      street: r.name,
      ...(r.idHouseNumber ? { hnrId: r.idHouseNumber } : {}),
    },
  }))
}

async function readAbfallplus(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const id = String(cfg.hnrId ?? '')
  if (!cfg.key || !/^[0-9]{1,12}$/.test(id)) throw new Error('reconnect_required')
  const pub = await init(cfg.key)
  const out: SyncedEvent[] = []
  for (const a of await appointments(pub, id, cfg.key)) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(a.date || '')) continue
    const start = new Date(`${a.date}T00:00:00Z`)
    out.push({
      uid: `abfall:abfallplus:${cfg.key.slice(0, 8)}:${a.id}`,
      title: (a.wasteType?.name || 'Abfuhr').trim(),
      notes: null,
      location: cfg.label ?? null,
      startsAt: start.toISOString(),
      endsAt: new Date(start.getTime() + 86_400_000).toISOString(),
      allDay: true,
    })
  }
  return out
}

/// Every city the publisher serves. `areaId` is set when the whole town shares
/// one schedule. A city split into districts is still one town here: its
/// streets are searched across the whole city (see `findStreet`).
async function towns(p: AbfallProvider): Promise<Town[]> {
  if (!p.key) return []
  const pub = await init(p.key)
  const d = await gql<{ cities: ApCity[] }>(pub, Q_CITIES, { q: '' })
  return (d.cities || [])
    .map((c) => ({
      vendor: 'abfallplus' as const,
      name: p.town && d.cities.length === 1 ? p.town : c.name,
      provider: p.id,
      key: p.key,
      cityId: c.id,
      ...(c.idHouseNumber ? { areaId: c.idHouseNumber } : {}),
    }))
}

export const adapter: VendorAdapter = {
  family: 'abfallplus',
  towns,
  searchStreets: searchStreetsAbfallplus,
  probe: probeAbfallplus,
  rhythm: restRhythm,
  read: readAbfallplus,
}
