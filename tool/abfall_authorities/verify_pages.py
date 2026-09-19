"""Fetch every page an agent reported and say whether it holds up.

Reads a results JSON ({towns:[...]}) and writes <name>_verified.json with, per town:
http status, final URL after redirects, whether the page talks about bins at all, whether
it mentions an iCal export, and whether it mentions a PDF. Agents return wrong or dead URLs
with full confidence; nothing goes into the app that this has not fetched.

    python3 verify_pages.py pilot_nrw_results.json
"""
import json, re, sys, ssl, urllib.request, concurrent.futures as cf
from urllib.parse import urlparse

UA = 'Aporah-Abfall-Check/1.0 (+philipecampagnaro@gmail.com)'
BINS = re.compile(r'abfall|m[üu]ll|tonne|abfuhr|entsorgung|wertstoff', re.I)
ICS = re.compile(r'\bical\b|\.ics\b|icalendar|webcal|kalender[- ]?(export|datei|abonn)|in (ihren|den) kalender|outlook|ics-datei', re.I)
PDF = re.compile(r'\.pdf\b|pdf-download|als pdf', re.I)
ctx = ssl.create_default_context()

def check(t):
    url = t.get('page_url')
    out = {'ars': t['ars'], 'url': url}
    if not url:
        return {**out, 'status': None, 'ok': False}
    try:
        req = urllib.request.Request(url, headers={'User-Agent': UA, 'Accept-Language': 'de'})
        with urllib.request.urlopen(req, timeout=25, context=ctx) as r:
            body = r.read(2_000_000).decode('utf-8', 'replace')
            final, status = r.geturl(), r.status
    except urllib.error.HTTPError as e:
        return {**out, 'status': e.code, 'ok': False}
    except Exception as e:
        return {**out, 'status': type(e).__name__, 'ok': False}
    return {**out, 'status': status, 'final': final,
            'moved_host': urlparse(final).netloc != urlparse(url).netloc,
            'bins': bool(BINS.search(body)), 'ics_hint': bool(ICS.search(body)), 'pdf_hint': bool(PDF.search(body)),
            'ok': status == 200 and bool(BINS.search(body))}

src = sys.argv[1]
data = json.load(open(src))
with cf.ThreadPoolExecutor(8) as ex:
    checks = {c['ars']: c for c in ex.map(check, data['towns'])}
for t in data['towns']:
    t['check'] = checks[t['ars']]
json.dump(data, open(src.replace('.json', '_verified.json'), 'w'), ensure_ascii=False, indent=1)
n = len(data['towns'])
ok = sum(t['check']['ok'] for t in data['towns'])
print(f'{ok}/{n} pages load and talk about bins')
for t in data['towns']:
    c = t['check']
    if not c['ok']: print('  FAIL', t['name'], c.get('status'), c.get('url'))
