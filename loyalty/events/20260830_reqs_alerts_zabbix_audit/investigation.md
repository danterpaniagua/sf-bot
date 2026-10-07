# Investigation — 20260830_reqs_alerts_zabbix_audit

Jira: https://smartit-ar.atlassian.net/browse/GITIN-1966 (child of https://smartit-ar.atlassian.net/browse/GITIN-1965)

**Status:** in progress

## Scope

`GITIN-1965` (parent) split off from `GITIN-1961` (`SFCG-WSCG-01` Zabbix/Graylog onboarding) on 2026-08-30 — that ticket's Req/s alerting work (macro-context pattern, `WEBSCG01` fix) is now scoped into the `1965` line. `GITIN-1966` (child of `1965`) is the concrete work this event folder tracks: **check the efficiency of existing Zabbix Req/s alerts fleet-wide** — not just whether they exist, but whether their thresholds and coverage actually make sense.

## Confirmed facts (carried over from `GITIN-1961`)

- The `IIS by Zabbix agent active` template's per-app `GET`/`POST Requests/Sec` items are visibility-only fleet-wide — no host checked so far (`SFCG-WSCG-01`, `SFCG-WSV2-01`) has a trigger on them directly.
- The real, actionable alert is a **custom, non-template** 3-tier trigger (Warning/Average/High) on the generic `_Total` item — `IIS: Method Total requests per second` (key `perf_counter_en["\Web Service(_Total)\Total Method Requests/Sec", 60]`, native to the template, always present).
- Macro convention: `{$PERF_COUNT_TRIG_WARNING|AVERAGE|HIGH|OK|TIME_NOK:<CONTEXT>}` — global macros, per-service context suffix (e.g. `WEBSCG01`). Not defined anywhere by default (not global/host/template) — must be created explicitly per host.
- `SFCG-WSCG-01`: **fixed** 2026-08-28 — `WEBSCG01` context created (`WARNING:15, AVERAGE:30, HIGH:50, OK:<=10, TIME_NOK:5m`, VM-capacity-based), 3-tier trigger chain created (`26862`→`26863`→`26864`), verified `state:0`/`error:""`.
- `SFCG-WSV2-01`: reference triggers (`26139`/`26140`/`26141`) reference this same macro family but **no context/value was ever defined anywhere** for them — non-functional as of last check. Not yet fixed (was deliberately out of scope for `GITIN-1961`).
- Full pattern detail and the macro/API gotchas (`usermacro.create` vs `usermacro.createglobal`, `formulaid` only valid with `evaltype:"3"`) are documented in `../../docs/zabbix_observability.md` and `.claude/commands/ope-zabbix.md`.

## Current working theory (revised 2026-08-30)

The initial theory — every host has the same "zero triggers, undefined macros" gap `SFCG-WSCG-01` had — was **wrong** for most of the fleet. Full inventory (11 hosts with the `_Total` "Method Total requests per second" item, `fleet-total-requests-items.json`) shows every host except `SFCG-WSCG-01` already had a functional trigger set before this ticket. The real problem isn't absence — it's **drift**: four different, uncoordinated macro/trigger "generations" exist across the fleet, several sharing thresholds across hosts with different traffic profiles, one host (`SFCG-MOBI-01/02`) running three overlapping schemes simultaneously, and at least one clearly inverted threshold (`WEBS` context: `AVERAGE=11` < `WARNING=15`).

## Fleet inventory (2026-08-30)

| Host(s) | Trigger family | Context | Thresholds (Warn/Avg/High, req/s) | Status |
|---|---|---|---|---|
| `SFCG-WSV2-01`, `SFCG-WSV2-02` | `PERF_COUNT_TRIG_*` | none (base default) | 9/13/15, OK≤7, TIME_NOK=10m | Functional |
| `SFCG-CLUB-01`, `SFCG-CLUB-02` | `PERF_COUNT_TRIG_*` | `CLUBS` (shared pair) | 50/75/90, OK≤49 | Functional |
| `SFCG-WEBS-01/02/03`, `SFCG-WSIT-01` | `IIS_REQUESTS_WSV1_POST` (different macro family) | `WARN`/`AVG`/`HIGH` shared literally across all 4 hosts | 30/90/120, OK≤10 | Functional, but **identical thresholds for 4 different services** — no per-host tuning at all |
| `SFCG-WSCG-01` | `PERF_COUNT_TRIG_*` | `WEBSCG01` | 15/30/50, OK≤10, TIME_NOK=5m | Fixed this cycle (`GITIN-1961`) |
| `SFCG-MOBI-01` | 3 schemes at once (see below) | — | — | Functional but redundant/inconsistent |
| `SFCG-MOBI-02` | 3 schemes at once (see below) | — | — | Functional but redundant/inconsistent, plus extra nodata coverage `MOBI-01` lacks |

**`SFCG-MOBI-01`/`02` detail** — three overlapping schemes on the same `_Total` item:
1. Legacy `PERF_COUNT_TRIG_*` (plain/base defaults, same as `WSV2-01/02`) — functional, likely superseded.
2. `Caída brusca` (%-drop detection): `{$DROP.PCT:MOBI}=60`, `{$DROP.WINDOW:MOBI}=10m`, `{$DROP.MIN.ACTIVITY:MOBI}=1`, `{$DROP.MIN.DURATION:MOBI}=2m`, `{$DROP.OK.ACTIVITY:MOBI}=0`, `{$DROP.OK.ACTIVITY.TIME:MOBI}=20m` — shared `MOBI` context, functional.
3. `IIS Spike`: `{$MOBILE_PCOUNT_SPIKE_WARN/AVG/HIGH/OK:MOBI01}` vs `:MOBI02}` — per-host context, functional, but **`MOBI01` (1.5/2.5/4, OK=1) is ~13x lower than `MOBI02` (20/30/60, OK=15)** despite both being `MobileAppService` instances behind the same LB (`SFCG-MOBI-LB`) — not yet confirmed whether this reflects a real traffic asymmetry or copy-paste drift.

`MOBI-02` also has a dedicated "sin datos" trigger (`26748`) and `{$MOBILE_PCOUNT_NODATA_WINDOW:MOBI02}=11h`; `MOBI-01` has neither.

**Orphaned macros** (defined, no trigger currently references them among hosts checked): `{$PERF_COUNT_TRIG_*:WEBS}` (distinct from the `IIS_REQUESTS_WSV1_POST` family the WEBS/WSIT hosts actually use — and note `AVERAGE:WEBS=11` < `WARNING:WEBS=15`, inverted), `{$IIS_REQUESTS_WSV2_POST:OK}`, `{$IIS_REQUESTS_WSV3_POST}`. The `WSV1`/`WSV2`/`WSV3` naming in this macro family is unrelated to but easily confused with the real `SFCG-WSV2-01/02` hostnames.

## Ruled out

- ~~All PERF_COUNT_TRIG_* macros are undefined instance-wide~~ — wrong, see correction note in `loyalty/events/20260828_wscg01_zabbix_graylog_onboarding/investigation.md`. Base defaults exist and are functional.

## Open questions / next steps

- **Efficiency verdict, per the ticket's actual scope** — for each host/scheme above, is the threshold sane relative to real observed traffic? Only `WEBSCG01`'s thresholds were derived from a stated method (VM-capacity-based, per user); `CLUBS` and `WEBS`/`IIS_REQUESTS_WSV1_POST` still have unknown provenance — need either historical data pulls (`Monitoring → Latest data → Graph`, 30d min/avg/max, per the `ope-zabbix` skill's own guidance for latency thresholds) or the person who set them, to judge if they're still appropriate. `MOBI` SPIKE is now resolved, see below.
- ~~Confirm whether `MOBI-01` vs `MOBI-02`'s 13x threshold gap is intentional~~ — **RESOLVED (2026-08-31), cross-referenced from `operations/events/20260829_mobile_alerts_coverage_analysis/investigation.md` (GITIN-1965):** not drift. GITIN-1918's own investigation documents the thresholds were deliberately calibrated per-host from real traffic percentiles at the time (Mobi01 3m-avg p99=1.22 vs. Mobi02's p99=18.99). A fresh 3-weekend baseline pulled independently under GITIN-1965 reconfirms the same ~20-40x traffic gap a week later (Mobi01 combined mean 0.20-0.26 req/s vs. Mobi02's 5.34-10.23 req/s across 4 weekends) — the 13x threshold ratio is proportionate to real, current traffic, not copy-paste drift. No action needed on this specific pair.
- Confirm whether `MOBI-01`'s missing nodata trigger/macro is a real gap. Still open — not addressed by the threshold-gap finding above (that's a different kind of coverage gap: absence of a `nodata()` trigger, not a threshold-value question).
- Decide whether the legacy `PERF_COUNT_TRIG_*` scheme on `MOBI-01/02` should be disabled now that `IIS Spike` (scheme 3) appears to be the newer, per-host-tuned approach — running three schemes for one metric is itself an efficiency problem (alert noise / triage confusion), independent of any single threshold's correctness.
- Decide whether the `WEBS`/`IIS_REQUESTS_WSV1_POST` shared-across-4-hosts threshold set should be split per host, and whether the orphaned `:WEBS` context (with its inverted Average<Warning bug) should be deleted or was meant to replace `IIS_REQUESTS_WSV1_POST` and never got finished.
