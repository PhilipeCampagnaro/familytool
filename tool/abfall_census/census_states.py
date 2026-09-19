#!/usr/bin/env python3
"""Assign a Bundesland to every provider of census_raw.json, verify it with Photon,
and map jumomind-mymuell (nationwide) per town. Writes census_states.json and
census_summary.md. Geocoding results are cached in photon_cache.json so a crash
loses nothing."""
import json, os, re, sys, time, threading
import urllib.request, urllib.parse
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, 'census_raw.json')
CACHE = os.path.join(HERE, 'photon_cache.json')
OUT = os.path.join(HERE, 'census_states.json')
SUMMARY = os.path.join(HERE, 'census_summary.md')

STATE_CODES = {
    'Baden-Württemberg': 'BW', 'Bayern': 'BY', 'Berlin': 'BE', 'Brandenburg': 'BB',
    'Bremen': 'HB', 'Hamburg': 'HH', 'Hessen': 'HE', 'Mecklenburg-Vorpommern': 'MV',
    'Niedersachsen': 'NI', 'Nordrhein-Westfalen': 'NW', 'Rheinland-Pfalz': 'RP',
    'Saarland': 'SL', 'Sachsen': 'SN', 'Sachsen-Anhalt': 'ST', 'Schleswig-Holstein': 'SH',
    'Thüringen': 'TH',
}
STATE_NAMES = {v: k for k, v in STATE_CODES.items()}

# id -> (displayName, state). Assigned from the authority named by the slug/name;
# every one is then verified against two geocoded towns.
ASSIGN = {
    # regio-iT AbfallNavi customers (slug -> authority, identified from the towns the
    # /rest/orte endpoint returns; the web page title is generic for all of them)
    'regioit-aachen': ('Stadt Aachen (Aachener Stadtbetrieb)', 'NW'),
    'regioit-zew2': ('ZEW Zweckverband Entsorgungsregion West (StädteRegion Aachen, Kreis Düren)', 'NW'),
    'regioit-aw-bgl2': ('Abfallwirtschaftsbetrieb Bergisch Gladbach', 'NW'),
    'regioit-bav': ('BAV Bergischer Abfallwirtschaftsverband (Rheinisch-Bergischer und Oberbergischer Kreis)', 'NW'),
    'regioit-din': ('DIN Service Dinslaken', 'NW'),
    'regioit-dorsten': ('Stadt Dorsten', 'NW'),
    'regioit-gt2': ('Stadt Gütersloh', 'NW'),
    'regioit-hlv': ('Stadt Halver', 'NW'),
    'regioit-coe': ('WBC Wirtschaftsbetriebe Kreis Coesfeld', 'NW'),
    'regioit-krhs': ('Kreis Heinsberg', 'NW'),
    'regioit-pi': ('Kreis Pinneberg (GAB Umwelt Service)', 'SH'),
    'regioit-krwaf': ('AWG Kreis Warendorf (mit GEG Kreis Gütersloh)', 'NW'),
    'regioit-stl': ('STL Stadtreinigungs-, Transport- und Baubetrieb Lüdenscheid', 'NW'),
    'regioit-nds': ('Stadt Norderstedt (Betriebsamt)', 'SH'),
    'regioit-nuernberg': ('Stadt Nürnberg (ASN Abfallwirtschaft)', 'BY'),
    'regioit-solingen': ('Stadt Solingen (Technische Betriebe)', 'NW'),
    'regioit-wml2': ('EGW Entsorgungsgesellschaft Westmünsterland (Kreis Borken)', 'NW'),
    'regioit-cottbus': ('Stadt Cottbus', 'BB'),
    'regioit-kronberg': ('Stadt Kronberg im Taunus', 'HE'),
    'regioit-muelheim': ('Stadt Mülheim an der Ruhr', 'NW'),
    'regioit-viersen': ('Kreis Viersen', 'NW'),
    'regioit-oberhausen': ('Stadt Oberhausen (WBO)', 'NW'),
    'regioit-cux': ('Stadt Cuxhaven', 'NI'),
    'regioit-portawestfalica': ('Stadt Porta Westfalica', 'NW'),
    'regioit-unna': ('GWA Kreis Unna', 'NW'),
    'regioit-frankenthal': ('Stadt Frankenthal (Pfalz)', 'RP'),
    'regioit-awvlippe': ('Abfallwirtschaftsverband Lippe', 'NW'),
    'regioit-kranenburg': ('Gemeinde Kranenburg', 'NW'),
    # awido
    'awido-ebu': ('EBU Ulm', 'BW'),
    'awido-aic-fdb': ('Landratsamt Aichach-Friedberg', 'BY'),
    'awido-ansbach': ('Landkreis Ansbach', 'BY'),
    'awido-awb-ak': ('AWB Landkreis Altenkirchen', 'RP'),
    'awido-awb-duerkheim': ('AWB Landkreis Bad Dürkheim', 'RP'),
    'awido-awld': ('Abfallwirtschaft Lahn-Dill-Kreis', 'HE'),
    'awido-awv-isar-inn': ('Abfallwirtschaft Isar-Inn', 'BY'),
    'awido-awv-nordschwaben': ('AWV Nordschwaben', 'BY'),
    'awido-azv-hef-rof': ('AZV Hersfeld-Rotenburg', 'HE'),
    'awido-bgl': ('Landkreis Berchtesgadener Land', 'BY'),
    'awido-coburg': ('Landkreis Coburg', 'BY'),
    'awido-ebe': ('Landkreis Ebersberg', 'BY'),
    'awido-erding': ('Landkreis Erding', 'BY'),
    'awido-eww-suew': ('Landkreis Südliche Weinstraße', 'RP'),
    'awido-ffb': ('AWB Landkreis Fürstenfeldbruck', 'BY'),
    'awido-fulda': ('Landkreis Fulda', 'HE'),
    'awido-fulda-stadt': ('Stadt Fulda', 'HE'),
    'awido-gifhorn': ('Landkreis Gifhorn', 'NI'),
    'awido-gotha': ('Landkreis Gotha', 'TH'),
    'awido-kaufbeuren': ('Stadt Kaufbeuren', 'BY'),
    'awido-kaw-guenzburg': ('Landkreis Günzburg', 'BY'),
    'awido-kelheim': ('Landkreis Kelheim', 'BY'),
    'awido-koenigstein': ('Stadt Königstein im Taunus', 'HE'),
    'awido-kreis-tir': ('Landkreis Tirschenreuth', 'BY'),
    'awido-kronach': ('Landkreis Kronach', 'BY'),
    'awido-kulmbach': ('Landkreis Kulmbach', 'BY'),
    'awido-landkreisbetriebe': ('Landkreisbetriebe Neuburg-Schrobenhausen', 'BY'),
    'awido-lichtenfels': ('Landkreis Lichtenfels', 'BY'),
    'awido-lkgi': ('Landkreis Gießen', 'HE'),
    'awido-lra-ab': ('Landkreis Aschaffenburg', 'BY'),
    'awido-lra-dah': ('Landratsamt Dachau', 'BY'),
    'awido-lra-mue': ('Landkreis Mühldorf a. Inn', 'BY'),
    'awido-lra-regensburg': ('Landratsamt Regensburg', 'BY'),
    'awido-lra-schweinfurt': ('Landkreis Schweinfurt', 'BY'),
    'awido-memmingen': ('Stadt Memmingen', 'BY'),
    'awido-neustadt': ('Landkreis Neustadt a.d. Waldnaab', 'BY'),
    'awido-pullach': ('Gemeinde Pullach im Isartal', 'BY'),
    'awido-regensburg': ('Stadt Regensburg', 'BY'),
    'awido-rmk': ('Abfallwirtschaft Rems-Murr', 'BW'),
    'awido-rosenheim': ('Landkreis Rosenheim', 'BY'),
    'awido-roth': ('Landkreis Roth', 'BY'),
    'awido-tuebingen': ('Landkreis Tübingen', 'BW'),
    'awido-unterhaching': ('Gemeinde Unterhaching', 'BY'),
    'awido-unterschleissheim': ('Stadt Unterschleißheim', 'BY'),
    'awido-wgv': ('WGV Recycling (Landkreis Bad Tölz-Wolfratshausen)', 'BY'),
    'awido-zaso': ('ZV Abfallwirtschaft Saale-Orla (Saale-Orla-Kreis, Saalfeld-Rudolstadt)', 'TH'),
    'awido-zv-muc-so': ('Zweckverband München-Südost', 'BY'),
    # jumomind
    'jumomind-zaw': ('ZAW Darmstadt-Dieburg', 'HE'),
    'jumomind-aoe': ('Landkreis Altötting', 'BY'),
    'jumomind-lka': ('MKW Landkreis Aurich', 'NI'),
    'jumomind-hom': ('Stadt Bad Homburg v.d. Höhe', 'HE'),
    'jumomind-bdg': ('Kreiswerke Barnim', 'BB'),
    'jumomind-hat': ('Stadt Hattersheim am Main', 'HE'),
    'jumomind-ingol': ('Stadt Ingolstadt', 'BY'),
    'jumomind-lue': ('Stadt Lübbecke', 'NW'),
    'jumomind-sbm': ('Städtische Betriebe Minden', 'NW'),
    'jumomind-ksr': ('ZBH Kommunale Servicebetriebe Recklinghausen', 'NW'),
    'jumomind-rhe': ('RH Entsorgung (Rhein-Hunsrück-Kreis)', 'RP'),
    'jumomind-udg': ('UDG Uckermärkische Dienstleistungsgesellschaft (Landkreis Uckermark)', 'BB'),
    'jumomind-mymuell': ('MyMüll App (bundesweit, per Ort)', None),
    'jumomind-esn': ('Stadt Neustadt an der Weinstraße (ESN)', 'RP'),
    'jumomind-zac': ('Zweckverband Abfallwirtschaft Celle', 'NI'),
    'jumomind-ben': ('AWB Landkreis Grafschaft Bentheim', 'NI'),
    'jumomind-enwi': ('enwi Entsorgungswirtschaft Landkreis Harz', 'ST'),
    'jumomind-hox': ('Abfallservice Kreis Höxter', 'NW'),
    'jumomind-kbl': ('KBL Kommunale Betriebe Langen (Hessen)', 'HE'),
    'jumomind-ros': ('Stadt Rosbach v.d. Höhe', 'HE'),
    'jumomind-mkk': ('Main-Kinzig-Kreis', 'HE'),
    'jumomind-wol': ('ALW Abfallwirtschaft Landkreis Wolfenbüttel', 'NI'),
    # abfall.io
    'abfallio-e21758b9': ('EGST Entsorgungsgesellschaft Steinfurt', 'NW'),
    'abfallio-040b38fe': ('ASO Abfall-Service Osterholz', 'NI'),
    'abfallio-594f805e': ('Abfallwirtschaft Landkreis Kitzingen', 'BY'),
    'abfallio-e5543a3e': ('MüllALARM / Schönmackers (Niederrhein, Eifel)', 'NW'),
    'abfallio-3ca331fb': ('Abfallbewirtschaftung Ostalbkreis', 'BW'),
    'abfallio-27708a01': ('Landkreis Oldenburg', 'NI'),
    'abfallio-914fb9d0': ('AVR Kommunal Rhein-Neckar-Kreis', 'BW'),
    'abfallio-645adb3c': ('Landkreis Rotenburg (Wümme)', 'NI'),
    'abfallio-c22b850e': ('Landratsamt Unterallgäu', 'BY'),
    'abfallio-248deacb': ('AWB Westerwaldkreis', 'RP'),
    'abfallio-31fb9c7d': ('Landkreis Weißenburg-Gunzenhausen', 'BY'),
    'abfallio-49fe8a63': ('Landkreis Cuxhaven', 'NI'),
    'abfallio-bd0c2d01': ('Stadt Landshut', 'BY'),
    'abfallio-6efba91e': ('Stadt Ludwigshafen am Rhein', 'RP'),
    'abfallio-1e959241': ('Amt Bad Wilsnack/Weisen (Landkreis Prignitz)', 'BB'),
    'abfallio-af91b65d': ('Gemeinde Groß Pankow (Landkreis Prignitz)', 'BB'),
    'abfallio-3cefa45a': ('Gemeinde Gumtow (Landkreis Prignitz)', 'BB'),
    'abfallio-798f59a7': ('Gemeinde Karstädt (Landkreis Prignitz)', 'BB'),
    'abfallio-bb937857': ('Amt Lenzen-Elbtalaue (Landkreis Prignitz)', 'BB'),
    'abfallio-4638881e': ('Amt Meyenburg (Landkreis Prignitz)', 'BB'),
    'abfallio-9fb3e2e5': ('Stadt Perleberg (Landkreis Prignitz)', 'BB'),
    'abfallio-a0461612': ('Gemeinde Plattenburg (Landkreis Prignitz)', 'BB'),
    'abfallio-d92f59ef': ('Stadt Pritzwalk (Landkreis Prignitz)', 'BB'),
    'abfallio-4f06df48': ('Amt Putlitz/Berge (Landkreis Prignitz)', 'BB'),
    'abfallio-b870ecfa': ('Stadt Wittenberge (Landkreis Prignitz)', 'BB'),
    # ctrace + awgbassum (state already given in the source)
    'ctrace-bremen': ('Bremer Stadtreinigung', 'HB'),
    'ctrace-arnsberg': ('Stadt Arnsberg', 'NW'),
    'ctrace-landau': ('EWB Landau in der Pfalz', 'RP'),
    'ctrace-oberursel': ('BSO Oberursel', 'HE'),
    'awg-bassum': ('AWG Bassum (Landkreis Diepholz)', 'NI'),
}

# Providers whose towns may span states: geocode every town instead of inheriting.
PER_TOWN = {'jumomind-mymuell', 'abfallio-e5543a3e'}

# Providers with an empty town list: verify against the authority's seat instead.
SEAT = {'abfallio-040b38fe': 'Osterholz-Scharmbeck', 'abfallio-594f805e': 'Kitzingen'}

# ── Photon ──────────────────────────────────────────────────────────────────
_cache_lock = threading.Lock()
cache = {}
if os.path.exists(CACHE):
    with open(CACHE) as f:
        cache = json.load(f)


def save_cache():
    with _cache_lock:
        tmp = CACHE + '.tmp'
        with open(tmp, 'w') as f:
            json.dump(cache, f, ensure_ascii=False)
        os.replace(tmp, CACHE)


def photon_raw(q):
    """One Photon query; retries once on 429/5xx. Returns list of features."""
    url = 'https://photon.komoot.io/api/?' + urllib.parse.urlencode(
        {'q': q, 'lang': 'de', 'limit': 5, 'osm_tag': 'place'})
    for attempt in range(3):
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'aporah-census/1.0'})
            with urllib.request.urlopen(req, timeout=20) as r:
                return json.load(r).get('features', [])
        except urllib.error.HTTPError as e:
            if e.code == 429 or e.code >= 500:
                time.sleep(3.0 * (attempt + 1))
                continue
            print(f'photon {q!r}: HTTP {e.code}', file=sys.stderr)
            return None
        except Exception as e:
            print(f'photon {q!r}: {e} (attempt {attempt + 1})', file=sys.stderr)
            time.sleep(3.0 * (attempt + 1))
    return None


def photon(q):
    with _cache_lock:
        if q in cache:
            return cache[q]
    feats = photon_raw(q)
    if feats is None:
        return None
    slim = []
    for f in feats:
        p = f.get('properties', {})
        slim.append({
            'name': p.get('name'), 'osm_key': p.get('osm_key'), 'osm_value': p.get('osm_value'),
            'country': p.get('countrycode'), 'state': p.get('state'), 'city': p.get('city'),
            'county': p.get('county'),
        })
    with _cache_lock:
        cache[q] = slim
    return slim


def state_of(hit):
    s = hit.get('state')
    if not s and hit.get('city') in ('Berlin', 'Hamburg'):
        s = hit['city']
    if not s and hit.get('name') in ('Berlin', 'Hamburg', 'Bremen'):
        s = hit['name']
    return STATE_CODES.get(s)


def de_places(hits):
    return [h for h in hits or [] if h.get('osm_key') == 'place' and h.get('country') == 'DE']


def norm(s):
    return re.sub(r'\s+', ' ', (s or '').strip().lower())


def clean_town(name):
    """Strip authority prefixes / district suffixes so Photon sees a place name."""
    n = name
    n = re.sub(r'^(SLF-RU-|SOK-|VG |Gemeinden? |Markt |Stadt )', '', n)
    n = re.sub(r'\s+(Kernstadt|Nord|Süd|Ost|West|mit .*)$', '', n)
    n = n.replace('/WN', '').strip()
    return n


def resolve_town(name):
    """Geocode one town. Returns dict {state, ambiguous, matched, query}."""
    q = clean_town(name)
    candidates = [q]
    # 'Municipality-District' or 'Municipality - District': the municipality decides.
    m = re.split(r'\s+-\s+|-', q, maxsplit=1)
    if len(m) == 2 and m[0] and m[0] not in candidates:
        candidates.append(m[0].strip())
    first_fallback = None
    failed = False
    for i, c in enumerate(candidates):
        raw_hits = photon(c)
        if raw_hits is None:
            failed = True
            continue
        hits = de_places(raw_hits)
        if not hits:
            continue
        if first_fallback is None:
            first_fallback = hits[0]
        exact = [h for h in hits if norm(h['name']) == norm(c)]
        if exact:
            states = {state_of(h) for h in exact} - {None}
            st = state_of(exact[0])
            return {'state': st, 'ambiguous': len(states) > 1, 'matched': c,
                    'hit': exact[0]['name'], 'via_municipality': i > 0}
    if first_fallback:
        return {'state': state_of(first_fallback), 'ambiguous': True, 'matched': None,
                'hit': first_fallback['name'], 'via_municipality': False}
    return {'state': None, 'ambiguous': False, 'matched': None, 'hit': None, 'via_municipality': False,
            'failed': failed}


def geocode_many(names, label):
    """Batches of 4, ~150ms apart; results in cache. Returns {name: resolve_town(name)}."""
    out = {}
    todo = list(dict.fromkeys(names))
    done = 0
    with ThreadPoolExecutor(max_workers=2) as ex:
        for i in range(0, len(todo), 2):
            batch = todo[i:i + 2]
            for name, res in zip(batch, ex.map(resolve_town, batch)):
                out[name] = res
            done += len(batch)
            if done % 40 == 0 or done == len(todo):
                save_cache()
                print(f'  {label}: {done}/{len(todo)}', file=sys.stderr)
            time.sleep(0.5)
    save_cache()
    return out


# ── main ────────────────────────────────────────────────────────────────────
def main():
    raw = json.load(open(RAW))
    providers = raw['providers']
    missing = [p['id'] for p in providers if p['id'] not in ASSIGN]
    if missing:
        sys.exit(f'no assignment for: {missing}')

    out_providers = []
    unverified = []
    for p in providers:
        pid = p['id']
        display, st = ASSIGN[pid]
        entry = {'id': pid, 'displayName': display, 'family': p['family']}
        note = []

        if pid in PER_TOWN:
            print(f'{pid}: geocoding all {len(p["towns"])} towns', file=sys.stderr)
            res = geocode_many(p['towns'], pid)
            towns = []
            counts = {}
            for t in p['towns']:
                r = res[t]
                row = {'name': t, 'state': r['state']}
                if r['ambiguous']:
                    row['ambiguous'] = True
                if r['state'] is None:
                    row['lookupFailed' if r.get('failed') else 'unresolved'] = True
                if r.get('via_municipality'):
                    row['viaMunicipality'] = r['matched']
                towns.append(row)
                if r['state']:
                    counts[r['state']] = counts.get(r['state'], 0) + 1
            ordered = sorted(counts.items(), key=lambda kv: -kv[1])
            entry['towns'] = towns
            entry['stateCounts'] = dict(ordered)
            if st is None:
                # nationwide: provider state = the most common one, flagged
                entry['state'] = ordered[0][0] if ordered else None
                entry['stateConfidence'] = 'assigned'
                entry['spansStates'] = True
                note.append('nationwide app; towns mapped individually, `state` is the most frequent one')
            else:
                entry['state'] = st
                others = [k for k, _ in ordered if k != st]
                if others:
                    entry['stateConfidence'] = 'verified'
                    entry['spansStates'] = True
                    note.append(f'towns mapped individually; {st} is the majority, also {", ".join(others)}')
                else:
                    entry['stateConfidence'] = 'verified'
                    note.append('every town geocoded individually; all agree')
            unresolved = [t['name'] for t in towns if t.get('unresolved')]
            if unresolved:
                note.append(f'unresolved (no German place): {", ".join(unresolved)}')
            failed = [t['name'] for t in towns if t.get('lookupFailed')]
            if failed:
                note.append(f'LOOKUP FAILED (rerun): {len(failed)} towns')
        else:
            entry['state'] = st
            # pick two geocodable sample towns
            samples = []
            pool = [t for t in p['towns'] if not re.search(r'Kernstadt|Altstadt|/', t)]
            if not pool and pid in SEAT:
                pool = [SEAT[pid]]
                note.append(f'provider returned no towns; verified against its seat {SEAT[pid]}')
            elif not pool:
                pool = p['towns']
            for t in pool:
                if len(samples) >= 2:
                    break
                r = resolve_town(t)
                time.sleep(0.5)
                if r['state'] and r['matched']:
                    samples.append({'town': t, 'state': r['state'], 'hit': r['hit']})
            if len(samples) < 2:
                # accept fuzzy matches rather than nothing
                for t in pool:
                    if len(samples) >= 2:
                        break
                    if any(s['town'] == t for s in samples):
                        continue
                    r = resolve_town(t)
                    if r['state']:
                        samples.append({'town': t, 'state': r['state'], 'hit': r['hit'], 'fuzzy': True})
            entry['samples'] = samples
            agree = [s for s in samples if s['state'] == st]
            if len(samples) >= 2 and len(agree) == len(samples) and pid not in SEAT:
                entry['stateConfidence'] = 'verified'
            elif len(samples) >= 1 and len(agree) == len(samples) and pid in SEAT:
                entry['stateConfidence'] = 'assigned'
                unverified.append(pid)
            else:
                entry['stateConfidence'] = 'assigned'
                unverified.append(pid)
                if samples and len(agree) < len(samples):
                    disagree = [f"{s['town']}→{s['state']}" for s in samples if s['state'] != st]
                    note.append(f'sample disagreement: {", ".join(disagree)} (assignment {st} kept from the authority name)')
                elif not samples:
                    note.append('no sample town could be geocoded')
            entry['towns'] = [{'name': t, 'state': st} for t in p['towns']]
            save_cache()
        if note:
            entry['note'] = '; '.join(note)
        out_providers.append(entry)
        print(f"{pid}: {entry['state']} {entry['stateConfidence']} {entry.get('note','')}", file=sys.stderr)

    with open(OUT, 'w') as f:
        json.dump({'at': raw.get('at'), 'providers': out_providers}, f, ensure_ascii=False, indent=1)
    write_summary(out_providers)
    print('unverified:', unverified, file=sys.stderr)


BIG_CITIES = ['Berlin', 'Hamburg', 'München', 'Köln', 'Frankfurt am Main', 'Stuttgart', 'Düsseldorf',
              'Leipzig', 'Dortmund', 'Essen', 'Bremen', 'Dresden', 'Hannover', 'Nürnberg', 'Duisburg',
              'Bochum', 'Wuppertal', 'Bielefeld', 'Bonn', 'Münster', 'Mannheim', 'Karlsruhe', 'Augsburg',
              'Wiesbaden', 'Mönchengladbach', 'Gelsenkirchen', 'Aachen', 'Braunschweig', 'Chemnitz', 'Kiel',
              'Halle (Saale)', 'Magdeburg', 'Freiburg', 'Krefeld', 'Mainz', 'Lübeck', 'Erfurt', 'Oberhausen',
              'Rostock', 'Kassel', 'Hagen', 'Potsdam', 'Saarbrücken', 'Hamm', 'Ludwigshafen', 'Mülheim',
              'Oldenburg', 'Osnabrück', 'Leverkusen', 'Darmstadt', 'Heidelberg', 'Solingen', 'Regensburg',
              'Herne', 'Paderborn', 'Neuss', 'Ingolstadt', 'Offenbach', 'Fürth', 'Würzburg', 'Ulm', 'Heilbronn',
              'Pforzheim', 'Wolfsburg', 'Göttingen', 'Bottrop', 'Reutlingen', 'Koblenz', 'Bremerhaven',
              'Recklinghausen', 'Bergisch Gladbach', 'Erlangen', 'Remscheid', 'Jena', 'Trier', 'Salzgitter',
              'Moers', 'Siegen', 'Hildesheim', 'Cottbus']
CITY_STATE = {'Berlin': 'BE', 'Hamburg': 'HH', 'München': 'BY', 'Köln': 'NW', 'Frankfurt am Main': 'HE',
              'Stuttgart': 'BW', 'Düsseldorf': 'NW', 'Leipzig': 'SN', 'Dortmund': 'NW', 'Essen': 'NW',
              'Bremen': 'HB', 'Dresden': 'SN', 'Hannover': 'NI', 'Nürnberg': 'BY', 'Duisburg': 'NW',
              'Bochum': 'NW', 'Wuppertal': 'NW', 'Bielefeld': 'NW', 'Bonn': 'NW', 'Münster': 'NW',
              'Mannheim': 'BW', 'Karlsruhe': 'BW', 'Augsburg': 'BY', 'Wiesbaden': 'HE', 'Mönchengladbach': 'NW',
              'Gelsenkirchen': 'NW', 'Aachen': 'NW', 'Braunschweig': 'NI', 'Chemnitz': 'SN', 'Kiel': 'SH',
              'Halle (Saale)': 'ST', 'Magdeburg': 'ST', 'Freiburg': 'BW', 'Krefeld': 'NW', 'Mainz': 'RP',
              'Lübeck': 'SH', 'Erfurt': 'TH', 'Oberhausen': 'NW', 'Rostock': 'MV', 'Kassel': 'HE',
              'Hagen': 'NW', 'Potsdam': 'BB', 'Saarbrücken': 'SL', 'Hamm': 'NW', 'Ludwigshafen': 'RP',
              'Mülheim': 'NW', 'Oldenburg': 'NI', 'Osnabrück': 'NI', 'Leverkusen': 'NW', 'Darmstadt': 'HE',
              'Heidelberg': 'BW', 'Solingen': 'NW', 'Regensburg': 'BY', 'Herne': 'NW', 'Paderborn': 'NW',
              'Neuss': 'NW', 'Ingolstadt': 'BY', 'Offenbach': 'HE', 'Fürth': 'BY', 'Würzburg': 'BY', 'Ulm': 'BW',
              'Heilbronn': 'BW', 'Pforzheim': 'BW', 'Wolfsburg': 'NI', 'Göttingen': 'NI', 'Bottrop': 'NW',
              'Reutlingen': 'BW', 'Koblenz': 'RP', 'Bremerhaven': 'HB', 'Recklinghausen': 'NW',
              'Bergisch Gladbach': 'NW', 'Erlangen': 'BY', 'Remscheid': 'NW', 'Jena': 'TH', 'Trier': 'RP',
              'Salzgitter': 'NI', 'Moers': 'NW', 'Siegen': 'NW', 'Hildesheim': 'NI', 'Cottbus': 'BB'}
# Census spellings that are the same city (the whole city, not a district of it).
CITY_ALIASES = {
    'Frankfurt am Main': ['Frankfurt', 'Frankfurt a. M.', 'Frankfurt a.M.'],
    'Ludwigshafen': ['Ludwigshafen am Rhein'],
    'Mülheim': ['Mülheim an der Ruhr'],
    'Offenbach': ['Offenbach am Main'],
    'Freiburg': ['Freiburg im Breisgau'],
    'Halle (Saale)': ['Halle'],
    'Oldenburg': ['Oldenburg (Oldb)', 'Oldenburg (Oldenburg)'],
}


def city_matches(city, town, town_state):
    """Exact / word-boundary match: the census town IS the city (or 'City-District' /
    'City - District' of it), never a substring inside another word."""
    names = [city] + CITY_ALIASES.get(city, [])
    tn = norm(town)
    for n in names:
        nn = norm(n)
        if tn == nn:
            return True
        # 'Alzenau-Albstadt' style: municipality followed by a district separator
        if re.match(r'^' + re.escape(nn) + r'(\s+-\s+|-)\S', tn):
            return True
    return False


def write_summary(providers):
    by_state = {}
    for p in providers:
        for t in p['towns']:
            s = t['state'] or '??'
            d = by_state.setdefault(s, {'towns': 0, 'providers': set()})
            d['towns'] += 1
            d['providers'].add(p['displayName'])
        if p['state'] and not p.get('spansStates'):
            by_state.setdefault(p['state'], {'towns': 0, 'providers': set()})['providers'].add(p['displayName'])
    lines = ['# Abfall census by Bundesland', '',
             f'{len(providers)} providers, {sum(len(p["towns"]) for p in providers)} towns. '
             'A provider whose towns span states (MyMüll, Schönmackers) is counted in every state '
             'it has a town in; town counts are per town.', '',
             '| Bundesland | Providers | Towns | Provider names |', '|---|---:|---:|---|']
    order = ['BW', 'BY', 'BE', 'BB', 'HB', 'HH', 'HE', 'MV', 'NI', 'NW', 'RP', 'SL', 'SN', 'ST', 'SH', 'TH', '??']
    for code in order:
        d = by_state.get(code)
        if not d:
            lines.append(f'| {code} {STATE_NAMES.get(code, "")} | 0 | 0 | — |')
            continue
        label = f'{code} {STATE_NAMES[code]}' if code in STATE_NAMES else '?? unresolved (test rows in MyMüll)'
        names = '; '.join(sorted(d['providers'], key=lambda s: s.lower()))
        lines.append(f'| {label} | {len(d["providers"])} | {d["towns"]} | {names} |')
    lines += ['', '## Largest German cities: covered?', '',
              'Exact / word-boundary match of the census town name against the city name '
              '(a "City-District" town of the city counts; a name that merely contains the city does not).', '',
              '| # | City | State | Covered | Provider(s) | Matching census town |', '|---:|---|---|---|---|---|']
    covered = 0
    for i, city in enumerate(BIG_CITIES, 1):
        hits = []
        for p in providers:
            for t in p['towns']:
                if t['state'] == CITY_STATE[city] and city_matches(city, t['name'], t['state']):
                    hits.append((p['displayName'], t['name']))
        if hits:
            covered += 1
        provs = '; '.join(sorted({h[0] for h in hits}))
        towns = ', '.join(sorted({h[1] for h in hits}))
        if len(towns) > 60:
            towns = towns[:57] + '…'
        lines.append(f'| {i} | {city} | {CITY_STATE[city]} | {"yes" if hits else "no"} | {provs or "—"} | {towns or "—"} |')
    lines += ['', f'Covered: {covered} of {len(BIG_CITIES)}.']
    lines += ['', '## Providers not verified by two matching samples', '']
    for p in providers:
        if p['stateConfidence'] != 'verified':
            lines.append(f'- `{p["id"]}` ({p["displayName"]}): {p["state"]} — {p.get("note", "")}')
    with open(SUMMARY, 'w') as f:
        f.write('\n'.join(lines) + '\n')


if __name__ == '__main__':
    main()
