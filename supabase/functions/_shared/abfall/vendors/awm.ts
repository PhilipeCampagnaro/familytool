// abfall/vendors/awm.ts — AWM München — a TYPO3 form walk; the ICS link is cHash-signed per year.

import {
  type AbfallConfig,
  type AbfallProvider,
  decodeEntities,
  fetchWithTimeout,
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

// ── AWM (München) ───────────────────────────────────────────────────────────
//
// The one vendor here that is a form rather than an API, and it is worth it for
// 1.5 million people. Three steps, no key and no session:
//
//   1. GET the Abfuhrkalender page. It carries **every München street** as
//      `<span class="aostrasse">`, which is the autocomplete source, and the
//      TYPO3/Extbase form with its signed `__trustedProperties` and `__referrer`
//      fields. Both come out of the one fetch, which is why they are cached
//      together.
//   2. POST street + Hausnummer back with those fields echoed verbatim. The
//      answer carries a link with `section=ics` on it.
//   3. GET that link. It is a full year of pickups.
//
// **The ICS link cannot be built by hand**: TYPO3 signs the query with a
// `cHash`, and it also carries the Stellplatz and Leerungszyklus ids the form
// worked out for that address. So the walk is redone on every refresh rather
// than the URL being stored — which also means an address whose bin cycle
// changes is simply right the next day.
//
// Per house, like Berlin and Frankfurt: the form marks Hausnummer `required`
// and a street alone yields nothing, so an address without one is answered
// `needsHouseNumber`.
const AWM_PAGE = 'https://www.awm-muenchen.de/abfall-entsorgen/muelltonnen/abfuhrkalender'

const AWM_ORIGIN = 'https://www.awm-muenchen.de'

interface AwmForm {
  action: string
  hidden: Map<string, string>
  streets: string[]
}

let _awmForm: { at: number; form: AwmForm } | null = null

/// The page, parsed once per warm instance. Six hours, like the town cache:
/// München does not rename its streets over lunch, and the page is 400 KB.
async function awmForm(): Promise<AwmForm> {
  if (_awmForm && Date.now() - _awmForm.at < 6 * 60 * 60 * 1000) return _awmForm.form
  const res = await fetchWithTimeout(AWM_PAGE, {
    headers: { 'User-Agent': UA, Accept: 'text/html,*/*' },
  })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const html = await res.text()

  const open = html.match(/<form[^>]*name="abfuhrkalender"[^>]*>/i)
  if (!open) throw new Error('awm form not found')
  const action = decodeEntities((open[0].match(/action="([^"]*)"/i) || [])[1] || '')
  const body = html.slice(open.index! + open[0].length)
  const form = body.slice(0, body.search(/<\/form>/i))

  const hidden = new Map<string, string>()
  for (const tag of form.match(/<input[^>]*type="hidden"[^>]*>/gi) || []) {
    const name = (tag.match(/name="([^"]*)"/i) || [])[1]
    if (!name) continue
    hidden.set(decodeEntities(name), decodeEntities((tag.match(/value="([^"]*)"/i) || [])[1] || ''))
  }

  const streets: string[] = []
  const seen = new Set<string>()
  for (const m of html.matchAll(/<span class="aostrasse">([^<]*)<\/span>/g)) {
    const name = decodeEntities(m[1]).trim()
    if (!name || seen.has(name.toLowerCase())) continue
    seen.add(name.toLowerCase())
    streets.push(name)
  }
  if (!streets.length) throw new Error('awm street list empty')

  const out = { action: action.startsWith('http') ? action : `${AWM_ORIGIN}${action}`, hidden, streets }
  _awmForm = { at: Date.now(), form: out }
  return out
}

const AWM_FIELD = 'tx_awmabfuhrkalender_abfuhrkalender'

/// Street + house number -> the generated ICS link, or null when the form did
/// not produce one (an unknown house number, or a follow-up question we cannot
/// answer for the household).
async function awmIcsUrl(street: string, hnr: string): Promise<string | null> {
  const form = await awmForm()
  const body = new URLSearchParams()
  for (const [k, v] of form.hidden) body.set(k, v)
  body.set(`${AWM_FIELD}[strasse]`, street)
  body.set(`${AWM_FIELD}[hausnummer]`, hnr)
  body.set(`${AWM_FIELD}[section]`, 'address')
  body.set(`${AWM_FIELD}[submitAbfuhrkalender]`, 'true')

  // The server checks Origin on this POST — without it the form is refused.
  const res = await fetchWithTimeout(form.action, {
    method: 'POST',
    headers: {
      'User-Agent': UA,
      'Content-Type': 'application/x-www-form-urlencoded',
      Origin: AWM_ORIGIN,
      Referer: AWM_PAGE,
      Accept: 'text/html,*/*',
    },
    body: body.toString(),
  })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const html = await res.text()
  const href = (html.match(/href="([^"]*section%5D=ics[^"]*)"/i) || [])[1]
  if (!href) return null
  const url = decodeEntities(href)
  return url.startsWith('http') ? url : `${AWM_ORIGIN}${url}`
}

async function searchStreetsAwm(query: string): Promise<StreetOption[]> {
  const q = normStreet(query)
  if (!q) return []
  const { streets } = await awmForm()
  return streets
    .filter((name) => normStreet(name).includes(q))
    .slice(0, 50)
    .map((name) => ({ name, config: { vendor: 'awm', street: name } }))
}

async function probeAwm(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  if (!addr.street) return null
  const { streets } = await awmForm()
  const target = normStreet(addr.street)
  // The list is written the vendor's way ("Francestr."), the geocoder writes it
  // out and keeps the accent ("Francéstraße"); normStreet folds both to
  // "francestr".
  const best =
    streets.find((s) => normStreet(s) === target) ||
    streets.find((s) => {
      const n = normStreet(s)
      return n.includes(target) || target.includes(n)
    })
  if (!best) return null

  const hnr = (addr.houseNumber || '').trim()
  if (!hnr) {
    return { supported: true, town: town.name, street: best, needsHouseNumber: true, config: { vendor: 'awm', street: best } }
  }
  // The form is the only thing that knows whether this house exists, so the
  // probe is the real request rather than a lookup.
  //
  // No link back means one of two things, and both end here. Usually the house
  // number is simply not on that street, which is what the answer says. Rarely
  // — 0 of 24 sampled addresses, and the Rathaus is one of them — the building
  // holds several emptying cycles and the form asks which one the household is
  // on, a question only they can answer. Picking one would be picking their bin
  // frequency for them and getting half the dates wrong, so it is not picked:
  // they answer it on awm-muenchen.de and paste the calendar in, which is what
  // the ICS fallback is for.
  const url = await awmIcsUrl(best, hnr)
  if (!url) {
    return { supported: true, town: town.name, street: best, needsHouseNumber: true, config: { vendor: 'awm', street: best } }
  }
  return {
    supported: true,
    town: town.name,
    street: best,
    config: { vendor: 'awm', street: best, hnr },
  }
}

async function readAwm(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  if (!cfg.street || !cfg.hnr) throw new Error('reconnect_required')
  const url = await awmIcsUrl(cfg.street, cfg.hnr)
  if (!url) return []
  const res = await fetchWithTimeout(url, {
    headers: { 'User-Agent': UA, Accept: 'text/calendar, */*', Origin: AWM_ORIGIN },
  })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const ics = (await res.text()).replace(/^﻿/, '')
  if (!ics.includes('BEGIN:VEVENT')) return []
  const thisYear = new Date().getUTCFullYear()
  const start = new Date(Date.UTC(thisYear - 1, 0, 1))
  const end = new Date(Date.UTC(thisYear + 2, 0, 1))
  const out: SyncedEvent[] = []
  const seen = new Set<string>()
  for (const ev of parseIcs(ics, start, end)) {
    // "Restmülltonne, Francestr. 10" -> "Restmülltonne". Only the trailing
    // address is dropped: the "Achtung:" prefix on the holiday notices stays,
    // because those days were taken out of the series on purpose and must not
    // read as an ordinary collection.
    const title = ev.title.replace(/,\s*[^,]*$/, '').trim() || 'Abfuhr'
    const dayKey = `${ev.startsAt.slice(0, 10)}:${title}`
    if (seen.has(dayKey)) continue
    seen.add(dayKey)
    out.push({
      ...ev,
      uid: `abfall:awm:${cfg.street}:${cfg.hnr}:${dayKey}`,
      title,
      // The Stellplatz line is the one useful thing in the description: which
      // address the bins are actually collected from, which in München is
      // regularly a neighbouring house.
      notes: ev.notes,
      location: cfg.label ?? ev.location ?? null,
    })
  }
  return out
}

function towns(p: AbfallProvider): Town[] {
  // One city; streets are searched live and the address validated by the probe.
  return [{ vendor: 'awm', name: p.town || 'München', provider: p.id }]
}

export const adapter: VendorAdapter = {
  family: 'awm',
  towns,
  searchStreets: (_town, query) => searchStreetsAwm(query),
  probe: probeAwm,
  read: readAwm,
}
