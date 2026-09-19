"""vendor_configs.json -> candidates.json: one would-be provider row per vendor
config not yet in abfall_providers.ts, with the unserved register towns of the
counties it was found for (what the probe checks the adapter's towns against)."""
import json, re, sys
from collections import defaultdict
from served import load_census, strict_index, served_strict

STATES = {'Schleswig-Holstein':'SH','Hamburg':'HH','Niedersachsen':'NI','Bremen':'HB','Nordrhein-Westfalen':'NW',
  'Hessen':'HE','Rheinland-Pfalz':'RP','Baden-Württemberg':'BW','Bayern':'BY','Saarland':'SL','Berlin':'BE',
  'Brandenburg':'BB','Mecklenburg-Vorpommern':'MV','Sachsen':'SN','Sachsen-Anhalt':'ST','Thüringen':'TH'}
src = open('../../supabase/functions/_shared/abfall_providers.ts').read()
reg = json.load(open('register.json'))
kreise = {k['key']: k for k in reg['kreise']}
by_name = defaultdict(list)
for k in reg['kreise']:
    by_name[(STATES[k['state']], k['name'])].append(k['key'])
towns_by_kreis = defaultdict(list)
for g in reg['gemeinden']:
    if g['population']:
        towns_by_kreis[g['kreis']].append(g)

cands = {}
for r in json.load(open('vendor_configs.json')):
    keys = by_name.get((r['st'], r['kreis'])) or []
    if len(keys) > 1:
        # Bavaria names a Landkreis and its city alike ("Passau"): a county row
        # is the Landkreis, a town row the city.
        city = r['scope'] == 'town' and r['n'] == 1
        keys = [k for k in keys if (kreise[k]['kind'] in ('kreisfreie Stadt', 'Stadtkreis')) == city] or keys
    if len(keys) != 1:
        print('county not unique:', r['st'], r['kreis'], keys, file=sys.stderr); continue
    kk = keys[0]
    for fam, vals in r['configs'].items():
        for v in vals:
            if fam in ('advantic', 'jumomind', 'insertit'):
                continue
            if fam in ('abfallio', 'abfallplus'):
                if v[:8] in src: continue
                c = {'id': f'key-{v[:8]}', 'families': ['abfallio', 'abfallplus'], 'key': v}
            elif fam == 'athos':
                tenant = v.rstrip('/').rsplit('/', 1)[1]
                if v in src: continue
                c = {'id': 'athos-' + re.sub(r'^wastemanagement', '', tenant.lower()), 'families': ['athos'], 'host': v}
            elif fam == 'awido':
                if v in ('bundles', 'content', 'scripts', 'customer') or f"['{v}'" in src: continue
                c = {'id': f'awido-{v}', 'families': ['awido'], 'client': v}
            elif fam == 'muellmax':
                if f"client: '{v}'" in src: continue
                c = {'id': f'muellmax-{v}', 'families': ['muellmax'], 'client': v}
            elif fam == 'ctrace':
                host, service = v.split('/', 1)
                if f"service: '{service}'" in src: continue
                c = {'id': 'ctrace-' + service.lower(), 'families': ['ctrace'], 'host': host, 'service': service}
            else:
                continue
            c = cands.setdefault(c['id'], {**c, 'state': r['st'], 'publisher': r['publisher'], 'pages': [], 'kreise': {}})
            if r['url'] not in c['pages']: c['pages'].append(r['url'])
            c['kreise'][kk] = kreise[kk]['name']

# the county's register towns, largest first, and which of them are unserved
by_state, _ = load_census()
index = strict_index(by_state, reg['gemeinden'], lambda a: STATES[kreise[a[:5]]['state']])
for c in cands.values():
    ts = []
    for kk in c['kreise']:
        for g in towns_by_kreis[kk]:
            live, up = served_strict(index, c['state'], g)
            ts.append({'ars': g['ars'], 'name': g['name'], 'plz': g['plz'], 'pop': g['population'], 'served': bool(live or up)})
    c['reg_towns'] = sorted(ts, key=lambda t: -t['pop'])
json.dump(sorted(cands.values(), key=lambda c: -sum(t['pop'] for t in c['reg_towns'])), open('candidates.json', 'w'), ensure_ascii=False, indent=1)
print(len(cands), 'candidates')
for c in cands.values(): print(' ', c['id'], c['state'], list(c['kreise'].values()))
