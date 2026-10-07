# Investigation: GITIN-2107 parent plan tracker

**Jira:** [GITIN-2107](https://smartit-ar.atlassian.net/browse/GITIN-2107) — "[SP] Plan actualización SmartPedidos"

## Status

**Converged — this is a lightweight parent/tracker, not a technical investigation.**

## Purpose

GITIN-2107 is the parent story for a SmartPedidos-wide npm package update effort, split into 3 child subtasks, one per service:

| Child | Service | Notes |
|---|---|---|
| GITIN-2116 | platforms-service | Real technical work already done this event, see below |
| GITIN-2117 | concentrador-service | Not started (Backlog) |
| GITIN-2118 | BBOO (backOffice) | Not started (Backlog) — backOffice is a static S3+CloudFront deploy with no production Node runtime (`smartpedidos/CLAUDE.md`), but still has build-time npm dependencies that can carry CVEs, so the ticket is legitimate scope, not a mismatch |

User-provided source: pasted Jira subtask list, 2026-09-28, 0% complete, all 3 children in "Backlog" status, all assigned to the same person (name omitted here per this project's no-names-in-events rule).

## Confirmed facts (2026-09-28)

The GITIN-2116 diagnostic (axios/express-jwt/jsonwebtoken/uuid CVEs vs. Node-20 compat boundary, full 33-package table) was already completed in a separate local event folder: `smartpedidos/events/20260928_gitin2116-platform-npm-update/` (`ops.md` scoped to platforms-service only, written and rescoped 2026-09-28, referencing GITIN-2116 directly — not GITIN-2107). That folder was originally created 2026-09-25 as a generic, mixed-scope folder (`20260925_npm-compat-node20-boundary`) before the parent/child ticket structure was known; migrated/renamed to its current GITIN-2116-scoped name same day the split was clarified.

GITIN-2117 and GITIN-2118 have no local investigation work yet — this tracker's `ops.md` only reports their Jira status as given by the user, nothing technical.

## Related

- `smartpedidos/events/20260928_gitin2116-platform-npm-update/` — GITIN-2116 (platforms-service) diagnostic and `ops.md`. Local-path cross-reference, internal use only per root `CLAUDE.md` — never cited this way in `ops.md`/`ops-events.md`, only by Jira ID there.

## Next steps

1. If/when GITIN-2117 (concentrador-service) work starts, open its own local event folder (`YYYYMMDD_gitin2117-<description>`) rather than reusing this one — the GITIN-2107 compat/CVE data for concentrador-service already partially exists in the GITIN-2116 folder's raw `data/` (registry/OSV fetches covered the union of both services' dependencies) and can be reused without re-fetching.
2. If/when GITIN-2118 (BBOO) work starts, same pattern — new folder, `YYYYMMDD_gitin2118-<description>`.
3. Update this tracker's `ops.md` only when the user asks for a fresh status snapshot — it's a point-in-time summary of subtask status, not a living document to poll Jira against (no Jira connector available in this environment; status here reflects only what the user has pasted).
