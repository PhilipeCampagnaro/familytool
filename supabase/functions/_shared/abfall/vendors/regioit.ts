// abfall/vendors/regioit.ts — regio iT AbfallNavi — one JSON API serving many municipalities by region slug.

import {
  type AbfallConfig,
  type AbfallProvider,
  getJson,
  type StreetOption,
  type SyncedEvent,
  type Town,
  type VendorAdapter,
} from "../core.ts";

// regio-iT serves each region from a per-service subdomain
// (<slug>-abfallapp.regioit.de), but some regions only resolve on the SHARED
// host (abfallapp.regioit.de/abfall-app-<slug>). Try per-service first, fall back
// to shared, and remember whichever answered so we only pay the retry once.
const _regioitHost = new Map<string, string>()

async function regioitGet(region: string, path: string): Promise<unknown> {
  const cached = _regioitHost.get(region)
  const bases = cached ? [cached] : [
    `https://${region}-abfallapp.regioit.de/abfall-app-${region}/rest`,
    `https://abfallapp.regioit.de/abfall-app-${region}/rest`,
  ]
  let lastErr: unknown
  for (const base of bases) {
    try {
      const val = await getJson(`${base}/${path}`)
      _regioitHost.set(region, base)
      return val
    } catch (e) { lastErr = e }
  }
  throw lastErr
}

async function searchStreetsRegioit(town: Town, query: string): Promise<StreetOption[]> {
  if (!town.region || !town.ortId) return []
  const list = await regioitGet(town.region, `orte/${town.ortId}/strassen`) as Array<{
    id: number; name: string; hausNrList?: Array<{ id: number; nr: string }>
  }>
  const q = (query || '').trim().toLowerCase()
  return (Array.isArray(list) ? list : [])
    .filter((s) => !q || (s.name || '').toLowerCase().includes(q))
    .slice(0, 40)
    .map((s) => ({
      name: s.name,
      hausNrList: (s.hausNrList || []).map((h) => ({ id: h.id, nr: h.nr })),
      config: { vendor: 'regioit', region: town.region, ortId: town.ortId, strasseId: s.id },
    }))
}

async function readRegioit(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  if (!cfg.region || !cfg.strasseId) throw new Error('reconnect_required')
  // A house number gives the most precise schedule; the street is the fallback.
  const scope = cfg.hnrId ? `hausnummern/${cfg.hnrId}` : `strassen/${cfg.strasseId}`
  const [fraktionen, termine] = await Promise.all([
    regioitGet(cfg.region, 'fraktionen') as Promise<Array<{ id: number; name: string }>>,
    regioitGet(cfg.region, `${scope}/termine`) as Promise<Array<{
      id?: number; datum?: string; bezirk?: { fraktionId?: number }
    }>>,
  ])
  const fname = new Map<number, string>()
  for (const f of (Array.isArray(fraktionen) ? fraktionen : [])) fname.set(f.id, f.name)

  const events: SyncedEvent[] = []
  for (const t of (Array.isArray(termine) ? termine : [])) {
    if (!t?.datum) continue
    const start = new Date(`${t.datum}T00:00:00Z`)
    if (isNaN(start.getTime())) continue
    // All-day events use an exclusive end (like Google's date-only end): +1 day.
    const end = new Date(start)
    end.setUTCDate(end.getUTCDate() + 1)
    const fid = t.bezirk?.fraktionId
    const title = (fid != null && fname.get(fid)) || 'Abfuhr'
    // strasseId/hnrId scope the uid: termin ids are shared district-wide, so two
    // family addresses in one region would otherwise collide (and their events
    // would wrongly merge into one on the calendar).
    events.push({
      uid: `abfall:regioit:${cfg.region}:${cfg.strasseId}:${cfg.hnrId ?? ''}:${t.id ?? `${t.datum}:${fid}`}`,
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
  if (!p.region) return []
  const orte = await regioitGet(p.region, 'orte') as Array<{ id: number; name: string }>
  return (Array.isArray(orte) ? orte : []).map((o) => ({
    vendor: 'regioit', name: o.name, provider: p.id, region: p.region, ortId: o.id,
  }))
}

export const adapter: VendorAdapter = {
  family: 'regioit',
  towns,
  searchStreets: searchStreetsRegioit,
  read: readRegioit,
}
