"""Split every unserved municipality outside the NRW pilot into agent batches.

Unserved = in the Destatis register but not among the towns the census
(tool/abfall_census/census_states.json) says a live provider covers. Batches
are per county, because outside NRW the county (or its Zweckverband) usually
publishes one calendar for all of its towns; Hessen's towns mostly collect
themselves, so a Hessian county weighs more.

    python3 build_batches.py   ->  batches_rest.json, unserved.json
"""
import json, re
from collections import defaultdict

STATES = {'Schleswig-Holstein':'SH','Hamburg':'HH','Niedersachsen':'NI','Bremen':'HB',
  'Nordrhein-Westfalen':'NW','Hessen':'HE','Rheinland-Pfalz':'RP','Baden-Württemberg':'BW',
  'Bayern':'BY','Saarland':'SL','Berlin':'BE','Brandenburg':'BB','Mecklenburg-Vorpommern':'MV',
  'Sachsen':'SN','Sachsen-Anhalt':'ST','Thüringen':'TH'}
ORDER = ['BW','BY','NI','HE','RP','SN','SH','BB','TH','ST','MV','SL']
TOWN_WEIGHT = {'HE': 0.25}
BATCH_WORK = {'HE': 8.0}  # everything else: 12

def norm(n):
    n = re.split(r',|/| \(| an der | am | im | in | a\. ?d\. | bei ', n.lower())[0]
    n = re.sub(r'^(bad|hansestadt|stadt) ', '', n)
    return re.sub(r'[^a-zäöüß]', '', n)

reg = json.load(open('register.json'))
census = json.load(open('../abfall_census/census_states.json'))
served = defaultdict(set)
for p in census['providers']:
    for t in p['towns']:
        served[t.get('state') or p.get('state')].add(norm(t['name']))

kreise = {k['key']: k for k in reg['kreise']}
by_kreis = defaultdict(list)
for g in reg['gemeinden']:
    k = kreise[g['kreis']]
    st = STATES[k['state']]
    if st == 'NW' or g['population'] == 0 or norm(g['name']) in served[st]:
        continue
    by_kreis[g['kreis']].append({'ars': g['ars'], 'name': g['name'], 'plz': g['plz'], 'population': g['population']})

batches, unserved = [], []
for st in ORDER:
    keys = sorted((k for k in by_kreis if STATES[kreise[k]['state']] == st),
                  key=lambda k: -sum(t['population'] for t in by_kreis[k]))
    cur, work = [], 0.0
    for k in keys:
        towns = sorted(by_kreis[k], key=lambda t: -t['population'])
        w = 1 + len(towns) * TOWN_WEIGHT.get(st, 0.02)
        if cur and work + w > BATCH_WORK.get(st, 12.0):
            batches.append({'state': st, 'counties': cur}); cur, work = [], 0.0
        cur.append({'kreis': kreise[k]['name'], 'kreis_key': k, 'kind': kreise[k]['kind'],
                    'county_population': kreise[k]['population'],
                    'municipalities_in_county': kreise[k]['municipalities'], 'towns': towns})
        work += w
        unserved += [dict(t, kreis=k, state=st) for t in towns]
    if cur: batches.append({'state': st, 'counties': cur})

json.dump(batches, open('batches_rest.json', 'w'), ensure_ascii=False, indent=1)
json.dump(unserved, open('unserved.json', 'w'), ensure_ascii=False, indent=1)
per = defaultdict(int)
for b in batches: per[b['state']] += 1
print(len(batches), 'batches', dict(per))
print(sum(len(b['counties']) for b in batches), 'counties', len(unserved), 'towns')
