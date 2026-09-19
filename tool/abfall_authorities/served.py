"""Which register towns the app already recognises — with the app's own rule.

Mirrors `townMatches` in supabase/functions/_shared/abfall/core.ts: a lowercase
whole-word containment either way, and a provider in another Bundesland never
counts (resolve.ts `wrongState`). A census town of an upload-only provider is
recognised too — the household is sent to that provider's page — so it is
reported apart from the live ones."""
import json, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
_NAME = re.compile(r'[a-z0-9äöüß]')


def contains_word(hay, needle):
    if len(needle) < 3:
        return False
    start = 0
    while True:
        at = hay.find(needle, start)
        if at < 0:
            return False
        before = hay[at - 1] if at else ''
        after = hay[at + len(needle)] if at + len(needle) < len(hay) else ''
        if not (before and _NAME.match(before)) and not (after and _NAME.match(after)):
            return True
        start = at + 1


def town_matches(cand, target):
    return cand == target or contains_word(cand, target) or contains_word(target, cand)


def geocoder_name(register_name):
    """'Büren, Stadt' / 'Neustadt a.d.Aisch' → what a geocoder calls the town."""
    return register_name.split(',')[0].strip().lower()


def load_census():
    """state -> list of (lowercase town name, provider id, upload?)"""
    census = json.load(open(os.path.join(HERE, '../abfall_census/census_states.json')))
    src = open(os.path.join(HERE, '../../supabase/functions/_shared/abfall_providers.ts')).read()
    upload_ids = set(re.findall(r"id: '([^']+)'[^\n]*\n?[^\n]*upload: \{", src))
    # the jumomind family builds its rows in a map() with the upload flag on all of them
    upload_ids |= {p['id'] for p in census['providers'] if p['family'] == 'jumomind'}
    by_state = {}
    for p in census['providers']:
        for t in p['towns']:
            st = t.get('state') or p.get('state')
            by_state.setdefault(st, []).append((t['name'].lower(), p['id'], p['id'] in upload_ids))
    return by_state, upload_ids


def served_by(by_state, state, register_name):
    """(live provider ids, upload provider ids) that recognise this town."""
    target = geocoder_name(register_name)
    live, up = set(), set()
    for name, pid, is_up in by_state.get(state, []):
        if town_matches(name, target):
            (up if is_up else live).add(pid)
    return live, up


# ── Strict: the name itself, in a county the provider serves ─────────────────
# Containment (the app's rule) also lets "Buch a.Erlbach" hit Altötting's
# "Erlbach". For the atlas a town counts as recognised only when its base name
# equals a census town's base name — the census side losing its district
# ("Altenbeken-Buke" → "altenbeken"), the register side only its suffixes
# ("Büren, Stadt", "Wörth a.d.Isar") — AND the provider demonstrably serves
# that county: at least 3 register towns of the county match it, or it names
# one town only.
_REG = r',| \(|/| an der | am | im | in | a\. ?d\. ?| a\.| i\.| b\.| bei | v\. ?d\. '
_CEN = _REG + r'| - |-'


def _clean(n):
    n = re.sub(r'^(bad|hansestadt|stadt) ', '', n.strip())
    return re.sub(r'[^a-zäöüß]', '', n)


def reg_base(n):
    return _clean(re.split(_REG, n.lower())[0])


def cen_base(n):
    return _clean(re.split(_CEN, n.lower())[0])


def strict_index(by_state, register, st_of):
    idx, size = {}, {}
    for st, rows in by_state.items():
        for name, pid, is_up in rows:
            idx.setdefault((st, cen_base(name)), set()).add((pid, is_up))
            size[pid] = size.get(pid, 0) + 1
    hits = {}
    for t in register:
        for pid, _ in idx.get((st_of(t['ars']), reg_base(t['name'])), ()):
            hits[(pid, t['kreis'])] = hits.get((pid, t['kreis']), 0) + 1
    ok = {k for k, n in hits.items() if n >= 3 or size[k[0]] == 1}
    return idx, ok


def served_strict(index, state, town):
    idx, ok = index
    hits = [(p, u) for p, u in idx.get((state, reg_base(town['name'])), ()) if (p, town['kreis']) in ok]
    return {p for p, u in hits if not u}, {p for p, u in hits if u}
