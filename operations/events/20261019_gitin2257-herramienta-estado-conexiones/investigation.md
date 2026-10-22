# Investigation: tool to see connection status (office internet instability, Google Admin per-host data)

**Status (2026-10-19): closed as not viable by the user; `ops.md` written once from this state.** There is no Zabbix or other always-on host in the office (reported), so the probe route is not available either. Google Admin routes closed for now: the Admin console lists no devices and the account has no Chrome Enterprise SKU (both reported by the user, not independently checked), and the Meet quality data (`admin.google.com/ac/meet/quality`) is not reachable through the API (user's conclusion: not viable; both the Playground and an Apps Script project were blocked by the Admin console's API controls, and the page has no export option). Next route: probes from the office network (Zabbix). Jira: https://smartit-ar.atlassian.net/browse/GITIN-2257 ("[OPE] Herramienta para ver estado de conexiones"). Times are UTC-3 unless marked GMT.

## Scope

Several office users report that the internet does not work. Goal: gather per-host data to assess internet stability and user PC problems. The user first proposed `GET https://admin.googleapis.com/gmail/v1/reports/usage/`; that path is not a Google API and Gmail usage reports only hold mail counters (not checked against the docs).

## What was tried (evidence in `data/`)

| File | What | Result |
|---|---|---|
| `telemetry-devices-p1.json`, `tokeninfo.json`, `token-refresh-attempt1.json`, `token-refresh-attempt2.json`, `tokeninfo-attempt2.txt` | Telemetry call with the token held in the shell | 401; `tokeninfo` says `invalid_token` although the token looked well-formed. Refresh from the shell was impossible: the tokens came from the OAuth Playground's shared client, whose secret the user does not have |
| `playground-telemetry-test1.txt` | Telemetry call from the Playground, no `readMask` | 400 `read_mask is required`: token, scope and API accepted |
| `playground-telemetry-test2.txt` | Same with `readMask` | `{}`: no device returns telemetry |
| (no file) | Directory API scopes in the Playground | `access_not_configured`: Admin console API controls block the Playground app for those scopes |

| `apps-script-reports-403.txt`, `scripts/meet-call-ended-export.gs` | Meet `call_ended` events (Reports API, `applicationName=meet`) through an Apps Script project as the admin | 403 `ACCESS_TOKEN_SCOPE_INSUFFICIENT` (token had no `admin.reports.audit.readonly`: the manifest was not edited); after adding the scope to the manifest, the authorization screen said "Acceso bloqueado: el administrador de tu institución debe revisar Proyecto sin título". Needs a super admin to trust the project; not requested. Playground also blocked for this scope |

## Findings

- Meet quality tool (Admin console → Reporting): the page offers no export option in this account (reported). The Reports API route needs a super admin to trust an app or project for `admin.reports.audit.readonly`; not done, so the Meet data was never read. Whether the Meet data would have been useful was not tested.

- Telemetry API works for this account but returns no devices.
- The user checked Admin console → Devices → Chrome (reported, no screenshot or count saved): no devices, and the organisation has no Chrome Enterprise SKU. Managed-browser inventory was not confirmed either way.
- Consequence: Google Admin holds no per-host connection data for the office PCs. It could not tell an ISP/router problem from a PC problem even with data.
- Access tokens pasted into chat once (expired within the hour, not stored).

## Next step (proposed, not decided)

Measure from inside the office: Zabbix probes (ping to gateway and public IPs, DNS resolution time, HTTPS check) from a host on the office LAN, plus router/ISP-side data if available. Open questions: is there a Zabbix proxy or agent host on the office network; who manages the office router/ISP link; time pattern of the user reports (to line up against the probe data).
