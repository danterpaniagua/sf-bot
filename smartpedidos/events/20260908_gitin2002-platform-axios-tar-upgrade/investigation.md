# Investigation: GITIN-2002 — Platform: Upgrade Axios y Tar

## Ticket
GITIN-2002 — https://smartit-ar.atlassian.net/browse/GITIN-2002
"[SP] Platform: Upgrade Axios y Tar"

Subtarea de GITIN-1306. Estado (2026-09-08, reportado por el usuario): Backlog, sin asignar. Hermanas: GITIN-1858 ("Correr Jenkins Platform", Finalizada), GITIN-1859 ("Correr Jenkins Concentrador", Descartado), GITIN-2000 ("Concentrador: Upgrade Axios y Tar", En curso, Dante Paniagua — ver `smartpedidos/events/20260908_gitin2000-axios-tar-upgrade/`), GITIN-1957 ("Nuevo mensaje POST build a SmartPedidos team", Backlog).

**Email a PMs consolidado con GITIN-2000:** vive en `smartpedidos/events/20260908_gitin2000-axios-tar-upgrade/email_pm.md` — cubre ambos tickets en un solo correo, no hay una copia separada en esta carpeta.

## Context
Sibling ticket to GITIN-2000 (`smartpedidos/events/20260908_gitin2000-axios-tar-upgrade/`), which covers the identical fix for concentrador-service. Kept as a separate ticket per the user's decision (2026-09-08) since GITIN-2000's title/scope is explicitly "Concentrador."

## Target
`platforms-service`, `api/package.json`, checked against the local read-only clone at `smartpedidos/repo/dev-scr-smartPedidos-platformsService/`. Real work happens on branch `ope` in the user's actual working copy of this repo (not this clone, which is lookup-only per project convention).

## Trivy report findings (report generated 2026-09-03, received 2026-09-08)

Report: `platform_Trivy_20Scan(4).zip`, artifact `dev-src-pedidos-platform:develop`. Persisted as evidence: `data/trivy_scan.zip` (original) and `data/trivy_vuln.json` (extracted, no PII/secrets — vulnerability metadata only). Scan targets: `Node.js` (43 vulnerabilities total) plus two zero-vuln targets (`production.js`, `staging.js` config files) — **no OS/Alpine package target at all**, same limitation as GITIN-2000's report.

Findings are **identical in substance to GITIN-2000** (same CVE IDs, same installed versions):
- **tar** — installed `6.2.1`, 9 CVEs (1 CRITICAL `CVE-2026-59873`, 8 HIGH). Highest fix required: `7.5.21`.
- **axios** — two installed versions, `0.26.1` and `1.13.6`, ~10 HIGH CVEs each. Highest fix required across all: `1.16.0`.

**Root cause confirmed identical to concentrador-service:** `package.json` shows `dependencies.axios: "~1.13.5"` (line 28) and `dependencies["@sendgrid/mail"]: "^7.7.0"` (line 24). `@sendgrid/mail@^7.7.0` → `@sendgrid/client@^7.7.0` declares `"axios": "^0.26.0"` (verified against the npm registry for GITIN-2000, same package/version, not re-checked here since it's the identical dependency declaration) — matching the `0.26.1` install exactly.

## Current state on branch `ope` (checked 2026-09-08)

`api/package.json` diff on the user's actual working copy (staged, 2026-09-08):
```json
"overrides": {
  "axios": "$axios",
  "tar": "latest"
}
```
Same shape and same partial-fix caveat as GITIN-2000: `tar` fully resolved and now tracks the `latest` dist-tag (consistent with GITIN-2000's decision, avoiding a new ticket per future `tar` CVE); `axios` override only forces `@sendgrid/client`'s nested axios to match the top-level `~1.13.5` — CVEs requiring `1.15.1`–`1.16.0` remain open, same deferred status as GITIN-2000.

**Additional change not covered by any evidence on file:** `api/Dockerfile` was also modified on this branch —
```dockerfile
-RUN apk add --no-cache ca-certificates
+RUN apk update && apk upgrade --no-cache && apk add --no-cache ca-certificates
```
This Trivy report has no OS-package scan target, so there is no evidence on file justifying this specific change. Not yet confirmed whether it comes from a separate scan/finding or was added independently.

## Open questions

- ~~Should the `tar` override here also move to `"latest"`?~~ Resolved 2026-09-08 — changed to `"latest"`, consistent with GITIN-2000.
- What evidence (if any) justifies the `apk update && apk upgrade` Dockerfile change? Not covered by this Trivy report (no OS-package scan target in either GITIN-2000's or GITIN-2002's report). Recommendation given to the user: keep this out of scope for GITIN-2002 — it addresses OS-level packages, not the npm `axios`/`tar` CVEs this ticket evidences, and an unpinned `apk upgrade` trades away build reproducibility. If OS-layer hardening is wanted, it should be its own ticket backed by an actual OS-layer Trivy scan.
- Axios `1.15.1`–`1.16.0` CVEs remain open here too, same as GITIN-2000 — same deferred-decision status applies (impact radius of the full axios bump not yet assessed for platforms-service specifically; GITIN-2000's impact analysis was done against concentrador-service's own source, not platforms-service's).
