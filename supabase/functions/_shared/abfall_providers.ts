// abfallProviders.ts — the German waste-collection provider MAP.
//
// This is the registry we grow provider-by-provider. Each entry is one waste
// authority, tagged with the vendor "family" whose URL pattern fetches its data.
// Cracking one family's pattern (see abfall.ts adapters) unlocks EVERY provider
// in that family at once — so a modest map already covers a large share of towns.
//
// Families:
//  - 'regioit'   — AbfallNavi JSON API (PLATFORM family: one API pattern, many
//                  regions). `region` is the host slug; towns are fetched live.
//  - 'awido'     — AWIDO Online / Cubefour (PLATFORM family). One shared host
//                  (awido.cubefour.de), keyed by `client`; towns fetched live.
//  - 'jumomind'  — Jumomind / MyMuell app API (PLATFORM family). Per-service host
//                  ({service}.jumomind.com), keyed by `service`; towns fetched live.
//  - 'abfallio'  — abfall.io / AbfallPlus legacy widget API (PLATFORM family).
//                  One host (api.abfall.io), keyed by a free per-authority `key`
//                  (extracted from each authority's embedded widget — NOT the
//                  paid B2B API). Towns fetched live from the widget's form.
//  - 'ctrace'    — C-Trace ASP.NET calendar (PLATFORM family, incl. Bremen).
//                  No street enumeration exists, so coverage is validated by
//                  probing the ICS export with the geocoded street (the server
//                  rejects unknown streets). One static town per service.
//  - 'awgbassum' — a bespoke per-street ICS export (SINGLE-provider family). Only
//                  AWG Bassum uses this exact pattern, so it does not grow. `host`
//                  is the domain; `cities` are the municipalities it serves (baked
//                  into the site's own page, so we list them here).
//  - 'bsr'       — Berliner Stadtreinigung (SINGLE-provider family, one city of
//                  3.8 million). Three keyless JSON GETs on umnewforms.bsr.de.
//                  Berlin plans per HOUSE, so the resolver needs the house
//                  number and says so (`needsHouseNumber`) instead of guessing.
//  - 'fes'       — FES Frankfurt am Main (SINGLE-provider family, 0.8 million).
//                  Two keyless JSON GETs on frankfurtplus.de and one ICS per
//                  address. Per HOUSE as well, so it answers the same way.
//  - 'awm'        — AWM München (SINGLE-provider family, 1.5 million). A TYPO3
//                  form walk: the page carries all 5,834 streets and the signed
//                  form fields, the POST answers with an ICS link. Per HOUSE.
//  - 'awbkoeln'  — AWB Köln (SINGLE-provider family, 1.1 million). Two keyless
//                  GETs; the calendar is keyed on the **Stellplatz**, not the
//                  household's own door. Per HOUSE.
//  - 'srh'       — Stadtreinigung Hamburg (SINGLE-provider family, 1.9 million).
//                  One unsigned POST turns a street into every house on it with
//                  its `hnId`, and the ICS hangs off that id alone. Per HOUSE,
//                  and the only vendor here that enumerates the house numbers,
//                  so the household picks theirs from a list.
//
// Broad coverage comes from adding more PLATFORM families (abfall.io/AbfallPlus,
// C-Trace) as new adapters — each one API pattern over many municipalities.
// To add coverage: append an entry (and, for a new platform, its adapter).
// See ABFALL.md for the full playbook incl. the live-census commands used to
// validate every slug below before it ships.

export interface AbfallProvider {
  id: string
  name: string
  family: 'regioit' | 'awido' | 'jumomind' | 'abfallio' | 'ctrace' | 'awgbassum' | 'bsr' | 'fes' | 'awm' | 'awbkoeln' | 'srh' | 'awsstuttgart' | 'awista'
  state?: string        // Bundesland, for display/grouping (optional)
  // regioit:
  region?: string       // AbfallNavi host slug; towns fetched live
  // awido:
  client?: string       // AWIDO customer slug (the `client=` path segment)
  // jumomind:
  service?: string      // Jumomind service id (the `{service}.jumomind.com` host)
  // abfallio:
  key?: string          // per-authority widget key (32-hex)
  town?: string         // display town for single-municipality keys (no town list to fetch)
  // ctrace (also reuses host + service + town):
  ort?: string          // the export's Ort= param ('' where the service wants it empty)
  icalFile?: string     // export path segment: 'cal' (default) or 'downloadcal'
  // awgbassum:
  host?: string         // domain, e.g. 'www.awg-bassum.de'
  cities?: string[]     // served municipalities (exact names for the ?city= param)
}

// regio-iT / AbfallNavi — one entry per host slug; towns resolved live. Slugs are
// validated live against /rest/orte; some resolve only on the shared host, which
// the resolver's per-service→shared fallback handles automatically.
// `gt2` (Gütersloh) is deliberately absent: the host still answers `orte` and
// 1,100 streets, but every `termine` call returns `[]` (live probe 2026-09-17,
// 14 streets, district level too) — the city has moved its calendar off
// AbfallNavi and the instance is a shell. Listed, it resolved a Gütersloh
// address as "verbunden" with an empty calendar.
const REGIOIT: AbfallProvider[] = [
  'aachen', 'zew2', 'aw-bgl2', 'bav', 'din', 'dorsten', 'hlv', 'coe',
  'krhs', 'pi', 'krwaf', 'stl', 'nds', 'nuernberg', 'solingen', 'wml2',
  // Added after a live census (2026-07):
  'cottbus', 'kronberg', 'muelheim', 'viersen', 'oberhausen', 'cux',
  'portawestfalica', 'unna', 'frankenthal', 'awvlippe', 'kranenburg',
].map((region) => ({ id: `regioit-${region}`, name: region, family: 'regioit' as const, region }))

// awgbassum — bespoke per-street ICS export. This exact pattern is unique to AWG
// Bassum (Landkreis Diepholz + Delmenhorst), so this family holds one provider and
// does not grow. Its 44 municipalities are listed below.
const AWG_BASSUM: AbfallProvider[] = [
  {
    id: 'awg-bassum',
    name: 'AWG Bassum (Landkreis Diepholz)',
    family: 'awgbassum',
    state: 'NI',
    host: 'www.awg-bassum.de',
    cities: [
      'Affinghausen', 'Asendorf', 'Bahrenborstel', 'Barenburg', 'Barnstorf',
      'Barver', 'Bassum', 'Borstel', 'Brockum', 'Bruchhausen-Vilsen',
      'Delmenhorst', 'Dickel', 'Diepholz', 'Drebber', 'Drentwede', 'Ehrenburg',
      'Eydelstedt', 'Freistatt', 'Hemsloh', 'Hüde', 'Kirchdorf', 'Lembruch',
      'Lemförde', 'Maasen', 'Marl', 'Martfeld', 'Mellinghausen', 'Neuenkirchen',
      'Quernheim', 'Rehden', 'Scholen', 'Schwaförden', 'Schwarme', 'Siedenburg',
      'Staffhorst', 'Stemshorn', 'Stuhr', 'Sudwalde', 'Sulingen', 'Syke',
      'Twistringen', 'Varrel', 'Wagenfeld', 'Wehrbleck', 'Wetschen', 'Weyhe',
    ],
  },
]

// AWIDO Online (Cubefour) — one shared host, one entry per customer slug; towns
// resolved live via getPlaces. All 46 slugs below were validated with a live
// census (2026-07): every one answers getPlaces with at least one town.
// Slug list sourced from the HA waste_collection_schedule project (awido_de.py).
const AWIDO: Array<[string, string]> = [
  ['aic-fdb', 'Landratsamt Aichach-Friedberg'],
  ['ansbach', 'Landkreis Ansbach'],
  ['awb-ak', 'AWB Landkreis Altenkirchen'],
  ['awb-duerkheim', 'AWB Landkreis Bad Dürkheim'],
  ['awld', 'Abfallwirtschaft Lahn-Dill-Kreis'],
  ['awv-isar-inn', 'Abfallwirtschaft Isar-Inn'],
  ['awv-nordschwaben', 'AWV Nordschwaben'],
  ['azv-hef-rof', 'AZV Hersfeld-Rotenburg'],
  ['bgl', 'Landkreis Berchtesgadener Land'],
  ['coburg', 'Landkreis Coburg'],
  ['ebe', 'Landkreis Ebersberg'],
  ['erding', 'Landkreis Erding'],
  ['eww-suew', 'Landkreis Südliche Weinstraße'],
  ['ffb', 'AWB Landkreis Fürstenfeldbruck'],
  ['fulda', 'Landkreis Fulda'],
  ['fulda-stadt', 'Stadt Fulda'],
  ['gifhorn', 'Landkreis Gifhorn'],
  ['gotha', 'Landkreis Gotha'],
  ['kaufbeuren', 'Stadt Kaufbeuren'],
  ['kaw-guenzburg', 'Landkreis Günzburg'],
  ['kelheim', 'Landkreis Kelheim'],
  ['koenigstein', 'Stadt Königstein im Taunus'],
  ['kreis-tir', 'Landkreis Tirschenreuth'],
  ['kronach', 'Landkreis Kronach'],
  ['kulmbach', 'Landkreis Kulmbach'],
  ['landkreisbetriebe', 'Landkreisbetriebe Neuburg-Schrobenhausen'],
  ['lichtenfels', 'Landkreis Lichtenfels'],
  ['lkgi', 'Landkreis Gießen'],
  ['lra-ab', 'Landkreis Aschaffenburg'],
  ['lra-dah', 'Landratsamt Dachau'],
  ['lra-mue', 'Landkreis Mühldorf a. Inn'],
  ['lra-regensburg', 'Landratsamt Regensburg'],
  ['lra-schweinfurt', 'Landkreis Schweinfurt'],
  ['memmingen', 'Stadt Memmingen'],
  ['neustadt', 'Neustadt a.d. Waldnaab'],
  ['pullach', 'Pullach im Isartal'],
  ['regensburg', 'Stadt Regensburg'],
  ['rmk', 'Abfallwirtschaft Rems-Murr'],
  ['rosenheim', 'Landkreis Rosenheim'],
  ['roth', 'Landkreis Roth'],
  ['tuebingen', 'Landkreis Tübingen'],
  ['unterhaching', 'Gemeinde Unterhaching'],
  ['unterschleissheim', 'Stadt Unterschleißheim'],
  ['wgv', 'WGV Recycling (Quarzbichl)'],
  ['zaso', 'ZV Abfallwirtschaft Saale-Orla'],
  ['zv-muc-so', 'Zweckverband München-Südost'],
]
const AWIDO_PROVIDERS: AbfallProvider[] = AWIDO.map(([client, name]) => ({
  id: `awido-${client}`, name, family: 'awido' as const, client,
}))

// Jumomind / MyMuell — one entry per service host; towns resolved live via
// r=cities_web. All 22 services below were validated with a live census
// (2026-07): every host answers with at least one town. `mymuell` alone serves
// ~300 towns nationwide. Slug list sourced from the HA project (jumomind_de.py).
const JUMOMIND: Array<[string, string]> = [
  ['zaw', 'ZAW Darmstadt-Dieburg'],
  ['aoe', 'Landkreis Altötting'],
  ['lka', 'MKW Aurich'],
  ['hom', 'Bad Homburg v.d.H.'],
  ['bdg', 'Kreiswerke Barnim'],
  ['hat', 'Hattersheim am Main'],
  ['ingol', 'Ingolstadt'],
  ['lue', 'Lübbecke'],
  ['sbm', 'Minden'],
  ['ksr', 'ZBH Recklinghausen'],
  ['rhe', 'RH Entsorgung (Rhein-Hunsrück)'],
  ['udg', 'UDG Uckermark'],
  ['mymuell', 'MyMuell App'],
  ['esn', 'Neustadt an der Weinstraße'],
  ['zac', 'ZA Celle'],
  ['ben', 'AWB Grafschaft Bentheim'],
  ['enwi', 'enwi Landkreis Harz'],
  ['hox', 'Abfallservice Kreis Höxter'],
  ['kbl', 'KBL Langen'],
  ['ros', 'Rosbach v.d. Höhe'],
  ['mkk', 'Main-Kinzig-Kreis'],
  ['wol', 'ALW Wolfenbüttel'],
]
const JUMOMIND_PROVIDERS: AbfallProvider[] = JUMOMIND.map(([service, name]) => ({
  id: `jumomind-${service}`, name, family: 'jumomind' as const, service,
}))

// abfall.io / AbfallPlus (legacy widget API) — one entry per authority key.
// Keys sourced from the HA project (service/AbfallIO.py) and censused live
// (2026-07): of 44 published keys, these 25 answer; the rest 401 (migrated to
// the newer app.abfallplus.de v3 API, a future family). Three shapes, all
// handled by one adapter: kommune select (most), streets-in-init single city
// (`town` set below), and district (Bezirk) select (the Prignitz authorities,
// whose villages surface as selectable towns).
const ABFALLIO: Array<[string, string, string?]> = [
  ['e21758b9c711463552fb9c70ac7d4273', 'EGST Steinfurt'],
  ['040b38fe83f026f161f30f282b2748c0', 'ASO Abfall-Service Osterholz'],
  ['594f805eb33677ad5bc645aeeeaf2623', 'Abfallwirtschaft Landkreis Kitzingen'],
  ['e5543a3e190cb8d91c645660ad60965f', 'MüllALARM / Schönmackers'],
  ['3ca331fb42d25e25f95014693ebcf855', 'Abfallbewirtschaftung Ostalbkreis'],
  ['27708a019a2e35de7eb4bbe7c851609f', 'Landkreis Oldenburg'],
  ['914fb9d000a9a05af4fd54cfba478860', 'AVR Kommunal Rhein-Neckar-Kreis'],
  ['645adb3c27370a61f7eabbb2039de4f1', 'Landkreis Rotenburg (Wümme)'],
  ['c22b850ea4eff207a273e46847e417c5', 'Landratsamt Unterallgäu'],
  ['248deacbb49b06e868d29cb53c8ef034', 'AWB Westerwaldkreis'],
  ['31fb9c7d783a030bf9e4e1994c7d2a91', 'Landkreis Weißenburg-Gunzenhausen'],
  ['49fe8a63a056adbfc43f051f61dd4a44', 'Landkreis Cuxhaven'],
  ['bd0c2d0177a0849a905cded5cb734a6f', 'Stadt Landshut', 'Landshut'],
  ['6efba91e69a5b454ac0ae3497978fe1d', 'Ludwigshafen am Rhein', 'Ludwigshafen am Rhein'],
  ['1e9592418582666e2a5d1c62b2683435', 'Amt Bad Wilsnack/Weisen (Prignitz)'],
  ['af91b65d2753a219309072837d8ea4e1', 'Gemeinde Groß Pankow (Prignitz)'],
  ['3cefa45ab357d231891bb497253c630f', 'Gemeinde Gumtow (Prignitz)'],
  ['798f59a75627f5d7686dab0c7226c877', 'Gemeinde Karstädt (Prignitz)'],
  ['bb937857acd951dfc8de5be8b8a49f6d', 'Amt Lenzen-Elbtalaue (Prignitz)'],
  ['4638881e7bebe6869e2e86de5f8aa09e', 'Amt Meyenburg (Prignitz)'],
  ['9fb3e2e5498e825250105ee272102a7b', 'Stadt Perleberg (Prignitz)'],
  ['a0461612534502273c518e28d4f6f1e4', 'Gemeinde Plattenburg (Prignitz)'],
  ['d92f59ef4066ae6d299478996d1d8430', 'Stadt Pritzwalk (Prignitz)'],
  ['4f06df48f154246415e57ce12b26abe5', 'Amt Putlitz/Berge (Prignitz)'],
  ['b870ecfa6e1f882680758d374ba3fa2d', 'Stadt Wittenberge (Prignitz)'],
]
const ABFALLIO_PROVIDERS: AbfallProvider[] = ABFALLIO.map(([key, name, town]) => ({
  id: `abfallio-${key.slice(0, 8)}`, name, family: 'abfallio' as const, key,
  ...(town ? { town } : {}),
}))

// C-Trace — ASP.NET waste calendars (session redirect + plain-text Ort/Strasse/
// Hausnr params -> ICS). No street enumeration; the adapter validates coverage
// by probing the export with the geocoded street. All four entries were
// validated live (2026-07); Dietzenbach / Bayreuth / St. Wendel from the HA
// list currently 500/404 on every variant tried and are left out. The Kreis
// services (Augsburg Land, Segeberg, Groß-Gerau, ...) need their town lists
// cracked before they can be added.
const CTRACE: AbfallProvider[] = [
  {
    id: 'ctrace-bremen', name: 'Bremer Stadtreinigung', family: 'ctrace', state: 'HB',
    host: 'web.c-trace.de', service: 'bremenabfallkalender', icalFile: 'cal',
    town: 'Bremen', ort: 'Bremen',
  },
  {
    id: 'ctrace-arnsberg', name: 'Stadt Arnsberg', family: 'ctrace', state: 'NW',
    host: 'web.c-trace.de', service: 'arnsberg-abfallkalender', icalFile: 'cal',
    town: 'Arnsberg', ort: 'Arnsberg',
  },
  {
    id: 'ctrace-landau', name: 'EWB Landau in der Pfalz', family: 'ctrace', state: 'RP',
    host: 'apps.c-trace.de', service: 'web.landau', icalFile: 'downloadcal',
    town: 'Landau in der Pfalz', ort: '',
  },
  {
    id: 'ctrace-oberursel', name: 'BSO Oberursel', family: 'ctrace', state: 'HE',
    host: 'apps.c-trace.de', service: 'web.oberursel', icalFile: 'cal',
    town: 'Oberursel', ort: '',
  },
]

// BSR — Berlin, the one city that is a Bundesland. Verified live 2026-09-17:
// Karl-Marx-Allee 1 → 78 pickup days, and houses 1, 3 and 12 on the same street
// answer three different calendars, which is why the family needs the number.
const BSR: AbfallProvider[] = [
  { id: 'bsr-berlin', name: 'BSR Berliner Stadtreinigung', family: 'bsr', state: 'BE', town: 'Berlin' },
]

// FES — Frankfurt am Main. Verified live 2026-09-17: Frankenallee 2 reads 156
// pickups and Frankenallee 20 reads 130, which is why this one is per house too.
//
// The town is spelled out. "Frankfurt" alone would also match **Frankfurt
// (Oder)**, a different city 500 km away in Brandenburg, through townMatches'
// prefix rule — and "Bahnhofstraße" exists in both, so the mis-match would have
// produced a plausible, entirely wrong calendar. `probeFes` checks the postcode
// on top of that.
const FES: AbfallProvider[] = [
  { id: 'fes-frankfurt', name: 'FES Frankfurt am Main', family: 'fes', state: 'HE', town: 'Frankfurt am Main' },
]

// AWM — München. Verified live 2026-09-17 against an address whose own ICS
// download was to hand: Francestr. 10 comes back byte-for-byte as the file the
// household had already been given.
const AWM: AbfallProvider[] = [
  { id: 'awm-muenchen', name: 'AWM Abfallwirtschaftsbetrieb München', family: 'awm', state: 'BY', town: 'München' },
]

// AWB Köln. Verified live 2026-09-17 against the household's own ICS download.
// The only vendor here whose address search returns a **postcode**, and the only
// one whose ICS takes a year range rather than one signed year.
const AWB_KOELN: AbfallProvider[] = [
  { id: 'awbkoeln-koeln', name: 'AWB Abfallwirtschaftsbetriebe Köln', family: 'awbkoeln', state: 'NW', town: 'Köln' },
]

// Stadtreinigung Hamburg. Verified live 2026-09-17 against the household's own
// webcal link: hnId 139014 is Fraenkelstraße 1-3, and the feed it returns is the
// one they were already subscribed to.
//
// Hamburg is a city state, so the town and the Bundesland are the same word and
// there is no neighbouring authority to be confused with — the one place where
// the town guard costs nothing.
// Stuttgart's feed is addressed by the street name and house number themselves —
// no ids at all — so one household's subscription link is the whole API.
// AWISTA Kommunal, Düsseldorf. The calendar is addressed by a uuid the city's own
// address search hands out; see abfall/vendors/awista.ts.
const AWISTA: AbfallProvider[] = [
  { id: 'awista-duesseldorf', name: 'AWISTA Kommunal Düsseldorf', family: 'awista', state: 'NW', town: 'Düsseldorf' },
]

const AWS_STUTTGART: AbfallProvider[] = [
  { id: 'aws-stuttgart', name: 'Abfallwirtschaft Stuttgart', family: 'awsstuttgart', state: 'BW', town: 'Stuttgart' },
]

const SRH: AbfallProvider[] = [
  { id: 'srh-hamburg', name: 'Stadtreinigung Hamburg', family: 'srh', state: 'HH', town: 'Hamburg' },
]

// The Bundesland each authority sits in — **a correctness guard, not a label.**
//
// Two towns in different states share a name far more often than one would
// like: 37 of the names in this map do. A geocoded "Kirchheim" in Baden-
// Württemberg matches the "Kirchheim" of a Bavarian Landkreis exactly, and
// where that vendor publishes one schedule for the whole town it accepts any
// street at all — so the household gets real pickup dates for a place 300 km
// away. `matchTownAndStreet` therefore drops a candidate whose state contradicts
// the address's own, which is the postcode's information in the form the vendors
// actually give us: none of them publishes a PLZ, but every one of them serves
// exactly one Bundesland.
//
// Verified against the live town lists rather than guessed: every entry was
// checked by geocoding sample towns of that provider (tool/abfall_census).
// `jumomind-mymuell` is deliberately absent — it serves ~300 towns nationwide,
// so it has no single state, and an address it might wrongly match is caught by
// nothing here. That is the one gap, and it is written down rather than hidden.
const PROVIDER_STATES: Record<string, string> = {
  'abfallio-040b38fe': 'NI',
  'abfallio-1e959241': 'BB',
  'abfallio-248deacb': 'RP',
  'abfallio-27708a01': 'NI',
  'abfallio-31fb9c7d': 'BY',
  'abfallio-3ca331fb': 'BW',
  'abfallio-3cefa45a': 'BB',
  'abfallio-4638881e': 'BB',
  'abfallio-49fe8a63': 'NI',
  'abfallio-4f06df48': 'BB',
  'abfallio-594f805e': 'BY',
  'abfallio-645adb3c': 'NI',
  'abfallio-6efba91e': 'RP',
  'abfallio-798f59a7': 'BB',
  'abfallio-914fb9d0': 'BW',
  'abfallio-9fb3e2e5': 'BB',
  'abfallio-a0461612': 'BB',
  'abfallio-af91b65d': 'BB',
  'abfallio-b870ecfa': 'BB',
  'abfallio-bb937857': 'BB',
  'abfallio-bd0c2d01': 'BY',
  'abfallio-c22b850e': 'BY',
  'abfallio-d92f59ef': 'BB',
  'abfallio-e21758b9': 'NW',
  'abfallio-e5543a3e': 'NW',
  'awg-bassum': 'NI',
  'awido-aic-fdb': 'BY',
  'awido-ansbach': 'BY',
  'awido-awb-ak': 'RP',
  'awido-awb-duerkheim': 'RP',
  'awido-awld': 'HE',
  'awido-awv-isar-inn': 'BY',
  'awido-awv-nordschwaben': 'BY',
  'awido-azv-hef-rof': 'HE',
  'awido-bgl': 'BY',
  'awido-coburg': 'BY',
  'awido-ebe': 'BY',
  'awido-erding': 'BY',
  'awido-eww-suew': 'RP',
  'awido-ffb': 'BY',
  'awido-fulda': 'HE',
  'awido-fulda-stadt': 'HE',
  'awido-gifhorn': 'NI',
  'awido-gotha': 'TH',
  'awido-kaufbeuren': 'BY',
  'awido-kaw-guenzburg': 'BY',
  'awido-kelheim': 'BY',
  'awido-koenigstein': 'HE',
  'awido-kreis-tir': 'BY',
  'awido-kronach': 'BY',
  'awido-kulmbach': 'BY',
  'awido-landkreisbetriebe': 'BY',
  'awido-lichtenfels': 'BY',
  'awido-lkgi': 'HE',
  'awido-lra-ab': 'BY',
  'awido-lra-dah': 'BY',
  'awido-lra-mue': 'BY',
  'awido-lra-regensburg': 'BY',
  'awido-lra-schweinfurt': 'BY',
  'awido-memmingen': 'BY',
  'awido-neustadt': 'BY',
  'awido-pullach': 'BY',
  'awido-regensburg': 'BY',
  'awido-rmk': 'BW',
  'awido-rosenheim': 'BY',
  'awido-roth': 'BY',
  'awido-tuebingen': 'BW',
  'awido-unterhaching': 'BY',
  'awido-unterschleissheim': 'BY',
  'awido-wgv': 'BY',
  'awido-zaso': 'TH',
  'awido-zv-muc-so': 'BY',
  'awm-muenchen': 'BY',
  'awbkoeln-koeln': 'NW',
  'srh-hamburg': 'HH',
  'aws-stuttgart': 'BW',
  'awista-duesseldorf': 'NW',
  'bsr-berlin': 'BE',
  'ctrace-arnsberg': 'NW',
  'ctrace-bremen': 'HB',
  'ctrace-landau': 'RP',
  'ctrace-oberursel': 'HE',
  'fes-frankfurt': 'HE',
  'jumomind-aoe': 'BY',
  'jumomind-bdg': 'BB',
  'jumomind-ben': 'NI',
  'jumomind-enwi': 'ST',
  'jumomind-esn': 'RP',
  'jumomind-hat': 'HE',
  'jumomind-hom': 'HE',
  'jumomind-hox': 'NW',
  'jumomind-ingol': 'BY',
  'jumomind-kbl': 'HE',
  'jumomind-ksr': 'NW',
  'jumomind-lka': 'NI',
  'jumomind-lue': 'NW',
  'jumomind-mkk': 'HE',
  'jumomind-rhe': 'RP',
  'jumomind-ros': 'HE',
  'jumomind-sbm': 'NW',
  'jumomind-udg': 'BB',
  'jumomind-wol': 'NI',
  'jumomind-zac': 'NI',
  'jumomind-zaw': 'HE',
  'regioit-aachen': 'NW',
  'regioit-aw-bgl2': 'NW',
  'regioit-awvlippe': 'NW',
  'regioit-bav': 'NW',
  'regioit-coe': 'NW',
  'regioit-cottbus': 'BB',
  'regioit-cux': 'NI',
  'regioit-din': 'NW',
  'regioit-dorsten': 'NW',
  'regioit-frankenthal': 'RP',
  'regioit-hlv': 'NW',
  'regioit-kranenburg': 'NW',
  'regioit-krhs': 'NW',
  'regioit-kronberg': 'HE',
  'regioit-krwaf': 'NW',
  'regioit-muelheim': 'NW',
  'regioit-nds': 'SH',
  'regioit-nuernberg': 'BY',
  'regioit-oberhausen': 'NW',
  'regioit-pi': 'SH',
  'regioit-portawestfalica': 'NW',
  'regioit-solingen': 'NW',
  'regioit-stl': 'NW',
  'regioit-unna': 'NW',
  'regioit-viersen': 'NW',
  'regioit-wml2': 'NW',
  'regioit-zew2': 'NW',
}

export const ABFALL_PROVIDERS: AbfallProvider[] = [
  ...REGIOIT, ...AWIDO_PROVIDERS, ...JUMOMIND_PROVIDERS, ...ABFALLIO_PROVIDERS,
  ...CTRACE, ...AWG_BASSUM, ...BSR, ...FES, ...AWM, ...AWB_KOELN, ...SRH, ...AWS_STUTTGART,
  ...AWISTA,
].map((p) => (p.state ? p : { ...p, ...(PROVIDER_STATES[p.id] ? { state: PROVIDER_STATES[p.id] } : {}) }))
