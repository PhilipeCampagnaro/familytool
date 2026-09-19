// abfall/vendors/abis.ts — ABIS (flynet) — the calendar GELSENDIENSTE
// (Gelsenkirchen) and BEST (Bottrop) run on their own sites and apps.

import {
  type AbfallConfig,
  type AbfallProvider,
  dayEvents,
  fetchWithTimeout,
  type GeoAddress,
  icsDays,
  normStreet,
  type ResolveResult,
  type SyncedEvent,
  type Town,
  UA,
  type VendorAdapter,
} from "../core.ts";

// ── ABIS (<tenant>.abisapp.de) ──────────────────────────────────────────────
//
//   GET https://<host>/api/street   -> [{"id":"FBEDAE97","locality":"…","name":"Ackerstr."}]
//   GET https://<host>/abfuhrkalender?format=ical&street=<id>&number=<nr>
//
// The authority's page loads flynet's script, which proxies to the same host;
// the tenant host answers directly. The plan is **per house and the number is
// free text that is never checked** — 9999 gets a calendar — so it is required,
// and it is the street, not the number, that stops a made-up address. An unknown
// street id answers an HTML page with 200, told apart by the content type. The
// ICS runs from about six months back to the end of next year, so the new year
// is already in it. GELSENDIENSTE also plans 2- and 4-weekly Restabfall for some
// households on paper only; the API shows the weekly grey bin everywhere, so a
// household on the slower rhythm sees more dates than it has.
const ID = /^[0-9A-F]{8}$/

interface Street { id: string; locality?: string; name: string }

async function streets(host: string): Promise<Street[]> {
  const res = await fetchWithTimeout(`https://${host}/api/street`, { headers: { 'User-Agent': UA, Accept: 'application/json' } })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const body = await res.json()
  return Array.isArray(body) ? body as Street[] : []
}

async function probeAbis(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  if (!addr.street || !town.host) return null
  const target = normStreet(addr.street)
  const hits = (await streets(town.host)).filter((s) => normStreet(s.name) === target && ID.test(s.id))
  if (!hits.length) return null
  const street = hits[0].name
  const nr = (addr.houseNumber || '').trim()
  const cfg = { vendor: 'abis' as const, host: town.host, street, strasseId: hits[0].id }
  if (hits.length > 1) {
    return {
      supported: true, town: town.name, street, needsHouseNumber: !nr,
      hausNrList: hits.map((h) => ({ id: h.id, nr: `${nr} (${(h.locality || '').trim()})`.trim() })),
      config: { ...cfg, hnr: nr || undefined },
    }
  }
  if (!nr) return { supported: true, town: town.name, street, needsHouseNumber: true, config: cfg }
  return { supported: true, town: town.name, street, config: { ...cfg, hnr: nr } }
}

async function readAbis(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const host = cfg.host || ''
  // A twin street picked from the list arrives as hnrId; otherwise strasseId.
  const id = String((cfg.hnrId && ID.test(String(cfg.hnrId)) ? cfg.hnrId : cfg.strasseId) ?? '')
  const nr = (cfg.hnr || '').trim()
  if (!/^[a-z]+\.abisapp\.de$/.test(host) || !ID.test(id) || !/^[0-9][0-9a-zA-Z /-]{0,10}$/.test(nr)) {
    throw new Error('reconnect_required')
  }
  const q = new URLSearchParams({ format: 'ical', street: id, number: nr })
  const res = await fetchWithTimeout(`https://${host}/abfuhrkalender?${q}`, { headers: { 'User-Agent': UA, Accept: 'text/calendar, */*' } })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  if (!(res.headers.get('content-type') || '').includes('calendar')) throw new Error('reconnect_required')
  return dayEvents(icsDays(await res.text()), `abfall:abis:${host.split('.')[0]}-${id}-${nr.toLowerCase().replace(/\s+/g, '')}`, cfg.label ?? null)
}

function towns(p: AbfallProvider): Town[] {
  return [{ vendor: 'abis', name: p.town || '', provider: p.id, host: p.host }]
}

export const adapter: VendorAdapter = {
  family: 'abis',
  towns,
  probe: probeAbis,
  read: readAbis,
}
