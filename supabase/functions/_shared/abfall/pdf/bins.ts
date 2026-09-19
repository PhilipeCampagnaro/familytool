// abfall/pdf/bins.ts — which bin a printed word means.
//
// Two kinds of evidence, kept apart on purpose. A *name* ("Restmüll", "Gelber Sack", "Papiertonne")
// means its bin wherever it is printed. A *code* ("R", "B", "BT", "APP") means nothing until the
// calendar's own legend says what it means: "BT" is the Blaue Tonne in one town and the Biotonne
// in the next, and guessing it is how a household puts the wrong bin out. Only a handful of
// abbreviations are unambiguous enough across Germany to stand without a legend.

export type Bin = 'rest' | 'bio' | 'papier' | 'gelb' | 'glas' | 'gruen' | 'sperr' | 'schadstoff'

export const BIN_LABEL: Record<Bin, string> = {
  rest: 'Restmüll',
  bio: 'Biotonne',
  papier: 'Papier',
  gelb: 'Gelber Sack',
  glas: 'Altglas',
  gruen: 'Grünschnitt',
  sperr: 'Sperrmüll',
  schadstoff: 'Schadstoffmobil',
}

const fold = (s: string) =>
  s.toLowerCase().replace(/ä/g, 'ae').replace(/ö/g, 'oe').replace(/ü/g, 'ue').replace(/ß/g, 'ss').replace(/[^a-z0-9/+ -]/g, '')

// Whole-phrase names. Tested against one or two consecutive words, folded.
const NAMES: [RegExp, Bin][] = [
  [/^(rest(muell|abfall|tonne|abfalltonne|m)?|graue tonne|restmuelltonne|hausmuell)$/, 'rest'],
  [/^(bio(muell|abfall|abfaelle|tonne|gut)?|braune tonne|biomuelltonne)$/, 'bio'],
  [/^(alt)?papier(tonne|muell)?$|^(blaue tonne|papier ?\/ ?pappe|ppk|pappe)$/, 'papier'],
  [/^(gelbe?r? (sack|saecke|tonne)|gelbe(r)?|gelber-sack|gelbe-tonne|lvp|dsd|wertstoff(tonne|e)?|leichtverpackungen?|gruener punkt|verpackungen)$/, 'gelb'],
  [/^(alt)?glas$/, 'glas'],
  [/^(gruen(schnitt|gut|abfall|abfaelle)|garten(abfall|abfaelle)?|baum(schnitt)?|strauch(gut|schnitt|werk)?|christbaum|christbaeume|weihnachtsbaeume?|tannenbaeume?|laub|haeckselaktion|haeckseln)$/, 'gruen'],
  [/^sperr(muell|gut)?$/, 'sperr'],
  [/^(schadstoff(e|mobil|sammlung)?|problemstoff(e|sammlung|mobil)?|problemmuell|giftmobil|umweltmobil|sondermuell)$/, 'schadstoff'],
]

/// Abbreviations that mean the same bin in every calendar we have read. Everything else waits
/// for a legend.
const SAFE_CODES: Record<string, Bin> = {
  rm: 'rest',
  bio: 'bio',
  ppk: 'papier',
  lvp: 'gelb',
  dsd: 'gelb',
  gs: 'gelb',
}

/// The bin one or two words name, or null. `two` is the next word, tried first as a pair.
export function binOfName(one: string, two?: string): { bin: Bin; words: number } | null {
  const a = fold(one).replace(/[-/]$/, '')
  if (two !== undefined) {
    const pair = `${a} ${fold(two)}`.trim()
    for (const [re, bin] of NAMES) if (re.test(pair)) return { bin, words: 2 }
  }
  for (const [re, bin] of NAMES) if (re.test(a)) return { bin, words: 1 }
  const safe = SAFE_CODES[a]
  if (safe) return { bin: safe, words: 1 }
  return null
}

/// A word that is a holiday, a week number or a time: printed in day cells, never a pickup.
const NOISE =
  /^(neujahr|hl|heilige|drei|koenige|karfreitag|oster(sonntag|montag|n)|pfingst(sonntag|montag|en)|christi|himmelf(ahrt)?|fronleichnam|tag|der|deutschen|einheit|arbeit|allerheiligen|reformationstag|buss-?|bettag|heiligabend|weihnacht(en|stag)?|silvester|mariae|himmelfahrt|kw\d*|\d{1,2}[.:]\d{2}(-\d{1,2}[.:]\d{2})?|uhr|feiertag|advent|kalenderwoche|sommerferien|ferien|schulferien|valentinstag|muttertag|vatertag|rosenmontag|fastnacht|faschingsdienstag|aschermittwoch|erntedank|volkstrauertag|totensonntag|nikolaus|halloween)$/

export function isNoise(word: string): boolean {
  return NOISE.test(fold(word))
}
