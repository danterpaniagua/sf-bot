# Memory Index

Repo-tracked, loyalty-specific project data — not an AI-memory store (that's the separate auto-memory system Claude Code maintains outside this repo; see root `CLAUDE.md` for the distinction). This folder holds fraud-investigation case knowledge that needs to be shared and versioned across sessions/machines, plus one architecture note referenced from root `CLAUDE.md`.

- [Known hubs](known_hubs.md) — confirmed aggregation/concentration accounts with CustomerId, DNI, creation date
- [Known relays](known_relays.md) — confirmed relay/feeder/pass-through accounts
- [Known POS actors](known_pos.md) — confirmed branches and franchise operators (accumulation + redemption), insider staff
- [Actor notes](actor_notes.md) — extended context for known fraud actors, keyed by DNI or branch Codigo
- [Commands architecture](project_commands_architecture.md) — all skills in root `.claude/commands/` with prefix; loyalty's local commands dir is documented but confirmed absent from disk (unresolved)

**2026-09-04 reconciliation:** this folder previously also held `feedback_output_language.md`, `feedback_always_propose.md`, `feedback_ticket_sql_queries.md`, and `reference_jira.md` — a second, drifted copy of content the auto-memory store (or `loyalty/CLAUDE.md` itself) already owned. Confirmed one real divergence (the language rule was missing a refinement the auto-memory copy already had) before deleting. `reference_jira.md`'s content (GITIN-1275, the root fraud epic) was genuinely unique and migrated to the auto-memory store rather than deleted. See root `CLAUDE.md`'s account of the same problem recurring at the repo root (deleted 2026-08-30) for why this class of duplication keeps getting cleaned up rather than reconciled in place.
