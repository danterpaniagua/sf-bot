#!/usr/bin/env python3
"""Summarize SmartPedidos CloudWatch metrics — CPUUtilization (concentrador-
service, platform-service) and SQS ApproximateAgeOfOldestMessage
(PRD_BranchMessages.fifo, a cleaner signal since concentrador-service's CPU
is confounded by the unrelated GITIN-1964 fan-out bug) — across the same
now/now-1w/now-2w/now-3w weekends used for the Zabbix side, for the
peak-season cross-check (GITIN-1965)."""
import json
import statistics
from datetime import datetime, timedelta, timezone
from pathlib import Path

DATA_DIR = Path(__file__).parent / "data"
ARG_TZ = timezone(timedelta(hours=-3))
SERVICES = ["concentrador", "platform"]


def discover_weekends():
    weekends = []
    for f in sorted(DATA_DIR.glob("*_mobi01_get.json")):
        label = f.name[: -len("_mobi01_get.json")]
        data = json.load(open(f))
        result = data.get("result", [])
        if not result:
            continue
        min_clock = min(int(r["clock"]) for r in result)
        sat_date = datetime.fromtimestamp(min_clock, tz=ARG_TZ).date()
        sun_date = sat_date + timedelta(days=1)
        display = f"{sat_date.strftime('%m-%d')}/{sun_date.strftime('%d')}"
        weekends.append((label, display, sat_date.isoformat()))
    return sorted(weekends, key=lambda w: w[2])


WEEKENDS = discover_weekends()
if WEEKENDS:
    label, display, sat_date = WEEKENDS[-1]
    WEEKENDS[-1] = (label, f"{display} (now)", sat_date)
NOW_LABEL = WEEKENDS[-1][0] if WEEKENDS else None
BASELINE = WEEKENDS[:-1] if WEEKENDS else []


def load_datapoints(path):
    if not path.exists():
        return None
    data = json.load(open(path))
    return data.get("Datapoints", [])


def stats(datapoints):
    if not datapoints:
        return None
    avgs = sorted(dp["Average"] for dp in datapoints)
    maxs = sorted(dp["Maximum"] for dp in datapoints)
    return {
        "n": len(datapoints),
        "avg_mean": statistics.mean(avgs),
        "max_mean": statistics.mean(maxs),
        "max_peak": maxs[-1],
    }


hdr = f"{'weekend':<32}{'service':<14}{'n':>6}{'avg(Average)':>14}{'avg(Maximum)':>14}{'peak(Maximum)':>15}"
print(hdr)
print("-" * len(hdr))
summary = {}
for wk_label, wk_dates, _ in WEEKENDS:
    for svc in SERVICES:
        fname = DATA_DIR / f"{wk_label}_{svc}_cpu.json"
        dps = load_datapoints(fname)
        if dps is None:
            print(f"{wk_dates:<32}{svc:<14}MISSING FILE")
            continue
        s = stats(dps)
        if s is None:
            print(f"{wk_dates:<32}{svc:<14}{'0':>6}  (no datapoints in window)")
            continue
        summary[(wk_dates, svc)] = s
        print(f"{wk_dates:<32}{svc:<14}{s['n']:>6}{s['avg_mean']:>14.2f}{s['max_mean']:>14.2f}{s['max_peak']:>15.2f}")

if NOW_LABEL:
    now_dates = WEEKENDS[-1][1]
    print()
    print("Now vs baseline (mean of 5-min 'Average' CPUUtilization %):")
    for svc in SERVICES:
        baseline_vals = [summary[(dates, svc)]["avg_mean"] for _, dates, _ in BASELINE if (dates, svc) in summary]
        now_val = summary.get((now_dates, svc), {}).get("avg_mean")
        if not baseline_vals or now_val is None:
            continue
        baseline_avg = statistics.mean(baseline_vals)
        delta = (now_val - baseline_avg) / baseline_avg * 100 if baseline_avg else float("inf")
        print(f"  {svc:<14}baseline avg={baseline_avg:.2f}%, now={now_val:.2f}%, delta={delta:+.0f}%")

print()
print("=" * len(hdr))
print("SQS PRD_BranchMessages.fifo — ApproximateAgeOfOldestMessage (seconds)")
print("=" * len(hdr))
sqs_hdr = f"{'weekend':<32}{'n':>6}{'avg(Average)':>14}{'avg(Maximum)':>14}{'peak(Maximum)':>15}"
print(sqs_hdr)
print("-" * len(sqs_hdr))
sqs_summary = {}
for wk_label, wk_dates, _ in WEEKENDS:
    fname = DATA_DIR / f"{wk_label}_sqs_branchmessages_age.json"
    dps = load_datapoints(fname)
    if dps is None:
        print(f"{wk_dates:<32}MISSING FILE")
        continue
    s = stats(dps)
    if s is None:
        print(f"{wk_dates:<32}{'0':>6}  (no datapoints in window)")
        continue
    sqs_summary[wk_dates] = s
    print(f"{wk_dates:<32}{s['n']:>6}{s['avg_mean']:>14.2f}{s['max_mean']:>14.2f}{s['max_peak']:>15.2f}")

if NOW_LABEL:
    now_dates = WEEKENDS[-1][1]
    baseline_vals = [sqs_summary[dates]["avg_mean"] for _, dates, _ in BASELINE if dates in sqs_summary]
    now_val = sqs_summary.get(now_dates, {}).get("avg_mean")
    if baseline_vals and now_val is not None:
        baseline_avg = statistics.mean(baseline_vals)
        delta = (now_val - baseline_avg) / baseline_avg * 100 if baseline_avg else float("inf")
        print()
        print(f"SQS age, now vs baseline: baseline avg={baseline_avg:.2f}s, now={now_val:.2f}s, delta={delta:+.0f}%")
