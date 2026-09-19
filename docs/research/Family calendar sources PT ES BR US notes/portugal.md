# Portugal: free, machine-readable calendar sources (holidays, school holidays, waste collection)

Researched 2026-09-18. About 22 tool calls. Verified facts carry a URL; anything without one is in Inferences or Gaps.

## Public holidays (national, regional, municipal): can the app compute them, or must it fetch them?

### Takeaway
The app can compute national and regional feriados from the law, just as it does for Germany. That covers 13 mandatory national days, optional Carnival, 3 Madeira days and 1 Azores day. Municipal holidays (one per concelho, 308 in total) are set locally, and no official machine-readable dataset of them turned up. The practical route is a static table of about 308 rows maintained in-house, possibly seeded from a community JSON repo or aggregator sites whose licensing is unclear. A few of those rows are movable (Easter-relative).

### Cited Findings
- **Legal basis:** Código do Trabalho art. 234 lists the mandatory holidays: 1 Jan, Good Friday, Easter Sunday, 25 Apr, 1 May, Corpo de Deus, 10 Jun, 15 Aug, 5 Oct, 1 Nov, 1 Dec, 8 Dec and 25 Dec. — [DR, CT art. 234 (consolidated)](https://diariodarepublica.pt/dr/legislacao-consolidada/lei/2009-34546475-73982045); [informador.pt copy](https://informador.pt/legislacao/lexit/codigos/direito-laboral/codigo-do-trabalho/livro-i-parte-geral-2/titulo-ii-contrato-de-trabalho/capitulo-ii-prestacao-do-trabalho/seccao-ii-duracao-e-organizacao-do-tempo-de-trabalho/subseccao-ix-feriados/artigo-234-o-feriados-obrigatorios/)
- The same article lets Good Friday be observed on another day of local significance in the Easter period. — [search summary of informador.pt / CT art. 234](https://informador.pt/legislacao/lexit/codigos/direito-laboral/codigo-do-trabalho/livro-i-parte-geral-2/titulo-ii-contrato-de-trabalho/capitulo-ii-prestacao-do-trabalho/seccao-ii-duracao-e-organizacao-do-tempo-de-trabalho/subseccao-ix-feriados/artigo-234-o-feriados-obrigatorios/)
- **Movable rules:** Good Friday and Easter Sunday; Corpus Christi is 60 days after Easter; Carnival is optional, 47 days before Easter. — [Wikipedia: Public holidays in Portugal](https://en.wikipedia.org/wiki/Public_holidays_in_Portugal)
- **2016 restoration:** four holidays were revoked from 2013 to 2015 (5 Oct, 1 Dec, Corpus Christi, 1 Nov) and restored in January 2016. — [Wikipedia](https://en.wikipedia.org/wiki/Public_holidays_in_Portugal). Wikipedia names the restoring government but not the law number. The law was not verified against DRE here; see Gaps.
- **Madeira regional:** Autonomy Day (2 Apr), Dia da Região (1 Jul) and 1ª Oitava (26 Dec). — [Wikipedia](https://en.wikipedia.org/wiki/Public_holidays_in_Portugal); 1 Jul and 26 Dec also at [madeira-web.com](https://www.madeira-web.com/pt/o-que-se-passa/feriados.html), [Rui Gonçalves Silva](https://www.ruigoncalvessilva.com/trabalhos/feriados-regionais-regi%C3%A3o-aut%C3%B3noma-da-madeira)
- **Azores regional:** Dia da Região Autónoma dos Açores falls on Whit Monday (Segunda-feira do Espírito Santo, Easter + 50). — [Wikipedia](https://en.wikipedia.org/wiki/Public_holidays_in_Portugal)
- **Municipal:** each of the 308 municipalities has one municipal holiday, set by the Câmara Municipal. — [Santander, list by municipality](https://www.santander.pt/salto/feriados-municipais-portugal-2026); [Wikipedia](https://en.wikipedia.org/wiki/Public_holidays_in_Portugal)
- **No official dataset:** a dados.gov.pt search for "feriados" returns no holiday dataset, only transport NeTEx feeds and an ACSS dataset that mention feriados in passing. — [dados.gov.pt search](https://dados.gov.pt/pt/datasets/?q=feriados)
- A DGAEP "Feriados" page appears in search results, but it returned HTTP 404 when fetched on 2026-09-18. — [dgaep.gov.pt (404)](https://www.dgaep.gov.pt/stap/infoPage.cfm?objid=9a36961c-71bc-40de-8ee0-5cdeb2dea832&KeepThis=true)
- **Secondary compilations (HTML, not open data, terms unknown):** [icalendario.pt](https://icalendario.pt/feriados/municipais/) (2026–2028), [dirportugal.com](https://dirportugal.com/feriados-municipais/), [cidadesportuguesas.com](https://cidadesportuguesas.com/lista-de-feriados-municipais-portugueses/), [Santander](https://www.santander.pt/salto/feriados-municipais-portugal-2026), and an association PDF at [aspl.pt](https://www.aspl.pt/images/aspl_pdfs/Feriados%20Municipais%20Nacionais.pdf).
- **Community JSON:** GitHub `ChemieuroDEV/festivos-locales` covers ES, PT and IT, with PT stored as `data/PT/<YEAR>/<POSTAL-PREFIX>.json`. It claims all 308 concelhos, keys them by postal-code prefix, and ships movable dates already resolved. A GitHub Action refreshes it monthly from Sept to Jan, plus Apr and Jul. It gives no explicit licence for the PT data and names its source only as "feriado municipal oficial". — [GitHub festivos-locales](https://github.com/ChemieuroDEV/festivos-locales)
- **SAPO Holiday API:** listed as covering national, regional and municipal holidays for 1582–2299, at `services.sapo.pt/Metadata/Contract/Holiday?culture=PT`. — [devpt-org/public-data-portugal](https://github.com/devpt-org/public-data-portugal). Liveness and terms were not checked.

### Inferences
- National and regional holidays belong in an in-app rules file, the equivalent of `german_holidays.dart`. That is 10 fixed dates plus Good Friday, Easter and Corpus Christi, with Carnival flagged as optional/tolerância (not a legal holiday, but schools close). Regional days need only the region (Continente / Açores / Madeira).
- Municipal holidays need a concelho → rule table. Most are fixed dates. Some concelhos use movable ones: my prior knowledge, unverified here, is Quinta-feira de Ascensão ("Dia da Espiga", Easter + 39) in several concelhos and Easter Monday in some. Store `{concelho_code, fixed MM-DD | easter_offset}`, so the rule can be computed rather than refetched yearly. Changes are rare but possible (a Câmara decision).
- The festivos-locales repo is useful to cross-check or seed a hand-maintained table. Given the missing licence, copy the facts (dates are not copyrightable per se) instead of depending on the repo at runtime.

### Gaps
- No official, machine-readable register of all 308 municipal holidays was found: not on dados.gov.pt, and the DGAEP page is 404. It is unclear whether any government body keeps a consolidated list.
- The law that restored the four holidays in 2016 (commonly cited as Lei n.º 8/2016, de 1 de abril) was not verified against DRE here.
- Whether the SAPO Holiday API is still online in 2026, and on what terms, was not checked.
- The licence of the festivos-locales PT data and its upstream source could not be established.

## School holidays (calendário escolar): national? machine-readable? regional differences?

### Takeaway
Mainland public schools follow one national calendar, set by Despacho of the Ministry of Education (MECI). The current Despacho n.º 8368/2024, amended by 9989/2025, fixes four school years at once: 2024/25 to 2027/28. The Azores (Portaria n.º 937/2025, only referential, so each school sets its own dates) and Madeira (yearly binding Despacho in JORAM) differ. No ICS, JSON or open-data version exists. The source is a PDF in the Diário da República, so the app must hand-encode about 4 date ranges a year for 3 regions. That is closer to "computed from law" than to Germany's per-Bundesland Ferien feed.

### Cited Findings
- **Mainland:** Despacho n.º 8368/2024 (25 Jul 2024, DR 2.ª série n.º 143) sets the calendar for 2024/25 to 2027/28. It covers public pre-school, basic and secondary schools on the mainland, plus private special-education establishments. — [DR Despacho 8368/2024](https://diariodarepublica.pt/dr/detalhe/despacho/8368-2024-873447631); [PDF](https://files.diariodarepublica.pt/2s/2024/07/143000000/0016600171.pdf); [DGAE news: 2024/2025 a 2027/2028](https://www.dgae.medu.pt/noticias/calendario-escolar-2024-2025-a-2027-2028)
- **Amendment:** Despacho n.º 9989/2025 (21 Aug 2025) changed the dates of the first interruption for 2025/26 only. The multi-year calendar can therefore be amended mid-cycle. — [DR Despacho 9989/2025](https://diariodarepublica.pt/dr/detalhe/despacho/9989-2025-932720956)
- **2026/27 mainland dates:**
  - Start: between 11 and 15 Sep 2026 (pre-school, 1st–3rd cycle).
  - Interruptions: Christmas 16–31 Dec 2026, Carnival 8–10 Feb 2027, Easter 22 Mar–2 Apr 2027.
  - End: 4 Jun (9th, 11th, 12th grade), 11 Jun (5th–8th, 10th) or 30 Jun 2027 (pre-school, 1st cycle).
  - Sources: [CGD Saldo Positivo](https://www.cgd.pt/Site/Saldo-Positivo/formacao-e-tecnologia/Pages/calendario-escolar.aspx); [casadoprofessor.pt](https://casadoprofessor.pt/calendario-escolar-2026-2027-datas-chave-e-interrupcoes-letivas/)
  - The secondary scientific-humanistic start of 21 Sep 2026 appears in the search summary only.
- Schools may choose a trimester or semester organisation. This does not change the interruptions. — [CGD](https://www.cgd.pt/Site/Saldo-Positivo/formacao-e-tecnologia/Pages/calendario-escolar.aspx)
- **Azores:** Portaria n.º 937/2025 (8 Jul 2025) approves the calendars for 2025/26 to 2027/28, and its tables are referential only: each school sets its own dates.
  - 2026/27: classes start 10–15 Sep 2026; Christmas break 21–31 Dec 2026.
  - Portaria n.º 909/2026 (25 Aug 2026) pushed the 3rd cycle and secondary start back by five working days.
  - Sources: [Portal da Educação Açores](https://edu.azores.gov.pt/seccoes/calendario-escolar-2025-2026-a-2027-2028/); [ESMA school notice](https://esmarriaga.edu.azores.gov.pt/alteracao-da-data-de-inicio-do-ano-letivo-2026-2027/); [calendarioescolar.pt Açores](https://calendarioescolar.pt/calendario-escolar-acores/)
  - Some of these details come from search summaries of those pages.
- **Madeira:** the 2026/27 calendar is Despacho n.º 198/2026 (5 May 2026, JORAM) and binds all institutions in the region. Pre-school runs 7 Sep 2026 to 14 Jul 2027. — [calendarioescolar.pt Madeira](https://calendarioescolar.pt/calendario-escolar-madeira/); [Escola Digital Madeira](https://escoladigital.madeira.gov.pt/ebspecalheta/2026/09/06/calendario-escolar-2026-2027-2/)
- **Private schools:** the mainland Despacho applies to public establishments and, among private ones, only to private special-education establishments. — [DR](https://diariodarepublica.pt/dr/detalhe/despacho/8368-2024-873447631); [CGD](https://www.cgd.pt/Site/Saldo-Positivo/formacao-e-tecnologia/Pages/calendario-escolar.aspx)
- **No open data:** the dados.gov.pt search turned up no calendário escolar dataset. Only regional transport NeTEx feeds (Coimbra) encode "períodos escolares" internally. — [dados.gov.pt search](https://dados.gov.pt/pt/datasets/?q=feriados)

### Inferences
- The feature should be one static table per region: Continente, Açores (referential), Madeira. It needs updating about once a year for Madeira and once per multi-year Despacho for the mainland, plus the occasional amendment. That is a hand-maintained data file, not a daily-fetched feed.
- The Azores dates may be off by a few days for a given school. The UI should say "datas de referência".
- Private and cooperative schools (ensino particular e cooperativo) generally set their own calendar, often close to the public one. This is inferred from the Despacho's scope; no source was found on how closely they follow it.
- Carnival (a school interruption, not a legal holiday) and municipal holidays (schools close locally) should both show up for school families.

### Gaps
- No ICS, JSON or API from DGEstE, DGE, DGAE or the regional governments was found. The machine-readable versions on community sites (calendarioescolar.pt etc.) have unknown terms.
- Private-school conventions could not be verified.
- The mainland 2026/27 dates came from secondary sites (CGD, casadoprofessor), not from a direct read of the Despacho annex PDF. The PDF should be checked before encoding.

## Waste collection: who publishes schedules, in what format, and how common is scheduled kerbside collection?

### Takeaway
Structurally this is very different from Germany. Most Portuguese households take waste to street containers: undifferentiated bins, plus ecopontos for recyclables (no household schedule). Scheduled door-to-door (porta-a-porta, PAP) collection is a minority. It is mostly limited to single-family-house zones in some municipalities, and APA figures put PAP at about 2% of selective collection. Where schedules exist they are municipal PDFs, zone tables on web pages or calendars handed out on enrolment. The one machine-readable source found is Lisbon's open data (circuits with periodicity and start time, CC0). No common vendor platform giving broad coverage was found.

### Cited Findings
- **Share of PAP:** APA's Relatório Anual Resíduos Urbanos 2024 puts door-to-door at 2% of selective collection by typology, against 8% for ecopontos and 6% for special circuits (figures as reported by search). — [APA RARU 2024 (PDF)](https://apambiente.pt/sites/default/files/_Residuos/Producao_Gest%C3%A3o_Residuos/Dados%20RU/2024/raru_2024.pdf); [RARU 2023](https://apambiente.pt/sites/default/files/_Residuos/Producao_Gest%C3%A3o_Residuos/Dados%20RU/2023/raru_2023.pdf). Treat these figures with caution: the search summary's percentages do not obviously add up, and the table was not read directly.
- **Ecoponto access:** per RASARP 2024, only about 60% of ecopontos are close to citizens; recommended fixes include PAP and PAYT. — [Electrão press release](https://electrao.pt/pt/sala-de-imprensa/ecopontos-longe-dos-cidadaos-dificultam-reciclagem-de-embalagens)
- **Lisbon (the best source):** the dataset "Circuitos de Recolha de Resíduos Urbanos" gives each circuit's designation, periodicity and start time, plus the collection points covered (location, container capacity by type).
  - Publisher: Município de Lisboa. Licence: CC0.
  - Formats: API, GeoJSON, CSV and WFS.
  - Last updated 15 Dec 2023, with no declared update frequency.
  - Sources: [dados.gov.pt](https://dados.gov.pt/en/datasets/circuitos-de-recolha-de-residuos-urbanos/); [dados.cm-lisboa.pt](https://dados.cm-lisboa.pt/no/dataset/circuitos-de-recolha-de-residuos-urbanos)
  - A second dataset, "Áreas de Recolha de Resíduos – Porta-a-Porta, Entidades e Ecoilhas de Superfície", maps collection zones with days and times. — [dados.gov.pt](https://dados.gov.pt/pt/datasets/areas-de-recolha-de-residuos-porta-a-porta-entidades-e-ecoilhas-de-superficie/); [dados.cm-lisboa.pt (403 to fetcher)](https://dados.cm-lisboa.pt/dataset/areas-recolha-de-residuos-porta-a-porta-entidades-e-eco-ilhas-de-superficie)
  - Also available: garden-waste collection ([dataset](https://dados.cm-lisboa.pt/dataset/recolha-seletiva-de-residuos-de-jardim)) and the ArcGIS hub [Geodados CML](https://geodados-cml.hub.arcgis.com/).
- **Porto (Porto Ambiente):** PAP covers western zones, expanding east with EU funding, mainly single-family homes. Schedules are three zone PDFs for 2026 (Azul, Vermelha, Verde) plus a coverage-map PDF. There is no street search and no ICS. — [Porto Ambiente](https://www.portoambiente.pt/residuos-urbanos/recolha-porta-a-porta-residencial)
- **Lipor "Reciclar é Dar +" in Porto:** about 2,433 households in 3 zones, with a fixed weekly timetable per zone as HTML (glass every 15 days). — [Lipor](https://www.lipor.pt/darmais/recolhas/porto.html). Valongo has a similar programme. — [residuos.cm-valongo.pt](https://residuos.cm-valongo.pt/recolha-seletiva/reciclar-e-dar-21)
- **Maia:** PAP selective collection reportedly covers about 85% of the population, an outlier. — [CM Maia](https://www.cm-maia.pt/pages/1017)
- **Intermunicipal systems with PAP pages:**
  - ERSUC: Aveiro and Coimbra. Undifferentiated twice weekly, packaging weekly, paper every 15 days, glass monthly. Residents get a calendar per freguesia on enrolment. — [ERSUC](https://www.ersuc.pt/pt/area-de-utilizador/reciclagem-a-porta/)
  - Suldouro — [Suldouro](https://www.suldouro.pt/pt/area-de-utilizador/recolha-porta-a-porta/)
  - Amarsul — [Amarsul](https://www.amarsul.pt/pt/area-de-utilizador/recolha-domestica/)
  - Resitejo and RSTJ, "Ecoponto à Porta" — [Resitejo](https://www.resitejo.pt/ecoponto-a-porta/), [RSTJ](https://rstj.pt/ecoponto-a-porta/)
- **Other municipal schedule pages (HTML or PDF, no structured format seen):**
  - Espinho — [cm-espinho](https://portal.cm-espinho.pt/en/acolhemos/municipes/ambiente-e-espacos-verdes/1-4-205/1-4-319/)
  - Barreiro — [cm-barreiro](https://www.cm-barreiro.pt/viver/aguas-e-higiene-urbana/residuos-e-higiene-urbana/horarios-recolha/)
  - Funchal — [funchal.pt](https://www.funchal.pt/areas-intervencao/ambiente/recolha-residuos/horarios-de-recolha-de-residuos/)
  - Ponta Delgada — [cm-pontadelgada](https://www.cm-pontadelgada.pt/viver/ambiente-e-protecao-animal/recolha-de-residuos-horarios-e-percursos)
  - Povoação — [cm-povoacao](https://www.cm-povoacao.pt/index.php/servicos-municipais/ambiente/residuos/horarios-e-circuitos-de-recolha)
  - Ribeira Grande — [cm-ribeiragrande](https://www.cm-ribeiragrande.pt/areas-de-atividade/ambiente/recolha-de-residuos-solidos-urbanos)
  - Soure: collection 06:00–23:00 every day, no per-street schedule — [cm-soure](https://cm-soure.pt/horarios-de-recolha-de-residuos-urbanos/)
  - Vila do Conde — [cm-viladoconde](https://www.cm-viladoconde.pt/servicos/servicos-municipais/ambiente-e-acao-social/ambiente/recolha-de-residuos)
  - Moita — [cm-moita](https://www.cm-moita.pt/viver/ambiente/residuos-96)
  - Lisbon parish example, Junta de Freguesia de Alvalade — [jf-alvalade](https://jf-alvalade.pt/tema-a-tema/higiene-urbana/recolha-de-residuos-urbanos/)
- **Split of responsibility:** municipalities or their companies collect undifferentiated waste. Intermunicipal systems (Lipor, Valorsul, ERSUC, Amarsul, Suldouro, Resitejo…) mostly handle selective/recyclable collection and treatment. — pattern across the pages above (e.g. [Amarsul](https://www.amarsul.pt/pt/area-de-utilizador/recolha-domestica/), [ERSUC](https://www.ersuc.pt/pt/area-de-utilizador/reciclagem-a-porta/))
- The GitHub aggregator of PT public APIs lists nothing for waste collection. — [devpt-org/public-data-portugal](https://github.com/devpt-org/public-data-portugal)

### Inferences
- For most Portuguese households (flats in cities, ecoponto users) there is no personal pickup date to show at all. At most, the undifferentiated bin is emptied nightly or several times a week, and the rule is "put the bag out between X and Y h". A German-style "bins tomorrow at 19:00" reminder fits only PAP households, mostly in single-family zones.
- The best MVP is probably not per-street scraping. Instead:
  - **(a)** Lisbon, via the CC0 open data: circuit periodicity and start time, joined spatially to the address. This is the only real API.
  - **(b)** A user-entered recurring rule ("indiferenciado seg/qua/sex, embalagens quinta, vidro 1.ª terça do mês"), since PAP calendars are weekly or fortnightly patterns handed out on paper or PDF.
  - **(c)** Later, per-zone PDF transcription for a few large PAP programmes (Porto, Maia, ERSUC Aveiro/Coimbra, Valongo).
- No evidence was found of a common SaaS vendor (the German Abfall-IO / C-Trace equivalent) serving many Portuguese municipalities with an address lookup. A one-adapter, broad-coverage route does not appear to exist.
- The Valorsul, Resíduos do Nordeste and EMAC Cascais pages were not individually checked. Cascais has an open-data portal ("Cascais Data", listed by [devpt-org](https://github.com/devpt-org/public-data-portugal)) that may hold circuit data, but this is unverified.

### Gaps
- The share of households with scheduled kerbside collection nationally is not established. The "2% of selective collection" figure is by typology or tonnage, not by population served.
- Valorsul, Resíduos do Nordeste, EMAC Cascais and Braga/Braval schedule formats were not checked.
- The Lisbon datasets' freshness (last updated Dec 2023) and field schema were not verified by download. The dados.cm-lisboa.pt pages returned 403 to the fetcher.
- No GitHub scrapers for Portuguese collection schedules were found.

## Which regional fields should onboarding capture?

### Takeaway
Capture the concelho (municipality), with the region derived from it (Continente / Açores / Madeira). That alone drives national, regional and municipal holidays and the school calendar. For waste, capture a full street address or código postal (CP4-CP3) plus freguesia, geocoded to coordinates for Lisbon's spatial data. The código postal can pre-fill the concelho and freguesia via GEO API PT.

### Cited Findings
- **GEO API PT** (geoapi.pt):
  - Endpoints: `/cp/{CP4-CP3}` returns concelho, freguesia and street; `/gps/{lat},{lon}` reverse-geocodes to administrative divisions; `/municipios` and `/freguesias` list the units.
  - Free public tier with hourly and daily request limits (numbers not shown), plus a premium tier with an API key.
  - The code is GPL-3.0; the data licence is not stated.
  - Source: [geoapi.pt docs](https://geoapi.pt/docs/); listed in [devpt-org/public-data-portugal](https://github.com/devpt-org/public-data-portugal)
- The community municipal-holiday JSON is keyed by postal-code prefix, which confirms that CP → concelho is a workable key. — [festivos-locales](https://github.com/ChemieuroDEV/festivos-locales)
- ERSUC PAP calendars are issued per freguesia. — [ERSUC](https://www.ersuc.pt/pt/area-de-utilizador/reciclagem-a-porta/)
- Porto PAP schedules are per zone within the city. — [Porto Ambiente](https://www.portoambiente.pt/residuos-urbanos/recolha-porta-a-porta-residencial)

### Inferences
- The minimum is concelho (308 values; a picker is feasible, grouped by distrito or região autónoma). Distrito is not needed for any of the three features: no holiday or school rule is set at district level.
- Region is fully determined by concelho, so it is never asked.
- Freguesia matters only for waste, and only in some systems. Collect it implicitly from the CP4-CP3 or the address, not as a separate question.
- Some concelhos straddle PAP and non-PAP zones, so street-level location is needed wherever PAP exists.
- As in the German app, the family's `families.address` (town) can hold this, extended with a concelho INE/DICOFRE code as the stable key. Official concelho codes come from INE/DGT CAOP; not verified here, see Gaps.

### Gaps
- The official concelho/freguesia code source (DGT CAOP, INE DICOFRE) and its licence were not verified in this pass.
- GEO API PT's exact free-tier limits and the provenance of its postcode data (CTT postcode data is commercially licensed) were not confirmed. This matters for commercial use.
