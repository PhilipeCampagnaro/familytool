// abfall/vendors/heilbronn.ts — Stadt Heilbronn, Abfallwirtschaft — the
// city's own API behind its "Abfall App": two whole-city JSON files.

import {
  type AbfallConfig,
  type AbfallProvider,
  dayEvents,
  fetchWithTimeout,
  type GeoAddress,
  normStreet,
  type ResolveResult,
  type SyncedEvent,
  type Town,
  UA,
  type VendorAdapter,
} from "../core.ts";

// ── Heilbronn (api.heilbronn.de, no key) ─────────────────────────────────────
//
//   …/garbage-calendar?method=get&datatype=districts     (~450 KB)
//        {data: {"74072": {"Allee": {"1": {residual:"72", bio:"72",
//                 paper:"72-2", yellow:"72-2", green:"72"}, "*": …}}}}
//   …/garbage-calendar?method=get&datatype=pickupdates   (~160 KB)
//        {data: {"72": {"residual_2": {"<ts>": "2026-09-24"}, "bio_1": …}}}
//
// An address is a PLZ, a street and a house number (or "*" for the whole
// street); it names one **district code per bin**, and the dates hang off the
// codes. So connecting reads the big file once and stores the five codes, and
// every refresh reads only the dates. 19 street names exist under two PLZ, so
// the PLZ decides. The dates run about a year ahead and cross the new year.
//
// Which series a normal household gets is what the city's own app shows:
// `residual_2`, Bio as `bio` + `bio_1` (the summer extra) + `bio_2`, `paper` and
// `paper-bundle`, `light-packaging`, `green` and `christmastree`. The
// `*_big_*` series are for 770/1100-litre containers, which a house with
// ordinary bins does not have, and are left out.
const API = 'https://api.heilbronn.de/garbage-calendar'

type Codes = { residual?: string; bio?: string; paper?: string; yellow?: string; green?: string }
const SLOTS = ['residual', 'bio', 'paper', 'yellow', 'green'] as const
const SERIES: Record<typeof SLOTS[number], Array<[string, string]>> = {
  residual: [['residual_2', 'Restmüll']],
  bio: [['bio', 'Biomüll'], ['bio_1', 'Biomüll'], ['bio_2', 'Biomüll']],
  paper: [['paper', 'Papier'], ['paper-bundle', 'Papier (gebündelt)']],
  yellow: [['light-packaging', 'Gelber Sack']],
  green: [['green', 'Grüngut'], ['christmastree', 'Christbaum']],
}

async function get<T>(datatype: string): Promise<T> {
  const res = await fetchWithTimeout(`${API}?method=get&datatype=${datatype}`, {
    headers: { 'User-Agent': UA, Accept: 'application/json' },
  })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const body = await res.json() as { data?: T }
  if (!body?.data) throw new Error('abfall upstream: unexpected answer')
  return body.data
}

const pack = (c: Codes) => SLOTS.map((s) => c[s] ?? '').join('|')

async function probeHn(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  if (!addr.street) return null
  const target = normStreet(addr.street)
  const data = await get<Record<string, Record<string, Record<string, Codes>>>>('districts')
  let found = Object.entries(data).flatMap(([plz, streets]) =>
    Object.entries(streets).filter(([name]) => normStreet(name) === target).map(([name, houses]) => ({ plz, name, houses })))
  if (found.length > 1 && addr.postcode) {
    const byPlz = found.filter((f) => f.plz === addr.postcode)
    if (byPlz.length) found = byPlz
  }
  if (!found.length) return null
  const street = found[0].name
  const cfg = { vendor: 'heilbronn' as const, street }
  const want = (addr.houseNumber || '').toLowerCase().replace(/\s+/g, '')
  const houses = found.flatMap((f) => Object.entries(f.houses).map(([nr, c]) => ({
    nr: found.length > 1 ? `${nr} (${f.plz})` : nr, key: nr.toLowerCase(), id: pack(c),
  })))
  const hit = houses.filter((h) => h.key === want)
  const whole = houses.filter((h) => h.key === '*')
  const pick = hit.length === 1 ? hit[0] : (!hit.length && whole.length === 1 && houses.length === 1) ? whole[0] : undefined
  if (pick) return { supported: true, town: town.name, street, config: { ...cfg, hnrId: pick.id } }
  // One plan for every house on the street: no number to ask for.
  if (new Set(houses.map((h) => h.id)).size === 1) return { supported: true, town: town.name, street, config: { ...cfg, hnrId: houses[0].id } }
  return {
    supported: true, town: town.name, street, needsHouseNumber: true,
    hausNrList: houses.filter((h) => h.key !== '*').map(({ id, nr }) => ({ id, nr })),
    config: cfg,
  }
}

async function readHn(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const packed = cfg.hnrId != null ? String(cfg.hnrId) : ''
  const codes = packed.split('|')
  if (codes.length !== SLOTS.length || !codes.every((c) => /^[A-Za-zÄÖÜäöü0-9-]{0,8}$/.test(c)) || !codes.some(Boolean)) {
    throw new Error('reconnect_required')
  }
  const dates = await get<Record<string, Record<string, Record<string, string>>>>('pickupdates')
  const rows: Array<{ day: string; title: string }> = []
  SLOTS.forEach((slot, i) => {
    const d = dates[codes[i]]
    if (!codes[i]) return
    if (!d) throw new Error('reconnect_required')
    for (const [series, title] of SERIES[slot]) {
      for (const day of Object.values(d[series] ?? {})) rows.push({ day: String(day).slice(0, 10), title })
    }
  })
  rows.sort((a, b) => a.day.localeCompare(b.day))
  return dayEvents(rows, `abfall:heilbronn:${packed}`, cfg.label ?? null)
}

function towns(p: AbfallProvider): Town[] {
  return [{ vendor: 'heilbronn', name: p.town || 'Heilbronn', provider: p.id }]
}

export const adapter: VendorAdapter = {
  family: 'heilbronn',
  towns,
  probe: probeHn,
  read: readHn,
}
