# Investigation: Club Grido campaign — query health during traffic peak

## Context

Sunday 2026-08-16, Club Grido sent a mass marketing campaign. Reported traffic peak: avg 80 POST req/s and 100 GET req/s. User wants to know the health of SQL queries on `PNSSRL` during the window 12:00–17:00 UTC-3.

Time window conversion (skill rule: GMT = UTC-3 + 3h):
- UTC-3: 2026-08-16 12:00 – 17:00
- GMT/UTC: 2026-08-16 15:00 – 20:00

Affected service: **MobileAppService** — `SFCG-MOBI-01/02` (Mobile service, per `loyalty-dba-investigation` skill's Known Infrastructure table). Traffic (80 POST/s, 100 GET/s avg peak) hit this service; the query-health question is whether `PNSSRL` showed CPU/blocking/wait stress correlated to that load.

Jira ticket: [GITIN-1866](https://smartit-ar.atlassian.net/browse/GITIN-1866) — "[SML] Impacto Campañas". Ticket scope is general campaign-impact-on-DB analysis, not limited to the single 2026-08-16 occurrence — later spikes/campaigns are in-scope follow-ups under the same ticket, not scope creep.

**Linked tickets (per Jira, confirmed 2026-09-09):**
- **Blocks [GITIN-1981](https://smartit-ar.atlassian.net/browse/GITIN-1981)** — matches what's already known locally: `GITIN-1981` is the `PNSSRL_MantenimientoIndices` blocking-chain ticket split off from this one's 2026-08-28/29/30 weekend findings (`loyalty/events/20260901_pnssrl_mantenimientoindices_review/`).
- **Is blocked by [GITIN-1876](https://smartit-ar.atlassian.net/browse/GITIN-1876)** — **no local record at all**: zero references anywhere in this repo (`events/`, `docs/`, memory). Scope/content unconfirmed — don't assume what it covers without checking Jira directly.

## Status

2026-08-16 campaign window findings (below) are final. Reopened 2026-08-20 to cover a second occurrence — a MobileAppService traffic spike on 2026-08-19 21:00–22:00 UTC-3 (see "Follow-up: 2026-08-19 spike" below) — in-scope under GITIN-1866's general "campaign impact on DB" framing, not a separate ticket. Capacity/limits question for a larger future campaign remains a proposed follow-up item, potentially reusing the existing `20260727_cpu_peaks_loadtest`/`20260803_cpu_peaks_loadtest` precedent (not yet read, `events/` is write-only unless explicitly requested). `20260723_bloqueo_customerpointslog_loadtest` **has since been read** — not for this capacity question, but as precedent for the split-off `PNSSRL_MantenimientoIndices` finding below; see "Split off — GITIN-1981" and `loyalty/events/20260901_pnssrl_mantenimientoindices_review/investigation.md`.

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

### Query077 — actual source text (`loyalty/repo/dev-src-sol-smartloyalty/Core/Domain.Query/Domain/Query/Query077-sql.xml`, confirmed 2026-09-09)

```sql
DECLARE @params XML = {0}
DECLARE @BranchOfficeTableTmp TABLE (BranchOfficeId UNIQUEIDENTIFIER)
DECLARE @PromotionTmp TABLE (PromotionId INT)
DECLARE @branchOfficeCountryId INT;
DECLARE @Counter INT

SELECT @branchOfficeCountryId = n.value('cId[1][not(@xsi:nil = "true")]', 'int')
FROM @params.nodes('params') AS p(n)

INSERT INTO @BranchOfficeTableTmp
SELECT n.value('.', 'uniqueidentifier')
FROM @params.nodes('params/bo') AS p(n)

SELECT @Counter = @@ROWCOUNT

INSERT INTO @PromotionTmp
SELECT n.value('.', 'int')
FROM @params.nodes('params/pId') AS p(n)

DECLARE @branchOfficeCount INT
SELECT @branchOfficeCount = COUNT(*) FROM @BranchOfficeTableTmp

IF (@branchOfficeCountryId IS NOT NULL OR @branchOfficeCount = 0)
BEGIN
     INSERT INTO @BranchOfficeTableTmp
     SELECT BO.Id
     FROM Sml.BranchOffice BO WITH (NOLOCK)
     INNER JOIN Sml.[Address] A WITH (NOLOCK) ON A.Id = BO.AddressId
     INNER JOIN Sml.[Location] CITY WITH (NOLOCK) ON CITY.Id = A.LocationId
     INNER JOIN Sml.[Location] [STATE] WITH (NOLOCK) ON [STATE].Id = CITY.ParentLocationId
     INNER JOIN SML.[Location] COUNTRY WITH (NOLOCK) ON COUNTRY.Id = [STATE].ParentLocationId
     WHERE BO.ActivatedDate IS NOT NULL
     AND BO.DeactivatedDate IS NULL
     AND (@branchOfficeCountryId IS NULL OR COUNTRY.Id = @branchOfficeCountryId)

     SELECT @Counter = @@ROWCOUNT
END

IF((SELECT COUNT(*) FROM @PromotionTmp) > 0)
BEGIN
     SELECT  PBO.PromotionId
     FROM SmlSupp.PromotionBranchOffice PBO WITH (NOLOCK)
     INNER JOIN (SELECT BranchOfficeId, PromotionId
                 FROM @BranchOfficeTableTmp
                 CROSS JOIN @PromotionTmp) temp ON temp.PromotionId = PBO.PromotionId
                                               AND temp.BranchOfficeId = PBO.BranchOfficeId
     GROUP BY PBO.PromotionId
END
ELSE
BEGIN
     SELECT  PBO.PromotionId
     FROM SmlSupp.PromotionBranchOffice PBO WITH (NOLOCK)
     INNER JOIN @BranchOfficeTableTmp temp ON temp.BranchOfficeId = PBO.BranchOfficeId
     GROUP BY PBO.PromotionId
     HAVING COUNT(DISTINCT PBO.BranchOfficeId) = @Counter
END
```

**New detail from the actual source, not previously captured:** the `CROSS JOIN`'s real size isn't a fixed structural cost — `@BranchOfficeTableTmp` gets populated with *every active branch office in the given country* whenever no specific branch-office list is passed (or a country filter is given) (`IF (@branchOfficeCountryId IS NOT NULL OR @branchOfficeCount = 0)`). So the CPU cost scales with how many branches match that filter × how many promotions are passed — a call with a broad/no branch filter and many promotions is the worst case. This refines the optimization angle: filtering branch offices down to only the ones actually relevant *before* the cross join (rather than pulling the whole country's active branches into the temp table first) is the concrete lever, not just "add an index."

## Tangential (not part of this investigation — recorded for the record only)

`SFCG-WSV2-01` (WebServiceV2) was the single largest CPU consumer in the window (306,890ms, ~half the window total) but does not appear in `PNSSRL_TempdbProc` top-20 (no tempdb footprint), so its query is unidentified from these capture tables. Load was steady across the *entire* 15:00–20:00 window, not concentrated around the campaign's traffic pattern, and WebServiceV2 is a different service than the Mobile tier the campaign hit. Treated as a pre-existing baseline pattern unrelated to GITIN-1866, not chased further here. If worth investigating, open as a separate ticket/event — per repo convention, tangential findings don't get folded into an unrelated ticket's conclusion.

## Dead ends

- Retroactive `.svclog`-based attribution for `SaveNewMember`/`Login`/`RecoveryPassword` on the 2026-08-16 and 2026-08-19 occurrences: mechanism fully validated (see "Real `.svclog` pull received" above), but user confirmed no rotated/archived copy of `SmartLoyalty.MobileAppService.svclog` exists reaching back to either campaign window — the only file available (pulled 2026-08-20) rotated past both windows before it could be pulled (~11–12h retention at observed fill rate). This specific data is unrecoverable; not pursued further for this ticket.

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

## Follow-up: 2026-08-19 spike

**Context**: User reports a traffic spike of ~100 req/s on MobileAppService yesterday (2026-08-19), 21:00–22:00 UTC-3. Not yet confirmed against Graylog/`PNSSRL` data — reported figure only so far.

Time window conversion (GMT = UTC-3 + 3h):
- UTC-3: 2026-08-19 21:00 – 22:00
- GMT/UTC: 2026-08-20 00:00 – 01:00

This window does **not** overlap the 2026-08-16 campaign window above — separate occurrence, same host tier (MobileAppService, `SFCG-MOBI-01/02`). Continuing under this ticket/event folder per user instruction rather than opening a new one.

**Q7 result (data availability)**: 12 snapshots, 00:01:00.567–00:56:00.157 UTC, 5-min cadence — full coverage of the 00:00–01:00 UTC window.

**Q8 result (blocking check)**: 0 rows. No blocking in `PNSSRL` during the spike window.

**Q9 result (hostname CPU breakdown, 2026-08-20 00:00–01:00 UTC)**:

| Host | Snapshot rows | Total CPU delta (ms) |
|---|---|---|
| `SFCG-WSV2-01` | 56 | 63,320 — dominant |
| `SFCG-WEBS-02` | 85 | 11,273 |
| `SFCG-CLUB-01` | 55 | 6,935 |
| `SFCG-WSCG-01` | 1 | 3,985 |
| `SFCG-WSIT-01` | 3 | 2,983 |
| `SFCG-CLUB-02` | 53 | 2,828 |
| `SFCG-WEBS-01` | 178 | 2,719 |
| `SFCG-WEBS-03` | 39 | 906 |
| `SFCG-MOBI-02` | 144 | 156 |
| `SFCG-MOBI-01` | 26 | 0 |
| `SFCG-DB01`/`SFCG-TO-01` (SQL Agent, SSMS, background) | — | ~590, normal |

**DB layer (spike window): clean, same pattern as the 2026-08-16 campaign.** No blocking (Q8: 0 rows). MobileAppService (`SFCG-MOBI-01/02`, the tier the reported spike hit) shows negligible CPU cost — 156ms total on `MOBI-02` across 144 snapshot rows, 0ms on `MOBI-01`. `SFCG-WSV2-01` is again the dominant CPU consumer (63,320ms/hour here vs. ~61,400ms/hour average in the 2026-08-16 window's 5h span) — consistent rate, reinforcing the prior tangential finding that this is a steady pre-existing baseline load, not campaign/spike-driven, and not related to MobileAppService.

### IIS/app-layer analysis (Graylog export, `Messages-search-result.csv`, 84,428 raw rows; 28,028 are `iis_w3c_mobile` IIS log lines, the rest are `svclog_input` app-level events — status/latency analysis below uses IIS rows only)

Export's `EventReceivedTime` (Graylog ingestion) spans 2026-08-20 00:00:00–01:59:58 UTC, wider than the reported 21:00–22:00 UTC-3 (00:00–01:00 UTC) spike window — covers a second hour too. Internal IIS `date`/`time` fields (actual request time, ~1min ingestion lag behind `EventReceivedTime`) place the real coverage at 2026-08-19 23:59–2026-08-20 01:59 UTC.

Almost entirely `SFCG-MOBI-02` (27,552 rows) vs `SFCG-MOBI-01` (476) — same volume-carrier pattern as the 2026-08-16 window.

**Status code totals (IIS rows only)**: 200 = 23,787; 400 = 4,144 (**14.8%**); 404 = 97; 500 = 0.

**Endpoint breakdown**:

| Endpoint | Total | 400 | 400 rate |
|---|---|---|---|
| `/api/Account/SaveNewMember` | 448 | 320 | 71.4% |
| `/api/Account/Login` | 4,677 | 3,050 | 65.2% |
| `/api/Account/RecoveryPassword` | 1,746 | 637 | 36.5% |
| `/api/Customer/GetCustomerProfile` | 5,757 | 130 | 2.3% |
| `/api/Benefits/GetCustomerStatus` | 5,603 | 4 (+84 404) | 0.1% |
| `/api/AdditionalInformation/GetAddicionalInformation` | 6,593 | 0 | 0% |
| `/api/Benefits/GetCustomerProvisionalPoints` | 2,390 | 0 (+13 404) | 0% |
| (remaining endpoints low-volume, <600 hits each) | | | 0–2 errors each |

**This reproduces the exact 400-rate pattern from the 2026-08-16 campaign window**, on the same three endpoints, same rank order (`SaveNewMember` > `Login` > `RecoveryPassword` >> everything else): 71.4/65.2/36.5% here vs. 66.5/52.1/33.6% on the 16th. Two independent occurrences, same signature — this materially strengthens the case that it's a real, recurring validation defect on these three flows rather than campaign-specific user-error noise (the open question flagged as "not confirmed" in the 2026-08-16 conclusion below).

**No 500 errors** in this window (vs. the single isolated 500 found at the tail of the 2026-08-16 window).

**Latency**: healthy — avg 53.2ms, p95 116ms, max 1,098ms (single outlier, 01:25 bucket). No sustained degradation.

**Traffic volume vs. reported spike (100 req/s)**: busiest 5-min bucket (2026-08-20 01:25, actual-time) = 1,396 requests ≈ 4.7 req/s. Every 5-min bucket across the full 2-hour export is in the 2.9–4.7 req/s range — **no bucket comes close to the reported 100 req/s**, and there's no sharp spike shape either (traffic is flat/steady across the whole export, gradually rising from ~3.3 req/s at 00:00 to a mild peak near 01:25 then tapering). Same unreconciled gap as the 2026-08-16 campaign ("reported peak vs. measured 5-min-bucket rate" — see that section): either the 100 req/s figure describes a sub-5-minute burst this bucket size can't resolve, or it's an estimate from a different measurement point (e.g. load balancer/gateway level, not this IIS log). Not reconciled here either.

**DB-side cross-reference**: this app-layer traffic level (steady ~3–5 req/s, no sharp spike) is consistent with the DB-side finding above (negligible `SFCG-MOBI-01/02` CPU, no blocking) — nothing here contradicts the "DB layer clean" conclusion.

### Follow-up conclusion (2026-08-19 spike)

**DB layer: clean**, same as 2026-08-16 — no blocking, negligible MobileAppService CPU cost.

**App layer: same defect signature as 2026-08-16, now seen twice.** The ~15–71% 400 rate concentrated on `SaveNewMember`/`Login`/`RecoveryPassword` recurs with the same rank order and similar magnitude across two independent occurrences six days apart. Combined with this, the reported 100 req/s spike does not show up in either occurrence's IIS logs (measured peak both times: ~30 req/s on the 16th, ~4.7 req/s here) — raises the open question of whether "spike" reports from upstream (campaign trigger, gateway/LB metrics) reflect a measurement point this IIS log can't see, separate from the 400-rate question.

**Net for GITIN-1866 (updated)**: DB layer clean across both occurrences. The recurring 400 rate on the three auth/signup endpoints is the standing open item — now with two data points instead of one — still not root-caused (needs response-body/error-reason sampling, not yet pulled either time).

## Source-code root-cause analysis (400/404 mechanism)

Read directly from the local read-only clone (`repo/dev-src-sol-smartloyalty/Front/MobileAppService/`) — `Controllers/AccountController.cs`, `Controllers/CustomerController.cs`, `Controllers/BenefitsController.cs`, `Filters/Logger.cs`, `Filters/ModelValidatorFilter.cs`, `Core/Shared/Code/BusinessRulesCode.cs`, `Models/Request/{LoginRequest,NewMemberRequest,AccountPasswordRequest}.cs`. This confirms the **mechanism** by which 400s are produced; it does not confirm the **real-world attribution** (which cause accounts for what share of the observed 400 counts) — that still needs response-body/`st`-field sampling from actual traffic, not yet pulled.

**Two independent mechanisms produce a 400, both applied at the `AccountController`/`CustomerController`/`BenefitsController` level:**

1. `[ModelValidatorFilter]` (controller-level attribute, runs in `OnActionExecuting` before the action body) — if `ModelState` is invalid, returns 400 immediately with `st` = a `CODE|xxx` tag pulled from the failing property's `[Required]`/`[RegularExpression]`/`[MinLength]` `ErrorMessage`, or `st = "BadRequest"` if the failing attribute has no `CODE|` tag.
2. `[Logger(...)]` (per-action attribute, runs in `OnActionExecuted`) — if the action threw **any** exception, unconditionally rewrites the response to 400 with `st` = the business-rule code if it's a `BusinessRulesException`, else `st = "Fail"`. This means every server-side business-rule violation (age check, existing-account check, expired card, etc.) surfaces as a generic HTTP 400 — same status code as a truly malformed client request. Worth flagging as a design smell independent of this ticket's scope, not chased further here.

**Endpoint-by-endpoint, non-OK codes and their trigger:**

| Endpoint | HTTP | `st` | Trigger |
|---|---|---|---|
| `Login` | 400 | `CODE\|UidSerie` | `UidSerie` fails `^([1-9][0-9]{5})([0-9]{0,6})$` — 6–12 digits, no leading zero |
| `Login` | 400 | `CODE\|RequiredAuthMethod` | `AuthMethod` missing |
| `Login` | 400 | `BadRequest` | `UidCode`/`MemberCountryCode` missing |
| `Login` | 400 | `InvalidAuthMethod` | `AuthMethod` not `Facebook`/`Apple`/`LoginPassword` |
| `Login` | 400 | *(external service code, not in this repo)* | `Authenticate()` → `UserAccessApplicationSvc.LoginUser()` — wrong password/unknown user; plausibly the source of the `InvalidPassword` app-event seen in the 2026-08-19 Graylog `svclog_input` rows (2,276 occurrences) — not confirmed as the same code path, just consistent |
| `Login` | 400 | `UserNotCustomer` | Authenticated user has no linked `Customer` record |
| `SaveNewMember` | 400 | `CODE\|UidSerie`/`UidCode`/`FirstName`/`LastName`/`Email`/`PasswordTooShort` | Missing required field, or `Password` <6 chars |
| `SaveNewMember` | 400 | `InvalidDocumentFormat` / `DocumentTooShort` | `UidSerie` non-numeric or below `Settings.DocumentMinLength` |
| `SaveNewMember` | 400 | `InvalidEmailFormat` / `InvalidEmailDomain` | Malformed email, or domain on `Settings.BlockedEmailDomains` |
| `SaveNewMember` | 400 | `InvalidDateOfBirth` | `BirthDate` not parseable as `yyyy-MM-dd` |
| `SaveNewMember` | 400 | `CustomerMinor` | Age below `CustomerMinAge` |
| `SaveNewMember` | 400 | `PendingCustomerExists` | No `CardNumber` given but a pending affiliate card already exists for this DNI |
| `SaveNewMember` | 400 | `PendingCustomerNotExists`/`CardNotExists`/`CustomerPendingAffiliateCustomerExistsWithAccess`/`CustomerExistsWithoutAccess`/`DeactivatedCard` | `CardNumber` given but doesn't resolve to a valid pending card (`ValidateCardNewMember`) |
| `SaveNewMember` | 400 | `InvalidProviderName` | `ProviderName` not `Facebook`/`Apple` on social signup |
| `SaveNewMember` | **200** (not counted in 400 rate) | body `Status`: `InvalidFormatPhone`/`PhoneTooLong`/`PhoneTooShort`/`InvalidPhone`/`PhoneFail`/`UidType`/`UidTypeFail`/`BadRequest`/`CountryCodeNotExists` | Phone-format/UidType/country checks return a plain `Response` object, not a thrown exception — never reaches the `Logger` filter, so HTTP stays 200 with a failure `Status` in the body. **Invisible to the status-code-based 400-rate metric used in this investigation.** |
| `RecoveryPassword` | 400 | `customerEmailNotCompatible` | `Email` doesn't match the one on file for that DNI — matches the `customerEmailNotCompatible` app-event in the 2026-08-19 export (648 occurrences) |
| `RecoveryPassword` | **200** (not counted in 400 rate) | body `Status`: `InvalidUserName` | DNI/`UidCode` not found — plain return, not an exception |
| `GetCustomerProfile` | 400 | `UserNotCustomer` | `uidCode`/`uidSerie` don't resolve to any customer |
| `GetCustomerStatus` | 400 | `BadRequest` | `uidCode`/`uidSerie`/`cardNumber` query params missing |
| `GetCustomerStatus` | 404 | `NotFound` ("Cliente no encontrado") | Customer not found by `uidCode`/`uidSerie` |
| `GetCustomerStatus` | 404 | `NotFound` ("El número de tarjeta no existe") | `cardNumber` not found |
| `GetCustomerStatus` | 400 | `BadRequest` ("La tarjeta no corresponde al socio indicado") | Card found but doesn't belong to that customer |

**Notable implication for the open root-cause question**: a meaningful share of `SaveNewMember`'s and `RecoveryPassword`'s soft-failure paths never produce a 400 at all (plain 200 + failure `Status` in body) — meaning the true failure rate on those flows, from the client's perspective, is higher than the 400-rate metric shows, just not visible via HTTP status code. Also, `Login`'s `UidSerie` regex (6–12 digits, no leading zero) is a plausible mechanical driver of a chunk of its `BadRequest` 400s if the app sends a malformed DNI — plausible, not confirmed without body sampling.

## Partial attribution via `svclog_input` `Action` field (2026-08-19 export)

**User correction, important caveat**: the `Action` field in `svclog_input` rows is a **regex extraction from raw svclog text**, not a general log of every business-rule/`st` code — it only surfaces whatever specific patterns the Graylog extractor was written to match. It is not a substitute for real response-body sampling.

Full `Action` breakdown, 2026-08-19 window (56,399 `svclog_input` rows): `LoginSuccess` 4,658, `InvalidPassword` 2,276, `customerEmailNotCompatible` 648, `PointsTransfer` 88, `Exception` 1.

Two of these happen to line up with codes identified in the source-code table above — `InvalidPassword` (plausibly `Login`'s auth-failure path) and `customerEmailNotCompatible` (`RecoveryPassword`'s email-mismatch `BusinessRulesException`, code `customerEmailNotCompatible`, confirmed exact string match against `BusinessRulesCode.cs`). Both are **sustained flat across the full window** (`InvalidPassword`: 64–166 per 5-min bucket, no spike concentration; `customerEmailNotCompatible`: 9–55 per bucket, front-loaded slightly higher in the first 15 min then flat) — consistent with the IIS-side finding that the 400 rate itself is steady, not spiky.

**Critically, none of `SaveNewMember`'s codes appear at all** (`CustomerMinor`, `InvalidDocumentFormat`, `PendingCustomerExists`, etc.) — `SaveNewMember` still has **zero** attribution visibility from any data pulled so far, whether that's because those failure modes didn't occur in this window or because the extractor simply doesn't capture them (not distinguishable from this data). `SaveNewMember` has the worst 400 rate of any endpoint in both occurrences (71.4%/66.5%) and remains the least understood.

**Still needed for full attribution**: real response-body sampling (the actual `st` field) across all three endpoints, not proxied through this extractor — not pulled in this ticket.

## NXLog config confirms the gap is structural, not just a query problem

User provided the actual NXLog config running on `SFCG-MOBI-01` (`ServiceName=SF-MOBILE`, `ServiceCardinality="01"` — MOBI-02 presumably runs an identical config with Cardinality `"02"`). Two inputs:

- **`iis_w3c_mobile`**: parses `D:\Log\inetpub\W3SVC*\u_extend*.log` via `w3c_parser_mobile` (`xm_csv`). `Fields` list is fixed: `date, time, s-sitename, s-computername, s-ip, cs-method, cs-uri-stem, cs-uri-query, s-port, cs-username, c-ip, cs-version, cs(User-Agent), cs-host, sc-status, sc-substatus, sc-bytes, cs-bytes, time-taken` — **no body field, structurally**. Standard W3C extended IIS logging has no capacity to log a response body; this isn't an NXLog omission, it's what IIS itself writes to the log file. Confirms the IIS side can never yield `st` sampling, full stop — not just "not captured by this pipeline," but "not capturable by this pipeline without changing what IIS logs."
- **`svclog_input`**: parses the app's own log, `D:\Log\SmartLoyalty.MobileAppService\csv\*SmartLoyalty.MobileAppService.csv` — a legacy XML-tag-per-line format (`<EndOn>`, `<Elapsed>`, `<UidSerie>`, `<Password>`, `<BusinessReport-{code}>`, `<Args><Id>...`, literal `--Exception--` marker). Five regex patterns extract `Action` = `LoginSuccess`, `InvalidPassword`, `Exception`, `customerEmailNotCompatible` (from a literal `<BusinessReport-customerEmailNotCompatible>` tag), `PointsTransfer`.

**Critical mechanism**: the `<BusinessReport-customerEmailNotCompatible>` tag strongly implies the app writes a `<BusinessReport-{code}>` tag for business-rule failures generally — i.e. the raw log almost certainly already contains `<BusinessReport-CustomerMinor>`, `<BusinessReport-InvalidDocumentFormat>`, etc. for every other code in `BusinessRulesCode.cs`. But NXLog only has a regex for that one literal tag name — no generic `<BusinessReport-(.+)>` capture exists.

Worse: `to_json()` (from `xm_json`) serializes only the fields this `Exec` block explicitly set, and **overwrites `$raw_event`** with that serialization — the original XML-tag line is discarded for any row that doesn't match one of the 5 regexes. Evidence from the 2026-08-19 data: 56,399 total `svclog_input` rows, only 7,671 carry an `Action` (`LoginSuccess` 4,658 + `InvalidPassword` 2,276 + `customerEmailNotCompatible` 648 + `PointsTransfer` 88 + `Exception` 1). **The other 48,728 rows reach Graylog with no extracted content at all** — just `ServiceName`/`ServiceCardinality`/`ServiceType`/`EventReceivedTime`, the original line's content gone.

**Conclusion**: `SaveNewMember`'s root cause is not a "query it differently" problem — the data was discarded at the NXLog collection step, before transmission to Graylog, and does not exist anywhere in the Graylog-side data regardless of what query is run. The only remaining source is the raw file itself, directly on the server: `D:\Log\SmartLoyalty.MobileAppService\csv\*SmartLoyalty.MobileAppService.csv` on `SFCG-MOBI-01`/`02`. Not yet pulled — pending user access/confirmation.

**Longer-term fix (proposed, out of scope to execute here)**: broaden the NXLog regex to a generic `<BusinessReport-([A-Za-z]+)>` capture so all business-rule codes reach Graylog going forward, not just `customerEmailNotCompatible`. This is a state-changing config edit on a production log-shipping agent — would need the destructive-command banner and explicit user sign-off if ever turned into an actual command, not something to draft casually.

## App-side tracing config (`SystemDiagnostics.config`, `SFCG-MOBI-01`) — confirms the source data exists and is complete

`.NET System.Diagnostics` trace source `SmartLoyalty.MobileAppService`, `switchType="SourceSwitch"`, **`value="All"`** — every trace level (Verbose/Information/Warning/Error/Critical) is captured at the app layer, nothing filtered before it reaches the listeners. Two listeners, both fed the same trace stream:

1. **`delimitedListener`** (`DelimitedListTraceListener`, delimiter `,`) → `D:\Log\SmartLoyalty.MobileAppService\csv\SmartLoyalty.MobileAppService.csv`, 10MB rotation. This is the exact file NXLog's `svclog_input` reads — comma-delimited lines with embedded XML-tag fragments as the message payload, which is why the NXLog config needs regexes to pull fields back out.
2. **`XmlListener`** (custom `SegmentedXmlTraceListener`, `SmartFran.Seed.Logging.TraceSource`) → `D:\Log\SmartLoyalty.MobileAppService\SmartLoyalty.MobileAppService.svclog`, 10MB rotation. Standard .NET trace XML format (`E2ETraceEvent`-style), **never read by NXLog at all** — a second, more structured copy of the exact same trace stream, untouched by the Graylog pipeline's narrow regex limitations.

**This resolves the "is the data even there" question**: yes, confirmed — `SourceSwitch=All` means `SaveNewMember`'s `<BusinessReport-CustomerMinor>`/`<BusinessReport-InvalidDocumentFormat>`/etc. traces (and everything else) are being written to disk on `SFCG-MOBI-01`/`02` right now, in both files. The gap is entirely in the NXLog→Graylog leg, not upstream of it.

**Recommended pull target**: the `.svclog` XML file, not the CSV — it's the same content, never mangled through NXLog's regex extraction, and is standard structured XML rather than comma-delimited-lines-with-embedded-XML. Not yet pulled — pending user access to the server.

**User correction**: the `.svclog` file is written as a stream of plain XML-fragment lines with **no enclosing root element** — not a single well-formed XML document. This is exactly why NXLog never ingests it at all (only the CSV): NXLog's free/Community edition can't serialize root-less multi-fragment XML into structured events — this is a hard product-tier limitation, not an oversight in the config. Confirms the "longer-term fix" action item below only applies to the CSV/regex path — the `.svclog` file can never become a Graylog-native structured source under Community edition, broadened regex or not.

This doesn't block a **manual** pull, though — the file can still be read directly (grep/regex over the raw fragment lines, or wrap the content in a synthetic root tag before parsing as XML) for ad-hoc analysis. It just can't be piped through NXLog into Graylog automatically. Manual pull of this file, filtered to the campaign windows, remains the recommended path for `SaveNewMember` attribution — not yet done, pending user access to the server.

## Confirmed `.svclog` record structure (real sample, `SFCG-MOBI-01`, 2026-08-20T05:00 UTC)

User provided one real, concrete `.svclog` excerpt (not from the campaign windows — a later timestamp, illustrative of format only). Confirms the earlier "user correction" empirically: a flat stream of `<E2ETraceEvent>` elements, no enclosing root, no newlines between them.

**Per-event shape**: `<System>` carries `EventID`, `Type`, `SubType Name="Start"/"Stop"/"Information"`, `Level`, `TimeCreated SystemTime=...`, `Source Name="SmartLoyalty.MobileAppService"`, `Correlation ActivityID` (always the empty-GUID in this sample — not used for cross-event correlation here), `Execution ProcessName="w3wp" ProcessID ThreadID`, `Computer`. `<ApplicationData>` holds the payload, HTML-entity-escaped:
- `Start` events: just the endpoint path (e.g. `/api/Account/RecoveryPassword`).
- `Information` events: a custom `<TraceSourceLogger><Data>...</Data></TraceSourceLogger>` fragment — e.g. `RecoverUserPassword` + `<UserName>`/`<UserEmail>`, or `GetCustomerStatus` + `<Endpoint>`/`<ClientIP>`/`<Method>`/`<Timestamp>`. Shape varies per call site, not standardized.
- `Stop` events: endpoint path + `<TraceSourceLogger><Data><Id><BeginOn><EndOn><Elapsed><ParentId/></Data><Args>...</Args></TraceSourceLogger>` — `Args` holds the method's actual parameters (e.g. `UidSerie`, `Email`).

**No `<BusinessReport-*>` tag appears anywhere in this sample.** Consistent with the theory, not yet a confirmation: this excerpt traces 4 back-to-back `RecoveryPassword` calls (same `w3wp` process, threads 7/8/10/11/12, `UidSerie=47642502`) that all complete via a plain `Stop` with `Elapsed` and `Args` — no error branch. That's the shape of a **successful** call, where no `BusinessRulesException` is thrown, so no `<BusinessReport-{code}>` line is emitted — matching the CSV-side finding (`<BusinessReport-customerEmailNotCompatible>` only appears on the failure path). **Still needed**: one real failing-request sample from a campaign window to confirm the tag actually surfaces in `.svclog` the same way it does in the CSV. Not yet pulled.

**Side observation, not chased further**: 4 overlapping `RecoveryPassword` calls for the same `UidSerie`/email within ~1 second of each other, elapsed times 6396/1993/3884/6694ms — looks like client-side retries or a double-tap/resubmit pattern on that endpoint, not a single clean request. Worth keeping in mind if/when real campaign-window samples are pulled — elevated-latency `RecoveryPassword` calls in this shape could inflate both the req/s count and the *apparent* 400 rate if retries themselves are what's landing as duplicate 400s (e.g. a second attempt hitting `PendingCustomerExists`-style state left by the first). Speculative, not confirmed.

## Real `.svclog` pull received — mechanism confirmed, but wrong time window

User provided the actual file: `SmartLoyalty.MobileAppService.svclog` from `SFCG-MOBI-01`, 6.4MB (near the 10MB rotation cap). **Critical caveat**: its `TimeCreated` range is 2026-08-20T05:00:35Z–2026-08-20T12:33:29Z — this does **not** overlap either campaign window (2026-08-16 15:00–20:56 UTC, or 2026-08-20 00:00–01:00 UTC). At 10MB/rotation with no numbered/archived backups supplied alongside it, the file that covered the campaign windows has almost certainly already rolled over and is gone unless an older rotated copy still exists on the server or in a backup location — not yet confirmed either way. **This pull cannot be used to answer the campaign-window question**; treat everything below as mechanism validation only, not as campaign attribution.

**`<BusinessReport-*>` tags are confirmed present and fully endpoint-attributable in the raw `.svclog`** — the earlier hypothesis holds. Every `BusinessReport` event's message text is prefixed with a literal `[OP] {endpoint-path}: ` immediately before the `<TraceSourceLogger>` block, giving direct endpoint attribution without needing thread/correlation-ID reconstruction:

```
[OP] /api/Account/SaveNewMember: <TraceSourceLogger><Data><UidSerie>...</UidSerie><Email>...</Email><BusinessReport-CustomerExists>El socio ya se encuentra dado de alta en la base de datos.</BusinessReport-CustomerExists></Data></TraceSourceLogger>
```

**Codes found in this (non-campaign) window, by endpoint** (202 total business-rule-failure events, 05:00–12:33 UTC today):

| Endpoint | Code | Count |
|---|---|---|
| `Login` | `InvalidPassword` | 93 |
| `Login` | `InvalidUserName` | 41 |
| `RecoveryPassword` | `customerEmailNotCompatible` | 58 |
| `SaveNewMember` | `EmailAlreadyExist` | 4 |
| `SaveNewMember` | `CustomerExists` | 4 |
| `SaveNewMember` | `PendingCustomerExists` | 1 |
| `SaveNewMember` | `DocumentTooShort` | 1 |

**This directly resolves the open question from H11/action item 1**: `SaveNewMember`'s business-rule codes are not actually invisible — they were only invisible in the Graylog/NXLog `svclog_input` pipeline (regex-limited, see earlier section). The raw `.svclog` file has full attribution for every endpoint, including `SaveNewMember`, once the right file is pulled. `InvalidUserName` also appears here, interesting because source-code review classified it as a **plain-200 return** path (not a thrown exception) — confirms the `BusinessReport` trace is written independent of whether the call path ends in an HTTP 400 or a 200-with-failure-body, meaning `.svclog` sampling can resolve the "invisible 200 failures" gap flagged in the source-code section too, not just the 400-rate attribution.

**Extraction pattern for future pulls** (once the correct campaign-window file is obtained): `grep -oP '\[OP\] [^:]+: .{0,300}?BusinessReport-[A-Za-z]+&gt;'` isolates each failure event with its endpoint prefix intact; pair `\[OP\] \K[^:]+` with `BusinessReport-\K[A-Za-z]+` to tabulate endpoint × code counts. Confirmed working against this real file (accounts for the file being one giant line with HTML-entity-escaped inner XML, no true newlines).

**Still needed**: the actual `.svclog` (or an archived/rotated copy of it) covering 2026-08-16 15:00–20:56 UTC and/or 2026-08-20 00:00–01:00 UTC. Not yet obtained — need to ask whether rotated backups exist on the server, or whether a differently-scoped pull (e.g. from a log archive/backup job) can reach further back.

**Update: user confirmed no rotated copy exists.** Retroactive `SaveNewMember`/`Login`/`RecoveryPassword` attribution for the 2026-08-16 and 2026-08-19 occurrences via `.svclog` is a dead end — the data existed on disk at the time (per `SourceSwitch=All`) but rolled off before it could be pulled, and single-file rotation with no numbered backups means there's no other copy to check. Moving to "Dead ends" below.

**Forward-looking note**: the file filled ~6.4MB in ~7.5h (05:00–12:33 UTC) in this sample, ≈853KB/h — at 10MB rotation that's roughly a 11–12h retention window from empty. For any *future* occurrence, the `.svclog` needs to be pulled within that window (well under a day) to avoid the same loss. Worth adding to the action items as a standing operational note, not just this ticket's closure.

## Follow-up: 2026-08-28/29/30 weekend window

**Context**: User asked to add data from the weekend of 2026-08-28/29/30 to this investigation. No specific hours given — queried full calendar days in UTC-3, converted to GMT (UTC-3 + 3h): **2026-08-28 03:00 – 2026-08-31 03:00 UTC**. Continuing under this ticket/event folder per established pattern for GITIN-1866's recurring "campaign/traffic impact on DB" scope.

**Q10 result (data availability)**: full coverage, 864 snapshots at 5-min cadence, 2026-08-28 03:01:00.783–2026-08-31 02:56:00.540 UTC (72h × 12/hr = 864 exact — no gaps).

**Q11 result (blocking check) — materially different from both prior occurrences**: **488 rows with `blocked <> 0`**, vs. **zero** blocking rows in both the 2026-08-16 campaign window and the 2026-08-19 spike window. This is the first confirmed blocking activity found in this investigation.

Pattern observed in the raw dump (not yet run through Q13/Q14 aggregation, so treat the following as a working read, not final):
- Blocking recurs in three separate **early-morning windows**, one per day, each ~45–60 min long: 2026-08-28 ~06:46–07:26 UTC, 2026-08-29 ~07:31–08:01 UTC, 2026-08-30 ~07:06–07:46 UTC. All fall around UTC-3 03:45–05:00 — outside typical user-traffic hours, consistent with a scheduled batch/sync window rather than campaign or organic traffic.
- The large majority of blocked rows wait on `LCK_M_SCH_S` (schema-stability lock) against `TAB: 5:1445580188:*` (partitions 0–15 of the same table) — identified via the blocked queries' text as **`Sml.CustomerPointsLog`** in `SmartFran.Solution.SmartLoyalty` (production DB, not `PNSSRL`).
- Blocked sessions are mostly `SFCG-MOBI-01`'s EF query (`SELECT ... FROM [Sml].[CustomerPointsLog] WHERE CustomerId = @EntityKeyValue1`) and `sfzabbix`'s index-fragmentation healthcheck query.
- One distinct secondary blocking event (2026-08-28 07:56:00.150 UTC) is on a **different** table, `TAB: 5:859918185:1` (`SmlSupp.PromotionBranchOffice`) — `SFCG-TO-01` running `Query076-sql.xml`, a DELETE+INSERT rebuild of that table, invoked from `SmartLoyalty.TaskOperatorService`.
- The blocking chain is **cascading** across snapshots (spid A blocked by B, B itself blocked by C in an adjacent snapshot) — the true root/head blocker per window is **not yet confirmed** from eyeballing the raw dump; Q13 (root-blocker identification) and Q14 (per-snapshot severity) queries were issued to resolve this properly, not yet run.

**Q12 result (hostname CPU breakdown, full weekend window)** — also a sharp departure from both prior occurrences:

| Host / program | Snapshot rows | Total CPU delta (ms) |
|---|---|---|
| `SFCG-TO-01` (.Net SqlClient Data Provider) | 1,394 | **44,634,597** — dominant, ~23x the next highest |
| `SFCG-DB01` SQLAgent Job `0x9B0BD93393BA1846BE961FADF915AE66` | 70 | 7,872,716 (~112,467ms/row — very high per-active-row cost despite few rows) |
| `SFCG-WSV2-01` | 4,082 | 1,986,025 |
| `SFCG-WSIT-01` | 160 | 999,435 |
| `SFCG-WSV2-02` | 2,055 | 981,158 |
| `SFCG-WEBS-02` | 5,706 | 826,089 |
| `SFCG-WEBS-03` | 2,396 | 822,191 |
| `SFCG-WEBS-01` | 11,877 | 561,426 |
| `SFCG-DB01` SQLAgent Job `0xAC5A646AF3CD2C41939160A1FBC86300` | 268 | 486,345 |
| `SFCG-CLUB-01` | 3,966 | 179,316 |
| `SFCG-MOBI-02` | 7,416 | 107,231 |
| `SFCG-MOBI-01` | 4,561 | **20,445** |
| (remaining hosts, `sfzabbix`, SQLAgent internals) | — | all ≤33,000, negligible |

`SFCG-TO-01` (TaskOperatorService) at 44.6M ms is ~2,180x `SFCG-MOBI-01`'s 20,445ms — a total reversal from the 2026-08-16 and 2026-08-19 occurrences, where `SFCG-WSV2-01` was the dominant baseline consumer (~307K ms/5h window and ~63K ms/hour respectively) and MobileAppService was always negligible relative to a *comparably-sized* dominant host, not a 2,000x gap.

**Correction (superseded by Q13 below)**: this section originally attributed the blocking chain to `SFCG-TO-01`'s workload. Q13's head-blocker identification shows that read was wrong — the actual root blocker is a separate `SFCG-DB01` maintenance job (see below). `SFCG-TO-01`'s CPU dominance is a distinct, still-unexplained finding, not yet tied to the blocking mechanism.

## Root blocker confirmed (Q13/Q14)

**Q13 result — root cause identified, not just correlated.** In all 26 blocking snapshots across all three days, the head blocker (the spid with `blocked=0` that every other blocked row ultimately queues behind) is the **same SQL Agent job**, `0x9B0BD93393BA1846BE961FADF915AE66`, running on `SFCG-DB01`:

- `ALTER INDEX [IX_CustomerId] ON [SmartFran.Solution.SmartLoyalty].[Sml].[CustomerPointsLog] REBUILD;` — head blocker in 25 of 26 snapshots (all of 2026-08-28 06:46–07:26, all of 2026-08-29 07:31–08:01, all of 2026-08-30 07:06–07:46 UTC).
- `ALTER INDEX [IX_PromotionBranchOffice_1] ON [SmartFran.Solution.SmartLoyalty].[SmlSupp].[PromotionBranchOffice] REBUILD;` — head blocker for the single isolated 2026-08-28 07:56:00.150 UTC event (this corrects the earlier read that attributed that event to `SFCG-TO-01`'s `Query076-sql.xml` DELETE+INSERT — that query appeared in the raw Q11 dump but was not the head blocker; the actual blocker was this second `ALTER INDEX REBUILD`, same job).

The job's own wait type alternates `MEMORY_ALLOCATION_EXT` / `SOS_SCHEDULER_YIELD` (status `runnable` both times — actively executing, not itself blocked) — consistent with a resource-intensive index rebuild rather than an idle/stuck session. This fully explains the `LCK_M_SCH_S` (schema-stability) wait type seen on nearly every blocked row in Q11: sessions requesting a schema-stability lock on `Sml.CustomerPointsLog`/`SmlSupp.PromotionBranchOffice` queue behind the schema-modification lock this `ALTER INDEX REBUILD` holds for its duration.

**Q14 result — severity per snapshot.** Blocking scales up and down within each ~40–70 min window rather than staying flat:

| Day | Peak snapshot (UTC) | Peak blocked sessions | Peak distinct blocker-chain links |
|---|---|---|---|
| 2026-08-28 | 07:21:00 | **38** | 16 |
| 2026-08-29 | 07:56:00 | **33** | 13 |
| 2026-08-30 | 07:06:00 (start) / 07:31:00 (mid) | 26 | 12 |

The isolated `PromotionBranchOffice` event (2026-08-28 07:56:00.150) was minimal — 1 blocked row, 1 blocker.

## Job identity and schedule confirmed (Q15/Q16/Q17)

Job GUID `0x9B0BD93393BA1846BE961FADF915AE66` = **`PNSSRL_MantenimientoIndices`**, `enabled=1`, matching the reference script already tracked at `queries/PNSSRL_MantenimientoIndices.sql` in this repo (not the `_Lunes`/`_Miercoles` day-specific variants — this is the general one).

**Schedule (Q16)**: `freq_type=4` (daily), `freq_interval=1`, `active_start_time=061500` (06:15:00 UTC = 03:15 UTC-3), `active_end_time=235959` (effectively unbounded). **This is a standing daily job, not weekend-specific or new** — confirms the earlier open question: the two prior occurrences in this investigation (2026-08-16 campaign window 15:00–20:56 UTC, 2026-08-19/20 spike window 00:00–01:00 UTC) simply never overlapped this job's ~06:15+ UTC run window. This blocking pattern is very likely present every day, not something introduced this weekend — the weekend timing is coincidental to when this investigation happened to check.

**Steps (Q15)**: Step 1 — `EXEC PNSSRL_MantenimientoModulos` (generates the per-table `ALTER INDEX REBUILD` statements dynamically, including the ones observed in Q13 — the rebuild commands aren't in the job step text directly). Step 2 — conditionally kicks off `Operaciones_MaintenancePlan_Backups.Backup_Log` if it isn't already running/retrying (tangential, not chased further here). Step 3 — retention cleanup on `PNSSRL_DetallesEjecucionTablasModulos` (internal monitoring housekeeping, unrelated to the blocking).

**Run history (Q17, last 10 rows, most recent first)** confirms daily execution with **highly variable duration**:

| Date (UTC) | Start | Step 1 duration | Outcome |
|---|---|---|---|
| 2026-09-01 | 06:15:00 | 01:52:55 | Succeeded |
| 2026-08-31 | 06:15:00 | **06:14:11** | Succeeded |
| 2026-08-30 | (Step1 not in this 10-row sample; Step2/3 fired at 08:16:17) | — | Succeeded |

Not directly confirmed from this 10-row sample whether it ran on 2026-08-28/08-29 specifically (history not pulled that far back), but the daily schedule makes it near-certain it did — consistent with the head-blocker match on all three days in Q13.

**Duration variability explains the differing blocking-window start offsets per day** (06:46 on 08-28, 07:31 on 08-29, 07:06 on 08-30, all after the fixed 06:15 start): `PNSSRL_MantenimientoModulos` iterates tables sequentially, so `CustomerPointsLog`'s turn — and the resulting blocking — lands at a different elapsed offset depending on how long earlier tables in the same run took. The 2026-08-31 run taking 6h14m (vs. 1h53m the next day) is itself a standalone flag — a job blocking production queries for over 6 hours on at least one occasion is worth surfacing as an operational concern, independent of this ticket's original scope.

**Still open**: relationship (if any) between this confirmed index-rebuild blocking and `SFCG-TO-01`'s CPU dominance (44.6M ms, Q12) — possibly `SFCG-TO-01`'s `CustomerPointsLog` sync queries piling up/retrying while blocked behind the same rebuild, but not confirmed. Also not confirmed: whether the rebuild runs `ONLINE=OFF` (Standard Edition per `loyalty/CLAUDE.md`'s server description, and the plain `ALTER INDEX ... REBUILD;` syntax without an explicit `ONLINE=ON` option is consistent with an offline rebuild, but not directly verified from the full command text captured).

## Split off — GITIN-1981

The `PNSSRL_MantenimientoIndices` root-cause finding above (job identity, schedule, blocking severity, duration variability) has been split off into its own ticket, **[GITIN-1981](https://smartit-ar.atlassian.net/browse/GITIN-1981)** — "[SML] Revision de PNSSRL_MantenimientoIndices" — since it's a standing daily maintenance-job concern independent of any campaign, not something that belongs folded into a "campaign impact" ticket's conclusion. New event folder: `loyalty/events/20260901_pnssrl_mantenimientoindices_review/`. Further investigation of the job itself (duration variability, `ONLINE`/`OFFLINE` rebuild option, fix options) continues there, not here. The `SFCG-TO-01` CPU-dominance open question also moves with it.

**Related ticket, for further analysis — GITIN-1965 / GITIN-1969**: per user, GITIN-1866 is related to GITIN-1965 (parent ticket for fleet-wide Req/s alerting work). Its child `GITIN-1969` (`operations/events/20260829_mobile_alerts_coverage_analysis/`) independently confirms elevated MobileAppService traffic for the **same weekend, 2026-08-29/30**: service-total (Mobi01+Mobi02) req/s baseline avg=4.60 → weekend actual=6.15 (+34%), Mobi02 alone +89% vs. the most recent prior weekend, concentrated in a Saturday 16:00–17:00 local peak.

**Now further disconfirmed as causally related, given the Q13 root-cause finding**: the blocking chain's confirmed cause (a scheduled `ALTER INDEX REBUILD` job on `SFCG-DB01`, recurring in an early-morning window ~03:45–05:00 UTC-3) is a maintenance-schedule mechanism, independent of application traffic volume — it would fire on this schedule regardless of whether MobileAppService traffic was elevated that weekend. GITIN-1969's Saturday-afternoon traffic peak and this early-morning blocking window remain same-weekend but mechanistically unrelated as far as the data shows. Keeping the cross-reference for the record, but this looks like a coincidence of timing, not a shared cause.
