import json, os, re, time, urllib.request, urllib.parse, sys
sys.argv=['x']  # keep census_states import side-effect free
import census_states as cs
raw=json.load(open('census_raw.json'))
# The geocode cache is vendored beside this script on purpose: Photon refuses
# connections after a few hundred bulk lookups, so the census must not depend on
# reaching it. Anything missing falls through to Nominatim at 1 req/s.
cache=json.load(open('photon_cache.json')) if os.path.exists('photon_cache.json') else {}
STATE_CODES=cs.STATE_CODES
CITY_STATES={'berlin':'BE','hamburg':'HH','bremen':'HB','bremerhaven':'HB'}
def state_from_photon(hits, name):
    cands=[]
    for h in hits or []:
        if h.get('country')!='DE' or h.get('osm_key')!='place': continue
        st=STATE_CODES.get(h.get('state') or '')
        if not st: st=CITY_STATES.get((h.get('city') or h.get('name') or '').lower())
        if st: cands.append(st)
    if not cands: return None, False
    return cands[0], len(set(cands))>1
def clean(name):
    n=re.sub(r'\s*[-–/(].*$','',name).strip()   # "Esens Ost" -> keep; "Schöllkrippen-Hofstädten" -> Schöllkrippen
    n=re.sub(r'\s+(Nord|Süd|Ost|West|Kernstadt)$','',n).strip()
    return n or name
nomi_cache={}
def nominatim_state(name):
    q=clean(name)
    if q in nomi_cache: return nomi_cache[q]
    url='https://nominatim.openstreetmap.org/search?'+urllib.parse.urlencode({'q':q,'countrycodes':'de','format':'json','limit':3,'addressdetails':1})
    req=urllib.request.Request(url, headers={'User-Agent':'Aporah coverage census (philipecampagnaro@gmail.com)'})
    try:
        with urllib.request.urlopen(req, timeout=20) as r: hits=json.load(r)
    except Exception as e:
        print('nominatim fail', q, e); hits=[]
    time.sleep(1.1)
    sts=[]
    for h in hits:
        a=h.get('address',{})
        st=STATE_CODES.get(a.get('state') or '') or CITY_STATES.get((a.get('city') or '').lower())
        if st: sts.append(st)
    res=(sts[0] if sts else None, len(set(sts))>1)
    nomi_cache[q]=res
    return res
# MyMüll ships demo rows in its live city list; they are not places.
JUNK_TOWNS = {'xyz', 'musterstadt', 'springfield', 'testort', 'test'}
# Ortsteile the geocoders cannot place, resolved by hand from the parent town.
HAND_STATES = {'Büren-Stadtkern': 'NW', 'Großostheim-Sonneck': 'BY',
               'Schöneck-Büdesheim': 'HE', 'Schöneck-Kilianstädten': 'HE',
               'Schöneck-Oberdorfelden': 'HE'}

# Per-town Bundesländer for the providers whose towns span states, decided by
# the **Landkreis** the provider demonstrably serves rather than the geocoder's
# top hit. First-hit ranking put Dahlem in Berlin (it is Kreis Euskirchen),
# Lichtenau in Landkreis Ansbach (Kreis Paderborn) and Goldbach in Thüringen
# (Landkreis Aschaffenburg). 30 towns were moved that way; the file is the
# record, and a town missing from it falls back to geocoding below.
TOWN_STATES = json.load(open('town_states.json')) if os.path.exists('town_states.json') else {}

out=[]
unverified=[]
for p in raw['providers']:
    disp, st = cs.ASSIGN.get(p['id'], (p['name'], p.get('state')))
    if p['id']=='bsr-berlin': disp, st = ('BSR Berliner Stadtreinigung','BE')
    if p['id']=='fes-frankfurt': disp, st = ('FES Frankfurt am Main','HE')
    if p['id']=='awm-muenchen': disp, st = ('AWM Abfallwirtschaftsbetrieb München','BY')
    if p['id']=='awbkoeln-koeln': disp, st = ('AWB Abfallwirtschaftsbetriebe Köln','NW')
    if p['id']=='srh-hamburg': disp, st = ('Stadtreinigung Hamburg','HH')
    if p['id']=='aws-stuttgart': disp, st = ('Abfallwirtschaft Stuttgart','BW')
    if p['id']=='awista-duesseldorf': disp, st = ('AWISTA Kommunal Düsseldorf','NW')
    towns=[]
    per_town = p['id']=='jumomind-mymuell'
    ambiguous=0; geocoded=0
    for name in p['towns']:
        if name.strip().lower() in JUNK_TOWNS: continue
        tst=st; amb=False
        if per_town:
            known = TOWN_STATES.get(p['id'], {}).get(name)
            if known:
                tst, amb = known, False
            elif name in cache:
                tst, amb = state_from_photon(cache[name], name)
            else:
                tst, amb = nominatim_state(name)
            if not tst: tst=HAND_STATES.get(name)
            else: geocoded+=1
            ambiguous+=amb
        towns.append({'name':name,'state':tst, **({'ambiguous':True} if amb else {})})
    # verification: any cached sample towns of this provider agreeing?
    conf='assigned'
    if not per_town:
        samples=[t for t in p['towns'] if t in cache][:3]
        agree=[state_from_photon(cache[t],t)[0] for t in samples]
        agree=[a for a in agree if a]
        if agree and all(a==st for a in agree): conf='verified'
        elif agree: conf='conflict:'+','.join(agree); unverified.append((p['id'],st,agree))
    out.append({'id':p['id'],'name':p['name'],'displayName':disp,'family':p['family'],'state':st,'stateConfidence':conf,'towns':towns,
                **({'geocoded':geocoded,'ambiguous':ambiguous} if per_town else {})})
    if per_town: print('mymuell geocoded',geocoded,'of',len(p['towns']),'ambiguous',ambiguous,'unresolved',[t['name'] for t in towns if not t['state']][:20])
json.dump({'at':raw['at'],'providers':out}, open('census_states.json','w'), ensure_ascii=False, indent=1)
print('providers',len(out),'unverified/conflicts',unverified)
# top cities
CITIES=[('Berlin','BE',3780),('Hamburg','HH',1890),('München','BY',1510),('Köln','NW',1090),('Frankfurt am Main','HE',775),('Stuttgart','BW',635),('Düsseldorf','NW',630),('Leipzig','SN',620),('Dortmund','NW',600),('Essen','NW',585),('Bremen','HB',570),('Dresden','SN',565),('Hannover','NI',550),('Nürnberg','BY',525),('Duisburg','NW',505),('Bochum','NW',365),('Wuppertal','NW',360),('Bielefeld','NW',340),('Bonn','NW',335),('Münster','NW',320),('Mannheim','BW',315),('Karlsruhe','BW',310),('Augsburg','BY',300),('Wiesbaden','HE',280),('Mönchengladbach','NW',265),('Gelsenkirchen','NW',265),('Aachen','NW',255),('Braunschweig','NI',250),('Chemnitz','SN',245),('Kiel','SH',250),('Halle (Saale)','ST',240),('Magdeburg','ST',240),('Freiburg im Breisgau','BW',235),('Krefeld','NW',230),('Mainz','RP',220),('Lübeck','SH',220),('Erfurt','TH',215),('Oberhausen','NW',210),('Rostock','MV',210),('Kassel','HE',205),('Hagen','NW',190),('Potsdam','BB',185),('Saarbrücken','SL',180),('Hamm','NW',180),('Ludwigshafen am Rhein','RP',175),('Mülheim an der Ruhr','NW',170),('Oldenburg','NI',170),('Osnabrück','NI',165),('Leverkusen','NW',165),('Darmstadt','HE',160),('Heidelberg','BW',160),('Solingen','NW',160),('Regensburg','BY',155),('Herne','NW',155),('Paderborn','NW',155),('Neuss','NW',155),('Ingolstadt','BY',140),('Offenbach am Main','HE',130),('Fürth','BY',130),('Würzburg','BY',130),('Ulm','BW',125),('Heilbronn','BW',125),('Pforzheim','BW',125),('Wolfsburg','NI',125),('Göttingen','NI',120),('Bottrop','NW',120),('Reutlingen','BW',115),('Koblenz','RP',115),('Bremerhaven','HB',115),('Recklinghausen','NW',110),('Bergisch Gladbach','NW',110),('Erlangen','BY',115),('Remscheid','NW',110),('Jena','TH',110),('Trier','RP',110),('Salzgitter','NI',105),('Moers','NW',105),('Siegen','NW',105),('Hildesheim','NI',100),('Cottbus','BB',100),('Gütersloh','NW',100)]
NOTES={'abfall.io v3 (GraphQL)':['Essen','Duisburg','Göttingen','Reutlingen'],'Insert IT':['Mannheim','Kassel','Krefeld','Lübeck','Herne','Offenbach am Main'],'AWB Köln API':['Köln'],'Stadtreinigung Hamburg (ICS + Formular)':['Hamburg'],'Stadtreinigung Leipzig REST':['Leipzig'],'AWS Stuttgart Formular':['Stuttgart'],'ABK Kiel JSON':['Kiel'],'AWM München Formular':['München'],'aha Region Hannover':['Hannover'],'Müllmax (IP-Sperre!)':['Münster','Mainz','Bochum','Hamm','Darmstadt','Remscheid'],'Abfall+ App-Backend':['Bonn','Augsburg','Dortmund','Freiburg im Breisgau','Würzburg','Leverkusen','Oldenburg','Hagen'],'ATHOS-Servlet':['Saarbrücken','Pforzheim','Bielefeld'],'nur ICS-ID (kein Adapter)':['Frankfurt am Main','Wiesbaden','Dresden','Rostock','Schwerin'],'AWISTA (Next.js-Action, fragil)':['Düsseldorf'],'Magdeburg smart-village ICS':['Magdeburg'],'AWG Wuppertal':['Wuppertal'],'hausmuell.info':['Erfurt','Chemnitz'],'Karlsruhe (TLS defekt) / Müllmann-App':['Karlsruhe'],'Stadt Potsdam (Rhythmus-Rechnung)':['Potsdam']}
note_for={c:k for k,v in NOTES.items() for c in v}
def norm(s): return re.sub(r'[^a-zäöüß]','',s.lower())
def word_in(hay, needle):
    return re.search(r'(?<![a-zäöüß])'+re.escape(needle)+r'(?![a-zäöüß])', hay) is not None
cities=[]
for city,st,pop in CITIES:
    base=re.sub(r'\s*\(.*\)$','',city); base=base.split(' am ')[0].split(' im ')[0].split(' an der ')[0]
    # The Bundesland has to agree. Without it a "Münster" in Hessen counts as
    # Münster in Westphalia and the map claims coverage it does not have — the
    # same class of error as "Hain" matching inside "Friedrichshain".
    hits=[]
    for p in out:
        for t in p['towns']:
            tn=t['name'].lower()
            if t.get('state')!=st: continue
            if tn==city.lower() or tn==base.lower() or word_in(tn, base.lower()):
                hits.append(p['displayName']); break
    status='covered' if hits else 'missing'
    cities.append({'city':city,'state':st,'pop':pop,'status':status,'via':', '.join(sorted(set(hits))[:2]),'note':'' if hits else note_for.get(city,'')})
g=json.load(open('growth.json')); g['cities']=cities; json.dump(g, open('growth.json','w'), ensure_ascii=False, indent=1)
print('cities covered', sum(1 for c in cities if c['status']=='covered'), 'of', len(cities))
print([c['city'] for c in cities if c['status']=='covered'])
