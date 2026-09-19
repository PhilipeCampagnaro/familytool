// probe.ts — live end-to-end proof that every Abfall provider still delivers
// pickup dates. Read-only against the project; writes probe_results.json here.
import {
  aggregateTowns, searchStreets, readAbfallEvents, resolveAddress, rhythmChoices,
  type Town, type StreetOption, type AbfallConfig, type GeoAddress,
} from "../../supabase/functions/_shared/abfall.ts";
import { ABFALL_PROVIDERS } from "../../supabase/functions/_shared/abfall_providers.ts";
import { PROVIDER_STATE } from "../../supabase/functions/_shared/abfall/geo.ts";

// The Bundesland as Photon names it, which the app always sends along: without
// it the Bundesland guard in resolveAddress is off, and the probe for the city
// of Heidelberg resolved to the village of Heidelberg in the Prignitz.
const STATE_NAME: Record<string, string> = {
  BW: "Baden-Württemberg", BY: "Bayern", BE: "Berlin", BB: "Brandenburg", HB: "Bremen", HH: "Hamburg",
  HE: "Hessen", MV: "Mecklenburg-Vorpommern", NI: "Niedersachsen", NW: "Nordrhein-Westfalen",
  RP: "Rheinland-Pfalz", SL: "Saarland", SN: "Sachsen", ST: "Sachsen-Anhalt", SH: "Schleswig-Holstein", TH: "Thüringen",
};

const OUT = new URL("./probe_results.json", import.meta.url).pathname;
const CONCURRENCY = 4;
const PROVIDER_TIMEOUT_MS = 25_000;
const STEMS = ["haupt", "schul", "bahnhof", "kirch", "garten", "berg", "dorf", "a"];

interface Result {
  provider: string; name: string; family: string;
  town: string | null; street: string | null;
  events: number; from: string | null; to: string | null; bins: string[];
  ms: number; error?: string; triedTowns: string[];
  // The rhythm question this address would ask, as "bin: a/b/c" — empty almost
  // everywhere, and a new entry on a provider that never asked is a regression.
  rhythm?: string[];
  // Upload-only (`upload` in abfall_providers.ts): the proof is that the
  // address resolves to `uploadOnly` — the fetch logger shows no request left.
  upload?: string;
}

// Families that cannot be walked town -> street -> config, so the probe goes in
// through resolveAddress with a real address instead. C-Trace has no street
// enumeration at all; BSR and FES enumerate streets but plan per house, so a
// street alone yields no readable config.
const RESOLVE_FAMILIES = new Set(["ctrace", "bsr", "fes", "awm", "awbkoeln", "srh", "awsstuttgart", "awista", "srl", "athos", "abfallplus", "srdd", "aha", "awgwuppertal", "insertit", "abki", "wuerzburg", "avea", "oldenburg", "art", "waswob", "albabs", "elw", "fuerth", "heilbronn", "abis", "enni", "muellmax", "hws", "ksj", "tsk", "hausmuell", "sab", "swp", "osb", "meinabfall", "geb", "mags", "citko", "zah", "heidelberg", "beg", "sro", "ead"]);

const PROBE_ADDRESSES: Record<string, { street: string; town: string; postcode: string; houseNumber?: string }> = {
  "ctrace-bremen": { street: "Obernstraße", town: "Bremen", postcode: "28195" },
  "ctrace-arnsberg": { street: "Hauptstraße", town: "Arnsberg", postcode: "59821" },
  "ctrace-landau": { street: "Marktstraße", town: "Landau in der Pfalz", postcode: "76829" },
  "ctrace-oberursel": { street: "Hauptstraße", town: "Oberursel", postcode: "61440" },
  "bsr-berlin": { street: "Karl-Marx-Allee", town: "Berlin", postcode: "10178", houseNumber: "1" },
  "fes-frankfurt": { street: "Frankenallee", town: "Frankfurt am Main", postcode: "60327", houseNumber: "2" },
  // Spelled as the geocoder spells it, not as AWM does ("Francestr."): the
  // accent and the written-out "straße" are exactly what used to miss.
  "awm-muenchen": { street: "Francéstraße", town: "München", postcode: "80997", houseNumber: "10" },
  "awbkoeln-koeln": { street: "Bergisch Gladbacher Straße", town: "Köln", postcode: "51065", houseNumber: "102" },
  "srh-hamburg": { street: "Fränkelstraße", town: "Hamburg", postcode: "22307", houseNumber: "3" },
  // Deliberately the full "Straße": the city writes "Wachenheimer Str." and
  // will not find the unabbreviated form, so this exercises the stem lookup.
  "aws-stuttgart": { street: "Wachenheimer Straße", town: "Stuttgart", postcode: "70376", houseNumber: "3" },
  // Deliberately in the ae-spelling AWISTA does not index, so this also
  // exercises the title scan that finds "Askanierstraße 3" regardless.
  "awista-duesseldorf": { street: "Askanierstrasse", town: "Düsseldorf", postcode: "40547", houseNumber: "3" },
  // "1a" as the geocoder writes it, where Leipzig lists "1 A".
  "srl-leipzig": { street: "Karl-Liebknecht-Straße", town: "Leipzig", postcode: "04275", houseNumber: "1a" },
  // Written out, where EDG lists "Hohe Str." under the letter H.
  "athos-edg-dortmund": { street: "Hohe Straße", town: "Dortmund", postcode: "44139", houseNumber: "20" },
  "athos-umweltbetrieb-bielefeld": { street: "Eckendorfer Straße", town: "Bielefeld", postcode: "33609", houseNumber: "57" },
  "srdd-dresden": { street: "Neumarkt", town: "Dresden", postcode: "01067", houseNumber: "6" },
  "aha-region-hannover": { street: "Voltastraße", town: "Hannover", postcode: "30165", houseNumber: "25" },
  "awg-wuppertal": { street: "Kaiserstraße", town: "Wuppertal", postcode: "42329", houseNumber: "10" },
  "abk-kiel": { street: "Holstenstraße", town: "Kiel", postcode: "24103", houseNumber: "14" },
  "athos-bonnorange-bonn": { street: "Kaiserstraße", town: "Bonn", postcode: "53113", houseNumber: "10" },
  "athos-aws-augsburg": { street: "Frölichstraße", town: "Augsburg", postcode: "86150", houseNumber: "10" },
  // A split street: 198 is Lindleinsmühle, 199 Versbach.
  "stadt-wuerzburg": { street: "Frankenstraße", town: "Würzburg", postcode: "97078", houseNumber: "198" },
  // A split street: "1 - 71 und 2 - 88" / "73 - Ende und 90 - Ende".
  "avea-leverkusen": { street: "Bergische Landstraße", town: "Leverkusen", postcode: "51375", houseNumber: "95" },
  // 1–200 and 300–400 are different rhythms: the number decides.
  "stadt-oldenburg": { street: "Donnerschweer Straße", town: "Oldenburg", postcode: "26123", houseNumber: "350" },
  "art-trier": { street: "Saarstraße", town: "Trier", postcode: "54290", houseNumber: "10" },
  "was-wolfsburg": { street: "Kleiststraße", town: "Wolfsburg", postcode: "38440", houseNumber: "5" },
  "alba-braunschweig": { street: "Kastanienallee", town: "Braunschweig", postcode: "38102", houseNumber: "10" },
  "elw-wiesbaden": { street: "Rheinstraße", town: "Wiesbaden", postcode: "65185", houseNumber: "1" },
  "stadt-fuerth": { street: "Königstraße", town: "Fürth", postcode: "90762", houseNumber: "3" },
  "stadt-heilbronn": { street: "Allee", town: "Heilbronn", postcode: "74072", houseNumber: "5" },
  "abis-gelsenkirchen": { street: "Ackerstraße", town: "Gelsenkirchen", postcode: "45881", houseNumber: "10" },
  "abis-bottrop": { street: "Horster Straße", town: "Bottrop", postcode: "46238", houseNumber: "228" },
  "enni-moers": { street: "Homberger Straße", town: "Moers", postcode: "47441", houseNumber: "70" },
  "muellmax-usb": { street: "Königsallee", town: "Bochum", postcode: "44789", houseNumber: "16" },
  "muellmax-ash": { street: "Oststraße", town: "Hamm", postcode: "59065", houseNumber: "3" },
  "muellmax-tbr": { street: "Alleestraße", town: "Remscheid", postcode: "42853", houseNumber: "50" },
  "muellmax-awm": { street: "Hammer Straße", town: "Münster", postcode: "48153", houseNumber: "72" },
  "muellmax-ebm": { street: "Kaiserstraße", town: "Mainz", postcode: "55116", houseNumber: "10" },
  "hws-halle": { street: "Adam-Kuckhoff-Straße", town: "Halle (Saale)", postcode: "06108", houseNumber: "11" },
  "ksj-jena": { street: "Magdelstieg", town: "Jena", postcode: "07745", houseNumber: "103" },
  "tsk-karlsruhe": { street: "Rheinstraße", town: "Karlsruhe", postcode: "76185", houseNumber: "20" },
  "hausmuell-asr-chemnitz": { street: "Zschopauer Straße", town: "Chemnitz", postcode: "09126", houseNumber: "28" },
  "hausmuell-swe-erfurt": { street: "Juri-Gagarin-Ring", town: "Erfurt", postcode: "99084", houseNumber: "1" },
  "sab-magdeburg": { street: "Abendstraße", town: "Magdeburg", postcode: "39124", houseNumber: "10" },
  "swp-potsdam": { street: "Zeppelinstraße", town: "Potsdam", postcode: "14471", houseNumber: "11" },
  "osb-osnabrueck": { street: "Lotter Straße", town: "Osnabrück", postcode: "49078", houseNumber: "10" },
  "meinabfall-erlangen": { street: "Hauptstraße", town: "Erlangen", postcode: "91054", houseNumber: "5" },
  "geb-goettingen": { street: "Weender Landstraße", town: "Göttingen", postcode: "37073", houseNumber: "50" },
  "mags-moenchengladbach": { street: "Hindenburgstraße", town: "Mönchengladbach", postcode: "41061", houseNumber: "10" },
  "stadt-siegen": { street: "Koblenzer Straße", town: "Siegen", postcode: "57072", houseNumber: "10" },
  "zah-hildesheim": { street: "Almsstraße", town: "Hildesheim", postcode: "31134", houseNumber: "1" },
  "stadt-heidelberg": { street: "Bergheimer Straße", town: "Heidelberg", postcode: "69115", houseNumber: "10" },
  "ead-darmstadt": { street: "Rheinstraße", town: "Darmstadt", postcode: "64295", houseNumber: "105" },
  "beg-bremerhaven": { street: "Bürgermeister-Smidt-Straße", town: "Bremerhaven", postcode: "27568", houseNumber: "10" },
  "sro-rostock": { street: "Lange Straße", town: "Rostock", postcode: "18055", houseNumber: "10" },
  "insertit-mannheim": { street: "Hauptstraße", town: "Mannheim", postcode: "68259", houseNumber: "10" },
  "insertit-kassel": { street: "Wilhelmshöher Allee", town: "Kassel", postcode: "34119", houseNumber: "102" },
  "insertit-luebeck": { street: "Breite Straße", town: "Lübeck", postcode: "23552", houseNumber: "10" },
  "insertit-herne": { street: "Bahnhofstraße", town: "Herne", postcode: "44623", houseNumber: "7b" },
  "insertit-krefeld": { street: "Hochstraße", town: "Krefeld", postcode: "47798", houseNumber: "12" },
  "insertit-offenbach": { street: "Kaiserstraße", town: "Offenbach am Main", postcode: "63065", houseNumber: "3" },
  "athos-kaw-hameln-pyrmont": { street: "Ahorn", town: "Aerzen", postcode: "31855", houseNumber: "1" },
  "athos-aws-schaumburg": { street: "Obernstraße", town: "Stadthagen", postcode: "31655", houseNumber: "10" },
  "athos-awb-lk-karlsruhe": { street: "Melanchthonstraße", town: "Bretten", postcode: "75015", houseNumber: "10" },
  // Written out, where EBE lists "Rüttenscheider Str." — the stem lookup.
  "abfallplus-51be67f3": { street: "Rüttenscheider Straße", town: "Essen", postcode: "45130", houseNumber: "102" },
  "abfallplus-80acad6c": { street: "Königstraße", town: "Duisburg", postcode: "47051", houseNumber: "10" },
  "abfallplus-15f69fab": { street: "Hauptstraße", town: "Bad Urach", postcode: "72574", houseNumber: "10" },
  "abfallplus-efb75cbd": { street: "Königstraße", town: "Bad Freienwalde", postcode: "16259", houseNumber: "10" },
  // Not Eilenburg, which ASG does not serve: that address used to resolve to
  // Mockrehna's Torgauer Straße through the postcode fallback, and must not.
  "abfallplus-2085afd9": { street: "Leipziger Straße", town: "Torgau", postcode: "04860", houseNumber: "10" },
  "abfallplus-8b016df0": { street: "Bahnhofstraße", town: "Osterholz-Scharmbeck", postcode: "27711", houseNumber: "10" },
  // The five that ask for the Restmüll rhythm.
  "abfallplus-ba5c0a03": { street: "Kaiser-Joseph-Straße", town: "Freiburg im Breisgau", postcode: "79098", houseNumber: "200" },
  "abfallplus-8fb8b2b0": { street: "Elberfelder Straße", town: "Hagen", postcode: "58095", houseNumber: "10" },
  "abfallplus-1bf5dd38": { street: "Wilhelmstraße", town: "Reutlingen", postcode: "72764", houseNumber: "10" },
  "athos-pforzheim": { street: "Bahnhofstraße", town: "Pforzheim", postcode: "75172", houseNumber: "10" },
  // One Mainzer Straße; the four Bahnhofstraßen answer with Ortsteil chips instead.
  "athos-zke-saarbruecken": { street: "Mainzer Straße", town: "Saarbrücken", postcode: "66111", houseNumber: "2" },
  "meinabfall-neuss": { street: "Abteiweg", town: "Neuss", postcode: "41469", houseNumber: "1" },
  // Added 2026-09-19 from the Abfuhrkalender Atlas (tool/abfall_authorities/probe_candidates.ts).
  "abfallplus-ff692443": { street: "Poststraße", town: "Offenburg", postcode: "77652", houseNumber: "2" },
  "abfallplus-be047b0b": { street: "Hauptstraße", town: "Neckarsulm", postcode: "74172", houseNumber: "1" },
  "abfallplus-0d74f933": { street: "Hauptstraße", town: "Witten", postcode: "58452", houseNumber: "2" },
  "abfallplus-4dc39a5b": { street: "Hauptstraße", town: "Radeberg", postcode: "01454", houseNumber: "1" },
  "abfallplus-26bbdbe6": { street: "Schulstraße", town: "Königsbrunn", postcode: "86343", houseNumber: "3" },
  "abfallplus-f35bd08b": { street: "Hauptstraße", town: "Göppingen", postcode: "73033", houseNumber: "1" },
  "abfallplus-0e37304e": { street: "Hauptstraße", town: "Rastatt", postcode: "76437", houseNumber: "1" },
  "abfallplus-2fd91be1": { street: "Bahnhofstraße", town: "Andernach", postcode: "56626", houseNumber: "1" },
  "abfallplus-29ac778f": { street: "Schulstraße", town: "Cloppenburg", postcode: "49661", houseNumber: "2" },
  "abfallplus-29727e74": { street: "Hauptstraße", town: "Hadamar", postcode: "65589", houseNumber: "1" },
  "abfallplus-254ef8a2": { street: "Hauptstraße", town: "Marktoberdorf", postcode: "87616", houseNumber: "1" },
  "abfallplus-30f9958c": { street: "Hauptstraße", town: "Rottweil", postcode: "78628", houseNumber: "1" },
  "abfallplus-58b436d5": { street: "Bahnhofstraße", town: "Bad Saulgau", postcode: "88348", houseNumber: "2" },
  "abfallplus-1d5df3c2": { street: "Schulstraße", town: "Kitzingen", postcode: "97318", houseNumber: "2" },
  "abfallplus-2dd1ce4c": { street: "Schulstraße", town: "Nordenham", postcode: "26954", houseNumber: "2" },
  "athos-ludwigsburg": { street: "Hauptstraße", town: "Ludwigsburg", postcode: "71638", houseNumber: "2" },
  "athos-ravensburgprivat": { street: "Bahnhofstraße", town: "Ravensburg", postcode: "88212", houseNumber: "1" },
  "athos-suedbrandenburg": { street: "Hauptstraße", town: "Königs Wusterhausen", postcode: "15711", houseNumber: "1" },
  "athos-suedwestsachsen": { street: "Hauptstraße", town: "Aue-Bad Schlema", postcode: "08280", houseNumber: "3" },
  "athos-vogtland": { street: "Bahnhofstraße", town: "Plauen", postcode: "08523", houseNumber: "4" },
  "athos-biberach": { street: "Hauptstraße", town: "Laupheim", postcode: "88471", houseNumber: "2" },
  "athos-lueneburg": { street: "Hauptstraße", town: "Lüneburg", postcode: "21335", houseNumber: "1" },
  "athos-schwarzeelster": { street: "Bahnhofstraße", town: "Finsterwalde", postcode: "03238", houseNumber: "1" },
  "athos-neckarodenwald": { street: "Hauptstraße", town: "Mosbach", postcode: "74821", houseNumber: "5" },
  "athos-straubing": { street: "Bahnhofstraße", town: "Straubing", postcode: "94315", houseNumber: "2" },
  "athos-verden": { street: "Hauptstraße", town: "Achim", postcode: "28832", houseNumber: "1" },
  "athos-starnberg": { street: "Hauptstraße", town: "Starnberg", postcode: "82319", houseNumber: "1" },
  "athos-miltenberg": { street: "Hauptstraße", town: "Miltenberg", postcode: "63897", houseNumber: "4" },
  "athos-freudenstadt": { street: "Schulstraße", town: "Horb am Neckar", postcode: "72160", houseNumber: "1" },
  "athos-fuerth": { street: "Hauptstraße", town: "Zirndorf", postcode: "90513", houseNumber: "1" },
  "athos-alzeyworms": { street: "Hauptstraße", town: "Alzey", postcode: "55232", houseNumber: "2" },
  "athos-ahrweiler": { street: "Hauptstraße", town: "Bad Neuenahr-Ahrweiler", postcode: "53474", houseNumber: "5" },
  "athos-wunsiedel": { street: "Bahnhofstraße", town: "Marktredwitz", postcode: "95615", houseNumber: "1" },
  "athos-suedwestpfalz": { street: "Hauptstraße", town: "Rodalben", postcode: "66976", houseNumber: "1" },
  "athos-zweibruecken": { street: "Hauptstraße", town: "Zweibrücken", postcode: "66482", houseNumber: "1" },
  "athos-wuerzburg": { street: "Hauptstraße", town: "Ochsenfurt", postcode: "97199", houseNumber: "1" },
  "athos-rheinhunsrueck": { street: "Hauptstraße", town: "Boppard", postcode: "56154", houseNumber: "1" },
  "muellmax-his": { street: "Hauptstraße", town: "Hanau", postcode: "63450", houseNumber: "1" },
  "muellmax-mai": { street: "Hauptstraße", town: "Maintal", postcode: "63477", houseNumber: "1" },
};
const CTRACE_FALLBACK_STREETS = ["Bahnhofstraße", "Kirchstraße"];
// Streets the vendor is known to hold, tried last, so a failure separates "wrong test address" from "provider down".
const CTRACE_EXTRA_STREETS: Record<string, string[]> = { "ctrace-landau": ["Königstr."], "ctrace-oberursel": ["Vorstadt"] };
// A per-house vendor needs its own street to keep its house number; the generic
// fallbacks below would carry no. 1 onto a street that may not have one.
const KEEPS_HOUSE_NUMBER = new Set(["bsr", "fes", "awm", "srh", "awsstuttgart", "awista", "srl", "athos", "abfallplus", "srdd", "aha", "awgwuppertal", "insertit", "abki", "wuerzburg", "avea", "oldenburg", "art", "waswob", "albabs", "elw", "fuerth", "heilbronn", "abis", "enni", "muellmax", "hws", "ksj", "tsk", "hausmuell", "sab", "swp", "osb", "meinabfall", "geb", "mags", "citko", "zah", "heidelberg", "beg", "sro", "ead"]);

const E2E_ADDRESSES: Array<{ label: string; street: string; town: string; postcode: string; houseNumber?: string }> = [
  { label: "Templergraben, 52062 Aachen", street: "Templergraben", town: "Aachen", postcode: "52062" },
  { label: "Bahnhofstraße, 71332 Waiblingen", street: "Bahnhofstraße", town: "Waiblingen", postcode: "71332" },
  { label: "Rheinstraße, 64283 Darmstadt", street: "Rheinstraße", town: "Darmstadt", postcode: "64283" },
  { label: "Weyher Straße, 28816 Stuhr", street: "Weyher Straße", town: "Stuhr", postcode: "28816" },
  { label: "Hauptstraße, 49536 Lienen", street: "Hauptstraße", town: "Lienen", postcode: "49536" },
  { label: "Karl-Marx-Allee 1, 10178 Berlin", street: "Karl-Marx-Allee", town: "Berlin", postcode: "10178", houseNumber: "1" },
  { label: "Frankenallee 2, 60327 Frankfurt am Main", street: "Frankenallee", town: "Frankfurt am Main", postcode: "60327", houseNumber: "2" },
  { label: "Francestr. 10, 80995 München", street: "Francestr.", town: "München", postcode: "80995", houseNumber: "10" },
];

function withTimeout<T>(p: Promise<T>, ms: number, what: string): Promise<T> {
  let t: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, rej) => {
    t = setTimeout(() => rej(new Error(`timeout after ${ms}ms (${what})`)), ms);
  });
  return Promise.race([p, timeout]).finally(() => clearTimeout(t));
}

function summarise(events: Array<{ startsAt: string; title: string }>) {
  const dates = events.map((e) => e.startsAt.slice(0, 10)).sort();
  const bins = [...new Set(events.map((e) => e.title))].slice(0, 6);
  return { events: events.length, from: dates[0] ?? null, to: dates[dates.length - 1] ?? null, bins };
}

const errMsg = (e: unknown) => (e instanceof Error ? e.message : String(e));

async function rhythmOf(cfg: AbfallConfig): Promise<string[]> {
  const ch = await withTimeout(rhythmChoices(cfg), PROVIDER_TIMEOUT_MS, "rhythms").catch(() => []);
  return ch.map((c) => `${c.bin}: ${c.options.map((o) => o.id).join("/")}`);
}

// Street pick + config merge, exactly the way the client would do it.
async function pickStreet(town: Town): Promise<{ option: StreetOption; config: AbfallConfig; query: string } | null> {
  let lastErr: unknown = null;
  for (const q of STEMS) {
    let options: StreetOption[];
    try {
      options = await searchStreets(town, q);
    } catch (e) { lastErr = e; continue; }
    if (!options.length) continue;
    const tn = town.name.trim().toLowerCase();
    const option = options.find((o) => o.name.trim().toLowerCase() !== tn) ?? options[0];
    const config: AbfallConfig = { ...option.config, label: `${option.name}, ${town.name}` };
    if (option.hausNrList?.length) config.hnrId = option.hausNrList[0].id;
    return { option, config, query: q };
  }
  if (lastErr) throw lastErr;
  return null;
}

async function probeProvider(
  p: typeof ABFALL_PROVIDERS[number], towns: Town[],
): Promise<Result> {
  const t0 = Date.now();
  const base: Result = {
    provider: p.id, name: p.name, family: p.family, town: null, street: null,
    events: 0, from: null, to: null, bins: [], ms: 0, triedTowns: [],
  };
  const done = (r: Partial<Result>): Result => ({ ...base, ...r, ms: Date.now() - t0 });

  try {
    if (p.upload) {
      const addr = PROBE_ADDRESSES[p.id];
      const town = addr?.town ?? towns.find((t) => t.provider === p.id)?.name;
      if (!town) return done({ upload: p.upload.why, error: "upload-only provider without a town" });
      const res = await resolveAddress({
        label: town, street: addr?.street ?? "Hauptstraße", town, postcode: addr?.postcode,
        state: STATE_NAME[PROVIDER_STATE.get(p.id) ?? p.state ?? ""],
      });
      return done({ town: res.town, upload: p.upload.why,
        ...(res.uploadOnly ? {} : { error: `expected uploadOnly, got supported=${res.supported}` }) });
    }
    if (RESOLVE_FAMILIES.has(p.family)) {
      const addr = PROBE_ADDRESSES[p.id];
      if (!addr) return done({ error: `no probe address configured for this ${p.family} provider` });
      const tried: string[] = [];
      let lastErr: string | undefined;
      const streets = KEEPS_HOUSE_NUMBER.has(p.family)
        ? [addr.street]
        : [addr.street, ...CTRACE_FALLBACK_STREETS, ...(CTRACE_EXTRA_STREETS[p.id] ?? [])];
      for (const street of streets) {
        tried.push(street);
        const geo: GeoAddress = {
          label: `${street}${addr.houseNumber ? ` ${addr.houseNumber}` : ""}, ${addr.postcode} ${addr.town}`,
          street, town: addr.town, postcode: addr.postcode,
          state: STATE_NAME[PROVIDER_STATE.get(p.id) ?? p.state ?? ""],
          ...(addr.houseNumber ? { houseNumber: addr.houseNumber } : {}),
        };
        let res;
        try {
          res = await withTimeout(resolveAddress(geo), PROVIDER_TIMEOUT_MS, `resolve ${p.id}`);
        } catch (e) { lastErr = errMsg(e); continue; }
        if (!res.supported || !res.config) { lastErr = `resolveAddress: unsupported (town=${res.town})`; continue; }
        try {
          const events = await withTimeout(readAbfallEvents(res.config), PROVIDER_TIMEOUT_MS, `read ${p.id}`);
          return done({ town: res.town, street: res.street ?? street, ...summarise(events), triedTowns: tried,
            rhythm: await rhythmOf(res.config),
            ...(events.length ? {} : { error: "resolved but readAbfallEvents returned 0 events" }) });
        } catch (e) { lastErr = errMsg(e); }
      }
      return done({ town: addr.town, triedTowns: tried, error: lastErr ?? "no street accepted" });
    }

    const mine = towns.filter((t) => t.provider === p.id);
    if (!mine.length) return done({ error: "aggregateTowns returned no towns for this provider" });
    const tried: string[] = [];
    let lastErr: string | undefined;
    let lastTown: string | null = null;
    let lastStreet: string | null = null;
    for (const town of mine.slice(0, 3)) {
      tried.push(town.name);
      lastTown = town.name;
      lastStreet = null;
      const remaining = PROVIDER_TIMEOUT_MS - (Date.now() - t0);
      if (remaining <= 0) { lastErr = `timeout after ${PROVIDER_TIMEOUT_MS}ms (budget spent)`; break; }
      try {
        const picked = await withTimeout(pickStreet(town), remaining, `streets ${p.id}/${town.name}`);
        if (!picked) { lastErr = `no street options for any query stem in ${town.name}`; continue; }
        lastStreet = picked.option.name;
        const left = PROVIDER_TIMEOUT_MS - (Date.now() - t0);
        if (left <= 0) { lastErr = `timeout after ${PROVIDER_TIMEOUT_MS}ms (budget spent)`; break; }
        const events = await withTimeout(readAbfallEvents(picked.config), left, `read ${p.id}/${town.name}`);
        if (events.length) {
          return done({ town: town.name, street: picked.option.name, ...summarise(events), triedTowns: tried,
            rhythm: await rhythmOf(picked.config) });
        }
        lastErr = `readAbfallEvents returned 0 events (street "${picked.option.name}" via stem "${picked.query}")`;
      } catch (e) {
        lastErr = errMsg(e);
        if (/timeout after/.test(lastErr)) break;
      }
    }
    return done({ town: lastTown, street: lastStreet, triedTowns: tried, error: lastErr ?? "unknown" });
  } catch (e) {
    return done({ error: errMsg(e) });
  }
}

async function e2e(a: typeof E2E_ADDRESSES[number]): Promise<Result> {
  const t0 = Date.now();
  const base: Result = {
    provider: `e2e:${a.town}`, name: a.label, family: "resolveAddress", town: a.town, street: a.street,
    events: 0, from: null, to: null, bins: [], ms: 0, triedTowns: [a.town],
  };
  const done = (r: Partial<Result>): Result => ({ ...base, ...r, ms: Date.now() - t0 });
  try {
    const res = await withTimeout(resolveAddress({ label: a.label, street: a.street, town: a.town, postcode: a.postcode, ...(a.houseNumber ? { houseNumber: a.houseNumber } : {}) }), PROVIDER_TIMEOUT_MS, `resolve ${a.town}`);
    if (!res.supported || !res.config) return done({ error: `resolveAddress: unsupported (town=${res.town})` });
    const cfg: AbfallConfig = { ...res.config, label: a.label };
    if (res.hausNrList?.length) cfg.hnrId = res.hausNrList[0].id;
    const events = await withTimeout(readAbfallEvents(cfg), PROVIDER_TIMEOUT_MS, `read ${a.town}`);
    return done({
      provider: `e2e:${a.town} (${cfg.vendor})`, town: res.town, street: res.street ?? a.street,
      ...summarise(events),
      ...(events.length ? {} : { error: "resolved but readAbfallEvents returned 0 events" }),
    });
  } catch (e) { return done({ error: errMsg(e) }); }
}

// ── main ─────────────────────────────────────────────────────────────────────
const started = Date.now();
const results: Result[] = [];
const e2eResults: Result[] = [];
async function flush() {
  await Deno.writeTextFile(OUT, JSON.stringify({
    at: new Date().toISOString(), elapsedMs: Date.now() - started,
    results, e2e: e2eResults,
  }, null, 1));
}

console.log("aggregating towns…");
const towns = await aggregateTowns();
console.log(`towns=${towns.length} in ${Date.now() - started}ms; probing ${ABFALL_PROVIDERS.length} providers with concurrency ${CONCURRENCY}`);

let next = 0;
async function worker() {
  while (next < ABFALL_PROVIDERS.length) {
    const p = ABFALL_PROVIDERS[next++];
    const r = await probeProvider(p, towns);
    results.push(r);
    console.log(`[${results.length}/${ABFALL_PROVIDERS.length}] ${r.provider} ${r.family} town=${r.town} street=${r.street} events=${r.events} ${r.from}..${r.to} ${r.ms}ms${r.rhythm?.length ? ` RHYTHM ${r.rhythm.join("; ")}` : ""}${r.upload ? ` UPLOAD(${r.upload})` : ""}${r.error ? ` ERROR: ${r.error}` : ""}`);
    await flush();
  }
}
await Promise.all(Array.from({ length: CONCURRENCY }, worker));

console.log("e2e resolveAddress runs…");
for (const a of E2E_ADDRESSES) {
  const r = await e2e(a);
  e2eResults.push(r);
  console.log(`e2e ${r.provider} town=${r.town} street=${r.street} events=${r.events} ${r.from}..${r.to} ${r.ms}ms${r.upload ? ` UPLOAD(${r.upload})` : ""}${r.error ? ` ERROR: ${r.error}` : ""}`);
  await flush();
}
const bad = results.filter((r) => r.error || (r.events === 0 && !r.upload));
const asking = results.filter((r) => r.rhythm?.length);
console.log(`rhythm question asked by ${asking.length}: ${asking.map((r) => `${r.provider} (${r.rhythm!.join("; ")})`).join(", ")}`);
console.log(`done in ${Date.now() - started}ms; providers=${results.length} bad=${bad.length}: ${bad.map((r) => r.provider).join(",")}`);
Deno.exit(0);
