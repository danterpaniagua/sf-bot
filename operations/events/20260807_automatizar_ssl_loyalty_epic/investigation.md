# Investigation — 20260807_automatizar_ssl_loyalty_epic

**Status:** reference only — tracks the epic-level architecture map for `GITIN-1768`, not an incident investigation.

## Context

`GITIN-1768` ("Automatizar SSL Loyalty") is the epic grouping SSL certificate renewal automation across SmartFran/Grido's public services, motivated by the MobileAppService expiry incident (`GITIN-1758`, August 2026). Six subtasks: `GITIN-1774` (Migración `_acme-challenge`), `GITIN-1769` (ClubSite PY), `GITIN-1770` (ClubSite AR), `GITIN-1771` (WebSite), `GITIN-1772` (WebServiceV2), `GITIN-1773` (WebServiceCG).

This event exists solely to hold and version the epic-level Mermaid diagram (`epic_map.md`) summarizing all six subtasks' status — the actual investigation/implementation work for each subtask lives in its own sibling event folder:

- `GITIN-1774` → `operations/events/20260806_acme_challenge_migration/`
- `GITIN-1769` → `operations/events/20260806_automatizar_clubsite_py/`
- `GITIN-1770` → `operations/events/20260806_automatizar_clubsite_ar/`
- `GITIN-1771` / `GITIN-1772` / `GITIN-1773` → not started, no event folder yet.

## Status snapshot (2026-08-07)

| Subtask | Estado |
|---|---|
| `GITIN-1774` | Completo y verificado |
| `GITIN-1770` | Completo y verificado (tramo público + tramo backend) |
| `GITIN-1769` | Bloqueado — sin acceso DNS administrativo a `clubgrido.com.py` |
| `GITIN-1771` | No iniciado |
| `GITIN-1772` | No iniciado |
| `GITIN-1773` | No iniciado |

See `epic_map.md` for the diagram itself — kept in Spanish per this project's `events/` language rule (this file is the one exception that stays English).
