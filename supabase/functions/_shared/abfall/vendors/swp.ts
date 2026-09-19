// abfall/vendors/swp.ts — Stadtwerke Potsdam / STEP — the Abfallkalender on
// swp-potsdam.de, which answers per address.

import {
  type AbfallConfig,
  type AbfallProvider,
  dayEvents,
  decodeEntities,
  fetchWithTimeout,
  type GeoAddress,
  normStreet,
  type ResolveResult,
  streetStem,
  type SyncedEvent,
  type Town,
  UA,
  type VendorAdapter,
} from "../core.ts";

// ── SWP Potsdam (www.swp-potsdam.de/api/garbageservice-web/) ─────────────────
//
//   GET  addresses/lookup?street=<prefix>             ["Zeppelinstr. (14471 Potsdam)", …]
//   GET  addresses/lookup?street=<entry>&housenumber= ["", "1", "101", …]
//   POST addresses/garbage/html/<street>/<nr>/<plz>/<count>   JSON body, HTML answer
//
// **Not potsdam.de's own Online-Abfallkalender**: that one asks the household for
// its Leerungsrhythmus off the bin sticker, and this one knows it per address
// (Zeppelinstr. is weekly, Groß Glienicke fortnightly). The POST wants the
// page's link maps as its body and answers 500 to none at all; empty maps are
// enough. The answer is one <li> per day — "Dienstag, 22. September 2026" and
// the bins as link texts. An unknown number answers 200 with "Zu der
// eingegebenen Adresse liegen keine Daten vor." The window runs to 31 December.
const API = 'https://www.swp-potsdam.de/api/garbageservice-web/addresses'
const MONTHS = ['januar', 'februar', 'märz', 'april', 'mai', 'juni', 'juli', 'august', 'september', 'oktober', 'november', 'dezember']

async function lookup(params: Record<string, string>): Promise<string[]> {
  const res = await fetchWithTimeout(`${API}/lookup?${new URLSearchParams(params)}`, {
    headers: { 'User-Agent': UA, Accept: '*/*' },
  })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const list = await res.json()
  return Array.isArray(list) ? list.filter((s): s is string => typeof s === 'string') : []
}

/// "Zeppelinstr. (14471 Potsdam)" -> street, postcode.
const entry = (e: string) => e.match(/^(.*?)\s*\((\d{5})\s+[^)]*\)\s*$/)

async function probeSwp(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  if (!addr.street) return null
  const target = normStreet(addr.street)
  const hits = (await lookup({ street: streetStem(addr.street) }))
    .map((e) => ({ e, m: entry(e) })).filter((x) => x.m && normStreet(x.m[1]) === target)
  // The same street in two Ortsteile has two postcodes; the address's own decides.
  const pick = hits.length > 1 ? hits.filter((x) => x.m![2] === addr.postcode) : hits
  if (pick.length !== 1) return null
  const [, street, plz] = pick[0].m!
  const nrs = (await lookup({ street: pick[0].e, housenumber: '' })).filter(Boolean)
    .sort((a, b) => parseInt(a, 10) - parseInt(b, 10) || a.localeCompare(b))
  const cfg = { vendor: 'swp' as const, street, strasseId: plz }
  const want = (addr.houseNumber || '').toUpperCase().replace(/\s+/g, '')
  const hit = nrs.find((n) => n.toUpperCase() === want)
  if (hit) return { supported: true, town: town.name, street, config: { ...cfg, hnrId: hit } }
  return { supported: true, town: town.name, street, needsHouseNumber: true, hausNrList: nrs.map((n) => ({ id: n, nr: n })), config: cfg }
}

async function readSwp(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const street = (cfg.street || '').trim()
  const plz = String(cfg.strasseId ?? '')
  const nr = cfg.hnrId != null ? String(cfg.hnrId).trim() : ''
  if (!street || street.length > 80 || !/^\d{5}$/.test(plz) || !/^[0-9][0-9A-Za-z/-]{0,10}$/.test(nr)) throw new Error('reconnect_required')
  const path = [street, nr, plz].map(encodeURIComponent).join('/')
  const res = await fetchWithTimeout(`${API}/garbage/html/${path}/200`, {
    method: 'POST',
    headers: { 'User-Agent': UA, 'Content-Type': 'application/json', Accept: '*/*' },
    body: JSON.stringify({ linkMap: {}, svgLink: '', svgLinkMap: {} }),
  })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const html = await res.text()
  const rows: Array<{ day: string; title: string }> = []
  for (const li of html.split(/<li[\s>]/).slice(1)) {
    const d = li.match(/<dd>\s*[A-Za-zäöü]+,\s*(\d{1,2})\.\s*([A-Za-zäöü]+)\s+(\d{4})\s*<\/dd>/)
    const month = d ? MONTHS.indexOf(d[2].toLowerCase()) + 1 : 0
    if (!d || !month) continue
    const day = `${d[3]}-${String(month).padStart(2, '0')}-${d[1].padStart(2, '0')}`
    for (const b of li.matchAll(/<span class="link-text">([^<]+)<\/span>/g)) rows.push({ day, title: decodeEntities(b[1]).trim() })
  }
  if (!rows.length && /keine Daten/.test(html)) throw new Error('reconnect_required')
  return dayEvents(rows, `abfall:swp:${normStreet(street)}-${nr.toLowerCase()}-${plz}`, cfg.label ?? null)
}

function towns(p: AbfallProvider): Town[] {
  return [{ vendor: 'swp', name: p.town || 'Potsdam', provider: p.id }]
}

export const adapter: VendorAdapter = {
  family: 'swp',
  towns,
  probe: probeSwp,
  read: readSwp,
}
