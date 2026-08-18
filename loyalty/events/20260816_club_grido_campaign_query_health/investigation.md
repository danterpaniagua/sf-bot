# Investigation: Club Grido campaign — query health during traffic peak

## Context

Sunday 2026-08-16, Club Grido sent a mass marketing campaign. Reported traffic peak: avg 80 POST req/s and 100 GET req/s. User wants to know the health of SQL queries on `PNSSRL` during the window 12:00–17:00 UTC-3.

Time window conversion (skill rule: GMT = UTC-3 + 3h):
- UTC-3: 2026-08-16 12:00 – 17:00
- GMT/UTC: 2026-08-16 15:00 – 20:00

Affected service: **MobileAppService** — `SFCG-MOBI-01/02` (Mobile service, per `loyalty-dba-investigation` skill's Known Infrastructure table). Traffic (80 POST/s, 100 GET/s avg peak) hit this service; the query-health question is whether `PNSSRL` showed CPU/blocking/wait stress correlated to that load.

Jira ticket: [GITIN-1866](https://smartit-ar.atlassian.net/browse/GITIN-1866)

## Status

Investigation closed for this ticket (GITIN-1866) scope. DB-layer and app-layer findings below are final; root cause of the 400 rate and the capacity/limits question for a larger future campaign are explicitly out of scope here and listed as proposed follow-up items — user reframed the ask mid-session (this was a low-impact campaign on a cold winter Sunday; the real question is headroom for a bigger one, which needs its own investigation, potentially reusing the existing `20260727_cpu_peaks_loadtest`/`20260803_cpu_peaks_loadtest`/`20260723_bloqueo_customerpointslog_loadtest` precedent — not yet read, `events/` is write-only unless explicitly requested).

## Working theory

Top-50 CPU-delta rows in the window (from raw `PNSSRL_AuditSysprocesses` snapshot diffs, 5-min cadence) show:
- `blocked = 0` on every row — no blocking observed in the top-CPU slice.
- Wait types mostly `MISCELLANEOUS` (idle carryover) or `ASYNC_NETWORK_IO` (app-side slow consumption of results); 3 rows show `SOS_WORK_DISPATCHER` (mild CPU scheduler contention) — not a red flag alone.
- Heaviest single deltas: spid 102 @ 15:56 (18.8s CPU/5min, `SFCG-WSIT-01`), spid 118 @ 19:31 (15.6s, `SFCG-WEBS-02`, runnable+`SOS_WORK_DISPATCHER`), spid 176 @ 18:51 (14.2s, `SFCG-WEBS-03`, same wait type).
- **Open question**: none of the top 50 rows show `hostname = SFCG-MOBI-01/02` (MobileAppService), which the user identified as the service the campaign hit. All top consumers are `SFCG-WEBS-*`/`SFCG-WSIT-01`/`SFCG-WSV2-01`. Need to confirm whether MobileAppService connects to `PNSSRL` directly (and just wasn't the top CPU driver this window) or routes through another tier — not yet documented in `docs/infrastructure.md`.

## Findings so far

**Service-level CPU breakdown (`PNSSRL_AuditSysprocesses`, 15:00–20:00 GMT window, CPU delta summed per host):**

| Host | Snapshot rows | Total CPU delta (ms) |
|---|---|---|
| `SFCG-WSV2-01` (WebServiceV2) | 401 | 306,890 — dominant, ~half of all SQL CPU in window |
| `SFCG-WEBS-01` | 1,291 | 65,512 |
| `SFCG-WEBS-02` | 764 | 52,594 |
| `SFCG-CLUB-01` | 434 | 49,706 |
| `SFCG-WEBS-03` | 394 | 40,326 |
| `SFCG-WSCG-01` | 10 | 28,157 |
| `SFCG-WSIT-01` | 14 | 24,809 |
| `SFCG-MOBI-02` | 1,483 | 14,075 |
| `SFCG-MOBI-01` | 157 | 110 |
| `SFCG-DB01`/`SFCG-TO-01` (SQL Agent, background) | — | ~2,750, normal |

**Blocking check across the full window**: 0 rows with `blocked <> 0`. No blocking observed at all in `PNSSRL_AuditSysprocesses` for 15:00–20:00 GMT.

**Cross-reference with Graylog (SmartLoyalty Mobile access log, endpoint hit counts + avg response time — window not yet confirmed as matching 12:00–17:00 UTC-3 exactly, treat as approximate for now):**

| Endpoint | Hits | Avg ms |
|---|---|---|
| `/api/Benefits/GetCustomerStatus` | 42,126 | 85 |
| `/api/Customer/GetCustomerProfile` | 42,874 | 66 |
| `/api/Account/Login` | 40,514 | 99 |
| `/api/AdditionalInformation/GetAddicionalInformation` | 48,215 | 28 |
| `/api/Account/RecoveryPassword` | 20,935 | 90 |
| `/api/Benefits/GetCustomerProvisionalPoints` | 13,724 | 84 |
| (remaining endpoints low-volume, <3k hits each) | | up to 649ms on `Catalog/AvailablePromotion` (23 hits only, not a volume driver) |

Total ~214,877 hits across the pasted set. All high-volume endpoints show healthy sub-100ms average response times, consistent with the low SQL-side CPU footprint measured for `SFCG-MOBI-01/02` above — no sign of app-layer or DB-layer stress from the Mobile tier during the campaign.

## Working theory (updated — conclusion)

Query health for the campaign window is clean:
- No blocking anywhere in `PNSSRL` during 15:00–20:00 GMT.
- MobileAppService (the service the campaign hit) shows the volume fingerprint (highest connection/snapshot-row count of any host — 1,483 rows on `MOBI-02`) but negligible CPU cost per query (~8.6ms avg/row) and healthy Graylog response times (sub-100ms average on all high-volume endpoints: `GetCustomerStatus`, `GetCustomerProfile`, `Login`, `GetAddicionalInformation`, `RecoveryPassword`, `GetCustomerProvisionalPoints`). The campaign traffic did not stress `PNSSRL`.
- `SFCG-CLUB-01` (Club Grido website) repeatedly executed **Query077** (`AvailablePromotion`, `Domain\Query\Query077-sql.xml` in `SmartLoyalty.WebService`) — 14+ times across the window, ~4,000–6,700ms CPU and ~12,000 logical reads each, via `PNSSRL_TempdbProc`. Fully accounts for `SFCG-CLUB-01`'s 49,706ms total CPU delta, and matches the slowest Graylog endpoint (`/api/Catalog/AvailablePromotion`, 649ms avg, though only 23 hits — not a volume driver). Cost driver: `CROSS JOIN` of two table-valued params (`@BranchOfficeTableTmp × @PromotionTmp`) inside `SmlSupp.PromotionBranchOffice`. Not blocking, not escalating — repeated fixed cost per call, not worsening over the window.

## Tangential (not part of this investigation — recorded for the record only)

`SFCG-WSV2-01` (WebServiceV2) was the single largest CPU consumer in the window (306,890ms, ~half the window total) but does not appear in `PNSSRL_TempdbProc` top-20 (no tempdb footprint), so its query is unidentified from these capture tables. Load was steady across the *entire* 15:00–20:00 window, not concentrated around the campaign's traffic pattern, and WebServiceV2 is a different service than the Mobile tier the campaign hit. Treated as a pre-existing baseline pattern unrelated to GITIN-1866, not chased further here. If worth investigating, open as a separate ticket/event — per repo convention, tangential findings don't get folded into an unrelated ticket's conclusion.

## Dead ends

None.

## Still open

- ~~Confirm whether the pasted Graylog hit-count window actually matches 2026-08-16 12:00–17:00 UTC-3~~ — **resolved, and window is wider than assumed**: user confirmed Graylog's actual peak-traffic window is **16:00–21:00 UTC**, not 15:00–20:00 UTC as converted from the original 12:00–17:00 UTC-3 ask. Total hits in the 16–21 UTC window: ~236,201 (vs ~214,877 in the originally-checked window) — confirms this is the real peak.
- ~~Gap: 20:00–21:00 UTC not checked~~ — **resolved**. 12 snapshots (20:01–20:56 UTC), full coverage, no blocking (0 rows). CPU breakdown for this hour: `SFCG-WEBS-03` 76,923ms (87 rows, ~884ms/row — notably higher intensity than its earlier average, standout for this hour), `SFCG-WEBS-01` 29,914ms, `SFCG-WEBS-02` 27,342ms, `SFCG-WSV2-01` 25,568ms (down sharply from its ~307k over the prior 5h — confirms that load was front-loaded/baseline, not sustained into this hour), `SFCG-CLUB-01` 2,859ms (Query077 activity tapered off), `SFCG-MOBI-02` 327ms, `SFCG-MOBI-01` 0ms. Mobile stayed negligible through the full actual peak window (16:00–21:00 UTC), combining this check with the earlier 15:00–20:00 UTC data.

## IIS/app-layer analysis (Graylog export, `Untitled-Message-Table-search-result(1).csv`, 302,748 rows)

Covers the confirmed peak window 2026-08-16 15:25–20:55 UTC (200-status count of 236,201 matches the user's earlier Graylog OK-only paste exactly — same underlying window/data). Almost entirely `SFCG-MOBI-02` (301,434 rows) vs `SFCG-MOBI-01` (1,314) — consistent with the DB-side finding that MOBI-02 carried the connection volume. 1,314 rows are `Zabbix` health-check traffic (excluded from the interesting findings below), 1,577 `Ruby` UA (source not yet identified — possibly a monitoring/test client, not confirmed).

**Status code totals**: 200 = 236,201; 400 = 65,796 (**21.7% of all traffic**); 404 = 750; 500 = 1.

**400 rate is sustained across the entire window, not a spike** — present from the very first bucket (15:25) at ~11%, climbing to and holding ~15–30% per 5-min bucket for the rest of the window. Breakdown by endpoint (OK counts from user's earlier Graylog paste, 400s from this file):

| Endpoint | OK | 400 | Total | 400 rate |
|---|---|---|---|---|
| `/api/Account/SaveNewMember` | 1,071 | 2,123 | 3,194 | 66.5% |
| `/api/Account/Login` | 46,483 | 50,605 | 97,088 | 52.1% |
| `/api/Account/RecoveryPassword` | 23,939 | 12,125 | 36,064 | 33.6% |
| `/api/Customer/GetCustomerProfile` | 46,169 | 902 | 47,071 | 1.9% |
| `/api/Benefits/GetCustomerStatus` | 45,309 | 8 (+707 404) | 46,024 | ~1.6% |

**Not confirmed**: root cause of the 400 rate. Could be expected UX-scale noise (wrong passwords, duplicate signups) or a real validation defect amplified by campaign traffic (malformed deep-link params, promo-code handling) — status codes alone don't distinguish these. Needs response-body/error-reason sampling to determine, not yet pulled.

**Latency**: average stayed flat and healthy throughout (55–76ms per bucket, no volume correlation). Occasional tail-latency bursts (max 2,000–3,500ms) recur roughly every 15–40 min throughout the window — not one incident, a recurring pattern.

**One genuine anomaly**: the 20:55 bucket has the worst tail latency of the whole window (max 6,573ms, 14 slow requests >1s) and contains the **only** 500 in all 302,748 rows (`GetCustomerProfile`, 20:58, `SFCG-MOBI-02`). Loosely coincides in time with `SFCG-WEBS-03`'s CPU intensity spike in the 20:00–21:00 UTC DB check, but that's a different host/service — **not confirmed as causally related**, flagging as a timing coincidence only.

**Traffic volume vs. reported peak**: busiest 5-min bucket (16:05 UTC) totals 8,956 requests ≈ 29.9 req/s sustained — well under the reported peak of 80 POST + 100 GET/s combined. Either that figure describes a sub-5-minute burst this bucket size doesn't resolve, or it was an estimate — not reconciled.

## Final conclusion (updated after IIS/app-layer analysis)

**DB layer (`PNSSRL`): clean.** Full campaign peak window (16:00–21:00 UTC, confirmed by Graylog as the actual high-traffic period) is covered end-to-end by `PNSSRL_AuditSysprocesses` (15:00–20:56 UTC combined checks) with zero blocking observed at any point. MobileAppService never exceeded negligible CPU cost per query in either checked segment. No DB-side incident.

**App layer (`SFCG-MOBI-01/02` IIS logs): not fully clean — two findings that change the overall answer.**
1. A **sustained 400 (Bad Request) rate of ~21.7% overall**, present from the start of the window and held steady (not a spike) — concentrated in `SaveNewMember` (66.5%), `Login` (52.1%), and `RecoveryPassword` (33.6%). Root cause not confirmed — could be expected UX-scale noise or a real validation defect; needs response-body/error-reason sampling to distinguish, not yet pulled. This is the most material finding of the investigation and is **not visible from the DB side at all** (these requests never reached `PNSSRL` as blocking/CPU events — a 400 is typically rejected before or without a full query).
2. A **latency degradation + the only 500 of the entire dataset**, both isolated to the 20:55–20:58 UTC bucket (`SFCG-MOBI-02`, `GetCustomerProfile`). Everything else in the window (avg latency, 5xx count) was flat and healthy. Loosely coincides in time with `SFCG-WEBS-03`'s CPU intensity spike in the same hour on the DB side — **not confirmed as related**, different host/service, flagged as a timing coincidence only.

**Net**: no DB-side incident, but the campaign correlates with a majority-failure rate on login/signup/recovery flows and one isolated 500+latency event at the tail of the window. Whether the 400 rate is a real defect or expected user-error-at-scale is the open question for GITIN-1866, not the DB.

## Tangential (not part of this investigation — recorded for the record only)

`SFCG-WSV2-01` (WebServiceV2) was the single largest CPU consumer of the 15:00–20:00 UTC window (306,890ms, ~half the window total) but does not appear in `PNSSRL_TempdbProc` top-20 (no tempdb footprint), so its query is unidentified from these capture tables. Load was steady across the *entire* window, not concentrated around the campaign's traffic pattern, and WebServiceV2 is a different service than the Mobile tier the campaign hit. Treated as a pre-existing baseline pattern unrelated to GITIN-1866, not chased further here. `SFCG-CLUB-01`'s Query077 (`AvailablePromotion`, `CROSS JOIN`-based, ~4,000–6,700ms CPU per call, 14+ executions) is a real optimization candidate but not blocking/escalating and not campaign-driven. If worth investigating, open as separate tickets/events — per repo convention, tangential findings don't get folded into this ticket's conclusion.
