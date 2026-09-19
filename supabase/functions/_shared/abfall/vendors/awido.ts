// abfall/vendors/awido.ts — AWIDO Online (Cubefour) — many municipalities keyed by a client id.

import {
  type AbfallConfig,
  type AbfallProvider,
  getJson,
  type HausNr,
  type StreetOption,
  type SyncedEvent,
  type Town,
  type VendorAdapter,
} from "../core.ts";

// AWIDO Online (Cubefour) — one shared host for every customer; the customer
// slug rides in the URL (note: `client=` is a PATH segment on getPlaces, a query
// param elsewhere — that asymmetry is the vendor's, not ours).
const AWIDO_BASE = 'https://awido.cubefour.de/WebServices/Awido.Service.svc/secure'

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

// AWIDO: one getData call returns the full calendar year as JSON — pickup dates
// (dt=YYYYMMDD, fr=fraction codes) plus the fraction-code -> name map (fracts).
// Entries with fr=null are public holidays, not pickups. A picked house number
// (hnrId = addon GUID) replaces the street oid.
//
// **Only /WebServices/ is ours to call.** awido.cubefour.de's robots.txt
// disallows /Customer/, which is where the per-street ICS export lives, so the
// fallback to it that stood here is gone (2026-09-19): a client without the
// JSON payload fails like any other upstream error. The live probe never
// reached for it.
// Fractions that are not a bin at the kerb: EBU Ulm's feed carries its Repair
// Café (76 a year, with Neu-Ulm addresses), swap days, clean-ups, events and the
// clubs' own paper collections beside the pickups.
const NOT_A_PICKUP = /veranstaltung|warentausch|reparatur|putzete|vereins/i

async function readAwido(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  if (!cfg.client || !cfg.oid) throw new Error('reconnect_required')
  const oid = (typeof cfg.hnrId === 'string' && cfg.hnrId) || cfg.oid
  let data: {
    fracts?: Array<{ snm: string; nm: string }>
    calendar?: Array<{ dt?: string; fr?: string[] | null }>
  }
  data = await getJson(
    `${AWIDO_BASE}/getData/${oid}?fractions=&client=${cfg.client}`,
  ) as typeof data
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
      if (NOT_A_PICKUP.test(fname.get(fr) || '')) continue
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

async function towns(p: AbfallProvider): Promise<Town[]> {
  if (!p.client) return []
  const places = await getJson(
    `${AWIDO_BASE}/getPlaces/client=${p.client}`,
  ) as Array<{ key: string; value: string }>
  return (Array.isArray(places) ? places : []).map((pl) => ({
    vendor: 'awido', name: pl.value, provider: p.id, client: p.client, placeKey: pl.key,
  }))
}

// AWIDO house numbers live behind an extra per-street call, so they are fetched
// only for the one matched street. No addons = a street-level schedule.
async function houseNumbers(opt: StreetOption): Promise<HausNr[] | undefined> {
  if (!opt.config.oid) return undefined
  const addons = await getJson(
    `${AWIDO_BASE}/getStreetAddons/${opt.config.oid}?client=${opt.config.client}`,
  ) as Array<{ key: string; value: string }>
  return (Array.isArray(addons) ? addons : [])
    .filter((a) => (a.value || '').trim())
    .map((a) => ({ id: a.key, nr: a.value }))
}

export const adapter: VendorAdapter = {
  family: 'awido',
  towns,
  searchStreets: searchStreetsAwido,
  houseNumbers,
  read: readAwido,
}
