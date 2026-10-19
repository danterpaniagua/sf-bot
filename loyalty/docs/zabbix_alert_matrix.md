# Zabbix alert matrix — loyalty (prod SFCG hosts)

Compliance of the alerts on the 14 prod SFCG loyalty hosts against the alert standard, and where each alert is delivered. Read from the live Zabbix 6.0.32 instance on 2026-10-18 (`GITIN-2250`); destination = the enabled trigger actions whose conditions the trigger's tags satisfy, computed by `alert_matrix.py` from `action.get`. Re-run the audit with the skill `alert-normalizer`; this file is a snapshot, not a live view.

**Scope.** Prod hosts: CLUB-01/02, JENKINS-01, MOBI-01/02, SMTP-01, TO-01, WEBS-01/02/03, WSCG-01, WSIT-01, WSV2-01/02. Out of scope (user, 2026-10-18): `sfcg-monitoreo` and `sfcg-sonarqube` (tooling hosts, not prod); `SFCG-DB01`, `SFCG-DB01-CLON`, `SFCG-SMTP-02` (disabled, not used).

## Standard (thresholds are the user's decisions, not measurements)

| Metric | Tiers (priority) | Window | Recovery | Status |
|---|---|---|---|---|
| CPU utilization | Warning 70 (2) / Average 80 (3) / High 85 (4) | `avg` 10m | `max` 10m below 60 / 70 / 75 | Applied 2026-10-18, read back |
| RAM commit ratio (`% Committed Bytes In Use`) | Warning 70 / Average 75 / High 80 | `avg` 10m | `max` 15m below 60 | Applied 2026-10-18; items collecting on 6 of 14 hosts at 18:36, the rest pending |
| IIS request queue | Warning > 10 / Average > 50 / High > 200 | `min` 5m | see `docs/zabbix_observability.md` | Existing |
| Disk used / free space | stock: low 80 % and under 10 GB or fill < 1 day (2), critically low 90 % and under 5 GB or fill < 1 day (3); wanted: High tier and usage alert | `last` / 1h forecast | none | **Not routed**; decisions pending |
| IIS healthcheck | step `Healthcheck` in web scenario `[PROD] API POS / Gestion` | | | Step collecting; trigger pending |

Routing tags (all alerts that must reach Operations): `scope:GIT-SML-OPE`, `service_group:LOYALTY`, `action:GCHAT` plus a `SVC_FRIENDLYNAME` → action 7 (Operaciones Chat).

## Delivery per host (number of triggers by destination; `none` = no enabled action matches)

Keyword classification of trigger names is approximate (about 500 triggers fall in no category and are not shown). `Chat` = action 7 (Operaciones Chat); `Chat+TG` = action 12 (`env = PROD`, named "Chat + Telegram"; one recipient with enabled Chat and Telegram media; at least 250 alerts per media type were sent without error in the 7 days to 2026-10-18).

| Host | CPU | RAM | Disk | IIS |
|---|---|---|---|---|
| SFCG-CLUB-01 | 3 Chat, 4 none | 3 Chat, 3 none | 10 none | 3 Chat+TG, 8 none |
| SFCG-CLUB-02 | 3 Chat, 4 none | 3 Chat, 3 none | 10 none | 3 Chat+TG, 8 none |
| SFCG-JENKINS-01 | 3 Chat, 4 none | 3 Chat, 3 none | 10 none | - |
| SFCG-MOBI-01 | 3 Chat, 4 none | 3 Chat, 3 none | 10 none | 3 Chat, 5 Chat+Chat+TG, 7 none |
| SFCG-MOBI-02 | 3 Chat, 4 none | 3 Chat, 3 none | 10 none | 3 Chat, 5 Chat+Chat+TG, 1 Chat+TG, 7 none |
| SFCG-SMTP-01 | 3 Chat, 4 none | 3 Chat, 3 none | 10 none | - |
| SFCG-TO-01 | 3 Chat, 4 none | 3 Chat, 3 none | 15 none | - |
| SFCG-WEBS-01 | 3 Chat, 4 none | 3 Chat, 3 none | 10 none | 3 Chat, 6 Chat+TG, 8 none |
| SFCG-WEBS-02 | 3 Chat, 4 none | 3 Chat, 3 none | 10 none | 3 Chat, 6 Chat+TG, 7 none |
| SFCG-WEBS-03 | 3 Chat, 4 none | 3 Chat, 3 none | 10 none | 3 Chat, 6 Chat+TG, 7 none |
| SFCG-WSCG-01 | 3 Chat, 4 none | 3 Chat, 3 none | 15 none | 3 Chat, 3 Chat+TG, 7 none |
| SFCG-WSIT-01 | 3 Chat, 4 none | 3 Chat, 3 none | 10 Chat+TG | 7 Chat+TG, 1 none |
| SFCG-WSV2-01 | 3 Chat, 4 Chat+TG | 3 Chat, 3 none | 13 none | 3 Chat, 1 Chat+Chat+TG, 3 Chat+TG, 7 none |
| SFCG-WSV2-02 | 3 Chat, 4 none | 3 Chat, 3 none | 15 none | 3 Chat, 1 Chat+Chat+TG, 3 Chat+TG, 7 none |

## Gaps (2026-10-18)

| Gap | Detail |
|---|---|
| Disk alerts reach no one | Stock disk triggers carry only `scope:capacity`/`scope:performance`; routed only on `SFCG-WSIT-01` via `env:PROD` |
| Stock CPU/RAM triggers route nowhere | Four stock CPU and three stock memory triggers per host; the new tiers cover CPU and RAM; `SFCG-WSV2-01` stock CPU goes through action 12 |
| IIS partly unrouted | Request queue and MOBI spike go to Chat; legacy WSV1 triggers go through action 12; V1 web-scenario triggers 25746/25753 carry no tags |
| Telegram only for `env:PROD` triggers | Action 12 sends to Chat and Telegram (7-day history: sent, no errors); the new CPU/RAM tiers do not carry `env:PROD`, so they reach Chat only |
| Healthcheck step has no trigger | Collecting HTTP 200 in about 0.5 s at 18:34-18:36 |
