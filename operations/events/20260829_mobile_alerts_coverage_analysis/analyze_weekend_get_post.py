#!/usr/bin/env python3
"""Summarize weekend GET/POST history JSON files into per-service/per-host stats,
including an hour-by-hour (Sat/Sun, local UTC-3) breakdown.

Cross-service peak-season check: Mobile (SFCG-MOBI-01/02), WebServiceV1
(SFCG-WEBS-01/02/03), WebServiceV2 (SFCG-WSV2-01/02).

Weekend set is discovered dynamically from data/*_mobi01_get.json — no
hardcoded dates/labels. Each weekend's Saturday date is derived from its own
data (earliest sample's local date), so adding a new pull (baseline or a
"now" comparison file) just works without editing this script.
"""
import json
import statistics
from datetime import datetime, timedelta, timezone
from pathlib import Path

DATA_DIR = Path(__file__).parent / "data"
ARG_TZ = timezone(timedelta(hours=-3))
METRICS = ["get", "post"]
SUFFIX = "_mobi01_get.json"

# Service groupings — order controls report order.
SERVICES = {
    "Mobile": ["mobi01", "mobi02"],
    "WebServiceV1": ["webs01", "webs02", "webs03"],
    "WebServiceV2": ["wsv201", "wsv202"],
}
HOSTS = [h for hosts in SERVICES.values() for h in hosts]

# Hosts with a known nightly power-off (per loyalty/docs/infrastructure.md):
# missing minutes mean genuinely "off", not a data gap — zero-fill in
# service-level totals, but exclude from that host's own per-host stats
# (an "off" host shouldn't drag down its own average when it's on).
INTERMITTENT_HOSTS = {"mobi02", "wsv202"}


def discover_weekends():
    """Return [(label, display, sat_date_iso), ...], sorted chronologically,
    derived entirely from what's on disk (each file's own earliest sample) —
    no hardcoded weekend list or label convention required."""
    weekends = []
    for f in sorted(DATA_DIR.glob(f"*{SUFFIX}")):
        label = f.name[: -len(SUFFIX)]
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
# The most recent weekend on disk is "now" — compared against everything
# older, treated as baseline. Purely date-driven, no special filename needed.
if WEEKENDS:
    label, display, sat_date = WEEKENDS[-1]
    WEEKENDS[-1] = (label, f"{display} (now)", sat_date)
TODAY = WEEKENDS[-1] if WEEKENDS else None
BASELINE_WEEKENDS = WEEKENDS[:-1] if WEEKENDS else []


def pct(sorted_vals, p):
    if not sorted_vals:
        return None
    k = (len(sorted_vals) - 1) * p
    f = int(k)
    c = min(f + 1, len(sorted_vals) - 1)
    if f == c:
        return sorted_vals[f]
    return sorted_vals[f] + (sorted_vals[c] - sorted_vals[f]) * (k - f)


def load_values(path):
    data = json.load(open(path))
    result = data.get("result", [])
    return sorted(float(r["value"]) for r in result)


def load_minute_series(path):
    """clock (floored to minute) -> value, summing any same-minute duplicates."""
    data = json.load(open(path))
    series = {}
    for r in data.get("result", []):
        minute = int(r["clock"]) // 60 * 60
        series[minute] = series.get(minute, 0.0) + float(r["value"])
    return series


def service_total_series(wk_label, hosts):
    """Per-minute total across `hosts` (get+post summed), missing minutes on
    INTERMITTENT_HOSTS treated as 0 (genuinely off, not a gap) — anchored on
    Mobi01's GET timeline since it has ~100% coverage."""
    series = {}
    for host in hosts:
        for metric in METRICS:
            fname = DATA_DIR / f"{wk_label}_{host}_{metric}.json"
            if not fname.exists():
                return None
            series[(host, metric)] = load_minute_series(fname)

    anchor = load_minute_series(DATA_DIR / f"{wk_label}_mobi01_get.json")
    total_by_minute = {}
    for minute in anchor:
        total = 0.0
        for host in hosts:
            for metric in METRICS:
                total += series[(host, metric)].get(minute, 0.0)
        total_by_minute[minute] = total
    return sorted(total_by_minute.values())


def day_hour(minute_epoch, sat_date_str):
    """Classify a minute epoch as ('Sat'|'Sun', hour) in local (UTC-3) time,
    or (None, None) if outside the two-day window."""
    dt = datetime.fromtimestamp(minute_epoch, tz=ARG_TZ)
    sat_date = datetime.strptime(sat_date_str, "%Y-%m-%d").date()
    if dt.date() == sat_date:
        return "Sat", dt.hour
    if dt.date() == sat_date + timedelta(days=1):
        return "Sun", dt.hour
    return None, None


def hourly_buckets(wk_label, sat_date_str, value_fn):
    """value_fn(minute_epoch) -> float or None (None = exclude, e.g. host off).
    Anchored on Mobi01 GET's timeline (near-100% coverage) to enumerate minutes."""
    anchor_path = DATA_DIR / f"{wk_label}_mobi01_get.json"
    if not anchor_path.exists():
        return None
    anchor = load_minute_series(anchor_path)
    buckets = {}
    for minute in anchor:
        day, hour = day_hour(minute, sat_date_str)
        if day is None:
            continue
        val = value_fn(minute)
        if val is None:
            continue
        buckets.setdefault((day, hour), []).append(val)
    return buckets


def print_hourly_matrix(title, per_weekend_buckets):
    print()
    print(title)
    weekend_labels = [wd for _, wd, _ in WEEKENDS]
    col_w = 11
    for day in ("Sat", "Sun"):
        print(f"\n  {day}")
        row_hdr = "  hour".ljust(8) + "".join(w.rjust(col_w) for w in weekend_labels)
        print(row_hdr)
        for hour in range(24):
            row = f"  {hour:02d}:00".ljust(8)
            for wk_label, wk_dates, _ in WEEKENDS:
                buckets = per_weekend_buckets.get(wk_label)
                vals = buckets.get((day, hour)) if buckets else None
                cell = f"{statistics.mean(vals):.2f}" if vals else "-"
                row += cell.rjust(col_w)
            print(row)


if not WEEKENDS:
    raise SystemExit(f"No weekend data found under {DATA_DIR} (looked for *{SUFFIX})")

rows = []
for wk_label, wk_dates, _ in WEEKENDS:
    for host in HOSTS:
        for metric in METRICS:
            fname = DATA_DIR / f"{wk_label}_{host}_{metric}.json"
            if not fname.exists():
                rows.append((wk_dates, host, metric, "MISSING FILE", None, None, None, None, None, None))
                continue
            vals = load_values(fname)
            n = len(vals)
            if n == 0:
                rows.append((wk_dates, host, metric, 0, None, None, None, None, None, None))
                continue
            mean = statistics.mean(vals)
            p50 = pct(vals, 0.50)
            p90 = pct(vals, 0.90)
            p95 = pct(vals, 0.95)
            p99 = pct(vals, 0.99)
            vmax = vals[-1]
            rows.append((wk_dates, host, metric, n, mean, p50, p90, p95, p99, vmax))

hdr = f"{'weekend':<14}{'host':<8}{'metric':<7}{'n':>6}{'mean':>9}{'p50':>8}{'p90':>8}{'p95':>8}{'p99':>8}{'max':>9}"
print(hdr)
print("-" * len(hdr))
for r in rows:
    wk, host, metric, n, mean, p50, p90, p95, p99, vmax = r
    if mean is None:
        print(f"{wk:<14}{host:<8}{metric:<7}{str(n):>6}")
        continue
    print(f"{wk:<14}{host:<8}{metric:<7}{n:>6}{mean:>9.2f}{p50:>8.2f}{p90:>8.2f}{p95:>8.2f}{p99:>8.2f}{vmax:>9.2f}")

# combined GET+POST per weekend per host (sum of means as a rough total-rate proxy)
print()
print("GET+POST combined mean rate (req/s), by weekend/host:")
combined = {}
for r in rows:
    wk, host, metric, n, mean = r[0], r[1], r[2], r[3], r[4]
    if mean is None:
        continue
    combined.setdefault((wk, host), 0.0)
    combined[(wk, host)] += mean
for (wk, host), total in sorted(combined.items()):
    print(f"  {wk:<14}{host:<8}{total:.2f} req/s")

# comparison of "now" (if present) vs the rest, treated as baseline, per host
if TODAY is not None:
    print()
    print("Now vs baseline (combined GET+POST mean rate), per host:")
    for host in HOSTS:
        baseline_vals = [combined[(dates, host)] for _, dates, _ in BASELINE_WEEKENDS if (dates, host) in combined]
        today_val = combined.get((TODAY[1], host))
        if not baseline_vals or today_val is None:
            continue
        baseline_avg = statistics.mean(baseline_vals)
        delta_pct = (today_val - baseline_avg) / baseline_avg * 100 if baseline_avg else float("inf")
        print(f"  {host:<8}baseline avg={baseline_avg:.2f} req/s, now={today_val:.2f} req/s, delta={delta_pct:+.0f}%")

# per-service (Total) — PM/higher-level view: hosts within a service combined,
# not per-VM (per feedback_reporting_granularity_by_audience: Ops gets
# per-machine, PM gets service total). One table per service.
for svc_name, svc_hosts in SERVICES.items():
    print()
    print("=" * len(hdr))
    print(f"PER SERVICE (Total): {svc_name} ({'+'.join(svc_hosts)}) — for PM/higher-level reporting")
    print("=" * len(hdr))
    svc_hdr = f"{'weekend':<32}{'n':>6}{'mean':>9}{'p50':>8}{'p90':>8}{'p95':>8}{'p99':>8}{'max':>9}"
    print(svc_hdr)
    print("-" * len(svc_hdr))
    svc_stats = {}
    for wk_label, wk_dates, _ in WEEKENDS:
        vals = service_total_series(wk_label, svc_hosts)
        if vals is None:
            print(f"{wk_dates:<32}MISSING FILE(S)")
            continue
        n = len(vals)
        mean = statistics.mean(vals)
        p50, p90, p95, p99 = pct(vals, 0.50), pct(vals, 0.90), pct(vals, 0.95), pct(vals, 0.99)
        vmax = vals[-1]
        svc_stats[wk_dates] = mean
        print(f"{wk_dates:<32}{n:>6}{mean:>9.2f}{p50:>8.2f}{p90:>8.2f}{p95:>8.2f}{p99:>8.2f}{vmax:>9.2f}")

    if TODAY is not None and TODAY[1] in svc_stats:
        baseline_svc_vals = [svc_stats[dates] for _, dates, _ in BASELINE_WEEKENDS if dates in svc_stats]
        if baseline_svc_vals:
            baseline_svc_avg = statistics.mean(baseline_svc_vals)
            today_svc = svc_stats[TODAY[1]]
            delta_pct = (today_svc - baseline_svc_avg) / baseline_svc_avg * 100 if baseline_svc_avg else float("inf")
            print()
            print(f"{svc_name} total, now vs baseline: baseline avg={baseline_svc_avg:.2f} req/s, "
                  f"now={today_svc:.2f} req/s, delta={delta_pct:+.0f}%")

# --- Hour-by-hour breakdown, Sat/Sun local (UTC-3) ---
print()
print("=" * len(hdr))
print("HOUR-BY-HOUR BREAKDOWN (local time, UTC-3)")
print("=" * len(hdr))

for svc_name, svc_hosts in SERVICES.items():
    svc_hourly = {}
    for wk_label, wk_dates, sat_date in WEEKENDS:
        series = {}
        ok = True
        for host in svc_hosts:
            for metric in METRICS:
                fname = DATA_DIR / f"{wk_label}_{host}_{metric}.json"
                if not fname.exists():
                    ok = False
                    break
                series[(host, metric)] = load_minute_series(fname)
            if not ok:
                break
        if not ok:
            continue

        def value_fn(minute, series=series, svc_hosts=svc_hosts):
            return sum(series[(h, m)].get(minute, 0.0) for h in svc_hosts for m in METRICS)

        svc_hourly[wk_label] = hourly_buckets(wk_label, sat_date, value_fn)

    print_hourly_matrix(f"{svc_name} TOTAL ({'+'.join(svc_hosts)}, GET+POST) — mean req/s per hour", svc_hourly)

# Per-host hourly view for intermittently-powered hosts specifically — Ops view,
# since these are the ones where "off" vs. "low traffic" actually matters.
for host in HOSTS:
    if host not in INTERMITTENT_HOSTS:
        continue
    get_f_suffix = f"_{host}_get.json"
    post_f_suffix = f"_{host}_post.json"
    host_hourly = {}
    for wk_label, wk_dates, sat_date in WEEKENDS:
        get_f = DATA_DIR / f"{wk_label}{get_f_suffix}"
        post_f = DATA_DIR / f"{wk_label}{post_f_suffix}"
        if not (get_f.exists() and post_f.exists()):
            continue
        get_s = load_minute_series(get_f)
        post_s = load_minute_series(post_f)

        def value_fn(minute, get_s=get_s, post_s=post_s):
            if minute not in get_s and minute not in post_s:
                return None  # host powered off this minute — exclude, don't zero-fill
            return get_s.get(minute, 0.0) + post_s.get(minute, 0.0)

        host_hourly[wk_label] = hourly_buckets(wk_label, sat_date, value_fn)

    print_hourly_matrix(f"{host.upper()} ONLY (GET+POST) — mean req/s per hour — '-' may mean powered off", host_hourly)
