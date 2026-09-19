// abfall/pdf/types.ts — what a printed bin calendar is reduced to before it is read.
//
// The parser never sees a PDF. `extract.ts` turns one into positioned words and filled boxes,
// and everything after that is pure functions over this shape. That split is what lets the
// regression harness in tool/abfall_pdf/ score the exact code the Edge Function ships: it runs
// the same extraction under Node, caches the result, and feeds the parser from the cache.

/// One word, in page coordinates with the origin top-left, y growing down.
export interface Word {
  s: string
  x0: number
  y0: number
  x1: number
  y1: number
}

/// A filled rectangle, with its fill as 0–255 RGB. Colour is how some towns say which bin a
/// cell means, so the boxes are kept rather than thrown away with the rest of the drawing.
export interface Box {
  x0: number
  y0: number
  x1: number
  y1: number
  rgb: [number, number, number]
}

export interface PdfPage {
  w: number
  h: number
  words: Word[]
  boxes: Box[]
}

export interface PdfDoc {
  pages: PdfPage[]
  error?: string
}

/// One bin on one day, as the calendar printed it.
export interface Pickup {
  date: string // YYYY-MM-DD
  bin: string // canonical bin key, see BINS in bins.ts
}

/// What a household picks between: a district, a tour, a zone. `id` is stable for one PDF.
export interface PdfChoice {
  id: string
  label: string
  pickups: Pickup[]
}

/// Why a PDF was not read. Each one is a promise not to guess.
export type Refusal =
  | "no_text" // no text layer: scanned or outlined
  | "no_year" // no year the calendar could be about
  | "not_calendar" // text, but no day grid or date list in it
  | "low_coverage" // the grid was found but too many days did not check out
  | "weekday_mismatch" // printed weekdays disagree with the calendar
  | "no_bins" // days found, but nothing on them reads as a bin
  | "colour_only" // bins told apart by colour alone, and the legend did not resolve
  | "independent_districts" // bins run separate district systems and nothing says which go together
  | "unsupported_layout" // recognisably a calendar, in a layout this parser does not read

export type ParseResult =
  | { ok: true; year: number; layout: string; choices: PdfChoice[] }
  | { ok: false; refusal: Refusal; detail?: string }
