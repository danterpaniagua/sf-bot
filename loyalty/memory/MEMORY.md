# Memory Index

- [Output language rule](feedback_output_language.md) — English for all analysis/conversational output; Spanish only for events/ artifacts
- [Always propose](feedback_always_propose.md) — every output must include a concrete proposal or next step, not just information
- [Known hubs](known_hubs.md) — confirmed aggregation/concentration accounts with CustomerId, DNI, creation date
- [Known relays](known_relays.md) — confirmed relay/feeder/pass-through accounts
- [Known POS actors](known_pos.md) — confirmed branches and franchise operators (accumulation + redemption), insider staff
- [Actor notes](actor_notes.md) — extended context for known fraud actors, keyed by DNI or branch Codigo
- [JIRA reference](reference_jira.md) — JIRA project GITIN; GITIN-1275 = fraude 2026-06-04 epic
- [Ticket SQL queries format](feedback_ticket_sql_queries.md) — queries go in a separate .sql file; ticket references them with a brief description table
- [Commands architecture](project_commands_architecture.md) — all skills in root .claude/commands/ with prefix; only loyalty/ has a local commands dir
