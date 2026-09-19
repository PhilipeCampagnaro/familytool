"""Render the tracking page for the official-calendar-page census.

Reads the pilot and rest-of-Germany results as far as they exist and writes one
self-contained HTML page. Re-run after every batch; the page is republished to
the same artifact URL.

    python3 build_tracker.py <out.html> [germany_results.json]
"""
import json, re, sys, os, html
from collections import defaultdict

STATES = {'Schleswig-Holstein':'SH','Hamburg':'HH','Niedersachsen':'NI','Bremen':'HB',
  'Nordrhein-Westfalen':'NW','Hessen':'HE','Rheinland-Pfalz':'RP','Baden-Württemberg':'BW',
  'Bayern':'BY','Saarland':'SL','Berlin':'BE','Brandenburg':'BB','Mecklenburg-Vorpommern':'MV',
  'Sachsen':'SN','Sachsen-Anhalt':'ST','Thüringen':'TH'}
NAMES = {v: k for k, v in STATES.items()}
ORDER = ['NW','BW','BY','NI','HE','RP','SN','SH','BB','TH','ST','MV','SL']

def norm(n):
    n = re.split(r',|/| \(| an der | am | im | in | a\. ?d\. | bei ', n.lower())[0]
    n = re.sub(r'^(bad|hansestadt|stadt) ', '', n)
    return re.sub(r'[^a-zäöüß]', '', n)

out_path = sys.argv[1]
res_path = sys.argv[2] if len(sys.argv) > 2 else 'germany_results.json'
reg = json.load(open('register.json'))
kreise = {k['key']: k for k in reg['kreise']}
census = json.load(open('../abfall_census/census_states.json'))

# --- the research set: every town that was unserved when the atlas began -------
# Fixed (unserved.json + the NRW pilot), so that a town the census serves later
# shows up as progress instead of silently leaving the page.
research = [u['ars'] for u in json.load(open('unserved.json'))] + \
    [t['ars'] for t in json.load(open('pilot_nrw_results_verified.json'))['towns']]
gem = {g['ars']: g for g in reg['gemeinden']}

# Served today? The name as the census writes it (norm), else the stricter
# second look in served.py ("Altenbeken-Buke", "Wörth a.d.Donau").
from served import load_census, strict_index, served_strict
_by_state, _upload_ids = load_census()
_index = strict_index(_by_state, reg['gemeinden'], lambda a: STATES[kreise[a[:5]]['state']])
_first = defaultdict(dict)
for p in census['providers']:
    for t in p['towns']:
        _first[t.get('state') or p.get('state')].setdefault(norm(t['name']), set()).add(p['id'])
recognised = {'live': [0, 0], 'upload': [0, 0]}
towns = {}
for a in research:
    g = gem[a]; st = STATES[kreise[g['kreis']]['state']]
    ids = _first[st].get(norm(g['name']), set())
    live, up = served_strict(_index, st, g)
    live |= {i for i in ids if i not in _upload_ids}; up |= {i for i in ids if i in _upload_ids}
    if live or up:
        k = 'live' if live else 'upload'
        recognised[k][0] += 1; recognised[k][1] += g['population']
        continue
    towns[a] = {'ars': a, 'name': g['name'], 'pop': g['population'], 'kreis': g['kreis'], 'st': st}

def page(p):
    return {'publisher': p.get('publisher'), 'url': p.get('page_url'), 'official': p.get('page_host_official'),
            'via': p.get('linked_from'), 'fmt': p.get('format') or 'unknown', 'conf': p.get('confidence'),
            'evidence': p.get('evidence')}

checks = json.load(open('checks.json')) if os.path.exists('checks.json') else {}
entries, town_fmt, town_page, levels, done_counties = [], {}, {}, {}, set()

def add(st, kkey, scope, name, covered, pg):
    c = checks.get(pg['url'] or '')
    pop = sum(towns[a]['pop'] for a in covered)
    entries.append({'st': st, 'kreis': kreise[kkey]['name'], 'scope': scope, 'name': name, 'n': len(covered),
                    'pop': pop, **pg, 'check': None if c is None else bool(c.get('ok')),
                    'status': None if c is None else c.get('status')})
    for a in covered:
        town_fmt[a] = pg['fmt'] if pg['url'] else 'none'
        town_page[a] = {**pg, 'check': None if c is None else bool(c.get('ok'))}

# NRW pilot: one row per town
pilot = json.load(open('pilot_nrw_results_verified.json'))
for c in pilot['counties']:
    levels[c['kreis_key']] = c['collection_level']; done_counties.add(c['kreis_key'])
pchecks = {t['ars']: t['check'] for t in pilot['towns']}
for t in pilot['towns']:
    if t['ars'] not in towns: continue
    pg = page(t)
    ck = pchecks[t['ars']]
    checks.setdefault(pg['url'] or '', ck)
    add('NW', t['ars'][:5], 'town', t['name'], [t['ars']], pg)

# the rest of Germany: a county page plus the towns it does not serve
batches = json.load(open('batches_rest.json'))
done_batches = set()
if os.path.exists(res_path):
    for b in json.load(open(res_path)):
        done_batches.add(b['batch'])
        inputs = {c['kreis_key']: [t['ars'] for t in c['towns'] if t['ars'] in towns] for c in batches[b['batch']]['counties']}
        for c in b['counties']:
            k = c['kreis_key']
            if k not in inputs: continue
            levels[k] = c['collection_level']; done_counties.add(k)
            own = {tp['ars']: tp for tp in c.get('town_pages', []) if tp['ars'] in towns}
            st = towns[inputs[k][0]]['st'] if inputs[k] else 'NW'
            rest = [a for a in inputs[k] if a not in own]
            if c.get('county_page') and rest:
                add(st, k, 'county', kreise[k]['name'], rest, page(c['county_page']))
            elif rest:
                for a in rest:
                    add(st, k, 'town', towns[a]['name'], [a], page({'format': 'unknown', 'evidence': 'not returned by the agent'}))
            for a, tp in own.items():
                add(st, k, 'town', tp['name'], [a], page(tp['page']))

# --- per-state summary ---------------------------------------------------------
batch_states = defaultdict(list)
for i, b in enumerate(batches):
    batch_states[b['state']].append(i)
states = []
for st in ORDER:
    ts = [t for t in towns.values() if t['st'] == st]
    ks = {t['kreis'] for t in ts}
    fm = defaultdict(lambda: [0, 0])
    for t in ts:
        f = town_fmt.get(t['ars'])
        if f: fm[f][0] += 1; fm[f][1] += t['pop']
    researched = sum(v[0] for v in fm.values())
    if st == 'NW': status = 'done'
    else:
        got = sum(i in done_batches for i in batch_states[st])
        status = 'done' if got == len(batch_states[st]) else ('running' if got else 'queued')
    lv = defaultdict(int)
    for k in ks:
        if k in levels: lv[levels[k]] += 1
    states.append({'st': st, 'name': NAMES[st], 'towns': len(ts), 'pop': sum(t['pop'] for t in ts), 'counties': len(ks),
                   'status': status, 'researched': researched, 'fmt': {k: v for k, v in fm.items()}, 'levels': dict(lv),
                   'batches': [sum(i in done_batches for i in batch_states[st]), len(batch_states[st])] if st != 'NW' else [8, 8]})

# The page each still-unserved town gets in the app (gen_town_pages.py).
json.dump({a: {**p, 'name': towns[a]['name'], 'st': towns[a]['st']} for a, p in town_page.items()},
          open('town_pages.json', 'w'), ensure_ascii=False)

findings = json.load(open('findings.json'))
data = {'recognised': recognised, 'states': states, 'entries': entries, 'findings': findings,
        'checked': sum(1 for e in entries if e['check'] is not None)}
tpl = open('tracker_template.html').read()
open(out_path, 'w').write(tpl.replace('/*DATA*/null', json.dumps(data, ensure_ascii=False).replace('</', '<\\/')))
print(out_path, len(entries), 'rows;', sum(s['researched'] for s in states), 'of', len(towns), 'towns researched')
