# Investigation: Guard-shift grouping ticket, 18-20 Sep (+ morning of 21)

**Jira:** [GITIN-2082](https://smartit-ar.atlassian.net/browse/GITIN-2082)

## Purpose

Not a technical investigation of its own — a grouping/index ticket ("[OPE] Guardia 18-9 -> 20-9") consolidating every real event worked during this on-call window, across SmartCloud and SmartLoyalty. Each row in `ops.md` links back to its own event folder and Jira ticket (where one exists) for full detail — this ticket doesn't duplicate that content, just indexes it.

## Source events (verified to exist on disk before listing in ops.md, per root CLAUDE.md)

- `cloud/events/20260918_sales-cosmos-403-firewall/` — no Jira ticket
- `cloud/events/20260918_sales-cpu-live-metrics-discrepancy/` — no dedicated Jira ticket (fed into GITIN-2073's scope, which was later found to need its own correction)
- `cloud/events/20260919_gitin2073-appserviceplan-insights-onboarding/` — GITIN-2073
- `cloud/events/20260919_grido-order-delay-peru-5396-5481/` — no Jira ticket yet
- `cloud/events/20260920_sales-oom-48h/` — GITIN-2075
- `loyalty/events/20260920_cpu-spikes/` — GITIN-2074 (+ subtasks GITIN-2077, GITIN-2078)
- `loyalty/events/20260921_customerpointslog-blocking/` — GITIN-2076 (morning of 21st, explicitly requested for inclusion — discovered while working GITIN-2074)

## Excluded

- `operations/events/20260919_search-knowledgebase/` — internal tooling/design proposal (a local search index over `investigation.md` files), not an incident or guard-triggered event. Left out; flag to user in case they want it included anyway.
