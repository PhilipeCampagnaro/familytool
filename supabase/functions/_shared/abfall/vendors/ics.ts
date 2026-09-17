// abfall/vendors/ics.ts — A calendar handed over as a plain link: the mechanism with the vendor taken out.

import {
  type AbfallConfig,
  fetchUntrusted,
  parseIcs,
  shortHash,
  type SyncedEvent,
  UA,
  type VendorAdapter,
} from "../core.ts";

// Accept http(s) and webcal:// (the subscription scheme waste sites often use);
// reject anything that could point at a private host.
export function normalizeIcsUrl(raw?: string): string | null {
  const s = (raw || '').trim().replace(/^webcal:\/\//i, 'https://')
  if (!s) return null
  let u: URL
  try { u = new URL(s) } catch { return null }
  if (u.protocol !== 'https:' && u.protocol !== 'http:') return null
  const h = u.hostname.toLowerCase()
  if (h === 'localhost' || h.endsWith('.local') || h.endsWith('.internal')) return null
  if (/^\d+\.\d+\.\d+\.\d+$/.test(h) || h.includes(':')) return null // IP literals (v4/v6)
  return u.href
}

export async function readIcsUrl(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const url = normalizeIcsUrl(cfg.url)
  if (!url) throw new Error('reconnect_required')
  // fetchUntrusted resolves the host and refuses a private address on *every*
  // hop, so a link that redirects into the private range is caught too.
  const res = await fetchUntrusted(url, { headers: { Accept: 'text/calendar, */*', 'User-Agent': UA } })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const ics = (await res.text()).replace(/^﻿/, '')
  if (!ics.includes('BEGIN:VEVENT')) return []
  const thisYear = new Date().getUTCFullYear()
  const start = new Date(Date.UTC(thisYear - 1, 0, 1))
  const end = new Date(Date.UTC(thisYear + 2, 0, 1))
  const out: SyncedEvent[] = []
  const seen = new Set<string>()
  for (const ev of parseIcs(ics, start, end)) {
    const title = ev.title.replace(/^Abfuhr:\s*/i, '')
    const dayKey = `${ev.startsAt.slice(0, 10)}:${title}`
    if (seen.has(dayKey)) continue
    seen.add(dayKey)
    out.push({
      ...ev,
      uid: `abfall:ics:${shortHash(url)}:${dayKey}`,
      title,
      notes: null,
      location: cfg.label ?? ev.location ?? null,
    })
  }
  return out
}

// No towns and no probe: this one is reached by a pasted link, never by an
// address, so it contributes nothing to the town list.
export const adapter: VendorAdapter = {
  family: 'ics',
  read: readIcsUrl,
}
