#!/usr/bin/env python3
"""Hourly-only comparison for WebServiceV1/WebServiceV2: 'now' from per-minute
History (fetch_get_post_weeks.sh), baseline weekends from hourly Trends
(fetch_webs_wsv2_trends_baseline.sh, value_avg). Deliberately kept separate
from analyze_weekend_get_post.py's percentile table — mixing per-minute and
hourly resolution under one n/percentile column would misstate precision.
"""
import json
import statistics
from datetime import datetime, timedelta, timezone
from pathlib import Path

DATA_DIR = Path(__file__).parent / "data"
ARG_TZ = timezone(timedelta(hours=-3))
METRICS = ["get", "post"]

SERVICES = {
    "WebServiceV1": ["webs01", "webs02", "webs03"],
    "WebServiceV2": ["wsv201", "wsv202"],
}
HOSTS = [h for hosts in SERVICES.values() for h in hosts]


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
    NOW_LABEL = label


def day_hour(epoch, sat_date_str):
    dt = datetime.fromtimestamp(epoch, tz=ARG_TZ)
    sat_date = datetime.strptime(sat_date_str, "%Y-%m-%d").date()
    if dt.date() == sat_date:
        return "Sat", dt.hour
    if dt.date() == sat_date + timedelta(days=1):
        return "Sun", dt.hour
    return None, None


def hourly_from_history(wk_label, sat_date_str, host, metric):
    """'now': per-minute History -> hourly means."""
    fname = DATA_DIR / f"{wk_label}_{host}_{metric}.json"
    if not fname.exists():
        return None
    data = json.load(open(fname))
    buckets = {}
    for r in data.get("result", []):
        day, hour = day_hour(int(r["clock"]), sat_date_str)
        if day is None:
            continue
        buckets.setdefault((day, hour), []).append(float(r["value"]))
    return {k: statistics.mean(v) for k, v in buckets.items()}


def hourly_from_trends(wk_label, sat_date_str, host, metric):
    """Baseline weekends: hourly Trends -> hourly means (value_avg, one row/hour already)."""
    fname = DATA_DIR / f"{wk_label}_{host}_{metric}_trends.json"
    if not fname.exists():
        return None
    data = json.load(open(fname))
    result = data.get("result", [])
    if not result:
        return {}
    buckets = {}
    for r in result:
        day, hour = day_hour(int(r["clock"]), sat_date_str)
        if day is None:
            continue
        buckets[(day, hour)] = float(r["value_avg"])
    return buckets


def hourly_for(wk_label, sat_date_str, host, metric):
    if wk_label == NOW_LABEL:
        return hourly_from_history(wk_label, sat_date_str, host, metric)
    return hourly_from_trends(wk_label, sat_date_str, host, metric)


def service_hourly(wk_label, sat_date_str, svc_hosts):
    """Sum GET+POST across svc_hosts, per (day, hour). None if any required file missing."""
    per_host_metric = {}
    for host in svc_hosts:
        for metric in METRICS:
            h = hourly_for(wk_label, sat_date_str, host, metric)
            if h is None:
                return None
            per_host_metric[(host, metric)] = h

    all_keys = set()
    for h in per_host_metric.values():
        all_keys |= set(h.keys())
    totals = {}
    for key in all_keys:
        totals[key] = sum(per_host_metric[(host, metric)].get(key, 0.0)
                           for host in svc_hosts for metric in METRICS)
    return totals


def print_matrix(title, per_weekend):
    print()
    print(title)
    weekend_labels = [wd for _, wd, _ in WEEKENDS]
    col_w = 11
    for day in ("Sat", "Sun"):
        print(f"\n  {day}")
        print("  hour".ljust(8) + "".join(w.rjust(col_w) for w in weekend_labels))
        for hour in range(24):
            row = f"  {hour:02d}:00".ljust(8)
            for wk_label, wk_dates, _ in WEEKENDS:
                buckets = per_weekend.get(wk_label)
                val = buckets.get((day, hour)) if buckets else None
                row += (f"{val:.2f}" if val is not None else "-").rjust(col_w)
            print(row)


if not WEEKENDS:
    raise SystemExit("No weekend data found.")

print("NOTE: 'now' is per-minute History; baseline weeks are hourly Trends (value_avg).")
print("Hourly means are directly comparable across both; no percentile/max data exists")
print("for the baseline weeks (Trends doesn't store percentiles) — only the mean.")

for svc_name, svc_hosts in SERVICES.items():
    per_weekend = {}
    for wk_label, wk_dates, sat_date in WEEKENDS:
        per_weekend[wk_label] = service_hourly(wk_label, sat_date, svc_hosts)
    print_matrix(f"{svc_name} TOTAL ({'+'.join(svc_hosts)}, GET+POST) — mean req/s per hour", per_weekend)

    # now vs baseline delta on overall weekend mean
    if NOW_LABEL in per_weekend and per_weekend[NOW_LABEL]:
        now_mean = statistics.mean(per_weekend[NOW_LABEL].values())
        baseline_means = []
        for wk_label, _, _ in WEEKENDS:
            if wk_label == NOW_LABEL:
                continue
            b = per_weekend.get(wk_label)
            if b:
                baseline_means.append(statistics.mean(b.values()))
        if baseline_means:
            baseline_avg = statistics.mean(baseline_means)
            delta = (now_mean - baseline_avg) / baseline_avg * 100 if baseline_avg else float("inf")
            print(f"\n{svc_name}: baseline avg={baseline_avg:.2f} req/s (hourly-mean basis), "
                  f"now={now_mean:.2f} req/s, delta={delta:+.0f}%")
