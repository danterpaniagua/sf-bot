#!/usr/bin/env python3
"""GITIN-2252 — local summary of the files written by sqs-spikes-pull.sh (reads saved files only). Usage: sqs-spikes-analyze.py <data dir> <HHMM suffix>
Times are shown in UTC-3. For PRD_BranchMessages.fifo: per window the maximum of the per-minute Maximum/Sum and the minute it occurred; for the dead-letter queues: total sent over the day and the highest visible count."""
import json, sys, os
from datetime import datetime, timezone, timedelta
d, sfx = sys.argv[1], sys.argv[2]
TZ = timezone(timedelta(hours=-3))
def load(name):
    txt = open(os.path.join(d, name)).read()
    j = txt[txt.index("{"):] if "{" in txt else None
    if j is None: return None, txt.strip().splitlines()[-1]
    return json.loads(j), None
def pts(name, stat):
    j, err = load(name)
    if j is None: return None, err
    return sorted((datetime.fromisoformat(p["Timestamp"]).astimezone(TZ), p.get(stat)) for p in j["Datapoints"] if p.get(stat) is not None), None
WIN = [("W1 WEBS-02 saturated 14:03-15:28", (14,3),(15,28)), ("W2 second saturation 16:34-17:10", (16,34),(17,10)),
       ("W3 POST surge 17:10-18:20", (17,10),(18,20)), ("W4 Mobile spike 19:02-19:18", (19,2),(19,18))]
def inwin(t, a, b): return (t.hour, t.minute) >= a and (t.hour, t.minute) < b
def show(label, name, stat):
    p, err = pts(name, stat)
    if p is None: print(f"{label} {stat}: {err}"); return
    allmax = max(p, key=lambda x: x[1]) if p else None
    print(f"{label} {stat}: {len(p)} points; day peak {allmax[1]:g} at {allmax[0]:%H:%M}" if p else f"{label} {stat}: no points")
    for w, a, b in WIN:
        q = [x for x in p if inwin(x[0], a, b)]
        if q:
            m = max(q, key=lambda x: x[1]); mean = sum(x[1] for x in q) / len(q)
            print(f"   {w}: peak {m[1]:g} at {m[0]:%H:%M}, mean {mean:.1f} ({len(q)} points)")
        else: print(f"   {w}: no points")
q = "PRD_BranchMessages"
for m, stats in [("NumberOfMessagesSent", ("Sum","Maximum")), ("NumberOfMessagesReceived", ("Sum","Maximum")), ("NumberOfMessagesDeleted", ("Sum","Maximum")), ("ApproximateAgeOfOldestMessage", ("Maximum",)), ("ApproximateNumberOfMessagesVisible", ("Maximum",))]:
    for st in stats: show(f"{q} {m}", f"sqs-{q}-{m}-{sfx}.txt", st)
print()
for Q in ("MainDeadLetter.fifo", "DeadLetter.fifo"):
    p, err = pts(f"sqs-{Q}-NumberOfMessagesSent-{sfx}.txt", "Sum")
    v, err2 = pts(f"sqs-{Q}-ApproximateNumberOfMessagesVisible-{sfx}.txt", "Maximum")
    print(f"{Q}: sent total {sum(x[1] for x in p):g} over {len(p)} points; highest visible {max((x[1] for x in v), default=0):g} ({len(v)} points)" if p is not None and v is not None else f"{Q}: {err or err2}")
