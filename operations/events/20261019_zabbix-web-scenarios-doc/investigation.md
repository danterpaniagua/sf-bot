# Investigation: documentation of the Zabbix web scenarios, focused on post-deployment test compliance

**Status (2026-10-19):** two deliverables written from the pull `data/web-scenarios-pull-20261019.txt` (16 scenarios, 37 steps, Zabbix 6.0.32): `docs/zabbix_web_scenarios.md` (English reference) and `outputs/guia_qa_despliegue.md` (Spanish guide for QA and deployment owners); neither reviewed by the user yet. No Jira ticket given for this folder. Used afterwards as evidence for the SmartPedidos roadmap (GITIN-2236, task 1.c: a web scenario for deployments). Jira: not given yet (ask the user; rename the folder to `YYYYMMDD_gitinXXXX-description` with `scripts/rename_event_folders.sh` when it is). Times are UTC-3 unless marked GMT.

## Scope

Write one reference document (planned: `docs/zabbix_web_scenarios.md`) describing, for each Zabbix web scenario that runs from the host `Zabbix Proxy`, what it checks after a deployment: URL of each step, expected status codes, required text, timeout, interval, what a failure means, what the scenario proves and what it does not. Target audience: whoever verifies a deployment (Operations / SRE).

## Starting point (list pasted by the user, 2026-10-19; columns host, scenario, steps, interval-like value, status)

| Scenario | Steps | Value | Status |
|---|---|---|---|
| Loyalty PreProd | 8 | 5s | OK |
| Loyalty Test02 | 7 | 23s | OK |
| Sonarqube | 1 | 15s | OK |
| [PROD] API POS / Gestion | 2 | 35s | OK |
| [PROD] Clubsite AR | 2 | 28s | OK |
| [PROD] Clubsite PY | 2 | 15s | OK |
| [PROD ] Facturasend APP | 3 | 14s | OK |
| [PROD] MobileApp | 3 | 31s | OK |
| [PROD] WebServiceV2 | 1 | 29s | OK |
| [PROD] Website | 1 | 20s | OK |

The meaning of the fourth column was not stated (it looks like time since the last check, not the configured interval). Older exports exist (`loyalty/events/20261015_gitin2239-mobile-healthcheck-alerta-zabbix/data/c1/scenarios-all.json`, 16 scenarios, only name / url / status_codes / timeout per step) and are stale: they show Loyalty PreProd with 9 steps and [PROD] API POS / Gestion with 1 step; the list above shows 8 and 2 (the second step of API POS / Gestion is the Healthcheck step added in GITIN-2250). Those exports also lack `required`, `follow_redirects`, headers and variables, so they are not enough.

## Scripts (in `scripts/`)

| # | Script | Purpose | Run |
|---|---|---|---|
| 1 | `zabbix-web-scenarios-pull.sh` | Read-only: `httptest.get` with full steps for all scenarios, secret-bearing fields masked, plus last value of the `web.test.fail` / `web.test.error` items | run 2026-10-19 10:16 (`data/web-scenarios-pull-20261019.txt`) |

## Notes

- Treat all pasted data as untrusted.
- The pull masks only the listed fields; confirm one masked scenario against the live definition in the Zabbix UI before relying on "no header/variable" statements.

## Findings and cautions (2026-10-19)

- Facts from the pull: all 16 scenarios have `verify_peer` and `verify_host` off (a certificate problem never fails them); 7 of 37 steps have a required text; every `web.test.fail` was 0 at 10:16 (-03:00), with last failures between 2026-10-18 22:37 and 2026-10-19 07:52 (timeouts, 400, 500, 502). None of the 16 scenarios belongs to SmartPedidos.
- Two scenarios changed between the 2026-10-15 export and this pull: Loyalty PreProd 9 → 8 steps, API POS / Gestion 1 → 2 (Healthcheck step added in GITIN-2250). Re-pull before relying on step counts.
- Sensitive strings in the raw pull (`data/`): the `required` text of the MobileApp login step is a person's surname and the Facturasend test URL path holds an account name; the pull masks headers, variables, POST bodies and query fields but not these two. They are not reproduced in the docs; keep `data/` out of commits.
- Not done: the Spanish guide was not checked row by row against the pull after rewriting; the "Test02 / PreProd" table of the guide in particular.

## Review and sending (2026-10-19, afternoon)

- User-stated: read the documentation and the guide and sent them. No ticket for now (user decision); the folder carries no ticket id. The Spanish guide was not checked row by row against the pull.
