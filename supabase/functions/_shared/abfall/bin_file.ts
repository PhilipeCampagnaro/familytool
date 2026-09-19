// abfall/bin_file.ts — is an uploaded file a waste calendar?
//
// A household in an upload-only town (see `upload` in abfall_providers.ts)
// adds its bins as a file, and that file does not count towards the free
// plan's calendar accounts, because Abfall is free everywhere else. This is
// the guard that keeps the free slot a bin calendar: most of the events must
// be named like a pickup. Stricter than the colour rules in
// lib/data/abfall_bins.dart on purpose — "bio", "rest" and "gelb" colour a
// pickup fine but also match "Biologie", "Restaurant" and "Gelbe Seiten".

export const BIN_FILE_MAX_BYTES = 512 * 1024

const PICKUP = /m[üu]e?ll|abfall|tonne|abfuhr|altpapier|papier|pappe|wertstoff|verpackung|gelber sack|gr[üu]e?n(gut|schnitt|abfall)|laubs[aä]ck|sperr|schadstoff|problemstoff|kompost|\bppk\b|\blvp\b|altglas|weihnachtsb[aä]um|tannenb[aä]um|entsorgung|\bbio(abfall|tonne|m[üu]ll)\b|restm[üu]ll|restabfall/i

/// The event titles of an ICS, unfolded. Enough for a check, not a parser.
export function summaries(ics: string): string[] {
  const unfolded = ics.replace(/\r?\n[ \t]/g, '')
  const out: string[] = []
  for (const m of unfolded.matchAll(/^SUMMARY[^:\r\n]*:(.*)$/gm)) {
    out.push(m[1].replace(/\\([,;\\])/g, '$1').replace(/\\n/gi, ' ').trim())
  }
  return out
}

/// At least three events, and four in five of them named like a pickup.
export function looksLikeBinCalendar(ics: string): boolean {
  const titles = summaries(ics).filter(Boolean)
  if (titles.length < 3) return false
  const hits = titles.filter((t) => PICKUP.test(t)).length
  return hits / titles.length >= 0.8
}
