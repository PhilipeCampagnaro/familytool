// abfall/vendors/ctrace.ts — C-Trace — no street enumeration; the server validates the street itself.

import {
  type AbfallConfig,
  type AbfallProvider,
  fetchWithTimeout,
  type GeoAddress,
  parseIcs,
  type ResolveResult,
  streetSpellings,
  type SyncedEvent,
  type Town,
  UA,
  type VendorAdapter,
} from "../core.ts";

// The export wants an explicit waste-type filter; 0..299 = everything.
const CTRACE_ALL_TYPES = Array.from({ length: 300 }, (_, i) => i).join('|')

async function ctraceFetchIcs(cfg: AbfallConfig): Promise<string> {
  if (!cfg.host || !cfg.service) throw new Error('reconnect_required')
  const base = `https://${cfg.host}/${cfg.service}`
  // First hit redirects to /<service>/(S(<session>))/... — grab the session.
  const r0 = await fetchWithTimeout(`${base}/Abfallkalender`, {
    redirect: 'manual', headers: { 'User-Agent': UA },
  })
  await r0.body?.cancel()
  const loc = r0.headers.get('location') || ''
  const sess = loc.match(/\(S\([^)]*\)\)/)?.[0] || ''
  const params = new URLSearchParams({
    Ort: cfg.ort || '',
    Gemeinde: cfg.ort || '',
    Strasse: cfg.street || '',
    Hausnr: cfg.hnr || '',
    Abfall: CTRACE_ALL_TYPES,
  })
  const res = await fetchWithTimeout(
    `${base}${sess ? `/${sess}` : ''}/abfallkalender/${cfg.icalFile || 'cal'}?${params}`,
    { headers: { 'User-Agent': UA, Accept: 'text/calendar, */*' } },
  )
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  return (await res.text()).replace(/^﻿/, '')
}

// Coverage probe: try the export with the geocoded street. Events back = the
// street exists and this IS its schedule; an error/empty = not this provider.
// The server requires a house number; when the geocoder has none, "1" works.
async function probeCtrace(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  if (!addr.street) return null
  const hnrs = [...new Set([(addr.houseNumber || '1').trim() || '1', '1'])]
  // Landau's instance stores its streets abbreviated — "Königstr." answers,
  // "Königstraße" is a 500 — and the geocoder writes them out, so essentially
  // every real Landau address was "nicht unterstützt" (live probe 2026-09-17).
  // Try the street as written, then the other spelling.
  for (const street of streetSpellings(addr.street)) {
    for (const hnr of hnrs) {
      const config: AbfallConfig = {
        vendor: 'ctrace', host: town.host, service: town.service,
        icalFile: town.icalFile, ort: town.city ?? '', street, hnr,
      }
      try {
        const ics = await ctraceFetchIcs(config)
        if (ics.includes('BEGIN:VEVENT')) {
          return { supported: true, town: town.name, street, config }
        }
      } catch { /* try the next spelling / house number */ }
    }
  }
  return null
}

// Sync-time reader. Event titles come as "Abfuhr: Restmüll" — strip the prefix
// so classifyWaste sees the bin name.
async function readCtrace(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  if (!cfg.street) throw new Error('reconnect_required')
  const ics = await ctraceFetchIcs(cfg)
  if (!ics.includes('BEGIN:VEVENT')) return []
  const thisYear = new Date().getUTCFullYear()
  const start = new Date(Date.UTC(thisYear - 1, 0, 1))
  const end = new Date(Date.UTC(thisYear + 2, 0, 1))
  const out: SyncedEvent[] = []
  const seen = new Set<string>()
  for (const ev of parseIcs(ics, start, end)) {
    const title = ev.title.replace(/^Abfuhr:\s*/i, '') || 'Abfuhr'
    const dayKey = `${ev.startsAt.slice(0, 10)}:${title}`
    if (seen.has(dayKey)) continue
    seen.add(dayKey)
    out.push({
      ...ev,
      uid: `abfall:ctrace:${cfg.service}:${cfg.ort || ''}:${cfg.street}:${dayKey}`,
      title,
      notes: null,
      location: cfg.label ?? ev.location ?? null,
    })
  }
  return out
}

function towns(p: AbfallProvider): Town[] {
  if (!p.host || !p.service) return []
  // Static: one town per service; streets are validated by the probe instead of
  // enumerated (see probeCtrace).
  return [{
    vendor: 'ctrace', name: p.town || p.name, provider: p.id,
    host: p.host, service: p.service, icalFile: p.icalFile, city: p.ort ?? '',
  }]
}

// No searchStreets: this vendor has no street list to offer.
export const adapter: VendorAdapter = {
  family: 'ctrace',
  towns,
  probe: probeCtrace,
  read: readCtrace,
}
