"""robots.txt and terms for every candidate that read real dates.

For each: the exact paths its adapter requests, tested against the host's
robots.txt with our User-Agent and '*'; and the candidate's own pages grepped
for real non-commercial terms (imprint boilerplate is reported, not decided)."""
import json, re, urllib.request, urllib.robotparser, http.cookiejar
from urllib.parse import urlparse
from concurrent.futures import ThreadPoolExecutor
from find_configs import fetch

UA = 'Aporah-Abfall-Check/1.0 (+philipecampagnaro@gmail.com)'
probe = {r['id']: r for f in ('candidate_probe_run1.json', 'candidate_probe_run2.json', 'candidate_probe_run3.json', 'candidate_probe.json')
         for r in json.load(open(f))}
cands = {c['id']: c for c in json.load(open('candidates.json'))}
ok = [i for i, r in probe.items() if r['ok']]


def paths(c, fam):
    if fam == 'abfallio': return ['https://api.abfall.io/?key=' + c['key'] + '&modus=d6c5855a62cf32a4dadbc2831f0f295f&waction=init']
    if fam == 'abfallplus': return ['https://widgets.abfall.io/graphql']
    if fam == 'athos': return [c['host'] + '/WasteManagementServlet']
    if fam == 'awido': return [f"https://awido.cubefour.de/WebServices/Awido.Service.svc/secure/getPlaces/client={c['client']}"]
    if fam == 'muellmax': return [f"https://www.muellmax.de/abfallkalender/{c['client']}/res/{c['client'].capitalize()}Start.php"]
    if fam == 'ctrace': return [f"https://{c['host']}/{c['service']}/"]


_robots = {}
def robots(url):
    u = urlparse(url); root = f'{u.scheme}://{u.netloc}'
    if root not in _robots:
        rp = urllib.robotparser.RobotFileParser()
        try:
            opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
            res = opener.open(urllib.request.Request(root + '/robots.txt', headers={'User-Agent': UA}), timeout=20)
            body = res.read(200_000).decode('utf-8', 'replace')
            rp.parse(body.splitlines()) if res.status == 200 and 'html' not in res.headers.get('Content-Type', '') else rp.parse([])
            _robots[root] = (rp, body[:400] if res.status == 200 else f'HTTP {res.status}')
        except Exception as e:
            rp.parse([]); _robots[root] = (rp, f'none ({type(e).__name__})')
    rp, raw = _robots[root]
    return rp.can_fetch(UA, url) and rp.can_fetch('*', url), raw

TERMS = re.compile(r'(nicht[- ]?kommerziell|nichtkommerziell|non-commercial|ausschlie(ß|ss)lich (für den )?privat|gewerbliche (Nutzung|Verwendung)|Nutzungsbedingungen)', re.I)


def gate(i):
    r, c = probe[i], cands[i]
    fam = r['result']['family']
    rb = [(p, *robots(p)) for p in paths(c, fam)]
    hits = []
    for pg in c['pages']:
        for m in TERMS.finditer(re.sub(r'<[^>]+>', ' ', fetch(pg))):
            s = fetch(pg)
            txt = re.sub(r'\s+', ' ', re.sub(r'<[^>]+>', ' ', s))
            k = txt.lower().find(m.group(0).lower())
            hits.append(txt[max(0, k - 120):k + 160])
            break
    return {'id': i, 'family': fam, 'state': c['state'], 'kreise': c['kreise'], 'robots_ok': all(x[1] for x in rb),
            'robots': [{'url': p, 'allowed': a, 'file': raw[:200]} for p, a, raw in rb], 'terms_hits': hits[:2],
            'probe': {k: r['result'].get(k) for k in ('town', 'street', 'events', 'from', 'to', 'bins')},
            'towns': r['result'].get('towns', [])}

with ThreadPoolExecutor(8) as ex:
    out = list(ex.map(gate, ok))
json.dump(out, open('candidate_gate.json', 'w'), ensure_ascii=False, indent=1)
for g in out:
    print(('ROBOTS-NO ' if not g['robots_ok'] else '') + ('TERMS? ' if g['terms_hits'] else ''), g['id'], g['family'], list(g['kreise'].values())[:3])
print(len(out), 'gated;', sum(not g['robots_ok'] for g in out), 'blocked by robots;', sum(bool(g['terms_hits']) for g in out), 'with a terms phrase')
