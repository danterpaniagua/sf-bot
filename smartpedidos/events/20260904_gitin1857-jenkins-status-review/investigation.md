# Investigation — 20260904_gitin1857-jenkins-status-review

**Jira:** [GITIN-1857](https://smartit-ar.atlassian.net/browse/GITIN-1857) (parent), subtasks:
- [GITIN-1858](https://smartit-ar.atlassian.net/browse/GITIN-1858) "[SP] Correr Jenkins Platform" — board status: `Bloqueado`
- [GITIN-1859](https://smartit-ar.atlassian.net/browse/GITIN-1859) "[SP] Correr Jenkins Concentrador" — board status: `Backlog`
- [GITIN-1957](https://smartit-ar.atlassian.net/browse/GITIN-1957) "[SP] Nuevo mensaje POST build a SmartPedidos team" — board status: `Backlog`

**Status: record-keeping only — no new work, this documents a status reconciliation.**

## Finding (2026-09-04)

Real, applied work already exists locally for this area, but doesn't line up cleanly with the Jira split. `smartpedidos/events/20260827_jenkins-bugreport-toggle-branch-filter/` — attributed there to **GITIN-1858 alone** — covers **both** Concentrador and Platform Jenkins jobs (`dev-src-pedidos-concentrador.jenkinsfile`, `dev-src-pedidos-platform.jenkinsfile` in `sf-devops`):

1. Added `RUN_BUGS_REPORT` toggle param (default `false`) so the "Bugs Report" stage (Claude Code analysis) no longer runs automatically on every build — matches the user's recollection that both jobs were "updated to run w/o claude."
2. Added a branch filter to each job's GitHub webhook trigger, so builds only fire for the configured branch.
3. Platform's target branch corrected from a stale feature branch to `develop`.

That folder's `ops.md` records `Aplicado: Sí, confirmado por el usuario en ambos jobs` — applied and confirmed in both jobs, 2026-08-27.

**The discrepancy — resolved (2026-09-04):** Jira originally split this into two separate subtasks (1858 = Platform, 1859 = Concentrador). Since both were actually addressed together under GITIN-1858's local record, **the user marked GITIN-1859 as discarded** in Jira — it isn't separate remaining work, it was already covered. GITIN-1858 remains the ticket of record for both services' Jenkinsfile changes; its `Bloqueado` board status is still stale relative to the confirmed-applied local state (not corrected here — a Jira status update, not something this repo tracks).

**GITIN-1957** is unrelated — a new post-build notification feature, nothing local addresses it. Genuinely still backlog.

## Open questions / next steps

1. ~~GITIN-1858's Jira status (`Bloqueado`) still doesn't reflect the confirmed-applied local state~~ — **resolved**, now shows `Finalizada` in Jira as of 2026-09-17.
2. ~~GITIN-1957 — not started, no local record exists~~ — **resolved differently than expected**: discarded in Jira (2026-09-17), not completed. Consistent with "genuinely still backlog" as of 2026-09-04 — it was never built, and the decision was to drop it rather than do it.

## Status (2026-09-17): epic complete

All 12 of GITIN-1857's subtasks are now in a terminal state (Finalizada or Descartado) — see `ops.md` for the full consolidated closure report.
