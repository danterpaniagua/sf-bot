#!/usr/bin/env python3
"""Alert matrix from a zabbix-alert-compliance-pull.sh file: per host x metric (CPU, RAM, DISK, IIS), how many triggers and which enabled action(s) each routes to.
Usage: alert_matrix.py <pull file> [--groups g1,g2] [--hosts-like text]
Reads only the file (no network). Keyword classification of trigger descriptions is approximate; 'other' counts are shown so gaps are visible."""
import json, sys, re, collections, argparse

ap = argparse.ArgumentParser(); ap.add_argument('file'); ap.add_argument('--groups', default=''); ap.add_argument('--hosts-like', default='')
a = ap.parse_args()
sec = None; hosts = {}; trig = []; actions = []
for l in open(a.file):
    if l.startswith('== '): sec = l.strip(); continue
    if not l.startswith('{') or sec is None: continue
    j = json.loads(l)
    if sec.startswith('== hosts'): hosts[j['host']] = j
    elif sec.startswith('== triggers'): trig.append(j)
    elif sec.startswith('== trigger actions'): actions.append(j)

def cond_true(c, tags, groups):
    t, op, v, v2 = int(c['conditiontype']), int(c['operator']), c['value'], c.get('value2', '')
    if t == 25: hit = any(k == v for k, _ in tags) if op in (0, 2) else None   # event tag name
    elif t == 26:                                                                # event tag value
        pairs = [x for k, x in tags if k == v2]
        if op == 0: hit = v in pairs
        elif op == 1: hit = v not in pairs
        elif op == 2: hit = any(v in x for x in pairs)
        elif op == 3: hit = not any(v in x for x in pairs)
        else: return None
        return hit
    elif t == 0:                                                                  # host group
        return (v in groups) if op == 0 else (v not in groups)
    else: return None                                                             # unsupported condition type
    return hit

def action_matches(act, tags, groups):
    f = act['filter']; conds = f['conditions']; ev = int(f['evaltype'])
    res = {c['formulaid']: cond_true(c, tags, groups) for c in conds}
    if any(r is None for r in res.values()): return None
    if not conds: return True
    if ev == 1: return all(res.values())
    if ev == 2: return any(res.values())
    if ev == 0:                                                                   # and/or: same type or'd, different types and'd
        by = collections.defaultdict(list)
        for c in conds: by[(c['conditiontype'], c.get('value2', '') if c['conditiontype'] == '26' else '')].append(res[c['formulaid']])
        return all(any(v) for v in by.values())
    expr = f['formula']                                                           # custom
    for k in sorted(res, key=len, reverse=True): expr = re.sub(r'\b%s\b' % k, str(res[k]), expr)
    return eval(expr)

def cat(d):
    s = d.lower()
    if 'cpu' in s: return 'CPU'
    if 'memory' in s or 'swap' in s: return 'RAM'
    if any(w in s for w in ('disk', 'free space', 'space is', 'volume', 'filesystem', 'fs ')): return 'DISK'
    if any(w in s for w in ('iis', 'request queue', 'healthcheck', 'app pool', 'webservice', 'spike')): return 'IIS'
    return 'other'

wantg = {g for g in a.groups.split(',') if g}
def keep(h):
    if a.hosts_like and a.hosts_like.lower() not in h.lower(): return False
    if wantg and not (wantg & set(hosts.get(h, {}).get('groups', []))): return False
    return True

enabled = [x for x in actions if x['status'] == '0']
M = collections.defaultdict(lambda: collections.defaultdict(list)); unsupported = set()
for t in trig:
    h = t['host']
    if not keep(h): continue
    tags = [tuple(x.split('=', 1)) for x in t['tags']]
    groups = hosts.get(h, {}).get('groups', [])
    dest = []
    for act in enabled:
        m = action_matches(act, tags, groups)
        if m is None: unsupported.add(act['actionid'])
        elif m: dest.append('%s:%s' % (act['actionid'], act['name'][:28]))
    M[h][cat(t['d'])].append((t['p'], dest))

print('enabled trigger actions:', ', '.join('%s=%s' % (x['actionid'], x['name']) for x in enabled))
if unsupported: print('NOTE: actions with condition types this script cannot evaluate (routing unknown for them):', sorted(unsupported))
print('%-18s %s' % ('host', 'CPU | RAM | DISK | IIS   (n triggers: destination xcount; NONE = no enabled action matches)'))
for h in sorted(M):
    row = []
    for c in ('CPU', 'RAM', 'DISK', 'IIS', 'other'):
        L = M[h].get(c, [])
        if not L: row.append('%s:-' % c); continue
        cnt = collections.Counter(','.join(d) or 'NONE' for _, d in L)
        row.append('%s:%dt[%s]' % (c, len(L), ' '.join('%sx%d' % (k, v) for k, v in cnt.items())))
    print('%-18s %s' % (h, ' | '.join(row)))
off = [h for h, x in hosts.items() if x['status'] != '0' and keep(h)]
print('disabled hosts (not monitored):', ', '.join(sorted(off)) or '-')
