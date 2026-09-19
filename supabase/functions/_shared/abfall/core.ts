// abfall/core.ts — the vocabulary every vendor adapter shares.
//
// Types, the HTTP helpers, the German street/town normalisers, and the
// VendorAdapter contract. A vendor module imports from here and from nothing else
// in this directory, so adding a vendor never means editing a file another vendor
// depends on.

import type { AbfallProvider } from "../abfall_providers.ts";
import { parseIcs } from "../caldav.ts";
import type { SyncedEvent } from "../calendar.ts";
import { fetchUntrusted, fetchWithTimeout } from "../net.ts";

export { fetchUntrusted, fetchWithTimeout, parseIcs };
export type { AbfallProvider, SyncedEvent };

// A house number a street can be split into, as the client's dropdown wants it.
export interface HausNr { id: string | number; nr: string }

// What `calendar_connections.config` holds for an abfall connection. It is a
// jsonb column here, not the JSON *string* the old web app kept in `account`,
// so nothing parses it on the way in or out.
export interface AbfallConfig {
  vendor: 'regioit' | 'awido' | 'jumomind' | 'abfallio' | 'ctrace' | 'ics' | 'awgbassum' | 'bsr' | 'fes' | 'awm' | 'awbkoeln' | 'srh'
    | 'awsstuttgart' | 'awista' | 'srl' | 'athos' | 'abfallplus' | 'srdd' | 'aha' | 'awgwuppertal' | 'insertit' | 'abki' | 'wuerzburg' | 'avea' | 'oldenburg'
    | 'art' | 'waswob' | 'albabs' | 'elw' | 'fuerth' | 'heilbronn' | 'abis' | 'enni' | 'muellmax' | 'hws' | 'ksj' | 'tsk' | 'hausmuell' | 'sab' | 'swp' | 'osb' | 'meinabfall' | 'geb' | 'mags' | 'citko' | 'zah' | 'heidelberg' | 'beg' | 'sro' | 'ead'
  label?: string          // human address label, for display / event location
  // regioit (AbfallNavi):
  region?: string         // host slug, e.g. 'aachen'
  ortId?: number
  strasseId?: number | string   // regioit: numeric; abfallio: form option value
  // house-number refinement, merged onto the config by the client when the user
  // picks one from hausNrList. regioit: numeric id. awido: the addon GUID (it
  // replaces the street oid). jumomind: "nr|areaId" (the area id replaces
  // areaId). abfallio: the f_id_strasse_hnr option value. bsr: the AddrKey of
  // the house, which is the whole address as far as BSR is concerned. fes: the
  // numeric address id frankfurtplus.de hangs its ICS off. awista: the uuid
  // AWISTA Kommunal's calendar page and ICS are both addressed by.
  hnrId?: number | string
  // abfallio (abfall.io / AbfallPlus legacy widget):
  key?: string            // per-authority widget key (32-hex)
  kommuneId?: string
  bezirkId?: string       // district step, only where the authority uses one
  // awbkoeln (AWB Köln): `strasseId`/`hnr` are the **Stellplatz** the calendar is
  // keyed on, `street` the household's own street, and `stellplatz` the written
  // address of the collection point when it is not their own door.
  stellplatz?: string
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
  service?: string        // jumomind: host id, e.g. 'ingol'; ctrace: service path
  cityId?: string
  areaId?: string
  // awgbassum (per-street ICS template):
  host?: string           // domain, e.g. 'www.awg-bassum.de'
  city?: string           // ?city= value
  street?: string         // ?street= display value
  slug?: string           // ?slug= value (the site's street key)
  // aha (Region Hannover): `city` is the Gemeinde, `hnr` the number, `zusatz`
  // its letter, `hnrId` "<strasse option>|<ladeort>".
  zusatz?: string
  // The household's answer to "how often is this bin emptied?", keyed by the
  // bin as the vendor names it: { "Restmüll": "2-wöchentlich" }. Only where the
  // vendor publishes every rhythm side by side and leaves the household to pick
  // (see RhythmChoice). Part of the feed key, so neighbours on different
  // rhythms get different feeds.
  rhythm?: Record<string, string>
}

// Some vendor endpoints (e.g. AWG Bassum's /ajax/ street search) 406 a request
// whose Accept is the bare `application/json` — they only negotiate against a list
// that includes `*/*`. A browser-like Accept + User-Agent satisfies them and is
// harmless to the regio-iT JSON API.
export const UA = 'Mozilla/5.0 (compatible; AporahCalendar/1.0)'

export const JSON_HEADERS = {
  Accept: 'application/json, text/javascript, */*; q=0.01',
  'User-Agent': UA,
}

export async function getJson(url: string, extraHeaders?: Record<string, string>): Promise<unknown> {
  const res = await fetchWithTimeout(url, { headers: { ...JSON_HEADERS, ...extraHeaders } })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  return res.json()
}

export function decodeEntities(s: string): string {
  return (s || '')
    .replace(/&quot;/g, '"').replace(/&#0?39;/g, "'")
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&')
}

// A selectable town. Carries whatever the vendor family needs to resolve streets.
export interface Town {
  vendor: 'regioit' | 'awido' | 'jumomind' | 'abfallio' | 'ctrace' | 'awgbassum' | 'bsr' | 'fes' | 'awm' | 'awbkoeln' | 'srh'
    | 'awsstuttgart' | 'awista' | 'srl' | 'athos' | 'abfallplus' | 'srdd' | 'aha' | 'awgwuppertal' | 'insertit' | 'abki' | 'wuerzburg' | 'avea' | 'oldenburg'
    | 'art' | 'waswob' | 'albabs' | 'elw' | 'fuerth' | 'heilbronn' | 'abis' | 'enni' | 'muellmax' | 'hws' | 'ksj' | 'tsk' | 'hausmuell' | 'sab' | 'swp' | 'osb' | 'meinabfall' | 'geb' | 'mags' | 'citko' | 'zah' | 'heidelberg' | 'beg' | 'sro' | 'ead'
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

// A selectable street. `config` is the base connection config (vendor-specific);
// the client merges a label (and an optional house number pick) onto it.
export interface StreetOption {
  name: string
  hausNrList?: Array<{ id: number | string; nr: string }>
  config: AbfallConfig
}

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
  // The vendor plans per house and the address came without a number (or with
  // one it does not know): `config` is the street and cannot be read yet. The
  // client asks for the number instead of connecting a calendar that would
  // fail on its first sync — or, worse, show the neighbour's bins.
  needsHouseNumber?: boolean
  // The town is served, but by a provider we may not fetch from (`upload` in
  // abfall_providers.ts): `supported` is false, nothing was asked of the
  // vendor, and the client sends the household to the file upload. `page` is
  // where the town hands out its calendar, when we know it.
  uploadOnly?: boolean
  page?: string
}

// Fold a name to plain a–z so that two spellings of the same street compare
// equal. Every letter a German street name can carry has two written forms and
// the vendor and the geocoder rarely pick the same one: ä/ae, ö/oe, ü/ue, ß/ss,
// and the accents on the handful named after people (Francéstraße, Désirée-,
// Gluckstraße/Glückstraße). Deleting them instead — which is what the bare
// character class here used to do — is the one thing that cannot work: it turns
// "Francéstraße" into "francstr" and the vendor's "Francestr." into
// "francestr", two strings that match nothing, not even each other.
export function foldGerman(s: string): string {
  return (s || '')
    .toLowerCase()
    .replace(/ä/g, 'ae')
    .replace(/ö/g, 'oe')
    .replace(/ü/g, 'ue')
    .replace(/ß/g, 'ss')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')      // é -> e, and every other accent
}

// Normalise a street name for fuzzy comparison across spelling variants:
// "Weyher Straße" / "Weyher Str." / "Weyher Str. [Brinkum]" -> "weyherstr".
export function normStreet(s: string): string {
  return foldGerman(s)
    .replace(/\[[^\]]*\]/g, ' ')          // drop district tags like "[Brinkum]"
    .replace(/\([^)]*\)/g, ' ')           // ...and "(Altenmittlau)" (jumomind style)
    .replace(/strasse/g, 'str')           // "straße" is already "strasse" here
    .replace(/str\.?/g, 'str')
    .replace(/[^a-z0-9]/g, '')
}

// The distinctive part of a street name (drops a trailing Straße/Str. word) so we
// can narrow the vendor's street list before fuzzy-matching. "Weyher Straße" ->
// "weyher", "Hauptstraße" -> "haupt".
export function streetStem(s: string): string {
  const stem = (s || '').toLowerCase().replace(/\s*(stra(ß|ss)e|str\.?)\s*$/, '').trim()
  return stem || (s || '').toLowerCase()
}

// Do a covered town's name and a geocoded town's name refer to the same place?
// Exact, or one appears inside the other AT A WORD BOUNDARY — which covers both
// "Gießen" in "Landkreis Gießen" and "Freigericht" in "Freigericht-Bernbach",
// because a hyphen is not a name character.
//
// The boundary is load-bearing, and this function has now been wrong twice in
// the same way. The old web app used a bare `includes`, which matched "Hain"
// inside "Friedrichshain" and gave a Berlin address a village's bin days
// 400 km away. The rewrite fixed that and then kept a bare prefix test for the
// "Freigericht-Bernbach" case — so **"München" matched "Münchenhof"**, a hamlet
// in the Landkreis Harz whose whole-town schedule accepts any street at all,
// and a München household was handed Saxony-Anhalt's Hausmüll, Papier and Gelbe
// Säcke. Found in the running app on 2026-09-17, by a reader who knew their own
// city has no Gelber Sack.
//
// The prefix test was also redundant: `containsWord` already accepts a prefix
// that ends on a separator, which is exactly the Freigericht case and exactly
// not the Münchenhof one. Two towns whose names merely start alike are two
// towns.
export function townMatches(candidate: string, target: string): boolean {
  if (candidate === target) return true
  return containsWord(candidate, target) || containsWord(target, candidate)
}

export function containsWord(haystack: string, needle: string): boolean {
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

export function isNameChar(ch: string): boolean {
  return !!ch && /[a-z0-9äöüß]/.test(ch)
}

// "Königstraße" → ["Königstraße", "Königstr."]; "Königstr." → ["Königstr.",
// "Königstraße"]; anything without the word stays alone.
export function streetSpellings(street: string): string[] {
  const s = street.trim()
  const out = [s]
  if (/stra(ß|ss)e$/i.test(s)) out.push(s.replace(/stra(ß|ss)e$/i, 'str.'))
  else if (/str\.?$/i.test(s)) out.push(s.replace(/str\.?$/i, 'straße'))
  return out
}

// Read a user-pasted ICS link. Kept inside the abfall family (vendor 'ics') so
// the pickup overlay, bin colours, and sync flow all apply unchanged. Also
// used by abfall-lookup's ics-check action to validate the link at setup time.
// Tiny stable fingerprint (djb2) so two manual ICS links in one family never
// share event uids (colliding uids would merge their events into one).
export function shortHash(s: string): string {
  let h = 5381
  for (let i = 0; i < s.length; i++) h = ((h * 33) ^ s.charCodeAt(i)) >>> 0
  return h.toString(36)
}

// Every way a German street name might be written, most likely first.
//
// German has two written forms of each umlaut and of ß, and which one a street
// sign carries is a local decision no rule predicts: Hamburg writes
// "Fraenkelstraße" and "Mönckebergstraße", one folded and one not, in the same
// list. The geocoder is no more consistent, so both directions are generated.
//
// This exists because some vendor searches fold NOTHING — they are literal
// prefix matches — and for those, normalising both sides afterwards is too late:
// the request itself has to carry the spelling the vendor holds. Nonsense falls
// out of it ("Neue" -> "Nü"), costing one request that returns nothing; the cap
// keeps that bounded. Lower-cased throughout, which is safe because every search
// that needs this is case-insensitive.
export function germanSpellings(street: string): string[] {
  const out = [street.trim().toLowerCase()]
  const swaps: Array<[RegExp, string]> = [
    [/ä/g, 'ae'], [/ö/g, 'oe'], [/ü/g, 'ue'], [/ß/g, 'ss'],
    [/ae/g, 'ä'], [/oe/g, 'ö'], [/ue/g, 'ü'], [/ss/g, 'ß'],
  ]
  for (const [re, to] of swaps) {
    for (const s of [...out]) {
      const v = s.replace(re, to)
      if (v !== s && !out.includes(v)) out.push(v)
      if (out.length >= 8) return out
    }
  }
  return out
}

// ── The vendor contract ──────────────────────────────────────────────────────
//
// One adapter per waste-vendor family. Everything the resolver knows how to do
// with a vendor is declared here, so adding a city is adding ONE file plus one
// line in registry.ts — never an edit to four dispatch chains.
//
// Only `family` and `read` are required. Each optional member answers one
// question, and leaving one out is a statement about the vendor rather than an
// omission:
//   towns         which towns this provider contributes. Left out: none — the
//                 vendor is reached by a pasted link, not by an address.
//   searchStreets street autocomplete inside a town. Left out: the vendor has no
//                 street list to offer (C-Trace validates server-side instead).
//   probe         resolve a whole address at once. When present it REPLACES the
//                 generic "search the street list and fuzzy-match" path, because
//                 the vendor needs the house number to name a schedule at all.
//   houseNumbers  extra numbers for a street matched the generic way, when the
//                 vendor keeps them behind a further call.
//   rhythm        which of the vendor's titles are one bin in different
//                 rhythms. Left out: every title is its own bin, and the
//                 household is never asked.
export interface VendorAdapter {
  family: string
  towns?(p: AbfallProvider): Town[] | Promise<Town[]>
  searchStreets?(town: Town, query: string, hint?: string): Promise<StreetOption[]>
  probe?(town: Town, addr: GeoAddress): Promise<ResolveResult | null>
  houseNumbers?(opt: StreetOption): Promise<HausNr[] | undefined>
  rhythm?(title: string): RhythmTag | null
  read(cfg: AbfallConfig): Promise<SyncedEvent[]>
}

// ── Rhythms the household has to name ───────────────────────────────────────
//
// Some vendors print every rhythm of a bin side by side — "Restmüll: Wöchentlich",
// "Restmüll: 2-wöchentlich", "Restmüll: 4-wöchentlich" — and leave the household
// to tick the one on its bin sticker, exactly as their own web page does. Showing
// all of them would put three Restmüll days in a fortnight on a calendar that has
// one. So the adapter reads them all, tags which titles are variants of one bin,
// and the household's pick (`AbfallConfig.rhythm`) keeps one.
//
// **The options are the ones this address has, never the vendor's full menu.**
// Saarbrücken offers weekly Restmüll city-wide, and Bahnhofstraße has no weekly
// dates at all: a menu would let a household pick a rhythm that yields no
// Restmüll, and nothing downstream would notice the bin had gone missing.

/// One title read as a bin and its rhythm: "Restmüll: 2-wöchentlich" ->
/// { bin: "Restmüll", option: "2-wöchentlich" }.
export interface RhythmTag { bin: string; option: string }

/// One option of a choice: the vendor's own words, and how many days apart its
/// dates actually fall (7, 14, 28), measured rather than read off the label —
/// Neuss says "Grau" and "Pink" and means weekly and fortnightly.
export interface RhythmOption { id: string; every: number | null }

/// A bin the household has to answer for, with the options its address has.
export interface RhythmChoice { bin: string; options: RhythmOption[] }

/// The common case, shared by the adapters that opt in: a Restmüll title with a
/// rhythm after it — "Restabfalltonne (14-täglich)", "Restmüll rote Woche",
/// "Restmüll: 2-wöchentlich", "Restmüll - 4-wöchentlich", "Restmüll-Pink". A
/// bare "Restmüll" is not a variant of anything.
export function restRhythm(title: string): RhythmTag | null {
  const m = (title || '').trim().match(/^(Rest(?:abfall|müll)[a-zäöüß]*)(?:\s*[:(–-]\s*|\s+)(.+?)\)?$/i)
  if (!m) return null
  const option = m[2].replace(/(\d)-\s+/g, '$1-').replace(/\s+/g, ' ').trim()
  return option ? { bin: m[1], option: option.charAt(0).toUpperCase() + option.slice(1) } : null
}

// ── House-number spans written into a street's name ─────────────────────────
//
// Some vendors split a long street into entries named for the numbers they
// cover, in free German: "Bergische Landstraße 1 - 71 und 2 - 88",
// "… 73 - Ende und 90 - Ende", "Frankenstraße 1-197 ung./2-210 ger. Nr.",
// "Friedrich-Ebert-Ring ab 13", "Rottendorfer Straße 15a-Ende", "… 117".
// Two spans without "ung."/"ger." are the two sides of the street, so each takes
// the parity of its first number; a lone span takes both sides.

export interface NrSpan { from: [number, string]; to: [number, string] | null; parity: 0 | 1 | null }

/// Split "Frankenstraße 1-197 ung./2-210 ger. Nr." into the street and its
/// spans; a name with no numbers in it has no spans (the whole street).
export function splitSpans(name: string): { street: string; spans: NrSpan[] } {
  const m = name.match(/^(.*?)\s+((?:ab\s+)?\d.*)$/i)
  if (!m) return { street: name.trim(), spans: [] }
  const parts = m[2].split(/\s+und\s+|\s*\/\s*/i).map((p) => p.trim()).filter(Boolean)
  const spans: NrSpan[] = []
  for (const part of parts) {
    const s = part.match(/^(?:ab\s*)?(\d+)\s*([a-z]?)\b\s*(?:(?:-|bis)\s*(?:(\d+)\s*([a-z]?)\b|Ende))?/i)
    if (!s) continue
    const open = /^ab\b/i.test(part) || /(?:-|bis)\s*Ende/i.test(part)
    const from: [number, string] = [Number(s[1]), (s[2] || '').toLowerCase()]
    const to: [number, string] | null = s[3] ? [Number(s[3]), (s[4] || '').toLowerCase()] : open ? null : from
    const parity = /\bung/i.test(part) ? 1 : /\bger/i.test(part) ? 0 : null
    spans.push({ from, to, parity })
  }
  if (spans.length > 1) for (const sp of spans) if (sp.parity === null) sp.parity = (sp.from[0] % 2) as 0 | 1
  return { street: m[1].trim(), spans }
}

/// Does a house number ("12", "15a") fall inside any of the spans?
export function inSpans(spans: NrSpan[], houseNumber: string): boolean {
  const m = (houseNumber || '').trim().toLowerCase().replace(/\s+/g, '').match(/^(\d+)([a-z]?)/)
  if (!m) return false
  const want: [number, string] = [Number(m[1]), m[2]]
  const cmp = (a: [number, string], b: [number, string]) => a[0] - b[0] || a[1].localeCompare(b[1])
  return spans.some((sp) =>
    (sp.parity === null || want[0] % 2 === sp.parity) &&
    cmp(sp.from, want) <= 0 &&
    (sp.to === null || cmp(want, [sp.to[0], sp.to[1] || 'zz']) <= 0))
}

// ── Whole-day ICS, read by hand ─────────────────────────────────────────────
//
// Several city calendars write every pickup as a bare `DTSTART;VALUE=DATE`,
// some with DTEND equal to DTSTART (ALBA) — a zero-length day the general parser
// may drop. For those the date is all there is to read, so it is read directly.
// A timed DTSTART in UTC ("…T220000Z", local midnight) is moved to Berlin first.
export function icsDays(ics: string): Array<{ day: string; title: string }> {
  const out: Array<{ day: string; title: string }> = []
  const unfolded = ics.replace(/\r?\n[ \t]/g, '')
  for (const b of unfolded.split('BEGIN:VEVENT').slice(1)) {
    const d = b.match(/\nDTSTART(?:;[^:\r\n]*)?:(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})\d{2}(Z)?)?/)
    const s = b.match(/\nSUMMARY(?:;[^:\r\n]*)?:([^\r\n]*)/)
    if (!d || !s) continue
    let day = `${d[1]}-${d[2]}-${d[3]}`
    if (d[6]) {
      const t = new Date(`${day}T${d[4]}:${d[5]}:00Z`)
      day = new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Berlin' }).format(t)
    }
    const title = s[1].replace(/\\([,;\\])/g, '$1').replace(/\\n/gi, ' ').trim()
    out.push({ day, title })
  }
  return out
}

/// Whole-day events from (day, title) pairs, one per bin per day.
export function dayEvents(
  rows: Array<{ day: string; title: string; notes?: string | null }>, uidBase: string, location: string | null,
): SyncedEvent[] {
  const out: SyncedEvent[] = []
  const seen = new Set<string>()
  for (const { day, title, notes } of rows) {
    if (!title || !/^\d{4}-\d{2}-\d{2}$/.test(day)) continue
    const k = `${day}:${title}`
    if (seen.has(k)) continue
    seen.add(k)
    const start = new Date(`${day}T00:00:00Z`)
    out.push({
      uid: `${uidBase}:${k}`,
      title,
      notes: notes ?? null,
      location,
      startsAt: start.toISOString(),
      endsAt: new Date(start.getTime() + 86_400_000).toISOString(),
      allDay: true,
    })
  }
  return out
}
