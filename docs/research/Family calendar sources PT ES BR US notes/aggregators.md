# Cross-country aggregators and rule libraries: public holidays, school holidays, waste collection (PT, ES, BR, US)

Checked 2026-09-18. "Verified live" = I called the endpoint myself on that date (curl) and report what came back. Anything under "Inferences" is my reading and has no source behind it.

## OpenHolidays API (openholidaysapi.org): coverage, granularity, license, limits, operator

### Takeaway
OpenHolidays is the best free source for **PT and ES**. It has PT public holidays down to the **308 municipalities**, ES public holidays by comunidad, and school holidays for both, ES down to province level. It has **nothing for the US**, and for **BR** it has national public holidays only, with no data past 2025. The data is ODbL. It is run by a small German company that also serves the German Ferien data the app probably already uses. Its ES school data for **2026/27 is not loaded yet**, even though that school year has already started.

### Cited Findings
- Verified live: `GET /Countries` returns 36 countries: AD AL AT BE BG BR BY CH CZ DE EE ES FR HR HU IE IT LI LT LU LV MC MD MT MX NL PL PT RO RS SE SI SK SM VA ZA. **The US is not among them.** — [openholidaysapi.org/Countries](https://openholidaysapi.org/Countries)
- Verified live: PT subdivisions are 18 distritos plus 2 regiões autónomas (PT-AC, PT-MA), with **308 municipality children** (for example `PT-AC-CO` Corvo, category "município"). — [Subdivisions?countryIsoCode=PT](https://openholidaysapi.org/Subdivisions?countryIsoCode=PT)
- Verified live: PT public holidays 2026 = **156 entries**. The national ones are flagged `nationwide: true`, including Carnaval. Each municipal holiday is tagged with municipality codes (for example Lisboa `PT-LI-LI` on 13 June, Porto `PT-PO-PO` on 24 June). 2027 is also loaded (156 entries). — [PublicHolidays PT](https://openholidaysapi.org/PublicHolidays?countryIsoCode=PT&validFrom=2026-01-01&validTo=2026-12-31)
- Verified live: PT school holidays: 7 entries in 2026, all `nationwide: true` (Natal, Carnaval, Páscoa, and three staggered "Férias de verão" end dates for different school levels). Data runs to 2027-12-31. — [SchoolHolidays PT](https://openholidaysapi.org/SchoolHolidays?countryIsoCode=PT&validFrom=2026-01-01&validTo=2026-12-31)
- The data repo README still says Portugal is only "national and district public holidays from 2020". It mentions neither the school holidays nor the municipal holidays that the live API returns, so the README is out of date. — [openholidaysapi.data README](https://github.com/openpotato/openholidaysapi.data)
- Verified live: ES subdivisions are 17 comunidades plus Ceuta and Melilla, with **50 provincia children** (for example `ES-AN-GR`). — [Subdivisions ES](https://openholidaysapi.org/Subdivisions?countryIsoCode=ES)
- Verified live: ES public holidays 2026 = 54 entries, 44 of them regional. **No municipal (fiesta local) holidays.** — [PublicHolidays ES](https://openholidaysapi.org/PublicHolidays?countryIsoCode=ES&validFrom=2026-01-01&validTo=2026-12-31)
- Verified live: ES school holidays: 121 entries in 2026, per comunidad and in Andalucía per province (`ES-AN-CO`, `ES-AN-MA`, `ES-AN-CA`). **The latest endDate in the dataset is 2026-07-23.** A query for 2026-09-01 to 2027-08-31 returns 0 entries, so the 2026/27 school year is missing as of 2026-09-18. — [SchoolHolidays ES](https://openholidaysapi.org/SchoolHolidays?countryIsoCode=ES&validFrom=2026-09-01&validTo=2027-08-31)
- Verified live: BR has **0 subdivisions**. Public holidays for 2026 return **0 entries**, while 2024–2025 return 34 (national only). School holidays return `[]`. — [PublicHolidays BR](https://openholidaysapi.org/PublicHolidays?countryIsoCode=BR&validFrom=2026-01-01&validTo=2026-12-31)
- The README lists "Brazil (public holidays from 2020)" and "Spain (public holidays and school holidays from 2020, Initial data from @TBiele)". Mexico is the only other country in the Americas. — [openholidaysapi.data README](https://github.com/openpotato/openholidaysapi.data)
- Licenses: the data repo `openpotato/openholidaysapi.data` is **ODbL-1.0** and the API server code `openpotato/openholidaysapi` is **AGPL-3.0** (GitHub license metadata). The data repo was last pushed 2026-04-13 and has 70 stars. — [data repo](https://github.com/openpotato/openholidaysapi.data), [API repo](https://github.com/openpotato/openholidaysapi)
- The operator is **STÜBER SYSTEMS GmbH (Germany)**. The site calls it "a small Open Data project". — [openholidaysapi.org/en](https://www.openholidaysapi.org/en/)
- Verified live: no API key is needed. The response headers show `server: nginx` and **no rate-limit headers**.
- Per-country source lists are published at [sources-europe](https://www.openholidaysapi.org/en/sources-europe/) and [sources-americas](https://www.openholidaysapi.org/en/sources-americas/).

### Inferences
- ODbL permits commercial use. It requires attribution and share-alike **for a derived database that is publicly conveyed**. Showing produced work (dates in the app) needs only attribution. A Settings/About credit line would be the safe choice.
- Better than calling the API from the app: fetch once per region into the existing `public_feeds` shared-row pattern, or vendor the ODbL YAML/CSV from the GitHub repo and compute from it. Either way no household data reaches a third party.
- Relying on it carries two risks: the ES school data lags (the 2026/27 year is missing in mid-September) and there is one small maintainer. Plan to contribute ES and PT data upstream by PR, or to add a fallback.
- PT municipal granularity requires mapping a household's address to a concelho. That mapping can happen locally or on the server from `families.address`, with no third-party call.

### Gaps
- No published rate limit or fair-use policy was found on the pages fetched. The docs pages covering limits (if any) were not reached.
- The funding and sustainability model of STÜBER SYSTEMS for this project is unknown.
- Whether ES municipal school days (días no lectivos locales) are ever planned is unknown.

## Nager.Date / Nager.Holidays (date.nager.at, nagerholidays.com)

### Takeaway
Nager covers all four countries at the national level with coarse state tags, and the API is free with no key. However, its **Terms of Service require "active sponsorship" for commercial use and forbid running your own holiday portal from the data**, and self-hosting now needs a paid license key. For a commercial freemium app that makes it a paid or conditional option. Its data also had at least one error in the spot-check.

### Cited Findings
- Verified live: `/api/v3/AvailableCountries` returns 204 countries, including PT, ES, BR and US.
- Verified live, 2026: **PT** has 17 holidays, 3 with subdivisions (PT-20 Azores, PT-30 Madeira) and no municipal holidays. **ES** has 32, 22 of them regional (tagged by comunidad). **BR** has 15, of which only 1 is state-level (BR-SP, Revolução Constitucionalista). **US** has 17, with state tags and types such as `Observance`, `School`, `Optional`. — [date.nager.at/api/v3/PublicHolidays/2026/US](https://date.nager.at/api/v3/PublicHolidays/2026/US)
- **Data error found:** Nager lists "Dia dos Açores" on **2026-06-01**. OpenHolidays lists it on **2026-05-25**. The holiday falls on the Monday after Pentecost, which is 25 May 2026 (Easter is 5 April plus 50 days). My own computation matches OpenHolidays.
- Verified live: responses are served through Cloudflare with `cache-control: public,max-age=604800`.
- The repo moved to nagerholidays.com. Its README says: "Docker container or the NuGet package. **Both options require a license key.** As a sponsor of nager, you get a license key." — [Nager.Date README](https://github.com/nager/Nager.Date)
- The code is MIT per GitHub metadata. It has 1,412 stars and was pushed 2026-09-17. — [nager/Nager.Date](https://github.com/nager/Nager.Date)
- The API page advertises "No Rate Limits – Unlimited queries" and CORS enabled, and shows no pricing. — [nagerholidays.com/api](https://nagerholidays.com/api)
- The ToS says: "The Web API can be used for private or non-profit projects. **For commercial purposes we require active sponsorship.**" and "It is not allowed to use the holiday information to publish or operate your own holiday portal." There is no availability warranty. — [nagerholidays.com/legal/termsofservice](https://nagerholidays.com/legal/termsofservice)

### Inferences
- Nager is not zero-cost for Aporah as a commercial app: it needs a GitHub sponsorship, of an amount not researched. It adds nothing for PT or ES over OpenHolidays and is weaker than python-holidays or date-holidays for BR and US states.
- The "open-source" MIT label covers the code, but the data and the hosted service carry their own restrictions. Don't assume MIT covers the data.

### Gaps
- Sponsorship tier price needed for commercial use was not checked.
- No school-holiday coverage for these countries was found (the `School` type only marks public holidays on which schools close).

## python-holidays (vacanza/holidays) and ports; date-holidays (npm); workalendar; Dart packages

### Takeaway
**python-holidays (MIT)** is the best-maintained rules library. For these four countries it covers PT districts and autonomous regions, all ES comunidades, BR states plus São Paulo city, and all US states and territories. It has no Dart or JS port. **date-holidays (npm, JS/TS, usable in Deno)** has a similar and in places deeper subdivision tree (ES Canary islands, BR state capitals). However, **its data is CC BY-SA 3.0** because it derives from Wikipedia, while the code is ISC. Neither library has PT municipal holidays. Spanish regional holidays in every library come from the **annual BOE resolution**, so they need yearly updates rather than being computable forever.

### Cited Findings
- python-holidays: MIT, 1,930 stars, pushed 2026-09-16, PyPI version 0.104. — [vacanza/holidays](https://github.com/vacanza/holidays), [PyPI](https://pypi.org/pypi/holidays/json)
  - **PT** subdivisions: "01"–"18" (the 18 distritos) plus "20" Açores and "30" Madeira. Categories are PUBLIC and OPTIONAL, languages en_US, pt_PT and uk. — [portugal.py](https://github.com/vacanza/holidays/blob/dev/holidays/countries/portugal.py)
  - **ES** subdivisions: all CCAA plus Ceuta and Melilla, with 19 `_populate_subdiv_*` methods. `start_year` is 2008 and each year is sourced from that year's BOE resolution, up to 2026 (BOE-A-2025-21667). Languages are ca, en_US and es. — [spain.py](https://github.com/vacanza/holidays/blob/dev/holidays/countries/spain.py)
  - **BR** subdivisions: 27 UFs plus "São Paulo Capital". Categories are OPTIONAL and PUBLIC, language pt_BR. — [brazil.py](https://github.com/vacanza/holidays/blob/dev/holidays/countries/brazil.py)
  - **US** subdivisions: 50 states plus DC and territories (AS, GU, …). Categories are GOVERNMENT, HALF_DAY, PUBLIC and UNOFFICIAL. — [united_states.py](https://github.com/vacanza/holidays/blob/dev/holidays/countries/united_states.py)
- date-holidays (commenthol): npm version 3.36.1, license "ISC AND CC-BY-3.0" in package.json. The LICENSE file says: "The data contained in `holidays.yaml` is available under **CC BY-SA 3.0** … as the data obtained relies on wikipedia articles. … All other code … ISC." It has 1,104 stars and was pushed 2026-09-06. — [LICENSE](https://github.com/commenthol/date-holidays/blob/master/LICENSE), [npm](https://registry.npmjs.org/date-holidays/latest)
  - Note the conflict: package.json says CC-BY-3.0 and LICENSE says CC BY-SA 3.0. Treat it as **BY-SA** (the stricter one).
  - Tree from the README: **PT** is national only, with no subdivisions listed. **ES** has 19 regions, plus 7 Canary islands under CN and Barcelona under CT. **BR** has 27 states plus city regions Goiânia, Belo Horizonte, Recife, Curitiba, Rio de Janeiro and São Paulo. **US** has all states plus some cities (for example Los Angeles under CA). — [date-holidays README](https://github.com/commenthol/date-holidays)
- workalendar: MIT, but **last pushed 2024-04-12**, so effectively stale. — [workalendar/workalendar](https://github.com/workalendar/workalendar)
- Dart on pub.dev: there is **no port of python-holidays or date-holidays**. The closest packages:
  - `world_holidays` 2.1.2 (2026-08-21), "Generated multi-country holiday information with offline-first lookup and optional hosted updates" — [github.com/beomq/world_holidays](https://github.com/beomq/world_holidays). Its license and upstream source were not checked.
  - `feriados_pt` 0.2.3 (2026-05-25), "Portuguese public holidays for Dart and Flutter — national, municipal and regional" — [github.com/JoseGomes2001/feriados_pt](https://github.com/JoseGomes2001/feriados_pt). License not checked.
  - `holidays_us` 1.0.3 was last published 2022-04-08, so it is stale.

### Inferences
- The fastest path that fits the privacy model is to **port the rules to Dart by hand**, the way `german_holidays.dart` is written: Easter-relative plus fixed dates plus nth-weekday. python-holidays (MIT) would be the reference. MIT allows copying the logic with a notice. The US and BR rules are almost entirely computable. PT national holidays are computable, but the 308 municipal holidays are a table, which OpenHolidays (ODbL) supplies.
- ES breaks the "compute it forever" model. Regional holidays and their substitutions (holidays moved from a Sunday) change every year by BOE resolution. They need either a yearly data update or a shared server feed.
- date-holidays runs directly in Deno through npm specifiers and could power a shared server feed. The CC BY-SA 3.0 data licence means crediting it, and share-alike may extend to any redistributed derived dataset. That is manageable, but it is a worse fit than MIT/ODbL.
- Adopting `world_holidays` or `feriados_pt` would first require checking their licenses and data provenance.

### Gaps
- Whether python-holidays handles ES *observed* substitutions (Sunday moves) correctly for 2027 depends on the 2027 BOE, which will likely be published around Oct–Nov 2026. This was not verified.
- Licenses of `world_holidays` and `feriados_pt` were not verified.

## Paid or keyed APIs and platform calendars: Calendarific, AbstractAPI, API Ninjas, Google/Apple/Outlook holiday calendars

### Takeaway
Calendarific's free tier (500 calls/month, attribution required, limited upcoming data) is too small and would need a key. Its useful tiers cost money. Google's public holiday ICS feeds are fetchable without a key and include BR/US, but they are a consumer feed with no reuse license. None of these fits better than OpenHolidays plus computed rules.

### Cited Findings
- Calendarific plans: Free $0 with 500 calls/month and attribution required. Starter is $12/month or $100/year for 10,000 calls. Business is $500/year for 50,000. Enterprise is $4,000/year. The free tier has "Limited Historical Data" and "Limited Upcoming Data", and its data is updated quarterly. — [calendarific.com/pricing](https://calendarific.com/pricing)
- Verified live: Google's `en.usa#holiday@group.v.calendar.google.com/public/basic.ics` returns a VCALENDAR ("Holidays and Observances in United States"). The BR feed `pt.brazilian#holiday@…` returned 275 VEVENTs. — [Google US holiday ICS](https://calendar.google.com/calendar/ical/en.usa%23holiday%40group.v.calendar.google.com/public/basic.ics)

### Inferences
- The Google feeds carry no license or terms of their own and mix observances with public holidays without subdivision tags. Serving them from Aporah's server as a product feature would rely on undocumented endpoints. A user who wants them can already subscribe with the existing `ical` tile, which is the consistent route.

### Gaps
- AbstractAPI and API Ninjas holiday pricing and terms were **not checked** (out of tool budget). Both are keyed commercial APIs and would be paid at useful volumes. Treat this as unverified.
- Apple's and Outlook's holiday calendar subscriptions were not researched. They are subscribed by the user in the OS and have no reuse API that I know of.
- Google's terms for reusing these ICS feeds were not located.

## School holidays across PT, ES, BR, US

### Takeaway
Only **OpenHolidays** aggregates school holidays for these countries, and only for **PT (national) and ES (comunidad or province)**. No aggregator found covers **BR or US** school calendars. Those are set by state or municipal networks in BR and by each district in the US, so there is no national or state feed to share.

### Cited Findings
- OpenHolidays PT and ES school data as above, with ES 2026/27 missing as of 2026-09-18. — [SchoolHolidays ES](https://openholidaysapi.org/SchoolHolidays?countryIsoCode=ES&validFrom=2025-09-01&validTo=2027-12-31)
- OpenHolidays BR school holidays return `[]`, and the US is not a covered country (verified live).
- Nager's `School` type in the US data marks a public holiday on which schools close (for example "Truman Day"), not school vacation periods (verified live, 2026 US response).

### Inferences
- For the US and BR, the practical answer is the existing pasted-link or `ical` mechanism, since many US districts publish ICS or Google calendars, rather than a shared feed.

### Gaps
- No systematic source was found for BR state school calendars (redes estaduais) or US district calendars. This was not searched exhaustively.

## Waste collection: multi-country aggregators (Home Assistant waste_collection_schedule)

### Takeaway
No real multi-country waste aggregator exists for these markets. The Home Assistant integration (MIT code) has **0 sources for Spain or Brazil, 1 for Portugal (Lisbon), and 73 US entries**. About half of the US entries go through two commercial white-label platforms, **ReCollect** (22) and **Recycle Coach** (11). Those are vendors' endpoints with their own terms, not open data, and the lookup is per address.

### Cited Findings
- `mampfes/hacs_waste_collection_schedule`: the LICENSE is MIT ("Copyright (c) 2020 Steffen Zimmermann"), though GitHub reports it as NOASSERTION because of an image header. It has 2,232 stars and was pushed 2026-09-16. — [LICENSE](https://github.com/mampfes/hacs_waste_collection_schedule/blob/master/LICENSE)
- README country sections: Australia, Austria, Belgium, Canada, Czech Republic, Denmark, Finland, France, Germany, Hungary, Iceland, Ireland, Italy, Japan, Liechtenstein, Lithuania, Luxembourg, Malta, Netherlands, New Zealand, Norway, Poland, **Portugal**, Slovakia, Slovenia, South Africa, Sweden, Switzerland, United Kingdom, **United States of America**, Uruguay. **There are no Spain or Brazil sections.** — [README](https://github.com/mampfes/hacs_waste_collection_schedule)
- Portugal has one source, `cm_lisboa_pt`: Câmara Municipal de Lisboa's "Dias do Lixo" (informacoeseservicos.lisboa.pt/servicos/dias-do-lixo). It is keyed by `area_name` (for example "Restelo") and covers Indiferenciado, Papel e Cartão and Embalagens. — [cm_lisboa_pt.md](https://github.com/mampfes/hacs_waste_collection_schedule/blob/master/doc/source/cm_lisboa_pt.md)
- The US has 73 entries. The top backends are `recollect` (22), `recyclecoach_com` (11) and `recyclebycity_com` (3), and the rest are single-city scrapers (LA, Philadelphia, Pittsburgh, OKC, Plano, …). — [README](https://github.com/mampfes/hacs_waste_collection_schedule)
- ReCollect is used through a **per-place ICS URL**, for example `https://recollect.a.ssl.fastly.net/api/places/<uuid>/services/<id>/events.en.ics`, which the user obtains by searching an address and choosing "Get a calendar". The docs suggest stripping `client_id`. Verified live: that URL returns 200. — [recollect.md](https://github.com/mampfes/hacs_waste_collection_schedule/blob/master/doc/ics/recollect.md)

### Inferences
- The MIT license covers the integration's code, not the municipal or vendor endpoints. ReCollect and Recycle Coach are commercial SaaS sold to municipalities, so bulk server-side use from a commercial app without an agreement is legally risky. That makes each of them a per-address ICS a user pastes into the existing `ical` tile, not a shared Aporah feed.
- A "one fetch per street" feed like the German Abfall one is only possible city by city (for example Lisbon by area), and there is no PT, ES or BR vendor family comparable to the German ones.

### Gaps
- The terms of use of ReCollect, Recycle Coach and Lisbon's Dias do Lixo were not checked.
- Spanish and Brazilian municipal waste portals were not surveyed. The HA integration is simply silent on them.
