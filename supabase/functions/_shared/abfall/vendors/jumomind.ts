// abfall/vendors/jumomind.ts — Jumomind / MyMuell app API — many municipalities keyed by a service id.

import {
  type AbfallConfig,
  type AbfallProvider,
  getJson,
  type StreetOption,
  type SyncedEvent,
  type Town,
  type VendorAdapter,
} from "../core.ts";

// Jumomind serves some responses with broken content-encoding; their own app
// requests identity, so we do too (harmless where it's not needed).
const JUMO_HEADERS = { 'Accept-Encoding': 'identity' }

function jumoUrl(service: string, params: string): string {
  return `https://${service}.jumomind.com/mmapp/api.php?${params}`
}

async function searchStreetsJumomind(town: Town, query: string): Promise<StreetOption[]> {
  if (!town.service || !town.cityId) return []
  // Whole-town schedule: no street list exists; the city-level area id IS the
  // schedule key. Surface it as one pseudo-street named like the town.
  if (!town.hasStreets) {
    return [{
      name: town.name,
      config: {
        vendor: 'jumomind', service: town.service,
        cityId: town.cityId, areaId: town.areaId,
      },
    }]
  }
  const list = await getJson(
    jumoUrl(town.service, `r=streets&city_id=${encodeURIComponent(town.cityId)}`),
    JUMO_HEADERS,
  ) as Array<{ name: string; area_id: string; houseNumbers?: Array<[string, string]> }>
  const q = (query || '').trim().toLowerCase()
  return (Array.isArray(list) ? list : [])
    .filter((s) => !q || (s.name || '').toLowerCase().includes(q))
    .slice(0, 40)
    .map((s) => ({
      name: s.name,
      // A street can span collection zones; each house number then carries its
      // own area id. Encode both into the pick id ("nr|areaId") — unique per
      // number — and readJumomind() decodes the area id back out of hnrId.
      hausNrList: (s.houseNumbers || []).map((h) => ({ id: `${h[0]}|${h[1]}`, nr: h[0] })),
      config: {
        vendor: 'jumomind', service: town.service,
        cityId: town.cityId, areaId: s.area_id,
      },
    }))
}

// Jumomind: one dates call returns upcoming pickups with human titles baked in.
// The schedule key is (city_id, area_id); a picked house number refines the
// area id (hnrId = "nr|areaId" — see searchStreetsJumomind).
async function readJumomind(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  if (!cfg.service || !cfg.cityId) throw new Error('reconnect_required')
  let areaId = cfg.areaId
  if (typeof cfg.hnrId === 'string' && cfg.hnrId.includes('|')) {
    areaId = cfg.hnrId.slice(cfg.hnrId.lastIndexOf('|') + 1)
  }
  if (areaId == null || areaId === '') throw new Error('reconnect_required')
  const list = await getJson(
    jumoUrl(cfg.service, `r=dates/0&city_id=${encodeURIComponent(cfg.cityId)}`
      + `&area_id=${encodeURIComponent(areaId)}&ws=3`),
    JUMO_HEADERS,
  ) as Array<{ title?: string; day?: string; trash_name?: string }>

  const events: SyncedEvent[] = []
  for (const t of (Array.isArray(list) ? list : [])) {
    if (!t?.day) continue
    const start = new Date(`${t.day}T00:00:00Z`)
    if (isNaN(start.getTime())) continue
    const end = new Date(start)
    end.setUTCDate(end.getUTCDate() + 1)
    const title = t.title || t.trash_name || 'Abfuhr'
    events.push({
      uid: `abfall:jumomind:${cfg.service}:${cfg.cityId}:${areaId}:${t.day}:${t.trash_name || title}`,
      title,
      notes: null,
      location: cfg.label ?? null,
      startsAt: start.toISOString(),
      endsAt: end.toISOString(),
      allDay: true,
    })
  }
  return events
}

async function towns(p: AbfallProvider): Promise<Town[]> {
  if (!p.service) return []
  const cities = await getJson(
    jumoUrl(p.service, 'r=cities_web'), JUMO_HEADERS,
  ) as Array<{ id: string; name: string; area_id: string; has_streets: boolean }>
  // An allowlisted host (MyMüll) serves only the towns named on its row.
  const allowed = (name: string) => !p.cities ||
    p.cities.some((c) => name === c || name.startsWith(`${c}-`) || name.startsWith(`${c} -`))
  return (Array.isArray(cities) ? cities : []).filter((c) => allowed(c.name)).map((c) => ({
    vendor: 'jumomind', name: c.name, provider: p.id, service: p.service,
    cityId: c.id, areaId: c.area_id, hasStreets: !!c.has_streets,
  }))
}

export const adapter: VendorAdapter = {
  family: 'jumomind',
  towns,
  searchStreets: searchStreetsJumomind,
  read: readJumomind,
}
