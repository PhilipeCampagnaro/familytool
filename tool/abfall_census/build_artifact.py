#!/usr/bin/env python3
"""Builds abfall_coverage.html from census_states.json, probe_results.json and growth.json."""
import json, html, datetime, re, os
S = os.path.dirname(os.path.abspath(__file__))
census = json.load(open(f"{S}/census_states.json"))
probe = json.load(open(f"{S}/probe_results.json")) if os.path.exists(f"{S}/probe_results.json") else {"results": []}
growth = json.load(open(f"{S}/growth.json")) if os.path.exists(f"{S}/growth.json") else {"candidates": [], "cities": []}

STATES = {
 'BW':'Baden-Württemberg','BY':'Bayern','BE':'Berlin','BB':'Brandenburg','HB':'Bremen','HH':'Hamburg',
 'HE':'Hessen','MV':'Mecklenburg-Vorpommern','NI':'Niedersachsen','NW':'Nordrhein-Westfalen',
 'RP':'Rheinland-Pfalz','SL':'Saarland','SN':'Sachsen','ST':'Sachsen-Anhalt','SH':'Schleswig-Holstein','TH':'Thüringen'}
# Population 2024 (Destatis, thousands) — to size the state tiles honestly.
POP = {'NW':18140,'BY':13370,'BW':11280,'NI':8140,'HE':6390,'RP':4160,'SN':4090,'BE':3780,'SH':2960,
       'BB':2570,'ST':2160,'TH':2110,'HH':1890,'MV':1580,'SL':990,'HB':690}
FAMILY = {'regioit':'regio-iT AbfallNavi','awido':'AWIDO / Cubefour','jumomind':'Jumomind / MyMuell',
          'abfallio':'abfall.io (legacy)','ctrace':'C-Trace','awgbassum':'AWG Bassum','bsr':'BSR Berlin'}

probe_by = {r['provider']: r for r in probe.get('results', [])}
providers = census['providers']
THIS_YEAR = datetime.date.today().year
NEXT_YEAR = THIS_YEAR + 1


def esc(x): return html.escape(str(x if x is not None else ''))

# --- per-state aggregation ---------------------------------------------------
st = {c: {'providers': set(), 'towns': 0, 'names': []} for c in STATES}
for p in providers:
    for t in p['towns']:
        code = t.get('state') or p.get('state')
        if code in st:
            st[code]['towns'] += 1
            st[code]['providers'].add(p['id'])
for p in providers:
    for c in {t.get('state') or p.get('state') for t in p['towns']}:
        if c in st: st[c]['names'].append(p.get('displayName') or p['name'])

total_towns = sum(len(p['towns']) for p in providers)
alive = [p for p in providers if len(p['towns']) > 0]
probed_ok = [r for r in probe.get('results', []) if not r.get('error') and (r.get('events') or 0) > 0]
probed_bad = [r for r in probe.get('results', []) if r.get('error') or (r.get('events') or 0) == 0]
states_covered = [c for c in STATES if st[c]['towns'] > 0]
pop_total = sum(POP.values()); pop_cov = sum(POP[c] for c in states_covered)

# --- state tiles -------------------------------------------------------------
def tile(code):
    d = st[code]; n = d['towns']
    level = 'none' if n == 0 else 'thin' if n < 30 else 'mid' if n < 200 else 'strong'
    provs = sorted(set(d['names']), key=str.lower)
    return f'''<div class="tile {level}" data-state="{code}">
  <div class="tile-head"><span class="code">{code}</span><span class="name">{esc(STATES[code])}</span></div>
  <div class="tile-num">{n:,}<span class="unit">Orte</span></div>
  <div class="tile-sub">{len(d['providers'])} {"Entsorger" if len(d['providers'])!=1 else "Entsorger"} · {POP[code]/1000:.1f} Mio. Einw.</div>
  <details class="tile-list"><summary>{"Wer" if provs else "Niemand"}</summary><ul>{''.join(f'<li>{esc(x)}</li>' for x in provs)}</ul></details>
</div>'''.replace(',', '.')

# --- cities table ------------------------------------------------------------
def city_rows():
    rows = []
    for c in growth.get('cities', []):
        status = c.get('status', 'missing')
        pill = {'covered':'ok','missing':'bad','partial':'warn','planned':'warn'}.get(status,'bad')
        label = {'covered':'abgedeckt','missing':'fehlt','partial':'teilweise','planned':'in Arbeit'}.get(status,status)
        rows.append(f'<tr><td>{esc(c["city"])}</td><td class="mono">{esc(c.get("state",""))}</td><td class="mono num">{esc(c.get("pop",""))}</td>'
                    f'<td><span class="pill {pill}">{label}</span></td><td class="muted">{esc(c.get("via",""))}</td><td class="muted">{esc(c.get("note",""))}</td></tr>')
    return ''.join(rows)

# --- providers table ---------------------------------------------------------
def prov_rows():
    rows = []
    for p in sorted(providers, key=lambda p: ((p.get('state') or 'ZZ'), (p.get('displayName') or p['name']).lower())):
        r = probe_by.get(p['id'])
        n = len(p['towns'])
        if n == 0: status, label = 'bad', 'tot (0 Orte)'
        elif r is None: status, label = 'muted', 'nicht getestet'
        elif r.get('error'): status, label = 'bad', 'Fehler'
        elif (r.get('events') or 0) == 0: status, label = 'warn', '0 Termine'
        else: status, label = 'ok', f'{r["events"]} Termine'
        detail = ''
        if r and not r.get('error') and r.get('town'):
            detail = f'{esc(r.get("town"))}{", " + esc(r.get("street")) if r.get("street") else ""} · {esc(r.get("from",""))[:10]} – {esc(r.get("to",""))[:10]}'
        elif r and r.get('error'):
            detail = esc(r['error'])[:140]
        towns_preview = ', '.join(t['name'] for t in p['towns'][:6]) + (' …' if n > 6 else '')
        rows.append(f'<tr data-family="{p["family"]}" data-state="{esc(p.get("state") or "")}" data-search="{esc((p.get("displayName") or p["name"]).lower())} {esc(" ".join(t["name"].lower() for t in p["towns"]))}">'
                    f'<td><div class="pname">{esc(p.get("displayName") or p["name"])}</div><div class="muted small mono">{esc(p["id"])}</div></td>'
                    f'<td class="mono">{esc(p.get("state") or "–")}</td><td>{esc(FAMILY.get(p["family"], p["family"]))}</td>'
                    f'<td class="num mono">{n}</td><td><span class="pill {status}">{label}</span><div class="muted small">{detail}</div></td>'
                    f'<td class="muted small towns">{esc(towns_preview)}</td></tr>')
    return ''.join(rows)

def rollover_rows():
    import collections
    by = collections.defaultdict(lambda: [0, 0])
    for r in probe.get('results', []):
        if not r.get('events'):
            continue
        by[r['family']][0] += 1
        if (r.get('to') or '') >= f'{THIS_YEAR + 1}-01-01':
            by[r['family']][1] += 1
    out = []
    for fam, (live, ahead) in sorted(by.items(), key=lambda kv: -kv[1][0]):
        pct = f'{round(100 * ahead / live)}\u2009%' if live else '–'
        out.append(
            f'<tr><td><code>{esc(fam)}</code></td><td class="num">{live}</td>'
            f'<td class="num">{ahead}</td><td class="num">{pct}</td></tr>'
        )
    return '\n'.join(out)

def growth_rows():
    rows = []
    for g in growth.get('candidates', []):
        rows.append(f'<tr><td><div class="pname">{esc(g["name"])}</div><div class="muted small">{esc(g.get("scope",""))}</div></td>'
                    f'<td class="mono">{esc(g.get("state",""))}</td><td>{esc(g.get("pattern",""))}</td>'
                    f'<td><span class="pill {esc(g.get("effortClass","muted"))}">{esc(g.get("effort",""))}</span></td><td class="muted">{esc(g.get("why",""))}</td></tr>')
    return ''.join(rows)

fam_counts = {}
for p in providers:
    fam_counts.setdefault(p['family'], [0, 0]); fam_counts[p['family']][0] += 1; fam_counts[p['family']][1] += len(p['towns'])
fam_chips = ''.join(f'<button class="chip" data-fam="{f}" type="button" id="fam-{f}">{esc(FAMILY.get(f,f))} <b>{c[0]}</b> · {c[1]} Orte</button>' for f, c in sorted(fam_counts.items(), key=lambda kv: -kv[1][1]))

today = datetime.date.today().strftime('%d.%m.%Y')
_live = [r for r in probe.get('results', []) if r.get('events')]
live_n = len(_live)
ahead_n = len([r for r in _live if (r.get('to') or '') >= f'{NEXT_YEAR}-01-01'])
this_year, next_year = THIS_YEAR, NEXT_YEAR

page = f'''<title>Abfall Coverage</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Manrope:wght@500;700;800&family=IBM+Plex+Sans:wght@400;500;600&family=IBM+Plex+Mono:wght@400;500&display=swap">
<style>
:root {{
  --bg:#F6F7F4; --paper:#FFFFFF; --ink:#1B1F1A; --ink2:#4A514B; --muted:#6F766F; --line:#E1E5DF; --line2:#CDD3CB;
  --accent:#6D4C41; --accent-ink:#FFFFFF; --accent-soft:#EFE6E2;
  --ok:#2E7D4F; --ok-soft:#E1F1E7; --warn:#9A6B00; --warn-soft:#FBF0D3; --bad:#B3372B; --bad-soft:#F8E3E0;
  --t0:#EEF0EC; --t1:#E4EBE2; --t2:#CFE0CF; --t3:#B4D0B7;
}}
@media (prefers-color-scheme: dark) {{ :root:not([data-theme="light"]) {{
  --bg:#141715; --paper:#1C201D; --ink:#EDEFEA; --ink2:#C3C8C1; --muted:#8E958E; --line:#2A302B; --line2:#3A423B;
  --accent:#C9A28F; --accent-ink:#1B1F1A; --accent-soft:#2E2622;
  --ok:#7CC69A; --ok-soft:#1E3327; --warn:#E3BD5E; --warn-soft:#3A2F14; --bad:#F0877B; --bad-soft:#3E1F1B;
  --t0:#1F2420; --t1:#233026; --t2:#294332; --t3:#33593F;
}} }}
:root[data-theme="dark"] {{
  --bg:#141715; --paper:#1C201D; --ink:#EDEFEA; --ink2:#C3C8C1; --muted:#8E958E; --line:#2A302B; --line2:#3A423B;
  --accent:#C9A28F; --accent-ink:#1B1F1A; --accent-soft:#2E2622;
  --ok:#7CC69A; --ok-soft:#1E3327; --warn:#E3BD5E; --warn-soft:#3A2F14; --bad:#F0877B; --bad-soft:#3E1F1B;
  --t0:#1F2420; --t1:#233026; --t2:#294332; --t3:#33593F;
}}
* {{ box-sizing:border-box }}
body {{ background:var(--bg); color:var(--ink); font-family:"IBM Plex Sans",system-ui,sans-serif; font-size:15px; line-height:1.5; margin:0; padding-block:28px 64px; padding-inline:clamp(16px,4vw,48px); }}
h1,h2,h3 {{ font-family:Manrope,"IBM Plex Sans",sans-serif; text-wrap:balance; margin:0 }}
h1 {{ font-size:clamp(28px,4vw,40px); font-weight:800; letter-spacing:-.02em; line-height:1.1 }}
h2 {{ font-size:20px; font-weight:700; margin-block:40px 14px; display:flex; align-items:baseline; gap:12px }}
h2 .eyebrow {{ font:500 11px/1 "IBM Plex Mono",monospace; letter-spacing:.12em; text-transform:uppercase; color:var(--muted) }}
p {{ max-width:68ch; margin:0 }}
.lede {{ color:var(--ink2); font-size:16px; margin-top:10px }}
.meta {{ font:500 12px "IBM Plex Mono",monospace; color:var(--muted); letter-spacing:.04em; margin-top:14px }}
.mono {{ font-family:"IBM Plex Mono",monospace; font-size:13px }}
.num {{ font-variant-numeric:tabular-nums; text-align:right }}
.muted {{ color:var(--muted) }} .small {{ font-size:12.5px }}
.stats {{ display:grid; grid-template-columns:repeat(auto-fit,minmax(150px,1fr)); gap:10px; margin-top:26px }}
.stat {{ background:var(--paper); border:1px solid var(--line); border-radius:12px; padding:14px 16px }}
.stat .v {{ font:800 30px/1.05 Manrope,sans-serif; letter-spacing:-.02em; font-variant-numeric:tabular-nums }}
.stat .l {{ color:var(--muted); font-size:12.5px; margin-top:6px }}
.stat.accent .v {{ color:var(--accent) }} .stat.ok .v {{ color:var(--ok) }} .stat.bad .v {{ color:var(--bad) }}
.grid {{ display:grid; grid-template-columns:repeat(auto-fill,minmax(190px,1fr)); gap:10px }}
.tile {{ border-radius:12px; padding:14px 14px 10px; border:1px solid var(--line); background:var(--t0); display:flex; flex-direction:column; gap:4px; min-width:0 }}
.tile.thin {{ background:var(--t1) }} .tile.mid {{ background:var(--t2) }} .tile.strong {{ background:var(--t3) }}
.tile.none {{ background:var(--paper); border-style:dashed; border-color:var(--line2) }}
.tile-head {{ display:flex; gap:8px; align-items:baseline; min-width:0 }}
.tile .code {{ font:500 12px "IBM Plex Mono",monospace; color:var(--muted) }}
.tile .name {{ font-weight:600; font-size:13.5px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis }}
.tile-num {{ font:800 26px/1.1 Manrope,sans-serif; letter-spacing:-.02em; font-variant-numeric:tabular-nums; margin-top:4px }}
.tile-num .unit {{ font:500 12px "IBM Plex Sans",sans-serif; color:var(--muted); margin-left:6px; letter-spacing:0 }}
.tile.none .tile-num {{ color:var(--bad) }}
.tile-sub {{ color:var(--ink2); font-size:12.5px }}
.tile-list summary {{ cursor:pointer; color:var(--muted); font-size:12px; margin-top:4px; list-style:none }}
.tile-list summary::after {{ content:" ▾" }} .tile-list[open] summary::after {{ content:" ▴" }}
.tile-list ul {{ margin:6px 0 0; padding-left:16px; font-size:12.5px; color:var(--ink2) }}
.legend {{ display:flex; flex-wrap:wrap; gap:14px; margin-top:12px; font-size:12.5px; color:var(--muted) }}
.legend i {{ display:inline-block; width:14px; height:14px; border-radius:4px; vertical-align:-2px; margin-right:6px; border:1px solid var(--line) }}
.tablewrap {{ overflow-x:auto; border:1px solid var(--line); border-radius:12px; background:var(--paper) }}
table {{ border-collapse:collapse; width:100%; font-size:14px }}
th {{ text-align:left; font:600 11.5px "IBM Plex Mono",monospace; letter-spacing:.08em; text-transform:uppercase; color:var(--muted); padding:10px 12px; border-bottom:1px solid var(--line); background:var(--paper); position:sticky; top:env(safe-area-inset-top,0px) }}
td {{ padding:10px 12px; border-bottom:1px solid var(--line); vertical-align:top }}
tr:last-child td {{ border-bottom:0 }}
.pname {{ font-weight:600 }}
.towns {{ max-width:340px }}
.pill {{ display:inline-block; font:600 12px/1 "IBM Plex Sans",sans-serif; padding:5px 9px; border-radius:999px; white-space:nowrap }}
.pill.ok {{ background:var(--ok-soft); color:var(--ok) }} .pill.warn {{ background:var(--warn-soft); color:var(--warn) }}
.pill.bad {{ background:var(--bad-soft); color:var(--bad) }} .pill.muted {{ background:var(--t0); color:var(--muted) }}
.pill.accent {{ background:var(--accent-soft); color:var(--accent) }}
.toolbar {{ display:flex; flex-wrap:wrap; gap:8px; align-items:center; margin-bottom:12px }}
.toolbar input {{ flex:1 1 220px; font:inherit; padding:9px 12px; border-radius:10px; border:1px solid var(--line2); background:var(--paper); color:var(--ink) }}
.toolbar input:focus {{ outline:2px solid var(--accent); outline-offset:1px }}
.chip {{ font:500 12.5px "IBM Plex Sans",sans-serif; padding:7px 11px; border-radius:999px; border:1px solid var(--line2); background:var(--paper); color:var(--ink2); cursor:pointer }}
.chip b {{ color:var(--ink) }} .chip[aria-pressed="true"] {{ background:var(--accent); color:var(--accent-ink); border-color:var(--accent) }} .chip[aria-pressed="true"] b {{ color:inherit }}
.chip:focus-visible {{ outline:2px solid var(--accent); outline-offset:2px }}
.note {{ background:var(--paper); border:1px solid var(--line); border-left:4px solid var(--accent); border-radius:10px; padding:14px 16px; max-width:80ch }}
.note code, .howto code {{ font:500 12.5px "IBM Plex Mono",monospace; background:var(--t0); padding:2px 5px; border-radius:4px }}
.howto {{ display:grid; grid-template-columns:repeat(auto-fit,minmax(260px,1fr)); gap:10px }}
.howto div {{ background:var(--paper); border:1px solid var(--line); border-radius:12px; padding:14px 16px; font-size:14px }}
.howto h3 {{ font-size:14px; margin-bottom:6px }}
.count {{ color:var(--muted); font-size:13px; font-weight:400 }}
@media (max-width:520px) {{ .towns {{ display:none }} }}
</style>

<header>
  <h1>Abfall Coverage</h1>
  <p class="lede">Welche Müllabfuhr-Kalender Aporah heute aus der Adresse heraus verbinden kann — pro Bundesland, pro Entsorger, pro Großstadt — und was als Nächstes fehlt. Live-Zensus der Vendor-APIs, nicht die Registry-Liste.</p>
  <div class="meta">Stand {today} · Zensus aus <code>abfall_providers.ts</code> + Live-Abfrage aller Vendor-Endpunkte · Sonde: eine echte Adresse pro Entsorger</div>
  <div class="stats">
    <div class="stat accent"><div class="v">{len(alive)}<span class="count"> / {len(providers)}</span></div><div class="l">Entsorger antworten (Registry-Einträge)</div></div>
    <div class="stat"><div class="v">{total_towns:,}</div><div class="l">Orte mit Straßenlisten</div></div>
    <div class="stat"><div class="v">{len(states_covered)}<span class="count"> / 16</span></div><div class="l">Bundesländer mit mindestens einem Ort</div></div>
    <div class="stat"><div class="v">{100*pop_cov/pop_total:.0f} %</div><div class="l">der Bevölkerung lebt in einem Land mit Abdeckung (nicht: ist abgedeckt)</div></div>
    <div class="stat ok"><div class="v">{len(probed_ok)}</div><div class="l">Entsorger liefern live Termine</div></div>
    <div class="stat bad"><div class="v">{len(probed_bad) + (len(providers)-len(alive) if not probe.get('results') else 0)}</div><div class="l">liefern nichts oder Fehler — siehe Tabelle</div></div>
  </div>
</header>

<h2><span class="eyebrow">01</span>Bundesländer</h2>
<div class="grid">{''.join(tile(c) for c in sorted(STATES, key=lambda c: -st[c]['towns']))}</div>
<div class="legend"><span><i style="background:var(--paper);border-style:dashed"></i>nichts</span><span><i style="background:var(--t1)"></i>unter 30 Orte</span><span><i style="background:var(--t2)"></i>30–199</span><span><i style="background:var(--t3)"></i>200+</span></div>

<h2><span class="eyebrow">02</span>Die großen Städte <span class="count">Einwohner in Tsd.</span></h2>
<div class="tablewrap"><table><thead><tr><th>Stadt</th><th>Land</th><th class="num">Einw.</th><th>Status</th><th>Über</th><th>Anmerkung</th></tr></thead><tbody>{city_rows()}</tbody></table></div>

<h2><span class="eyebrow">03</span>Entsorger <span class="count" id="provcount"></span></h2>
<div class="toolbar"><input id="q" type="search" placeholder="Ort oder Entsorger suchen … (z. B. Stuhr, Gießen, Prignitz)" aria-label="Suchen">{fam_chips}</div>
<div class="tablewrap"><table id="provs"><thead><tr><th>Entsorger</th><th>Land</th><th>Familie</th><th class="num">Orte</th><th>Live-Sonde</th><th>Orte (Auszug)</th></tr></thead><tbody>{prov_rows()}</tbody></table></div>

<h2><span class="eyebrow">04</span>Wachstum: was als Nächstes</h2>
<div class="note"><p>Reihenfolge, wie sie sich aus dem Zensus ergibt: erst die Plattformen, die viele Kommunen auf einmal bringen, dann die Stadtstaaten und Millionenstädte, die je einen eigenen Adapter kosten. Was Haushalte über <b>„Anfragen“</b> melden, wandert in <code>abfall_requests</code> und steht über allem hier — ein Ort, den drei Familien wollen, schlägt eine Großstadt, die niemand fragt.</p></div>
<div class="tablewrap" style="margin-top:12px"><table><thead><tr><th>Kandidat</th><th>Land</th><th>Muster</th><th>Aufwand</th><th>Warum</th></tr></thead><tbody>{growth_rows()}</tbody></table></div>

<h2><span class="eyebrow">05</span>Der Jahreswechsel</h2>
<div class="note"><p>Die meisten Entsorger veröffentlichen <b>genau ein Kalenderjahr</b>. Heute reichen {ahead_n} von {live_n} live geprüften Abfuhrplänen über den 31.&nbsp;Dezember {this_year} hinaus — der Rest endet dort. Das ist trotzdem kein Ablaufdatum: <b>wir speichern keinen Kalender und keinen Link</b>, sondern fragen den Entsorger bei jeder Aktualisierung neu. Das Jahr, das er dann ausliefert, ist das Jahr, das die Familie sieht. Niemand muss etwas neu verbinden, und keine Datei muss noch einmal hochgeladen werden.</p>
<p>Fünf Städte zeigen die drei Bauarten. <b>Köln</b> nimmt <code>start_year</code>/<code>end_year</code> als freie Parameter, also fragen wir immer <i>dieses und nächstes</i> Jahr ab; {next_year} ist heute eine gültige, leere Antwort und füllt sich von selbst, sobald der AWB den Plan freischaltet — <b>ohne Lücke</b>. <b>München</b> kann das nicht: der ICS-Link ist mit einem <code>cHash</code> pro Jahr signiert, ein von Hand geändertes Jahr ergibt 404, und das Formular ignoriert ein mitgeschicktes Jahr. Dort entscheidet allein der AWM. Dass er mitwandert, ist belegt: archivierte, korrekt signierte Links von <b>2022 und 2024</b> liefern bis heute ihr ICS aus, und dasselbe Formular gab im Januar 2024 <code>year=2024</code> und gibt jetzt <code>year={this_year}</code> aus.</p>
<p><b>Hamburg und Stuttgart</b> zeigen die dritte und einfachste Bauart: die Stadtreinigung kennt gar kein Jahr. Ihr Feed ist ein <b>rollierendes Fenster von rund vier Monaten ab heute</b> — die Abfrage von heute reicht bereits bis in den Januar {next_year} — und wandert damit jeden Tag ein Stück weiter. Ein Jahreswechsel findet dort schlicht nicht statt. Der Preis dafür ist die Gegenrichtung: weiter als vier Monate voraus sieht in Hamburg niemand, auch die Stadtreinigung selbst nicht. <b>Stuttgart</b> macht es genauso, einen Monat kürzer — rund drei Monate ab dem Tag der Abfrage, ohne Jahresparameter und ohne etwas, das umspringen könnte.</p>
<p><b>Düsseldorf</b> liegt dazwischen und ist der sauberste Fall von allen: der Feed läuft vom Montag dieser Woche bis zum <b>31. Dezember</b>, kennt keinen Jahresparameter — und die Adresse ist eine UUID, die den Jahreswechsel überlebt. Das ist nicht vermutet, sondern nachgemessen: eine im <b>Dezember 2025</b> vom Internet Archive erfasste Kalender-UUID liefert heute den Plan für {this_year}. Niemand muss dort etwas neu verbinden.</p>
<p><b>Was zu prüfen bleibt</b>, und zwar im Dezember: wann genau ein Einjahres-Entsorger umschaltet. Schaltet er spät, ist der Vorlauf im Dezember kurz; schaltet er früh, verschwindet der Rest des laufenden Jahres. Beides lässt sich von hier aus nicht erzwingen — nur nachsehen.</p></div>
<div class="tablewrap" style="margin-top:12px"><table><thead><tr><th>Familie</th><th class="num">live</th><th class="num">reicht bis {next_year}</th><th class="num">Anteil</th></tr></thead><tbody>{rollover_rows()}</tbody></table></div>

<h2><span class="eyebrow">06</span>So bleibt die Seite wahr</h2>
<div class="howto">
  <div><h3>Zensus neu ziehen</h3>Nach jeder Änderung an <code>abfall_providers.ts</code>: <code>deno run --allow-net --allow-read --allow-write --allow-env census.ts</code>, dann Zustandszuordnung und Sonde; die Seite wird aus den drei JSON-Dateien gebaut.</div>
  <div><h3>Offene Anfragen</h3><code>select town, postcode, state, count(*) from abfall_requests where status = 'open' group by 1,2,3 order by 4 desc</code> — das ist die Arbeitsliste. Nach dem Ausliefern <code>status = 'done'</code> und <code>resolved_provider</code> setzen.</div>
  <div><h3>Was „abgedeckt“ heißt</h3>Ein Ort zählt, wenn der Entsorger ihn in seiner Ortsliste führt. Eine Straße darin kann trotzdem fehlen — die Adresse wird erst beim Verbinden gegen die Straßenliste geprüft.</div>
</div>

<script>
(function(){{
  var q=document.getElementById('q'), rows=[].slice.call(document.querySelectorAll('#provs tbody tr')), chips=[].slice.call(document.querySelectorAll('.chip')), count=document.getElementById('provcount');
  var fam=null;
  function apply(){{
    var s=(q.value||'').trim().toLowerCase(), n=0;
    rows.forEach(function(r){{
      var ok=(!fam||r.dataset.family===fam)&&(!s||r.dataset.search.indexOf(s)>=0);
      r.hidden=!ok; if(ok) n++;
    }});
    count.textContent=n+' von '+rows.length;
  }}
  chips.forEach(function(c){{ c.setAttribute('aria-pressed','false'); c.addEventListener('click',function(){{ fam=(fam===c.dataset.fam)?null:c.dataset.fam; chips.forEach(function(x){{x.setAttribute('aria-pressed',String(x.dataset.fam===fam));}}); apply(); }}); }});
  q.addEventListener('input',apply);
  try {{ var saved=localStorage.getItem('abfall-q'); if(saved) q.value=saved; }} catch(e) {{}}
  q.addEventListener('change',function(){{ try {{ localStorage.setItem('abfall-q',q.value); }} catch(e) {{}} }});
  apply();
}})();
</script>
'''
open(f"{S}/abfall_coverage.html", "w").write(page)
print("built", len(page), "bytes;", len(providers), "providers", total_towns, "towns", len(states_covered), "states")
