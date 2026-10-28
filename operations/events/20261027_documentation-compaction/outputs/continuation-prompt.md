Continue the documentation compaction + consistency check.

Start by reading `/home/dpaniagua/Documentos/git/bots/operations/events/20261027_documentation-compaction/investigation.md` (decisions, done list, method rules, open inconsistencies, validation plan). Do not re-derive what is already there.

Goal: compact every `docs/` file (root, loyalty, smartpedidos, operations, cloud) so they work as context for an SRE + Infrastructure + DBA session.

Success criterion: after compaction, the docs alone must be enough to solve the issues already solved in `events/`. Example: working in cloud, the resulting docs must let us solve problems we already solved. A compaction that loses a fact an old event needed is a failure.

Constraints:
- Compact in place; no digests, no new `@import` lines beyond the 4 already added.
- English outside `events/`. Docs already in Spanish keep their language.
- Never edit `cloud/docs/devs-log-structure.md` (dev-authored). Ask me if another doc is not ours.
- Remove change history (corrections, "updated/added/fixed on <date>", "previously X") in `docs/` only; keep verification dates and keep incident narratives in CLAUDE.md files.
- Keep facts, rules, pitfalls, open gaps and event-folder pointers; drop narrative of how something was found. When unsure, keep the fact.
- Carry forward unreconciled figures with their flag; do not present them as settled.
- Git state changes (add, commit, rm, checkout) are mine to run: give me the command.

Next steps, in order:
1. Compact `docs/zabbix_observability.md`, then `loyalty/docs/infrastructure.md`, then `smartpedidos/docs/infrastructure.md`, then the `operations/docs/` runbooks (`sonarqube_upgrade_runbook.md` reads as an upgrade log).
2. After each project, run the validation plan in the investigation: pick 3-5 solved events, list the facts each needed, check the compacted docs still contain them, record gaps and restore them.
3. Run the consistency pass: contradictions between docs (Backup_FULL days, Graylog `*-http` sizes, and others listed in the investigation), and a check that every backticked path in the docs and CLAUDE.md files exists.
4. Keep `investigation.md` current after each doc (it is the resume point; a hook blocks compaction otherwise).

Report findings and a firm recommendation at the end of each step, no closing question.
