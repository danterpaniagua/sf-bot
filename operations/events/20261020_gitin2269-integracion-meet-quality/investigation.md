# Investigation: GITIN-2269 — Meet quality integration

**Status (2026-10-20): closed by the user; `ops.md` written once, from the GITIN-2257 analysis (no new work; the reason for closing was not stated).** Opened, nothing run for this event. Jira: https://smartit-ar.atlassian.net/browse/GITIN-2269, title as given by the user: "[OPE] Integracion de Meet QUality" (listed under the WiFi problems ticket GITIN-2268; the ticket body was not seen). Scope as given: integrate Meet quality data. What the integration must deliver (a report, a dashboard, an alert, a feed into Zabbix) was not stated.

## Starting point: the earlier analysis (not re-derived; `operations/events/20261019_gitin2257-herramienta-estado-conexiones/`, GITIN-2257, closed "not viable")
- Meet quality page (Admin console, `ac/meet/quality`): no export option in this account (user-stated).
- Reports API, Meet `call_ended` events (`applicationName=meet`):
  - OAuth Playground: blocked by the Admin console's API controls (`access_not_configured`).
  - Apps Script project run as the admin: 403 `ACCESS_TOKEN_SCOPE_INSUFFICIENT`; after adding `admin.reports.audit.readonly` to the manifest the authorization screen said "Acceso bloqueado: el administrador de tu institución debe revisar Proyecto sin título". A super admin has to trust the project; not requested. The script is `scripts/meet-call-ended-export.gs` in that event.
- No Meet data was ever read, so its usefulness for the office problem is untested. The same event found no devices in the Admin console and no Chrome Enterprise SKU (both user-stated).

## Open questions
- Which fields does the Reports API return for `call_ended` (network quality, packet loss, jitter, device and network type)? Not read from the documentation or from a live call yet; whether they identify a user or a network segment is unknown.
- Who is the super admin that can trust the project or the app for the Reports scope, and is the organisation willing to do it? Not asked.
- Does the Workspace edition include the Meet quality tool and the Reports API data for Meet? Not checked.
- How are Meet calls linked to the office network (client public IP, device, location) so that office problems can be told from home or mobile calls? Unknown.

## Next steps (proposed, not decided)
1. User: state the expected output of the integration.
2. User: ask the super admin to trust the Apps Script project (or a dedicated one) for `admin.reports.audit.readonly`; then run `meet-call-ended-export.gs` for a short window (it saves to a sheet; results to `data/`).
3. Read the returned fields and decide what can be measured; only then write the integration.
