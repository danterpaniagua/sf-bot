#!/usr/bin/env python3
"""GITIN-2250 — local analysis: minutes with CPU (1-min) under 40 % in which the balancer probe still lost checks, per hour (UTC-3), WEBS-02 and WEBS-03.
Usage: webs-lowcpu-loss-by-hour.py <dip json> <cpu jsonl>   (same files as webs-healthcheck-validate.py)"""
import json, sys, collections
from datetime import datetime, timezone, timedelta
IP = {"192.168.50.101": "WEBS-01", "192.168.50.102": "WEBS-02", "192.168.50.103": "WEBS-03"}
ITEM = {"51092": "WEBS-01", "51190": "WEBS-02", "51288": "WEBS-03"}
dip = json.load(open(sys.argv[1])); av = collections.defaultdict(dict)
for m in dip["value"]:
    for ts in m["timeseries"]:
        h = IP.get(ts["metadatavalues"][0]["value"])
        for d in ts["data"]:
            if d.get("average") is not None:
                av[h][int(datetime.fromisoformat(d["timeStamp"].replace("Z", "+00:00")).timestamp()) // 60] = d["average"]
cpu = collections.defaultdict(dict)
for l in open(sys.argv[2]):
    r = json.loads(l); cpu[ITEM[r["itemid"]]][int(r["clock"]) // 60] = float(r["value"])
tz = timezone(timedelta(hours=-3))
for h in ["WEBS-02", "WEBS-03"]:
    lost, tot, vals = collections.Counter(), collections.Counter(), []
    for mn, c in cpu[h].items():
        if c < 40 and mn in av[h]:
            hr = datetime.fromtimestamp(mn * 60, tz).hour; tot[hr] += 1
            if av[h][mn] < 99.9:
                lost[hr] += 1; vals.append(round(av[h][mn]))
    print(h, "CPU<40 minutes with probe loss per hour (-03):", dict(sorted(lost.items())))
    print("   minutes with CPU<40 per hour:", dict(sorted(tot.items())))
    print("   probe availability in those minutes (rounded %: count):", dict(sorted(collections.Counter(vals).items())))
