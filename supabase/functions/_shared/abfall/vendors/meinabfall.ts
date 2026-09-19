// abfall/vendors/meinabfall.ts — Mein-Abfallkalender (krissel.it) — the
// calendar erlangen.de links as the city's own, one subdomain per tenant.

import {
  type AbfallConfig,
  type AbfallProvider,
  dayEvents,
  decodeEntities,
  fetchWithTimeout,
  type GeoAddress,
  inSpans,
  normStreet,
  type NrSpan,
  type ResolveResult,
  restRhythm,
  type SyncedEvent,
  type Town,
  UA,
  type VendorAdapter,
} from "../core.ts";

// ── Mein-Abfallkalender (<tenant>.mein-abfallkalender.online) ────────────────
//
//   GET /                         <select name="street_id">, "Adlerstraße, Altstadt",
//                                 "Hauptstraße Hausnr. 01 - 19, Innenstadt"
//   GET /?street_id=<id>&filter_period=all.<year>&filter_waste:list=<fraction>…
//        &column_order=da_wa_we  one <tr class="dates"> per bin per day
//
// **Always send column_order**, or the columns come back in another order. The
// fractions are the tenant's own ids and are read off the start page. Its
// iCal route asks for an e-mail address and DSGVO consent — a registration,
// and not used. Street entries carry free-text house ranges and a validity
// ("gültig bis 31.12.2025", "(bis 31.12.2020)", "(ab 1.01.2021)"); an entry that
// is no longer valid is dropped, and the range picks the entry when the street
// has several. A range whose two ends share a parity ("01 - 19") is taken as
// that side of the street. Holiday notes are rows of their own and are not
// read. An unknown id answers with no rows; a year not yet published does too.
const TENANT = /^[a-z0-9-]{2,30}$/

async function get(tenant: string, query = ''): Promise<string> {
  const res = await fetchWithTimeout(`https://${tenant}.mein-abfallkalender.online/${query}`, {
    headers: { 'User-Agent': UA, Accept: 'text/html' },
  })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  return res.text()
}

interface Entry { id: string; street: string; range: string; district: string; spans: NrSpan[] }

function dateOf(d: string, m: string, y: string): string {
  return `${y}-${m.padStart(2, '0')}-${d.padStart(2, '0')}`
}

/// Every street entry that is valid today.
function entries(page: string, today: string): Entry[] {
  const sel = page.match(/<select[^>]*name="street_id"[\s\S]*?<\/select>/)?.[0] ?? ''
  const out: Entry[] = []
  for (const m of sel.matchAll(/<option value="(\d+)"[^>]*>([^<]+)/g)) {
    let text = decodeEntities(m[2]).trim()
    const until = text.match(/bis\s+(\d{1,2})\.(\d{1,2})\.(\d{4})/)
    if (until && dateOf(until[1], until[2], until[3]) < today) continue
    const from = text.match(/\(ab\s+(\d{1,2})\.(\d{1,2})\.(\d{4})\)/)
    if (from && dateOf(from[1], from[2], from[3]) > today) continue
    text = text.replace(/\s*\((?:bis|ab)[^)]*\)|\s*gültig bis\s+\S+/g, '')
    const comma = text.lastIndexOf(',')
    const district = comma > 0 ? text.slice(comma + 1).trim() : ''
    const name = comma > 0 ? text.slice(0, comma).trim() : text
    const [street, range = ''] = name.split(/\s+Hausnr\.\s*/)
    const spans: NrSpan[] = []
    for (const part of range.split(/\s+und\s+|\s*,\s*/)) {
      const r = part.match(/^0*(\d+)\s*([a-z]?)\s*(?:[-–]\s*0*(\d+)\s*([a-z]?))?/i)
      if (!r) continue
      const a = Number(r[1]), b = r[3] ? Number(r[3]) : a
      spans.push({ from: [a, (r[2] || '').toLowerCase()], to: [b, (r[4] || '').toLowerCase()], parity: r[3] && a % 2 === b % 2 ? (a % 2) as 0 | 1 : null })
    }
    out.push({ id: m[1], street: street.trim(), range: range.trim(), district, spans })
  }
  return out
}

async function probeMa(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  const tenant = town.client || ''
  if (!addr.street || !TENANT.test(tenant)) return null
  const today = new Date().toISOString().slice(0, 10)
  const target = normStreet(addr.street)
  const hits = entries(await get(tenant), today).filter((e) => normStreet(e.street) === target)
  if (!hits.length) return null
  const street = hits[0].street
  const cfg = { vendor: 'meinabfall' as const, client: tenant, street }
  let pick = hits
  if (pick.length > 1 && addr.houseNumber) {
    const fit = hits.filter((e) => e.spans.length && inSpans(e.spans, addr.houseNumber!))
    if (fit.length) pick = fit
  }
  if (pick.length === 1) return { supported: true, town: town.name, street, config: { ...cfg, hnrId: pick[0].id } }
  return {
    supported: true, town: town.name, street, needsHouseNumber: true,
    hausNrList: pick.map((e) => ({ id: e.id, nr: [e.range, e.district].filter(Boolean).join(', ') })), config: cfg,
  }
}

async function readMa(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const tenant = cfg.client || ''
  const id = String(cfg.hnrId ?? '')
  if (!TENANT.test(tenant) || !/^\d{1,9}$/.test(id)) throw new Error('reconnect_required')
  const start = await get(tenant)
  const fractions = [...new Set([...start.matchAll(/name="filter_waste:list"[^>]*value="(\d+)"|value="(\d+)"[^>]*name="filter_waste:list"/g)]
    .map((m) => m[1] || m[2]))]
  if (!fractions.length) throw new Error('abfall upstream: no fractions')
  const y = new Date().getUTCFullYear()
  const year = async (yr: number) => {
    const q = new URLSearchParams([['street_id', id], ['filter_period', `all.${yr}`], ...fractions.map((f) => ['filter_waste:list', f]), ['column_order', 'da_wa_we']])
    return get(tenant, `?${q}`)
  }
  const [now, next] = await Promise.all([year(y), year(y + 1).catch(() => '')])
  // Erlangen prints the bin as text, Neuss as a link to its description.
  const ROW = /<tr[^>]*class="dates"[^>]*>\s*<td>(\d{2})\.(\d{2})\.(\d{4})<\/td>[\s\S]*?<td class="nowrap">\s*(?:<a\b[^>]*>)?([^<]+)</g
  const rows = [...now.matchAll(ROW), ...next.matchAll(ROW)]
    .map((m) => ({ day: `${m[3]}-${m[2]}-${m[1]}`, title: decodeEntities(m[4]).trim() }))
  if (!rows.length) throw new Error('reconnect_required')
  return dayEvents(rows, `abfall:meinabfall:${tenant}:${id}`, cfg.label ?? null)
}

function towns(p: AbfallProvider): Town[] {
  return [{ vendor: 'meinabfall', name: p.town || '', provider: p.id, client: p.client }]
}

export const adapter: VendorAdapter = {
  family: 'meinabfall',
  towns,
  probe: probeMa,
  // Neuss: "Restmüll-Grau" and "Restmüll-Pink", the lid colours of its weekly
  // and fortnightly bins.
  rhythm: restRhythm,
  read: readMa,
}
