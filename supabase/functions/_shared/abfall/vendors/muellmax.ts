// abfall/vendors/muellmax.ts — Müllmax (Grafik-Partner) — the calendar USB
// Bochum, ASH Hamm, TBR Remscheid, AWM Münster and the Entsorgungsbetrieb Mainz
// each embed on their own website.

import {
  type AbfallConfig,
  type AbfallProvider,
  dayEvents,
  decodeEntities,
  fetchWithTimeout,
  type GeoAddress,
  icsDays,
  inSpans,
  normStreet,
  type ResolveResult,
  splitSpans,
  type SyncedEvent,
  type Town,
  UA,
  type VendorAdapter,
} from "../core.ts";

// ── Müllmax (www.muellmax.de/abfallkalender/<tenant>/res/<Tenant>Start.php) ──
//
// **Official only because each authority embeds it** — the page on
// usb-bochum.de, hamm.de/ash, tbr-info.de, awm.stadt-muenster.de and
// mz.kaw-mainz-bingen.de is an iframe of this form. Müllmax the app is not a
// source on its own (see the note on official sources in abfall_providers.ts).
//
// It is a server-side wizard, one POST per page, the state carried in a hidden
// `mm_ses` that each page hands to the next (no cookie is needed):
//
//   GET  …Start.php?abfuhr                  street page, a <datalist> of every street
//   POST mm_frm_ort_sel=<town>              only Remscheid (Remscheid | Wuppertal)
//   POST mm_frm_str_name=<exact name>       -> house <select> or straight on
//   POST mm_frm_hnr_sel="44789;Wiemelhausen;16;"  (PLZ;Ortsteil;Nr;Zusatz)
//   POST mm_ica_auswahl=iCalendar-Datei     -> one checkbox per bin at this house
//   POST mm_frm_fra_<CODE>=<CODE>… mm_ica_gen   -> text/calendar
//
// **The street search is fuzzy** — Hamm's "Amselweg" answers as Amselstraße —
// so the name sent is always one taken from the datalist, and the page is then
// read back for it. Münster has no house step: its long streets are split in the
// name ("Hammer Straße 67-111, 72-132, 131-173") and the number picks the entry.
// Mainz and Bochum carry the Ortsteil and PLZ in the house option. The ICS runs
// from today to 31 December; the new year appears when the authority publishes
// it. Hamm's "Umweltmobil" is a van at a car park, not a bin, and is not asked
// for. Six requests per refresh — the price of a wizard.
const TENANT = /^[a-z]{2,8}$/

interface Page { html: string; ses: string }

function base(tenant: string): string {
  return `https://www.muellmax.de/abfallkalender/${tenant}/res/${tenant[0].toUpperCase()}${tenant.slice(1)}Start.php`
}

async function send(tenant: string, form?: Record<string, string>): Promise<{ page: Page; res: Response; body: string }> {
  const res = await fetchWithTimeout(form ? base(tenant) : `${base(tenant)}?abfuhr`, form
    ? { method: 'POST', headers: { 'User-Agent': UA, 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams(form).toString() }
    : { headers: { 'User-Agent': UA, Accept: 'text/html' } })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  const body = await res.text()
  const ses = body.match(/name="mm_ses"\s+value="([^"]*)"/)?.[1] ?? ''
  return { page: { html: body, ses }, res, body }
}

const step = async (tenant: string, p: Page, fields: Record<string, string>) =>
  (await send(tenant, { mm_ses: p.ses, xxx: '1', ...fields })).page

/// The street page, past Remscheid's town question.
async function streetPage(tenant: string, town: string): Promise<Page> {
  let p = (await send(tenant)).page
  if (p.html.includes('mm_frm_ort_sel')) {
    const towns = [...p.html.matchAll(/<option[^>]*value="([^"]*)"/g)].map((m) => decodeEntities(m[1]))
    const pick = towns.find((t) => t.toLowerCase() === town.toLowerCase()) ?? towns[0]
    p = await step(tenant, p, { mm_frm_ort_sel: pick, mm_aus_ort_submit: 'weiter' })
  }
  if (!p.ses || !p.html.includes('mm_frm_str_name')) throw new Error('abfall upstream: unexpected page')
  return p
}

const datalist = (html: string) =>
  [...(html.match(/<datalist[\s\S]*?<\/datalist>/i)?.[0] ?? '').matchAll(/<option[^>]*value="([^"]*)"/g)]
    .map((m) => decodeEntities(m[1]).trim())

const houseOptions = (html: string) =>
  [...(html.match(/<select[^>]*name="mm_frm_hnr_sel"[\s\S]*?<\/select>/i)?.[0] ?? '').matchAll(/<option[^>]*value="([^"]*)"/g)]
    .map((m) => decodeEntities(m[1]))

/// "44789;Wiemelhausen;16;" -> "16", "…;2;a" -> "2a".
const houseNr = (v: string) => { const f = v.split(';'); return `${f[2] ?? ''}${f[3] ?? ''}`.trim() }

async function probeMm(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  const tenant = town.client || ''
  if (!addr.street || !TENANT.test(tenant)) return null
  const p = await streetPage(tenant, town.name)
  const target = normStreet(addr.street)
  const hits = datalist(p.html).map((name) => ({ name, ...splitSpans(name.replace(/,\s*(?=\d)/g, ' / ')) })).filter((s) => normStreet(s.street) === target)
  if (!hits.length) return null
  let entry = hits.length === 1 ? hits[0] : undefined
  if (!entry && addr.houseNumber) {
    const fit = hits.filter((h) => inSpans(h.spans, addr.houseNumber!))
    if (fit.length === 1) entry = fit[0]
  }
  const street = hits[0].street
  const cfg = { vendor: 'muellmax' as const, client: tenant, street, city: town.name }
  if (!entry) {
    // Münster's split street and no number that decides it: each chip names its
    // span, and its id is the entry's own name.
    return {
      supported: true, town: town.name, street, needsHouseNumber: true,
      hausNrList: hits.map((h) => ({ id: `${h.name}|`, nr: h.name.slice(h.street.length).trim() })), config: cfg,
    }
  }
  const after = await step(tenant, p, { mm_frm_str_name: entry.name, mm_aus_str_txt_submit: 'suchen' })
  const houses = houseOptions(after.html)
  if (!houses.length) {
    // No house step: the street (or its span) is the plan. It must be the page
    // for the name sent, not the fuzzy search's nearest street.
    if (!after.html.includes('mm_ica_auswahl')) return null
    return { supported: true, town: town.name, street, config: { ...cfg, hnrId: `${entry.name}|` } }
  }
  const want = (addr.houseNumber || '').toLowerCase().replace(/\s+/g, '')
  const hit = houses.filter((h) => houseNr(h).toLowerCase() === want)
  if (hit.length === 1) return { supported: true, town: town.name, street, config: { ...cfg, hnrId: `${entry.name}|${hit[0]}` } }
  return {
    supported: true, town: town.name, street, needsHouseNumber: true,
    hausNrList: houses.map((h) => ({ id: `${entry!.name}|${h}`, nr: houseNr(h) })), config: cfg,
  }
}

async function readMm(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const tenant = cfg.client || ''
  const [name, house = ''] = String(cfg.hnrId ?? '').split('|')
  if (!TENANT.test(tenant) || !name || name.length > 120 || house.length > 80) throw new Error('reconnect_required')
  let p = await streetPage(tenant, cfg.city || '')
  if (!datalist(p.html).includes(name)) throw new Error('reconnect_required')
  p = await step(tenant, p, { mm_frm_str_name: name, mm_aus_str_txt_submit: 'suchen' })
  if (house) {
    if (!houseOptions(p.html).includes(house)) throw new Error('reconnect_required')
    p = await step(tenant, p, { mm_frm_hnr_sel: house, mm_aus_hnr_sel_submit: 'weiter' })
  }
  if (!p.html.includes('mm_ica_auswahl')) throw new Error('reconnect_required')
  p = await step(tenant, p, { mm_ica_auswahl: 'iCalendar-Datei' })
  const bins: Record<string, string> = {}
  for (const m of p.html.matchAll(/<input[^>]*type="checkbox"[^>]*>/gi)) {
    const n = m[0].match(/name="(mm_frm_fra_[A-Za-z0-9]+)"/)?.[1]
    if (!n || n === 'mm_frm_fra_MOB') continue
    bins[n] = m[0].match(/value="([^"]*)"/)?.[1] ?? n.slice('mm_frm_fra_'.length)
  }
  // A house with nothing collected by this authority (Bochum has a few).
  if (!Object.keys(bins).length) return []
  const { res, body } = await send(tenant, {
    mm_ses: p.ses, xxx: '1', mm_frm_type: 'termine', ...bins, mm_ica_gen: 'iCalendar-Datei laden',
  })
  if (!(res.headers.get('content-type') || '').includes('calendar')) throw new Error('abfall upstream: no calendar')
  const rows = icsDays(body)
    .filter((r) => !/umweltmobil|schadstoffmobil/i.test(r.title))
    .map((r) => {
      // "USB Abfuhr Grau - Restmüll", "ASH Restmüll-Tonne", "awm Wertstofftonne,
      // Abfuhr durch REMONDIS": the authority's prefix goes, a colour before " - "
      // goes, and whatever follows a comma is a note, not the bin's name.
      const t = r.title.replace(/^(USB Abfuhr|EB|ASH|TBR|awm)\s+/i, '').replace(/^[A-Za-zäöü]+ - /, '')
      const [title, ...rest] = t.split(/,\s+/)
      return { day: r.day, title: title.trim(), notes: rest.join(', ').trim() || null }
    })
  return dayEvents(rows, `abfall:muellmax:${tenant}:${normStreet(name)}:${houseNr(house) || '-'}`, cfg.label ?? null)
}

function towns(p: AbfallProvider): Town[] {
  return [{ vendor: 'muellmax', name: p.town || '', provider: p.id, client: p.client }]
}

export const adapter: VendorAdapter = {
  family: 'muellmax',
  towns,
  probe: probeMm,
  read: readMm,
}
