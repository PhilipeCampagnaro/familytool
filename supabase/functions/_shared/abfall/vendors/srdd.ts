// abfall/vendors/srdd.ts — Stadtreinigung Dresden — a Wicket form turns an address
// into a `STANDORT` number, and the ICS behind it takes any date range asked for.

import {
  type AbfallConfig,
  type AbfallProvider,
  fetchWithTimeout,
  type GeoAddress,
  germanSpellings,
  normStreet,
  parseIcs,
  type ResolveResult,
  type SyncedEvent,
  type Town,
  UA,
  type VendorAdapter,
} from "../core.ts";

// ── Stadtreinigung Dresden ──────────────────────────────────────────────────
//
// The city's AbfallApp (`dresden.de/apps_ext/AbfallApp/wastebins`) is an Apache
// Wicket page: the state lives in a server session and every step is an Ajax
// "behaviour" addressed by the page's own counters. Four requests find a house:
//
//   GET  wastebins                                  -> JSESSIONID, `?0`
//   POST ?0-1.0-searchForm-street        street=…   (updates the form model)
//   GET  ?0-1.1-searchForm-street                   -> the house <select>
//   POST ?0-1.0-searchForm-buttonContainer-searchLink street=… hnrContainer:hnr=…
//                                                   -> "…kalender.ashx?STANDORT=80542"
//
// **The two street steps are not one.** The GET alone re-renders the form from
// an empty model and answers with blank placeholders; the POST sets the model
// and says nothing. The house ids in the <select> are *not* the STANDORT (Neumarkt
// 6 is 71676 there and 80542 in the calendar), so the search is always pressed.
// The behaviour URLs are read off the page rather than assumed.
//
// **Then the calendar is keyless and takes any window**:
//
//   GET stadtplan.dresden.de/…/abfall/ical.ashx?STANDORT=<n>&DATUM_VON=dd.mm.yyyy&DATUM_BIS=…
//
// so the read asks from the start of last month to the end of next year and the
// year rolls over by itself, as Köln's does. On 2026-09-18 it runs to the end of
// 2027. Its UIDs are stable (`20260803T000000_80542@…`); ours are built the same
// way. One event can name two bins ("Leerung Gelbe Tonne, Bio-Tonne") and is split,
// and "Abfallkalender endet bald" is a notice at the end of the window, not a
// pickup.
//
// **A street name can be served twice**, once in the city and once in a village
// incorporated into it, and the app tells them apart with a tag: "Dorfstraße",
// "Dorfstraße (CB)" (Cossebaude), "(SW)" Schönfeld-Weißig, "(LB)" Langebrück,
// and one "(Heidenau)" for the side of a border street Dresden collects. The
// postcode picks between them; a tag we can't place by postcode never wins by
// default, because the neighbour's bins look exactly like a working calendar.
const APP = 'https://www.dresden.de/apps_ext/AbfallApp/wastebins'
const ICS = 'https://stadtplan.dresden.de/project/cardo3Apps/IDU_DDStadtplan/abfall/ical.ashx'

const TAG_POSTCODES: Record<string, string[]> = {
  CB: ['01462'],
  LB: ['01465'],
  SW: ['01328'],
  Heidenau: ['01809'],
}

interface Session { cookie: string; base: string; complete: string; change: string; list: string }

const cookiesOf = (res: Response) =>
  (res.headers.get('set-cookie') || '')
    .split(/,(?=\s*[A-Za-z0-9_-]+=)/)
    .map((c) => c.split(';')[0].trim())
    .filter(Boolean)

async function open(): Promise<Session> {
  // `wastebins` sets the session cookie in a 302 to `wastebins?0`, and without
  // it that page redirects back — a loop a cookieless fetch follows 20 times.
  const jar = new Map<string, string>()
  let url = APP
  let res: Response | undefined
  for (let hop = 0; hop < 5; hop++) {
    res = await fetchWithTimeout(url, {
      redirect: 'manual',
      headers: {
        'User-Agent': UA,
        Accept: 'text/html,*/*',
        ...(jar.size ? { Cookie: [...jar].map(([k, v]) => `${k}=${v}`).join('; ') } : {}),
      },
    })
    for (const c of cookiesOf(res)) {
      const i = c.indexOf('=')
      if (i > 0) jar.set(c.slice(0, i), c.slice(i + 1))
    }
    const next = res.headers.get('location')
    if (res.status < 300 || res.status >= 400 || !next) break
    await res.body?.cancel()
    url = new URL(next, url).toString()
    // Only ever this app.
    if (!url.startsWith(APP)) throw new Error('abfall upstream: unexpected redirect')
  }
  if (!res?.ok) throw new Error(`abfall upstream ${res?.status}`)
  const html = await res.text()
  const cookie = [...jar].map(([k, v]) => `${k}=${v}`).join('; ')
  const base = html.match(/Wicket\.Ajax\.baseUrl="([^"]+)"/)?.[1] || 'wastebins?0'
  const u = (re: RegExp) => html.match(re)?.[1]
  const complete = u(/"u":"\.\/([^"]*-searchForm-street)","c":"id1","wr"/)
  const change = u(/"u":"\.\/([^"]*-searchForm-street)","m":"POST"/)
  const list = u(/"u":"\.\/([^"]*-searchForm-street)","c":"id1","e":"change"/)
  if (!cookie || !complete || !change || !list) throw new Error('abfall upstream: no Dresden session')
  return { cookie, base, complete, change, list }
}

async function call(s: Session, path: string, form?: Record<string, string>): Promise<string> {
  const res = await fetchWithTimeout(`${APP.replace(/wastebins$/, '')}${path}`, {
    method: form ? 'POST' : 'GET',
    headers: {
      'User-Agent': UA,
      Accept: 'text/xml, */*',
      Cookie: s.cookie,
      'Wicket-Ajax': 'true',
      'Wicket-Ajax-BaseURL': s.base,
      ...(form ? { 'Content-Type': 'application/x-www-form-urlencoded' } : {}),
    },
    body: form ? new URLSearchParams(form).toString() : undefined,
  })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  return res.text()
}

/// The autocomplete's rows for one prefix (it answers at most ten).
async function complete(s: Session, q: string): Promise<string[]> {
  const xml = await call(s, `${s.complete}&q=${encodeURIComponent(q)}`)
  return [...xml.matchAll(/textvalue="([^"]*)"/g)].map((m) => m[1].replace(/&amp;/g, '&'))
}

const tagOf = (name: string) => name.match(/\(([^)]+)\)\s*$/)?.[1]

/// Dresden's own spelling of the street, or null when it has none — or when the
/// name is served twice and the postcode cannot say which.
async function findStreet(s: Session, street: string, postcode?: string): Promise<string | null> {
  const target = normStreet(street)
  if (!target) return null
  const head = street.split(/[0-9]/)[0].trim().toLowerCase()
  const queries = [...germanSpellings(street)]
  if (head.length >= 3 && !queries.includes(head)) queries.push(head)
  for (const q of queries) {
    const hits = [...new Set((await complete(s, q).catch(() => [] as string[]))
      .filter((n) => normStreet(n) === target))]
    if (!hits.length) continue
    if (hits.length === 1) return hits[0]
    const claimed = hits.filter((n) => {
      const tag = tagOf(n)
      return tag && postcode && TAG_POSTCODES[tag]?.includes(postcode)
    })
    if (claimed.length === 1) return claimed[0]
    // The plain name is the city's own street — but only when every tagged
    // twin is one we can place and none of them claims this postcode.
    const plain = hits.filter((n) => !tagOf(n))
    const allKnown = hits.every((n) => !tagOf(n) || TAG_POSTCODES[tagOf(n)!])
    if (plain.length === 1 && !claimed.length && allKnown && postcode) return plain[0]
    return null
  }
  return null
}

interface House { id: string; nr: string }

async function houses(s: Session, street: string): Promise<House[]> {
  await call(s, s.change, { street })
  const xml = await call(s, s.list)
  return [...xml.matchAll(/<option value="(\d+)">([^<]*)</g)]
    .map((m) => ({ id: m[1], nr: m[2].trim() }))
    .filter((h) => h.nr)
}

async function standort(s: Session, street: string, houseId: string): Promise<string | undefined> {
  const xml = await call(s, s.list)
  const link = xml.match(/"u":"\.\/([^"]*-searchForm-buttonContainer-searchLink)"/)?.[1]
  if (!link) return undefined
  const res = await call(s, link, { street, 'hnrContainer:hnr': houseId, 'buttonContainer:searchLink': '1' })
  return res.match(/STANDORT=(\d{1,9})/)?.[1]
}

const key = (s: string) => (s || '').toLowerCase().replace(/\s+/g, '')

const ddmmyyyy = (d: Date) =>
  `${String(d.getUTCDate()).padStart(2, '0')}.${String(d.getUTCMonth() + 1).padStart(2, '0')}.${d.getUTCFullYear()}`

async function fetchIcs(id: string): Promise<string> {
  const now = new Date()
  const from = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 1, 1))
  const to = new Date(Date.UTC(now.getUTCFullYear() + 1, 11, 31))
  const q = new URLSearchParams({ STANDORT: id, DATUM_VON: ddmmyyyy(from), DATUM_BIS: ddmmyyyy(to) })
  const res = await fetchWithTimeout(`${ICS}?${q}`, { headers: { 'User-Agent': UA, Accept: 'text/calendar, */*' } })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  return res.text()
}

async function probeSrdd(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  if (!addr.street) return null
  const s = await open()
  const street = await findStreet(s, addr.street, addr.postcode)
  if (!street) return null
  const list = await houses(s, street)
  // Listed with nobody on it: nothing the city collects from.
  if (!list.length) return null
  const shown = street.replace(/\s*\([^)]*\)\s*$/, '')
  const want = key(addr.houseNumber || '')
  const house = want ? list.find((h) => key(h.nr) === want) : undefined
  if (house) {
    const id = await standort(s, street, house.id).catch(() => undefined)
    if (id && (await fetchIcs(id).catch(() => '')).includes('BEGIN:VEVENT')) {
      return {
        supported: true,
        town: town.name,
        street: shown,
        config: { vendor: 'srdd', street, hnrId: id, hnr: house.nr },
      }
    }
  }
  // The client connects with the picked row's id as `hnrId`, and the list's ids
  // are the app's, not the calendar's. So a picked house is stored as `h<id>`
  // and the read looks its STANDORT up; a number the probe could look up itself
  // is stored as the STANDORT and costs one request a refresh.
  return {
    supported: true,
    town: town.name,
    street: shown,
    needsHouseNumber: true,
    hausNrList: list.map((h) => ({ id: `h${h.id}`, nr: h.nr })),
    config: { vendor: 'srdd', street },
  }
}

async function readSrdd(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  let id = String(cfg.hnrId ?? '')
  const picked = id.match(/^h([0-9]{1,9})$/)?.[1]
  if (picked) {
    if (!cfg.street) throw new Error('reconnect_required')
    const s = await open()
    await call(s, s.change, { street: cfg.street })
    id = (await standort(s, cfg.street, picked)) ?? ''
    // The house is gone from the app's list: renamed, merged or demolished.
    if (!id) throw new Error('reconnect_required')
  }
  if (!/^[0-9]{1,9}$/.test(id)) throw new Error('reconnect_required')
  const ics = await fetchIcs(id)
  if (!ics.includes('BEGIN:VEVENT')) return []
  const y = new Date().getUTCFullYear()
  const out: SyncedEvent[] = []
  const seen = new Set<string>()
  for (const ev of parseIcs(ics, new Date(Date.UTC(y - 1, 0, 1)), new Date(Date.UTC(y + 2, 0, 1)))) {
    if (/endet bald/i.test(ev.title)) continue
    const day = ev.startsAt.slice(0, 10)
    for (const bin of ev.title.replace(/^\s*Leerung\s+/i, '').split(',').map((t) => t.trim()).filter(Boolean)) {
      const k = `${day}:${bin}`
      if (seen.has(k)) continue
      seen.add(k)
      const start = new Date(`${day}T00:00:00Z`)
      out.push({
        uid: `abfall:srdd:${id}:${k}`,
        title: bin,
        notes: null,
        location: cfg.label ?? ev.location ?? null,
        startsAt: start.toISOString(),
        endsAt: new Date(start.getTime() + 86_400_000).toISOString(),
        allDay: true,
      })
    }
  }
  return out
}

function towns(p: AbfallProvider): Town[] {
  return [{ vendor: 'srdd', name: p.town || 'Dresden', provider: p.id }]
}

export const adapter: VendorAdapter = {
  family: 'srdd',
  towns,
  probe: probeSrdd,
  read: readSrdd,
}
