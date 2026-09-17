// abfall/vendors/bsr.ts — BSR Berlin — needs the house number to name a schedule at all.

import {
  type AbfallConfig,
  type AbfallProvider,
  type GeoAddress,
  getJson,
  normStreet,
  type ResolveResult,
  type StreetOption,
  streetStem,
  type SyncedEvent,
  type Town,
  type VendorAdapter,
} from "../core.ts";

// ── BSR (Berliner Stadtreinigung) ────────────────────────────────────────────
//
// Three keyless GETs on the address app behind bsr.de/abfuhrkalender: a street
// search, street + house number → AddrKey, and the pickups of an AddrKey over
// a date window. Nothing to enumerate house numbers with — `plzSet` answers a
// bare street with `[]` — and Berlin plans per HOUSE rather than per street
// (Karl-Marx-Allee 1, 3 and 12 answer three different calendars), so an
// address without a number is answered `needsHouseNumber` and the client asks
// for it. Guessing "1" here would put the neighbour's bins on the calendar.
const BSR_BASE = 'https://umnewforms.bsr.de/p/de.bsr.adressen.app'

// Codes as the address app sends them. Names are chosen so classifyWaste on
// the client finds the bin: "Biogut" → bio, "Hausmüll" → rest, "Wertstoffe" →
// packaging. A code not listed here is shown as itself rather than dropped —
// the truck still comes.
const BSR_CATEGORIES: Record<string, string> = {
  BI: 'Biogut',
  HM: 'Hausmüll',
  BM: 'Biogut/Hausmüll',
  LT: 'Laubtonne',
  WS: 'Wertstoffe',
  WB: 'Weihnachtsbaum',
}

async function searchStreetsBsr(query: string): Promise<StreetOption[]> {
  const q = query.trim()
  if (!q) return []
  const rows = await getJson(
    `${BSR_BASE}/streetNames?searchQuery=${encodeURIComponent(q)}`,
  ) as Array<{ value?: string }>
  const seen = new Set<string>()
  const out: StreetOption[] = []
  for (const r of (Array.isArray(rows) ? rows : [])) {
    const name = (r?.value || '').trim()
    // The list carries "Karl-Marx-Str." and "KARL-MARX-STR." both; one is enough.
    const key = name.toLowerCase()
    if (!name || seen.has(key)) continue
    seen.add(key)
    out.push({ name, config: { vendor: 'bsr', street: name } })
  }
  return out
}

async function probeBsr(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  if (!addr.street) return null
  const streets = await searchStreetsBsr(streetStem(addr.street))
  const target = normStreet(addr.street)
  const best =
    streets.find((s) => normStreet(s.name) === target) ||
    streets.find((s) => {
      const n = normStreet(s.name)
      return n.includes(target) || target.includes(n)
    })
  if (!best) return null
  const hnr = (addr.houseNumber || '').trim()
  if (!hnr) {
    return { supported: true, town: town.name, street: best.name, needsHouseNumber: true, config: best.config }
  }
  const rows = await getJson(
    `${BSR_BASE}/plzSet/plzSet?searchQuery=${encodeURIComponent(`${best.name}:::${hnr}`)}`,
  ) as Array<{ value?: string; label?: string }>
  const found = (Array.isArray(rows) ? rows : []).filter((r) => r?.value && r?.label) as
    Array<{ value: string; label: string }>
  // The street is BSR's but the number is not ("1a" where it knows "1"): the
  // number is what is missing, not the vendor.
  if (!found.length) {
    return { supported: true, town: town.name, street: best.name, needsHouseNumber: true, config: best.config }
  }
  // A street that runs through several postcodes answers one row per PLZ.
  // The geocoded postcode picks; failing that, the rows become the chips.
  const byPlz = addr.postcode ? found.filter((r) => r.label.includes(addr.postcode!)) : []
  const pick = byPlz.length === 1 ? byPlz[0] : found.length === 1 ? found[0] : null
  if (pick) {
    return {
      supported: true, town: town.name, street: best.name,
      config: { ...best.config, hnrId: pick.value, hnr },
    }
  }
  return {
    supported: true, town: town.name, street: best.name, needsHouseNumber: true,
    hausNrList: found.map((r) => ({ id: r.value, nr: r.label.replace(/^.*?,\s*/, '') })),
    config: { ...best.config, hnr },
  }
}

async function readBsr(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const key = String(cfg.hnrId ?? '')
  if (!/^[0-9A-Za-z]{8,40}$/.test(key)) throw new Error('reconnect_required')
  const now = new Date()
  const from = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 1, 1))
  const to = new Date(Date.UTC(now.getUTCFullYear() + 1, now.getUTCMonth() + 1, 1))
  const stamp = (d: Date) => d.toISOString().slice(0, 19)
  const filter =
    `AddrKey eq '${key}' and DateFrom eq datetime'${stamp(from)}' and DateTo eq datetime'${stamp(to)}'`
  const data = await getJson(`${BSR_BASE}/abfuhrEvents?filter=${encodeURIComponent(filter)}`) as {
    dates?: Record<string, Array<{
      category?: string; serviceDate_actual?: string; disposalComp?: string; warningText?: string
    }>>
  }
  const out: SyncedEvent[] = []
  const seen = new Set<string>()
  for (const [day, items] of Object.entries(data?.dates ?? {})) {
    for (const it of (Array.isArray(items) ? items : [])) {
      // The map key is the regular day; `serviceDate_actual` is when the truck
      // really comes once a holiday has shifted the tour. The actual one wins.
      const m = (it.serviceDate_actual || '').match(/^(\d{2})\.(\d{2})\.(\d{4})$/)
      const iso = m ? `${m[3]}-${m[2]}-${m[1]}` : day
      const start = new Date(`${iso}T00:00:00Z`)
      if (isNaN(start.getTime())) continue
      const end = new Date(start)
      end.setUTCDate(end.getUTCDate() + 1)
      const code = (it.category || '').trim()
      const name = BSR_CATEGORIES[code] || code || 'Abfuhr'
      // Wertstoffe are ALBA's tour, not BSR's; the household reads it on the bin.
      const comp = (it.disposalComp || '').trim()
      const title = comp && comp !== 'BSR' ? `${name} (${comp})` : name
      const dayKey = `${iso}:${code || name}`
      if (seen.has(dayKey)) continue
      seen.add(dayKey)
      out.push({
        uid: `abfall:bsr:${key}:${dayKey}`,
        title,
        notes: (it.warningText || '').trim() || null,
        location: cfg.label ?? null,
        startsAt: start.toISOString(),
        endsAt: end.toISOString(),
        allDay: true,
      })
    }
  }
  return out
}

function towns(p: AbfallProvider): Town[] {
  // One city; streets are searched live and the address validated by the probe.
  return [{ vendor: 'bsr', name: p.town || 'Berlin', provider: p.id }]
}

export const adapter: VendorAdapter = {
  family: 'bsr',
  towns,
  searchStreets: (_town, query) => searchStreetsBsr(query),
  probe: probeBsr,
  read: readBsr,
}
