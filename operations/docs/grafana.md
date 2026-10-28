# Grafana + Prometheus monitoring stack — reference

> Source: read-only inventory of the VM and its compose repository, 2026-10-01 (`operations/events/20261001_gitin1174-grafana-7x-update/`, GITIN-1174), plus the earlier GITIN-1748 event (`smartpedidos/events/20260803_grafana-cache-panel-fix/`). Facts marked *unverified* were not checked. No credentials are recorded here.

## 1. What it is

A Docker Compose stack that charts AWS CloudWatch metrics (cached in Prometheus) and HTTP health probes in Grafana. It was **handed over by a third party ("ROSS") in March 2025** (first commit "Primer commit como lo deja ROSS. Funcionando"), then extended and documented in September 2025. Used for operations dashboards such as the SQS queue panels and the MongoDB Atlas cache panel (GITIN-1748).

## 2. Where it runs

| Item | Value |
|---|---|
| Host | AWS EC2 instance `ip-172-31-42-88` (kernel `5.15.0-1084-aws`), user `ubuntu` |
| Compose directory | `/home/ubuntu/grafana-prometheus` (also a git repository, 3 commits, README in Spanish) |
| Docker | 20.10.3, classic `docker-compose` (no `docker compose` plugin) |
| Current hostname | `monitoreosp.smartfran.com` (user-stated). Earlier tooling called it as `http://monitoreosp.smartfran.com:3000/…` (plain HTTP to Grafana's port) |
| Vendor hostname in the compose | `monitoreo.ross.com.ar` (Traefik router host rule; Let's Encrypt via ACME http-challenge) |
| Disk | root volume 59 GB, 26 GB used (45 %) at 2026-10-01 |

No Traefik router or certificate for `monitoreosp.smartfran.com` is defined in the compose. Checks on 2026-10-01 (~14:23Z): the name resolves to `52.25.171.46`; `http://monitoreosp.smartfran.com:3000/api/health` answers `200 OK`; `https://monitoreosp.smartfran.com/` answers `404` from Traefik with its **self-signed default certificate (`TRAEFIK DEFAULT CERT`, notAfter 2026-10-01 00:39:45 GMT — already expired at the time of the check)**. So Grafana is used over plain HTTP on port 3000 and no valid certificate exists for the SmartFran name (GITIN-1174 scope: add certificates).

## 3. Components (containers up 11–12 months at 2026-10-01)

| Service | Image | Port | Notes |
|---|---|---|---|
| Grafana | `grafana/grafana:7.3.7` (pinned; `/api/health` → 7.3.7, commit `1e261642f4`) | 3000 | data in `./db` (193 MB), `privileged: true` |
| Prometheus | `prom/prometheus:v2.24.1` | 9090 | `./prometheus-data` (15 GB), retention 180 days, global `scrape_interval: 15s` |
| CloudWatch exporter | `prom/cloudwatch-exporter:latest` (image 2 years old) | 9106 | region `us-east-1`; config `cloudwatch-exporter/cloudwatch-exporter-config.yml` |
| Blackbox exporter | `prom/blackbox-exporter` (unpinned, image 5 years old) | 9115 | HTTP probes |
| Traefik | `traefik:v2.4` | 80, 443, 8080 | `--api.insecure=true` (dashboard/API on 8080), docker socket mounted read-only, ACME storage `./letsencrypt` (root-owned) |

All ports are published on all interfaces; whether the AWS security group restricts them was *not checked*.

## 4. Grafana plugins (on disk in `db/plugins`)

`mtanda-aws-athena-datasource` 2.2.7 · `grafana-mongodb-atlas-datasource` 1.0.0 (2019, unmaintained, built for Grafana 6.x; its install line is commented out in the compose but it is present on disk) · `grafana-simple-json-datasource` 1.4.2 · a flowcharting panel plugin (version not captured; compose installs 0.5.0). The compose allows unsigned plugins (`GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS`). Some plugin directories are literally named with quotes (artifact of the compose's `;"name"` install syntax).

## 4b. Live content (Grafana API inventory, 2026-10-01)

7 datasources: `SmartFran - MongoDB Atlas ` (the **default**, unsigned Atlas plugin), `AWS Athena datasource` (unsigned), four native CloudWatch datasources (`AZ_CloudWatch`, `CloudWatch`, `Inviertis - CloudWatch`, `SmartFran - CloudWatch`) and `Prometheus` (`http://prometheus:9090`). 37 plugins installed (33 core; non-core: Athena 2.2.7, flowcharting 0.5.0, Atlas 1.0.0 — unsigned; simple-json 1.4.2 — signed). One folder, `SmartFran_Metrics`, with **8 dashboards / 85 panels, all schemaVersion 26** (62 are the classic `graph` panel): AWS Details, BBOO Status, Mongo Details, Operaciones, Operaciones Firewall, OperacionesV2, SmartFran - General, SP-STG (most recently edited: Operaciones, 2026-08-30). **16 legacy dashboard alerts** (15 ok, 1 no_data) on AWS Details (8), Operaciones (7) and Mongo Details (1), and **4 notification channels** (Slack, Telegram, two email). 4 organisation users. The server-admin API endpoints (`/api/admin/stats`, `/api/orgs`) are not reachable with an API key. Per dashboard (panels; datasources; legacy alerts; last edited): AWS Details (25; Athena, `SmartFran - CloudWatch`; 8; 2025-09-22), BBOO Status (3; CloudWatch, Prometheus; 0; 2025-10-29), Mongo Details (9; MongoDB Atlas; 1; 2024-02-07), Operaciones (17, all `graph`; `SmartFran - CloudWatch`, MongoDB Atlas; 7; 2026-08-30), Operaciones Firewall (6; Prometheus; 0; 2025-10-29), OperacionesV2 (14; Prometheus, MongoDB Atlas; 0; 2025-11-10), SmartFran - General (2, one flowcharting panel; default datasource, Prometheus; 0; 2022-03-02), SP-STG (9; `SmartFran - CloudWatch`; 0; 2025-04-25). The Atlas plugin is therefore used by three dashboards and is the default datasource; Athena by one; flowcharting by one. Notification channels: `Inviertis Slack`, `SmartPedidos Telegram`, `Inviertis` and `Mensajesencolados` (email), none the default (settings not collected: they may hold secrets). Users: 1 Admin (seen under a minute before the read), 1 Editor (3 months), 2 Viewers (2 months, 1 year). The API inventory used a temporary Admin key (`claude`, expires 2027-10-01) that travelled in clear over HTTP and was to be deleted by the user (not confirmed done). Details: `operations/events/20261001_gitin1174-grafana-7x-update/data/gf_*_20261001.*`.

## 5. What is monitored

**Prometheus jobs (active):** `prometheus` (self), `cloudwatch` (scrape 1 m), `blackbox` (`http_2xx` module). Several other jobs are commented out (MongoDB Atlas, Google, API checks, "lachuca").

**CloudWatch exporter metrics:** SQS (`ApproximateAgeOfOldestMessage`, `ApproximateNumberOfMessagesVisible`, `NumberOfMessagesDeleted`, `NumberOfMessagesReceived`, `NumberOfMessagesSent`); ECS (`ECS/ContainerInsights RunningTaskCount`, `AWS/ECS CPUUtilization`, `MemoryUtilization`); WAFV2 (`AllowedRequests`); CloudFront (`Requests`, `4xxErrorRate`, `5xxErrorRate`, `CacheHitRate`); Application Load Balancer (`HTTPCode_ELB_4XX_Count`, `HTTPCode_ELB_5XX_Count`, `UnHealthyHostCount`, `ProcessedBytes`). The README states a 5-minute CloudWatch scrape; `prometheus.yml` uses 1 m for that job (not reconciled).

**Blackbox targets (as configured):** two `smartfran` pedidos API endpoints (`prodpedidos.smartfran.com` login and branches/news), a MongoDB Atlas shard host, two `inviertis.es` health checks, plus leftover sample targets (`prometheus.io`, `example.com:8080`, `sadfgaga.com`).

## 6. Operations (as documented in the stack's README — manual)

- **Backup:** manual `tar` of `db/`, `prometheus-data/`, `prometheus-configuration/`, `cloudwatch-exporter/` and `docker-compose.yml`. **No scheduled backup is visible on the VM** (`ubuntu` has no crontab; `/etc/cron.d` holds only system entries). EBS snapshots / AWS Backup were *not checked*.
- **Update:** `docker-compose down` → `docker-compose pull` → `docker-compose up -d`. With Grafana pinned to `7.3.7` this does not upgrade Grafana; the unpinned exporters would change.
- **Cleanup/log rotation step listed in the README:** `docker system prune -a --volumes` — destructive (removes all unused images and volumes); handle with care.
- **Certificates (Traefik):** inspect Traefik logs, keep `letsencrypt/acme.json` mode 600; the README's forced renewal deletes `acme.json` and restarts the proxy.
- **Grafana API:** reachable on port 3000; `/api/health` needs no authentication; other calls need an API key (earlier work used one over plain HTTP — see §7).

## 7. Known issues and risks

- **Grafana 7.3.7 (about 2020) is far behind the current release**; the Atlas datasource plugin is unmaintained and hides the real error returned by the Atlas API (GITIN-1748 root cause analysis). The "MongoDB: Cache" panel was fixed by changing the dimension name `CACHE_USAGE_USED` → `CACHE_USED_BYTES`; other panels on that datasource were not audited.
- **The README documents the default Grafana login `admin` / `admin`** with the note to change it at first login; whether it was changed is *unverified*.
- **The SmartFran hostname was used over plain HTTP:3000** in earlier work, which sends API keys in clear text if the URLs are accurate.
- Old and partly unpinned images (Prometheus v2.24.1, Traefik v2.4, `latest` exporters); Docker 20.10.3 on the host; Traefik's insecure API port 8080 is published; Grafana and Prometheus containers run `privileged`; a stale editor swap file (`.docker-compose.yml.swp`, 2025-03-20) remains in the compose directory.

## 8. Related tickets

- **GITIN-1174** "Actualizacion Grafana 7.X" — scope stated 2026-10-01: update Grafana to the latest version, add certificates, update the automation. State at the end of 2026-10-01: inventory done, nothing changed on the VM or in Grafana, no upgrade plan drafted, no `ops.md`. Open decisions: the target version (what "7.X" means), how to get a certificate for `monitoreosp.smartfran.com` (Traefik ACME, a corporate certificate, or termination in front of the VM) and what "update automation" covers (pinned versions plus a scheduled pull, CI/CD, IaC, a backup job). Planning considerations from general Grafana knowledge, **not verified for these versions**: 7.3.7 to the current release crosses many majors (8 onward); the database migrates forward on start and normally cannot be rolled back, so a backup of `./db` and of the compose directory is a precondition and a rehearsal on a copy of the VM/volume is the safe way to find breakage; usual breakage points are legacy dashboard alerts and notification channels (replaced by unified alerting), API keys (replaced by service accounts), AngularJS-based plugins and the classic `graph` panel (62 panels here; flowcharting 0.5.0, simple-json, the Atlas 1.0.0 and Athena 2.2.7 plugins were built for old Grafana) and the unsigned-plugin allow-list; the host's Docker 20.10.3 may be too old for current images (README prerequisites: Docker ≥ 20.10, Compose ≥ 1.29). Whether Prometheus v2.24.1, Traefik v2.4 and the unpinned exporters are in scope is undecided. The compose directory also holds `docker-compose.old` (2024), `dbdetail.json`/`test.json` (2021) and `.idea/`. Investigation: `operations/events/20261001_gitin1174-grafana-7x-update/`.
- **GITIN-1748** — MongoDB cache panel fix (`smartpedidos/events/20260803_grafana-cache-panel-fix/`).

## 9. Not yet known

Whether the Grafana database is SQLite; whether any account-level backup (EBS snapshot / AWS Backup) of the instance exists; whether the AWS security group restricts the published ports; compatibility of each plugin and of the `graph` panels/legacy alerts with a current Grafana release; notification-channel settings (not collected); who the four users are and whether the default `admin` login was changed.

## SQS queue alerting around Grafana (2026-10-13, GITIN-2211)

- User-stated, not checked in Grafana: the SQS panels alert when the oldest-message age of `PRD_BranchMessages.fifo` exceeds 250 s (an order can be cancelled when no news arrives within 10 minutes). This is separate from the CloudWatch alarm `sendMailOldestMessage` (Average over 300 s, threshold above 25 s, notifies SNS `Pedidos_Production`, whose Lambda raises `platform-service-production-service` to 15 tasks); the CloudWatch statistic was read from the alarm itself on 2026-10-13, and it is Average, not Maximum.
- The Prometheus CloudWatch exporter lists SQS `ApproximateAgeOfOldestMessage`, `ApproximateNumberOfMessagesVisible` and `NumberOfMessagesDeleted/Received/Sent`: the panels can show a consumer stall as received and deleted at 0 while sent continues. Triage: `ops-aws` skill, F-007; evidence and episode list in `smartpedidos/docs/infrastructure.md` → "Production queue signals".

