#!/usr/bin/env python3
"""Rebuild the dashboard's hourly chart data at 15-minute resolution instead
of hourly means, from the already-fetched per-minute History JSON files.
Prints JS array literals to paste into dashboard_temporada_alta.html."""
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path

DATA_DIR = Path("/home/dpaniagua/Documentos/git/bots/operations/events/20260829_mobile_alerts_coverage_analysis/data")
ARG_TZ = timezone(timedelta(hours=-3))
BUCKET_MIN = 15
BUCKETS_PER_DAY = 24 * 60 // BUCKET_MIN  # 96

SAT_DATES = {
    "now": "2026-08-29",
    "now-1w": "2026-08-22",
    "now-2w": "2026-08-15",
    "now-3w": "2026-08-08",
}


def load_series(path):
    if not path.exists():
        return None
    data = json.load(open(path))
    return data.get("result", [])


def bucket_index(clock_epoch, sat_date_str):
    dt = datetime.fromtimestamp(clock_epoch, tz=ARG_TZ)
    sat = datetime.strptime(sat_date_str, "%Y-%m-%d").date()
    if dt.date() == sat:
        day_offset = 0
    elif dt.date() == sat + timedelta(days=1):
        day_offset = 1
    else:
        return None
    minute_of_day = dt.hour * 60 + dt.minute
    bucket = minute_of_day // BUCKET_MIN
    return day_offset * BUCKETS_PER_DAY + bucket


def combined_series(wk_label, hosts, metrics=("get", "post")):
    """Combine hosts+metrics at each raw minute first (true per-minute total),
    THEN bucket those combined per-minute totals into BUCKET_MIN windows and
    average across the ~BUCKET_MIN per-minute totals in each window."""
    sat_date = SAT_DATES[wk_label]
    per_minute_total = {}
    for host in hosts:
        for metric in metrics:
            rows = load_series(DATA_DIR / f"{wk_label}_{host}_{metric}.json")
            if rows is None:
                return None
            for r in rows:
                minute = int(r["clock"]) // 60 * 60
                per_minute_total[minute] = per_minute_total.get(minute, 0.0) + float(r["value"])

    bucket_sums = {}
    bucket_counts = {}
    for minute, combined_val in per_minute_total.items():
        idx = bucket_index(minute, sat_date)
        if idx is None:
            continue
        bucket_sums[idx] = bucket_sums.get(idx, 0.0) + combined_val
        bucket_counts[idx] = bucket_counts.get(idx, 0) + 1

    n_buckets = 2 * BUCKETS_PER_DAY
    result = []
    for i in range(n_buckets):
        if i in bucket_sums and bucket_counts[i] > 0:
            result.append(round(bucket_sums[i] / bucket_counts[i], 3))
        else:
            result.append(0.0)
    return result


def js_array(vals):
    return "[" + ",".join(f"{v:.2f}" for v in vals) + "]"


MOBILE_HOSTS = ["mobi01", "mobi02"]
WEBS_HOSTS = ["webs01", "webs02", "webs03"]
WSV2_HOSTS = ["wsv201", "wsv202"]

print(f"// {BUCKET_MIN}-minute buckets, {BUCKETS_PER_DAY} per day, Sat then Sun ({2*BUCKETS_PER_DAY} total)")
print()

mobile_now = combined_series("now", MOBILE_HOSTS)
mobile_baselines = [combined_series(lbl, MOBILE_HOSTS) for lbl in ("now-1w", "now-2w", "now-3w")]
mobile_baseline_avg = [round(sum(vs)/len(vs), 3) for vs in zip(*mobile_baselines)]
print("const mobileBaseline15 =", js_array(mobile_baseline_avg), ";")
print("const mobileNow15 =", js_array(mobile_now), ";")
print()

webs_now = combined_series("now", WEBS_HOSTS)
print("const webs15 =", js_array(webs_now), ";")
peak_idx = max(range(len(webs_now)), key=lambda i: webs_now[i])
day = "Sat" if peak_idx < BUCKETS_PER_DAY else "Sun"
local_idx = peak_idx if peak_idx < BUCKETS_PER_DAY else peak_idx - BUCKETS_PER_DAY
hh = (local_idx * BUCKET_MIN) // 60
mm = (local_idx * BUCKET_MIN) % 60
print(f"// WebService on-prem peak at 15-min resolution: {webs_now[peak_idx]:.1f} req/s, {day} {hh:02d}:{mm:02d} (index {peak_idx})")
print()

wsv2_now = combined_series("now", WSV2_HOSTS)
print("const wsv215 =", js_array(wsv2_now), ";")
