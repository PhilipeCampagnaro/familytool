// abfall/vendors/waswob.ts — WAS Wolfsburger Abfallwirtschaft und
// Straßenreinigung — the authority's own JSON API behind abfuhrtermine.waswob.de.

import {
  type AbfallConfig,
  type AbfallProvider,
  fetchWithTimeout,
  type GeoAddress,
  normStreet,
  type ResolveResult,
  type SyncedEvent,
  type Town,
  UA,
  type VendorAdapter,
} from "../core.ts";

// ── WAS Wolfsburg ───────────────────────────────────────────────────────────
//
//   GET …/php/abfuhr_api.php?action=strassen
//        -> {"1": {strIndex, strName, Hausnummer: ["1","2","21a",…]}, …}
//   GET …/php/abfuhr_api.php?action=termine&strasse=<name>&hausnummer=<nr>
//        -> {"<name>_<nr>": {ortsteil, behaelter: {"240": {"Restabfall":
//            {"2026-09-28": "", "2026-12-22": "Feiertagsverschiebung"}}}}}
//
// One call names every street with every house number (1,322 streets, names
// unique across Ortsteile), so the number is checked before anything is read.
// **An unknown address is a 502** with `success:false` — indistinguishable from
// an outage, which is the other reason the list is asked first.
//
// The plan is per house and per container: "240" and "770/1100" are container
// sizes, and a block of flats can have both, on different days (WAS warns holiday
// shifts may differ for the big ones). Both are kept; the size goes in the notes.
// The window is a rolling ~20 weeks and crosses the new year by itself.
const API = 'https://abfuhrtermine.waswob.de/php/abfuhr_api.php'

interface Street { strName: string; Hausnummer?: string[] }

async function streets(): Promise<Street[]> {
  const res = await fetchWithTimeout(`${API}?action=strassen`, { headers: { 'User-Agent': UA, Accept: 'application/json' } })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const body = await res.json() as Record<string, Street>
  return Object.values(body ?? {}).filter((s) => s && typeof s.strName === 'string')
}

const normNr = (s: string) => s.toLowerCase().replace(/\s+/g, '')

async function probeWas(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  if (!addr.street) return null
  const target = normStreet(addr.street)
  const st = (await streets()).find((s) => normStreet(s.strName) === target)
  if (!st) return null
  const nrs = st.Hausnummer ?? []
  const nr = nrs.find((n) => normNr(n) === normNr(addr.houseNumber || ''))
  const cfg = { vendor: 'waswob' as const, street: st.strName }
  if (nr) return { supported: true, town: town.name, street: st.strName, config: { ...cfg, hnrId: nr } }
  return {
    supported: true, town: town.name, street: st.strName, needsHouseNumber: true,
    hausNrList: nrs.map((n) => ({ id: n, nr: n })),
    config: cfg,
  }
}

async function readWas(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const street = (cfg.street || '').trim()
  const nr = cfg.hnrId != null ? String(cfg.hnrId).trim() : ''
  if (!street || !/^[0-9][0-9a-zA-Z /-]{0,12}$/.test(nr)) throw new Error('reconnect_required')
  const q = new URLSearchParams({ action: 'termine', strasse: street, hausnummer: nr })
  const res = await fetchWithTimeout(`${API}?${q}`, { headers: { 'User-Agent': UA, Accept: 'application/json' } })
  if (!res.ok) {
    // 502 is also what an address WAS no longer knows looks like; tell the two
    // apart by the street list.
    const st = await streets().catch(() => null)
    const known = st?.find((s) => s.strName === street)?.Hausnummer?.some((n) => normNr(n) === normNr(nr))
    if (st && !known) throw new Error('reconnect_required')
    throw new Error(`abfall upstream ${res.status}`)
  }
  const body = await res.json() as Record<string, { behaelter?: Record<string, Record<string, Record<string, string>>> }>
  const entry = Object.values(body ?? {})[0]
  const bins = entry?.behaelter
  if (!bins || typeof bins !== 'object') throw new Error('abfall upstream: unexpected answer')
  const sizes = Object.keys(bins)
  const out: SyncedEvent[] = []
  const seen = new Set<string>()
  for (const size of sizes) {
    for (const [title, days] of Object.entries(bins[size] ?? {})) {
      for (const [day, note] of Object.entries(days ?? {})) {
        if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) continue
        const k = `${day}:${title}`
        if (seen.has(k)) continue
        seen.add(k)
        const start = new Date(`${day}T00:00:00Z`)
        const notes = [sizes.length > 1 ? `${size} l` : '', note || ''].filter(Boolean).join(' · ')
        out.push({
          uid: `abfall:waswob:${normNr(street)}-${normNr(nr)}:${k}`,
          title,
          notes: notes || null,
          location: cfg.label ?? null,
          startsAt: start.toISOString(),
          endsAt: new Date(start.getTime() + 86_400_000).toISOString(),
          allDay: true,
        })
      }
    }
  }
  return out
}

function towns(p: AbfallProvider): Town[] {
  return [{ vendor: 'waswob', name: p.town || 'Wolfsburg', provider: p.id }]
}

export const adapter: VendorAdapter = {
  family: 'waswob',
  towns,
  probe: probeWas,
  read: readWas,
}
