// abfall/vendors/sab.ts — SAB Städtischer Abfallwirtschaftsbetrieb Magdeburg —
// the Abfuhrkalender magdeburg.de iframes (hosted by metageneric).

import {
  type AbfallConfig,
  type AbfallProvider,
  dayEvents,
  decodeEntities,
  fetchWithTimeout,
  type GeoAddress,
  inSpans,
  normStreet,
  type ResolveResult,
  splitSpans,
  type SyncedEvent,
  type Town,
  UA,
  type VendorAdapter,
} from "../core.ts";

// ── SAB Magdeburg (sab.ssl.metageneric.de/app/sab_i_tp/) ────────────────────
//
//   GET  index.php                            <select id="strasse"> of every street,
//                                             and js/sab2026_2025.js
//   GET  js/sab<y>_<y>.js                     names the season's endpoint, index.2025_2026.php
//   POST <endpoint> r=getStandplatzInfo&strasse=<name>   house buttons get('7-9a','h3')
//   POST <endpoint> r=getHausnummerInfo&strasse=&hausnummer=  the dates, as HTML
//
// **The endpoint's file name carries the season** and is looked up every time,
// not stored. There is no ICS: each bin is an <h3> followed by its dates
// ("Mo&nbsp;21.09.2026"), a leading "*" marking a holiday move, and the page
// ends in a machine tail (###$$$###…) that is not read. A house entry can be a
// range or list ("7-9a", "10,12"). The Gelbe Tonne comes pre-selected for the
// address's Stadtteil and the household bin size (120/240 l); a 1,100-litre
// block container is the rare case and is not asked for. The window runs from
// today to 31 December.
const BASE = 'https://sab.ssl.metageneric.de/app/sab_i_tp/'

async function get(path: string): Promise<string> {
  const res = await fetchWithTimeout(`${BASE}${path}`, { headers: { 'User-Agent': UA, Accept: 'text/html,*/*' } })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  return res.text()
}

async function endpoint(): Promise<{ page: string; url: string }> {
  const page = await get('index.php')
  const js = page.match(/js\/(sab\d{4}_\d{4}\.js)/)?.[1]
  const ep = js ? (await get(`js/${js}`)).match(/index\.\d{4}_\d{4}\.php/)?.[0] : undefined
  if (!ep) throw new Error('abfall upstream: no SAB endpoint')
  return { page, url: `${BASE}${ep}` }
}

async function post(url: string, form: Record<string, string>): Promise<string> {
  const res = await fetchWithTimeout(url, {
    method: 'POST',
    headers: { 'User-Agent': UA, 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(form).toString(),
  })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  return res.text()
}

async function probeSab(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  if (!addr.street) return null
  const { page, url } = await endpoint()
  const sel = page.match(/<select[^>]*id="strasse"[\s\S]*?<\/select>/)?.[0] ?? ''
  const target = normStreet(addr.street)
  const street = [...sel.matchAll(/<option[^>]*value="([^"]+)"/g)].map((m) => decodeEntities(m[1]).trim())
    .find((s) => normStreet(s) === target)
  if (!street) return null
  const html = await post(url, { r: 'getStandplatzInfo', strasse: street })
  const nrs = [...html.matchAll(/get\('([^']+)','h\d+'\)/g)].map((m) => decodeEntities(m[1]))
  const cfg = { vendor: 'sab' as const, street }
  if (!nrs.length) return null
  const want = (addr.houseNumber || '').toLowerCase().replace(/\s+/g, '')
  let hit = nrs.filter((n) => n.toLowerCase().replace(/\s+/g, '') === want)
  if (!hit.length && want) hit = nrs.filter((n) => /[-,]/.test(n) && inSpans(splitSpans(`x ${n.replace(/,/g, ' / ')}`).spans, want))
  if (hit.length === 1) return { supported: true, town: town.name, street, config: { ...cfg, hnrId: hit[0] } }
  return { supported: true, town: town.name, street, needsHouseNumber: true, hausNrList: nrs.map((n) => ({ id: n, nr: n })), config: cfg }
}

async function readSab(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const street = (cfg.street || '').trim()
  const nr = cfg.hnrId != null ? String(cfg.hnrId).trim() : ''
  if (!street || street.length > 80 || !nr || nr.length > 30) throw new Error('reconnect_required')
  const { url } = await endpoint()
  const html = (await post(url, { r: 'getHausnummerInfo', strasse: street, hausnummer: nr })).split('###$$$###')[0]
  const rows: Array<{ day: string; title: string; notes: string | null }> = []
  // The Gelbe Tonne's size picker opens an empty <h3> of its own; its dates
  // after that still belong to the bin above.
  let title = ''
  for (const block of html.split(/<h3[^>]*>/).slice(1)) {
    title = decodeEntities(block.slice(0, block.indexOf('<')).trim()) || title
    if (!title) continue
    for (const m of block.matchAll(/(\*?)&nbsp;[A-Za-z]{2}&nbsp;(\d{2})\.(\d{2})\.(\d{4})/g)) {
      rows.push({ day: `${m[4]}-${m[3]}-${m[2]}`, title, notes: m[1] ? 'Verschoben (Feiertag)' : null })
    }
  }
  if (!rows.length) throw new Error('reconnect_required')
  return dayEvents(rows, `abfall:sab:${normStreet(street)}-${nr.toLowerCase().replace(/[^a-z0-9]/g, '')}`, cfg.label ?? null)
}

function towns(p: AbfallProvider): Town[] {
  return [{ vendor: 'sab', name: p.town || 'Magdeburg', provider: p.id }]
}

export const adapter: VendorAdapter = {
  family: 'sab',
  towns,
  probe: probeSab,
  read: readSab,
}
