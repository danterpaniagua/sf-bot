# Zabbix alert matrix — Operations (prod business hosts)

Destination = enabled trigger actions whose conditions the trigger's tags satisfy, computed from the live `action.get` of 2026-10-18 (`GITIN-2250`) by `alert_matrix.py`; `Chat` = action 7 (Operaciones Chat), `Chat+TG` = action 12 (`env = PROD`, named "Chat + Telegram"; one recipient with enabled Chat and Telegram media; at least 250 alerts per media type were sent without error in the 7 days to 2026-10-18), `SP-Chat` = action 11, `none` = no enabled action matches. Counts by keyword in trigger names (approximate). Snapshot, not a live view; re-run with the skill `alert-normalizer`.

**Scope.** `SF-FACT-PY01`, a prod business machine (user-stated 2026-10-18; it runs Docker containers `facturasend`, `keycloak`, `pgfacturasend`). `Zabbix server` (the monitoring server itself, 142 triggers) is a tooling host (user, 2026-10-18) and is not in this table. The tier standard from `loyalty/docs/zabbix_alert_matrix.md` was **not** applied to this host.

## Delivery per host (number of triggers by destination)

| Host | CPU | RAM | Disk | IIS | Other |
|---|---|---|---|---|---|
| SF-FACT-PY01 | - | - | 4 none | - | 12 none |

## Triggers monitored on SF-FACT-PY01 (16)

| Trigger | Priority | Destination |
|---|---|---|
| Docker: Failed to fetch info data | 2 | none |
| Docker: Service is down | 3 | none |
| Docker: Version has changed | 1 | none |
| sda: Disk read/write request responses are too high | 2 | none |
| sdb: Disk read/write request responses are too high | 2 | none |
| sdc: Disk read/write request responses are too high | 2 | none |
| sdd: Disk read/write request responses are too high | 2 | none |
| Container /facturasend: An error has occurred in the container | 2 | none |
| Container /keycloak: An error has occurred in the container | 2 | none |
| Container /pgfacturasend: An error has occurred in the container | 2 | none |
| Container /facturasend: Container has been stopped with error code | 3 | none |
| Container /keycloak: Container has been stopped with error code | 3 | none |
| Container /pgfacturasend: Container has been stopped with error code | 3 | none |
| Container /facturasend: Health state container is unhealthy | 4 | none |
| Container /keycloak: Health state container is unhealthy | 4 | none |
| Container /pgfacturasend: Health state container is unhealthy | 4 | none |

## Observations (2026-10-18)

| Item | Detail |
|---|---|
| Routing | None of the 16 triggers matches an enabled action: container-unhealthy (priority 4), container-stopped (3) and Docker-service-down (3) alerts reach no one |
| Coverage | Among the 16 monitored triggers none is a CPU, memory or filesystem free-space trigger; only disk read/write latency (4 disks). Whether such templates exist but are not linked was not checked |
