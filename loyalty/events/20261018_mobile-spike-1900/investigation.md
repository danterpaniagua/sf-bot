# Investigation: Mobile request spike around 19:05, no alert

**Status (2026-10-18 22:30):** converged on the alerting question (BURST changed 60 -> 45, widgets set to Max / 5m in the UI; unit `req/s` and titles still to change); the cause of the traffic itself is not investigated; reported in the GITIN-2252 summary (no Jira ticket for this event yet). Jira: not given yet (ask the user; rename the folder to `YYYYMMDD_gitinXXXX-description` when it exists). Times are UTC-3 unless marked UTC; Zabbix history prints in UTC (22:05 UTC = 19:05).

## Scope

User report on 2026-10-18: a spike on the Mobile hosts (`SFCG-MOBI-01/02`, hostids 10659/10660) around 19:00, no alert; later "a spike of 180 GET reqs vm 01+02, max()" and "the Zabbix widgets are wrong", read from widget "GET Requests / 10m" on dashboard 337 (`SmartLoyalty`).

## Established from data (data/zabbix-mobi-window-2040.txt, zabbix-mobi-spike-2042.txt, zabbix-dashboard337-2043.txt, zabbix-burst-macros-2045.txt)

- Traffic: only MOBI-02 rose. `IIS: Method Total requests per second` (item 52755) went from about 6-7 to a peak of **49.8 req/s at 19:05**; GET (item 52742) peaked at **40.1 req/s**; both back to baseline by about 19:18. MOBI-01 stayed at 0.3-0.4 req/s throughout (its traffic share is very small against MOBI-02 all day; why was not looked at). MOBI-02 CPU rose from about 22 % to 45.5 % at 19:05 and back by 19:18; MOBI-01 CPU about 4 %.
- No trigger changed state on either host in 18:30-19:45, no events, no alerts (`event.get` and `alert.get` returned nothing; no problem events for the spike triggers since 2026-10-16).
- Thresholds in force (global macros, no host or template override): spike triggers use `avg` of the rate: WARN 45 req/s over 10 m, AVG 75 over 5 m, HIGH 100 over 3 m (recovery below 40 over 20 m); BURST trigger (26909 MOBI-01, 26910 MOBI-02) fires on `last()` of Total requests/s ≥ 60. The 10-minute average around the peak was about 18-23 req/s, so none of the four was crossed. The triggers carry `env:PROD` and `action:TELE,GCHAT`, so routing was not the gap.
- The item key averages over 60 s (`perf_counter_en[..., 60]`, one sample per minute): a shorter burst above 60 req/s inside a minute averaging 49.8 cannot be excluded; no sub-minute data was read.
- The "180": widget "GET Requests / 10m" (svggraph, hosts Mobile 01 + Mobile 02, item `IIS: Method GET requests per second`, `ds.aggregate_function.0`=5, `ds.aggregate_interval.0`=10m, `ds.aggregate_grouping.0`=1, Y unit `reqs`). Reading `5` as Sum comes from the Zabbix 6.0 definitions and was not confirmed in the dashboard editor. Summing the stored one-minute GET samples 19:00-19:09 gives **182.5** (MOBI-02 179.6 + MOBI-01 2.9; 10 samples; next bucket 109.3). So the widget shows a sum of ten one-minute readings of a requests-per-second counter, not a request count (a peak minute at 20-40 req/s is on the order of 1,000-2,400 requests) and not a peak rate (40.1 req/s). Same configuration is in "Mobile POST Requests / 10m", "Mobile: POST + GET", "Webservice: POST + GET" and "WebserviceV2: POST + GET".

## 30-day trends for sizing (data/zabbix-mobi-trends-2051.txt; hourly trends of Total requests/s, UTC days; a first run with the wrong API method `trends.get` was overwritten by the corrected run in the same minute)

- MOBI-02: median of the hourly averages 3-10 req/s per day. Hours with an hourly max above N req/s over 30 days: >15: 57, >20: 41, >25: 31, >30: 26, >45: 18, >60: 15. Days with hourly maxima far above today's 49.8: 2026-09-22 199.3, 09-29 141.8, 10-08 144.2, 10-13 239.6 (trigger 26910 last changed 10-13 22:34 UTC). So a peak of 49.8 is not exceptional for MOBI-02; only 3 of the 18 hours above 45 fall under the current BURST value of 60 (this event is one of them).
- MOBI-01: median of hourly averages 0.3; hours above 15: 8, above 30: 4, above 45: 0. A lower BURST value adds nothing for MOBI-01 above 45.
- Hourly trends smooth short peaks, so hours-above counts understate one-minute peaks; consecutive hours may belong to one episode, so hours are an upper bound on episodes (not computed per episode).
- MOBI-02 has 473 hourly points in 30 days against 719 for MOBI-01; the missing hours were not looked at (item created later, collection gap, or other).
- Recovery of the BURST triggers is `max` over 5 m below `{$MOBILE_PCOUNT_SPIKE_OK:MOBI}` (40): a BURST value at or below 40 would sit under its own recovery level; not tested what Zabbix does then.

## Applied 20:54: BURST threshold 60 -> 45 (data/burst-macro-run-20261018-205448/, burst-macro-apply-stdout-2054.txt; scripts/zabbix-burst-macro-apply.sh and -rollback.sh)

- Global macro 128 `{$MOBILE_PCOUNT_BURST:MOBI}` was changed by the user from 60 to 45 (`usermacro.updateglobal`; the after-read returns value 45). It applies to burst triggers 26909 (MOBI-01) and 26910 (MOBI-02); recovery is unchanged (`max` over 5 m below 40). Chosen from the 30-day trends: 45 would have flagged 3 more hours than 60 on MOBI-02 (this event among them) and none on MOBI-01. Not checked: that the triggers re-evaluate with the new value, a later problem event, or delivery. A single minute sample of 49.8 would now satisfy the condition; the 1-minute averaging of the counter may still hide shorter peaks.
- Widgets: "GET Requests / 10m" and "Mobile POST Requests / 10m" were edited in the UI to Max / 5m before the script could run (guard refused at 20:50); unit still `reqs` and titles still "/ 10m" at that snapshot. The widget apply script was not applied.

## Not known

- Which clients or endpoints produced the traffic at 19:02-19:18 (no IIS log or Graylog read).
- Why MOBI-01 receives about 0.3 req/s against 5-8 on MOBI-02.
- Whether the user wants the widget changed (max for a peak rate, avg, or sum times 60 for a count).

## Scripts (in `scripts/`)

| # | Script | Purpose | Run |
|---|---|---|---|
| 1 | `zabbix-mobi-window-pull.sh` | Triggers, events, alerts and CPU history of MOBI-01/02 for the window | yes (20:40) |
| 2 | `zabbix-mobi-spike-pull.sh` | Spike triggers raw, macros, request-rate and GET history | yes (20:42) |
| 3 | `zabbix-dashboard337-pull.sh` | Raw widgets of dashboard 337 | yes (20:43) |
| 4 | `zabbix-burst-macros-pull.sh` | BURST macros and triggers 26909/26910 | yes (20:45) |
| 5 | `zabbix-mobi-widgets-pull.sh` | Wider widget dump for MOBI | written, not run (superseded by 3) |
