---
name: project-commands-architecture
description: All project skills live in root .claude/commands/ (sf-skills submodule) with a project prefix. loyalty/'s local .claude/commands/ is documented as source of truth but does not currently exist on disk — unresolved.
metadata:
  type: project
---

**Rule:** Each project's skills belong in the root `bots/.claude/commands/` (sf-skills submodule), prefixed by project.

| Project | Prefix | Local commands dir |
|---|---|---|
| loyalty | `loyalty-*` | `loyalty/.claude/commands/` documented as source of truth (root CLAUDE.md, loyalty/CLAUDE.md) — **confirmed absent from disk as of 2026-07-11**. All edits currently land directly in root `.claude/commands/loyalty-*.md`. Unresolved: recreate the local dir and re-sync, or update docs to drop the claim. |
| smartpedidos | `sp-*` (+ `ops-aws`, legacy naming) | None — root sf-skills only |
| operations | `ope-*` | None — root sf-skills only |
| cloud | `cloud-*` | None — root sf-skills only. Split out of `ope-*` on 2026-07-11 (SmartFran Cloud multi-tenant App Services, Service Bus, franchise onboarding — distinct from `ope-azure`'s AADDS/VM/NSG scope). |
| itiano | `itiano-*` | None — root sf-skills only |

**Why:** Loyalty predates this architecture and was documented as having its own local copy. All newer projects (`sp-*`, `ope-*`, `cloud-*`, `itiano-*`) use only root sf-skills.

**How to apply:** When creating commands for any project other than loyalty, put them directly in root `.claude/commands/` with the correct prefix. Do not create a `.claude/commands/` subfolder inside the project directory. For loyalty, edits currently also go directly to root `.claude/commands/loyalty-*.md` until the local-dir discrepancy above is resolved.
