// abfall/vendors/awsstuttgart.ts — AWS Stuttgart — the ICS is addressed by plain
// street + house number, and the whole difficulty is proving it answered about
// the address we asked for.

import {
  type AbfallConfig,
  type AbfallProvider,
  fetchWithTimeout,
  type GeoAddress,
  germanSpellings,
  normStreet,
  parseIcs,
  type ResolveResult,
  type StreetOption,
  streetStem,
  type SyncedEvent,
  type Town,
  UA,
  type VendorAdapter,
} from "../core.ts";

// ── Abfallwirtschaft Stuttgart ──────────────────────────────────────────────
//
// No ids anywhere. The feed is addressed by the street name and house number
// themselves, which is why one household's subscription link is the whole API:
//
//   GET /lhs-services/aws/api/ical?street=Wachenheimer%20Str.&streetnr=3
//
// Two autocomplete endpoints sit beside it, and they are the same two the city's
// own form uses (`data-serviceurl` on the inputs; the param is `street`, not the
// jQuery library's default `query`):
//
//   GET /lhs-services/aws/strassennamen?street=<prefix>
//   GET /lhs-services/aws/hausnummern?street=<exact>&streetnr=<prefix>
//
// The second is deliberately NOT used to build a picker. It is capped at 12
// like the street search and the data behind it is ragged — "23-25",
// "27,27A" and "25TEILII(ErbbaurFl" are all real entries on Königstr. — so a
// dropdown built from it would be missing numbers that do work. A field to
// type in is honest where a truncated list is not.
//
// **The street must be spelled the city's way, abbreviated.** "Wachenheimer
// Straße" is a 404; only "Wachenheimer Str." is served, and the search will not
// find the full form either. So the street is always looked up first and the
// canonical spelling used from then on — `streetStem` drops the trailing type
// word, which is the longest prefix the city is guaranteed to share.
//
// **And the feed answers about a neighbouring address rather than saying no.**
// This is the trap, and it is worth stating plainly because the result looks
// perfectly healthy: it prefix-matches on BOTH the street and the number.
//
//   Königstr. 1  ->  a calendar for **Kleine Königstr. 1**   (wrong street)
//   Badstr. 1    ->  a calendar for **Badstr. 11**           (wrong house)
//
// Both return 200 with a full year of plausible pickups. The only thing that
// gives it away is `X-WR-CALDESC`, which echoes the address the server actually
// resolved — so every fetch is checked against what was asked for, and a
// mismatch is treated as "not found" rather than served. A household handed a
// neighbour's bin days has no way to tell.
//
// The window is a rolling ~3 months from the day it is asked, so there is no
// year-end to survive and no year parameter to pass.
const AWS_BASE = 'https://service.stuttgart.de/lhs-services/aws'

const AWS_STREETS = `${AWS_BASE}/strassennamen`
const AWS_HOUSES = `${AWS_BASE}/hausnummern`
const AWS_ICS = `${AWS_BASE}/api/ical`

interface AwsSuggestion { value?: string; data?: string }

async function awsSuggest(url: string, params: Record<string, string>): Promise<string[]> {
  const qs = new URLSearchParams(params).toString()
  const res = await fetchWithTimeout(`${url}?${qs}`, {
    headers: { 'User-Agent': UA, Accept: 'application/json, */*' },
  })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const val = await res.json().catch(() => null) as { suggestions?: AwsSuggestion[] } | null
  return (val?.suggestions || [])
    .map((s) => (s.value || s.data || '').trim())
    .filter(Boolean)
}

/// Street names starting with `query`. Case-insensitive, capped at 12, and it
/// folds nothing — "Koenigstr" finds Königstr. only if it is written that way.
const awsStreets = (query: string) => awsSuggest(AWS_STREETS, { street: query.trim() })

/// The city's own spelling of this street, or null when it does not serve one.
///
/// Asked for by the stem rather than the full name, because the city abbreviates
/// the type word and the search is a literal prefix match: "Wachenheimer Straße"
/// returns nothing where "Wachenheimer" returns "Wachenheimer Str.". The full
/// name is tried first anyway, for the streets that carry no type word at all.
async function awsFindStreet(street: string): Promise<string | null> {
  const target = normStreet(street)
  if (!target) return null
  const seen = new Set<string>()
  const queries: string[] = []
  for (const base of [street.trim(), streetStem(street)]) {
    for (const spelling of germanSpellings(base)) {
      if (spelling && !seen.has(spelling)) {
        seen.add(spelling)
        queries.push(spelling)
      }
    }
  }
  for (const q of queries) {
    const rows = await awsStreets(q).catch(() => [] as string[])
    // normStreet folds "Straße" and "Str." together, so the abbreviation the
    // city uses and the full form the geocoder gives compare equal here.
    const hit = rows.find((r) => normStreet(r) === target)
    if (hit) return hit
  }
  return null
}

const awsKey = (s: string) => (s || '').toLowerCase().replace(/[^a-z0-9]/g, '')

/// Is `hnr` a real house number on `street`?
///
/// Asked with the WHOLE number as the prefix, not its first digit: the endpoint
/// is capped at 12 results, and "1" on a long street returns 1, 1A, 1B, 10A …
/// and never reaches 134. The full number returns that number and its letters,
/// so the cap cannot hide it. An invented number returns nothing at all.
async function awsHouseExists(street: string, hnr: string): Promise<boolean> {
  const rows = await awsSuggest(AWS_HOUSES, { street, streetnr: hnr }).catch(() => [] as string[])
  return rows.some((r) => awsKey(r) === awsKey(hnr))
}

/// Fetch the calendar for exactly this address, or null if it could not be shown
/// to be ours.
///
/// This check is the whole point of the adapter — see the note at the top. The
/// server answers in one of three ways and only one of them is a plain yes:
///
///   404               no such address. This vendor does say no, which is more
///                     than most of them manage.
///   an address echoed in X-WR-CALDESC. If it is not the one we asked for, the
///                     server has substituted a neighbour (Königstr. 1 ->
///                     "Kleine Königstr. 1") and the calendar is refused.
///   no address echoed a collection point shared by several addresses, which is
///                     how a correct hit on a shared bin looks — Hohenheimer
///                     Str. 11 and Olgastr. 1 both answer this way. There is
///                     nothing to compare against, so the number is confirmed
///                     against the street's own house list instead. A number
///                     that is not on the street never reaches here (it 404s or
///                     it echoes), but the list is the cheaper thing to trust.
async function awsFetchIcs(street: string, hnr: string): Promise<string | null> {
  const qs = new URLSearchParams({ street, streetnr: hnr }).toString()
  const res = await fetchWithTimeout(`${AWS_ICS}?${qs}`, {
    headers: { 'User-Agent': UA, Accept: 'text/calendar, */*' },
  })
  if (res.status === 404) return null
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const ics = (await res.text()).replace(/^\uFEFF/, '')
  if (!ics.includes('BEGIN:VEVENT')) return null
  // "Abfallwirtschaft Stuttgart\, Wachenheimer Str. 3" — the part after the
  // escaped comma is the address the server actually resolved.
  const desc = ics.match(/^X-WR-CALDESC:(.*)$/m)?.[1] ?? ''
  const echoed = desc.includes('\\,') ? desc.split('\\,').slice(1).join(',').trim() : ''
  if (echoed) return awsKey(echoed) === awsKey(`${street} ${hnr}`) ? ics : null
  return await awsHouseExists(street, hnr) ? ics : null
}

async function searchStreetsAws(query: string): Promise<StreetOption[]> {
  const rows = await awsStreets(query)
  return rows.map((name) => ({
    name,
    config: { vendor: 'awsstuttgart' as const, street: name },
  }))
}

async function probeAws(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  const street = addr.street ? await awsFindStreet(addr.street) : null
  if (!street) return null

  const want = (addr.houseNumber || '').trim()
  if (want && await awsFetchIcs(street, want).catch(() => null)) {
    return {
      supported: true,
      town: town.name,
      street,
      config: { vendor: 'awsstuttgart', street, hnr: want },
    }
  }
  // Either no number was given, or the one given does not name a collection
  // point here — the household types it rather than picking, because the
  // vendor's own list is truncated and cannot be trusted to contain it.
  return {
    supported: true,
    town: town.name,
    street,
    needsHouseNumber: true,
    config: { vendor: 'awsstuttgart', street },
  }
}

async function readAws(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const street = (cfg.street || '').trim()
  const hnr = (cfg.hnr || '').trim()
  if (!street || !hnr) throw new Error('reconnect_required')
  const ics = await awsFetchIcs(street, hnr)
  // A verified-wrong or vanished address is a reconnect, not an empty calendar:
  // silently showing nothing would hide that the address stopped resolving.
  if (ics === null) throw new Error('reconnect_required')
  const thisYear = new Date().getUTCFullYear()
  const start = new Date(Date.UTC(thisYear - 1, 0, 1))
  const end = new Date(Date.UTC(thisYear + 2, 0, 1))
  const out: SyncedEvent[] = []
  const seen = new Set<string>()
  for (const ev of parseIcs(ics, start, end)) {
    // "Restmüll 02-wöchentl." — the rhythm is in the DESCRIPTION as well, and on
    // the title it just makes every row longer without saying anything the dates
    // do not already show.
    const title = ev.title.replace(/\s+\d{2}-w[öo]chentl\.?\s*$/i, '').trim() || ev.title.trim()
    const dayKey = `${ev.startsAt.slice(0, 10)}:${title}`
    if (seen.has(dayKey)) continue
    seen.add(dayKey)
    out.push({
      ...ev,
      uid: `abfall:awsstuttgart:${awsKey(street)}-${awsKey(hnr)}:${dayKey}`,
      title,
      location: cfg.label ?? ev.location ?? null,
    })
  }
  return out
}

function towns(p: AbfallProvider): Town[] {
  // One city; streets are searched live and the address validated by the probe.
  return [{ vendor: 'awsstuttgart', name: p.town || 'Stuttgart', provider: p.id }]
}

export const adapter: VendorAdapter = {
  family: 'awsstuttgart',
  towns,
  searchStreets: (_town, query) => searchStreetsAws(query),
  probe: probeAws,
  read: readAws,
}
