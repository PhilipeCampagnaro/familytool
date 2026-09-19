// abfall/pdf/upload.ts — a household's PDF bin calendar, turned into the ICS the upload route keeps.
//
// calendar-link's file route already proves, seals and re-parses an uploaded .ics; a PDF joins it
// by becoming one here, once, at upload. The PDF itself is not kept: what is stored is the
// calendar for the district the household picked, which is the only part of the PDF that is
// theirs. Every refusal in parse.ts surfaces as a German sentence the app shows as-is.

import * as pdfjs from 'npm:pdfjs-dist@4.10.38/legacy/build/pdf.mjs'
import { extractDoc } from './extract.ts'
import { parsePdfDoc, pickupsToIcs } from './parse.ts'
import type { Refusal } from './types.ts'

/// A year of one town's bins is a few hundred KB; the largest real one we have seen is 7.5 MB.
export const PDF_MAX_BYTES = 8 * 1024 * 1024

export interface PdfChoiceSummary {
  id: string
  label: string
  /// The next pickups for this choice, as ISO dates, so a household recognises its district.
  next: string[]
}

export type PdfUpload =
  | { ok: true; choices: PdfChoiceSummary[]; ics: string | null; fileName: string }
  | { ok: false; error: string }

const WHY: Record<Refusal | 'crash' | 'too_big' | 'not_pdf', string> = {
  no_text: 'Dieses PDF enthält keinen lesbaren Text (vermutlich ein Scan). Bitte lade die Kalenderdatei (.ics) der Stadt hoch, falls es eine gibt.',
  no_year: 'In diesem PDF steht kein Jahr, für das der Kalender gilt.',
  not_calendar: 'In diesem PDF haben wir keinen Abfuhrkalender gefunden. Bitte wähle den Kalender selbst, nicht ein Infoblatt.',
  low_coverage: 'Dieser Kalender lässt sich nicht vollständig lesen. Damit keine Abfuhr fehlt, übernehmen wir ihn nicht.',
  weekday_mismatch: 'Die Wochentage in diesem Kalender passen nicht zu den Daten. Wir übernehmen ihn nicht, um keine falschen Termine zu setzen.',
  no_bins: 'In diesem Kalender haben wir keine Tonnen erkannt.',
  colour_only: 'Dieser Kalender unterscheidet die Tonnen nur über Farben, die wir nicht sicher zuordnen können. Wir übernehmen ihn nicht, um keine falschen Termine zu setzen.',
  independent_districts: 'In diesem Kalender hat jede Tonne eigene Touren, und ohne Straßenverzeichnis können wir sie nicht sicher zuordnen.',
  unsupported_layout: 'Dieses Kalenderformat können wir noch nicht sicher lesen. Wir übernehmen es nicht, um keine falschen Termine zu setzen.',
  crash: 'Dieses PDF konnten wir nicht lesen.',
  too_big: 'Diese Datei ist zu groß für einen Abfallkalender.',
  not_pdf: 'Das ist keine PDF-Datei.',
}

/// Read `base64` as a bin calendar. With `choiceId` (or when the calendar has only one district)
/// the result carries the ICS for that district; without, only the choices to pick from.
export async function pdfToBinIcs(base64: string, opts: { choiceId?: string; name: string; fileName?: string; today: string }): Promise<PdfUpload> {
  if (base64.length > Math.ceil(PDF_MAX_BYTES / 3) * 4 + 4) return { ok: false, error: WHY.too_big }
  let bytes: Uint8Array
  try {
    bytes = Uint8Array.from(atob(base64.replace(/^data:[^,]*,/, '')), (c) => c.charCodeAt(0))
  } catch {
    return { ok: false, error: WHY.not_pdf }
  }
  if (bytes.length < 5 || String.fromCharCode(...bytes.subarray(0, 4)) !== '%PDF') return { ok: false, error: WHY.not_pdf }

  let res
  try {
    res = parsePdfDoc(await extractDoc(pdfjs, bytes))
  } catch {
    return { ok: false, error: WHY.crash }
  }
  if (!res.ok) return { ok: false, error: WHY[res.refusal] }

  const choices = res.choices.map((c) => ({
    id: c.id,
    label: c.label,
    next: [...new Set(c.pickups.filter((p) => p.date >= opts.today).map((p) => p.date))].slice(0, 3),
  }))
  const picked = opts.choiceId ? res.choices.find((c) => c.id === opts.choiceId) : res.choices.length === 1 ? res.choices[0] : undefined
  if (opts.choiceId && !picked) return { ok: false, error: 'Dieser Bezirk steht nicht im Kalender. Bitte wähle ihn noch einmal.' }
  const base = (opts.fileName ?? 'abfallkalender.pdf').replace(/\.pdf$/i, '')
  return {
    ok: true,
    choices,
    ics: picked ? pickupsToIcs(picked, opts.name) : null,
    fileName: `${base}.ics`,
  }
}
