#!/usr/bin/env python3
"""GITIN-2252 — local analysis of the files written by platform-since-friday-pull.sh (reads saved JSON only).
Usage: platform-since-friday-analyze.py <run dir>
Per -03:00 day and service: stretches / minutes with Running < Desired and lowest Running; the same for the busy hours 13:00-23:59 (-03:00); 17-10 also split at the capacity change (11:28:38 -03:00).
Platform CPU (AWS/ECS, service level): highest Maximum, highest Average, and minutes above 60 and above 75 on each statistic. CloudWatch prints timestamps in the CLI's local zone (-03:00)."""
import json, sys, glob, os
from datetime import datetime, timezone, timedelta
run = sys.argv[1]
TZ = timezone(timedelta(hours=-3))
CHANGE = datetime(2026, 10, 17, 11, 28, 38, tzinfo=TZ)
def series(res, id_):
    r = next(x for x in res["MetricDataResults"] if x["Id"] == id_)
    return {datetime.fromisoformat(t).astimezone(TZ): v for t, v in zip(r["Timestamps"], r["Values"])}
def stretches(run_s, des_s, keep=lambda t: True):
    n_str = n_min = 0; low = None; in_run = False
    for t in sorted(run_s):
        if not keep(t): in_run = False; continue
        d = des_s.get(t)
        below = d is not None and run_s[t] < d
        if below:
            n_min += 1; low = run_s[t] if low is None else min(low, run_s[t])
            if not in_run: n_str += 1
        in_run = below
    return n_str, n_min, low
print("day | service | scope | stretches Running<Desired | minutes | lowest Running")
cpu_rows = []
for f in sorted(glob.glob(os.path.join(run, "metric-data-*.json"))):
    day = os.path.basename(f)[12:22]; res = json.load(open(f))
    for svc in ("plat", "conc"):
        rs, ds = series(res, svc + "_run"), series(res, svc + "_des")
        scopes = [("whole day", lambda t: True), ("busy 13:00-23:59", lambda t: t.hour >= 13)]
        if day == "2026-10-17":
            scopes += [("before 11:28:38", lambda t: t < CHANGE), ("after 11:28:38", lambda t: t >= CHANGE)]
        for name, keep in scopes:
            a, b, c = stretches(rs, ds, keep)
            print(f"{day} | {svc} | {name} | {a} | {b} | {c}")
    for svc in ("plat", "conc"):
        if not any(x["Id"] == svc + "_cpu_max" for x in res["MetricDataResults"]): continue
        avg, mx = series(res, svc + "_cpu_avg"), series(res, svc + "_cpu_max")
        cpu_rows.append((svc, day, len(avg), max(mx.values()) if mx else None, max(avg.values()) if avg else None,
                         sum(1 for v in avg.values() if v > 60), sum(1 for v in avg.values() if v > 75),
                         sum(1 for v in mx.values() if v > 60), sum(1 for v in mx.values() if v > 75), sum(1 for v in mx.values() if v > 90)))
print("\nCPU (AWS/ECS, service level) | service | day | points | highest Maximum | highest Average | min Avg>60 | min Avg>75 | min Max>60 | min Max>75 | min Max>90")
for r in cpu_rows: print(" | ".join(str(round(x, 1)) if isinstance(x, float) else str(x) for x in r))
