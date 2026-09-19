"""What each gated candidate would add: its adapter's towns matched to register
towns of its Bundesland (strict base names), split into the counties it was
found for and elsewhere, and how many of those are unserved today."""
import json
from collections import defaultdict
from served import reg_base, cen_base, load_census, strict_index, served_strict

STATES = {'Schleswig-Holstein':'SH','Hamburg':'HH','Niedersachsen':'NI','Bremen':'HB','Nordrhein-Westfalen':'NW',
  'Hessen':'HE','Rheinland-Pfalz':'RP','Baden-Württemberg':'BW','Bayern':'BY','Saarland':'SL','Berlin':'BE',
  'Brandenburg':'BB','Mecklenburg-Vorpommern':'MV','Sachsen':'SN','Sachsen-Anhalt':'ST','Thüringen':'TH'}
reg = json.load(open('register.json'))
kreise = {k['key']: k for k in reg['kreise']}
st_of = lambda ars: STATES[kreise[ars[:5]]['state']]
by_base = defaultdict(list)
for g in reg['gemeinden']:
    if g['population']:
        by_base[(st_of(g['ars']), reg_base(g['name']))].append(g)
by_state, _ = load_census()
index = strict_index(by_state, reg['gemeinden'], st_of)
cands = {c['id']: c for c in json.load(open('candidates.json'))}

out = []
for g in json.load(open('candidate_gate.json')):
    c = cands[g['id']]
    home, away = {}, {}
    for t in g['towns'] or []:
        for r in by_base.get((c['state'], cen_base(t)), []):
            (home if r['kreis'] in c['kreise'] else away)[r['ars']] = r
    # a single-town row (muellmax, c-trace, a city tenant) covers the town it was probed with
    if len(g['towns'] or []) <= 1 and g['probe'].get('town'):
        for r in by_base.get((c['state'], cen_base(g['probe']['town'])), []):
            if r['kreis'] in c['kreise']: home[r['ars']] = r
    new = {a: r for a, r in home.items() if not any(served_strict(index, c['state'], r))}
    away_k = defaultdict(int)
    for r in away.values(): away_k[kreise[r['kreis']]['name']] += 1
    out.append({**g, 'home': len(home), 'new': len(new), 'new_pop': sum(r['population'] for r in new.values()),
                'new_towns': sorted(r['name'] for r in new.values()), 'away': dict(away_k)})
json.dump(out, open('candidate_coverage.json', 'w'), ensure_ascii=False, indent=1)
out.sort(key=lambda x: -x['new_pop'])
for x in out:
    aw = {k: v for k, v in x['away'].items() if v >= 3}
    print(f"{x['id']:34} {x['family']:10} {x['state']} towns={len(x['towns'] or []):3} home={x['home']:3} new={x['new']:3} {x['new_pop']/1000:6.0f}k ev={x['probe']['events']:3} {x['probe']['from']}..{x['probe']['to']} away={aw if aw else ''}")
print('TOTAL new towns', sum(x['new'] for x in out), 'people', round(sum(x['new_pop'] for x in out)/1e6, 2), 'M')
