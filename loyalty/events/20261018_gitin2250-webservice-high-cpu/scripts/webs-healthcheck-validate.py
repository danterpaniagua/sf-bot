#!/usr/bin/env python3
"""GITIN-2250 — local analysis (reads saved files, touches nothing else): does the balancer probe on healthcheck.ashx fail when the host is busy, as the handler's code says?
Usage: webs-healthcheck-validate.py <dip json> <cpu jsonl>
Handler (read on WEBS-02): HTTP 400 if one 500 ms sample of Processor(_Total) or the commit ratio is above 80, else 200. The probe (15 s, 1 failure = unhealthy) is averaged per minute in DipAvailability.
Per host, per 1-minute CPU bucket: minutes, mean probe availability, share of minutes with any probe lost. CPU is a 1-minute value, the handler a 500 ms sample, so only a trend is expected, not an exact threshold."""
import json, sys, collections
IP = {"192.168.50.101": "WEBS-01", "192.168.50.102": "WEBS-02", "192.168.50.103": "WEBS-03"}
ITEM = {"51092": "WEBS-01", "51190": "WEBS-02", "51288": "WEBS-03"}
BUCKETS = [(0, 40), (40, 60), (60, 80), (80, 101)]
dip = json.load(open(sys.argv[1]))
avail = collections.defaultdict(dict)  # host -> epoch minute -> availability %
from datetime import datetime, timezone
for m in dip.get("value", []):
    for ts in m.get("timeseries", []):
        ip = ts["metadatavalues"][0]["value"]
        host = IP.get(ip, ip)
        for d in ts["data"]:
            if d.get("average") is None:
                continue
            t = datetime.fromisoformat(d["timeStamp"].replace("Z", "+00:00")).replace(tzinfo=timezone.utc)
            avail[host][int(t.timestamp()) // 60] = float(d["average"])
cpu = collections.defaultdict(dict)
for line in open(sys.argv[2]):
    r = json.loads(line)
    cpu[ITEM[r["itemid"]]][int(r["clock"]) // 60] = float(r["value"])
print("host | CPU 1-min bucket | minutes | mean probe % | minutes with probe < 100 % | share")
for host in sorted(cpu):
    rows = collections.defaultdict(list)
    for mn, c in cpu[host].items():
        if mn in avail[host]:
            for lo, hi in BUCKETS:
                if lo <= c < hi:
                    rows[(lo, hi)].append(avail[host][mn])
    for b in BUCKETS:
        v = rows.get(b, [])
        if v:
            lost = sum(1 for x in v if x < 99.9)
            print(f"{host} | {b[0]}-{min(b[1],100)} | {len(v)} | {sum(v)/len(v):.1f} | {lost} | {100*lost/len(v):.0f} %")
        else:
            print(f"{host} | {b[0]}-{min(b[1],100)} | 0 | - | - | -")
    both = len(set(cpu[host]) & set(avail[host]))
    print(f"{host}: {len(cpu[host])} CPU minutes, {len(avail[host])} probe minutes, {both} joined")
