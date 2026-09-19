# Spain: free machine-readable calendar sources for a family organizer (public holidays, school holidays, waste collection)

Research date: 2026-09-18. Probes marked "(probed)" were live HTTP requests made from this session on that date.

## Q1. Public holidays (fiestas laborales): national + autonomous + local. Computable or fetched?

### Takeaway
You cannot compute Spanish holidays from a fixed rule set the way German Feiertage are computed. The national list is set each year by a BOE resolution. Each comunidad autónoma chooses which holidays to substitute, and moves holidays that fall on a Sunday to the Monday differently every year. On top of that, every municipality has two local holidays, published in the CCAA/provincial boletines. National and autonomous holidays together are one BOE document a year, which is small enough to hand-curate or fetch. Local holidays are available as free open data for about half the CCAA (Cataluña, Madrid, Euskadi, Andalucía, Castilla y León, Galicia, Baleares, Extremadura, Asturias, partly Aragón/Navarra) and are missing or stale for the rest. OpenHolidays API covers national and regional holidays but contains errors for 2026.

### Cited Findings
**Legal basis and yearly cadence**
- The 2026 national and autonomous list is BOE-A-2025-21667: a Resolution of 17 Oct 2025 by the Dirección General de Trabajo. It covers national, CCAA, Ceuta and Melilla holidays and is published under art. 45 of RD 2001/1983 — [BOE](https://www.boe.es/diario_boe/txt.php?id=BOE-A-2025-21667); [SEPE](https://www.sepe.es/HomeSepe/en/que-es-el-sepe/comunicacion-institucional/noticias/detalle-noticia.html?folder=%2FSEPE%2F2025%2FOctubre%2F&detail=relacion-fiestas-laborales-anio-2026)
- 2026 has 12 national/autonomous holidays plus 2 local ones, 14 days in total — [SEPE / BOE summary](https://www.sepe.es/HomeSepe/en/que-es-el-sepe/comunicacion-institucional/noticias/detalle-noticia.html?folder=%2FSEPE%2F2025%2FOctubre%2F&detail=relacion-fiestas-laborales-anio-2026)
- The national holidays every CCAA keeps in 2026 are 1 Jan, 3 Apr (Viernes Santo), 1 May, 15 Aug, 12 Oct, 8 Dec and 25 Dec. The CCAA-variable ones are 6 Jan, Jueves Santo, Lunes de Pascua, 19 Mar, 24 Jun, 25 Jul, 2 Nov (the day after Todos los Santos, which falls on a Sunday in 2026) and 7 Dec (the Monday after the Constitución). Up to two local days a year are fixed "por tradición" in each municipality (art. 37.2 Estatuto de los Trabajadores) and published in regional/provincial bulletins — [BOE-A-2025-21667](https://www.boe.es/diario_boe/txt.php?id=BOE-A-2025-21667)
- Catalonia's Val d'Aran swaps 26 Dec for 17 Jun, so a sub-CCAA territory exception exists even at the autonomous level — [BOE-A-2025-21667](https://www.boe.es/diario_boe/txt.php?id=BOE-A-2025-21667)
- The BOE resolution is also served as XML at `https://www.boe.es/diario_boe/xml.php?id=BOE-A-2025-21667` (probed: parseable, but the table uses asterisk columns per CCAA, so it is not a clean dataset) — [BOE](https://www.boe.es/diario_boe/txt.php?id=BOE-A-2025-21667)

**Ready-made APIs and aggregators**
- **OpenHolidays API** (openholidaysapi.org) lists "Spain (public holidays and school holidays from 2020)". It uses ISO subdivisions (ES-AN … ES-VC, ES-CE, ES-ML) and province children (e.g. ES-AN-GR), plus Canarias island codes (ES-CN-SC-TE …) — [OpenHolidays](https://www.openholidaysapi.org/en/). Probed: `/PublicHolidays?countryIsoCode=ES&validFrom=2026-01-01&validTo=2026-12-31` returned 54 entries, national plus regional plus some insular/city holidays, with no API key needed. Its data repo is licensed ODbL (probed `openpotato/openholidaysapi.data/LICENSE`).
- **OpenHolidays accuracy problems for 2026** (verified against the BOE XML):
  - It lists "Martes de Carnaval 2026-02-13" for ES-EX. That date is a Friday, and the BOE has no Carnaval entry at all.
  - It lists a second Corpus Christi for ES-CM on 2026-06-19. The BOE has only 4 Jun.
  - It gives "Lunes siguiente a Todos los Santos" (2 Nov) to 5 CCAA. The BOE row shows 9 CCAA marks.
  - Sources: [BOE XML](https://www.boe.es/diario_boe/xml.php?id=BOE-A-2025-21667) vs [OpenHolidays](https://openholidaysapi.org/PublicHolidays?countryIsoCode=ES&languageIsoCode=ES&validFrom=2026-01-01&validTo=2026-12-31)
- OpenHolidays has no municipal/local holidays for Spain. The GitHub project ChemieuroDEV/festivos-locales exists precisely because "no public API covers this level". It publishes static JSON for 8,025 Spanish municipalities at `data/ES/<YEAR>/<postal-prefix>.json`, keyed by INE code, with postal codes and the OpenHolidays subdivision code. Sources are the "API de festivos de Chemieuro por código INE" plus regional bulletins. A GitHub Action re-runs it monthly from September to January, plus April and July. Licence: "fuentes oficiales y de Wikipedia, cada una con su licencia", so there is no single clear licence — [GitHub](https://github.com/ChemieuroDEV/festivos-locales)
- Other GitHub options:
  - jmendoza-es/calendarios-laborales-espana scrapes micalendariolaboral.com and is CC BY 4.0. Its upstream is a commercial site, so provenance is weak.
  - ApasPowre/calendario-laboral-espana scrapes official sources for more than 2,500 municipalities.
  - davidbuenov/dbv-dias-festivos wraps the Python `holidays` library per province.
  - Sources: [jmendoza](https://github.com/jmendoza-es/calendarios-laborales-espana); [ApasPowre](https://github.com/ApasPowre/calendario-laboral-espana); [davidbuenov](https://github.com/davidbuenov/dbv-dias-festivos)

**Per-CCAA open data for local holidays** (census via the datos.gob.es API, `apidata/catalog/dataset/title/...`, probed)
- **Cataluña (A09):** Socrata dataset `b4eh-r8up` "Calendari de festes locals a Catalunya". Endpoint: `https://analisi.transparenciacatalunya.cat/resource/b4eh-r8up.json`. Columns: `any_calendari, data, ajuntament_o_nucli_municipal, codi_municipal, codi_municipi_ine, pedania, festiu, codiidescat`. It is keyed by INE code and also has sub-municipal nuclei (pedania). Probed row counts: 2026 = 2,794, 2025 = 15,129, 2024 = 7,516; the 2026 figure looks partial or differently structured. There is also a separate "Calendari laboral de Catalunya" (`yf2b-mjr6`) and an ICS version — [Catalonia portal](https://analisi.transparenciacatalunya.cat/Treball/Calendari-de-festes-locals-a-Catalunya/b4eh-r8up); [datos.gob.es ICS](https://datos.gob.es/en/catalogo/a09002970-calendario-laboral-de-catalunya-fichero-ics)
- **Comunidad de Madrid (A13):** "Festivos regionales y locales año en curso", CSV and JSON on datos.comunidad.madrid (`festivos_locales.csv`, `festivos_regionales.json`). Probed columns: `año;municipio_codigo;municipio_nombre;entidad_codigo;entidad_nombre;fecha_festivo`. The code is the 3-digit INE municipality code within province 28. It holds 338 rows for 2026 and is Latin-1 encoded. A "histórico" dataset also exists — [datos.gob.es](https://datos.gob.es/es/catalogo/a13002908-festivos-regionales-y-locales-ano-en-curso1)
- **Euskadi (A16):** "Calendario laboral de Euskadi para el 2026" in XML, JSON, JSONP, CSV, ICS and XLSX, plus a REST API at `https://opendata.euskadi.eus/api-work-calendar/?api=work-calendar`. It covers the CAE, the historical territories and the municipalities, with a `municipalitycode` (EUSTAT code) and lat/lon. Yearly datasets run from 2010 to 2026. Probed JSON fields: `date, descripcionEs, descriptionEu, municipalityEs, territory, municipalitycode, latwgs84, lonwgs84` — [Open Data Euskadi](https://opendata.euskadi.eus/catalogo/-/calendario-laboral-de-euskadi-para-el-2026/); [datos.gob.es](https://datos.gob.es/en/catalogo/a16003011-calendario-laboral-de-euskadi-para-el-2026)
- **Andalucía (A01):** "Calendario de días festivos en la Comunidad Autónoma de Andalucía", an API at `https://datos.juntadeandalucia.es/api/v0/work-calendar/all?format=json|csv|ics` with an OpenAPI spec at `/openapi.json`. Probed result: 1.4 MB covering 2023–2027, with 12 LABORAL (regional) rows a year and 1,548 LOCAL rows for 2026 across 775 municipalities. Keyed by **municipality name + province name, not INE code**. The 2027 regional rows are already present. It needed a browser User-Agent; the first plain request returned an HTML error — [datos.gob.es](https://datos.gob.es/es/catalogo/a01002820-calendario-de-dias-festivos-en-la-comunidad-autonoma-de-andalucia)
- **Galicia (A12):** "Calendario laboral 2026" (Xunta) in CSV, ICS, ODS and XLSX, including all local holidays, licensed CC BY-SA 4.0, last updated 15 Jan 2026. A "Calendario laboral 2027" dataset already exists (modified 2 Jul 2026) — [datos.gob.es 2026](https://datos.gob.es/en/catalogo/a12002994-calendario-laboral-2026); [2027 via API](https://abertos.xunta.gal/catalogo/economia-empresa-emprego/-/dataset/0699/calendario-laboral-2027/001/descarga-directa-ficheiro.csv)
- **Castilla y León (A07):** "Fiestas locales: Calendario de Fiestas de Carácter Local", three CSVs at datosabiertos.jcyl.es — [datos.gob.es](https://datos.gob.es/en/catalogo/a07002862-fiestas-locales-calendario-de-fiestas-de-caracter-local1)
- **Illes Balears (A04):** "Calendario Laboral General y Local Illes Balears 2026", a CSV (`calendari-laboral-2026.csv`) with the columns Illa, Àmbit, Municipi, Localitat, Data, Nom festa. Dates are free text in Catalan ("1 de gener"), so it needs parsing. Yearly datasets run from 2020 to 2026 — [datos.gob.es API](https://datos.gob.es/apidata/catalog/dataset/a04003003-calendario-laboral-general-y-local-illes-balears-2026.json)
- **Extremadura (A11):** "Festivos locales en Extremadura", published only as a **2025** XLSX (`FestivosLocales2025.xlsx`); the catalogue entry is dated Feb 2025 — [datos.gob.es API](https://datos.gob.es/apidata/catalog/dataset/a11002926-festivos-locales-en-extremadura.json)
- **Asturias (A03):** "Fiestas locales y autonómicas del Principado de Asturias", modified Dec 2025 — [datos.gob.es title search](https://datos.gob.es/apidata/catalog/dataset/title/fiestas%20locales.json)
- **Aragón (A02):** "Calendario de festivos en comunidad de Aragón 2026" (May 2026). Whether it includes local holidays was not verified — same API search.
- **Navarra (A15):** "Calendario de días festivos de la Comunidad Foral de Navarra" (Jun 2026). Local scope not verified — same API search.
- **La Rioja (A17):** local-holiday datasets exist only for 2018–2020 (stale) — same API search.
- **Castilla-La Mancha (A08):** calendario laboral datasets only up to 2025 — same API search.
- **Stale provincial and municipal entries:** "Fiestas locales oficiales en la provincia de Alicante" (Oct 2022, Diputación) and a few ayuntamientos (Santander, Terrassa, Torrent) — same API search.
- **No holiday dataset found** in the datos.gob.es title search for Canarias, Cantabria, Comunitat Valenciana (except the stale Alicante file), Región de Murcia, Ceuta or Melilla — same API search.
- The datos.gob.es API's `license` field came back `None` for every dataset probed, so the licence has to be read off each regional portal. Galicia's is CC BY-SA 4.0 (see above).

### Inferences
- **Feasible architecture:**
  - Compute the fixed-date and Easter-relative *candidates* in-app.
  - Take the per-CCAA *selection* for each year from a small hand-curated table built from the BOE resolution. That is one table per year, published in October, about 20 rows × 19 regions.
  - Treat local holidays as a fetched per-CCAA feed, the same way Aporah treats Ferien (one `public_feeds` row per municipality or per CCAA).
  - This mirrors why `german_holidays.dart` works: the law fixes the rule in Germany, whereas Spain fixes only the list, and only for one year at a time.
- Relying on OpenHolidays for regional holidays without cross-checking the BOE would ship wrong days: two to three errors were found in 2026 alone.
- For local holidays, the practical free options are:
  - (a) Per-CCAA adapters for the ~9–10 regions with usable open data, in the style of Aporah's Abfall vendor registry. Formats range from Socrata JSON to Latin-1 CSV to free-text dates.
  - (b) The ChemieuroDEV aggregate. It covers all 8,025 municipalities but has mixed licensing (partly Wikipedia CC BY-SA) and relies on an unexplained third-party "Chemieuro API", so it is risky as a commercial dependency.
  - (c) Leaving local holidays out in regions without data. That is analogous to Aporah showing no holidays in PT/ES today.
- Keys differ by source: INE 5-digit code (Cataluña, ChemieuroDEV), INE 3-digit within province (Madrid), EUSTAT code (Euskadi), name + province (Andalucía, Baleares). Normalising on the INE municipality code is the sensible canonical key.

### Gaps
- The licence terms of each regional portal were not individually verified. Several Spanish regional portals use CC BY 4.0 or the datos.gob.es "aviso legal" that permits commercial reuse with attribution, but that is from memory, not verified here.
- BOE reuse terms were not fetched. BOE content is generally reusable under its aviso legal, but this is unverified.
- The "API de festivos de Chemieuro" (terms, rate limits) could not be identified.
- Whether the Aragón and Navarra datasets include municipal holidays is unknown.
- The Catalan 2026 row count (2,794 vs 15,129 in 2025) is unexplained; the 2026 data may be incomplete.
- The Galicia 2026 labour CSV was not inspected for an INE code column. The 2027 CSV download returned empty to curl; the ICS worked with `-L` and a browser UA.

## Q2. School holidays (calendario escolar): coverage across the 17 CCAA + Ceuta/Melilla

### Takeaway
The school calendar is set per CCAA by an order of the consejería de educación. Andalucía sets part of it per province, and schools and municipalities add local non-teaching days (días no lectivos / de libre disposición). Official machine-readable feeds exist only for **Galicia (ICS/CSV, 2026-27 already published)**, **Andalucía (ICS export via Séneca/Secretaría Virtual, by centre)**, **Castilla y León** and **Castilla-La Mancha (stale)**. For everything else, OpenHolidays is the only free structured source across all regions. It covered all 19 regions for 2025-26, but **has no 2026-27 Spanish school data at all as of 18 Sep 2026**, even though the school year has already started.

### Cited Findings
- **OpenHolidays school holidays, Spain** (probed `/SchoolHolidays?countryIsoCode=ES`):
  - 2025-09-01..2026-08-31 returned 167 entries covering all 17 CCAA + Ceuta (ES-CE) + Melilla (ES-ML).
  - Andalucía is split into its 8 provinces (ES-AN-AL … ES-AN-SE) and Aragón into 3 (ES-AR-HU/TE/ZG).
  - Entries are ranges (Navidad, Pascua, summer) plus single "Día no lectivo" days and "EndOfLessons".
  - 2026-09-01..2027-08-31 returned **0 entries**. Nothing after 2026-06-19 exists for ES-MD, so summer 2026 and the whole 2026-27 year are missing — [OpenHolidays](https://www.openholidaysapi.org/en/)
- **Galicia:** the "Calendario escolar 2026-2027" dataset (Xunta, published 16 Jun 2026) comes as ODS, CSV, XLSX and ICS. Probed ICS: `X-WR-CALNAME:Calendario escolar 2026-2027`, events like "Curso académico" and "Actividades lectivas…", with teaching days starting 2026-09-09. There is a yearly series from 2012-13 onward. Download URL pattern: `https://abertos.xunta.gal/catalogo/ensino-formacion/-/dataset/0698/calendario-escolar-2026-2027/004/descarga-directa-ficheiro.calendario`. A new dataset id appears each year, so this is not a stable feed URL — [Portal Abertos](https://abertos.xunta.gal/es/catalogo/ensino-formacion/-/dataset/0698/calendario-escolar-2026-2027); [datos.gob.es](https://datos.gob.es/es/catalogo/a12002994-calendario-escolar-2026-2027)
- **Andalucía:** "Calendario escolar" dataset from the Consejería de Educación, annual. It holds the current year's school calendar for Andalusian centres, "including regional, provincial, local and other holidays", and is exported as ICS after running a query in the Secretaría Virtual (`https://www.juntadeandalucia.es/educacion/secretariavirtual/consulta/calendario-escolar/`). Licence: "consult the Consejería". The datos.gob.es entry was modified 11 Aug 2026 — [Junta de Andalucía open data](https://www.juntadeandalucia.es/datosabiertos/portal/dataset/calendario-escolar-del-curso-actual)
- **Castilla-La Mancha:** a "Calendario escolar de la Comunidad Autónoma de Castilla-La Mancha" dataset exists on datosabiertos.castillalamancha.es, last modified Feb 2025 (course 2024/25), so it is stale — [Datos Abiertos CLM](https://datosabiertos.castillalamancha.es/dataset/calendario-escolar-de-la-comunidad-aut%C3%B3noma-de-castilla-la-mancha)
- **Castilla y León:** a "Calendario escolar" dataset (A07002862) was modified 6 Jul 2026. Its distributions could not be retrieved through the datos.gob.es API — [datos.gob.es title search](https://datos.gob.es/apidata/catalog/dataset/title/calendario%20escolar.json)
- **Aragón:** datasets exist only for courses 2019-20 and 2020-21, so it is stale — same source.
- **Cataluña:** Ordre EDF/66/2026 of 22 Apr fixes the calendars for 2026-27, 2027-28 and 2028-29. The course runs 8 Sep 2026 – 21 Jun 2027. The published artefact is a PDF (`web.gencat.cat/.../calendari-escolar.pdf`), and no open dataset was found — [Jovecat](https://jovecat.gencat.cat/ca/actualitat/noticies/detalls/Noticia/Calendari-escolar-dels-cursos-2026-2027-2027-2028-i-2028-2029-centres-no-universitaris); [Gencat PDF](https://web.gencat.cat/content/dam/webgencat/documents/ciutadania/serveis/educacio-i-formaci%C3%B3/calendari-escolar.pdf)
- **Comunitat Valenciana:** 2026-27 is published as a sede electrónica procedure page (G25685), with no dataset found — [GVA](https://sede.gva.es/en/detall-tramit?id_proc=G25685)
- **Euskadi:** no school-calendar dataset was found on Open Data Euskadi, though its catalogue has many calendar sets — [Open Data Euskadi catalogue](https://opendata.euskadi.eus/catalogo-datos/)
- By law the school year must have at least 175 teaching days for compulsory education (LOE 2/2006). Commercial aggregators such as calendariosnacionales.com publish per-community tables, but they are not open data — [calendariosnacionales](https://calendariosnacionales.com/es/2026/escolar/)

### Inferences
- To reproduce Aporah's "one shared feed per region", the region key should be the CCAA, refined to the **province** for Andalucía and Aragón (matching OpenHolidays' subdivisions).
- Local non-teaching days (días de libre disposición, local fiestas) vary per municipality or per school, so a per-CCAA feed will be slightly incomplete. The honest framing is "regional school holidays", like Ferien.
- Realistic free sourcing today:
  - OpenHolidays as the primary source. It is ODbL, and its Spanish data is presumably loaded later each year; the lag is visible now.
  - Official ICS for Galicia and Andalucía.
  - Hand-curated entry of the other ~15 CCAA from their education orders: about 6–10 date ranges per region per year, published in spring. Catalonia already publishes three years ahead.
  - Hand-curation is probably required for a reliable product at the start of each school year.
- ODbL applies share-alike to *databases* derived from it, not to an app displaying the data. Attribution is required. This is an inference from the ODbL text; get legal review.

### Gaps
- Machine-readable status for Asturias, Baleares, Canarias, Cantabria, Extremadura, Madrid, Murcia, Navarra, La Rioja, Ceuta and Melilla school calendars was not individually checked. None surfaced in the datos.gob.es title search.
- OpenHolidays' data-loading timeline for Spain and its API rate limits are unknown; neither is documented on the fetched page.
- The format of the Castilla y León school dataset is unknown.

## Q3. Waste collection in Spain: does a per-address schedule exist? Any open data?

### Takeaway
In most Spanish cities, household waste goes into shared street containers (contenedores) that are emptied daily or near-daily. Residents have no personal pickup date, only local deposit-hour rules. That makes the German "bins at 19:00 the evening before" feature largely meaningless in big cities. A schedule matters in two places:
- **Puerta a puerta (door-to-door) municipalities.** About 368 in Catalonia (portaaporta.cat), plus Gipuzkoa's "atez ate" towns and parts of Navarra and Barcelona (Sarrià). Each fraction is put out on a fixed weekday and hour, but only as PDFs or municipal web pages, with no API found.
- **Bulky-item collection (muebles/enseres, mobles i trastos vells).** Madrid and Barcelona schedule it by street/zone, and Madrid publishes the zones as geodata.

### Cited Findings
- Ley 7/2022 made separate biowaste collection mandatory for all local entities from 31 Dec 2023. Collection may be "mediante contenedores, puerta a puerta, sistemas de entrega y recepción…", so the model is the municipality's choice — [BOE Ley 7/2022](https://www.boe.es/buscar/act.php?id=BOE-A-2022-5809); [MITECO biorresiduos](https://www.miteco.gob.es/es/calidad-y-evaluacion-ambiental/temas/prevencion-y-gestion-residuos/flujos/biorresiduos/biorresiduos-como-se-recogen.html)
- **Puerta a puerta in Catalonia:** 368 municipalities have fully or partially implemented door-to-door selective collection. The first were Tiana, Tona, Riudecanyes and Mancomunitat la Plana in 2000, and the municipal association was founded in 2002 — [portaaporta.cat](https://portaaporta.cat/es/); [municipalities list](https://www.portaaporta.cat/es/municipis.php)
- **Barcelona:** runs door-to-door in Sarrià (among its five-fraction system). The page returned HTTP 418 to the fetcher, so the weekday schedule was not captured — [Barcelona PaP](https://ajuntament.barcelona.cat/neteja-i-residus/en/household-waste-collection/five-fractions-domestic-waste-collection-system/door-door)
- **Gipuzkoa "atez ate":** residents must deposit each fraction on a set day and time at an identified point per household. Five fractions. It started in Usurbil in March 2009 and has spread to Oiartzun, Anoeta, Zizurkil and others. Schedules live on municipal/mancomunidad pages and PDFs — [Euskadi.eus](https://www.euskadi.eus/gobierno-vasco//contenidos/noticia/2013/es_130319/index.shtml); [Usurbil](https://www.usurbil.eus/es/recogida-de-residuos-puerta-a-puerta); [Tolosaldea](https://tolosaldekomankomunitatea.eus/es/noticias/aldaketak-atez-ateko-bilketan-anoeta-eta-zizurkilen/)
- **Barcelona bulky items:** "mobles i trastos vells" are collected on a fixed weekday per street, put out between 20:00 and 22:00. Residents look it up by address at barcelona.cat/recollidamobles. No Open Data BCN dataset for it was found — [Barcelona Eixample](https://ajuntament.barcelona.cat/eixample/ca/noticia/mobles-i-trastos-vells-el-dia-que-toca-3-1344959); [Info Barcelona](https://www.barcelona.cat/infobarcelona/ca/tema/medi-ambient-i-sostenibilitat/sabeu-quin-dia-es-recullen-els-mobles-i-trastos-vells-al-vostre-carrer_1343837.html)
- **Madrid bulky items:** the geoportal publishes a "Servicio de recogida programada de muebles, electrodomésticos y enseres. Zonas y calendario anual" dataset:
  - Formats: SHP download plus WMS and ESRI REST.
  - The service runs once a month per zone, and the dataset has existed since 2024.
  - Licence: Madrid's general conditions for public data.
  - Items go out between 21:00 and 23:00 on the zone's day.
  - On-request pickup is also available via 010 or Avisos Madrid, up to 3 m³ and 6 items.
  - Sources: [Geoportal Madrid](https://geoportal.madrid.es/IDEAM_WBGEOPORTAL/dataset.iam?id=e7207a09-7ead-11ec-b24a-60634c31c0aa); [madrid.es programada](https://www.madrid.es/portales/munimadrid/es/Inicio/Medio-ambiente/Recogida-de-residuos/Recogida-programada-por-distrito-de-muebles-electrodomesticos-y-enseres/?vgnextfmt=default&vgnextoid=db4e4c7788abd710VgnVCM2000001f4a900aRCRD&vgnextchannel=f81379ed268fe410VgnVCM1000000b205a0aRCRD)
- **Madrid container data:** open datasets give the geolocated addresses of paper, glass, packaging, organic and resto containers, and the clothing containers dataset includes collection schedules. These are about locating containers, not household schedules — [datos.madrid.es containers](https://datos.madrid.es/dataset/300276-0-contenedor-papel-carton-todos); [ropa](https://datos.madrid.es/dataset/204410-0-contenedores-ropa); [Madrid residuos data](https://www.madrid.es/go/DatosAbiertos/Residuos)
- A national container-geolocation dataset exists on datos.gob.es ("Contenedores y residuos", a Diputación publisher) — [datos.gob.es](https://datos.gob.es/en/catalogo/l02000047-contenedores-y-residuos)

### Inferences
- The German Abfall feature ("which bin goes out tomorrow") has no equivalent for most Spanish urban households.
- The meaningful Spanish equivalents are:
  - (1) The puerta-a-puerta weekly fraction calendar for several hundred smaller towns, mainly in Catalonia, Gipuzkoa and Navarra. It is a *recurring weekly rule*, not a date feed, so it could be modelled like Aporah's Tracker rhythm or entered by the user.
  - (2) Monthly or weekly bulky-item day by zone (Madrid SHP; Barcelona address lookup only).
- There is no open API for PaP calendars. Supporting them would mean per-town hand entry or PDF scraping, a poor cost/benefit for a first Spanish launch.
- Recommendation for inference: ship Spain without Abfall, or with a user-entered weekly rule, and optionally add Madrid bulky-item zones as the single geodata-backed adapter.

### Gaps
- No verification of Valencia (València ciutat), Bilbao, Sevilla or Zaragoza open data for collection schedules.
- The Barcelona Sarrià PaP weekday schedule was not retrieved (the fetch was blocked).
- The Madrid SHP field schema was not inspected; the fetch page only says it maps zones to an annual calendar.
- Container deposit-hour rules in the Madrid/Barcelona ordinances were not verified.

## Q4. Which regional fields should the onboarding address step capture?

### Takeaway
Capture the **municipality as an INE code** (5 digits: 2-digit province + 3-digit municipality). The province and CCAA derive from it deterministically, and it is the join key most holiday datasets use. The postal code is only a convenience input: it maps to several municipalities and cannot stand alone.

### Cited Findings
- Cataluña's local-holiday data carries `codi_municipi_ine` (5 digits) plus a sub-municipal `pedania` and an Idescat code — [Socrata b4eh-r8up](https://analisi.transparenciacatalunya.cat/resource/b4eh-r8up.json) (probed)
- Madrid uses `municipio_codigo` (3-digit INE within province 28) and `entidad_codigo` — [datos.comunidad.madrid](https://datos.gob.es/es/catalogo/a13002908-festivos-regionales-y-locales-ano-en-curso1) (probed)
- Euskadi uses a EUSTAT `municipalitycode` plus coordinates — [Open Data Euskadi](https://opendata.euskadi.eus/catalogo/-/calendario-laboral-de-euskadi-para-el-2026/) (probed)
- Andalucía uses the municipality *name* + province name (probed); Baleares uses island + municipality + locality names (probed) — [Andalucía API](https://datos.juntadeandalucia.es/api/v0/work-calendar/all?format=json); [Baleares CSV](https://intranet.caib.es/opendatacataleg/dataset/e89fb44b-67f3-4e29-affc-2df135b719e5/resource/edf08154-bbc0-4259-a254-3b0185411354/download/calendari-laboral-2026.csv)
- ChemieuroDEV groups files by postal-code prefix but keys municipalities by INE and stores their postal codes and OpenHolidays subdivision. This shows the postal-code → INE → subdivision chain is workable — [GitHub](https://github.com/ChemieuroDEV/festivos-locales)
- OpenHolidays school holidays need province granularity for Andalucía and Aragón (ES-AN-xx, ES-AR-xx). Canarias public holidays go down to the island (ES-CN-SC-TE etc.) — [OpenHolidays](https://www.openholidaysapi.org/en/) (probed)

### Inferences
- **Store:** INE municipio code (canonical); derived provincia and CCAA (ISO 3166-2, ES-XX); optional código postal (the user's entry point); and, for Canarias, the island, which is derivable from the province + municipality.
- **Minimum UX:** postal code → pick the municipality from the INE candidates → derive everything else.
- Sub-municipal entities (pedanías, entidades locales menores: Catalonia `pedania`, Madrid `entidad_codigo`, Baleares "Localitat") can have their own local holidays. Allow an optional locality below the municipality.
- A street address is only needed if a waste feature is built, and only for Madrid bulky-item zones or door-to-door towns.

### Gaps
- No authoritative free postal-code-to-INE mapping was verified this session. INE publishes a municipality list; CP → municipio mappings are commonly derived from Correos/CartoCiudad data, whose licensing was not checked.
