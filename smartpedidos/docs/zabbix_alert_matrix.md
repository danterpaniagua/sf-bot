# Zabbix alert matrix — SmartPedidos (AWS ECS hosts)

Destination = enabled trigger actions whose conditions the trigger's tags satisfy, computed from the live `action.get` of 2026-10-18 (`GITIN-2250`) by `alert_matrix.py`; `Chat` = action 7 (Operaciones Chat), `Chat+TG` = action 12 (`env = PROD`, named "Chat + Telegram"; one recipient with enabled Chat and Telegram media; at least 250 alerts per media type were sent without error in the 7 days to 2026-10-18), `SP-Chat` = action 11, `none` = no enabled action matches. Counts by keyword in trigger names (approximate). Snapshot, not a live view; re-run with the skill `alert-normalizer`.

**Scope.** The Zabbix host for the SmartPedidos production ECS cluster, `smartfran-pedidos-production`. `smartfran-pedidos-common` and `smartfran-pedidos-dev` are left out for now (user decision 2026-10-18). These hosts use the AWS ECS templates, so there is no per-filesystem disk or IIS monitoring here; the CPU/RAM/disk tier standard defined for loyalty (`loyalty/docs/zabbix_alert_matrix.md`) was **not** applied to them.

## Delivery per host (number of triggers by destination)

| Host | CPU | RAM | Disk | IIS | Other |
|---|---|---|---|---|---|
| smartfran-pedidos-production | 3 none | 3 none | - | - | 2 SP-Chat+Chat+TG, 6 none |

## Observations (2026-10-18)

| Item | Detail |
|---|---|
| ECS CPU / memory triggers | Cluster- and service-level "High CPU / memory utilization" triggers (priority 2) carry only `scope:capacity` and `scope:performance`: they route nowhere |
| What is routed | Two production "Running tasks ..." triggers (platform and concentrador services) carry `action:GCHAT`, `scope:SP`, `scope:OPE`, `env:PROD`: they match action 11 and action 12 |
| Not covered | No tiered CPU/RAM alerts, no disk alert, no routing for the target-tracking alarm triggers |
