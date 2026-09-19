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
  family: 'regioit' | 'awido' | 'jumomind' | 'abfallio' | 'ctrace' | 'awgbassum' | 'bsr' | 'fes' | 'awm' | 'awbkoeln' | 'srh' | 'awsstuttgart' | 'awista' | 'srl' | 'athos' | 'abfallplus' | 'srdd' | 'aha' | 'awgwuppertal' | 'insertit' | 'abki' | 'wuerzburg' | 'avea' | 'oldenburg'
    | 'art' | 'waswob' | 'albabs' | 'elw' | 'fuerth' | 'heilbronn' | 'abis' | 'enni' | 'muellmax' | 'hws' | 'ksj' | 'tsk' | 'hausmuell' | 'sab' | 'swp' | 'osb' | 'meinabfall' | 'geb' | 'mags' | 'citko' | 'zah' | 'heidelberg' | 'beg' | 'sro' | 'ead'
  state?: string        // Bundesland, for display/grouping (optional)
  // regioit:
  region?: string       // AbfallNavi host slug; towns fetched live
  // awido:
  client?: string       // AWIDO customer slug (the `client=` path segment); insertit: the BmsAbfallkalender<Slug> path slug
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
  cities?: string[]     // awgbassum: served municipalities (exact ?city= names); jumomind: town allowlist
  notTowns?: string[]   // abfallio: towns on the key that are taken from the town's own service instead
  skipTypes?: string[]  // abfallplus: wasteType ids that are city-wide stops, not anybody's bin
  wrongPostcodes?: boolean // abfallplus: the publisher's street postcodes are not the streets' own
  // **Served by upload only: nothing is ever requested from this provider.**
  // Its operator either reserves the data for non-commercial use in real terms
  // of use (`terms` — a free feature inside an app with a paid tier is still
  // commercial), or its robots.txt disallows the path the dates live on
  // (`robots`). Checked 2026-09-19 against every request the live probe makes;
  // tool/abfall_census/third_party.json holds the quotes. The town is still
  // recognised — from `town`, `cities` or abfall/upload_towns.ts, never from
  // the vendor — so the household is told why and sent to the file upload,
  // with `page` being where the town hands out its calendar.
  upload?: { why: 'terms' | 'robots'; page?: string }
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
  ['ebu', 'EBU Entsorgungs-Betriebe der Stadt Ulm'],
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
  ['awb-altenburg', 'AWB Altenburger Land'],
]
const AWIDO_PROVIDERS: AbfallProvider[] = AWIDO.map(([client, name]) => ({
  id: `awido-${client}`, name, family: 'awido' as const, client,
}))

// Jumomind — one entry per service host; towns resolved live via r=cities_web.
// Each host is one authority's own branded app. **`mymuell` is deliberately not
// here** (removed 2026-09-18): the MyMüll app re-publishes ~300 towns'
// schedules under its own brand, and Abfall takes a calendar from the
// authority's own service or not at all. Its Ulm entry was also a shell — 1,166
// streets, no dates in any area. Slug list from the HA project (jumomind_de.py).
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
  // 'rhe' (RH Entsorgung, Rhein-Hunsrück) left 2026-09-19: its own Athos tenant
  // (athos-rheinhunsrueck) serves the same towns and may be read.
  ['udg', 'UDG Uckermark'],
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
// **Every *.jumomind.com host answers robots.txt with `Disallow: /`** (checked
// 2026-09-19, all 22), so the whole family is upload-only: the towns are still
// recognised from abfall/upload_towns.ts and nothing is requested from them.
// The page is where the town's own calendar is, where we know it.
const JUMOMIND_PAGES: Record<string, string> = {
  ingol: 'https://www.in-kb.de/abfallkalender',
  ksr: 'https://recklinghausen.buergerportal.digital/calendar',
}
const JUMOMIND_PROVIDERS: AbfallProvider[] = JUMOMIND.map(([service, name]) => ({
  id: `jumomind-${service}`, name, family: 'jumomind' as const, service,
  upload: { why: 'robots' as const, page: JUMOMIND_PAGES[service] },
}))

// MyMüll only where the authority itself names it as its calendar, checked on
// its own site (2026-09-18) — never the nationwide list. `cities` is the
// allowlist: a town is taken when its MyMüll name is one of these or starts
// with one plus "-" (Kreis Paderborn lists villages as "Büren-Ahden"). One row
// per Bundesland, so the state guard holds.
//   Paderborn's own Abfuhrtermine page on paderborn.de embeds the MyMüll web
//   module for ASP (embed.js?m=asp) and A.V.E. uses it for the other nine Kreis
//   municipalities; Salzgitter's "Online-Abfallkalender" is the MyMüll web
//   module. Darmstadt is no longer here: EAD's page only shows the app's
//   badges beside a calendar of its own (vendors/ead.ts).
const MYMUELL_OFFICIAL: AbfallProvider[] = [
  { id: 'jumomind-mymuell-asp', name: 'ASP Paderborn (Online-Abfallkalender der Stadt)', family: 'jumomind', service: 'mymuell', state: 'NW',
    cities: ['Paderborn'],
    upload: { why: 'robots', page: 'https://www.paderborn.de/microsite/asp/abfallentsorgung/abfuhrtermine_pb.php' } },
  { id: 'jumomind-mymuell-ave', name: 'A.V.E. Kreis Paderborn (MyMüll)', family: 'jumomind', service: 'mymuell', state: 'NW',
    cities: ['Altenbeken', 'Bad Lippspringe', 'Bad Wünnenberg', 'Borchen', 'Büren', 'Delbrück',
      'Hövelhof', 'Lichtenau', 'Salzkotten'],
    upload: { why: 'robots', page: 'https://www.ave-kreis-paderborn.de/beratungsservice/abfallkalender/' } },
  { id: 'jumomind-mymuell-srb', name: 'SRB Stadt Salzgitter (MyMüll)', family: 'jumomind', service: 'mymuell', state: 'NI',
    cities: ['Salzgitter'],
    upload: { why: 'robots', page: 'https://www.salzgitter.de/leben/srb/abfallkalender-online.php' } },
]

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
  // Found 2026-09-19 on each authority's own calendar page (the Abfuhrkalender
  // Atlas, tool/abfall_authorities): read end to end by candidate probe, robots.txt
  // allowing the adapter's path, no terms reserving the dates.
  ['b3b6d7b73b7be61117fedc1dd5ec255a', 'ALB Abfallwirtschaft Breisgau-Hochschwarzwald'],
  ['e00c91ebd40b93d6b9cb697d3f0d6a50', 'Landkreis Görlitz (NEG)'],
  ['04b7561b94f2cbaa171cd85bb6aa56de', 'Landratsamt Landshut'],
]
// Towns on a key that come from the town's own service instead. MüllALARM is
// Schönmackers' app — the contracted collector in most of its towns — but
// Krefeld's own GSAK publishes on Insert IT, and the key's Krefeld lacked whole
// streets (Hochstraße).
const ABFALLIO_NOT_TOWNS: Record<string, string[]> = { 'e5543a3e': ['Krefeld'] }

const ABFALLIO_PROVIDERS: AbfallProvider[] = ABFALLIO.map(([key, name, town]) => ({
  id: `abfallio-${key.slice(0, 8)}`, name, family: 'abfallio' as const, key,
  ...(town ? { town } : {}),
  ...(ABFALLIO_NOT_TOWNS[key.slice(0, 8)] ? { notTowns: ABFALLIO_NOT_TOWNS[key.slice(0, 8)] } : {}),
}))

// AbfallPlus publisher widgets (v3, GraphQL) — the same kind of key, embedded as
// `<abfallplus-publisher key=…>`. See abfall/vendors/abfallplus.ts.
const ABFALLPLUS: AbfallProvider[] = [
  // ebe-essen.de/abfuhrkalender; the old abfallkalender.ebe-essen.de is NXDOMAIN.
  { id: 'abfallplus-51be67f3', name: 'EBE Entsorgungsbetriebe Essen', family: 'abfallplus', state: 'NW',
    key: '51be67f3758f1fb57b420efe065c0663', town: 'Essen' },
  // Keys from the Home Assistant project's AbfallIOGraphQL list, each answering
  // the v3 API live on 2026-09-18. Osterholz's is the one that replaced the dead
  // legacy key above.
  //
  // **Freiburg** (ASF, city 5846) and **Hagen** (HEB, city 2657) publish every
  // Restmüll rhythm side by side — Freiburg's "Restabfalltonne" wöchentlich /
  // 14-täglich / vierwöchentlich, Hagen's wöchentlich / rote Woche / grüne Woche
  // — and the household picks its own when it connects (RhythmChoice in
  // abfall/core.ts). **Neither publisher's street postcodes are real** — every
  // Freiburg street claims 79112 and every Hagen one 50895 — so they are not
  // compared (`wrongPostcodes`); both are one city, not a Landkreis. Hagen's
  // Umweltmobil (223) and Grünschnittsammlung (267) are city-wide stops, not
  // the household's.
  { id: 'abfallplus-ba5c0a03', name: 'ASF Abfallwirtschaft und Stadtreinigung Freiburg', family: 'abfallplus', state: 'BW',
    key: 'ba5c0a03ba41d81479797313161ced08', town: 'Freiburg im Breisgau', wrongPostcodes: true },
  { id: 'abfallplus-8fb8b2b0', name: 'HEB Hagener Entsorgungsbetrieb', family: 'abfallplus', state: 'NW',
    key: '8fb8b2b06139c9575b69493a4c86a7b9', town: 'Hagen', skipTypes: ['223', '267'], wrongPostcodes: true },
  // tbr-reutlingen.de's Entsorgungskalender embeds this key. The city has its
  // own collection, which the Landkreis key (15f69fab) lists without a street.
  { id: 'abfallplus-1bf5dd38', name: 'TBR Technische Betriebsdienste Reutlingen', family: 'abfallplus', state: 'BW',
    key: '1bf5dd3852fd8c24ec5679c53f678540', town: 'Reutlingen' },
  // Answering but deliberately NOT listed, because the calendar would be wrong:
  //  - Landkreis Göttingen (4b5702d7…) and Schwarzwald-Baar-Kreis (30628292…)
  //    publish every rhythm of one bin side by side, like Freiburg; they can
  //    come in the same way, once somebody checks their titles tag cleanly.
  //    (The city of Göttingen is GEB's own calendar, vendors/geb.ts.)
  //  - AWG Landkreis Calw (0813ea99…) plans per Ortsteil ("Kernstadt (ohne
  //    Monhardt)", "Berneck", each "alle Straßen"), and the geocoder rarely
  //    names the Ortsteil; guessing it hands out a neighbouring village's days.
  //  - KELL Landkreis Leipzig and AWB Böblingen answer with no cities at all.
  { id: 'abfallplus-efb75cbd', name: 'Landkreis Märkisch-Oderland', family: 'abfallplus', state: 'BB', key: 'efb75cbd1f08fae1d4e47ae72a85c655' },
  { id: 'abfallplus-15f69fab', name: 'Landkreis Reutlingen', family: 'abfallplus', state: 'BW', key: '15f69fab91c4cae50d9dbb5bcfd383f0' },
  { id: 'abfallplus-80acad6c', name: 'Wirtschaftsbetriebe Duisburg', family: 'abfallplus', state: 'NW', key: '80acad6c77fe9342ebafad29a8c58bf6', town: 'Duisburg' },
  { id: 'abfallplus-2085afd9', name: 'ASG Nordsachsen', family: 'abfallplus', state: 'SN', key: '2085afd95285e645e15ee9623d0c5172' },
  { id: 'abfallplus-8b016df0', name: 'ASO Abfall-Service Osterholz', family: 'abfallplus', state: 'NI', key: '8b016df0116d1d5094fa339bebea0c65' },
  // Found 2026-09-19 on each authority's own calendar page (the Abfuhrkalender
  // Atlas, tool/abfall_authorities): read end to end by candidate probe, robots.txt
  // allowing the adapter's path, no terms reserving the dates.
  // Cloppenburg and Rottweil print Restmüll in several rhythms; the household
  // picks its own (RhythmChoice). Held back for the same reason as Göttingen:
  // Zollernalb, Traunstein, Nordfriesland and Tuttlingen list a container size
  // beside the household bin with no way to choose; Neuwied lists every
  // Schadstoffmobil stop in the county; Böblingen's publisher answers with no
  // cities; Grünwald's key lists 14 Gemeinden and is only confirmed as Grünwald's.
  { id: 'abfallplus-ff692443', name: 'Eigenbetrieb Abfallwirtschaft Ortenaukreis', family: 'abfallplus', state: 'BW', key: 'ff692443f8b07d99f93674e9e0b6f529' },
  { id: 'abfallplus-be047b0b', name: 'Abfallwirtschaft Landkreis Heilbronn', family: 'abfallplus', state: 'BW', key: 'be047b0bf308c04e4dab7240aa418381' },
  { id: 'abfallplus-0d74f933', name: 'AHE Ennepe-Ruhr-Kreis', family: 'abfallplus', state: 'NW', key: '0d74f933a2959ed0133cd88eda556714' },
  { id: 'abfallplus-4dc39a5b', name: 'Landkreis Bautzen, Abfallamt', family: 'abfallplus', state: 'SN', key: '4dc39a5bb7e7f0b3ea3b8a15824b4a8d' },
  { id: 'abfallplus-26bbdbe6', name: 'AWB Landkreis Augsburg', family: 'abfallplus', state: 'BY', key: '26bbdbe6929dad3dc75d324f55a6990e' },
  { id: 'abfallplus-f35bd08b', name: 'AWB Landkreis Göppingen', family: 'abfallplus', state: 'BW', key: 'f35bd08b1d18d9c81fcdee75dbcce5d3' },
  { id: 'abfallplus-0e37304e', name: 'AWB Landkreis Rastatt', family: 'abfallplus', state: 'BW', key: '0e37304e640bce56f77c5506b3dadedb' },
  { id: 'abfallplus-2fd91be1', name: 'AZV Rhein-Mosel-Eifel (Landkreis Mayen-Koblenz)', family: 'abfallplus', state: 'RP', key: '2fd91be1ebb9ad8558b44914a983c435' },
  { id: 'abfallplus-29ac778f', name: 'Landkreis Cloppenburg', family: 'abfallplus', state: 'NI', key: '29ac778f07646f919b2aec119d0aedd0' },
  { id: 'abfallplus-29727e74', name: 'AWB Landkreis Limburg-Weilburg', family: 'abfallplus', state: 'HE', key: '29727e74d11041d98df0c0d013a846c6' },
  { id: 'abfallplus-254ef8a2', name: 'Landratsamt Ostallgäu', family: 'abfallplus', state: 'BY', key: '254ef8a2f4aa7cd1bff7f372d5dcfc53' },
  { id: 'abfallplus-30f9958c', name: 'Landkreis Rottweil, Eigenbetrieb Abfallwirtschaft', family: 'abfallplus', state: 'BW', key: '30f9958cb64ca47a83f40e0a738ddea0' },
  { id: 'abfallplus-58b436d5', name: 'Landratsamt Sigmaringen, Kreisabfallwirtschaft', family: 'abfallplus', state: 'BW', key: '58b436d539db805a4fadd93bb87b2693' },
  { id: 'abfallplus-1d5df3c2', name: 'abfallwelt Landkreis Kitzingen', family: 'abfallplus', state: 'BY', key: '1d5df3c2a6f64f5636f2c471649a0e6c' },
  { id: 'abfallplus-2dd1ce4c', name: 'GIB Entsorgung Wesermarsch', family: 'abfallplus', state: 'NI', key: '2dd1ce4c69e1a02c259502258412c40d' },
]

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
  { id: 'awista-duesseldorf', name: 'AWISTA Kommunal Düsseldorf', family: 'awista', state: 'NW', town: 'Düsseldorf',
    upload: { why: 'terms', page: 'https://www.awista-kommunal.de/abfallkalender' } },
]

const AWS_STUTTGART: AbfallProvider[] = [
  { id: 'aws-stuttgart', name: 'Abfallwirtschaft Stuttgart', family: 'awsstuttgart', state: 'BW', town: 'Stuttgart',
    upload: { why: 'robots', page: 'https://www.stuttgart.de/abfallkalender' } },
]

// Stadtreinigung Leipzig. One keyless street search lists every house with the
// position numbers its ICS is read by; see abfall/vendors/srl.ts.
const SRL: AbfallProvider[] = [
  { id: 'srl-leipzig', name: 'Stadtreinigung Leipzig', family: 'srl', state: 'SN', town: 'Leipzig' },
]

// Dresden's AbfallApp; see abfall/vendors/srdd.ts.
const SRDD: AbfallProvider[] = [
  { id: 'srdd-dresden', name: 'Stadtreinigung Dresden', family: 'srdd', state: 'SN', town: 'Dresden',
    upload: { why: 'terms', page: 'https://www.dresden.de/abfuhrkalender' } },
]

// The Region Hannover's 21 municipalities, Hannover itself included; the towns
// are the Gemeinde options on aha's own form. See abfall/vendors/aha.ts.
const AWGW: AbfallProvider[] = [
  { id: 'awg-wuppertal', name: 'AWG Abfallwirtschaftsgesellschaft Wuppertal', family: 'awgwuppertal', state: 'NW', town: 'Wuppertal' },
]

// Insert IT BmsAbfallkalender — one app per city on www.insert-it.de; `client` is
// the path slug after "BmsAbfallkalender". Krefeld's is GSAK's own calendar and
// replaces the MüllALARM key's Krefeld (which lacked streets like Hochstraße).
// Hattingen runs it too, but its 2026 calendar held a handful of dates per bin
// when it was surveyed (2026-09-18).
const INSERTIT: AbfallProvider[] = [
  { id: 'insertit-mannheim', name: 'Abfallwirtschaft Mannheim', family: 'insertit', state: 'BW', client: 'Mannheim', town: 'Mannheim' },
  { id: 'insertit-kassel', name: 'Die Stadtreiniger Kassel', family: 'insertit', state: 'HE', client: 'Kassel', town: 'Kassel' },
  { id: 'insertit-luebeck', name: 'Entsorgungsbetriebe Lübeck', family: 'insertit', state: 'SH', client: 'Luebeck', town: 'Lübeck' },
  { id: 'insertit-herne', name: 'entsorgung herne', family: 'insertit', state: 'NW', client: 'Herne', town: 'Herne' },
  { id: 'insertit-krefeld', name: 'GSAK Krefeld', family: 'insertit', state: 'NW', client: 'Krefeld', town: 'Krefeld' },
  { id: 'insertit-offenbach', name: 'ESO Stadtservice Offenbach', family: 'insertit', state: 'HE', client: 'Offenbach', town: 'Offenbach am Main' },
]

const ABKI: AbfallProvider[] = [
  { id: 'abk-kiel', name: 'ABK Abfallwirtschaftsbetrieb Kiel', family: 'abki', state: 'SH', town: 'Kiel' },
]

// Würzburg: the city's own open data (DL-DE-BY-2.0) and street page; Leverkusen:
// AVEA's own street pages and ICS; Oldenburg: the city's TYPO3 plugin. One
// vendor file each.
const CITY_OWN: AbfallProvider[] = [
  { id: 'stadt-wuerzburg', name: 'Stadt Würzburg (Die Stadtreiniger)', family: 'wuerzburg', state: 'BY', town: 'Würzburg' },
  { id: 'avea-leverkusen', name: 'AVEA Leverkusen', family: 'avea', state: 'NW', town: 'Leverkusen' },
  // The city, not the Landkreis (abfallio 27708a01): oldenburg.de's own plugin.
  { id: 'stadt-oldenburg', name: 'Abfallwirtschaftsbetrieb Stadt Oldenburg', family: 'oldenburg', state: 'NI', town: 'Oldenburg' },
  // Batch 5 (2026-09-18): each the authority's own site or the widget its own
  // page embeds. One vendor file each, except where noted.
  { id: 'art-trier', name: 'A.R.T. Zweckverband Abfallwirtschaft Region Trier', family: 'art', state: 'RP',
    upload: { why: 'robots', page: 'https://www.art-trier.de/abfuhrtermin' } },
  { id: 'was-wolfsburg', name: 'WAS Wolfsburger Abfallwirtschaft und Straßenreinigung', family: 'waswob', state: 'NI', town: 'Wolfsburg' },
  { id: 'alba-braunschweig', name: 'ALBA Braunschweig', family: 'albabs', state: 'NI', town: 'Braunschweig' },
  { id: 'elw-wiesbaden', name: 'ELW Entsorgungsbetriebe der Landeshauptstadt Wiesbaden', family: 'elw', state: 'HE', town: 'Wiesbaden' },
  { id: 'stadt-fuerth', name: 'Stadt Fürth, Amt für Abfallwirtschaft', family: 'fuerth', state: 'BY', town: 'Fürth' },
  { id: 'stadt-heilbronn', name: 'Heilbronner Entsorgungsbetriebe', family: 'heilbronn', state: 'BW', town: 'Heilbronn' },
  { id: 'enni-moers', name: 'ENNI Stadt & Service Niederrhein', family: 'enni', state: 'NW', town: 'Moers' },
  { id: 'hws-halle', name: 'HWS Hallesche Wasser und Stadtwirtschaft', family: 'hws', state: 'ST', town: 'Halle (Saale)' },
  { id: 'ksj-jena', name: 'KommunalService Jena', family: 'ksj', state: 'TH', town: 'Jena' },
  { id: 'tsk-karlsruhe', name: 'Team Sauberes Karlsruhe', family: 'tsk', state: 'BW', town: 'Karlsruhe' },
  { id: 'sab-magdeburg', name: 'SAB Städtischer Abfallwirtschaftsbetrieb Magdeburg', family: 'sab', state: 'ST', town: 'Magdeburg' },
  // Not potsdam.de's calendar, which asks for the Leerungsrhythmus: the
  // operator's own service knows it per address.
  { id: 'swp-potsdam', name: 'STEP Stadtentsorgung Potsdam', family: 'swp', state: 'BB', town: 'Potsdam' },
  { id: 'osb-osnabrueck', name: 'Osnabrücker ServiceBetrieb', family: 'osb', state: 'NI', town: 'Osnabrück' },
  // Not the Landkreis Göttingen's abfall.io key further up: the city runs its
  // own calendar, which knows each house's bins and so asks for no rhythm.
  { id: 'geb-goettingen', name: 'GEB Göttinger Entsorgungsbetriebe', family: 'geb', state: 'NI', town: 'Göttingen' },
  // The five below print every rhythm of a bin, or take it as a question, and
  // leave the household to name its own (RhythmChoice in abfall/core.ts).
  { id: 'mags-moenchengladbach', name: 'mags Mönchengladbacher Abfall-, Grün- und Straßenbetriebe', family: 'mags', state: 'NW', town: 'Mönchengladbach',
    upload: { why: 'robots', page: 'https://mags.de/online-abfuhrkalender/' } },
  { id: 'stadt-siegen', name: 'Universitätsstadt Siegen', family: 'citko', state: 'NW', town: 'Siegen',
    upload: { why: 'robots', page: 'https://www.siegen.de/leben-in-siegen/buergerservice/abfallentsorgung/abfallkalender' } },
  // The whole Landkreis: one Gemeinde per town, from vendors/zah.ts.
  { id: 'zah-hildesheim', name: 'ZAH Zweckverband Abfallwirtschaft Hildesheim', family: 'zah', state: 'NI' },
  { id: 'stadt-heidelberg', name: 'Stadt Heidelberg, Abfallwirtschaft und Stadtreinigung', family: 'heidelberg', state: 'BW', town: 'Heidelberg' },
  { id: 'beg-bremerhaven', name: 'BEG Bremerhavener Entsorgungsgesellschaft', family: 'beg', state: 'HB', town: 'Bremerhaven' },
  // The search asks the household to confirm it may look the address up; see
  // abfall/vendors/sro.ts for why connecting one's own address is that.
  { id: 'sro-rostock', name: 'Stadtentsorgung Rostock', family: 'sro', state: 'MV', town: 'Rostock',
    upload: { why: 'terms', page: 'https://www.stadtentsorgung-rostock.de/service-center/abfuhrkalender' } },
  // Street entries split by house number, and the Restabfall rhythm is the
  // household's (lid colour); see abfall/vendors/ead.ts.
  { id: 'ead-darmstadt', name: 'EAD Darmstadt', family: 'ead', state: 'HE', town: 'Darmstadt' },
]

// ABIS (flynet) — the calendar GELSENDIENSTE and BEST run on their own sites;
// `host` is the tenant.
const ABIS: AbfallProvider[] = [
  { id: 'abis-gelsenkirchen', name: 'GELSENDIENSTE', family: 'abis', state: 'NW', town: 'Gelsenkirchen', host: 'gelsendienste.abisapp.de' },
  { id: 'abis-bottrop', name: 'BEST Bottrop', family: 'abis', state: 'NW', town: 'Bottrop', host: 'best.abisapp.de' },
]

// hausmuell.info (aturis) — ASR Chemnitz embeds it on asr-chemnitz.de, and
// erfurt.de links SWE's own install. `client` is the software generation.
const HAUSMUELL: AbfallProvider[] = [
  { id: 'hausmuell-asr-chemnitz', name: 'ASR Abfallentsorgung Chemnitz', family: 'hausmuell', state: 'SN', town: 'Chemnitz',
    host: 'asc.hausmuell.info', client: 'proxy' },
  { id: 'hausmuell-swe-erfurt', name: 'SWE Stadtwirtschaft Erfurt', family: 'hausmuell', state: 'TH', town: 'Erfurt',
    host: 'abfallkalender.stadtwerke-erfurt.de', client: 'direct' },
]

// Mein-Abfallkalender (krissel.it) — erlangen.de links it as the city's own.
// `client` is the subdomain.
const MEINABFALL: AbfallProvider[] = [
  { id: 'meinabfall-erlangen', name: 'Stadt Erlangen Abfallwirtschaft', family: 'meinabfall', state: 'BY', town: 'Erlangen', client: 'erlangen' },
  // Neuss lists grey (weekly) and pink (fortnightly) Restmüll side by side; the
  // household picks its lid colour (RhythmChoice in abfall/core.ts).
  { id: 'meinabfall-neuss', name: 'Stadt Neuss Abfallwirtschaft', family: 'meinabfall', state: 'NW', town: 'Neuss', client: 'neuss' },
]

// Müllmax — **only the tenants whose authority embeds it on its own page**
// (checked 2026-09-18): usb-bochum.de, hamm.de/ash, tbr-info.de,
// awm.stadt-muenster.de, mz.kaw-mainz-bingen.de. `client` is the tenant path.
// Münster also publishes the same plan as open data (DL-DE-BY-2.0, one zip a
// year); the wizard was taken because it needs no yearly re-index.
const MUELLMAX: AbfallProvider[] = [
  { id: 'muellmax-usb', name: 'USB Umweltservice Bochum', family: 'muellmax', state: 'NW', town: 'Bochum', client: 'usb' },
  { id: 'muellmax-ash', name: 'ASH Abfallwirtschaft und Stadtreinigung Hamm', family: 'muellmax', state: 'NW', town: 'Hamm', client: 'ash' },
  { id: 'muellmax-tbr', name: 'Technische Betriebe Remscheid', family: 'muellmax', state: 'NW', town: 'Remscheid', client: 'tbr' },
  { id: 'muellmax-awm', name: 'AWM Abfallwirtschaftsbetriebe Münster', family: 'muellmax', state: 'NW', town: 'Münster', client: 'awm' },
  { id: 'muellmax-ebm', name: 'Entsorgungsbetrieb der Stadt Mainz', family: 'muellmax', state: 'RP', town: 'Mainz', client: 'ebm' },
  { id: 'muellmax-his', name: 'Hanau Infrastruktur Service', family: 'muellmax', state: 'HE', town: 'Hanau', client: 'his' },
  { id: 'muellmax-mai', name: 'Stadt Maintal', family: 'muellmax', state: 'HE', town: 'Maintal', client: 'mai' },
]

const AHA: AbfallProvider[] = [
  { id: 'aha-region-hannover', name: 'aha Zweckverband Abfallwirtschaft Region Hannover', family: 'aha', state: 'NI' },
]

// The Athos "WasteManagement" portal, a platform: `host` is the tenant's base
// URL, `town` the area it serves. See abfall/vendors/athos.ts.
const ATHOS: AbfallProvider[] = [
  { id: 'athos-edg-dortmund', name: 'EDG Entsorgung Dortmund', family: 'athos', state: 'NW', town: 'Dortmund',
    host: 'https://kundenportal.edg.de/WasteManagementDortmund' },
  // Bielefeld's production path is `…Test`; the one without it answers 404.
  { id: 'athos-umweltbetrieb-bielefeld', name: 'Umweltbetrieb Bielefeld', family: 'athos', state: 'NW', town: 'Bielefeld',
    host: 'https://anwendungen.bielefeld.de/WasteManagementBielefeldTest' },
  // No `town`: a Landkreis tenant's towns are the Ort options on its own form.
  { id: 'athos-aws-schaumburg', name: 'Abfallwirtschaft Schaumburg', family: 'athos', state: 'NI',
    host: 'https://kundenlogin.aws-shg.de/WasteManagementSchaumburg' },
  { id: 'athos-kaw-hameln-pyrmont', name: 'KAW Landkreis Hameln-Pyrmont', family: 'athos', state: 'NI',
    host: 'https://om.kaw-hameln.de/WasteManagementHameln' },
  { id: 'athos-awb-lk-karlsruhe', name: 'AWB Landkreis Karlsruhe', family: 'athos', state: 'BW',
    host: 'https://waste.awb-landkreis-karlsruhe.de/WasteManagementKarlsruheHaushalteBlank' },
  { id: 'athos-bonnorange-bonn', name: 'bonnorange Bonn', family: 'athos', state: 'NW', town: 'Bonn',
    host: 'https://www5.bonn.de/WasteManagementBonnOrange' },
  { id: 'athos-aws-augsburg', name: 'AWS Abfallwirtschafts- und Stadtreinigungsbetrieb Augsburg', family: 'athos', state: 'BY', town: 'Augsburg',
    host: 'https://abfall.augsburg.de/WasteManagementAugsburg' },
  // Pforzheim and ZKE Saarbrücken make the household name its own Restmüll
  // rhythm. Saarbrücken asks with a checkbox per container and answers none
  // ticked with no list; Pforzheim prints weekly and fortnightly under one
  // "Restmüll", told apart only by key (RM7, RM14). Both are read in full and
  // the household picks (RhythmChoice in abfall/core.ts; athos.ts for both).
  { id: 'athos-pforzheim', name: 'Eigenbetrieb Abfallwirtschaft Pforzheim', family: 'athos', state: 'BW', town: 'Pforzheim',
    host: 'https://onlineservices.abfallwirtschaft-pforzheim.de/WasteManagementPforzheim' },
  { id: 'athos-zke-saarbruecken', name: 'ZKE Zentraler Kommunaler Entsorgungsbetrieb Saarbrücken', family: 'athos', state: 'SL', town: 'Saarbrücken',
    host: 'https://info.zke-sb.de/WasteManagementSaarbruecken' },
  // Found 2026-09-19 on each authority's own calendar page (the Abfuhrkalender
  // Atlas, tool/abfall_authorities): read end to end by candidate probe, robots.txt
  // allowing the adapter's path, no terms reserving the dates.
  // Rhein-Hunsrück's own tenant: its towns were upload-only through jumomind-rhe,
  // and the resolver takes a provider it may read before an upload one.
  // Not listed: Donau-Wald (AWG) and Main-Spessart send an incomplete certificate
  // chain that Deno refuses; Emsland, Nienburg, Lörrach, Waldshut, Garmisch and
  // Bamberg did not resolve a test address yet; Neustadt/Aisch lists a yellow
  // bin and a yellow container side by side.
  { id: 'athos-ludwigsburg', name: 'AVL Landkreis Ludwigsburg', family: 'athos', state: 'BW',
    host: 'https://kundenportal.avl-lb.de/WasteManagementLudwigsburg' },
  { id: 'athos-ravensburgprivat', name: 'Landratsamt Ravensburg, Kreislaufwirtschaft', family: 'athos', state: 'BW',
    host: 'https://athos-onlinedienste.rv.de/WasteManagementRavensburgPrivat' },
  { id: 'athos-suedbrandenburg', name: 'SBAZV Südbrandenburg (Teltow-Fläming, Dahme-Spreewald)', family: 'athos', state: 'BB',
    host: 'https://fahrzeuge.sbazv.de/WasteManagementSuedbrandenburg' },
  { id: 'athos-suedwestsachsen', name: 'ZAS Südwestsachsen (Erzgebirgskreis)', family: 'athos', state: 'SN',
    host: 'https://online-portal.za-sws.de/WasteManagementSuedwestsachsen' },
  { id: 'athos-vogtland', name: 'Landratsamt Vogtlandkreis', family: 'athos', state: 'SN',
    host: 'https://awi.vogtlandkreis.de/WasteManagementVogtland' },
  { id: 'athos-biberach', name: 'AWB Landkreis Biberach', family: 'athos', state: 'BW',
    host: 'https://abfallwirtschaftsbetrieb.biberach.de/WasteManagementBiberach' },
  { id: 'athos-lueneburg', name: 'GfA Lüneburg', family: 'athos', state: 'NI',
    host: 'https://portal.gfa-lueneburg.de:8443/WasteManagementLueneburg' },
  { id: 'athos-schwarzeelster', name: 'AEV Schwarze Elster (Oberspreewald-Lausitz, Elbe-Elster)', family: 'athos', state: 'BB',
    host: 'https://athos.schwarze-elster.com/WasteManagementSchwarzeElster' },
  { id: 'athos-neckarodenwald', name: 'KWiN Neckar-Odenwald', family: 'athos', state: 'BW',
    host: 'https://athos.awn-online.de/WasteManagementNeckarOdenwald' },
  { id: 'athos-straubing', name: 'ZAW Straubing Stadt und Land', family: 'athos', state: 'BY',
    host: 'https://straubing.zaw-sr.de/WasteManagementStraubing' },
  { id: 'athos-verden', name: 'Landkreis Verden', family: 'athos', state: 'NI',
    host: 'https://lkv.landkreis-verden.de/WasteManagementVerden' },
  { id: 'athos-starnberg', name: 'AWISTA Starnberg', family: 'athos', state: 'BY',
    host: 'https://xmlcall.awista-starnberg.de/WasteManagementStarnberg' },
  { id: 'athos-miltenberg', name: 'Landratsamt Miltenberg', family: 'athos', state: 'BY',
    host: 'https://sperrgut.landkreis-miltenberg.de/WasteManagementMiltenberg' },
  { id: 'athos-freudenstadt', name: 'AWB Landkreis Freudenstadt', family: 'athos', state: 'BW',
    host: 'https://awb.kreis-fds.de/WasteManagementFreudenstadt' },
  { id: 'athos-fuerth', name: 'Landratsamt Fürth', family: 'athos', state: 'BY',
    host: 'https://webdienste.landkreis-fuerth.de/WasteManagementFuerth' },
  { id: 'athos-alzeyworms', name: 'AWB Landkreis Alzey-Worms', family: 'athos', state: 'RP',
    host: 'https://abfall.alzey-worms.de/WasteManagementAlzeyworms' },
  { id: 'athos-ahrweiler', name: 'AWB Landkreis Ahrweiler', family: 'athos', state: 'RP',
    host: 'https://extdienste01.koblenz.de/WasteManagementAhrweiler' },
  { id: 'athos-wunsiedel', name: 'KUFi Fichtelgebirge', family: 'athos', state: 'BY',
    host: 'https://app.ku-fichtelgebirge.de/WasteManagementWunsiedel' },
  { id: 'athos-suedwestpfalz', name: 'Kreisverwaltung Südwestpfalz', family: 'athos', state: 'RP',
    host: 'https://abfallwirtschaft.lksuedwestpfalz.de/WasteManagementSuedwestpfalz' },
  { id: 'athos-zweibruecken', name: 'UBZ Zweibrücken', family: 'athos', state: 'RP', town: 'Zweibrücken',
    host: 'https://leerungen.ubzzw.com/WasteManagementZweibruecken' },
  { id: 'athos-wuerzburg', name: 'team orange Landkreis Würzburg', family: 'athos', state: 'BY',
    host: 'https://athosweb.team-orange.info/WasteManagementWuerzburg' },
  { id: 'athos-rheinhunsrueck', name: 'RH Entsorgung (Rhein-Hunsrück)', family: 'athos', state: 'RP',
    host: 'https://aao.rh-entsorgung.de/WasteManagementRheinhunsrueck' },
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
// Every provider now serves one state: the nationwide `jumomind-mymuell`, which
// had none and was the guard's one gap, was replaced on 2026-09-18 by one
// allowlisted row per state (MYMUELL_OFFICIAL).
const PROVIDER_STATES: Record<string, string> = {
  'abfallio-b3b6d7b7': 'BW',
  'abfallio-e00c91eb': 'SN',
  'abfallio-04b7561b': 'BY',
  'awido-awb-altenburg': 'TH',
  'abfallio-040b38fe': 'NI',
  'abfallio-1e959241': 'BB',
  'abfallplus-51be67f3': 'NW',
  'abfallplus-efb75cbd': 'BB',
  'abfallplus-15f69fab': 'BW',
  'abfallplus-80acad6c': 'NW',
  'abfallplus-2085afd9': 'SN',
  'abfallplus-8b016df0': 'NI',
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
  'awido-ebu': 'BW',
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
  'srl-leipzig': 'SN',
  'srdd-dresden': 'SN',
  'aha-region-hannover': 'NI',
  'awg-wuppertal': 'NW',
  'athos-edg-dortmund': 'NW',
  'athos-umweltbetrieb-bielefeld': 'NW',
  'athos-aws-schaumburg': 'NI',
  'athos-kaw-hameln-pyrmont': 'NI',
  'athos-awb-lk-karlsruhe': 'BW',
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
  ...REGIOIT, ...AWIDO_PROVIDERS, ...JUMOMIND_PROVIDERS, ...MYMUELL_OFFICIAL, ...ABFALLIO_PROVIDERS,
  ...CTRACE, ...AWG_BASSUM, ...BSR, ...FES, ...AWM, ...AWB_KOELN, ...SRH, ...AWS_STUTTGART,
  ...AWISTA, ...SRL, ...SRDD, ...AHA, ...AWGW, ...INSERTIT, ...ABKI, ...CITY_OWN, ...ABIS, ...MUELLMAX, ...HAUSMUELL, ...MEINABFALL, ...ATHOS, ...ABFALLPLUS,
].map((p) => (p.state ? p : { ...p, ...(PROVIDER_STATES[p.id] ? { state: PROVIDER_STATES[p.id] } : {}) }))
