"""Pull vendor configs (abfall.io key, Athos host, AWIDO client, …) out of the
official pages in the atlas, so a county on a family the app already reads can
become one provider row. Reads the atlas data, fetches each distinct page plus
the iframes/scripts on it that point at a vendor, writes vendor_configs.json.

    python3 find_configs.py <atlas.html>
"""
import json, re, sys, os, threading, http.cookiejar
import urllib.request
from urllib.parse import urljoin, quote
from concurrent.futures import ThreadPoolExecutor

UA = 'Aporah-Abfall-Check/1.0 (+philipecampagnaro@gmail.com)'
PATTERNS = {
    'abfallio': [r'api\.abfall\.io[^"\'<>]*?[?&]key=([0-9a-f]{32})', r'abfall\.io[^<]{0,400}?["\']key["\']?\s*[:=]\s*["\']([0-9a-f]{32})'],
    'abfallplus': [r'abfallplus-publisher[^>]*?key=["\']?([0-9a-f]{32})', r'widgets\.abfall\.io[^<]{0,300}?([0-9a-f]{32})'],
    'athos': [r'(https?://[^\s"\'<>]+?/WasteManagement[A-Za-z0-9]+)'],
    'awido': [r'awido\.cubefour\.de/(?:Customer|WebServices)?/?([a-z0-9-]+)/', r'awido\.cubefour\.de[^"\'<>]*?[?&](?:client|customer)=([a-z0-9-]+)'],
    'ctrace': [r'((?:web|apps)\.c-trace\.de/[A-Za-z0-9._-]+)'],
    'muellmax': [r'muellmax\.de/abfallkalender/([a-z0-9]+)/'],
    'regioit': [r'([a-z0-9-]+)-abfallapp\.regioit\.de', r'abfallapp\.regioit\.de/abfall-app-([a-z0-9-]+)'],
    'insertit': [r'insert-it\.de/BmsAbfallkalender([A-Za-z0-9]+)'],
    'jumomind': [r'([a-z0-9]+)\.jumomind\.com', r'mymuell\.de/[^"\'<>]*?[?&]m=([a-z0-9]+)'],
    'advantic': [r'(advantic)', r'(Abfallmodul)'],
}
VENDOR_HOST = re.compile(r'abfall\.io|c-trace|cubefour|muellmax|regioit|insert-it|jumomind|mymuell|WasteManagement|advantic|abfallplus', re.I)
CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), '.page_cache')
os.makedirs(CACHE, exist_ok=True)


def fetch(url):
    key = os.path.join(CACHE, re.sub(r'[^A-Za-z0-9]', '_', url)[:180])
    if os.path.exists(key):
        return open(key, encoding='utf-8', errors='replace').read()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
    req = urllib.request.Request(quote(url, safe=':/?&=%#,+|;~'), headers={'User-Agent': UA, 'Accept-Language': 'de'})
    try:
        body = opener.open(req, timeout=25).read(3_000_000).decode('utf-8', 'replace')
    except Exception as e:
        body = f'<!-- fetch failed: {e} -->'
    open(key, 'w', encoding='utf-8').write(body)
    return body


def configs(text):
    out = {}
    for fam, pats in PATTERNS.items():
        for p in pats:
            for m in re.findall(p, text, re.I if fam == 'advantic' else 0):
                out.setdefault(fam, set()).add(m)
    return out


def scan(url):
    html = fetch(url)
    found = configs(html)
    subs = set()
    for src in re.findall(r'<(?:iframe|script|a)[^>]+(?:src|href)=["\']([^"\']+)', html, re.I):
        full = urljoin(url, src)
        if VENDOR_HOST.search(full) and full.startswith('http') and full != url:
            subs.add(full)
    for s in list(subs)[:6]:
        for fam, vals in configs(s + '\n' + fetch(s)).items():
            found.setdefault(fam, set()).update(vals)
    return url, {k: sorted(v) for k, v in found.items()}


if __name__ == '__main__':
    s = open(sys.argv[1]).read()
    data = json.loads(re.search(r'const DATA = (\{.*?\});\n', s, re.S).group(1))
    rows = [e for e in data['entries'] if e.get('url')]
    urls = sorted({e['url'] for e in rows})
    with ThreadPoolExecutor(8) as ex:
        res = dict(ex.map(scan, urls))
    out = []
    for e in rows:
        out.append({'st': e['st'], 'kreis': e['kreis'], 'scope': e['scope'], 'name': e['name'], 'n': e['n'],
                    'pop': e['pop'], 'fmt': e['fmt'], 'url': e['url'], 'publisher': e.get('publisher'),
                    'configs': res.get(e['url'], {})})
    json.dump(out, open('vendor_configs.json', 'w'), ensure_ascii=False, indent=1)
    from collections import Counter
    fam = Counter(); pop = Counter()
    for r in out:
        for f in r['configs']:
            fam[f] += 1; pop[f] += r['pop']
    for f, n in fam.most_common():
        print(f, n, 'rows', round(pop[f] / 1e6, 2), 'M')
    print(sum(1 for r in out if not r['configs']), 'rows with no vendor found')
