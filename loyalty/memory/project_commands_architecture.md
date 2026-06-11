---
name: project-commands-architecture
description: All project skills live in root .claude/commands/ (sf-skills submodule) with a project prefix. Only loyalty/ has a local .claude/commands/ as source of truth.
metadata:
  type: project
---

**Rule:** Each project's skills belong in the root `bots/.claude/commands/` (sf-skills submodule), prefixed by project.

| Project | Prefix | Local commands dir |
|---|---|---|
| loyalty | `loyalty-*` | `loyalty/.claude/commands/` — source of truth; sf-skills is synced from it |
| smartpedidos | `sp-*` | None — root sf-skills only |
| operations | `ope-*` | None — root sf-skills only |
| itiano | `itiano-*` | None — root sf-skills only |

**Why:** Loyalty predates this architecture and has its own local copy. All newer projects use only root sf-skills.

**How to apply:** When creating commands for any project other than loyalty, put them directly in root `.claude/commands/` with the correct prefix. Do not create a `.claude/commands/` subfolder inside the project directory.
