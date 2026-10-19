#!/usr/bin/env python3
"""
Fetch AppServiceHTTPLogs traffic from Graylog for a SmartFran Cloud App Service,
aggregate response time (TimeTaken) by 10-minute bucket x CsUriStem, optionally
overlay App Service Plan CPU/RAM (avg/min/max), and render one linked Altair report
(zoom bar + endpoint legend drive every panel together).

Originated in cloud/events/20260913_pos-net-http-timeout/ (Sales-PRO OOM investigation)
and generalized here for reuse against any of the 8 production App Services — see
`cloud-appservice-perf-report` skill for the per-app command templates (stream IDs,
resource names) and the full 3-step workflow (Graylog export, Azure Monitor pull, this
script).

Bypasses Graylog's bare-field promotion (unreliable for historical data — see
cloud/docs/graylog-log-fields.md, GITIN-2034) by exporting raw `properties` JSON via
the CSV export endpoint and parsing it locally.

Requires: requests, pandas, altair
Requires env var: GRAYLOG_API_KEY

Usage:
  GRAYLOG_API_KEY=... python3 appservice_perf_report.py \\
      --from 2026-09-11T18:20:00.000Z --to 2026-09-14T18:20:00.000Z \\
      --stream-id <PROD-{App}-AppServiceHTTPLogs stream id> \\
      --app-label Sales-PRO \\
      --metrics-json cpu_ram.json --incidents-file incidents.txt

Default output locations (repo-relative, resolved from this script's own path —
override with --data-dir/--report-dir, e.g. to write into a specific event folder
instead): raw/aggregated data -> cloud/scripts/data/, the HTML report -> cloud/report/.
Both use fixed filenames (raw_export.csv, timetaken_by_path_aggregated.csv,
timetaken_report.html) — repeated runs against the *default* dirs overwrite each
other regardless of --app-label, so pass explicit --data-dir/--report-dir when working
a specific investigation (see cloud-appservice-perf-report skill).
"""

import argparse
import csv
import json
import os
import re
import sys
from datetime import datetime

import altair as alt
import pandas as pd
import requests

AZURE_WINDOWS_IDLE_TIMEOUT_MS = 230_000

# Resolved from this script's own location (cloud/scripts/appservice_perf_report.py),
# not the caller's cwd, so the defaults are stable regardless of where this is invoked
# from. Override with --data-dir/--report-dir for an event-specific investigation.
_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_DATA_DIR = os.path.join(_SCRIPT_DIR, "data")
DEFAULT_REPORT_DIR = os.path.normpath(os.path.join(_SCRIPT_DIR, "..", "report"))

# Path prefixes whose trailing segments are per-call parameters (store code,
# external POS id, ...), not distinct routes — collapsed so they're counted together.
# App-specific; extend if another App Service's endpoint shapes need the same treatment.
NORMALIZED_PATH_PREFIXES = [
    "/api/v1/MercadoPago/GetPosByExternalId",
    "/api/v1/Kds/orders/set-done",
    "/api/processes",
]


GUID_RE = re.compile(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")

# HTTP status color families: (low, high, light shade, dark shade) — each observed
# code within a band gets its own shade along that band's gradient (lowest code =
# lightest), so e.g. 200 and 204 are both green but visually distinguishable.
STATUS_COLOR_FAMILIES = [
    (200, 399, "#a8e6a1", "#0b5e17"),  # success/redirect — light to dark green
    (400, 499, "#ffe89a", "#b8860b"),  # client error — light to dark amber
    (500, 599, "#f5a3a3", "#7a0d0d"),  # server error — light to dark red
]

# Incident marker colors by type. "default" is what an incidents.txt line without a
# Type field (or a bare --incident TS|LABEL) gets — same orange used before per-type
# coloring existed, so every pre-existing incidents.txt in events/ renders unchanged.
# New types get their own entry here; anything not listed falls back to DEFAULT_INCIDENT_COLOR.
INCIDENT_TYPE_COLORS = {
    "default": "#e67e22",
    "escalation": "#e67e22",
    "oom": "#d63384",
}
DEFAULT_INCIDENT_COLOR = "#e67e22"


def _hex_to_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def _rgb_to_hex(rgb):
    return "#" + "".join(f"{max(0, min(255, round(c))):02x}" for c in rgb)


def _interp_hex(c1, c2, t):
    r1, g1, b1 = _hex_to_rgb(c1)
    r2, g2, b2 = _hex_to_rgb(c2)
    return _rgb_to_hex((r1 + (r2 - r1) * t, g1 + (g2 - g1) * t, b1 + (b2 - b1) * t))


def avg_ms_gradient_scale(max_val):
    """Piecewise-linear domain/range for avg_ms: a light->dark gradient within each
    of three bands (<=600 green, 600-2000 amber, >2000 red), with a hard edge at each
    boundary (two near-duplicate domain stops = instant color jump, still-smooth
    interpolation on either side — the standard multi-stop-linear-scale trick)."""
    max_val = max(float(max_val), 2000.0 + 1)
    eps = 1e-3
    domain = [0, 600, 600 + eps, 2000, 2000 + eps, max_val]
    range_ = [
        "#a8e6a1", "#0b5e17",  # green: light -> dark, 0-600
        "#ffe89a", "#b8860b",  # amber: light -> dark, 600-2000
        "#f5a3a3", "#7a0d0d",  # red: light -> dark, 2000-max
    ]
    return domain, range_


def status_color_scale(statuses):
    """Domain/range for an explicit per-status-code color scale, graded by family."""
    uniq = list(pd.unique(pd.Series(list(statuses))))

    def to_num(v):
        try:
            return int(v)
        except (TypeError, ValueError):
            return None

    domain, range_, used = [], [], set()
    for lo, hi, light, dark in STATUS_COLOR_FAMILIES:
        family = sorted((v for v in uniq if (n := to_num(v)) is not None and lo <= n <= hi), key=to_num)
        n_codes = len(family)
        for i, code in enumerate(family):
            t = 0.0 if n_codes <= 1 else i / (n_codes - 1)
            domain.append(code)
            range_.append(_interp_hex(light, dark, t))
            used.add(code)
    # Anything outside 200-599 (or unparseable) falls back to grey, appended last.
    for v in sorted((v for v in uniq if v not in used), key=str):
        domain.append(v)
        range_.append("#999999")
    return domain, range_


def normalize_path(path):
    for prefix in NORMALIZED_PATH_PREFIXES:
        if path == prefix or path.startswith(prefix + "/"):
            return prefix
    # Any GUID-shaped segment elsewhere in the path (e.g. /api/v1/SaleOrder/<id>/pay
    # vs .../deliver) is a per-call id, not a distinct route — collapse in place so
    # the surrounding path (action name) stays intact.
    segments = [("{id}" if GUID_RE.match(seg) else seg) for seg in path.split("/")]
    return "/".join(segments)


VERSIONED_API_RE = re.compile(r"^/api/v\d+/", re.IGNORECASE)


def is_versioned_api(path):
    return bool(VERSIONED_API_RE.match(path))


def load_incidents_file(path):
    """Plain text, one incident per line: `ISO_TIMESTAMP|Label text` or
    `ISO_TIMESTAMP|Label text|Type` (Type optional — see INCIDENT_TYPE_COLORS; omitted
    or unrecognized Type falls back to "default", the original orange). Blank lines and
    lines starting with `#` are ignored. Same format as the repeatable --incident flag
    — see cloud-appservice-perf-report skill for how to populate one per event."""
    incidents = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split("|", 2)
            if len(parts) < 2:
                continue
            ts, label = parts[0].strip(), parts[1].strip()
            itype = parts[2].strip() if len(parts) > 2 and parts[2].strip() else "default"
            if not label:
                continue
            incidents.append((ts, label, itype))
    return incidents


def load_azure_metrics(json_path, bucket_minutes):
    """Parse an `az monitor metrics list --aggregation Average Minimum Maximum` JSON
    (CpuPercentage, MemoryPercentage — plan-level `Microsoft.Web/serverfarms` metrics)
    into a long DataFrame of (bucket, metric, avg_value, min_value, max_value).

    Reads Azure's own reported min/max per sample interval directly (not derived by
    re-aggregating already-averaged sub-samples in Python) — requires the source JSON
    to have been fetched with all three aggregations requested."""
    with open(json_path) as f:
        data = json.load(f)

    rows = []
    for m in data.get("value", []):
        name = m.get("name", {}).get("value")
        if name not in ("CpuPercentage", "MemoryPercentage"):
            continue
        for ts in m.get("timeseries", []):
            for point in ts.get("data", []):
                avg, mn, mx = point.get("average"), point.get("minimum"), point.get("maximum")
                if avg is None and mn is None and mx is None:
                    continue
                dt = datetime.fromisoformat(point["timeStamp"].replace("Z", "+00:00"))
                bucket_minute = (dt.minute // bucket_minutes) * bucket_minutes
                bucket = dt.replace(minute=bucket_minute, second=0, microsecond=0)
                rows.append((bucket, name, avg, mn, mx))

    df = pd.DataFrame(rows, columns=["bucket", "metric", "avg", "min", "max"])
    if df.empty:
        return df

    # Roll PT5M sub-samples up into 10-min buckets: mean-of-averages (a fine
    # approximation for the bucket average), true min-of-minimums, true max-of-maximums
    # — both directly from Azure's own per-5-min Min/Max aggregation, not re-derived.
    frames = []
    for name in ("CpuPercentage", "MemoryPercentage"):
        sub = df[df["metric"] == name]
        if sub.empty:
            continue
        g = sub.groupby("bucket").agg(
            avg_value=("avg", "mean"), min_value=("min", "min"), max_value=("max", "max")
        ).reset_index()
        g["metric"] = name
        frames.append(g)
    return pd.concat(frames, ignore_index=True) if frames else df


def fetch_raw_export(base_url, api_key, stream_id, time_from, time_to, out_path):
    resp = requests.get(
        f"{base_url}/search/universal/absolute/export",
        auth=(api_key, "token"),
        params={
            "query": "*",
            "filter": f"streams:{stream_id}",
            "fields": "timestamp,properties",
            "from": time_from,
            "to": time_to,
        },
        headers={"Accept": "text/csv"},
        stream=True,
        timeout=300,
    )
    resp.raise_for_status()
    with open(out_path, "wb") as f:
        for chunk in resp.iter_content(chunk_size=1 << 20):
            f.write(chunk)
    return out_path


def parse_and_bucket(raw_csv_path, bucket_minutes, versioned_api_only=True):
    rows = []
    with open(raw_csv_path, newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        next(reader, None)
        for row in reader:
            if len(row) < 2:
                continue
            ts_raw, props_raw = row[0], row[1]
            try:
                props = json.loads(props_raw)
                path = props.get("CsUriStem")
                ms = props.get("TimeTaken")
                if path is None or ms is None:
                    continue
                if versioned_api_only and not is_versioned_api(path):
                    continue
                referer = props.get("Referer") or "-"
                status = props.get("ScStatus")
                path = normalize_path(path)
                dt = datetime.fromisoformat(ts_raw.replace("Z", "+00:00"))
            except Exception:
                continue
            bucket_minute = (dt.minute // bucket_minutes) * bucket_minutes
            bucket = dt.replace(minute=bucket_minute, second=0, microsecond=0)
            rows.append((bucket, path, referer, status, float(ms)))

    df = pd.DataFrame(rows, columns=["bucket", "path", "referer", "status", "ms"])
    if df.empty:
        return df, df

    # Chart-level aggregation (bucket x path only) — what the Altair views render.
    agg = (
        df.groupby(["bucket", "path"])["ms"]
        .agg(avg_ms="mean", max_ms="max", count="size")
        .reset_index()
    )
    # CSV-level aggregation, split further by referer and response code.
    agg_detailed = (
        df.groupby(["bucket", "path", "referer", "status"])["ms"]
        .agg(avg_ms="mean", max_ms="max", count="size")
        .reset_index()
    )
    return agg, agg_detailed


def build_charts(agg, agg_detailed, output_dir, incidents, app_label, metrics_df=None):
    all_paths = agg.groupby("path")["count"].sum().sort_values(ascending=False).index.tolist()
    status_agg = (
        agg_detailed.groupby(["bucket", "path", "status"])["count"].sum().reset_index()
    )

    # Field named "bucket" (not "ts") on purpose — see note below on why x must be
    # defined once, at the layer level, using one consistent field name across layers.
    incidents_df = pd.DataFrame(
        [
            {"bucket": datetime.fromisoformat(ts.replace("Z", "+00:00")), "label": label, "type": itype}
            for ts, label, itype in incidents
        ]
    ) if incidents else pd.DataFrame(columns=["bucket", "label", "type"])

    # Color scale built only from types actually present, in first-seen order — keeps
    # the legend short and stable rather than always listing every known type.
    incident_types_present = list(dict.fromkeys(t for _, _, t in incidents)) or ["default"]
    incident_color_scale = alt.Scale(
        domain=incident_types_present,
        range=[INCIDENT_TYPE_COLORS.get(t, DEFAULT_INCIDENT_COLOR) for t in incident_types_present],
    )
    # Legend only on the ONE reused instance below (incident_rules, on the top panel) —
    # every other panel below reuses incident_rules_nolegend/incident_color_nolegend so
    # the same "Incident type" legend doesn't repeat on every single panel.
    incident_color = alt.Color(
        "type:N",
        title="Incident type",
        scale=incident_color_scale,
        legend=alt.Legend(title="Incident type") if len(incident_types_present) > 1 else None,
    )
    incident_color_nolegend = alt.Color("type:N", scale=incident_color_scale, legend=None)

    # No x encoding here — deliberately. It's supplied once per combined chart via
    # `.encode(x=zoomed_x)` on the outer layer (see below), not per child.
    incident_rules = (
        alt.Chart(incidents_df)
        .mark_rule(strokeDash=[2, 2], size=1)
        .encode(color=incident_color, tooltip="label:N")
    )
    incident_rules_nolegend = (
        alt.Chart(incidents_df)
        .mark_rule(strokeDash=[2, 2], size=1)
        .encode(color=incident_color_nolegend, tooltip="label:N")
    )
    incident_labels = (
        alt.Chart(incidents_df)
        .mark_text(align="left", angle=270, dy=-4, dx=4, fontSize=9)
        .encode(y=alt.value(0), text="label:N", color=incident_color_nolegend)
    )
    # Separate copy WITH its own x — used only by the zoom bar below, which is not
    # part of any domain-bound group and needs its x defined directly on the child.
    incident_rules_with_own_x = (
        alt.Chart(incidents_df)
        .mark_rule(strokeDash=[2, 2], size=1)
        .encode(x="bucket:T", color=incident_color_nolegend, tooltip="label:N")
    )

    # Click a legend entry to isolate that endpoint (dims the rest); shift-click to
    # enable/disable several at once. Empty selection (nothing clicked yet) shows all.
    selection = alt.selection_point(fields=["path"], bind="legend")
    # Drag on the zoom bar to pick a time range; every chart's x-scale is bound to it,
    # so they all zoom together. Note: this replaces an earlier bind="scales" scroll
    # zoom — Vega-Lite can't have both a brush-bound scale domain and a scales-bound
    # interval on the same encoding channel.
    brush = alt.selection_interval(encodings=["x"])
    # IMPORTANT: this must be applied once, at the *combined-layer* level (via
    # `.encode(x=zoomed_x)` on the whole `a + b + c` chart), never on an individual
    # child chart that then gets layered with others. When a per-layer scale(domain=)
    # override is layered with sibling charts that also reference the x field, Vega-Lite
    # silently discards the override and recomputes a plain union-of-data-extents
    # domain instead — the brush's selection signal still fires correctly (confirmed
    # via a live signal listener in a headless-browser test), but no scale actually
    # listens to it, so nothing visibly zooms. Verified via the compiled low-level
    # Vega spec (vegaLite.compile(spec).spec) showing a domain: {fields: [...]} union
    # instead of the expected domain: {signal: "brush_..."} reference.
    zoomed_x = alt.X("bucket:T", title="Time", scale=alt.Scale(domain=brush))
    path_scale = alt.Scale(domain=all_paths, scheme="category20")
    # Vega's default legend symbolLimit (30) truncates long legends to a bare count
    # ("N entries") instead of listing them — raise it so every endpoint renders,
    # in columns so the resulting tall legend scrolls with the page.
    color = alt.Color(
        "path:N",
        title="Endpoint",
        scale=path_scale,
        legend=alt.Legend(symbolLimit=len(all_paths), columns=2, labelLimit=280),
    )
    color_no_legend = alt.Color("path:N", scale=path_scale, legend=None)

    line = (
        alt.Chart(agg)
        .mark_line(point=True)
        .encode(
            y=alt.Y("max_ms:Q", title="Max response time (ms)"),
            color=color,
            opacity=alt.condition(selection, alt.value(1), alt.value(0.05)),
            tooltip=["bucket:T", "path:N", "avg_ms:Q", "max_ms:Q", "count:Q"],
        )
        .add_params(selection)
        .properties(width=1000, height=400, title=f"{app_label} — max response time per endpoint, 10-min buckets (click legend to enable/disable endpoints; drag the zoom bar below to pick a time range)")
    )
    ceiling = (
        alt.Chart(pd.DataFrame({"y": [AZURE_WINDOWS_IDLE_TIMEOUT_MS]}))
        .mark_rule(color="red", strokeDash=[4, 4])
        .encode(y="y:Q")
    )
    # `ceiling` deliberately stays OUTSIDE the x-encoded group below (added as a
    # sibling afterward, not flattened in) — it has no x/x2 of its own (that's what
    # lets it auto-span the full plot width) and its data has no `bucket` field, so
    # sharing the group's x encoding with it would break it.
    line_chart = (
        (line + incident_rules + incident_labels).encode(x=zoomed_x).resolve_scale(color="independent")
    ) + ceiling

    def _metric_group(df, color, y_title):
        # Shaded band between min and max, the avg as a solid line, min/max as thin
        # dashed lines on top of the band edges. None of these define their own x —
        # supplied once by the caller's `.encode(x=zoomed_x)`, same reasoning as
        # elsewhere in this file.
        band = (
            alt.Chart(df)
            .mark_area(color=color, opacity=0.15)
            .encode(y=alt.Y("min_value:Q", title=y_title, scale=alt.Scale(domain=[0, 100])), y2="max_value:Q")
        )
        avg_line = (
            alt.Chart(df)
            .mark_line(point=True, color=color)
            .encode(
                y=alt.Y("avg_value:Q"),
                tooltip=["bucket:T", "avg_value:Q", "min_value:Q", "max_value:Q"],
            )
        )
        min_line = (
            alt.Chart(df)
            .mark_line(color=color, strokeDash=[2, 2], opacity=0.6)
            .encode(y=alt.Y("min_value:Q"))
        )
        max_line = (
            alt.Chart(df)
            .mark_line(color=color, strokeDash=[2, 2], opacity=0.6)
            .encode(y=alt.Y("max_value:Q"))
        )
        return band + avg_line + min_line + max_line

    cpu_chart = None
    ram_chart = None
    if metrics_df is not None and not metrics_df.empty:
        cpu_df = metrics_df[metrics_df["metric"] == "CpuPercentage"]
        ram_df = metrics_df[metrics_df["metric"] == "MemoryPercentage"]

        if not cpu_df.empty:
            cpu_chart = (_metric_group(cpu_df, "#8e44ad", "CPU (%)") + incident_rules_nolegend).encode(x=zoomed_x).properties(
                width=1000, height=180, title=f"{app_label} — CPU usage (%), avg/min/max per 10-min bucket — linked to the legend above"
            )

        if not ram_df.empty:
            ram_chart = (_metric_group(ram_df, "#2980b9", "Memory (%)") + incident_rules_nolegend).encode(x=zoomed_x).properties(
                width=1000, height=180, title=f"{app_label} — memory usage (%), avg/min/max per 10-min bucket — linked to the legend above"
            )

    occurrence = (
        alt.Chart(agg)
        .mark_line(point=True)
        .encode(
            y=alt.Y("count:Q", title="Requests (occurrences)"),
            color=color_no_legend,
            opacity=alt.condition(selection, alt.value(1), alt.value(0.05)),
            tooltip=["bucket:T", "path:N", "avg_ms:Q", "max_ms:Q", "count:Q"],
        )
        .properties(width=1000, height=250, title="Request volume per endpoint, 10-min buckets — linked to the legend above")
    )
    occurrence_chart = (occurrence + incident_rules_nolegend).encode(x=zoomed_x).resolve_scale(color="independent")

    # Horizontal zoom bar: always shows the full time range; drag to select a window,
    # click once to clear it. Total request volume is the overview signal.
    zoom_bar = (
        alt.Chart(agg)
        .mark_area(color="#7f8c8d", opacity=0.6)
        .encode(
            x=alt.X("bucket:T", title="Drag to zoom (click to reset) — applies to every chart"),
            y=alt.Y("sum(count):Q", title=None, axis=None),
        )
        .add_params(brush)
        .properties(width=1000, height=60)
    ) + incident_rules_with_own_x

    status_domain, status_range = status_color_scale(status_agg["status"].dropna().unique())
    status_chart_base = (
        alt.Chart(status_agg)
        .mark_bar()
        .encode(
            y=alt.Y("count:Q", title="Requests"),
            color=alt.Color(
                "status:N",
                title="Response code",
                scale=alt.Scale(domain=status_domain, range=status_range),
                sort=status_domain,
            ),
            opacity=alt.condition(selection, alt.value(1), alt.value(0.05)),
            tooltip=["bucket:T", "path:N", "status:N", "count:Q"],
        )
        .properties(width=1000, height=250, title="Request count per response code, 10-min buckets — linked to the legend above")
    )
    status_chart = (status_chart_base + incident_rules_nolegend).encode(x=zoomed_x).resolve_scale(color="independent")

    avg_ms_domain, avg_ms_range = avg_ms_gradient_scale(agg["avg_ms"].max())
    heatmap = (
        alt.Chart(agg)
        .mark_rect()
        .encode(
            y=alt.Y("path:N", title="Endpoint", sort=all_paths),
            color=alt.Color(
                "avg_ms:Q",
                scale=alt.Scale(type="linear", domain=avg_ms_domain, range=avg_ms_range, clamp=True),
                title="Avg ms",
            ),
            opacity=alt.condition(selection, alt.value(1), alt.value(0.15)),
            tooltip=["bucket:T", "path:N", "avg_ms:Q", "max_ms:Q", "count:Q"],
        )
        .properties(width=1000, height=15 * len(all_paths), title="Avg response time heatmap — linked to the legend above")
    )
    heatmap_chart = (heatmap + incident_rules_nolegend).encode(x=zoomed_x).resolve_scale(color="independent")

    panels = [line_chart]
    if cpu_chart is not None:
        panels.append(cpu_chart)
    if ram_chart is not None:
        panels.append(ram_chart)
    panels += [occurrence_chart, status_chart, zoom_bar, heatmap_chart]

    combined = alt.vconcat(*panels)
    combined.save(os.path.join(output_dir, "timetaken_report.html"))
    return combined


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", default="https://sfcloud-monitoreo.smartfran.com/graylog/api")
    ap.add_argument("--stream-id", required=True, help="The App Service's PROD-{App}-AppServiceHTTPLogs stream id — see cloud-appservice-perf-report skill for the per-app table")
    ap.add_argument("--from", dest="time_from", required=True)
    ap.add_argument("--to", dest="time_to", required=True)
    ap.add_argument("--bucket-minutes", type=int, default=10)
    ap.add_argument("--data-dir", default=DEFAULT_DATA_DIR, help=f"Where raw/aggregated data files go (default: {DEFAULT_DATA_DIR})")
    ap.add_argument("--report-dir", default=DEFAULT_REPORT_DIR, help=f"Where the final HTML report goes (default: {DEFAULT_REPORT_DIR})")
    ap.add_argument("--app-label", default="App Service", help="Used in chart titles, e.g. 'Sales-PRO'")
    ap.add_argument("--raw-csv", default=None, help="Skip fetch, parse this existing raw export instead")
    ap.add_argument(
        "--all-paths",
        action="store_true",
        help="Include everything (Kudu/Azure infra, SignalR hub negotiate, static files), not just versioned API routes (/api/v<N>/...). Off by default.",
    )
    ap.add_argument(
        "--incident",
        action="append",
        default=None,
        metavar="ISO_TIMESTAMP|LABEL|TYPE",
        help="Vertical marker line, e.g. '2026-09-13T23:55:00Z|Crash 23:55Z|oom' (pipe-separated, ISO timestamp has colons). TYPE is optional (defaults to 'default', orange) and picks the marker's color — see INCIDENT_TYPE_COLORS. Repeatable. Takes precedence over --incidents-file.",
    )
    ap.add_argument(
        "--incidents-file",
        default=None,
        help="Plain text file, one 'ISO_TIMESTAMP|Label' or 'ISO_TIMESTAMP|Label|Type' per line (# comments/blank lines ignored) — see cloud-appservice-perf-report skill. Ignored if --incident is also given.",
    )
    ap.add_argument(
        "--metrics-json",
        default=None,
        help="Path to an `az monitor metrics list --aggregation Average Minimum Maximum` JSON (CpuPercentage, MemoryPercentage — plan-level Microsoft.Web/serverfarms metrics) for the App Service Plan — adds linked CPU/RAM %% panels. Optional.",
    )
    args = ap.parse_args()

    if args.incident:
        incidents = []
        for i in args.incident:
            parts = i.split("|", 2)
            ts, label = parts[0], parts[1]
            itype = parts[2] if len(parts) > 2 and parts[2] else "default"
            incidents.append((ts, label, itype))
    elif args.incidents_file:
        incidents = load_incidents_file(args.incidents_file)
    else:
        incidents = []

    api_key = os.environ.get("GRAYLOG_API_KEY")
    if not api_key and not args.raw_csv:
        sys.exit("GRAYLOG_API_KEY env var not set")

    os.makedirs(args.data_dir, exist_ok=True)
    os.makedirs(args.report_dir, exist_ok=True)

    if args.raw_csv:
        raw_path = args.raw_csv
    else:
        raw_path = os.path.join(args.data_dir, "raw_export.csv")
        print(f"Fetching {args.time_from} -> {args.time_to} from stream {args.stream_id} ...")
        fetch_raw_export(args.base_url, api_key, args.stream_id, args.time_from, args.time_to, raw_path)
        print(f"Wrote {raw_path}")

    agg, agg_detailed = parse_and_bucket(raw_path, args.bucket_minutes, versioned_api_only=not args.all_paths)
    if agg.empty:
        sys.exit("No parseable rows found (check CsUriStem/TimeTaken presence in properties)")

    agg_path = os.path.join(args.data_dir, "timetaken_by_path_aggregated.csv")
    agg_detailed.to_csv(agg_path, index=False)
    print(f"Wrote {agg_path} ({len(agg_detailed)} rows, split by referer/status)")

    metrics_df = None
    if args.metrics_json:
        metrics_df = load_azure_metrics(args.metrics_json, args.bucket_minutes)
        print(f"Loaded {len(metrics_df)} CPU/RAM metric rows from {args.metrics_json}")

    build_charts(agg, agg_detailed, args.report_dir, incidents, args.app_label, metrics_df=metrics_df)
    print(f"Wrote {args.report_dir}/timetaken_report.html")

    near_ceiling = agg[agg["max_ms"] >= AZURE_WINDOWS_IDLE_TIMEOUT_MS - 5000]
    print(f"\n{len(near_ceiling)} bucket/path rows within 5s of the {AZURE_WINDOWS_IDLE_TIMEOUT_MS}ms Azure Windows idle timeout")


if __name__ == "__main__":
    main()
