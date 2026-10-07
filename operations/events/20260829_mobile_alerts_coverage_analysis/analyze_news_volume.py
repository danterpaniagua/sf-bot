#!/usr/bin/env python3
"""SmartPedidos MongoDB `news` document volume, hourly, from a pasted mongosh
aggregation (data/news_hourly_raw.json). 15-day retention means now-3w has no
data at all, and now-2w is missing Saturday (08-15) — flagged explicitly,
not silently averaged over."""
import json
from collections import defaultdict
from datetime import datetime

DATA_DIR_FILE = "/home/dpaniagua/Documentos/git/bots/operations/events/20260829_mobile_alerts_coverage_analysis/data/news_hourly_raw.json"

WEEKENDS = {
    "now-3w (08-08/09)": ["2026-08-08", "2026-08-09"],
    "now-2w (08-15/16)": ["2026-08-15", "2026-08-16"],
    "now-1w (08-22/23)": ["2026-08-22", "2026-08-23"],
    "now (08-29/30)": ["2026-08-29", "2026-08-30"],
}

data = json.load(open(DATA_DIR_FILE))
by_date = defaultdict(int)
for row in data:
    date_str, _hour = row["_id"].split(" ")
    by_date[date_str] += row["count"]

print(f"{'weekend':<20}{'date':<12}{'total':>10}{'note':>20}")
print("-" * 62)
weekend_totals = {}
for wk_label, dates in WEEKENDS.items():
    total = 0
    missing = []
    for d in dates:
        day_total = by_date.get(d, 0)
        total += day_total
        note = "" if d in by_date else "NO DATA"
        if d not in by_date:
            missing.append(d)
        print(f"{wk_label:<20}{d:<12}{day_total:>10}{note:>20}")
    weekend_totals[wk_label] = (total, missing)
    complete = "COMPLETE" if not missing else f"PARTIAL (missing {', '.join(missing)})"
    print(f"{'':<20}{'TOTAL':<12}{total:>10}{complete:>20}")
    print()

now_total, now_missing = weekend_totals["now (08-29/30)"]
baseline_complete = [wk for wk, (t, m) in weekend_totals.items() if wk != "now (08-29/30)" and not m]
if baseline_complete:
    baseline_avg = sum(weekend_totals[wk][0] for wk in baseline_complete) / len(baseline_complete)
    delta = (now_total - baseline_avg) / baseline_avg * 100
    print(f"Now vs. COMPLETE baseline weekends only ({', '.join(baseline_complete)}):")
    print(f"  baseline avg={baseline_avg:.0f} news docs, now={now_total}, delta={delta:+.0f}%")

print()
print("Excluded from baseline average: now-3w (no data, retention) and now-2w (missing Saturday, partial).")
