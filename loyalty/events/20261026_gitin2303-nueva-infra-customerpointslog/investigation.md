# Investigation — 20261026_gitin2303-nueva-infra-customerpointslog

**Status:** in progress (just opened, no design or data yet)

Jira: [GITIN-2303](https://smartit-ar.atlassian.net/browse/GITIN-2303) "[SML] Nueva infra para minimizar el impacto en CustomerPointsLog".

## Confirmed facts
- Scope as described by the user on 2026-10-26: an infrastructure improvement, a proxy between the SmartLoyalty services and the database. The design (what kind of proxy, where it sits, what it does) has not been given or decided.
- No earlier event mentions a database proxy for SmartLoyalty. Search on 2026-10-26 across `loyalty/events/*gitin2250*`, the other GITIN-22xx loyalty events and `loyalty/docs/`: the word "proxy" in `20261018_gitin2250-webservice-high-cpu/investigation.md` always means the Zabbix proxy (id 10609, host `sfcg-monitoreo`), not a database proxy. That file does not mention `CustomerPointsLog`.
- `loyalty/events/20261018_gitin2251-webs-db-misma-ventana/` (`investigation.md`, `ops.md`) is the event that studied `CustomerPointsLog` in the 2250 window; searched for proxy, pooler, pool, infra: no mention of a database proxy or a new infrastructure layer.
- No file in the repo references GITIN-2303.
- Context recorded in `loyalty/CLAUDE.md` from GITIN-2251, not re-verified here: `Sml.CustomerPointsLog` has about 404 million rows in 16 yearly partitions; each insert fires `[Sml].[CustomerPointsLogAfterInsert]`, which sums the customer's history and MERGEs it into `SmlSt.CustomerPointsLog`; at peak about 500-700 rows and 240-300 customers are inserted per minute.

## Earlier events that touch `CustomerPointsLog` (local folders, exist on disk; contents not read for this note)
- `loyalty/events/20260723_bloqueo_customerpointslog_loadtest/`
- `loyalty/events/20260925_etl-customerpointslog-sargable-rewrite/`
- `loyalty/events/20260715_cpu_spikes/`
- `loyalty/events/20260803_cpu_peaks_loadtest/`
- `loyalty/events/20260915_mobileappservice_loadtest_errors/`
- `loyalty/events/20260816_club_grido_campaign_query_health/`

## Open questions / next steps
- Design of the proxy: type, placement, which services and which database it sits between, and what impact on `CustomerPointsLog` it is meant to reduce.
- Read the earlier events above to get the evidence on the `CustomerPointsLog` impact before writing the design.
- Whether GITIN-2250 or its child tickets discussed this outside the files in the repo (the user remembered it; not found on disk).
