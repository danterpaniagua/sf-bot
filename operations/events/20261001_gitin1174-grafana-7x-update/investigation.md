# Investigation — 20261001_gitin1174-grafana-7x-update

**Jira:** [GITIN-1174](https://smartit-ar.atlassian.net/browse/GITIN-1174) "Actualizacion Grafana 7.X" (title as given by the user, 2026-10-01; ticket description not yet provided).

**Status (2026-10-01, end of day):** in progress — scope stated by the user (Grafana to latest, certificates, update automation). Done, all read-only: VM inventory over ssh (Grafana 7.3.7, compose identical to the local copy, history/README read), hostname checks (`monitoreosp.smartfran.com` → `52.25.171.46`; Grafana on plain HTTP :3000; HTTPS answers 404 with Traefik's self-signed default certificate, expired 2026-10-01 00:39:45 GMT), and the live Grafana API inventory (7 datasources, 37 plugins, 8 dashboards / 85 panels, 16 legacy alerts, 4 notification channels, 4 users). Reference doc created: `operations/docs/grafana.md`. Nothing changed on the VM or in Grafana. **To do by the user:** delete the temporary Admin API key (`claude`, expires 2027-10-01). **Open decisions:** how to obtain the certificate for `monitoreosp.smartfran.com` (Traefik ACME, corporate certificate, or termination in front of the VM) and what "update automation" should cover; the upgrade plan (backup of `db/`, rehearsal on a copy of the VM, staged path) is not drafted yet.

## Origin of this event

The user asked whether an investigation already existed for GITIN-1174. Searched `~/Documentos/` (names and content, 31 GB tree, excluding `.git`/`node_modules`/virtualenvs) on 2026-10-01: **no investigation, event folder or note for GITIN-1174 exists** (the only content matches are two lines in `git/itiano/logs/app.log`, a Django template error that lists ticket ids 1173/1174/1175 — not analysis). The user believed an analysis had been done in a previous setup; none was found. This folder is the first record.

## Confirmed facts (from existing files, 2026-10-01)

- **Deployment definition:** `~/Documentos/git/smartfran/smart-pedidos/grafana/docker-compose.yml` (identical copy under `git/smartfran/smartfran/smart-pedidos/grafana/`; a `docker-compose.yml~` backup differs only in whitespace; files dated Oct–Dec 2025; the `smartfran/` folder is **not** a git repository, so there is no history). Compose services:
  - **Grafana `grafana/grafana:7.3.7`** (pinned), port 3000, data in local volume `./db`, `privileged: true`, `restart: always`, behind Traefik with host rule `monitoreo.ross.com.ar` (TLS via ACME http challenge).
  - Plugins in `GF_INSTALL_PLUGINS`: `agenty-flowcharting-panel` 0.5.0 and `grafana-aws-athena-datasource` 2.2.7 (a `GF_INSTALL_PLUGINS` line for the MongoDB Atlas datasource is commented out); `GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=grafana-mongodb-atlas-datasource,mtanda-aws-athena-datasource`.
  - `prom/prometheus:v2.24.1` (180-day retention, `./prometheus-data`), `prom/blackbox-exporter` (unpinned), `prom/cloudwatch-exporter:latest` (unpinned, `AWS_REGION=us-east-1`), `traefik:v2.4` with `--api.insecure=true` on port 8080 and docker socket mounted read-only.
  - (The compose also carries a personal ACME contact address — deliberately not recorded here.)
- **Related event:** `smartpedidos/events/20260803_grafana-cache-panel-fix/` (GITIN-1748): Grafana 7.3.7 (~2020) on the dashboard host `monitoreosp.smartfran.com`; datasource plugin `grafana-mongodb-atlas-datasource` v1.0.0 (2019-04-10, no updates since, built for Grafana 6.x) hides the real Atlas API error; open actions there: audit other panels on that datasource, evaluate replacing/forking the plugin; it flags the Grafana version as technical debt to weigh when prioritising. The Grafana API (API key, `api/frontend/settings`, `api/tsdb/query`) was usable there. `operations/events/20260829_mobile_alerts_coverage_analysis/` also queried the Grafana API.
- Project tag for Grafana work: `Obserbavilidad` (root `docs/tags.md`).

## Scope (user, 2026-10-01)

1. **Update Grafana to the latest version** (from 7.3.7).
2. **Add certificates** (TLS) — exact meaning not yet specified; today Traefik v2.4 terminates TLS on the host rule `monitoreo.ross.com.ar` using an ACME http-challenge resolver with a `./letsencrypt` volume (root-owned, 20 KB), so the intent (corporate/other CA certificate, wildcard, a different hostname such as a `smartfran.com` name, or replacing/automating the current ACME setup) must be confirmed.
3. **Update the automation** of the stack ("update automation": how the stack is deployed and kept up to date) — what exists today is a compose directory on the VM that is also a git repository (history not yet read), unpinned exporter images and no visible scheduled job/backup; target automation (pinned versions + scheduled pull/rebuild, CI/CD, IaC, backup job, …) to be defined.

Considerations for planning (general knowledge about Grafana, **not verified for this installation — to be checked against the release notes of each major**): going from 7.3.7 to the current release crosses many major versions (8 → latest); the Grafana database is migrated forward on start and normally cannot be rolled back, so a backup of `./db` (and of the compose directory) is a precondition; legacy dashboard alerts, API keys (replaced by service accounts), AngularJS-based plugins (the flowcharting plugin 0.5.0, simple-json, the Atlas plugin 1.0.0 and the Athena plugin 2.2.7 were built for old Grafana) and unsigned-plugin loading are the usual breakage points; a rehearsal on a copy of the VM/volume before touching production is the safe way to find out. The host's Docker 20.10.3 may also be too old for current Grafana images/compose features (not checked).

## Current hostname (user, 2026-10-01): `monitoreosp.smartfran.com`

The user states the current hostname of this Grafana is **`monitoreosp.smartfran.com`** — the same name used in the GITIN-1748 event, whose scripts call it as **`http://monitoreosp.smartfran.com:3000/...`** (`api/dashboards/home`, `api/tsdb/query`, `api/frontend/settings`; `smartpedidos/events/20260803_grafana-cache-panel-fix/…_scripts.sh` lines 7, 11, 43), i.e. **plain HTTP straight to Grafana's published port 3000**, not through Traefik. The Traefik rules in the VM's compose only match the vendor name `monitoreo.ross.com.ar`, so **no router or certificate for `monitoreosp.smartfran.com` is defined in this compose** (consistent with the scope item "add certificates": the SmartFran hostname appears to be served without TLS today — **unverified**: HTTPS on 443/another proxy in front was not tested; DNS target of the name was not resolved). Note for the security review: API keys were sent in clear over HTTP in that earlier work if the scripts' URLs are accurate.

**Hostname checks, run 2026-10-01 ~14:23Z from the user's machine (`data/hostname_checks_20261001.txt`):** `monitoreosp.smartfran.com` resolves to **52.25.171.46**; **`http://…:3000/api/health` → `200 OK`** (Grafana is reachable over plain HTTP); **`https://…/` (port 443) → `HTTP/2 404`** from Traefik (no router matches the Host header) and the certificate presented is **Traefik's self-signed default (`CN = TRAEFIK DEFAULT CERT`, valid 2025-10-01 00:39:45 GMT → 2026-10-01 00:39:45 GMT) — i.e. already expired by about 13 h at the time of the check**, with no certificate for the SmartFran name. This confirms that no valid certificate is served for `monitoreosp.smartfran.com` today and that users reach Grafana via port 3000 without TLS. Not yet seen: the Traefik/ACME log check on the VM (`vm_12_traefik_acme_20261001.txt` does not exist yet) and whether the AWS security group restricts the exposed ports.

## Live Grafana inventory via API (2026-10-01 ~14:29–14:30Z; `data/gf_*_20261001.*`, `scripts_grafana_api.sh`)

Run against `http://monitoreosp.smartfran.com:3000` with a temporary Admin-role API key (the key travelled in clear text over HTTP). `/api/admin/stats` and `/api/orgs` returned `Permission denied` (server-admin endpoints, not available to API keys). Everything else worked. Health: version **7.3.7**, database ok.

- **Datasources (7):** `SmartFran - MongoDB Atlas ` (plugin `grafana-mongodb-atlas-datasource`, **the default datasource**), `AWS Athena datasource` (`mtanda-aws-athena-datasource`), four native `cloudwatch` datasources (`AZ_CloudWatch`, `CloudWatch`, `Inviertis - CloudWatch`, `SmartFran - CloudWatch`) and `Prometheus` (`http://prometheus:9090`).
- **Plugins (37):** 33 core, 4 non-core — `mtanda-aws-athena-datasource` 2.2.7, `agenty-flowcharting-panel` 0.5.0 and `grafana-mongodb-atlas-datasource` 1.0.0, all **unsigned**, plus `grafana-simple-json-datasource` 1.4.2 (signature valid).
- **Folders/dashboards:** one folder (`SmartFran_Metrics`), **8 dashboards, 85 panels in total, all at dashboard schemaVersion 26** (Grafana 7.3 era):

  | Dashboard | Panels | Panel types | Datasources | Legacy alerts | Last updated |
  |---|---|---|---|---|---|
  | AWS Details | 25 | graph 13, text 5, gauge 4, table 2, stat 1 | Athena, SmartFran - CloudWatch | 8 | 2025-09-22 |
  | BBOO Status | 3 | graph 2, logs 1 | CloudWatch, Prometheus | 0 | 2025-10-29 |
  | Mongo Details | 9 | graph 4, stat 2, bargauge, gauge, text | MongoDB Atlas | 1 | 2024-02-07 |
  | Operaciones | 17 | graph 17 | SmartFran - CloudWatch, MongoDB Atlas | 7 | 2026-08-30 |
  | Operaciones Firewall | 6 | graph 5, stat 1 | Prometheus | 0 | 2025-10-29 |
  | OperacionesV2 | 14 | graph 14 | Prometheus, MongoDB Atlas | 0 | 2025-11-10 |
  | SmartFran - General | 2 | flowcharting 1, text 1 | (default), Prometheus | 0 | 2022-03-02 |
  | SP-STG | 9 | graph 7, gauge 2 | SmartFran - CloudWatch | 0 | 2025-04-25 |

  Totals: **62 panels of the classic `graph` type**; MongoDB Atlas plugin used by 3 dashboards (Mongo Details, Operaciones, OperacionesV2, and it is also the default datasource used by the flowcharting dashboard's unspecified datasource); Athena by 1 (AWS Details); flowcharting by 1 (SmartFran - General, untouched since 2022).
- **Alerts:** **16 legacy dashboard alerts** (15 `ok`, 1 `no_data`; AWS Details 8, Operaciones 7, Mongo Details 1) and **4 notification channels**: `Inviertis Slack` (slack), `SmartPedidos Telegram` (telegram), `Inviertis` and `Mensajesencolados` (email) — channel settings were not collected (may carry secrets). None is the default channel.
- **Users/keys:** 4 organisation users (1 Admin seen <1 min ago, Editor seen 3 months ago, Viewers seen 2 months and 1 year ago; logins not recorded here) and **1 API key — the temporary one used for this run (name `claude`, role Admin, expires 2027-10-01) — to be deleted**; no other API key exists (the key used in GITIN-1748 is gone).
- **Planning observations (general Grafana knowledge, not verified for these versions):** the legacy `graph` panel and old unsigned plugins depend on AngularJS, which newer Grafana releases deprecate/remove; legacy alerts and notification channels have to be migrated to the unified alerting system in newer majors; dashboards at schema 26 are auto-migrated on load. The most exposed assets are the default Atlas datasource (3 dashboards, GITIN-1748's unmaintained plugin), the 16 alerts/4 channels, and the 62 `graph` panels.

## Deployed location (user, 2026-10-01)

Compose directory on the VM (user-stated): **`/home/ubuntu/grafana-prometheus`**. Read-only inventory taken over ssh on 2026-10-01 ~14:17Z (`data/vm_01…vm_09_*_20261001.*`; secret-like values masked on the VM):

- **Host:** `ip-172-31-42-88` (AWS EC2 naming, kernel `5.15.0-1084-aws`), **Docker 20.10.3** (old; no `docker compose` plugin — container names `grafana-prometheus_<svc>_1` indicate classic `docker-compose`).
- **Grafana version confirmed: 7.3.7** (`/api/health`: commit `1e261642f4`, database ok). Running containers: `grafana/grafana:7.3.7` (up 12 months), `prom/prometheus:v2.24.1` (up 11 months), `traefik:v2.4` (up 12 months), `prom/cloudwatch-exporter:latest` (image created 2 years ago, up 11 months), `prom/blackbox-exporter` (unpinned, image 5 years old). Leftover images on the host: `grafana/grafana:latest` (5 years old), `robot`, `python:3`. Ports published on all interfaces: 3000, 9090, 9106, 9115, 80/443 and Traefik's insecure API on 8080 (whether the AWS security group restricts them was not checked).
- **The VM's `docker-compose.yml` is identical to the local copy** (masked, whitespace-insensitive diff) — so the earlier analysis of the local file describes the deployed definition.
- **Directory contents:** a **`.git` repository** (history available on the VM, not yet read), `README.md` (11.7 KB, not read), `docker-compose.old` (2024), `dbdetail.json`/`test.json` (2021), `plugins/`, `prometheus-configuration/`, `prometheus-data/`, `letsencrypt/` (root-owned, 20 KB), `.idea/` and a leftover editor swap file `.docker-compose.yml.swp` from 2025-03-20 owned by a personal account (an edit left open/unsaved at some point; contents not read).
- **Plugins installed in `db/plugins`:** `mtanda-aws-athena-datasource` 2.2.7, `grafana-mongodb-atlas-datasource` 1.0.0 (active on disk although its install line is commented out in the compose), `grafana-simple-json-datasource` 1.4.2, and a flowcharting plugin directory (its `plugin.json`/version not captured); some plugin directories are literally named with quotes (artifact of the compose's `;"name"` install syntax) and one holds a full source checkout (`Makefile`, `package.json`, …).
- **Prometheus** (`prometheus.yml`): `scrape_interval 15s`; active jobs `prometheus`, `cloudwatch` (1 m) and `blackbox` (target list in `data/vm_05…`); many jobs commented out (MongoDB Atlas, Google, several API checks, "lachuca"). **CloudWatch exporter** (`region: us-east-1`): SQS (`ApproximateAgeOfOldestMessage`, `ApproximateNumberOfMessagesVisible`, `NumberOfMessagesDeleted/Received/Sent`), ECS (`RunningTaskCount`, `CPUUtilization`, `MemoryUtilization`), WAFV2 (`AllowedRequests`, …); full list in `data/vm_05…`.
- **Sizes:** root volume 59 GB, 26 GB used (45 %), 33 GB free; `prometheus-data` **15 GB**; Grafana `db` **193 MB** (SQLite assumed from `database: ok`, not confirmed); `letsencrypt` 20 KB.
- **Backups:** `ubuntu` has no crontab and `/etc/cron.d` holds only `e2scrub_all` and `popularity-contest` — **no scheduled backup is visible on the VM**; EBS snapshots/AWS Backup at the account level were not checked.

## VM repository history and README (read 2026-10-01; `data/vm_10_git_log_20261001.txt`, `data/vm_11_readme_20261001.txt`)

- **History:** three commits only. `5571896` (2025-03-20) **"Primer commit como lo deja ROSS. Funcionando"**, `912b739` (2025-09-30) adds the CloudWatch exporter, `ac17586` (2025-09-30) adds the README — all by a generic account named "Ubuntu" (author names are in the data file, not recorded here). So the stack was **handed over by a third party ("ROSS", the owner of the `ross.com.ar` domain used in the Traefik host rule `monitoreo.ross.com.ar`)** in March 2025 and documented/extended in September 2025; no earlier history, and nothing about GITIN-1174 or an update analysis.
- **README** (Spanish, 451 lines, 1 email address masked): architecture (CloudWatch exporter → Prometheus → Grafana; blackbox for HTTP checks), component list matching the compose (Grafana v7.3.7, Prometheus v2.24.1, exporters `latest`, Traefik v2.4 "SSL automático (Let's Encrypt)"); prerequisites Docker ≥ 20.10 and Docker Compose ≥ 1.29, domain `monitoreo.ross.com.ar`; **it documents the default Grafana login `admin` / `admin` "(cambiar en primer login)"** — whether it was changed was not checked. Maintenance section is **manual**: `tar` backups of `db/`, `prometheus-data/`, configs and the compose file (no scheduled job found — see sizes/cron above); updates = `docker-compose down` → `docker-compose pull` → `up -d` (with Grafana pinned to `7.3.7` the pull does not move Grafana; only the unpinned exporters change); a "log rotation" step suggests `docker system prune -a --volumes` (destructive: removes all unused images and volumes — to treat with care); certificate troubleshooting = check Traefik logs, `letsencrypt/acme.json` (must be mode 600), and to force renewal delete `acme.json` and restart the proxy.
- The README also lists SQS metrics and HTTP health checks as the monitored scope; the CloudWatch exporter scrape interval is stated as 5 minutes (README) vs. `scrape_interval: 1m` for that job in `prometheus.yml` and `15s` global — not reconciled.

## Not known

- What "7.X" means in the ticket: an upgrade within 7.x or from 7.x to a newer major; the target version.
- Whether `monitoreo.ross.com.ar` (compose) and `monitoreosp.smartfran.com` (GITIN-1748 event) are the same instance, which host/VM runs it, and whether the compose files in `~/Documentos` match what is deployed.
- Current Grafana state: dashboards, datasources and plugins actually in use (the compose is a definition, not an inventory), users/alerts, size and backup of `./db` (database engine not stated in the compose), and whether the data volume is backed up.
- Plugin compatibility with a newer Grafana: `flowcharting` 0.5.0, `grafana-aws-athena-datasource` 2.2.7 and the unsigned MongoDB Atlas plugin were all built for older Grafana releases (general knowledge, not verified for these exact versions: newer Grafana majors deprecate/remove AngularJS plugins and tighten unsigned-plugin loading) — to be checked against each plugin's own release notes.
- Prometheus/Traefik/exporters: whether they are upgraded in scope (Prometheus v2.24.1 and Traefik v2.4 are old; blackbox and cloudwatch exporters are unpinned).

## Next steps

1. Ticket description and target version; confirm the hosting of the instance(s).
2. Inventory on the live Grafana via API (version from `/api/health` or `/api/frontend/settings`, datasources, installed plugins, dashboards list/count, alert rules), saved to `data/` (read-only; the user runs and pastes back).
3. Per plugin: compatibility with the target Grafana version.
4. Backup of `./db` and a rollback plan before any change; decide whether Prometheus/Traefik/exporter pins are part of the scope.
5. Write `ops.md` (Spanish) only once converged.
