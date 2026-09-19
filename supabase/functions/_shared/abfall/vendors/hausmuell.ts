// abfall/vendors/hausmuell.ts — hausmuell.info (aturis) — the calendar ASR
// Chemnitz embeds on asr-chemnitz.de and SWE runs as abfallkalender.stadtwerke-
// erfurt.de, the page erfurt.de links. ICS per house.

import {
  type AbfallConfig,
  type AbfallProvider,
  dayEvents,
  decodeEntities,
  fetchWithTimeout,
  type GeoAddress,
  icsDays,
  normStreet,
  type ResolveResult,
  streetStem,
  type SyncedEvent,
  type Town,
  UA,
  type VendorAdapter,
} from "../core.ts";

// ── hausmuell.info ──────────────────────────────────────────────────────────
//
// Two generations of the same software, told apart by `client`:
//
// **proxy** (Chemnitz, asc.hausmuell.info) — everything through proxy.php:
//   POST proxy.php  input=<prefix>&ort_id=0&str_id=0&url=2&server=0
//        -> <li id='str_188085'>…<span>188085</span><span>0</span><span>Reichenhainer Str.</span>
//   POST proxy.php  input=&ort_id=0&str_id=<id>&hidden_kalenderart=privat&url=3&server=0
//        -> get_value("hnr",<hnr id>,<egebiet id>) with the number as label
//   POST ics/ics.php hidden_id_egebiet, hidden_id_hnr, hidden_id_ort=0,
//        hidden_id_ortsteil=0 and every showBins* flag — **leave one out and the
//        body is empty with a 200**.
//
// **direct** (Erfurt) — search/search_strassen.php, search/search_hnr.php, then
//   ics/ics.php with hidden_id_str, hidden_id_hnr and **hidden_id_zusatz, which
//   is the hnr id again** unless the building is split (Vorderhaus/Hinterhaus),
//   which search/check_zusatz.php answers "visible" for.
//
// An empty house list is the whole answer for the street — some Chemnitz houses
// return a calendar with no events, which means ASR collects nothing there.
// Titles read "Entsorgung: Restabfall"; Erfurt adds "verschobene Abholung:
// Hausmüll" for a date moved by a holiday. Chemnitz's window rolls a few months
// past today; Erfurt's stops at 31 December.
const HOST = /^[a-z0-9.-]+\.(hausmuell\.info|stadtwerke-erfurt\.de)$/

async function post(host: string, path: string, form: Record<string, string>): Promise<string> {
  const res = await fetchWithTimeout(`https://${host}/${path}`, {
    method: 'POST',
    headers: { 'User-Agent': UA, 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(form).toString(),
  })
  if (!res.ok) throw new Error(`abfall upstream ${res.status}`)
  return res.text()
}

/// Each <li>: its hidden spans, then the visible label.
function items(html: string, prefix: string): Array<{ ids: string[]; label: string }> {
  return [...html.matchAll(new RegExp(`<li[^>]*id\\s*=\\s*'${prefix}_\\d+'[^>]*>([\\s\\S]*?)</li>`, 'g'))].map((m) => {
    const spans = [...m[1].matchAll(/<span[^>]*>([^<]*)<\/span>/g)].map((s) => decodeEntities(s[1]).trim())
    return { ids: spans.slice(0, -1), label: spans[spans.length - 1] ?? '' }
  })
}

async function streets(host: string, proxy: boolean, stem: string) {
  const html = proxy
    ? await post(host, 'proxy.php', { input: stem, ort_id: '0', str_id: '0', url: '2', server: '0' })
    : await post(host, 'search/search_strassen.php', { input_str: stem, str_id: '', input_hnr: '', hidden_kalenderart: 'privat' })
  return items(html, 'str').map((i) => ({ id: i.ids[0], name: i.label }))
}

/// House chips; the id is what ics.php needs: "hnr|egebiet" (proxy) or
/// "hnr|zusatz" (direct, the zusatz being the hnr id unless the house is split).
async function houses(host: string, proxy: boolean, strId: string, street: string) {
  const html = proxy
    ? await post(host, 'proxy.php', { input: '', ort_id: '0', str_id: strId, hidden_kalenderart: 'privat', url: '3', server: '0' })
    : await post(host, 'search/search_hnr.php', { input_hnr: '', str_id: strId, input_str: street, hidden_kalenderart: 'privat' })
  return items(html, 'hnr').map((i) => ({ id: `${i.ids[0]}|${proxy ? i.ids[1] : i.ids[0]}`, nr: i.label }))
}

/// A split building in Erfurt: one chip per part instead of the house.
async function parts(host: string, strId: string, hnrId: string, nr: string) {
  const vis = await post(host, 'search/check_zusatz.php', { hidden_id_hnr: hnrId, hidden_id_str: strId, hidden_kalenderart: 'privat' })
  if (!/visible/.test(vis)) return null
  const html = await post(host, 'search/search_zusatz.php', {
    input_zusatz: '', hidden_id_hnr: hnrId, hidden_id_str: strId, hidden_kalenderart: 'privat',
  })
  const list = items(html, 'zusatz').map((i) => ({ id: `${hnrId}|${i.ids[0]}`, nr: `${nr} ${i.label}` }))
  return list.length ? list : null
}

async function probeHm(town: Town, addr: GeoAddress): Promise<ResolveResult | null> {
  const host = town.host || ''
  if (!addr.street || !HOST.test(host)) return null
  const proxy = town.client === 'proxy'
  const target = normStreet(addr.street)
  const street = (await streets(host, proxy, streetStem(addr.street))).find((s) => normStreet(s.name) === target)
  if (!street) return null
  const cfg = { vendor: 'hausmuell' as const, host, client: town.client, strasseId: street.id, street: street.name }
  const list = await houses(host, proxy, street.id, street.name)
  const want = (addr.houseNumber || '').toLowerCase().replace(/\s+/g, '')
  const hit = list.filter((h) => h.nr.toLowerCase().replace(/\s+/g, '') === want)
  if (hit.length === 1) {
    if (!proxy) {
      const split = await parts(host, street.id, hit[0].id.split('|')[0], hit[0].nr)
      if (split) return { supported: true, town: town.name, street: street.name, needsHouseNumber: true, hausNrList: split, config: cfg }
    }
    return { supported: true, town: town.name, street: street.name, config: { ...cfg, hnrId: hit[0].id } }
  }
  return { supported: true, town: town.name, street: street.name, needsHouseNumber: true, hausNrList: list, config: cfg }
}

async function readHm(cfg: AbfallConfig): Promise<SyncedEvent[]> {
  const host = cfg.host || ''
  const strId = String(cfg.strasseId ?? '')
  const [hnr, second] = String(cfg.hnrId ?? '').split('|')
  if (!HOST.test(host) || !/^\d+$/.test(hnr || '') || !/^\d+$/.test(second || '') || !/^\d*$/.test(strId)) {
    throw new Error('reconnect_required')
  }
  const body = cfg.client === 'proxy'
    ? await post(host, 'ics/ics.php', {
      hidden_id_egebiet: second, hidden_id_hnr: hnr, hidden_kalenderart: 'privat', hidden_id_ort: '0', hidden_id_ortsteil: '0',
      showBinsRest: 'on', showBinsRest_rc: 'on', showBinsDsd: 'on', showBinsBio: 'on', showBinsPapier: 'on',
      showBinsProb: 'on', showBinsXmas: 'on', showBinsOrganic: 'on',
    })
    : await post(host, 'ics/ics.php', { hidden_id_str: strId, hidden_id_hnr: hnr, hidden_id_zusatz: second, hidden_kalenderart: 'privat' })
  if (!body.includes('BEGIN:VCALENDAR')) throw new Error('reconnect_required')
  const rows = icsDays(body).map(({ day, title }) => {
    const moved = /^verschobene Abholung:/i.test(title)
    const bin = title.replace(/^[^:]*:\s*/, '').trim()
    return { day, title: bin.charAt(0).toUpperCase() + bin.slice(1), notes: moved ? 'Verschoben (Feiertag)' : null }
  })
  return dayEvents(rows, `abfall:hausmuell:${host.split('.')[0]}:${hnr}-${second}`, cfg.label ?? null)
}

function towns(p: AbfallProvider): Town[] {
  return [{ vendor: 'hausmuell', name: p.town || '', provider: p.id, host: p.host, client: p.client }]
}

export const adapter: VendorAdapter = {
  family: 'hausmuell',
  towns,
  probe: probeHm,
  read: readHm,
}
