# Operations — TODO

Open work of this project. One entry per piece of work, each with the tickets it spans. When an item is done, record the resulting fact in the doc it belongs to (the runbooks, `../docs/zabbix_observability.md`, `zabbix_alert_matrix.md`) and delete the entry here. State below was read from the docs as last recorded, not re-measured. The loyalty SSL work (GITIN-1772, GITIN-1773) is tracked in `loyalty/docs/todo.md`; it uses `mobileappservice_ssl_renewal_runbook.md` from this project.

## 1. Zabbix alert normalization

Tickets: [GITIN-2250](https://smartit-ar.atlassian.net/browse/GITIN-2250), GITIN-2252, GITIN-2156 (state recorded 2026-10-02: MOBI tiers and routing applied; Caída brusca / WAF total-block, SSL tiers, SMTP and macro cleanup pending; not re-read since). Open items in `zabbix_alert_matrix.md` and `../docs/zabbix_observability.md`:
- Disk alerts reach no one on the loyalty hosts (stock triggers carry only `scope:capacity`/`scope:performance`; routed only on `SFCG-WSIT-01` through `env:PROD`); the High tier and usage alert are wanted, decisions pending.
- The RAM commit items collected on 6 of 14 hosts when last read (2026-10-18); the IIS Healthcheck step has no trigger yet.
- The new CPU/RAM tiers do not carry `env:PROD`, so they reach Chat only (no Telegram); duplicate Chat messages between actions 7 and 12 are untested.
- `SF-FACT-PY01` (prod, Docker `facturasend`, `keycloak`, `pgfacturasend`): none of its 16 triggers matches an enabled action (container-unhealthy, container-stopped and Docker-service-down reach no one) and it has no CPU, memory or filesystem free-space trigger (whether such templates exist unlinked was not checked); the loyalty tier standard was not applied to it.
- Zabbix API apply pattern: snapshot, guards and rollback; read triggers without `expandExpression`.

## 2. SSL-expiry alert reads `0`

Ticket: GITIN-2249 (`events/20261015_gitin2249-ssl-mobileappservice-falso-positivo/`). A `0` from `get_enddate.sh` is a failed read and keeps the High tier open until 30 days; left unchanged by decision, options listed in `../docs/zabbix_observability.md`. Also: the web scenarios have `verify_peer` and `verify_host` off, so a certificate problem never fails them (`../docs/zabbix_web_scenarios.md`).

## 3. SonarQube upgrade runbook

Ticket: GITIN-1327 (`events/20260905_sonarqube_upgrade/`). `sonarqube_upgrade_runbook.md` mixes the plan with what was executed (section 2 is the starting state; 6bis and 7bis record the executed chain and 26.9.0.129388 up): split or relabel. Housekeeping left after the upgrade is in 6bis. Decide whether `operations/CLAUDE.md` line 31 should stop describing the runbook as needing the 24.04 jump (section 5 discarded it); `CLAUDE.md` changes only on the user's request.

## 4. `itservices` password rotation

Ticket: from `events/20260723_itservices_bloqueo_password/` (no ticket recorded in the doc). Open (runbook section 6bis): no alert on `badPwdCount`, the initial server that locked the account was never identified, and AADDS was not rechecked after the rollout.

## 5. Certificate automation for the sites behind `WAF_APPs`

Tickets: GITIN-1770 (ClubSite AR), GITIN-1771 (WebSite), GITIN-1774 (MobileAppService). Open: the Paraguay backend certificate had no renewal and was due to expire 2026-09-15 (check it was handled); the AR listener-repoint commands were never captured in a script; `SFCG-MOBI-02` shuts down nightly and the `Start_Mobile02_11AM` Logic App starts it (the renewal task runs through `StartWhenAvailable`).

## 6. Graylog stack of SmartPedidos and SmartLoyalty (`sf-monitoreo`)

Tickets: GITIN-1827 (closed), GITIN-1854 (carried on). Events: `events/20260812_graylog_messages_not_arriving/`, `events/20260813_platform-service-branch-id-unknown-mapping-error/`; reference `../docs/graylog_infrastructure.md`. State as last recorded 2026-08-15 to 2026-09-18, re-read before acting:
- The `index.mapping.total_fields.limit` fix on the Default index set (and the SmartPedidos platform index) was drafted and not applied: the next write index can stick like `graylog_299`.
- Delete or strip the secrets of the stale `docker-compose.yml` next to the live `graylog-compose.yml`.
- Zero replicas on every index; a restart makes the whole single-node cluster unavailable and UDP messages sent then are lost silently.
- The pipeline rule that sanitizes `msg_rest_status` is not confirmed on live traffic (check the stream's own routing rules first); the Dev fixes in `log.js` of both services and the raw-payload email leak (`platform.js` 648/661) are in `smartpedidos/docs/todo.md`.
- Hostname question: `GITIN-2167` found `sfcloud-monitoreo` behind `sf-monitoreo.smartfran.com`; confirm which VM each name points to (`../docs/graylog_infrastructure.md`).

## 7. Grafana

Ticket: [GITIN-1174](https://smartit-ar.atlassian.net/browse/GITIN-1174) "Actualizacion Grafana 7.X" (`events/20261001_gitin1174-grafana-7x-update/`; reference `grafana.md`). State at the end of 2026-10-01: read-only inventory done, nothing changed, no upgrade plan, no `ops.md`. Scope stated by the user: update Grafana (7.3.7) to the latest version, add certificates, update the automation.
- Decide the target version (what "7.X" means) and whether Prometheus v2.24.1, Traefik v2.4 and the unpinned exporters are in scope.
- Certificates for `monitoreosp.smartfran.com`: Traefik's default certificate expired 2026-10-01 and the compose only has a router for the vendor name `monitoreo.ross.com.ar`, so Grafana is used over plain HTTP on 3000. Decide Traefik ACME, a corporate certificate, or termination in front of the VM.
- "Update automation": pinned versions plus a scheduled pull, CI/CD, IaC and a backup job (none exists: manual `tar` backups, no cron, EBS snapshots / AWS Backup not checked).
- Upgrade plan: backup of `./db` and the compose directory, rehearsal on a copy of the VM/volume, staged path; check each plugin (flowcharting 0.5.0, Athena 2.2.7, the unmaintained Atlas 1.0.0 that is the default datasource of 3 dashboards) and the 16 legacy alerts / 4 channels / 62 `graph` panels against the target release; Docker 20.10.3 may be too old.
- The user was to delete the temporary Admin API key `claude` (expires 2027-10-01) created for the inventory: not confirmed done.
- Security: the README documents the default `admin` / `admin` login (changed or not, unverified); Traefik's API on 8080 and the other ports are published on all interfaces (the AWS security group was not checked); Grafana and Prometheus run `privileged`.
- Not known: database engine (SQLite assumed), whether `monitoreo.ross.com.ar` and `monitoreosp.smartfran.com` are the same instance, who the four users are.

## 8. Settings

The `language` key of `.claude/settings.json` was set to `english` but its name was never verified: check with `/config` or the settings schema.

## 9. FEPE alerts

Event: `events/20260714_fepe_zabbix_healthcheck/` (no ticket recorded). `FEPE DOWN` fired for real on 2026-07-24 (Xacto Peru ports 8099 / 3636 time out). Open: which delivery path the FEPE alerts reach beyond Chat; the 8099 question (tracked in `cloud/docs/todo.md` item 6); the macros were created with initial values to retune after ~2 weeks of data (`../docs/zabbix_observability.md` → "FEPE healthcheck"); `FEPE ConsultaProd Latency` and its triggers were deferred.

## 10. Documentation leftovers

Not reviewed against events: the `job_description_*.md` (kept in Spanish by decision), `../docs/token_efficiency.md`, `../docs/zabbix_web_scenarios.md`, `../docs/tags.md`, `../docs/chat-status.md` (a snapshot).
