#!/usr/bin/env python3
"""Builds abfall_coverage.html from census_states.json, probe_results.json and growth.json."""
import json, html, datetime, re, os
S = os.path.dirname(os.path.abspath(__file__))
census = json.load(open(f"{S}/census_states.json"))
probe = json.load(open(f"{S}/probe_results.json")) if os.path.exists(f"{S}/probe_results.json") else {"results": []}
growth = json.load(open(f"{S}/growth.json")) if os.path.exists(f"{S}/growth.json") else {"candidates": [], "cities": []}
# Hand-kept per city: test addresses, the vendor's own page, a known caveat.
city_meta = json.load(open(f"{S}/city_meta.json")) if os.path.exists(f"{S}/city_meta.json") else {}
# Written by city_check.ts: each test address run live through the resolver.
city_checks = json.load(open(f"{S}/city_checks.json")) if os.path.exists(f"{S}/city_checks.json") else {}

STATES = {
 'BW':'Baden-Württemberg','BY':'Bayern','BE':'Berlin','BB':'Brandenburg','HB':'Bremen','HH':'Hamburg',
 'HE':'Hessen','MV':'Mecklenburg-Vorpommern','NI':'Niedersachsen','NW':'Nordrhein-Westfalen',
 'RP':'Rheinland-Pfalz','SL':'Saarland','SN':'Sachsen','ST':'Sachsen-Anhalt','SH':'Schleswig-Holstein','TH':'Thüringen'}
# Population 2024 (Destatis, thousands) — to size the state tiles honestly.
POP = {'NW':18140,'BY':13370,'BW':11280,'NI':8140,'HE':6390,'RP':4160,'SN':4090,'BE':3780,'SH':2960,
       'BB':2570,'ST':2160,'TH':2110,'HH':1890,'MV':1580,'SL':990,'HB':690}
FAMILY = {'regioit':'regio-iT AbfallNavi','awido':'AWIDO / Cubefour','jumomind':'Jumomind (Behörden-Apps)',
          'abfallio':'abfall.io (legacy)','ctrace':'C-Trace','awgbassum':'AWG Bassum','bsr':'BSR Berlin',
          'fes':'FES Frankfurt','awm':'AWM München','awbkoeln':'AWB Köln','srh':'Stadtreinigung Hamburg',
          'awsstuttgart':'AWS Stuttgart','awista':'AWISTA Düsseldorf','srl':'Stadtreinigung Leipzig',
          'athos':'Athos WasteManagement','abfallplus':'AbfallPlus v3 (GraphQL)','srdd':'Stadtreinigung Dresden',
          'aha':'aha Region Hannover','awgwuppertal':'AWG Wuppertal','insertit':'Insert IT BmsAbfallkalender',
          'abki':'ABK Kiel','wuerzburg':'Stadt Würzburg (Open Data)','avea':'AVEA Leverkusen',
          'oldenburg':'Stadt Oldenburg',
          'art':'A.R.T. Trier','waswob':'WAS Wolfsburg','albabs':'ALBA Braunschweig','elw':'ELW Wiesbaden','fuerth':'Stadt Fürth',
          'heilbronn':'Stadt Heilbronn','abis':'ABIS (flynet)','enni':'ENNI Moers','muellmax':'Müllmax (von der Stadt eingebunden)','hws':'HWS Halle','ksj':'KSJ Jena','tsk':'TSK Karlsruhe','hausmuell':'hausmuell.info (aturis)','sab':'SAB Magdeburg','swp':'SWP Potsdam','osb':'OSB Osnabrück','meinabfall':'Mein-Abfallkalender'}

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
probed_bad = [r for r in probe.get('results', []) if r.get('error') or ((r.get('events') or 0) == 0 and not r.get('upload'))]
probed_upload = [r for r in probe.get('results', []) if r.get('upload') and not r.get('error')]
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
def slug(city):
    t = city.lower()
    for a, b in (('ä','ae'),('ö','oe'),('ü','ue'),('ß','ss')): t = t.replace(a, b)
    return re.sub(r'[^a-z0-9]+', '-', t).strip('-')

def city_status(c):
    """The census counts a city when a vendor lists its name; the live check
    overrules that when not one real address there resolves. A city whose
    source we may not fetch (terms or robots.txt) is served by upload only."""
    if c['city'] in UPLOAD_CITIES: return 'upload'
    status = c.get('status', 'missing')
    chk = city_checks.get(c['city'])
    if status == 'covered' and chk and not any(x['outcome'] in ('ok', 'pick') for x in chk['checks']) \
            and not city_meta.get(c['city'], {}).get('outage'):
        return 'listed'
    return status

def trust(c):
    """(pill class, label, reason) — from the live check plus the hand note."""
    chk = city_checks.get(c['city']); note = (city_meta.get(c['city'], {}).get('note') or '').strip()
    if not chk: return ('muted', 'ungeprüft', note)
    outs = [x['outcome'] for x in chk['checks']]
    if not chk.get('fakeRefused', True):
        return ('bad', 'Prüfen', 'Eine erfundene Straße bekam einen Kalender — Gefahr falscher Termine.')
    if not any(o == 'ok' for o in outs):
        return ('bad', 'Prüfen', note or 'Keine Testadresse liefert Termine.')
    if note or any(o in ('none', 'error') for o in outs):
        return ('warn', 'Mit Einschränkung', note or 'Eine Testadresse wird nicht gefunden.')
    return ('ok', 'Verlässlich', 'Jede Testadresse liefert Termine, eine erfundene Straße wird abgelehnt.')

def test_lines(c):
    chk = {x['address']: x for x in city_checks.get(c['city'], {}).get('checks', [])}
    out = []
    for t in city_meta.get(c['city'], {}).get('tests', []):
        addr = f"{t['street']} {t['nr']}".strip()
        x = chk.get(f"{addr}, {t['plz']} {c['city']}")
        if not x: res, cls = '', 'muted'
        elif x['outcome'] == 'ok': res, cls = f"✓ {x.get('events', 0)} Termine", 'ok'
        elif x['outcome'] == 'pick': res, cls = 'fragt nach Hausnummer', 'warn'
        elif x['outcome'] == 'none': res, cls = '✗ nicht gefunden', 'bad'
        else: res, cls = f"✗ {x.get('error') or 'Fehler'}", 'bad'
        out.append(f'<div class="taddr"><span class="mono">{esc(addr)}, {esc(t["plz"])}</span> <span class="tres {cls}">{esc(res)}</span></div>')
    return ''.join(out)

def rhythm_pill(c):
    bins = (city_meta.get(c['city'], {}).get('rhythm') or {}).get('bins') or []
    if not bins: return ''
    if len(bins) > 1: return f' <span class="pill accent multi">Rhythmus-Frage × {len(bins)} Tonnen</span>'
    return ' <span class="pill accent">Rhythmus-Frage</span>'

def rhythm_box():
    """The cities that ask the household for its bins' rhythm, several bins first."""
    rows = []
    items = [(c, city_meta[c]['rhythm']) for c in city_meta
             if (city_meta[c].get('rhythm') or {}).get('bins') and c not in UPLOAD_CITIES]
    items.sort(key=lambda x: (-len(x[1]['bins']), x[0]))
    for city, r in items:
        multi = len(r['bins']) > 1
        head = (f'<span class="pill accent multi">{len(r["bins"])} Tonnen — zuerst testen</span>' if multi
                else '<span class="pill muted">1 Tonne</span>')
        rows.append(f'<tr class="{"multi" if multi else ""}"><td class="pname">{esc(city)}</td><td>{head}<div class="why">{esc(" · ".join(r["bins"]))}</div></td>'
                    f'<td class="mono">{esc(r["test"])}</td><td>{esc(r["expect"])}</td></tr>')
    n_multi = sum(1 for _, r in items if len(r['bins']) > 1)
    return (f'<h3 class="sub">Rhythmus-Frage testen <span class="count">{len(items)} Städte · {n_multi} mit mehreren Tonnen</span></h3>'
            '<div class="note"><p>Diese Städte drucken jeden Rhythmus einer Tonne nebeneinander oder fragen ihn selbst ab. '
            'Die App fragt deshalb beim Verbinden „… — wie oft geleert?“, mit genau den Optionen, die die Adresse hat. '
            '<b>Hervorgehoben: mehrere Tonnen in einer Frage</b> — da muss jede Tonne einzeln beantwortet werden, sonst lässt die App nicht verbinden. '
            'Test: Adresse eingeben, jede Frage beantworten, im Kalender prüfen, dass pro Tonne nur der gewählte Rhythmus erscheint.</p></div>'
            '<div class="tablewrap"><table class="rhythm"><thead><tr><th>Stadt</th><th>Fragt nach</th><th>Testadresse</th><th>Was erscheinen soll</th></tr></thead>'
            f'<tbody>{"".join(rows)}</tbody></table></div>')

# Written by hand from a live check of each city's own page: whose domain the
# calendar is read from, and whether the city itself still points there.
third = json.load(open(f"{S}/third_party.json")) if os.path.exists(f"{S}/third_party.json") else {}
# Served by upload only since 2026-09-19: the source's terms or robots.txt rule
# out fetching, so the app recognises the town and sends it to the file upload.
UPLOAD_CITIES = {c for c, v in (third.get('terms') or {}).items() if v.get('fix', '').startswith('Upload')}

def third_box():
    vd = third.get('vendor_domain') or {}
    if not vd: return ''
    order = {'elsewhere': 0, 'open': 1, 'ok': 2}
    items = sorted(vd.items(), key=lambda kv: (order.get(kv[1]['status'], 1), kv[1]['vendor'], kv[0]))
    PILL = {'ok': '<span class="pill ok">Auf der Stadtseite eingebunden</span>',
            'open': '<span class="pill warn">Nicht bestätigt — von Hand prüfen</span>',
            'elsewhere': '<span class="pill bad">Stadt zeigt woanders hin</span>'}
    rows = []
    for city, v in items:
        ev = (f'<a href="{esc(v["url"])}" target="_blank" rel="noopener">Seite der Stadt</a>' if v.get('url') else '–')
        note = f'<div class="why">{esc(v["note"])}</div>' if v.get('note') else ''
        rows.append(f'<tr><td class="pname">{esc(city)}</td><td>{esc(v["vendor"])}<div class="why mono">{esc(v["host"])}</div></td>'
                    f'<td>{PILL.get(v["status"], esc(v["status"]))}{note}</td><td>{ev}</td></tr>')
    n_ok = sum(1 for v in vd.values() if v['status'] == 'ok')
    n_open = sum(1 for v in vd.values() if v['status'] == 'open')
    n_else = sum(1 for v in vd.values() if v['status'] == 'elsewhere')
    own = third.get('own_domain_vendor_software') or {}
    moved = third.get('moved_off') or {}
    fams = {}
    for v in vd.values(): fams[v['vendor']] = fams.get(v['vendor'], 0) + 1
    fam_line = ' · '.join(f'{esc(k)} <b>{n}</b>' for k, n in sorted(fams.items(), key=lambda kv: -kv[1]))
    own_line = ', '.join(f'{esc(c)} ({esc(t)})' for c, t in own.items())
    moved_line = ''.join(f'<p><span class="pill ok">Umgestellt · {esc(c)}</span> {esc(t)}</p>' for c, t in moved.items())
    return (f'<h2><span class="eyebrow">02b</span>Drittanbieter <span class="count">{len(vd)} Städte über eine Anbieter-Domain · {n_ok} bestätigt · {n_open} offen · {n_else} zeigen woanders hin</span></h2>'
            '<div class="note"><p>Bei diesen Städten lesen wir die Termine nicht von einer Domain der Stadt, sondern vom Software-Anbieter, den die Stadt beauftragt hat. '
            'Das ist erlaubt, solange <b>die Stadt selbst</b> ihn auf ihrer Abfallseite einbindet — dann ist er ihr offizieller Kalender. '
            'Das Risiko ist ein anderes als bei einer eigenen Stadtseite: <b>wechselt die Stadt den Anbieter, antwortet der alte oft weiter — nur leer oder veraltet</b> '
            '(so ist Güterslohs eigene AbfallNavi-Instanz heute eine leere Hülle). Deshalb steht hier, ob die Stadtseite heute noch auf genau diesen Anbieter zeigt '
            f'(geprüft {esc(third.get("checked", ""))}). <b>Offen</b> heißt: im Seitenquelltext nicht gefunden, meist weil das Widget per JavaScript nachlädt — bitte einmal im Browser ansehen.</p>'
            f'<p>{fam_line}</p>{moved_line}'
            f'<p><b>Eigene Domain, fremde Software</b> (kein Drittanbieter-Risiko beim Abruf, die Stadt betreibt es selbst): {own_line}. '
            'Alle übrigen abgedeckten Großstädte werden direkt von der Seite der Stadt oder ihres Entsorgers gelesen.</p></div>'
            '<div class="tablewrap" style="margin-top:12px"><table class="rhythm"><thead><tr><th>Stadt</th><th>Anbieter · Host</th><th>Offiziell?</th><th>Beleg</th></tr></thead>'
            f'<tbody>{"".join(rows)}</tbody></table></div>')

def terms_box():
    T = third.get('terms') or {}
    if not T: return ''
    def rank(v):
        if v['verdict'] == 'terms': return 0
        if v['robots']: return 1
        if v['verdict'] == 'open' or v.get('fix'): return 2
        return {'boiler': 3, 'silent': 4}.get(v['verdict'], 5)
    PILL = {'open': '<span class="pill ok">Offene Lizenz</span>',
            'terms': '<span class="pill bad">Echte Bedingung: nicht kommerziell</span>',
            'boiler': '<span class="pill muted">Nur Standard-Urheberrechtsabsatz</span>',
            'silent': '<span class="pill ok">Keine Einschränkung gefunden</span>'}
    rows = []
    for city, v in sorted(T.items(), key=lambda kv: (rank(kv[1]), kv[1]['source'], kv[0])):
        pills = PILL.get(v['verdict'], '')
        if v['robots']: pills += ' <span class="pill bad">robots.txt sperrt unseren Pfad</span>'
        fix = f'<b>{esc(v["fix"])}</b>' if v.get('fix') else '<span class="count">so lassen</span>'
        rows.append(f'<tr><td class="pname">{esc(city)}</td><td>{esc(v["source"])}</td><td>{pills}<div class="why">{esc(v["quote"])}</div></td><td>{fix}</td></tr>')
    n = lambda f: sum(1 for v in T.values() if f(v))
    act = n(lambda v: v['verdict'] == 'terms' or v['robots'])
    return (f'<h2><span class="eyebrow">02c</span>Nutzungsbedingungen <span class="count">{len(T)} Städte gelesen · '
            f'{n(lambda v: v["verdict"] == "terms")} echte Bedingung · {n(lambda v: v["robots"])} robots.txt-Sperre · '
            f'{n(lambda v: v["verdict"] == "open")} offene Lizenz · {n(lambda v: v["verdict"] == "boiler")} nur Standardabsatz · '
            f'{n(lambda v: v["verdict"] == "silent")} nichts</span></h2>'
            '<div class="note"><p>Von jeder Quelle, die wir automatisch abfragen, Impressum, Nutzungsbedingungen, Lizenz und <code>robots.txt</code> gelesen '
            f'({esc(third.get("terms_checked", ""))}), mit wörtlichem Zitat. <b>Kein Anbieter hat Nutzungs- oder API-Bedingungen für die Termine.</b> '
            'Der Satz „nur für den privaten, nicht kommerziellen Gebrauch“ ist ein Muster-Absatz (eRecht24 u. a.), der auf fast jeder deutschen Seite steht und die Texte und Bilder der Website meint — MyMüll ist damit kein Sonderfall.</p>'
            '<p>Was wirklich trennt: <b>(1) echte Bedingungen</b>, die Nutzung ausdrücklich auf nicht kommerziell beschränken (Düsseldorf, Rostock, Dresden), und '
            '<b>(2) robots.txt</b>, mit dem der Betreiber maschinenlesbar sagt, dass genau dieser Pfad nicht automatisch abgerufen werden soll. '
            f'<b>Umgesetzt am 19.09.2026:</b> diese Städte laufen über den Upload-Flow, die App fragt ihren Anbieter nichts mehr ({esc(third.get("upload_checked", ""))}). '
            'Regensburg und Ulm (AWIDO) bleiben live, weil nur der entfernte ICS-Ersatzweg gesperrt war; Würzburg bleibt live, weil die offene Lizenz die Nutzung erlaubt. '
            'Bonn und Moers veröffentlichen dieselben Termine zusätzlich unter offener Lizenz — der Umstieg dort ist Kür, nicht Pflicht. '
            'Keine Rechtsberatung: für den Store-Start einmal von einer Anwältin / einem Anwalt gegenlesen lassen.</p></div>'
            '<div class="tablewrap" style="margin-top:12px"><table class="rhythm"><thead><tr><th>Stadt</th><th>Quelle</th><th>Was dort steht</th><th>Was tun</th></tr></thead>'
            f'<tbody>{"".join(rows)}</tbody></table></div>')

# Tested first, in this order: the city that asks about several bins, then
# everything built since the last deploy. The rest is the big table, one at a time.
NOW = ['Düsseldorf', 'Paderborn', 'Heidelberg', 'Darmstadt', 'Reutlingen', 'Hildesheim', 'Bremerhaven']

def now_box():
    decisions = [(c, m['decision']) for c, m in city_meta.items() if m.get('decision')]
    dec = ''.join(f'<div class="decide"><span class="pill warn">Entscheidung · {esc(c)}</span> {esc(t)}</div>' for c, t in decisions)
    rows = []
    for i, city in enumerate(NOW, 1):
        m = city_meta.get(city, {})
        r = m.get('rhythm') or {}
        bins = r.get('bins') or []
        t = (m.get('tests') or [{}])[0]
        addr = r.get('test') or f"{t.get('street','')} {t.get('nr','')}, {t.get('plz','')}"
        expect = r.get('expect') or m.get('expect') or m.get('note') or ''
        if city in UPLOAD_CITIES:
            ask = '<span class="pill muted">Upload-Flow</span>'
            expect = ('Die Adresse zeigt „Nur als Datei“. Weiter: „Abfallkalender der Stadt öffnen“ und „Kalenderdatei hochladen“ — '
                      'das schließt das Blatt und öffnet den iCal-Upload. Dort die ICS von der Stadtseite wählen; die Termine erscheinen im Kalender.')
        elif len(bins) > 1: ask = f'<span class="pill accent multi">{len(bins)} Tonnen</span><div class="why">{esc(" · ".join(bins))}</div>'
        elif bins: ask = f'<span class="pill accent">Rhythmus-Frage</span><div class="why">{esc(bins[0])}</div>'
        else: ask = '<span class="pill muted">keine Frage</span>'
        if m.get('decision'): ask += ' <span class="pill warn">Entscheidung</span>'
        rows.append(f'<tr class="{"multi" if len(bins) > 1 else ""}"><td class="num mono">{i}</td><td class="pname">{esc(city)}</td><td>{ask}</td>'
                    f'<td class="mono">{esc(addr)} {esc(city)}</td><td>{esc(expect)}</td>'
                    f'<td><label class="tested"><input type="checkbox" data-city="{slug(city)}"><span class="at"></span></label></td></tr>')
    return (f'<h2><span class="eyebrow">00</span>Jetzt für dich <span class="count">1 Entscheidung · {len(NOW)} Städte sofort testen</span></h2>'
            f'{dec}'
            '<div class="note"><p><b>Erst deployen</b> — ohne das kennt die App keine dieser Städte:<br>'
            '<code>npx supabase functions deploy abfall-lookup calendar-feed calendar-events calendar-link calendar-connect calendar-caldav --project-ref uzhzrwakrtwbpuuupccu</code></p>'
            '<p><b>Neu: Upload-Flow.</b> 11 Städte werden nicht mehr abgefragt (echte Nutzungsbedingung oder robots.txt, siehe 02c). '
            'Düsseldorf steht für die Bedingungen, Paderborn für robots.txt — beide einmal durchspielen. '
            '<b>Die Datei ist kostenlos</b>: sie zählt nicht zu den zwei Kalendern des Free-Plans. Test: mit zwei verbundenen Konten trotzdem hochladen — keine Paywall. '
            'Und die Gegenprobe: eine andere .ics (z. B. ein Arbeitskalender) wird dort abgelehnt.</p>'
            '<p><b>Dann in dieser Reihenfolge:</b> Adresse in der App eingeben, jede Frage beantworten, im Kalender die Termine mit der rechten Spalte vergleichen, abhaken. '
            'Der Haken ist derselbe wie in der großen Tabelle unten — danach gehst du dort mit <b>„Nur ungetestete“</b> Schritt für Schritt die übrigen Städte durch.</p></div>'
            '<div class="tablewrap" style="margin-top:12px"><table class="rhythm now"><thead><tr><th class="num">#</th><th>Stadt</th><th>Fragt nach</th><th>Testadresse</th><th>Was erscheinen soll</th><th>Getestet</th></tr></thead>'
            f'<tbody>{"".join(rows)}</tbody></table></div>')

def city_rows():
    rows = []
    for c in growth.get('cities', []):
        status = city_status(c)
        pill = {'covered':'ok','missing':'bad','partial':'warn','planned':'warn','listed':'bad','upload':'warn'}.get(status,'bad')
        label = {'covered':'abgedeckt','missing':'fehlt','partial':'teilweise','planned':'in Arbeit','listed':'nur gelistet','upload':'nur als Datei'}.get(status,status)
        meta = city_meta.get(c['city'], {})
        url = meta.get('url')
        site = (f'<a href="{esc(url)}" target="_blank" rel="noopener">Seite ↗</a>' if url else
                f'<a class="muted" href="https://www.google.com/search?q={esc("Abfallkalender " + c["city"])}" target="_blank" rel="noopener">suchen ↗</a>')
        if status == 'upload':
            tv = (third.get('terms') or {}).get(c['city'], {})
            why = 'Echte Nutzungsbedingung: nicht kommerziell.' if tv.get('verdict') == 'terms' else 'robots.txt sperrt den Pfad der Termine.'
            trust_cell = (f'<span class="pill muted">Upload-Flow</span><div class="why">{esc(why)} Die App erkennt die Stadt, '
                          'fragt den Anbieter nichts und schickt den Haushalt zum Datei-Upload — mit Link zur Seite der Stadt.</div>')
            check = f'<label class="tested"><input type="checkbox" data-city="{slug(c["city"])}"><span class="at"></span></label>'
        elif status == 'covered':
            tp, tl, tr = trust(c)
            trust_cell = f'<span class="pill {tp}">{tl}</span>{rhythm_pill(c)}<div class="why">{esc(tr)}</div>'
            check = f'<label class="tested"><input type="checkbox" data-city="{slug(c["city"])}"><span class="at"></span></label>'
        else:
            why = (meta.get('note') or c.get('note') or '').strip()
            todo = meta.get('todo') or {}
            who = todo.get('who', 'ich')
            wp, wl = {'du': ('bad', 'braucht dich'), 'entscheidung': ('warn', 'deine Entscheidung'),
                      'ich': ('muted', 'ich bin dran'), 'nicht machbar': ('muted', 'nicht machbar')}.get(who, ('muted', who))
            text = todo.get('text') or why
            trust_cell = f'<span class="pill {wp}">{wl}</span>' + (f'<div class="why">{esc(text)}</div>' if text else '')
            check = ''
        via = c.get('via', '')
        stage = _stage_of(c)
        who_attr = '' if status in ('covered', 'upload') else (meta.get('todo') or {}).get('who', 'ich')
        rows.append(f'<tr data-status="{status}" data-stage="{stage}" data-who="{who_attr}"><td class="pname">{esc(c["city"])}<div class="why">{esc(via)}</div></td><td class="mono">{esc(c.get("state",""))}</td>'
                    f'<td class="mono num">{esc(c.get("pop",""))}</td><td><span class="pill {pill}">{label}</span></td>'
                    f'<td class="trust">{trust_cell}</td><td class="tests">{test_lines(c) if status == "covered" else ""}</td>'
                    f'<td>{site}</td><td>{check}</td></tr>')
    return ''.join(rows)

checked_on = max((v.get('at', '') for v in city_checks.values()), default='')
checked_on = datetime.date.fromisoformat(checked_on).strftime('%d.%m.%Y') if checked_on else 'nie'
cities_covered = sum(1 for c in growth.get('cities', []) if city_status(c) == 'covered')
cities_total = len(growth.get('cities', []))
STAGES = [
    ('ok', 'Verlässlich', 'Abgedeckt. Jede Testadresse liefert Termine, eine erfundene Straße wird abgelehnt. Du kannst testen und abhaken.'),
    ('warn', 'Mit Einschränkung', 'Abgedeckt, aber mit bekanntem Haken — er steht in der Zeile. Testen und sagen, ob der Haken im Alltag stört.'),
    ('bad', 'Prüfen', 'Abgedeckt, aber gerade liefert keine Testadresse Termine (meist eine Störung beim Entsorger).'),
    ('du', 'Braucht dich', 'Ich finde keine offizielle Quelle. Such auf der Seite der Stadt den Abfallkalender bzw. ICS-/iCal-Link und schick ihn mir.'),
    ('entscheidung', 'Deine Entscheidung', 'Technisch machbar, aber es gibt eine Frage, die du entscheiden musst — sie steht in der Zeile.'),
    ('ich', 'Ich bin dran', 'Die offizielle Quelle ist gefunden, der Adapter kommt im nächsten Batch. Nichts zu tun für dich.'),
    ('nicht machbar', 'Nicht machbar', 'Die Stadt veröffentlicht die Termine nicht digital. Nicht angeboten; „Anfragen“ in der App bleibt offen.'),
    ('upload', 'Nur als Datei', 'Die Stadt erlaubt keinen automatischen Abruf (echte Nutzungsbedingung oder robots.txt). Die App erkennt sie und schickt den Haushalt zum Datei-Upload. Zum Testen: Adresse eingeben, „Kalenderdatei hochladen“ tippen, die ICS der Stadt wählen.'),
    ('listed', 'Nur gelistet', 'Ein Entsorger führt den Ort, aber keine echte Adresse bekommt Termine. Braucht die offizielle Quelle.'),
]
def _stage_of(c):
    s = city_status(c)
    if s == 'covered': return {'ok': 'ok', 'warn': 'warn', 'bad': 'bad', 'muted': 'ok'}[trust(c)[0]]
    if s == 'listed': return 'listed'
    if s == 'upload': return 'upload'
    return (city_meta.get(c['city'], {}).get('todo') or {}).get('who', 'ich')
stage_counts = {k: 0 for k, _, _ in STAGES}
for _c in growth.get('cities', []): stage_counts[_stage_of(_c)] = stage_counts.get(_stage_of(_c), 0) + 1
stage_opts = f'<option value="">Alle Status ({cities_total})</option>' + ''.join(
    f'<option value="{k}">{esc(l)} ({stage_counts[k]})</option>' for k, l, _ in STAGES if stage_counts.get(k))
stage_help = json.dumps({k: d for k, _, d in STAGES}, ensure_ascii=False)
needs_me = sum(1 for c in growth.get('cities', []) if city_status(c) != 'covered'
               and (city_meta.get(c['city'], {}).get('todo') or {}).get('who') in ('du', 'entscheidung'))

# --- providers table ---------------------------------------------------------
def prov_rows():
    rows = []
    for p in sorted(providers, key=lambda p: ((p.get('state') or 'ZZ'), (p.get('displayName') or p['name']).lower())):
        r = probe_by.get(p['id'])
        n = len(p['towns'])
        if n == 0: status, label = 'bad', 'tot (0 Orte)'
        elif r is None: status, label = 'muted', 'nicht getestet'
        elif r.get('error'): status, label = 'bad', 'Fehler'
        elif r.get('upload'): status, label = 'muted', 'nur Upload (' + ('Bedingungen' if r['upload'] == 'terms' else 'robots.txt') + ')'
        elif (r.get('events') or 0) == 0: status, label = 'warn', '0 Termine'
        else: status, label = 'ok', f'{r["events"]} Termine'
        detail = ''
        if r and r.get('upload') and not r.get('error'):
            detail = f'{esc(r.get("town") or "")} → erkannt, nichts abgefragt'
        elif r and not r.get('error') and r.get('town'):
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

def history_rows():
    fmt = lambda v: '–' if v is None else f'{v:,}'.replace(',', '.')
    rows = []
    for h in growth.get('history', []):
        rows.append(f'<tr><td class="mono">{esc(h["date"])}</td><td><div class="pname">{esc(h["title"])}</div><div class="muted small">{esc(h.get("what",""))}</div></td>'
                    f'<td class="num mono">{fmt(h.get("providers"))}</td><td class="num mono">{fmt(h.get("towns"))}</td><td class="num mono">{fmt(h.get("cities"))}</td></tr>')
    return ''.join(rows)

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
.pill.multi {{ background:var(--accent); color:var(--accent-ink) }}
h3.sub {{ font:600 17px/1.3 "IBM Plex Sans",sans-serif; margin:28px 0 10px }}
table.rhythm tr.multi td {{ background:var(--accent-soft) }} table.rhythm tr.multi td:first-child {{ box-shadow:inset 4px 0 0 var(--accent) }}
.toolbar {{ display:flex; flex-wrap:wrap; gap:8px; align-items:center; margin-bottom:12px }}
.toolbar input {{ flex:1 1 220px; font:inherit; padding:9px 12px; border-radius:10px; border:1px solid var(--line2); background:var(--paper); color:var(--ink) }}
.toolbar input:focus {{ outline:2px solid var(--accent); outline-offset:1px }}
.chip {{ font:500 12.5px "IBM Plex Sans",sans-serif; padding:7px 11px; border-radius:999px; border:1px solid var(--line2); background:var(--paper); color:var(--ink2); cursor:pointer }}
.chip b {{ color:var(--ink) }} .chip[aria-pressed="true"] {{ background:var(--accent); color:var(--accent-ink); border-color:var(--accent) }} .chip[aria-pressed="true"] b {{ color:inherit }}
.thf select {{ display:block; margin-top:5px; font:500 12px "IBM Plex Sans",sans-serif; color:var(--ink); background:var(--paper); border:1px solid var(--line2); border-radius:6px; padding:4px 6px; max-width:100% }}
.stagehelp {{ margin-top:10px; padding:9px 12px; border-left:3px solid var(--accent); background:var(--paper); color:var(--ink2); font-size:13.5px }}
.chip:focus-visible {{ outline:2px solid var(--accent); outline-offset:2px }}
.note {{ background:var(--paper); border:1px solid var(--line); border-left:4px solid var(--accent); border-radius:10px; padding:14px 16px; max-width:80ch }}
.note code, .howto code {{ font:500 12.5px "IBM Plex Mono",monospace; background:var(--t0); padding:2px 5px; border-radius:4px }}
.howto {{ display:grid; grid-template-columns:repeat(auto-fit,minmax(260px,1fr)); gap:10px }}
.howto div {{ background:var(--paper); border:1px solid var(--line); border-radius:12px; padding:14px 16px; font-size:14px }}
.howto h3 {{ font-size:14px; margin-bottom:6px }}
.count {{ color:var(--muted); font-size:13px; font-weight:400 }}
@media (max-width:520px) {{ .towns {{ display:none }} }}
.why {{ color:var(--muted); font-size:12.5px; margin-top:4px; max-width:34ch }}
td.trust {{ min-width:170px }} td.tests {{ min-width:250px }}
.taddr {{ font-size:13px; line-height:1.35; margin-bottom:4px }} .taddr .mono {{ font:500 12.5px "IBM Plex Mono",monospace }}
.tres {{ white-space:nowrap; font-size:12px; font-weight:600 }} .tres.ok {{ color:var(--ok) }} .tres.warn {{ color:var(--warn) }} .tres.bad {{ color:var(--bad) }} .tres.muted {{ color:var(--muted) }}
.tested {{ display:flex; align-items:center; gap:8px; cursor:pointer; white-space:nowrap }}
.tested input {{ width:20px; height:20px; accent-color:var(--ok); cursor:pointer }}
.tested .at {{ font-size:12px; color:var(--muted) }}
.decide {{ background:var(--paper); border:1px solid var(--line); border-left:4px solid var(--warn); border-radius:10px; padding:12px 16px; max-width:80ch; margin-bottom:12px; font-size:14.5px }}
a {{ color:var(--accent) }} a.muted {{ color:var(--muted) }}
tr[hidden] {{ display:none }}
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
    <div class="stat"><div class="v">{len(probed_upload)}</div><div class="l">nur Upload — Bedingungen oder robots.txt, nichts wird abgefragt</div></div>
  </div>
</header>

{now_box()}

<h2><span class="eyebrow">01</span>Bundesländer</h2>
<div class="grid">{''.join(tile(c) for c in sorted(STATES, key=lambda c: -st[c]['towns']))}</div>
<div class="legend"><span><i style="background:var(--paper);border-style:dashed"></i>nichts</span><span><i style="background:var(--t1)"></i>unter 30 Orte</span><span><i style="background:var(--t2)"></i>30–199</span><span><i style="background:var(--t3)"></i>200+</span></div>

<h2><span class="eyebrow">02</span>Die großen Städte <span class="count">{cities_covered} von {cities_total} abgedeckt · Einwohner in Tsd.</span></h2>
<div class="note"><p><b>Verlässlichkeit</b> kommt aus einer Live-Prüfung ({checked_on}): jede Testadresse läuft durch denselben Resolver wie die App, dazu eine erfundene Straße, die abgelehnt werden muss. <span class="pill ok">Verlässlich</span> jede Adresse liefert Termine · <span class="pill warn">Mit Einschränkung</span> funktioniert, aber mit bekanntem Haken — der steht darunter · <span class="pill bad">Prüfen</span> keine Testadresse liefert gerade Termine. „fragt nach Hausnummer“ ist kein Fehler: die Straße ist bekannt, die Nummer kein Abholort, und die App lässt wählen.</p>
<p><b>Getestet</b> hakst du ab, wenn du die Stadt in der App selbst verbunden hast. Das wird gespeichert und bleibt über jede neue Version dieser Seite erhalten; ich lese es beim nächsten Batch mit. <span id="testsum" class="count"></span></p></div>
<div class="toolbar" style="margin-top:12px"><button class="chip" id="untested" type="button">Nur ungetestete</button><button class="chip" id="needsme" type="button">Braucht mich <b>{needs_me}</b></button><span id="savestate" class="count"></span></div>
<div id="stagehelp" class="stagehelp" hidden></div>
<div class="tablewrap"><table id="cities"><thead><tr><th>Stadt</th><th>Land</th><th class="num">Einw.</th><th class="thf">Status<select id="stagef" aria-label="Nach Status filtern">{stage_opts}</select></th><th>Verlässlichkeit / Nächster Schritt</th><th>Testadressen</th><th>Website</th><th>Getestet</th></tr></thead><tbody>{city_rows()}</tbody></table></div>
{rhythm_box()}

{third_box()}

{terms_box()}

<h2><span class="eyebrow">03</span>Entsorger <span class="count" id="provcount"></span></h2>
<div class="toolbar"><input id="q" type="search" placeholder="Ort oder Entsorger suchen … (z. B. Stuhr, Gießen, Prignitz)" aria-label="Suchen">{fam_chips}</div>
<div class="tablewrap"><table id="provs"><thead><tr><th>Entsorger</th><th>Land</th><th>Familie</th><th class="num">Orte</th><th>Live-Sonde</th><th>Orte (Auszug)</th></tr></thead><tbody>{prov_rows()}</tbody></table></div>

<h2><span class="eyebrow">04</span>Verlauf <span class="count">was wann dazukam</span></h2>
<div class="tablewrap"><table><thead><tr><th>Datum</th><th>Schritt</th><th class="num">Entsorger</th><th class="num">Orte</th><th class="num">Großstädte</th></tr></thead><tbody>{history_rows()}</tbody></table></div>

<h2><span class="eyebrow">05</span>Wachstum: was als Nächstes</h2>
<div class="note"><p>Reihenfolge, wie sie sich aus dem Zensus ergibt: erst die Plattformen, die viele Kommunen auf einmal bringen, dann die Stadtstaaten und Millionenstädte, die je einen eigenen Adapter kosten. Was Haushalte über <b>„Anfragen“</b> melden, wandert in <code>abfall_requests</code> und steht über allem hier — ein Ort, den drei Familien wollen, schlägt eine Großstadt, die niemand fragt.</p></div>
<div class="tablewrap" style="margin-top:12px"><table><thead><tr><th>Kandidat</th><th>Land</th><th>Muster</th><th>Aufwand</th><th>Warum</th></tr></thead><tbody>{growth_rows()}</tbody></table></div>

<h2><span class="eyebrow">06</span>Der Jahreswechsel</h2>
<div class="note"><p>Die meisten Entsorger veröffentlichen <b>genau ein Kalenderjahr</b>. Heute reichen {ahead_n} von {live_n} live geprüften Abfuhrplänen über den 31.&nbsp;Dezember {this_year} hinaus — der Rest endet dort. Das ist trotzdem kein Ablaufdatum: <b>wir speichern keinen Kalender und keinen Link</b>, sondern fragen den Entsorger bei jeder Aktualisierung neu. Das Jahr, das er dann ausliefert, ist das Jahr, das die Familie sieht. Niemand muss etwas neu verbinden, und keine Datei muss noch einmal hochgeladen werden.</p>
<p>Fünf Städte zeigen die drei Bauarten. <b>Köln</b> nimmt <code>start_year</code>/<code>end_year</code> als freie Parameter, also fragen wir immer <i>dieses und nächstes</i> Jahr ab; {next_year} ist heute eine gültige, leere Antwort und füllt sich von selbst, sobald der AWB den Plan freischaltet — <b>ohne Lücke</b>. <b>München</b> kann das nicht: der ICS-Link ist mit einem <code>cHash</code> pro Jahr signiert, ein von Hand geändertes Jahr ergibt 404, und das Formular ignoriert ein mitgeschicktes Jahr. Dort entscheidet allein der AWM. Dass er mitwandert, ist belegt: archivierte, korrekt signierte Links von <b>2022 und 2024</b> liefern bis heute ihr ICS aus, und dasselbe Formular gab im Januar 2024 <code>year=2024</code> und gibt jetzt <code>year={this_year}</code> aus.</p>
<p><b>Hamburg und Stuttgart</b> zeigen die dritte und einfachste Bauart: die Stadtreinigung kennt gar kein Jahr. Ihr Feed ist ein <b>rollierendes Fenster von rund vier Monaten ab heute</b> — die Abfrage von heute reicht bereits bis in den Januar {next_year} — und wandert damit jeden Tag ein Stück weiter. Ein Jahreswechsel findet dort schlicht nicht statt. Der Preis dafür ist die Gegenrichtung: weiter als vier Monate voraus sieht in Hamburg niemand, auch die Stadtreinigung selbst nicht. <b>Stuttgart</b> macht es genauso, einen Monat kürzer — rund drei Monate ab dem Tag der Abfrage, ohne Jahresparameter und ohne etwas, das umspringen könnte.</p>
<p><b>Düsseldorf</b> liegt dazwischen und ist der sauberste Fall von allen: der Feed läuft vom Montag dieser Woche bis zum <b>31. Dezember</b>, kennt keinen Jahresparameter — und die Adresse ist eine UUID, die den Jahreswechsel überlebt. Das ist nicht vermutet, sondern nachgemessen: eine im <b>Dezember 2025</b> vom Internet Archive erfasste Kalender-UUID liefert heute den Plan für {this_year}. Niemand muss dort etwas neu verbinden.</p>
<p><b>Was zu prüfen bleibt</b>, und zwar im Dezember: wann genau ein Einjahres-Entsorger umschaltet. Schaltet er spät, ist der Vorlauf im Dezember kurz; schaltet er früh, verschwindet der Rest des laufenden Jahres. Beides lässt sich von hier aus nicht erzwingen — nur nachsehen.</p></div>
<div class="tablewrap" style="margin-top:12px"><table><thead><tr><th>Familie</th><th class="num">live</th><th class="num">reicht bis {next_year}</th><th class="num">Anteil</th></tr></thead><tbody>{rollover_rows()}</tbody></table></div>

<h2><span class="eyebrow">07</span>So bleibt die Seite wahr</h2>
<div class="howto">
  <div><h3>Zensus neu ziehen</h3>Nach jeder Änderung an <code>abfall_providers.ts</code>: <code>deno run --allow-net --allow-read --allow-write --allow-env census.ts</code>, dann Zustandszuordnung und Sonde; die Seite wird aus den drei JSON-Dateien gebaut.</div>
  <div><h3>Offene Anfragen</h3><code>select town, postcode, state, count(*) from abfall_requests where status = 'open' group by 1,2,3 order by 4 desc</code> — das ist die Arbeitsliste. Nach dem Ausliefern <code>status = 'done'</code> und <code>resolved_provider</code> setzen.</div>
  <div><h3>Was „abgedeckt“ heißt</h3>Ein Ort zählt, wenn der Entsorger ihn in seiner Ortsliste führt. Eine Straße darin kann trotzdem fehlen — die Adresse wird erst beim Verbinden gegen die Straßenliste geprüft.</div>
</div>

<script>
(function(){{
  var q=document.getElementById('q'), rows=[].slice.call(document.querySelectorAll('#provs tbody tr')), chips=[].slice.call(document.querySelectorAll('.chip[data-fam]')), count=document.getElementById('provcount');
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
(function(){{
  // "Getestet": one doc per city in the page's shared store (tests/<slug>), so
  // a tick survives every republish of this page. Without the store it falls
  // back to this browser only.
  var boxes=[].slice.call(document.querySelectorAll('input[data-city]'));
  function same(c){{ return boxes.filter(function(x){{return x.dataset.city===c;}}); }}
  var sum=document.getElementById('testsum'), state=document.getElementById('savestate');
  var only=document.getElementById('untested'), onlyOn=false, db=null, local={{}};
  function fmt(iso){{ try {{ var d=new Date(iso); return d.toLocaleDateString('de-DE',{{day:'2-digit',month:'2-digit'}}); }} catch(e) {{ return ''; }} }}
  function paint(box, v){{ box.checked=!!(v&&v.ok); box.parentNode.querySelector('.at').textContent=(v&&v.ok&&v.at)?fmt(v.at):''; }}
  function refresh(){{
    var main=[].slice.call(document.querySelectorAll('#cities input[data-city]'));
    var n=main.filter(function(b){{return b.checked;}}).length;
    sum.textContent=n+' von '+main.length+' abgedeckten Städten getestet.';
    [].slice.call(document.querySelectorAll('#cities tbody tr')).forEach(function(tr){{
      var b=tr.querySelector('input[data-city]');
      tr.hidden=(onlyOn&&(!b||b.checked))||(meOn&&['du','entscheidung'].indexOf(tr.dataset.who)<0)||(stage&&tr.dataset.stage!==stage);
    }});
  }}
  var HELP={stage_help}, stage='', sf=document.getElementById('stagef'), help=document.getElementById('stagehelp');
  sf.addEventListener('change',function(){{ stage=sf.value; help.hidden=!stage; help.textContent=stage?HELP[stage]:''; refresh(); }});
  var me=document.getElementById('needsme'), meOn=false;
  me.setAttribute('aria-pressed','false');
  me.addEventListener('click',function(){{ meOn=!meOn; me.setAttribute('aria-pressed',String(meOn)); refresh(); }});
  only.setAttribute('aria-pressed','false');
  only.addEventListener('click',function(){{ onlyOn=!onlyOn; only.setAttribute('aria-pressed',String(onlyOn)); refresh(); }});
  try {{ local=JSON.parse(localStorage.getItem('abfall-tested')||'{{}}')||{{}}; }} catch(e) {{ local={{}}; }}
  boxes.forEach(function(b){{ paint(b, local[b.dataset.city]); }});
  refresh();
  boxes.forEach(function(b){{
    b.addEventListener('change',function(){{
      var v={{ok:b.checked, at:new Date().toISOString()}};
      same(b.dataset.city).forEach(function(x){{ paint(x,v); }}); refresh();
      if(db){{
        state.textContent='speichert …';
        db.doc('tests/'+b.dataset.city).set(v).then(function(){{ state.textContent='gespeichert'; }},function(e){{
          state.textContent='Nicht gespeichert ('+((e&&e.code)||'Fehler')+')'; same(b.dataset.city).forEach(function(x){{ paint(x,{{ok:!v.ok,at:v.at}}); }}); refresh();
        }});
      }} else {{
        local[b.dataset.city]=v; try {{ localStorage.setItem('abfall-tested',JSON.stringify(local)); }} catch(e) {{}}
        state.textContent='nur in diesem Browser gespeichert';
      }}
    }});
  }});
  if(window.claude&&typeof window.claude.use==='function'){{
    window.claude.use('db').then(function(d){{
      if(!d) return;
      db=d;
      db.collection('tests').onSnapshot(function(snap){{
        var seen={{}};
        snap.docs.forEach(function(doc){{ seen[doc.id]=doc.data(); }});
        boxes.forEach(function(b){{ paint(b, seen[b.dataset.city]); }});
        refresh();
      }},function(e){{ state.textContent='Speicher nicht erreichbar ('+((e&&e.code)||'Fehler')+')'; }});
    }},function(){{}});
  }}
}})();
</script>
'''
open(f"{S}/abfall_coverage.html", "w").write(page)
print("built", len(page), "bytes;", len(providers), "providers", total_towns, "towns", len(states_covered), "states")
