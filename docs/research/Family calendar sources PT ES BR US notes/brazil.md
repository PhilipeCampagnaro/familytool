# Brazil — free, machine-readable sources for holidays, school holidays and waste collection

Research date: 2026-09-18. About 20 tool calls. Some pages are JavaScript apps (brasilapi.com.br/docs, SP's coleta lookup), and a fetch returned no API details for them. Those items are marked as gaps rather than guessed.

## 1. Public holidays (feriados): the legal structure, and whether to compute or fetch

### Takeaway
National holidays are fixed in federal law, and the movable ones follow from Easter, so they can be **computed in-app** exactly the way `german_holidays.dart` works. State holidays are a small list you can maintain by hand (27 UFs). Municipal holidays are the hard part: up to 4 religious days plus civil dates for each of 5,570 municipalities. The only free bulk source I found is an MIT-licensed community repo keyed on the IBGE code. Carnaval and Corpus Christi are **pontos facultativos, not feriados**. BrasilAPI labels them "national", which is misleading.

### Cited Findings
- **Legal basis for the three tiers (Lei 9.093/1995).** Art. 1 lists the civil holidays: those declared in federal law, the state's *data magna* fixed in state law, and the first and last day of the year of a municipality's centenary, fixed in municipal law. Art. 2 covers religious holidays: days of observance declared in municipal law according to local tradition, "em número não superior a quatro, neste incluída a Sexta-Feira da Paixão". Sources: [Planalto L9093](https://www.planalto.gov.br/ccivil_03/leis/l9093.htm) (the fetch failed with ECONNRESET, so the content comes from the [Guia Trabalhista mirror](https://www.guiatrabalhista.com.br/legislacao/l9093.htm) via the search summary), [Câmara original text](https://www2.camara.leg.br/legin/fed/lei/1995/lei-9093-12-setembro-1995-348594-publicacaooriginal-1-pl.html).
  - Consequence: each state has **exactly one** *data magna* under this law. Good Friday is legally a *municipal* religious holiday that uses one of the municipality's four slots. It is not a federal holiday in the statute, but federal administration treats it as one (see the MGI portaria below).
- **20 November is a national holiday.** Lei 14.759 of 21 Dec 2023 declares the Dia Nacional de Zumbi e da Consciência Negra a feriado nacional. Before that it was a holiday in 6 states and about 1,200 cities. Sources: [Planalto L14759](https://www.planalto.gov.br/ccivil_03/_ato2023-2026/2023/lei/l14759.htm), [Câmara news](https://www.camara.leg.br/noticias/1029291-lei-torna-feriado-nacional-o-dia-20-de-novembro-dia-nacional-de-zumbi-e-da-consciencia-negra/), [gov.br/MDS](https://www.gov.br/mds/pt-br/noticias-e-conteudos/desenvolvimento-social/noticias-desenvolvimento-social/pela-primeira-vez-feriado-da-consciencia-negra-e-nacional).
- **The yearly federal calendar is set by portaria.** For 2026 it is **Portaria MGI nº 11.460 of 29 Dec 2025** (DOU 30 Dec 2025). It lists 10 national holidays and 9 pontos facultativos.
  - The 10 holidays: 1 Jan, Paixão de Cristo, Tiradentes, 1 May, 7 Sep, 12 Oct, 2 Nov, 15 Nov, 20 Nov, 25 Dec.
  - The pontos facultativos: Carnaval (16 and 17 Feb), Ash Wednesday until 14:00, Corpus Christi (4 Jun), 5 Jun, Dia do Servidor (28 Oct), and the afternoons of 24 and 31 Dec.
  - Sources: [SINAIT](https://www.sinait.org.br/noticia/23028/portaria-do-mgi-divulga-feriados-nacionais-e-estabelece-os-dias-de-ponto-facultativo-em-2026), [UFAL](https://noticias.ufal.br/transparencia/noticias/2026/1/governo-federal-divulga-lista-de-feriados-nacionais-e-pontos-facultativos-de-2026), [gov.br Portal do Servidor on 5 Jun](https://www.gov.br/servidor/pt-br/assuntos/noticias/2026/portaria-do-mgi-estabelece-ponto-facultativo-no-dia-5-de-junho-para-os-orgaos-da-administracao-publica-federal).
  - These pontos facultativos bind **federal agencies only**. States, municipalities and private employers decide for themselves (inference; standard reading).
- **BrasilAPI `GET /api/feriados/v1/{ano}`** (free, no key; the project is MIT on [GitHub](https://github.com/BrasilAPI/BrasilAPI), 11.2k stars).
  - For 2026 it returned 14 entries, all with `type: "national"`: the 10 legal holidays plus Carnaval (16 and 17 Feb), Páscoa (5 Apr) and Corpus Christi (4 Jun). Source: [live response](https://brasilapi.com.br/api/feriados/v1/2026).
  - It has **no state or municipal parameter**, and it mislabels pontos facultativos and Easter Sunday as national holidays.
  - Treat it as a cross-check at most. Easter-offset computation (Corpus Christi = Easter + 60) is the common approach ([GitHub examples](https://github.com/topics/feriados-brasil)).
- **Municipal holiday datasets:**
  - [joaopbini/feriados-brasil](https://github.com/joaopbini/feriados-brasil):
    - **MIT license**; "5.570 municípios e 27 estados".
    - Formats: CSV, JSON and SQL per year (2024, 2025 and 2026 visible).
    - Fields: `data`, `nome`, `tipo` (NATIONAL/STATE/MUNICIPAL/DISCRETIONARY), `descricao`, `uf`, `codigo_ibge`.
    - Compiled "from public sources", with the IBGE Localidades API used for geography. The page shows no update date. This is the best free bulk candidate, and it has community-level reliability.
  - [dadosbr/feriados](https://github.com/dadosbr/feriados): community project aiming at importable files and free APIs. Not inspected further.
  - [Kaggle "Feriados de todas cidades Brasileiras (2000–2025)"](https://www.kaggle.com/datasets/markfinn1/feriados-municipais-de-todos-estados-brasileiros): license not checked.
  - A BrasilAPI issue requesting per-municipality holidays exists ([#380](https://github.com/BrasilAPI/BrasilAPI/issues/380)). BrasilAPI has no such endpoint today.
- **Commercial or freemium APIs (flag: not confirmed free for commercial use):**
  - [feriadosapi.com](https://feriadosapi.com/sobre): 5,571 municipalities, keyed on IBGE codes. It claims to monitor DOU/DOE/DOM and municipal legislation. A free account exists, but the tier limits and terms are on separate pricing and terms pages I did not read.
  - [feriados.dev](https://feriados.dev/documentacao): national, state and municipal; v1 and v2. Terms not checked.
  - [RapidAPI "feriados-brasileiros"](https://rapidapi.com/davidsimonmarques/api/feriados-brasileiros): input is city + UF + year. RapidAPI has paid tiers.

### Inferences
- **Recommended split:**
  - **Compute** the national holidays (a fixed list plus Easter-derived Sexta-feira Santa) and optionally show Carnaval and Corpus Christi as a separate "ponto facultativo" style. This mirrors how the German Feiertage are computed.
  - **Hand-maintain a table** for the 27 state *data magna* and other state holidays. The list is small and rarely changes.
  - **Import municipal holidays** from the MIT repo into a table keyed by `codigo_ibge`, refreshed yearly. They cannot be computed.
- **Municipal data quality is the weak point.** The rules sit in 5,570 separate municipal laws, and no official consolidated federal dataset exists. That matches the joaopbini repo and feriadosapi both building their own compilations.
- Corpus Christi is a *municipal* religious holiday in many cities (for example, it is widely one in São Paulo capital). The municipal dataset should decide whether it counts as a holiday there. A national rule should not.

### Gaps
- I did not verify ANBIMA's calendar (it is a bank-holiday list, national only, and unlikely to add value), Invertexto's holiday API terms, or the exact texts of Lei 662/1949 and Lei 10.607/2002 (these set the list of national dates).
- I did not verify the list of state holidays per UF, for example SP's 9 de julho (Revolução Constitucionalista, state law). No official consolidated dataset was found.
- I did not check the update cadence or accuracy of joaopbini/feriados-brasil beyond its README. It has 99 commits and shows no last-update date.

## 2. School holidays (calendário escolar)

### Takeaway
**No free machine-readable (ICS/JSON/CSV) school calendar was found for any state or municipal network.** Every secretaria publishes a PDF or HTML page, or a resolution with parameters that each school adapts. On top of that, a German-style "one feed per region" does not map cleanly. A single city has at least three independent calendars (rede estadual, rede municipal, and each private school), and in several states each school adapts the network calendar.

### Cited Findings
- **RS rede estadual 2026:** published as a PDF.
  - Classes run 18 Feb to 18 Dec 2026.
  - Paradas pedagógicas on 15/04, 13/08 and 24/11.
  - Winter recess from 27/07 to 02/08.
  - Sources: [educacao.rs.gov.br PDF](https://educacao.rs.gov.br/upload/arquivos/202601/07115929-calendario-escolar-2026-da-rede-estadual.pdf), [HTML page](https://educacao.rs.gov.br/calendario-escolar-de-2026).
- **SP rede estadual 2026:** classes 2 Feb to 18 Dec. First semester 2 Feb to 6 Jul, second 24 Jul to 18 Dec. Published as a knowledge-base article or news item, not data. Sources: [SEDUC-SP atendimento article SED-08404](https://atendimento.educacao.sp.gov.br/knowledgebase/article/SED-08404/pt-br), [Conam](https://www.conam.com.br/educacao-de-sp-divulga-calendario-escolar-para-2026-aulas-comecam-em-2-de-fevereiro/).
- **Goiás:** the Conselho Estadual de Educação sets *parameters* for school calendars (Resolução nº 08 of 29 Aug 2025) ([goias.gov.br/cee](https://goias.gov.br/cee/calendario-escolar-2026/)). The SIAP system has a printable calendar page ([siap.educacao.go.gov.br](https://siap.educacao.go.gov.br/imprimircalendario.aspx?anoLetivo=2026)), which is HTML for printing, not a feed.
- **Other networks, all HTML or PDF:** Paraná has a calendars page covering 2016–2026 ([educacao.pr.gov.br](https://www.educacao.pr.gov.br/Pagina/Calendario-Escolar)). Rio de Janeiro's municipal network publishes "Calendários Escolares 2026" ([educacao.prefeitura.rio](https://educacao.prefeitura.rio/calendarios-escolares-2026/)). The DF publishes downloadable calendars ([educacao.df.gov.br](https://www.educacao.df.gov.br/calendario-escolar/)).
- **Open-data portals have school data but no calendars.** SP's state portal lists Secretaria da Educação CSVs on schools, INEP codes, addresses and enrolments ([dadosabertos.sp.gov.br](https://dadosabertos.sp.gov.br/organization/secretaria-da-educacao?organization=secretaria-da-educacao&tags=C%C3%B3digo+INEP+Escola&tags=Escola&tags=Endere%C3%A7o+Escola&res_format=CSV), [dados.educacao.sp.gov.br](https://dados.educacao.sp.gov.br/aprenda)). The search turned up no calendar dataset.

### Inferences
- The realistic options are:
  - (a) Hand-curate a yearly table of **state-network** recess dates (27 PDFs a year; July recess plus Dec–Jan/Feb summer break). Offer it as a feed per UF, labelled "rede estadual" so it is not presented as "the" school holidays.
  - (b) Skip the feature for Brazil, or reuse the existing "paste an ICS link" mechanism for private schools that publish one (many private schools use Google Calendar or school apps, but this is unverified).
- Unlike the German Ferien, the dates differ by network within the same city. A Bundesland-style picker would need a UF + network choice (estadual / municipal of city X). Municipal networks multiply to 5,570.

### Gaps
- I did not check MG, BA, PE, CE, SC or other states individually. Absence of evidence is not proof, but the searches aimed at "dados abertos calendário escolar CSV/ICS" returned nothing machine-readable.
- I found no national aggregator (MEC/INEP) of school calendars.

## 3. Waste collection (coleta domiciliar / seletiva)

### Takeaway
Big capitals have **address or CEP web lookups** run by the prefeitura or its concessionária. Only **Belo Horizonte publishes open data (CC-BY)**. None document a public API or terms for machine use. Brazilian schedules are **recurring weekday and shift patterns** ("Seg/Qua/Sex, noturno"), not dated pickups like German vendor feeds. The data model is simpler (a weekly rule per address) but still needs per-city adapters.

### Cited Findings
- **São Paulo:**
  - Official lookup at [coleta.prefeitura.sp.gov.br](https://coleta.prefeitura.sp.gov.br/): "Digite… o seu CEP e saiba os dias e horários".
  - The result table shows Logradouro, Subprefeitura, CEP, and Mon–Sun columns for Domiciliar and Seletiva with time periods. The page exposes no public API or terms.
  - A second front end is at [SP Regula BI](https://bi.spregula.sp.gov.br/consultas/consulta_coleta.html), with CEP input and the same output. Its backend was not visible.
  - Two concessionaires: **Loga** (Noroeste: Centro, Norte, Oeste) and **Ecourbis** (Sudeste: Sul, Leste). Coleta seletiva covers 96 districts, about 76% of streets.
  - Sources: [Prefeitura SP news](https://prefeitura.sp.gov.br/w/noticia/servico-saiba-como-consultar-dias-e-horarios-das-coletas-domiciliar-seletiva-e-cata-bagulho), [SP Regula coleta seletiva](https://www.prefeitura.sp.gov.br/cidade/secretarias/spregula/residuos_solidos/coleta_seletiva/index.php?p=4623), [Ecourbis horários](https://www.ecourbis.com.br/coleta/index.html).
  - GeoSampa has a public GeoServer WFS ([GetCapabilities](http://wfs.geosampa.prefeitura.sp.gov.br/geoserver/ows?service=wfs&version=1.0.0&request=GetCapabilities)) and a metadata catalogue. I did **not** confirm a collection-sector layer with schedules in it.
- **Belo Horizonte (best open-data case):**
  - Dataset "Dados georreferenciados coleta resíduos" on [dados.pbh.gov.br](https://dados.pbh.gov.br/dataset/dados-georreferenciados-coleta-residuos). It describes "frequência e abrangência do serviço de coleta". It comes as CSV plus MapInfo TAB/DAT/ID/MAP files.
  - **CC-BY license.** Last updated 18 Jun 2026; updated ad hoc; maintained by the SLU.
  - A separate dataset covers [Coleta Seletiva Porta a Porta](https://ckan.pbh.gov.br/dataset/coleta-seletiva-porta-a-porta). Door-to-door selective collection reaches about 556k people in 60 neighbourhoods; the lookup is on the PBH portal or by phone 156 ([PBH](https://prefeitura.pbh.gov.br/slu/informacoes/servicos/porta-a-porta), [PBH news](https://prefeitura.pbh.gov.br/noticias/coleta-seletiva-porta-porta-e-ampliada-em-belo-horizonte)).
  - I did not confirm that the CSV has day or shift columns per street.
- **Porto Alegre (DMLU):**
  - Lookup "por endereço completo" at [prefeitura.poa.br consulta coleta seletiva](https://prefeitura.poa.br/smsurb/servicos/consulta-coleta-seletiva), plus a domiciliar lookup ([rs.gov.br carta de serviços 790](https://www.rs.gov.br/carta-de-servicos/servicos?servico=790)).
  - Selective collection runs 3×/week in Centro Histórico and listed central bairros, and 2×/week elsewhere ([DMLU coleta seletiva](https://prefeitura.poa.br/dmlu/coleta-seletiva)).
  - No open dataset found.
- **Curitiba:**
  - Lookup of frequency and shift by address at [coletalixo.curitiba.pr.gov.br](https://coletalixo.curitiba.pr.gov.br/lixo-domestico), for household and recyclable waste.
  - The toxic-waste collection is a **yearly PDF calendar** by terminal ([2025 PDF](https://coletalixo.curitiba.pr.gov.br/pdf/CALENDARIO_COLETA_LIXO_2025_pdf.pdf)). Times listed are start times; night collection can run past midnight.
  - The concessionaire Estre also hosts a lookup ([estre.com.br](https://www.estre.com.br/consulta-coleta/consulta-coleta-curitiba/)).
- **Rio de Janeiro (Comlurb):**
  - Lookup per street at [comlurb.prefeitura.rio/servico/coleta-domiciliar](https://comlurb.prefeitura.rio/servico/coleta-domiciliar/).
  - Day shifts start 07:00 and night shifts 17:00. Centro, Gamboa and Saúde have daily Mon–Sat collection. Bags go out up to 1 h before collection, containers up to 2 h before.
- **No common vendor platform surfaced** comparable to the German families (AbfallPlus, etc.). Collection is run by municipal autarquias (SLU, DMLU, Comlurb) or concessionaires (Loga, Ecourbis, Estre), each with its own site. This is an inference from the five cities checked.

### Inferences
- The best form for a Brazilian adapter is **"weekly rule per address"** (weekdays + shift + type), expanded into dates in-app. It resembles how trackers compute due days more than it resembles the German ICS feeds.
- **Start with BH, the only one with explicit legal clearance** (CC-BY open data, attribution required).
- **SP is the biggest prize.** Its CEP lookup almost certainly calls a JSON backend, but the backend is undocumented and has no stated terms. Scraping it is technically likely to work and legally grey, like several German vendor adapters. A written request to SP Regula, or a LAI (Lei de Acesso à Informação) request, is the clean route.
- Many smaller municipalities publish schedules only as a PDF or image per bairro, or not at all (inference; not checked).

### Gaps
- I did not inspect the SP, Curitiba, POA or Comlurb lookups' network calls, so there are no endpoint URLs, and no terms of use were found for any of them.
- I did not open BH's CSV to confirm its columns.
- I did not check Recife, Fortaleza, Salvador, Brasília (SLU-DF), Florianópolis (Comcap) or Campinas.
- I did not check dados.prefeitura.sp.gov.br for a collection dataset.

## 4. Address resolution and what onboarding should capture

### Takeaway
Capture the **CEP** and resolve it with ViaCEP (or BrasilAPI CEP). That yields UF, município name and the **IBGE municipality code**. Store `uf` + `codigo_ibge` as the region keys for holidays and school calendars, and keep CEP/logradouro/número for waste lookups, since SP's lookup is itself keyed on CEP.

### Cited Findings
- **ViaCEP** ([viacep.com.br](https://viacep.com.br/)):
  - Free, no key.
  - Returns `cep, logradouro, complemento, unidade, bairro, localidade, uf, estado, regiao, ibge, gia, ddd, siafi`.
  - Reverse search by UF/city/street takes at least 3 characters and returns at most 50 results.
  - JSON, JSONP and XML. An invalid format returns HTTP 400; a nonexistent CEP returns `{"erro": true}`.
  - **Terms:** it forbids commercial redistribution or resale of the database and warns that bulk validation "may automatically block access indefinitely". No explicit rate limit is published. Per-user onboarding lookups fit the intended use (inference).
- **BrasilAPI** (MIT open source, [GitHub](https://github.com/BrasilAPI/BrasilAPI)) also offers CEP and IBGE endpoints. Its docs page is a JavaScript app, and I could not read the field lists or fair-use terms.
- The joaopbini dataset keys municipal holidays on `codigo_ibge` + `uf` ([repo](https://github.com/joaopbini/feriados-brasil)), and feriadosapi.com uses IBGE codes too ([sobre](https://feriadosapi.com/sobre)). ViaCEP's `ibge` field connects them directly.
- Some CEPs are city-wide "CEP geral" codes for small municipalities (common knowledge, unverified here). In those cases ViaCEP returns an empty `logradouro`/`bairro`, and the street has to be typed.

### Inferences
- **Onboarding fields:** CEP (required) → auto-fill UF, município (+ hidden `codigo_ibge`), bairro, logradouro; then número (for waste lookups).
- Keep **UF** and **codigo_ibge** as the stable keys.
- School calendars additionally need a **network choice** (estadual / municipal / particular).
- CEP resolution should run server-side in an Edge Function or client-side per user. It should never be a bulk sync, which ViaCEP's terms prohibit.

### Gaps
- BrasilAPI CEP v2's upstream providers, rate limits and terms were not retrieved (the docs didn't render).
- The IBGE Localidades API (servicodados.ibge.gov.br) was not fetched directly. Its use is inferred from the joaopbini README.
