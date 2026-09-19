// abfall/vendors/abfallio.ts — abfall.io / AbfallPlus legacy widget API — a multi-step HTML form walk.

import {
  type AbfallConfig,
  type AbfallProvider,
  decodeEntities,
  fetchWithTimeout,
  type HausNr,
  parseIcs,
  type StreetOption,
  type SyncedEvent,
  type Town,
  UA,
  type VendorAdapter,
} from "../core.ts";

// ── abfall.io / AbfallPlus (legacy widget API) ───────────────────────────────
//
// Not a JSON API: the embeddable widget's multi-step HTML form. Every step is a
// POST to api.abfall.io?key=&modus=&waction=; the response is an HTML fragment
// whose hidden inputs carry the server-side state (a token pair plus an
// accumulating `f_posts_json[]`) and whose <select> holds the next choice
// (kommune -> optional bezirk -> strasse -> optional house number). We replay
// exactly what the widget posts. `modus` is the widget's public constant.
const ABFALLIO_BASE = 'https://api.abfall.io'

const ABFALLIO_MODUS = 'd6c5855a62cf32a4dadbc2831f0f295f'

interface AbfallioPage {
  // Hidden-input form state with dict semantics (a later duplicate name wins),
  // mirroring how the widget itself accumulates state across steps.
  hidden: Map<string, string>
  selects: Map<string, Array<{ value: string; label: string }>>
}

function parseAbfallioPage(html: string): AbfallioPage {
  const hidden = new Map<string, string>()
  for (const m of html.matchAll(/<input[^>]*type="hidden"[^>]*name="([^"]*)"[^>]*value="([^"]*)"/g)) {
    hidden.set(decodeEntities(m[1]), decodeEntities(m[2]))
  }
  const selects = new Map<string, Array<{ value: string; label: string }>>()
  for (const sm of html.matchAll(/<select[^>]*name="([^"]+)"[^>]*>([\s\S]*?)<\/select>/g)) {
    const opts: Array<{ value: string; label: string }> = []
    for (const om of sm[2].matchAll(/<option value="([^"]*)"[^>]*>([^<]*)<\/option>/g)) {
      // value "0" / "" is the "Bitte auswählen..." placeholder
      if (!om[1] || om[1] === '0') continue
      opts.push({ value: om[1], label: decodeEntities(om[2].trim()) })
    }
    selects.set(sm[1], opts)
  }
  return { hidden, selects }
}

async function abfallioPost(
  key: string, waction: string, form: Map<string, string>,
): Promise<AbfallioPage> {
  const body = new URLSearchParams()
  for (const [n, v] of form) body.append(n, v)
  const res = await fetchWithTimeout(
    `${ABFALLIO_BASE}/?key=${key}&modus=${ABFALLIO_MODUS}&waction=${waction}`,
    {
      method: 'POST',
      headers: { 'User-Agent': UA, Accept: '*/*', 'Content-Type': 'application/x-www-form-urlencoded' },
      body: body.toString(),
    },
  )
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  return parseAbfallioPage(await res.text())
}

// A form step: the accumulated hidden state + this step's selections.
function abfallioForm(page: AbfallioPage, set: Record<string, string>): Map<string, string> {
  const form = new Map(page.hidden)
  for (const [n, v] of Object.entries(set)) form.set(n, v)
  return form
}

// Steps accumulate: the next request posts everything sent so far, with the
// response's hidden fields layered on top (that's how `f_posts_json[]` grows
// the server-side state the final export needs).
function abfallioMerge(form: Map<string, string>, page: AbfallioPage): Map<string, string> {
  const next = new Map(form)
  for (const [n, v] of page.hidden) next.set(n, v)
  return next
}

async function searchStreetsAbfallio(town: Town, query: string, hint?: string): Promise<StreetOption[]> {
  if (!town.key || !town.kommuneId) return []
  const init = await abfallioPost(town.key, 'init', new Map())
  const q = (query || '').trim().toLowerCase()

  const toOptions = (page: AbfallioPage, bezirkId?: string): StreetOption[] => {
    const list = page.selects.get('f_id_strasse') || []
    return list
      // "alle Straßen" = one schedule for the whole area; surface it under the
      // town's own name so the whole-town fallback matches it.
      .map((s) => ({ ...s, label: /^alle stra(ß|ss)en/i.test(s.label) ? town.name : s.label }))
      .filter((s) => !q || s.label.toLowerCase().includes(q) || s.label === town.name)
      .slice(0, 40)
      .map((s) => ({
        name: s.label,
        config: {
          vendor: 'abfallio' as const, key: town.key, kommuneId: town.kommuneId,
          ...(bezirkId ? { bezirkId } : {}), strasseId: s.value,
        },
      }))
  }

  // District-keyed town (Prignitz shape): one bezirk step straight from init.
  if (town.bezirkId) {
    const page = await abfallioPost(town.key, 'auswahl_bezirk_set',
      abfallioForm(init, { f_id_kommune: town.kommuneId, f_id_bezirk: town.bezirkId }))
    return toOptions(page, town.bezirkId)
  }

  // Streets right in the init form (single-municipality keys).
  if (init.selects.get('f_id_strasse')?.length) return toOptions(init)

  // Multi-kommune key: select the town, then either streets or districts.
  const page = await abfallioPost(town.key, 'auswahl_kommune_set',
    abfallioForm(init, { f_id_kommune: town.kommuneId }))
  const bezirke = page.selects.get('f_id_bezirk')
  if (!bezirke?.length || page.selects.get('f_id_strasse')?.length) return toOptions(page)

  // The kommune subdivides into districts and the address doesn't say which.
  // Walk them best-first: the geocoder's district hint, then "Innenbereich"
  // (the built-up area = the overwhelmingly common case), then form order.
  const h = (hint || '').trim().toLowerCase()
  const score = (b: { label: string }) => {
    const l = b.label.toLowerCase()
    if (h && (l.includes(h) || h.includes(l))) return 2
    if (/innen/.test(l)) return 1
    return 0
  }
  const ranked = [...bezirke].sort((a, b) => score(b) - score(a))
  const out: StreetOption[] = []
  for (const bz of ranked.slice(0, 12)) {
    try {
      const bp = await abfallioPost(town.key, 'auswahl_bezirk_set',
        abfallioForm(init, { f_id_kommune: town.kommuneId, f_id_bezirk: bz.value }))
      out.push(...toOptions(bp, bz.value))
    } catch { /* skip a dead district */ }
    if (out.length >= 40) break
  }
  return out.slice(0, 40)
}

// abfall.io: replay the widget's form steps (init -> optional bezirk/strasse
// steps so the server-side `f_posts_json[]` state accumulates) and finish with
// waction=export_ics for a rolling window, then parse the ICS.
async function readAbfallio(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  if (!cfg.key || !cfg.kommuneId || cfg.strasseId == null) throw new Error('reconnect_required')
  const init = await abfallioPost(cfg.key, 'init', new Map())
  let form = abfallioForm(init, { f_id_kommune: cfg.kommuneId })
  if (cfg.bezirkId) {
    form.set('f_id_bezirk', cfg.bezirkId)
    form = abfallioMerge(form, await abfallioPost(cfg.key, 'auswahl_bezirk_set', form))
    form.set('f_id_strasse', String(cfg.strasseId))
    form = abfallioMerge(form, await abfallioPost(cfg.key, 'auswahl_strasse_set', form))
    if (cfg.hnrId != null && cfg.hnrId !== '') {
      form.set('f_id_strasse_hnr', String(cfg.hnrId))
      form = abfallioMerge(form, await abfallioPost(cfg.key, 'auswahl_hnr_set', form))
    }
  } else {
    form.set('f_id_strasse', String(cfg.strasseId))
    if (cfg.hnrId != null && cfg.hnrId !== '') form.set('f_id_strasse_hnr', String(cfg.hnrId))
  }
  form.set('f_abfallarten_index_max', '0')
  form.set('f_abfallarten', '')
  const now = new Date()
  const from = new Date(now); from.setUTCDate(from.getUTCDate() - 30)
  const to = new Date(now); to.setUTCDate(to.getUTCDate() + 365)
  const ymd = (d: Date) => d.toISOString().slice(0, 10).replace(/-/g, '')
  form.set('f_zeitraum', `${ymd(from)}-${ymd(to)}`)

  const body = new URLSearchParams()
  for (const [n, v] of form) body.append(n, v)
  const res = await fetchWithTimeout(
    `${ABFALLIO_BASE}/?key=${cfg.key}&modus=${ABFALLIO_MODUS}&waction=export_ics`,
    {
      method: 'POST',
      headers: { 'User-Agent': UA, Accept: '*/*', 'Content-Type': 'application/x-www-form-urlencoded' },
      body: body.toString(),
    },
  )
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  let ics = await res.text()
  // The export can prepend HTML warning lines (e.g. about extra waste-type
  // radio buttons some authorities configure); strip anything tag-like.
  if (/<b/i.test(ics)) ics = ics.replace(/<br[^\n]*|<b[^\n]*/gi, '\r')
  if (!ics.includes('BEGIN:VEVENT')) return []

  const winStart = new Date(Date.UTC(now.getUTCFullYear() - 1, 0, 1))
  const winEnd = new Date(Date.UTC(now.getUTCFullYear() + 2, 0, 1))
  const out: SyncedEvent[] = []
  const seen = new Set<string>()
  for (const ev of parseIcs(ics, winStart, winEnd)) {
    const dayKey = `${ev.startsAt.slice(0, 10)}:${ev.title}`
    if (seen.has(dayKey)) continue
    seen.add(dayKey)
    out.push({
      ...ev,
      uid: `abfall:abfallio:${cfg.key}:${cfg.kommuneId}:${cfg.strasseId}:${dayKey}`,
      notes: null,
      location: cfg.label ?? ev.location ?? null,
    })
  }
  return out
}

async function towns(p: AbfallProvider): Promise<Town[]> {
  const all = await allTowns(p)
  return p.notTowns ? all.filter((t) => !p.notTowns!.includes(t.name)) : all
}

async function allTowns(p: AbfallProvider): Promise<Town[]> {
  if (!p.key) return []
  const page = await abfallioPost(p.key, 'init', new Map())
  const kommunen = page.selects.get('f_id_kommune')
  if (kommunen?.length) {
    return kommunen.map((k) => ({
      vendor: 'abfallio', name: k.label, provider: p.id, key: p.key, kommuneId: k.value,
    }))
  }
  const hiddenKommune = page.hidden.get('f_id_kommune')
  if (!hiddenKommune) return []
  const bezirke = page.selects.get('f_id_bezirk')
  if (bezirke?.length) {
    // District-keyed authority (the Prignitz shape): the selectable "towns" are
    // its villages/districts.
    return bezirke.map((b) => ({
      vendor: 'abfallio', name: b.label, provider: p.id,
      key: p.key, kommuneId: hiddenKommune, bezirkId: b.value,
    }))
  }
  // Single municipality with its street list right in the init form.
  return [{
    vendor: 'abfallio', name: p.town || p.name, provider: p.id,
    key: p.key, kommuneId: hiddenKommune,
  }]
}

// abfall.io house numbers appear only after a street-set step, so they are
// fetched for the matched street alone. District chains don't use them.
async function houseNumbers(opt: StreetOption): Promise<HausNr[] | undefined> {
  if (!opt.config.key || opt.config.bezirkId) return undefined
  const init = await abfallioPost(opt.config.key, 'init', new Map())
  const page = await abfallioPost(opt.config.key, 'auswahl_strasse_set',
    abfallioForm(init, {
      f_id_kommune: opt.config.kommuneId || '',
      f_id_strasse: String(opt.config.strasseId ?? ''),
    }))
  const hnrs = page.selects.get('f_id_strasse_hnr') || []
  return hnrs.length ? hnrs.map((h) => ({ id: h.value, nr: h.label })) : undefined
}

export const adapter: VendorAdapter = {
  family: 'abfallio',
  towns,
  searchStreets: searchStreetsAbfallio,
  houseNumbers,
  read: readAbfallio,
}
