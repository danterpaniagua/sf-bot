# Investigation — 20260824_mobile_iis_spike_detection

**Status:** converged — ready for ticket

## Confirmed facts

- Existing Zabbix triggers on `SFCG-MOBI-01` (Mobile 01) and `SFCG-MOBI-02` (Mobile 02) for IIS `\Web Service(_Total)\Total Method Requests/Sec` used only a 10-minute sustained average (`avg(10m)>={$PERF_COUNT_TRIG_WARNING|AVERAGE|HIGH}` = 9/13/15 req/s, recovery `avg(15m)<=7`), shared as global macros with no per-host context (triggerids 26133–26138) (C1, C4).
- 16 days of 1-minute history for Mobile 02 (itemid 52755, 13,004 samples) shows: p50=2.7, p90=7.4, p95=9.7, p99=19.4, p99.9=74.1, max=177.4 req/s (C7, local analysis).
- Rolling 3-minute average on the same data: p90=7.44, p95=9.77, p99=18.99, p99.5=22.16, p99.9=65.11, max=172.89.
- The existing 10-minute-average trigger does catch nearly all large single-minute spikes (only ~4% of minutes ≥20 req/s never cross `avg(10m)>=9`) because one very large sample can push a short window's average past threshold alone. The actual gap is **detection latency**: a fast-onset burst needs several sustained high minutes before the 10-minute rolling average crosses threshold, so paging lags minutes behind the burst's actual start (e.g. the 2026-08-13 08:57–09:07 episode, peak 177 req/s).
- Mobile 01 (itemid 52797, 20,146 samples, same 16-day window) has a much lower traffic profile: p50=0.07, p90=0.43, p99=1.30, max=25.19 req/s raw; 3m-avg p99=1.22, p99.9=2.92, max=10.19. Roughly 40x lower than Mobile 02 at equivalent percentiles.
- Sample coverage over the identical 14-day span: Mobile 01 = 99.9% (effectively 24/7), Mobile 02 = 64.5%. Mobile 02's gaps are bimodal: 3 short gaps (2–5 min, transient) and 14 large gaps clustered between 7.1h and 10.1h (426–604 min), consistent with a nightly power-off/power-on cycle.
- `loyalty/events/20260821_mobileappservice_loadtest_503/investigation.md` independently confirms Mobile 02 was powered off before a 12:06:37 start during that incident, with an open item (not resolved there) on whether its power cycle is manual or scheduled.
- `loyalty/docs/infrastructure.md` confirms both `SFCG-MOBI-01` and `SFCG-MOBI-02` sit behind the same Azure Standard Load Balancer (`SFCG-MOBI-LB`) and are both live in its backend pool (confirmed 2026-08-21, GITIN-1909) — the traffic disparity is a role/uptime difference, not a routing misconfiguration.
- VM size/SKU for either host is not recorded in `loyalty/docs/infrastructure.md` or the 20260821 investigation — "Mobile 01 is the bigger VM" is unconfirmed from documentation; only the 24/7-vs-intermittent uptime difference is independently verified from the Zabbix history data.
- Both hosts are linked only to vendor templates (`IIS by Zabbix agent active`, `Windows by Zabbix agent active`) — no shared custom template exists, so per-host trigger objects (not template-inherited ones) are the correct mechanism, matching the pattern the existing 26133–26138 triggers already use.
- The only enabled alert action matching this trigger family's tag set (`scope=OPE`, `service_group=LOYALTY`, `action=TELE,GCHAT,MAIL`, plus 7 other fixed tags) is actionid 10, "Google Chat Loyalty to OPE (EMAIL)" (C9). Actions 7/8/9 require `scope=GIT-SML` or `scope` containing `PL`, so they don't apply here.

## Current working theory

N/A — investigation converged, no open causal question. This was proactive monitoring improvement work, not incident root-causing.

## Ruled out

- Shortening the existing sustained-load trigger's window in place (editing 26136/26137/26138 directly) — would change already-tuned Warning/Average/High semantics for existing consumers of those triggers; rejected in favor of adding independent, non-disruptive Spike triggers.
- Sharing one global spike threshold across both Mobile hosts — Mobile 01's real traffic (p99=1.22 on 3m-avg) never approaches Mobile 02-calibrated thresholds (20/30/60); a shared value would leave Mobile 01 blind to its own spikes. Resolved with per-host macro context (`:MOBI01`/`:MOBI02`), same pattern as the existing Clubs `:CLUBS` context.

## Open questions / next steps

- Whether Mobile 02's power cycle is manual or scheduled/automated remains unconfirmed (also open in the 20260821 loadtest investigation) — the 11h `nodata` window was set empirically from the observed max gap (10.07h) plus margin, not from a known schedule. If a real schedule is later confirmed, the window should be revisited against it rather than the inferred value.
- VM SKU/size for MOBI-01 vs MOBI-02 not yet confirmed via `az vm show` — not required for this trigger work, but flagged as a documentation gap in `loyalty/docs/infrastructure.md`.
