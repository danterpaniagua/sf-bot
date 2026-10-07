# Investigation — 20260915_sales-appservice-perf-report

**Status:** OPEN — general health check, not tied to a specific reported incident.
**Jira ticket:** not yet provided — ask before producing any external-facing output (ticket, email). See root `CLAUDE.md` → "External References — Jira, Not Local Paths."

## Scope

User requested a performance report for `SmartFran-Cloud-Sales-PRO` via `/cloud-appservice-perf-report`, general/ad-hoc rather than tied to a known incident window. No specific symptom reported yet.

## Window

Default 24h window, since no specific incident time was given:
- Start: `2026-09-14T22:55:49.000Z`
- End: computed dynamically at run time (`date -u '+%Y-%m-%dT%H:%M:%S.000Z'`)

## Incidents file

`incidents.txt` created empty in this event folder — no known incident markers to plot yet. Add entries if a specific timestamp turns out to be notable once the report is reviewed.

## Window extended to 3 days (user, 2026-09-15)

Start: `2026-09-12T23:02:03.000Z`. Report rebuilt (10,579 aggregated rows, 864 CPU/RAM metric points).

**Escalation confirmed — not steady background noise:** near-230s-timeout rows by day: `09-12`=5, `09-13`=41, `09-14`=48, `09-15` (partial)=8. An 8-10x jump starting `09-13`, suggesting something changed/degraded around then rather than a constant rate. Original 24h window (which only covered part of `09-15`) undersold the scale of this.

**Spread across 16 different endpoints, not isolated to `POSGetAll`:** `POSGetAll` still dominant (63/117 near-timeout rows), but `Shift/GetPaginatedForReportByFilterAsync`, `Sale/Create`, `PaymentMethod/GetAll`, `WsFePe/GetMaxAmountCustomerRequired`, `WsFeAr/CaeRequest`, `Sale/Close`, and even `Status/Health` also show occasional exact-230s timeouts. Endpoints this unrelated hitting the same precise threshold points toward a shared downstream dependency or connection-pool exhaustion, not a `POSGetAll`-specific bug — not yet confirmed which.

**`WsFeAr/CaeRequest` 408s over 3 days: 694** (~230/day average) — the known prior ticket (`20260825_sales-caerequest-408-timeout`) is clearly still active at meaningful volume, not resolved.

**Not yet done:** correlate against the CPU/RAM panel for the escalation window.

## CROSS-REFERENCE: this is the same incident as [GITIN-2040](https://smartit-ar.atlassian.net/browse/GITIN-2040), already open — `cloud/events/20260913_pos-net-http-timeout/`

That investigation already confirmed: `SmartFran-Cloud-Sales-PRO` crashing repeatedly on `System.OutOfMemoryException`, pattern starting `2026-09-12T23:15:26Z` (matches this report's `09-13` escalation almost exactly), 7 crashes on `09-13` alone (Azure Proactive Crash Monitoring). Each crash forces ANCM to kill/restart the worker process, leaving in-flight requests unanswered until the client's own timeout expires. Autoscaling already maxed at 4 instances — no spare capacity. Status: root cause confirmed, remediation pending; exact source of the memory growth itself still unconfirmed.

**That investigation already ran the same per-path/per-10-min 3-day response-time breakdown against the same Graylog stream (`PROD-Sales-AppServiceHTTPLogs`, `6a8edd694814bcaed323f9d6`) this report uses**, and already found that at crash time, practically all endpoints degrade simultaneously (not one isolated endpoint) — matching this report's 16-endpoint spread. It also explicitly ruled out `GetPaginatedForReportByFilterAsync` as an isolated cause (chronically slow throughout the period, not correlated with crash timing) — consistent with this report's 6 near-timeout occurrences for that endpoint.

**This session's report adds, rather than newly discovers:** a CPU/RAM-correlated HTML view of the same underlying pattern GITIN-2040 already root-caused via a Graylog pivot table. Worth feeding this report (`data/timetaken_report.html`) back into GITIN-2040 as an additional visualization/confirmation angle, not treating this event folder as a separate incident.

## Candidate crash timestamps identified via clustered multi-endpoint markers (2026-09-15)

All 117 near-230s-timeout bucket/path rows were added to `incidents.txt` individually (103 unique timestamp/label lines after grouping by bucket). Grouping by timestamp, three clusters stand out where many unrelated endpoints hit the timeout in the same 10-min bucket simultaneously — the exact "practically all endpoints degrade at once" signature GITIN-2040 attributes to an OOM crash, not scattered independent slowness:

- **`2026-09-14T18:40:00Z`** — 10 distinct endpoints (`Movement/POSGetAll`, `PaymentMethod/GetAll`, `Sale/AddRelatedCode`, `Sale/Close`, `Sale/Create`, `Shift/GetLastShifts`, `Shift/GetPaginatedForReportByFilterAsync`, `Status/Health`, `WsFePe/GeneratePending`, `WsFePe/GetMaxAmountCustomerRequired`).
- **`2026-09-14T20:30:00Z`** and **`2026-09-14T20:40:00Z`** — 11 distinct endpoints each, two consecutive 10-min buckets — likely one continuous ~20-minute event rather than two separate ones.

These are strong **candidate crash timestamps** for GITIN-2040's own crash-monitoring data (Azure Proactive Crash Monitoring `appcrashes` detector) to cross-check against — if they line up, this pins down exact crash times beyond the "7 crashes on 09-13" count GITIN-2040 already has, extending its evidence into `09-14`. Not yet cross-checked against that detector directly in this session.

**Important caveat, confirmed by a different mechanism (`ComputerName` field in the raw export):** `ComputerName` identifies the VM instance, not the worker process — an OOM crash that ANCM catches and restarts happens on the *same* VM, so VM-level instance turnover (15 distinct instances observed over 3 days, with a real handoff around `2026-09-14T21:35-21:46Z`) is structurally unable to confirm or deny a worker-process-level crash at these specific cluster timestamps. Not useful for this specific question, kept here only to record that it was checked and ruled out as a confirmation method.

## `HealthCheckStatus` metric — real signal, partially corroborates, partially complicates (user, 2026-09-15)

Pulled `HealthCheckStatus` (Microsoft.Web/sites metric, `PT5M`, `Average`/`Minimum`) for the same 3-day window — full file: `data/healthcheck_status.json`. This is a genuine Azure-reported signal (App Service's own health-check probe result), not inferred from HTTP logs like the clusters above.

**Only one dip in the entire 3-day, 869-sample series:** `2026-09-13T23:57:00Z` — `average=75.0`, `minimum=0.0`. This **corroborates the `2026-09-13T23:50:00Z` HTTP-log cluster** (4 endpoints) — 7 minutes apart, within the gap between the two sources' sampling granularity (10-min HTTP buckets vs. 5-min health-check samples). This is the one cluster in this investigation with independent, non-inferred confirmation.

**Not corroborated: the two largest clusters, `2026-09-14T20:30:00Z` and `20:40:00Z` (11 endpoints each) — the ones that looked like the strongest crash candidates by endpoint-count — show no corresponding `HealthCheckStatus` dip at all.** Only the smaller `09-13` cluster has independent confirmation; the larger `09-14` clusters don't, despite being more dramatic in the HTTP-log view. Not resolved — possible explanations (health-check endpoint staying responsive while other capacity was saturated; a dip too brief for a 5-minute sample; a different underlying cause for the `09-14` events) are all still open, none confirmed. **"Bigger endpoint-count cluster = more likely a real crash" does not hold up against this data** — don't carry that assumption into `GITIN-2040` without flagging this contradiction.

## Cross-checked via Log Analytics workspace `SmartFranCloudPro` (user, 2026-09-15) — two more data points, same conclusion

Discovered Sales-PRO actually has **two** diagnostic settings, not one: alongside the Event-Hub-to-Graylog one (`AllMetrics` disabled — confirms metrics never reach Graylog currently), a second one routes **all 9 log categories + `AllMetrics`** to Log Analytics workspace `SmartFranCloudPro` (customerId `76536d4a-5616-44ae-bee4-0aa6963b5d28`). `AppServicePlatformLogs` — asked about specifically — produces **no table at all** in this workspace (zero rows ever ingested for that category); confirmed empty, not useful for this investigation.

- **`AppExceptions` (Application Insights table) is completely empty for Sales-PRO across the full 3-day window** — no exception records at all, not even the `OutOfMemoryException` crashes `GITIN-2040` already confirmed via Azure's separate Proactive Crash Monitoring detector. Not necessarily a contradiction: an OOM crash typically kills the process before the App Insights SDK can flush its telemetry buffer — a known limitation of exception tracking for this specific crash type, not evidence against it. Table schema exists in the workspace only because other apps sharing it populate `AppExceptions`, not Sales-PRO.
- **`AzureMetrics`'s `HealthCheckStatus` (1-minute granularity, finer than the earlier `PT5M` pull) confirms the exact same single event:** `2026-09-13T23:58:00Z` and `23:59:00Z`, both `Average=50`, `Minimum=0` — a ~2-3 minute degraded window. **No second dip anywhere else in the 3 days**, including nothing near the `09-14` `20:30`/`20:40` clusters. Two independent data sources (`az monitor metrics` and this Log Analytics query) now agree on the same single confirmed event and the same absence of confirmation for the larger `09-14` clusters.

## Report built (2026-09-15) — superseded by the 3-day window below, kept for the original 24h finding

- Original 24h pull: `data/httplogs_raw_export.csv` (150,534 rows), `data/cpu_ram_full_window.json` (290 metric rows). **Both files were overwritten by the 3-day re-pull** (see "Window extended to 3 days" above) — current on-disk state is 562,239 rows / 864 metric rows, not these original counts. Kept here as a record of what the initial 24h analysis found, not as a description of current file contents.
- `data/timetaken_by_path_aggregated.csv` and `data/timetaken_report.html` — also since regenerated against the 3-day data (10,579 aggregated rows, current state).

**Real finding (2026-09-15), from `data/timetaken_by_path_aggregated.csv`:**

- **`/api/v1/Movement/POSGetAll` recurring 230s-timeout → `500`, 8 times across the full 24h window** (03:00, 14:50, 18:40, 18:50, 19:30, 20:20, 21:00, 21:10 UTC — all `max_ms` in the 230,001–230,020 range, landing precisely on Azure's Windows App Service idle-connection timeout threshold). Called from `referer: https://grido.pos.smartfran.com/` — this is the POS client. Spread across the whole day, not a single incident window. Added to `incidents.txt` as 8 markers.
- **`/api/v1/Movement/GetFromMoneyWarehouse` — separate anomaly, same controller family:** returns `200` (succeeds) but takes 76–130 seconds repeatedly (11:10, 10:50, 13:30, 18:20, 13:40, 11:20, 12:00 UTC). Slow, not timing out — different symptom, possibly related root cause (same `Movement` controller as `POSGetAll`).
- **Other error clusters, likely already-known:** `/api/v1/WsFeAr/CaeRequest` → 47× `408` (matches prior ticket `cloud/events/20260825_sales-caerequest-408-timeout/`, likely the same recurring issue, not new). `/api/v1/Sale/Create` → 17× `503`, `/api/v1/Sale/Close` → 12× `503` — availability/capacity errors on core sale operations, not yet investigated further.

**Not yet done:** correlate these `POSGetAll` timeout timestamps against the CPU/RAM panel in `timetaken_report.html` to check for resource pressure at those exact times; check whether `POSGetAll`/`GetFromMoneyWarehouse` share a slow downstream dependency (DB query, external call) that would explain both the hard timeout and the near-timeout slow-but-successful pattern.

## Next steps (planned, not yet executed)

1. Cross-check the candidate crash timestamps (`09-14` `18:40`, `20:30`, `20:40`) against Azure's actual Proactive Crash Monitoring detector (`appcrashes`) — still not queried directly this session. Would either confirm real crashes at those times or reinforce that they're a different, unconfirmed phenomenon from the one `09-13T23:57-23:59` event that Health Check data does confirm.
2. Correlate the `09-13T23:57-23:59` confirmed event and the `09-14` candidate clusters against the CPU/RAM panel in `timetaken_report.html` — not yet done despite being flagged twice already.
3. Reconcile `AppExceptions` being empty for Sales-PRO with `GITIN-2040`'s H6 finding ("App Insights telemetry empty") — worth a note back to that ticket that this still holds for exceptions specifically, with the OOM-buffer-flush caveat recorded above.
4. Decide whether/how to feed this report (`data/timetaken_report.html`, the candidate-crash-timestamp list, the Health Check corroboration) back into `GITIN-2040` — flagged as worth doing, not yet actually done (no comment/update posted there).
5. Get the Jira ticket URL for *this* event folder before writing any ticket/email output for it specifically (separate from feeding evidence into `GITIN-2040`, which already has its own ticket).
