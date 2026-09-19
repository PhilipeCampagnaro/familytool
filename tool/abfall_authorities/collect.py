"""Pull every finished batch out of one or more workflows' journals.

    python3 collect.py <journal.jsonl> [more.jsonl ...]   ->  germany_results.json
"""
import json, sys
labels, out = {}, []
for line in (l for p in sys.argv[1:] for l in open(p)):
    e = json.loads(line)
    if e.get('type') == 'started':
        labels[e['agentId']] = e['label']
    elif e.get('type') == 'result' and e.get('result'):
        out.append({'batch': int(labels[e['agentId']].split()[-1]), **e['result']})
out.sort(key=lambda b: b['batch'])
json.dump(out, open('germany_results.json', 'w'), ensure_ascii=False, indent=1)
print(len(out), 'batches:', [b['batch'] for b in out])
