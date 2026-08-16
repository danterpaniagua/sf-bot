# Graylog Infrastructure — SmartPedidos + SmartLoyalty (shared, cross-project)

**Last updated:** 2026-08-12 (`GITIN-1816`, `GITIN-1827`)

Distinct from the SmartCloud-dedicated Graylog instance (separate `cloud-graylog` repo, `smartfran-graylog-pro` VM, serves only the Business/Sales App Services). This document covers the older bare-metal Docker stack that serves **SmartPedidos and SmartLoyalty**. Don't conflate the two when a ticket just says "Graylog" — hostnames are easy to confuse (`sf-monitoreo` vs `sfcloud-monitoreo`).

## Host

`sf-monitoreo.smartfran.com` — also runs Zabbix natively on the same box (separate LVM volume `zabbix-zabbix--01` at `/mnt/database`, unrelated to Graylog/OpenSearch storage).

## Docker stack

| Container | Image |
|---|---|
| `graylog` | `graylog/graylog:5.2.12` |
| `opensearch` | `opensearchproject/opensearch:2` (running 2.19.4) |
| `mongo` | `mongo:6.0.5-jammy` |

Compose file and related scripts live locally on the host under `~/scritps/graylog/` — **not version-controlled in any repo** (not `bots/`, not `cloud-graylog/`). `opensearch` is single-node (`discovery.type: single-node`), `bootstrap.memory_lock: true` with no matching `ulimits: memlock` block (known risk, unresolved as of 2026-08-12), heap `-Xms2g -Xmx2g` inside a 6GB container memory limit.

**No cold/warm index storage tiering** — confirmed 2026-08-14: this stack runs the open-source `graylog/graylog:5.2.12` image (not `graylog/graylog-enterprise`), no license key or Data Tiering config anywhere in the compose environment. Data Tiering (S3-backed cold storage) is a Graylog Enterprise/Cloud feature, unlike `cloud-graylog` (SmartCloud-dedicated instance). Practical effect: the only levers on an oversized index like `graylog_299` are the field-limit fix, retention (`max_number_of_indices`), and raw disk capacity — no "move old data to cheap storage" option exists on this instance.

## Ports / Inputs

| Port | Purpose |
|---|---|
| `9000` | Graylog web UI / REST API |
| `9200` | OpenSearch — `plugins.security.disabled: true`, no auth |
| `1514` | `TXT_UDP` input — raw/plaintext. Carries hMailServer/`SF-SMTPRL` traffic (SmartLoyalty) and ClubSite/IIS traffic (also SmartLoyalty) through a shared, historically-reused JSON extractor (`mobile_json_extractor`) and CSV parser (`w3c_parser_mobile`) — names reflect the original IIS use, not current traffic. |
| `11514` | AWS WAF raw UDP |
| `12201`/`12202` | GELF |

## Mail relay hop (SmartLoyalty)

`SFCG-SMTP-01` (`192.168.50.161`) / `SFCG-SMTP-02` (`192.168.50.162`) run hMailServer for WebServiceCG's outbound email (e.g. `AccountRecovery`). Flow: app → hMailServer (these hosts) → `smtp.sendgrid.net` → recipient. NXLog on each ships delivery log lines (tag `SF-SMTPRL`, `Cardinality` `01`/`02`) to the `TXT_UDP` input above. Confirmed 2026-08-11/12 during `GITIN-1816`. See `loyalty/docs/infrastructure.md`.

## Known issues (as of 2026-08-12, `GITIN-1827`)

- **Zero replicas** on every index (`rep 0`) — no redundancy across the entire cluster.
- **`graylog_299`** (Default Stream) and **`sp_platform__50`** (SmartPedidos platform-service) are at OpenSearch's default `index.mapping.total_fields.limit` (1000 fields) — rejects any message introducing a field name not already mapped, blocks rollover to the next index in either series. 177,356 accumulated indexer failures. `graylog_299` is ~150x the size of its peer indices (472.8GB vs. ~3-4GB) — consistent with rollover being stuck. Fix (raise the limit via `_settings`) drafted but not applied — touches indices shared with other services, needs confirmation first.
- OpenSearch container restarted 2026-08-12 (`OOMKilled: false` — trigger not confirmed, JVM-internal heap issue suspected given the `bootstrap.memory_lock` misconfiguration above). On this single-node cluster, every restart makes the **entire cluster** briefly unavailable during recovery — with ~1.5B+ documents in `graylog_299` alone, that's not instant. Any message sent via UDP during that window is silently lost with **zero error on the sending side** (no delivery confirmation over UDP).

**Diagnostic lesson:** when messages "stop arriving" in Graylog with nothing wrong visible on the sending side, check this cluster's own health (`GET _cluster/health`, `docker logs opensearch` for restart signatures) **before** spending significant time on the sender's config. A multi-hour investigation during `GITIN-1827` chased NXLog configuration changes before finding the real cause here.

## Related

- `loyalty/docs/infrastructure.md` — SmartLoyalty application server inventory, including the mail relay hosts.
- `loyalty/events/20260811_webservicecg_recuperacion_cuenta_email/` (`GITIN-1816`) — the recovery-email ticket that led to this investigation.
- `operations/events/20260812_graylog_messages_not_arriving/` (`GITIN-1827`, **closed**) — original investigation, commands, and findings for the outage described above.
- `operations/events/20260813_platform-service-branch-id-unknown-mapping-error/` (`GITIN-1854`, **active**) — carries forward all continuing work from GITIN-1827 (OpenSearch memory-config fix, `msg_rest_status`/`msg_branch_id` indexer-failure root causes). Reference this one for current status.
