// abfall/vendors/awista.ts — AWISTA Kommunal (Düsseldorf) — the calendar is
// addressed by an opaque uuid, and the whole job is turning a street and a house
// number into the right one.

import {
  type AbfallConfig,
  type AbfallProvider,
  fetchWithTimeout,
  foldGerman,
  type GeoAddress,
  normStreet,
  parseIcs,
  type ResolveResult,
  type StreetOption,
  type SyncedEvent,
  type Town,
  UA,
  type VendorAdapter,
} from "../core.ts";

// ── AWISTA Kommunal GmbH, Düsseldorf ────────────────────────────────────────
//
// One household's downloaded file is the whole shape of it:
//
//   GET /abfallkalender/54c05220-3535-4231-a85e-5b37397efc1b/calendar.ics
//
// The uuid is the address. Nothing in the file says how to get one — there is no
// street id, no postcode, no numeric key anywhere — so the lookup had to come
// from the city's own page, and it is not an API in the usual sense.
//
// **The site is a Next.js app and its address search is a Server Action**, which
// is a POST to an ordinary page URL with the function's id in a `Next-Action`
// header and its arguments as a JSON array:
//
//   POST /abfallkalender          Next-Action: <id of searchAddressAction>
//   ["Askanierstraße 3"]
//   -> 1:{"items":[{"title":"Askanierstraße 3","id":"<uuid>", ...}],
//         "isReadyForHouseNumber":false,"addressIdForQuery":"<uuid>"}
//
// That single call is the whole lookup: it returns the uuid the ICS hangs off,
// and `isReadyForHouseNumber` when the street was understood but no number was
// given. The reply is an RSC stream rather than JSON — numbered lines, one JSON
// value each — so the line carrying `items` is picked out rather than parsed
// whole.
//
// **The id is build-specific, so it is discovered rather than trusted.** A stale
// one answers `404 Server action not found.`, which is unambiguous, and
// `discoverActionId()` then re-reads it from the page's own JavaScript. The
// value below is only a starting guess; nothing breaks when it goes out of date.
// There is a second `searchAddressAction` on the site — the home page's teaser
// search — and it answers with the city's twelve-digit STREET code, not a
// calendar uuid, so discovery insists on the chunk that also mentions
// `addressIdForQuery`.
//
// **The search never says "not found", and that is the trap.** It is fuzzy in
// both directions:
//
//   "Quatschstraße 1"   -> items: Kuhstraße 10, Kuhstraße 12, Kuhstraße 14
//   "Kopernikusstraße 6"-> items: Kopernikusstraße 60, Kopernikusstraße 61
//   "Königsallee 56"    -> items: Berliner Allee 56, Grafenberger Allee 56
//
// Every one of those carries a real uuid for a real address somewhere else in
// Düsseldorf. So a returned row is never taken on trust: its own `title` must
// match the address that was asked for, and then the calendar itself must agree
// — every VEVENT carries `LOCATION:Askanierstraße 3\n40547 Düsseldorf`, which is
// the vendor stating out loud whose bins these are.
//
// It folds "Str." into "Straße" but not "ae/oe/ue/ss" into umlauts — so
// "Koelner Strasse 1" sets no `addressIdForQuery` at all. Unlike Hamburg that
// costs nothing here: the suggestions come back in the city's own writing
// regardless, so the title scan below finds the row in the same one request and
// no spelling has to be re-asked.
//
// **An address can resolve and still have no calendar.** Venloer Straße 1 and
// Grafenberger Allee 302 both return a valid uuid and a valid page, and an ICS
// with zero events — AWISTA services them some other way. Connecting one would
// give a household a bin calendar that stays empty forever, so the resolve step
// requires at least one pickup.
//
// The feed runs from the start of the current week to 31 December, with no year
// parameter and nothing to pass. **The uuid survives the turn of the year**: one
// archived by the Wayback Machine in December 2025 returns a 2026 calendar
// today, so the new year arrives by itself and nothing has to be reconnected.
const AWISTA_BASE = 'https://www.awista-kommunal.de'
const AWISTA_PAGE = `${AWISTA_BASE}/abfallkalender`

// Last known id of `searchAddressAction` on the Abfallkalender page. Re-read from
// the site whenever it stops being accepted — see discoverActionId().
const AWISTA_ACTION_SEED = '406d03b3cea897fbbf9c7c1fc23b74d38574b337b9'

let actionId = AWISTA_ACTION_SEED

interface AwistaItem { title?: string; id?: string; slug?: string }
interface AwistaReply {
  items?: AwistaItem[]
  isReadyForHouseNumber?: boolean
  addressIdForQuery?: string
}

/// Find the current id of the Abfallkalender page's `searchAddressAction`.
///
/// The page's HTML names the JavaScript chunks its components are built from; one
/// of them registers the action, and the registration carries both the id and the
/// function's name:
///
///   createServerReference("406d03…",o.callServer,void 0,o.findSourceMapURL,"searchAddressAction")
///
/// The chunk is required to mention `addressIdForQuery` as well, because the home
/// page's same-named search resolves to street codes rather than to calendars and
/// its chunk is loaded by this page too.
async function discoverActionId(): Promise<string | null> {
  const page = await fetchWithTimeout(AWISTA_PAGE, { headers: { 'User-Agent': UA } })
  if (!page.ok) return null
  const html = await page.text()
  const seen = new Set<string>()
  const chunks: string[] = []
  for (const m of html.matchAll(/\/_next\/static\/chunks\/[A-Za-z0-9_.-]+\.js/g)) {
    if (!seen.has(m[0])) {
      seen.add(m[0])
      chunks.push(m[0])
    }
  }
  for (const path of chunks.slice(0, 24)) {
    const res = await fetchWithTimeout(AWISTA_BASE + path, { headers: { 'User-Agent': UA } })
      .catch(() => null)
    if (!res?.ok) continue
    const js = await res.text()
    if (!js.includes('addressIdForQuery')) continue
    const hit = js.match(/createServerReference\("([0-9a-f]{20,})"[^)]*"searchAddressAction"\)/)
    if (hit) return hit[1]
  }
  return null
}

/// One request, with a short wait when the site's firewall says "too many".
///
/// awista-kommunal.de sits behind Vercel's rate limiter and answers 429 to a
/// burst — which matters less for what we do (one lookup per household, one feed
/// fetch per address per day) than for how badly it would read if it leaked: a
/// 429 during a lookup would come out of `probe` as "Düsseldorf wird noch nicht
/// unterstützt" and invite a request for a city that is in fact covered. Two
/// retries turn a burst into a pause; anything past that is a real outage and is
/// reported as one.
async function awistaFetch(url: string, init?: RequestInit): Promise<Response> {
  for (let attempt = 0;; attempt++) {
    const res = await fetchWithTimeout(url, init)
    if (res.status !== 429 || attempt >= 2) return res
    await res.body?.cancel()
    const after = Number(res.headers.get('Retry-After'))
    const waitMs = Number.isFinite(after) && after > 0
      ? Math.min(after, 8) * 1000
      : 1500 * (attempt + 1)
    await new Promise((r) => setTimeout(r, waitMs))
  }
}

async function postAction(id: string, query: string): Promise<Response> {
  return await awistaFetch(AWISTA_PAGE, {
    method: 'POST',
    headers: {
      'Next-Action': id,
      'Content-Type': 'text/plain;charset=UTF-8',
      'User-Agent': UA,
    },
    body: JSON.stringify([query]),
  })
}

/// Ask the city's own address search about `query`.
///
/// The body is a React Server Components stream: numbered lines, one JSON value
/// each, in no guaranteed order. Only the line holding `items` is wanted, and
/// absent fields arrive as the literal string "$undefined".
async function awistaSearch(query: string): Promise<AwistaReply> {
  const q = query.trim()
  if (!q) return {}
  let res = await postAction(actionId, q)
  if (res.status === 404) {
    // "Server action not found." — the site was redeployed under us.
    const fresh = await discoverActionId().catch(() => null)
    if (!fresh) throw new Error('abfall upstream 404')
    actionId = fresh
    res = await postAction(actionId, q)
  }
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const body = await res.text()
  const line = body.match(/^\d+:(\{.*"items".*\})$/m)
  if (!line) return {}
  const raw = JSON.parse(line[1]) as Record<string, unknown>
  const undef = (v: unknown) => (v === '$undefined' ? undefined : v)
  return {
    items: (undef(raw.items) as AwistaItem[] | undefined) ?? [],
    isReadyForHouseNumber: undef(raw.isReadyForHouseNumber) === true,
    addressIdForQuery: undef(raw.addressIdForQuery) as string | undefined,
  }
}

// House numbers compare on their bare characters, so "66 a", "66a" and "66A" are
// one number and "3" is never "30".
const hnrKey = (s: string) => foldGerman(s || '').replace(/[^a-z0-9]/g, '')

/// Split "Kölner Straße 11a" into its street and its house number.
///
/// The number is the LAST whitespace-separated run that starts with a digit,
/// which matters because a street name here can contain one of its own:
/// "Königsberger Str. 219 Gartengelände" is a street, and 219 is not a house.
function splitAddress(label: string): { street: string; hnr: string } {
  const m = (label || '').trim().match(/^(.*\S)\s+(\d[^\s]*)$/)
  return m ? { street: m[1], hnr: m[2] } : { street: (label || '').trim(), hnr: '' }
}

const sameAddress = (label: string, street: string, hnr: string): boolean => {
  const got = splitAddress(label)
  return normStreet(got.street) === normStreet(street) && hnrKey(got.hnr) === hnrKey(hnr)
}

/// The uuid of exactly this address, or null.
///
/// One request. Every candidate the search offers is checked against what was
/// asked for, because the search answers "Quatschstraße 1" with "Kuhstraße 10"
/// rather than with nothing. `addressIdForQuery` — the vendor's own "this was an
/// exact match" — is preferred, but it is only believed when a row carrying that
/// id agrees.
///
/// No re-asking in other spellings, which is what Hamburg needs: the suggestions
/// come back in the city's own writing whatever was typed, so "Koelner Strasse 1"
/// offers "Kölner Straße 1" and `normStreet` folds the two together here. Only
/// `addressIdForQuery` is spelling-sensitive, and it is not the only way in.
async function awistaLookup(street: string, hnr: string): Promise<string | null> {
  const reply = await awistaSearch(`${street} ${hnr}`.trim())
  const rows = reply.items || []
  const exact = reply.addressIdForQuery
    ? rows.find((r) => r.id === reply.addressIdForQuery && sameAddress(r.title || '', street, hnr))
    : undefined
  const hit = exact ?? rows.find((r) => r.id && sameAddress(r.title || '', street, hnr))
  return hit?.id ?? null
}

/// Does AWISTA know this street at all (whatever the house number)?
///
/// Not `isReadyForHouseNumber` on its own: that flag is the vendor saying "a
/// street of mine, now give me a number", but it is only set when the street was
/// spelled its way ("Kölner Straße" yes, "Koelner Strasse" no). The name it
/// echoes is the reliable part, and it has to be checked anyway — the search
/// answers an invented street with a real one.
async function awistaKnowsStreet(street: string): Promise<boolean> {
  const reply = await awistaSearch(street)
  return (reply.items || [])
    .some((r) => normStreet(splitAddress(r.title || '').street) === normStreet(street))
}

async function awistaIcs(id: string): Promise<string | null> {
  const res = await awistaFetch(`${AWISTA_PAGE}/${encodeURIComponent(id)}/calendar.ics`, {
    headers: { 'User-Agent': UA, Accept: 'text/calendar, */*' },
  })
  if (res.status === 404) return null
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  return (await res.text()).replace(/^﻿/, '')
}

/// The address the feed itself says it is about: "Askanierstraße 3\n40547
/// Düsseldorf\, Deutschland" on every event. Empty when the feed has no events.
function icsAddress(ics: string): string {
  const line = ics.match(/^LOCATION:(.*)$/m)?.[1] ?? ''
  return line.split('\\n')[0].trim()
}

async function searchStreetsAwista(query: string): Promise<StreetOption[]> {
  const reply = await awistaSearch(query)
  const names = new Set<string>()
  for (const row of reply.items || []) {
    // Rows for a bare street carry a trailing space and no id; rows for a full
    // address carry the number too. Only the street part is offered here.
    const name = splitAddress(row.title || '').street
    if (name) names.add(name)
  }
  return [...names].map((name) => ({
    name,
    config: { vendor: 'awista' as const, street: name },
  }))
}

async function probeAwista(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  const street = (addr.street || '').trim()
  if (!street) return null
  const hnr = (addr.houseNumber || '').trim()

  if (hnr) {
    const id = await awistaLookup(street, hnr).catch(() => null)
    if (id) {
      const ics = await awistaIcs(id).catch(() => null)
      // An address with a uuid but no pickups is a real state here, not an
      // error, and a calendar that will never show anything is worse than an
      // honest "we don't serve you".
      const echoed = ics ? icsAddress(ics) : ''
      if (echoed && sameAddress(echoed, street, hnr)) {
        return {
          supported: true,
          town: town.name,
          street,
          config: { vendor: 'awista', hnrId: id, street, hnr },
        }
      }
    }
  }

  // The street is served but this number is not one AWISTA plans for — or none
  // was given. Either way the household types a number; there is no list to
  // offer, because the search invents numbers rather than enumerating them
  // ("Luegallee 2" comes back for a street whose numbers start at 3).
  if (!await awistaKnowsStreet(street).catch(() => false)) return null
  return {
    supported: true,
    town: town.name,
    street,
    needsHouseNumber: true,
    config: { vendor: 'awista', street },
  }
}

async function readAwista(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const id = String(cfg.hnrId ?? '').trim()
  if (!id) throw new Error('reconnect_required')
  const ics = await awistaIcs(id)
  if (ics === null) throw new Error('reconnect_required')

  const street = (cfg.street || '').trim()
  const hnr = (cfg.hnr || '').trim()
  const echoed = icsAddress(ics)
  // The uuid IS the address, so the vendor has nothing to substitute — but it
  // costs nothing to hold it to its word, and a uuid that started naming someone
  // else is a reconnect rather than a stranger's bin days.
  if (echoed && street && hnr && !sameAddress(echoed, street, hnr)) {
    throw new Error('reconnect_required')
  }

  const thisYear = new Date().getUTCFullYear()
  const start = new Date(Date.UTC(thisYear - 1, 0, 1))
  const end = new Date(Date.UTC(thisYear + 2, 0, 1))
  const out: SyncedEvent[] = []
  const seen = new Set<string>()
  for (const ev of parseIcs(ics, start, end)) {
    // "Papier (Teilservice)" — whether AWISTA carries the bin off the property or
    // the household wheels it to the kerb. It is a property of the contract, it
    // never changes, and repeating it on seventy rows only makes the bin name
    // harder to read.
    const title = ev.title.replace(/\s*\((?:Voll|Teil)service\)\s*$/i, '').trim() || ev.title.trim()
    const dayKey = `${ev.startsAt.slice(0, 10)}:${title}`
    if (seen.has(dayKey)) continue
    seen.add(dayKey)
    out.push({
      ...ev,
      uid: `abfall:awista:${id}:${dayKey}`,
      title,
      location: cfg.label ?? ev.location ?? null,
    })
  }
  return out
}

function towns(p: AbfallProvider): Town[] {
  // One city; the address is resolved in one call by the probe.
  return [{ vendor: 'awista', name: p.town || 'Düsseldorf', provider: p.id }]
}

export const adapter: VendorAdapter = {
  family: 'awista',
  towns,
  searchStreets: (_town, query) => searchStreetsAwista(query),
  probe: probeAwista,
  read: readAwista,
}
