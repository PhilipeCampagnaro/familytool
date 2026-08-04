// abfall.ts — German waste-collection (Abfall) resolver.
//
// Two jobs:
//  1) Setup-time address autocomplete — aggregateTowns() + searchStreets() let the
//     client offer a "type your town / street" picker driven by the vendor's own
//     authoritative data (no hand-labelled region slugs).
//  2) Sync-time event fetch — readAbfallEvents(config) turns a stored address
//     selection into all-day pickup events in the same SyncedEvent shape every other
//     calendar provider returns.
//
// Coverage is a MAP of providers (see abfall_providers.ts), each tagged with a
// vendor "family" = one adapter below. Two kinds of family:
//   - Platform families: ONE API/URL pattern serves many municipalities keyed by a
//     slug, so one adapter yields broad coverage. Live: `regioit` (AbfallNavi JSON
//     API), `awido` (AWIDO Online/Cubefour), `jumomind` (Jumomind/MyMuell app API),
//     `abfallio` (abfall.io/AbfallPlus legacy widget API). The path to
//     near-nationwide coverage is more of these — app.abfallplus.de v3, C-Trace —
//     added the same way (registry + adapter).
//   - Single-provider families: a bespoke feed that covers one authority and does
//     not generalise. `awgbassum` (Landkreis Diepholz incl. Stuhr/Weyhe) is one —
//     a per-street ICS export unique to that site.

import { parseIcs } from "./caldav.ts";
import type { SyncedEvent } from "./calendar.ts";
import { ABFALL_PROVIDERS } from "./abfall_providers.ts";

// What `calendar_connections.config` holds for an abfall connection. It is a
// jsonb column here, not the JSON *string* the old web app kept in `account`,
// so nothing parses it on the way in or out.
export interface AbfallConfig {
  vendor: 'regioit' | 'awido' | 'jumomind' | 'abfallio' | 'ctrace' | 'ics' | 'awgbassum'
  label?: string          // human address label, for display / event location
  // regioit (AbfallNavi):
  region?: string         // host slug, e.g. 'aachen'
  ortId?: number
  strasseId?: number | string   // regioit: numeric; abfallio: form option value
  // house-number refinement, merged onto the config by the client when the user
  // picks one from hausNrList. regioit: numeric id. awido: the addon GUID (it
  // replaces the street oid). jumomind: "nr|areaId" (the area id replaces
  // areaId). abfallio: the f_id_strasse_hnr option value.
  hnrId?: number | string
  // abfallio (abfall.io / AbfallPlus legacy widget):
  key?: string            // per-authority widget key (32-hex)
  kommuneId?: string
  bezirkId?: string       // district step, only where the authority uses one
  // ctrace (C-Trace ASP.NET calendar; also uses service + host + street):
  ort?: string            // Ort= param ('' where the service wants it empty)
  hnr?: string            // Hausnr= param (required by the server)
  icalFile?: string       // 'cal' (default) or 'downloadcal'
  // ics (manual ICS link fallback for unsupported areas):
  url?: string            // the user's pasted ICS/webcal link
  // awido (AWIDO Online / Cubefour):
  client?: string         // customer slug, e.g. 'rmk'
  oid?: string            // street key (GUID) for getData
  // jumomind (Jumomind / MyMuell app API; `service` shared with ctrace):
  service?: string        // jumomind: host id, e.g. 'mymuell'; ctrace: service path
  cityId?: string
  areaId?: string
  // awgbassum (per-street ICS template):
  host?: string           // domain, e.g. 'www.awg-bassum.de'
  city?: string           // ?city= value
  street?: string         // ?street= display value
  slug?: string           // ?slug= value (the site's street key)
}

// Some vendor endpoints (e.g. AWG Bassum's /ajax/ street search) 406 a request
// whose Accept is the bare `application/json` — they only negotiate against a list
// that includes `*/*`. A browser-like Accept + User-Agent satisfies them and is
// harmless to the regio-iT JSON API.
const UA = 'Mozilla/5.0 (compatible; AporahCalendar/1.0)'
const JSON_HEADERS = {
  Accept: 'application/json, text/javascript, */*; q=0.01',
  'User-Agent': UA,
}

async function getJson(url: string, extraHeaders?: Record<string, string>): Promise<unknown> {
  const res = await fetch(url, { headers: { ...JSON_HEADERS, ...extraHeaders } })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  return res.json()
}

// AWIDO Online (Cubefour) — one shared host for every customer; the customer
// slug rides in the URL (note: `client=` is a PATH segment on getPlaces, a query
// param elsewhere — that asymmetry is the vendor's, not ours).
const AWIDO_BASE = 'https://awido.cubefour.de/WebServices/Awido.Service.svc/secure'

// Jumomind serves some responses with broken content-encoding; their own app
// requests identity, so we do too (harmless where it's not needed).
const JUMO_HEADERS = { 'Accept-Encoding': 'identity' }
function jumoUrl(service: string, params: string): string {
  return `https://${service}.jumomind.com/mmapp/api.php?${params}`
}

// ── abfall.io / AbfallPlus (legacy widget API) ───────────────────────────────
//
// Not a JSON API: the embeddable widget's multi-step HTML form. Every step is a
// POST to api.abfall.io?key=&modus=&waction=; the response is an HTML fragment
// whose hidden inputs carry the server-side state (a token pair plus an
// accumulating `f_posts_json[]`) and whose <select> holds the next choice
// (kommune -> optional bezirk -> strasse -> optional house number). We replay
// exactly what the widget posts. `modus` is the widget's public constant.
const ABFALLIO_BASE = 'https://api.abfall.io'
const ABFALLIO_MODUS = 'd6c5855a62cf32a4dadbc2831f0f295f'

function decodeEntities(s: string): string {
  return (s || '')
    .replace(/&quot;/g, '"').replace(/&#0?39;/g, "'")
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&')
}

interface AbfallioPage {
  // Hidden-input form state with dict semantics (a later duplicate name wins),
  // mirroring how the widget itself accumulates state across steps.
  hidden: Map<string, string>
  selects: Map<string, Array<{ value: string; label: string }>>
}

function parseAbfallioPage(html: string): AbfallioPage {
  const hidden = new Map<string, string>()
  for (const m of html.matchAll(/<input[^>]*type="hidden"[^>]*name="([^"]*)"[^>]*value="([^"]*)"/g)) {
    hidden.set(decodeEntities(m[1]), decodeEntities(m[2]))
  }
  const selects = new Map<string, Array<{ value: string; label: string }>>()
  for (const sm of html.matchAll(/<select[^>]*name="([^"]+)"[^>]*>([\s\S]*?)<\/select>/g)) {
    const opts: Array<{ value: string; label: string }> = []
    for (const om of sm[2].matchAll(/<option value="([^"]*)"[^>]*>([^<]*)<\/option>/g)) {
      // value "0" / "" is the "Bitte auswählen..." placeholder
      if (!om[1] || om[1] === '0') continue
      opts.push({ value: om[1], label: decodeEntities(om[2].trim()) })
    }
    selects.set(sm[1], opts)
  }
  return { hidden, selects }
}

async function abfallioPost(
  key: string, waction: string, form: Map<string, string>,
): Promise<AbfallioPage> {
  const body = new URLSearchParams()
  for (const [n, v] of form) body.append(n, v)
  const res = await fetch(
    `${ABFALLIO_BASE}/?key=${key}&modus=${ABFALLIO_MODUS}&waction=${waction}`,
    {
      method: 'POST',
      headers: { 'User-Agent': UA, Accept: '*/*', 'Content-Type': 'application/x-www-form-urlencoded' },
      body: body.toString(),
    },
  )
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  return parseAbfallioPage(await res.text())
}

// A form step: the accumulated hidden state + this step's selections.
function abfallioForm(page: AbfallioPage, set: Record<string, string>): Map<string, string> {
  const form = new Map(page.hidden)
  for (const [n, v] of Object.entries(set)) form.set(n, v)
  return form
}

// Steps accumulate: the next request posts everything sent so far, with the
// response's hidden fields layered on top (that's how `f_posts_json[]` grows
// the server-side state the final export needs).
function abfallioMerge(form: Map<string, string>, page: AbfallioPage): Map<string, string> {
  const next = new Map(form)
  for (const [n, v] of page.hidden) next.set(n, v)
  return next
}

// regio-iT serves each region from a per-service subdomain
// (<slug>-abfallapp.regioit.de), but some regions only resolve on the SHARED
// host (abfallapp.regioit.de/abfall-app-<slug>). Try per-service first, fall back
// to shared, and remember whichever answered so we only pay the retry once.
const _regioitHost = new Map<string, string>()
async function regioitGet(region: string, path: string): Promise<unknown> {
  const cached = _regioitHost.get(region)
  const bases = cached ? [cached] : [
    `https://${region}-abfallapp.regioit.de/abfall-app-${region}/rest`,
    `https://abfallapp.regioit.de/abfall-app-${region}/rest`,
  ]
  let lastErr: unknown
  for (const base of bases) {
    try {
      const val = await getJson(`${base}/${path}`)
      _regioitHost.set(region, base)
      return val
    } catch (e) { lastErr = e }
  }
  throw lastErr
}

// ── Setup-time autocomplete ──────────────────────────────────────────────────

// A selectable town. Carries whatever the vendor family needs to resolve streets.
export interface Town {
  vendor: 'regioit' | 'awido' | 'jumomind' | 'abfallio' | 'ctrace' | 'awgbassum'
  name: string            // display name (town / city)
  provider: string        // provider id, for debugging / de-dup
  region?: string         // regioit
  ortId?: number          // regioit
  client?: string         // awido
  placeKey?: string       // awido (getPlaces key for the town)
  service?: string        // jumomind + ctrace
  cityId?: string         // jumomind
  areaId?: string         // jumomind (city-level area; authoritative when !hasStreets)
  hasStreets?: boolean    // jumomind (false = one schedule for the whole town)
  key?: string            // abfallio
  kommuneId?: string      // abfallio
  bezirkId?: string       // abfallio (set when the "town" is a district/village)
  icalFile?: string       // ctrace
  host?: string           // awgbassum + ctrace
  city?: string           // awgbassum (?city= value) / ctrace (Ort= value, may be '')
}

// Cheap in-memory cache so the provider fan-out only runs once per warm instance.
let _townCache: { at: number; towns: Town[] } | null = null

// Every town across every provider in the map, flattened for a single search box.
// regioit towns are fetched live; awgbassum towns come from the static city list.
// One dead provider never sinks the whole list (allSettled).
export async function aggregateTowns(): Promise<Town[]> {
  if (_townCache && Date.now() - _townCache.at < 6 * 60 * 60 * 1000) return _townCache.towns
  const results = await Promise.allSettled(
    ABFALL_PROVIDERS.map(async (p): Promise<Town[]> => {
      if (p.family === 'regioit' && p.region) {
        const orte = await regioitGet(p.region, 'orte') as Array<{ id: number; name: string }>
        return (Array.isArray(orte) ? orte : []).map((o) => ({
          vendor: 'regioit', name: o.name, provider: p.id, region: p.region, ortId: o.id,
        }))
      }
      if (p.family === 'awido' && p.client) {
        const places = await getJson(
          `${AWIDO_BASE}/getPlaces/client=${p.client}`,
        ) as Array<{ key: string; value: string }>
        return (Array.isArray(places) ? places : []).map((pl) => ({
          vendor: 'awido', name: pl.value, provider: p.id, client: p.client, placeKey: pl.key,
        }))
      }
      if (p.family === 'jumomind' && p.service) {
        const cities = await getJson(
          jumoUrl(p.service, 'r=cities_web'), JUMO_HEADERS,
        ) as Array<{ id: string; name: string; area_id: string; has_streets: boolean }>
        return (Array.isArray(cities) ? cities : []).map((c) => ({
          vendor: 'jumomind', name: c.name, provider: p.id, service: p.service,
          cityId: c.id, areaId: c.area_id, hasStreets: !!c.has_streets,
        }))
      }
      if (p.family === 'abfallio' && p.key) {
        const page = await abfallioPost(p.key, 'init', new Map())
        const kommunen = page.selects.get('f_id_kommune')
        if (kommunen?.length) {
          return kommunen.map((k) => ({
            vendor: 'abfallio', name: k.label, provider: p.id, key: p.key, kommuneId: k.value,
          }))
        }
        const hiddenKommune = page.hidden.get('f_id_kommune')
        if (!hiddenKommune) return []
        const bezirke = page.selects.get('f_id_bezirk')
        if (bezirke?.length) {
          // District-keyed authority (the Prignitz shape): the selectable
          // "towns" are its villages/districts.
          return bezirke.map((b) => ({
            vendor: 'abfallio', name: b.label, provider: p.id,
            key: p.key, kommuneId: hiddenKommune, bezirkId: b.value,
          }))
        }
        // Single municipality with its street list right in the init form.
        return [{
          vendor: 'abfallio', name: p.town || p.name, provider: p.id,
          key: p.key, kommuneId: hiddenKommune,
        }]
      }
      if (p.family === 'ctrace' && p.host && p.service) {
        // Static: one town per service; streets are validated by probe instead
        // of enumerated (see probeCtrace).
        return [{
          vendor: 'ctrace', name: p.town || p.name, provider: p.id,
          host: p.host, service: p.service, icalFile: p.icalFile, city: p.ort ?? '',
        }]
      }
      if (p.family === 'awgbassum' && p.host) {
        return (p.cities || []).map((c) => ({
          vendor: 'awgbassum', name: c, provider: p.id, host: p.host, city: c,
        }))
      }
      return []
    }),
  )
  const towns: Town[] = []
  for (const r of results) if (r.status === 'fulfilled') towns.push(...r.value)
  towns.sort((a, b) => a.name.localeCompare(b.name, 'de'))
  _townCache = { at: Date.now(), towns }
  return towns
}

// A selectable street. `config` is the base connection config (vendor-specific);
// the client merges a label (and an optional house number pick) onto it.
export interface StreetOption {
  name: string
  hausNrList?: Array<{ id: number | string; nr: string }>
  config: AbfallConfig
}

// Streets in one town, narrowed by a typed query (autocomplete). Dispatches by
// the town's vendor family. `hint` is the geocoder's town/district name — some
// vendors subdivide a town into districts (abfallio Bezirke) and the hint says
// which one to walk first.
export async function searchStreets(town: Town, query: string, hint?: string): Promise<StreetOption[]> {
  if (town.vendor === 'regioit') return searchStreetsRegioit(town, query)
  if (town.vendor === 'awido') return searchStreetsAwido(town, query)
  if (town.vendor === 'jumomind') return searchStreetsJumomind(town, query)
  if (town.vendor === 'abfallio') return searchStreetsAbfallio(town, query, hint)
  if (town.vendor === 'awgbassum') return searchStreetsAwgBassum(town, query)
  return []
}

// ── Nationwide address autocomplete (geocoder) ───────────────────────────────
//
// The waste vendors only cover ~35 towns, so we DON'T autocomplete against their
// street lists (that made every uncovered address look broken). Instead we
// autocomplete against all of Germany via Photon (a free, no-key, OpenStreetMap
// geocoder built for type-ahead) so the field always finds the user's street.
// Coverage is checked AFTER selection (resolveAddress), not while typing.

const PHOTON = 'https://photon.komoot.io/api/'

// A geocoded address the user can pick. Opaque to the client except for `label`
// and `prefix`; the client passes the whole object back to resolveAddress().
export interface GeoAddress {
  label: string           // "Weyher Straße 100, 28816 Stuhr"
  street: string
  houseNumber?: string
  town: string            // municipality / city
  postcode?: string
  state?: string          // Bundesland ("Niedersachsen") — lets the client offer the matching school-holiday (Ferien) calendar
  // A bare-postcode suggestion ("28213 Bremen"): not a resolvable address — the
  // client prefills the search field with it so the user keeps typing the street.
  prefix?: boolean
  name?: string           // POI/venue name (worldwide mode only) — a restaurant, office, etc.
}

// OSM boundary names are sometimes administrative jargon rather than the name
// people use ("Stadtgebiet Bremen" -> "Bremen").
function cleanTown(s: string): string {
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
  const res = await fetch(url, { headers: JSON_HEADERS })
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
      label, street, houseNumber: p.housenumber, town, postcode: p.postcode, state: p.state,
      ...(placeName ? { name: placeName } : {}),
    })
  }
  return out
}

// ── Coverage resolution (geocoded address -> vendor config) ───────────────────

// The outcome of checking whether a picked address is served by a known vendor.
export interface ResolveResult {
  supported: boolean
  town: string            // the town we looked up (for the "not supported" message)
  street?: string         // the vendor's street name (canonical spelling)
  // `id` is only numeric for regio-iT. AWIDO sends an addon GUID, abfall.io a
  // form option value and jumomind a packed "nr|areaId" — all strings, and all
  // of them fed straight back into AbfallConfig.hnrId. The old web app declared
  // this `number` and got away with it because nothing typechecked its edge
  // functions; a client that believed the declaration would drop every house
  // number outside regio-iT.
  hausNrList?: Array<{ id: number | string; nr: string }>
  config?: AbfallConfig
}

// Normalise a street name for fuzzy comparison across spelling variants:
// "Weyher Straße" / "Weyher Str." / "Weyher Str. [Brinkum]" -> "weyherstr".
function normStreet(s: string): string {
  return (s || '')
    .toLowerCase()
    .replace(/\[[^\]]*\]/g, ' ')          // drop district tags like "[Brinkum]"
    .replace(/\([^)]*\)/g, ' ')           // ...and "(Altenmittlau)" (jumomind style)
    .replace(/stra(ß|ss)e/g, 'str')
    .replace(/str\.?/g, 'str')
    .replace(/[^a-z0-9äöü]/g, '')
}

// The distinctive part of a street name (drops a trailing Straße/Str. word) so we
// can narrow the vendor's street list before fuzzy-matching. "Weyher Straße" ->
// "weyher", "Hauptstraße" -> "haupt".
function streetStem(s: string): string {
  const stem = (s || '').toLowerCase().replace(/\s*(stra(ß|ss)e|str\.?)\s*$/, '').trim()
  return stem || (s || '').toLowerCase()
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
      const res = await fetch(
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

// Do a covered town's name and a geocoded town's name refer to the same place?
// Exact; or one is a prefix of the other ("Freigericht" / "Freigericht-Bernbach");
// or one appears inside the other AT A WORD BOUNDARY ("Gießen" in "Landkreis
// Gießen").
//
// That last condition is load-bearing, and the old web app was missing it. A
// bare `includes` also matches "Hain" inside "Friedrichshain" — so an address in
// Berlin resolved, via the postcode fallback, to the whole-town bin schedule of
// a village 400 km away. It looked entirely plausible on the calendar: real
// Restmüll and Biotonne dates, all of them wrong. Silently wrong beats visibly
// broken only if nobody ever puts their bins out.
function townMatches(candidate: string, target: string): boolean {
  if (candidate === target) return true
  if (candidate.startsWith(target) || target.startsWith(candidate)) return true
  return containsWord(candidate, target) || containsWord(target, candidate)
}

function containsWord(haystack: string, needle: string): boolean {
  // Below three characters nothing is distinctive enough to be evidence.
  if (needle.length < 3) return false
  for (let from = 0;;) {
    const at = haystack.indexOf(needle, from)
    if (at < 0) return false
    const before = at === 0 ? '' : haystack[at - 1]
    const after = haystack[at + needle.length] ?? ''
    if (!isNameChar(before) && !isNameChar(after)) return true
    from = at + 1
  }
}

function isNameChar(ch: string): boolean {
  return !!ch && /[a-z0-9äöüß]/.test(ch)
}

// One match attempt: find covered towns named like `townName`, then a street in
// one of them matching the geocoded street. Returns null when nothing matches.
async function matchTownAndStreet(
  towns: Town[], townName: string, addr: GeoAddress,
): Promise<ResolveResult | null> {
  const tl = townName.toLowerCase()
  const candidates = towns
    .filter((t) => townMatches(t.name.toLowerCase(), tl))
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
    // C-Trace has no street enumeration; the server itself validates streets
    // (unknown ones error). Probe the ICS export with the geocoded street.
    if (town.vendor === 'ctrace') {
      const probed = await probeCtrace(town, addr).catch(() => null)
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
      // AWIDO house numbers live behind an extra per-street call; fetch them
      // only for the one matched street. No addons = street-level schedule.
      if (best.config.vendor === 'awido' && best.config.oid) {
        try {
          const addons = await getJson(
            `${AWIDO_BASE}/getStreetAddons/${best.config.oid}?client=${best.config.client}`,
          ) as Array<{ key: string; value: string }>
          hausNrList = (Array.isArray(addons) ? addons : [])
            .filter((a) => (a.value || '').trim())
            .map((a) => ({ id: a.key, nr: a.value }))
        } catch { /* street-level schedule is fine */ }
      }
      // abfall.io house numbers appear after a street-set step; fetch only for
      // the matched street. District chains don't use them — skip those.
      if (best.config.vendor === 'abfallio' && best.config.key && !best.config.bezirkId) {
        try {
          const init = await abfallioPost(best.config.key, 'init', new Map())
          const page = await abfallioPost(best.config.key, 'auswahl_strasse_set',
            abfallioForm(init, {
              f_id_kommune: best.config.kommuneId || '',
              f_id_strasse: String(best.config.strasseId ?? ''),
            }))
          const hnrs = page.selects.get('f_id_strasse_hnr') || []
          if (hnrs.length) hausNrList = hnrs.map((h) => ({ id: h.value, nr: h.label }))
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

async function searchStreetsRegioit(town: Town, query: string): Promise<StreetOption[]> {
  if (!town.region || !town.ortId) return []
  const list = await regioitGet(town.region, `orte/${town.ortId}/strassen`) as Array<{
    id: number; name: string; hausNrList?: Array<{ id: number; nr: string }>
  }>
  const q = (query || '').trim().toLowerCase()
  return (Array.isArray(list) ? list : [])
    .filter((s) => !q || (s.name || '').toLowerCase().includes(q))
    .slice(0, 40)
    .map((s) => ({
      name: s.name,
      hausNrList: (s.hausNrList || []).map((h) => ({ id: h.id, nr: h.nr })),
      config: { vendor: 'regioit', region: town.region, ortId: town.ortId, strasseId: s.id },
    }))
}

async function searchStreetsAwido(town: Town, query: string): Promise<StreetOption[]> {
  if (!town.client || !town.placeKey) return []
  const list = await getJson(
    `${AWIDO_BASE}/getGroupedStreets/${town.placeKey}?client=${town.client}`,
  ) as Array<{ key: string; value: string }>
  const q = (query || '').trim().toLowerCase()
  const tn = town.name.trim().toLowerCase()
  return (Array.isArray(list) ? list : [])
    // Keep a town-named entry even when the query misses it — that's the
    // vendor's "whole town, one schedule" form, which resolveAddress accepts.
    .filter((s) => {
      const n = (s.value || '').toLowerCase()
      return !q || n.includes(q) || n === tn
    })
    .slice(0, 40)
    .map((s) => ({
      name: s.value,
      config: { vendor: 'awido', client: town.client, oid: s.key },
    }))
}

async function searchStreetsJumomind(town: Town, query: string): Promise<StreetOption[]> {
  if (!town.service || !town.cityId) return []
  // Whole-town schedule: no street list exists; the city-level area id IS the
  // schedule key. Surface it as one pseudo-street named like the town.
  if (!town.hasStreets) {
    return [{
      name: town.name,
      config: {
        vendor: 'jumomind', service: town.service,
        cityId: town.cityId, areaId: town.areaId,
      },
    }]
  }
  const list = await getJson(
    jumoUrl(town.service, `r=streets&city_id=${encodeURIComponent(town.cityId)}`),
    JUMO_HEADERS,
  ) as Array<{ name: string; area_id: string; houseNumbers?: Array<[string, string]> }>
  const q = (query || '').trim().toLowerCase()
  return (Array.isArray(list) ? list : [])
    .filter((s) => !q || (s.name || '').toLowerCase().includes(q))
    .slice(0, 40)
    .map((s) => ({
      name: s.name,
      // A street can span collection zones; each house number then carries its
      // own area id. Encode both into the pick id ("nr|areaId") — unique per
      // number — and readJumomind() decodes the area id back out of hnrId.
      hausNrList: (s.houseNumbers || []).map((h) => ({ id: `${h[0]}|${h[1]}`, nr: h[0] })),
      config: {
        vendor: 'jumomind', service: town.service,
        cityId: town.cityId, areaId: s.area_id,
      },
    }))
}

async function searchStreetsAbfallio(town: Town, query: string, hint?: string): Promise<StreetOption[]> {
  if (!town.key || !town.kommuneId) return []
  const init = await abfallioPost(town.key, 'init', new Map())
  const q = (query || '').trim().toLowerCase()

  const toOptions = (page: AbfallioPage, bezirkId?: string): StreetOption[] => {
    const list = page.selects.get('f_id_strasse') || []
    return list
      // "alle Straßen" = one schedule for the whole area; surface it under the
      // town's own name so the whole-town fallback matches it.
      .map((s) => ({ ...s, label: /^alle stra(ß|ss)en/i.test(s.label) ? town.name : s.label }))
      .filter((s) => !q || s.label.toLowerCase().includes(q) || s.label === town.name)
      .slice(0, 40)
      .map((s) => ({
        name: s.label,
        config: {
          vendor: 'abfallio' as const, key: town.key, kommuneId: town.kommuneId,
          ...(bezirkId ? { bezirkId } : {}), strasseId: s.value,
        },
      }))
  }

  // District-keyed town (Prignitz shape): one bezirk step straight from init.
  if (town.bezirkId) {
    const page = await abfallioPost(town.key, 'auswahl_bezirk_set',
      abfallioForm(init, { f_id_kommune: town.kommuneId, f_id_bezirk: town.bezirkId }))
    return toOptions(page, town.bezirkId)
  }

  // Streets right in the init form (single-municipality keys).
  if (init.selects.get('f_id_strasse')?.length) return toOptions(init)

  // Multi-kommune key: select the town, then either streets or districts.
  const page = await abfallioPost(town.key, 'auswahl_kommune_set',
    abfallioForm(init, { f_id_kommune: town.kommuneId }))
  const bezirke = page.selects.get('f_id_bezirk')
  if (!bezirke?.length || page.selects.get('f_id_strasse')?.length) return toOptions(page)

  // The kommune subdivides into districts and the address doesn't say which.
  // Walk them best-first: the geocoder's district hint, then "Innenbereich"
  // (the built-up area = the overwhelmingly common case), then form order.
  const h = (hint || '').trim().toLowerCase()
  const score = (b: { label: string }) => {
    const l = b.label.toLowerCase()
    if (h && (l.includes(h) || h.includes(l))) return 2
    if (/innen/.test(l)) return 1
    return 0
  }
  const ranked = [...bezirke].sort((a, b) => score(b) - score(a))
  const out: StreetOption[] = []
  for (const bz of ranked.slice(0, 12)) {
    try {
      const bp = await abfallioPost(town.key, 'auswahl_bezirk_set',
        abfallioForm(init, { f_id_kommune: town.kommuneId, f_id_bezirk: bz.value }))
      out.push(...toOptions(bp, bz.value))
    } catch { /* skip a dead district */ }
    if (out.length >= 40) break
  }
  return out.slice(0, 40)
}

async function searchStreetsAwgBassum(town: Town, query: string): Promise<StreetOption[]> {
  if (!town.host || !town.city) return []
  const url = `https://${town.host}/ajax/?f=streets&c=${encodeURIComponent(town.city)}`
  const list = await getJson(url) as Array<{ display: string; data: string }>
  const q = (query || '').trim().toLowerCase()
  return (Array.isArray(list) ? list : [])
    .filter((s) => !q || (s.display || '').toLowerCase().includes(q))
    .slice(0, 40)
    .map((s) => ({
      name: s.display,
      config: {
        vendor: 'awgbassum', host: town.host, city: town.city,
        street: s.display, slug: s.data,
      },
    }))
}

// ── Sync-time event fetch ────────────────────────────────────────────────────

export async function readAbfallEvents(raw: unknown): Promise<SyncedEvent[]> {
  // `config` is jsonb, so it arrives as an object. A connection saved before its
  // address was resolved has no vendor at all — that is a reconnect, not a
  // transient failure, and the caller turns it into "Bitte erneut verbinden."
  if (!raw || typeof raw !== 'object') throw new Error('reconnect_required')
  const cfg = raw as AbfallConfig
  if (cfg.vendor === 'regioit') return readRegioit(cfg)
  if (cfg.vendor === 'awido') return readAwido(cfg)
  if (cfg.vendor === 'jumomind') return readJumomind(cfg)
  if (cfg.vendor === 'abfallio') return readAbfallio(cfg)
  if (cfg.vendor === 'ctrace') return readCtrace(cfg)
  if (cfg.vendor === 'ics') return readIcsUrl(cfg)
  if (cfg.vendor === 'awgbassum') return readAwgBassum(cfg)
  throw new Error('reconnect_required')
}

async function readRegioit(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  if (!cfg.region || !cfg.strasseId) throw new Error('reconnect_required')
  // A house number gives the most precise schedule; the street is the fallback.
  const scope = cfg.hnrId ? `hausnummern/${cfg.hnrId}` : `strassen/${cfg.strasseId}`
  const [fraktionen, termine] = await Promise.all([
    regioitGet(cfg.region, 'fraktionen') as Promise<Array<{ id: number; name: string }>>,
    regioitGet(cfg.region, `${scope}/termine`) as Promise<Array<{
      id?: number; datum?: string; bezirk?: { fraktionId?: number }
    }>>,
  ])
  const fname = new Map<number, string>()
  for (const f of (Array.isArray(fraktionen) ? fraktionen : [])) fname.set(f.id, f.name)

  const events: SyncedEvent[] = []
  for (const t of (Array.isArray(termine) ? termine : [])) {
    if (!t?.datum) continue
    const start = new Date(`${t.datum}T00:00:00Z`)
    if (isNaN(start.getTime())) continue
    // All-day events use an exclusive end (like Google's date-only end): +1 day.
    const end = new Date(start)
    end.setUTCDate(end.getUTCDate() + 1)
    const fid = t.bezirk?.fraktionId
    const title = (fid != null && fname.get(fid)) || 'Abfuhr'
    // strasseId/hnrId scope the uid: termin ids are shared district-wide, so two
    // family addresses in one region would otherwise collide (and their events
    // would wrongly merge into one on the calendar).
    events.push({
      uid: `abfall:regioit:${cfg.region}:${cfg.strasseId}:${cfg.hnrId ?? ''}:${t.id ?? `${t.datum}:${fid}`}`,
      title,
      notes: null,
      location: cfg.label ?? null,
      startsAt: start.toISOString(),
      endsAt: end.toISOString(),
      allDay: true,
    })
  }
  return events
}

// AWIDO: one getData call returns the full calendar year as JSON — pickup dates
// (dt=YYYYMMDD, fr=fraction codes) plus the fraction-code -> name map (fracts).
// Entries with fr=null are public holidays, not pickups. A picked house number
// (hnrId = addon GUID) replaces the street oid. A few clients don't serve the
// JSON payload at all; for those we fall back to the official ICS export.
async function readAwido(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  if (!cfg.client || !cfg.oid) throw new Error('reconnect_required')
  const oid = (typeof cfg.hnrId === 'string' && cfg.hnrId) || cfg.oid
  let data: {
    fracts?: Array<{ snm: string; nm: string }>
    calendar?: Array<{ dt?: string; fr?: string[] | null }>
  }
  try {
    data = await getJson(
      `${AWIDO_BASE}/getData/${oid}?fractions=&client=${cfg.client}`,
    ) as typeof data
  } catch {
    return readAwidoIcs(cfg, oid)
  }
  const fname = new Map<string, string>()
  for (const f of (data.fracts || [])) fname.set(f.snm, f.nm)

  const events: SyncedEvent[] = []
  for (const item of (data.calendar || [])) {
    if (!item?.dt || !Array.isArray(item.fr) || !item.fr.length) continue
    const iso = `${item.dt.slice(0, 4)}-${item.dt.slice(4, 6)}-${item.dt.slice(6, 8)}`
    const start = new Date(`${iso}T00:00:00Z`)
    if (isNaN(start.getTime())) continue
    const end = new Date(start)
    end.setUTCDate(end.getUTCDate() + 1)
    for (const fr of item.fr) {
      events.push({
        uid: `abfall:awido:${cfg.client}:${oid}:${item.dt}:${fr}`,
        title: fname.get(fr) || fr || 'Abfuhr',
        notes: null,
        location: cfg.label ?? null,
        startsAt: start.toISOString(),
        endsAt: end.toISOString(),
        allDay: true,
      })
    }
  }
  return events
}

// Fallback for AWIDO clients without the JSON payload: the per-oid ICS export,
// fetched for this year + next (mirrors the awgbassum year handling).
async function readAwidoIcs(cfg: AbfallConfig, oid: string): Promise<SyncedEvent[]> {
  const thisYear = new Date().getUTCFullYear()
  const start = new Date(Date.UTC(thisYear - 1, 0, 1))
  const end = new Date(Date.UTC(thisYear + 2, 0, 1))
  const out: SyncedEvent[] = []
  const seen = new Set<string>()
  for (const year of [thisYear, thisYear + 1]) {
    // An empty reminder= makes the endpoint answer with an HTML page instead of
    // ICS; the widget always sends a concrete value, so we mirror it.
    const url = `https://awido.cubefour.de/Customer/${cfg.client}/KalenderICS.aspx`
      + `?oid=${encodeURIComponent(oid)}&jahr=${year}&fraktionen=&reminder=${encodeURIComponent('-1.17:00')}`
    let ics: string
    try {
      const res = await fetch(url, { headers: { Accept: 'text/calendar', 'User-Agent': UA } })
      if (!res.ok) continue
      ics = await res.text()
    } catch { continue }
    if (!ics.includes('BEGIN:VEVENT')) continue
    for (const ev of parseIcs(ics, start, end)) {
      const key = `${ev.startsAt.slice(0, 10)}:${ev.title}`
      if (seen.has(key)) continue
      seen.add(key)
      out.push({
        ...ev,
        uid: `abfall:awido:${cfg.client}:${oid}:${key}`,
        notes: null,
        location: cfg.label ?? ev.location ?? null,
      })
    }
  }
  return out
}

// Jumomind: one dates call returns upcoming pickups with human titles baked in.
// The schedule key is (city_id, area_id); a picked house number refines the
// area id (hnrId = "nr|areaId" — see searchStreetsJumomind).
async function readJumomind(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  if (!cfg.service || !cfg.cityId) throw new Error('reconnect_required')
  let areaId = cfg.areaId
  if (typeof cfg.hnrId === 'string' && cfg.hnrId.includes('|')) {
    areaId = cfg.hnrId.slice(cfg.hnrId.lastIndexOf('|') + 1)
  }
  if (areaId == null || areaId === '') throw new Error('reconnect_required')
  const list = await getJson(
    jumoUrl(cfg.service, `r=dates/0&city_id=${encodeURIComponent(cfg.cityId)}`
      + `&area_id=${encodeURIComponent(areaId)}&ws=3`),
    JUMO_HEADERS,
  ) as Array<{ title?: string; day?: string; trash_name?: string }>

  const events: SyncedEvent[] = []
  for (const t of (Array.isArray(list) ? list : [])) {
    if (!t?.day) continue
    const start = new Date(`${t.day}T00:00:00Z`)
    if (isNaN(start.getTime())) continue
    const end = new Date(start)
    end.setUTCDate(end.getUTCDate() + 1)
    const title = t.title || t.trash_name || 'Abfuhr'
    events.push({
      uid: `abfall:jumomind:${cfg.service}:${cfg.cityId}:${areaId}:${t.day}:${t.trash_name || title}`,
      title,
      notes: null,
      location: cfg.label ?? null,
      startsAt: start.toISOString(),
      endsAt: end.toISOString(),
      allDay: true,
    })
  }
  return events
}

// ── C-Trace (ASP.NET calendar; Bremen et al.) ────────────────────────────────
//
// The app redirects to a session-scoped URL, then serves an ICS export from
// plain-text params (Ort/Gemeinde/Strasse/Hausnr) — no ID lookups. It rejects
// unknown streets, which is what makes probe-based coverage validation sound.

// The export wants an explicit waste-type filter; 0..299 = everything.
const CTRACE_ALL_TYPES = Array.from({ length: 300 }, (_, i) => i).join('|')

async function ctraceFetchIcs(cfg: AbfallConfig): Promise<string> {
  if (!cfg.host || !cfg.service) throw new Error('reconnect_required')
  const base = `https://${cfg.host}/${cfg.service}`
  // First hit redirects to /<service>/(S(<session>))/... — grab the session.
  const r0 = await fetch(`${base}/Abfallkalender`, {
    redirect: 'manual', headers: { 'User-Agent': UA },
  })
  await r0.body?.cancel()
  const loc = r0.headers.get('location') || ''
  const sess = loc.match(/\(S\([^)]*\)\)/)?.[0] || ''
  const params = new URLSearchParams({
    Ort: cfg.ort || '',
    Gemeinde: cfg.ort || '',
    Strasse: cfg.street || '',
    Hausnr: cfg.hnr || '',
    Abfall: CTRACE_ALL_TYPES,
  })
  const res = await fetch(
    `${base}${sess ? `/${sess}` : ''}/abfallkalender/${cfg.icalFile || 'cal'}?${params}`,
    { headers: { 'User-Agent': UA, Accept: 'text/calendar, */*' } },
  )
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  return (await res.text()).replace(/^﻿/, '')
}

// Coverage probe: try the export with the geocoded street. Events back = the
// street exists and this IS its schedule; an error/empty = not this provider.
// The server requires a house number; when the geocoder has none, "1" works.
async function probeCtrace(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  if (!addr.street) return null
  const tries = [...new Set([(addr.houseNumber || '1').trim() || '1', '1'])]
  for (const hnr of tries) {
    const config: AbfallConfig = {
      vendor: 'ctrace', host: town.host, service: town.service,
      icalFile: town.icalFile, ort: town.city ?? '', street: addr.street, hnr,
    }
    try {
      const ics = await ctraceFetchIcs(config)
      if (ics.includes('BEGIN:VEVENT')) {
        return { supported: true, town: town.name, street: addr.street, config }
      }
    } catch { /* try the next house number */ }
  }
  return null
}

// Sync-time reader. Event titles come as "Abfuhr: Restmüll" — strip the prefix
// so classifyWaste sees the bin name.
async function readCtrace(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  if (!cfg.street) throw new Error('reconnect_required')
  const ics = await ctraceFetchIcs(cfg)
  if (!ics.includes('BEGIN:VEVENT')) return []
  const thisYear = new Date().getUTCFullYear()
  const start = new Date(Date.UTC(thisYear - 1, 0, 1))
  const end = new Date(Date.UTC(thisYear + 2, 0, 1))
  const out: SyncedEvent[] = []
  const seen = new Set<string>()
  for (const ev of parseIcs(ics, start, end)) {
    const title = ev.title.replace(/^Abfuhr:\s*/i, '') || 'Abfuhr'
    const dayKey = `${ev.startsAt.slice(0, 10)}:${title}`
    if (seen.has(dayKey)) continue
    seen.add(dayKey)
    out.push({
      ...ev,
      uid: `abfall:ctrace:${cfg.service}:${cfg.ort || ''}:${cfg.street}:${dayKey}`,
      title,
      notes: null,
      location: cfg.label ?? ev.location ?? null,
    })
  }
  return out
}

// ── Manual ICS link (fallback for unsupported areas) ─────────────────────────

// Accept http(s) and webcal:// (the subscription scheme waste sites often use);
// reject anything that could point at a private host.
export function normalizeIcsUrl(raw?: string): string | null {
  const s = (raw || '').trim().replace(/^webcal:\/\//i, 'https://')
  if (!s) return null
  let u: URL
  try { u = new URL(s) } catch { return null }
  if (u.protocol !== 'https:' && u.protocol !== 'http:') return null
  const h = u.hostname.toLowerCase()
  if (h === 'localhost' || h.endsWith('.local') || h.endsWith('.internal')) return null
  if (/^\d+\.\d+\.\d+\.\d+$/.test(h) || h.includes(':')) return null // IP literals (v4/v6)
  return u.href
}

// Is a resolved IP in a private / loopback / link-local / reserved range? The
// literal checks in normalizeIcsUrl catch a URL that IS an IP; this catches a
// hostname that RESOLVES to one (the real SSRF vector — a public-looking domain
// pointing at 169.254.169.254, 127.0.0.1, 10.x, etc.).
function isPrivateIp(ip: string): boolean {
  const s = ip.toLowerCase()
  // IPv4-mapped IPv6 (::ffff:10.0.0.1) — check the embedded v4.
  const mapped = s.match(/^::ffff:(\d+\.\d+\.\d+\.\d+)$/)
  const v4 = mapped ? mapped[1] : (/^\d+\.\d+\.\d+\.\d+$/.test(s) ? s : null)
  if (v4) {
    const [a, b] = v4.split('.').map(Number)
    if (a === 10 || a === 127 || a === 0) return true
    if (a === 172 && b >= 16 && b <= 31) return true
    if (a === 192 && b === 168) return true
    if (a === 169 && b === 254) return true      // link-local (cloud metadata)
    if (a === 100 && b >= 64 && b <= 127) return true // CGNAT
    if (a >= 224) return true                     // multicast / reserved
    return false
  }
  // IPv6
  if (s === '::1' || s === '::') return true      // loopback / unspecified
  if (s.startsWith('fc') || s.startsWith('fd')) return true // unique-local fc00::/7
  if (s.startsWith('fe8') || s.startsWith('fe9') || s.startsWith('fea') || s.startsWith('feb')) return true // link-local fe80::/10
  return false
}

// SSRF guard for user-pasted ICS links: resolve the hostname and refuse if it
// points at a private/reserved address. Fails OPEN if the resolver itself is
// unavailable (the literal checks in normalizeIcsUrl already stopped the obvious
// cases) so a resolver hiccup never breaks a legitimate connection.
async function assertPublicHost(hostname: string): Promise<void> {
  let ips: string[] = []
  try {
    const [a, aaaa] = await Promise.allSettled([
      Deno.resolveDns(hostname, 'A'),
      Deno.resolveDns(hostname, 'AAAA'),
    ])
    if (a.status === 'fulfilled') ips = ips.concat(a.value)
    if (aaaa.status === 'fulfilled') ips = ips.concat(aaaa.value)
  } catch {
    return // resolver unavailable — don't hard-fail a real connection
  }
  if (ips.some(isPrivateIp)) throw new Error('reconnect_required')
}

// Read a user-pasted ICS link. Kept inside the abfall family (vendor 'ics') so
// the pickup overlay, bin colours, and sync flow all apply unchanged. Also
// used by abfall-lookup's ics-check action to validate the link at setup time.
// Tiny stable fingerprint (djb2) so two manual ICS links in one family never
// share event uids (colliding uids would merge their events into one).
function shortHash(s: string): string {
  let h = 5381
  for (let i = 0; i < s.length; i++) h = ((h * 33) ^ s.charCodeAt(i)) >>> 0
  return h.toString(36)
}

export async function readIcsUrl(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const url = normalizeIcsUrl(cfg.url)
  if (!url) throw new Error('reconnect_required')
  await assertPublicHost(new URL(url).hostname)
  const res = await fetch(url, { headers: { Accept: 'text/calendar, */*', 'User-Agent': UA } })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const ics = (await res.text()).replace(/^﻿/, '')
  if (!ics.includes('BEGIN:VEVENT')) return []
  const thisYear = new Date().getUTCFullYear()
  const start = new Date(Date.UTC(thisYear - 1, 0, 1))
  const end = new Date(Date.UTC(thisYear + 2, 0, 1))
  const out: SyncedEvent[] = []
  const seen = new Set<string>()
  for (const ev of parseIcs(ics, start, end)) {
    const title = ev.title.replace(/^Abfuhr:\s*/i, '')
    const dayKey = `${ev.startsAt.slice(0, 10)}:${title}`
    if (seen.has(dayKey)) continue
    seen.add(dayKey)
    out.push({
      ...ev,
      uid: `abfall:ics:${shortHash(url)}:${dayKey}`,
      title,
      notes: null,
      location: cfg.label ?? ev.location ?? null,
    })
  }
  return out
}

// abfall.io: replay the widget's form steps (init -> optional bezirk/strasse
// steps so the server-side `f_posts_json[]` state accumulates) and finish with
// waction=export_ics for a rolling window, then parse the ICS.
async function readAbfallio(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  if (!cfg.key || !cfg.kommuneId || cfg.strasseId == null) throw new Error('reconnect_required')
  const init = await abfallioPost(cfg.key, 'init', new Map())
  let form = abfallioForm(init, { f_id_kommune: cfg.kommuneId })
  if (cfg.bezirkId) {
    form.set('f_id_bezirk', cfg.bezirkId)
    form = abfallioMerge(form, await abfallioPost(cfg.key, 'auswahl_bezirk_set', form))
    form.set('f_id_strasse', String(cfg.strasseId))
    form = abfallioMerge(form, await abfallioPost(cfg.key, 'auswahl_strasse_set', form))
    if (cfg.hnrId != null && cfg.hnrId !== '') {
      form.set('f_id_strasse_hnr', String(cfg.hnrId))
      form = abfallioMerge(form, await abfallioPost(cfg.key, 'auswahl_hnr_set', form))
    }
  } else {
    form.set('f_id_strasse', String(cfg.strasseId))
    if (cfg.hnrId != null && cfg.hnrId !== '') form.set('f_id_strasse_hnr', String(cfg.hnrId))
  }
  form.set('f_abfallarten_index_max', '0')
  form.set('f_abfallarten', '')
  const now = new Date()
  const from = new Date(now); from.setUTCDate(from.getUTCDate() - 30)
  const to = new Date(now); to.setUTCDate(to.getUTCDate() + 365)
  const ymd = (d: Date) => d.toISOString().slice(0, 10).replace(/-/g, '')
  form.set('f_zeitraum', `${ymd(from)}-${ymd(to)}`)

  const body = new URLSearchParams()
  for (const [n, v] of form) body.append(n, v)
  const res = await fetch(
    `${ABFALLIO_BASE}/?key=${cfg.key}&modus=${ABFALLIO_MODUS}&waction=export_ics`,
    {
      method: 'POST',
      headers: { 'User-Agent': UA, Accept: '*/*', 'Content-Type': 'application/x-www-form-urlencoded' },
      body: body.toString(),
    },
  )
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  let ics = await res.text()
  // The export can prepend HTML warning lines (e.g. about extra waste-type
  // radio buttons some authorities configure); strip anything tag-like.
  if (/<b/i.test(ics)) ics = ics.replace(/<br[^\n]*|<b[^\n]*/gi, '\r')
  if (!ics.includes('BEGIN:VEVENT')) return []

  const winStart = new Date(Date.UTC(now.getUTCFullYear() - 1, 0, 1))
  const winEnd = new Date(Date.UTC(now.getUTCFullYear() + 2, 0, 1))
  const out: SyncedEvent[] = []
  const seen = new Set<string>()
  for (const ev of parseIcs(ics, winStart, winEnd)) {
    const dayKey = `${ev.startsAt.slice(0, 10)}:${ev.title}`
    if (seen.has(dayKey)) continue
    seen.add(dayKey)
    out.push({
      ...ev,
      uid: `abfall:abfallio:${cfg.key}:${cfg.kommuneId}:${cfg.strasseId}:${dayKey}`,
      notes: null,
      location: cfg.label ?? ev.location ?? null,
    })
  }
  return out
}

// AWG Bassum publishes a per-street ICS per calendar year. Fetch this year + next
// so the overlay always looks ahead, parse with the shared ICS parser, and de-dup
// across the two feeds (they overlap at the year boundary).
async function readAwgBassum(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  if (!cfg.host || !cfg.city || !cfg.slug) throw new Error('reconnect_required')
  const thisYear = new Date().getUTCFullYear()
  const years = [thisYear, thisYear + 1]
  const start = new Date(Date.UTC(thisYear - 1, 0, 1))
  const end = new Date(Date.UTC(thisYear + 2, 0, 1))
  const out: SyncedEvent[] = []
  const seen = new Set<string>()
  for (const year of years) {
    const url = `https://${cfg.host}/abfuhrkalender.html?year=${year}`
      + `&city=${encodeURIComponent(cfg.city)}`
      + `&street=${encodeURIComponent(cfg.street ?? '')}`
      + `&slug=${encodeURIComponent(cfg.slug)}&ical=1`
    let ics: string
    try {
      const res = await fetch(url, { headers: { Accept: 'text/calendar', 'User-Agent': UA } })
      if (!res.ok) continue
      ics = await res.text()
    } catch { continue }
    if (!ics.includes('BEGIN:VEVENT')) continue
    for (const ev of parseIcs(ics, start, end)) {
      const day = ev.startsAt.slice(0, 10)
      const key = `${day}:${ev.title}`
      if (seen.has(key)) continue
      seen.add(key)
      // city+slug scope the uid: every Landkreis-Diepholz address shares the same
      // host, so two family addresses would otherwise collide and merge.
      out.push({
        ...ev,
        uid: `abfall:awgbassum:${cfg.host}:${cfg.city}:${cfg.slug}:${key}`,
        notes: null,
        location: cfg.label ?? ev.location ?? null,
      })
    }
  }
  return out
}
