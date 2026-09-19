"""Fetch every page in germany_results.json that has not been checked yet.

Same test as verify_pages.py (status 200 and the page talks about bins), keyed
by URL rather than by town, because one county page serves dozens of towns.
Results accumulate in checks.json, which build_tracker.py reads.

    python3 verify_urls.py
"""
import json, os, re, ssl, http.cookiejar, urllib.request, concurrent.futures as cf
from urllib.parse import urlparse, quote

UA = 'Aporah-Abfall-Check/1.0 (+philipecampagnaro@gmail.com)'
BINS = re.compile(r'abfall|m[üu]ll|tonne|abfuhr|entsorgung|wertstoff', re.I)
ICS = re.compile(r'\bical\b|\.ics\b|icalendar|webcal|kalender[- ]?(export|datei|abonn)|in (ihren|den) kalender|outlook|ics-datei', re.I)
PDF = re.compile(r'\.pdf\b|pdf-download|als pdf', re.I)
ctx = ssl.create_default_context()

def check(url):
    try:
        # Town CMSes (IKISS) bounce a first visit through a 307 that sets a
        # cookie, so each fetch keeps its own jar; umlauts in paths are quoted.
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()),
                                             urllib.request.HTTPSHandler(context=ctx))
        req = urllib.request.Request(quote(url, safe=':/?&=%#,+|;~'), headers={'User-Agent': UA, 'Accept-Language': 'de'})
        with opener.open(req, timeout=25) as r:
            body = r.read(2_000_000).decode('utf-8', 'replace')
            final, status = r.geturl(), r.status
    except urllib.error.HTTPError as e:
        return url, {'status': e.code, 'ok': False}
    except Exception as e:
        return url, {'status': type(e).__name__, 'ok': False}
    return url, {'status': status, 'final': final, 'moved_host': urlparse(final).netloc != urlparse(url).netloc,
                 'bins': bool(BINS.search(body)), 'ics_hint': bool(ICS.search(body)), 'pdf_hint': bool(PDF.search(body)),
                 'ok': status == 200 and bool(BINS.search(body))}

checks = json.load(open('checks.json')) if os.path.exists('checks.json') else {}
urls = set()
for b in json.load(open('germany_results.json')):
    for c in b['counties']:
        pages = ([c['county_page']] if c.get('county_page') else []) + [t['page'] for t in c.get('town_pages', [])]
        urls |= {p['page_url'] for p in pages if p.get('page_url')}
todo = sorted(u for u in urls if u not in checks or not checks[u]['ok'])
with cf.ThreadPoolExecutor(8) as ex:
    for url, res in ex.map(check, todo):
        checks[url] = res
json.dump(checks, open('checks.json', 'w'), ensure_ascii=False, indent=1)
bad = [u for u in urls if not checks[u]['ok']]
print(f'{len(todo)} new, {len(urls) - len(bad)}/{len(urls)} pages load and talk about bins')
for u in sorted(bad): print('  FAIL', checks[u]['status'], u)
