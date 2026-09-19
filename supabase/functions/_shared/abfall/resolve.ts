// abfall/resolve.ts — the vendor-agnostic half: town aggregation, street search,
// address resolution and the event read.
//
// Nothing in this file names a waste vendor. Every branch that used to read
// `if (town.vendor === 'bsr')` now asks the adapter whether it can do the job, so
// a new city is a new file in vendors/ plus a line in registry.ts — and there is
// no longer a way to add a vendor to three dispatch chains out of four.

import { ABFALL_PROVIDERS, type AbfallProvider } from "../abfall_providers.ts";
import {
  type AbfallConfig, fetchWithTimeout, type GeoAddress, JSON_HEADERS, normStreet,
  type ResolveResult, type RhythmChoice, type RhythmTag, type StreetOption, streetStem,
  type SyncedEvent, type Town, townMatches, type VendorAdapter,
} from "./core.ts";
import { cityState, PROVIDER_STATE, stateCode } from "./geo.ts";
import { adapterFor } from "./registry.ts";
import { UPLOAD_TOWNS } from "./upload_towns.ts";

// ── Upload-only providers (see `upload` in abfall_providers.ts) ─────────────
//
// Nothing in this file may send a request to one of them: their towns come
// from the registry itself, a match answers `uploadOnly` without a probe, and
// a stored config of a family that is upload-only everywhere is refused before
// its adapter is reached — so neither the daily refresh nor a feed created
// before the flag can fetch from it.
const UPLOAD = new Map(ABFALL_PROVIDERS.filter((p) => p.upload).map((p) => [p.id, p]))
const UPLOAD_FAMILIES = new Set<string>(
  ABFALL_PROVIDERS.map((p) => p.family)
    .filter((f) => ABFALL_PROVIDERS.every((p) => p.family !== f || p.upload)),
)

function uploadTowns(p: AbfallProvider): Town[] {
  const names = p.town ? [p.town] : p.cities?.length ? p.cities : UPLOAD_TOWNS[p.id] ?? []
  return names.map((name) => ({ vendor: p.family, name, provider: p.id }))
}

/// Whether `town` is one of the upload-only towns — from the registry alone,
/// with no network. `calendar-link` asks it before a bin file goes onto the
/// free connection (see BIN_FILE_ACCOUNT in entitlements.ts).
export function isUploadOnlyTown(town: string): boolean {
  const tl = (town || '').trim().toLowerCase()
  if (tl.length < 3) return false
  for (const p of UPLOAD.values()) {
    if (uploadTowns(p).some((t) => townMatches(t.name.toLowerCase(), tl))) return true
  }
  return false
}

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
      if (p.upload) return uploadTowns(p)
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
  if (UPLOAD.has(town.provider) || !adapter?.searchStreets) return []
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
  if (direct && !direct.uploadOnly) return settleHouseNumber(direct, addr)
  // Upload-only is the last answer, not the first: the postcode may still lead
  // to a provider we are allowed to read.
  let uploadOnly = direct

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
          if (viaPlz && !viaPlz.uploadOnly) return settleHouseNumber(viaPlz, addr)
          uploadOnly ??= viaPlz
        }
      }
    } catch { /* fall through to unsupported */ }
  }
  return uploadOnly ?? { supported: false, town: townName }
}

// The app asks for the house number with the address, so a vendor that answers
// with a list of numbers to pick from (abfall.io, AWIDO, jumomind, …) is handed
// the pick here: the one entry that IS the typed number goes into the config the
// way the client's chip would have put it there, and the household never sees
// the list. Exact matches only — "12" is not "12a", and a range like "1-53" is
// the vendor's own business (Heidelberg settles its ranges in its probe). A
// list of one is no choice either — Lienen's "Alle Hausnummern" — and is taken
// whatever was typed. No match, or two, leaves the list for the household
// exactly as before.
const houseKey = (s: string) => (s || '').toLowerCase().replace(/\s+/g, '')

function settleHouseNumber(found: ResolveResult, addr: GeoAddress): ResolveResult {
  const typed = houseKey(addr.houseNumber || '')
  const list = found.hausNrList
  if (!found.config || !list?.length || found.config.hnrId != null) return found
  const hits = list.length === 1 ? list : typed ? list.filter((h) => houseKey(h.nr) === typed) : []
  if (hits.length !== 1) return found
  const { hausNrList: _list, needsHouseNumber: _needs, ...rest } = found
  return { ...rest, config: { ...found.config, hnrId: hits[0].id } }
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
  // A town served only by upload is the answer when no provider we may fetch
  // from serves the street — the loop goes on in case one does.
  let uploadOnly: ResolveResult | null = null
  for (const town of candidates) {
    const blocked = UPLOAD.get(town.provider)
    if (blocked) {
      uploadOnly ??= { supported: false, uploadOnly: true, town: town.name, page: blocked.upload?.page }
      continue
    }
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
  return uploadOnly
}

// `config` is jsonb, so it arrives as an object. A connection saved before its
// address was resolved has no vendor at all — that is a reconnect, not a
// transient failure, and the caller turns it into "Bitte erneut verbinden."
export async function readAbfallEvents(raw: unknown): Promise<SyncedEvent[]> {
  const { adapter, cfg } = adapterOf(raw)
  const events = await adapter.read(cfg)
  return adapter.rhythm ? keepRhythm(events, adapter.rhythm.bind(adapter), cfg.rhythm) : events
}

function adapterOf(raw: unknown): { adapter: VendorAdapter; cfg: AbfallConfig } {
  if (!raw || typeof raw !== 'object') throw new Error('reconnect_required')
  const cfg = raw as AbfallConfig
  const adapter = adapterFor(cfg.vendor)
  if (!adapter || UPLOAD_FAMILIES.has(cfg.vendor)) throw new Error('reconnect_required')
  return { adapter, cfg }
}

// ── Rhythms (see RhythmChoice in core.ts) ───────────────────────────────────

/// The household's pick applied: a picked bin keeps only its rhythm, renamed to
/// the bin with the rhythm in the notes, so the row reads "Restmüll" like every
/// other city's. A bin nobody picked for keeps every line — which is what a
/// connection made before the question existed has always shown.
function keepRhythm(
  events: SyncedEvent[], tag: (title: string) => RhythmTag | null, pick?: Record<string, string>,
): SyncedEvent[] {
  if (!pick || typeof pick !== 'object') return events
  const out: SyncedEvent[] = []
  for (const e of events) {
    const t = tag(e.title)
    const want = t ? pick[t.bin] : undefined
    if (!t || typeof want !== 'string') { out.push(e); continue }
    if (t.option !== want) continue
    out.push({ ...e, title: t.bin, notes: [t.option, e.notes].filter(Boolean).join(' · ') })
  }
  return out
}

/// Days between collections, as the dates actually fall: the median gap, snapped
/// to a week, a fortnight or four weeks. Holiday moves shift single gaps, which
/// is why it is the median and not the first one.
function interval(days: string[]): number | null {
  const ts = [...new Set(days)].sort().map((d) => Date.parse(`${d}T00:00:00Z`))
  const gaps = ts.slice(1).map((t, i) => Math.round((t - ts[i]) / 86_400_000)).sort((a, b) => a - b)
  if (!gaps.length) return null
  const mid = gaps[Math.floor(gaps.length / 2)]
  return [7, 14, 28].find((n) => Math.abs(mid - n) <= 2) ?? null
}

/// What this address makes the household choose: every bin with more than one
/// rhythm among its dates, the options ordered most frequent first. Empty for a
/// vendor that never asks, and for an address with one rhythm per bin.
export async function rhythmChoices(raw: unknown): Promise<RhythmChoice[]> {
  const { adapter, cfg } = adapterOf(raw)
  if (!adapter.rhythm) return []
  const bins = new Map<string, Map<string, string[]>>()
  for (const e of await adapter.read(cfg)) {
    const t = adapter.rhythm(e.title)
    if (!t) continue
    const opts = bins.get(t.bin) ?? new Map<string, string[]>()
    opts.set(t.option, [...(opts.get(t.option) ?? []), e.startsAt.slice(0, 10)])
    bins.set(t.bin, opts)
  }
  const out: RhythmChoice[] = []
  for (const [bin, opts] of bins) {
    if (opts.size < 2) continue
    const options = [...opts].map(([id, days]) => ({ id, every: interval(days), n: new Set(days).size }))
      .sort((a, b) => (a.every ?? 99) - (b.every ?? 99) || b.n - a.n || a.id.localeCompare(b.id, 'de'))
      .map(({ id, every }) => ({ id, every }))
    out.push({ bin, options })
  }
  return out
}

/// The bins a config still leaves unanswered — what `calendar-feed` refuses to
/// store, because the calendar would show every rhythm at once.
export async function openRhythms(raw: unknown): Promise<RhythmChoice[]> {
  const pick = (raw as AbfallConfig | null)?.rhythm ?? {}
  return (await rhythmChoices(raw)).filter((c) => !c.options.some((o) => o.id === pick[c.bin]))
}

/// The client's `rhythm` as we are willing to store it: a few short strings.
export function cleanRhythm(v: unknown): Record<string, string> | undefined {
  if (!v || typeof v !== 'object' || Array.isArray(v)) return undefined
  const out: Record<string, string> = {}
  for (const [k, x] of Object.entries(v as Record<string, unknown>).slice(0, 6)) {
    if (typeof x === 'string' && k.length <= 60 && x.length <= 80) out[k] = x
  }
  return Object.keys(out).length ? out : undefined
}
