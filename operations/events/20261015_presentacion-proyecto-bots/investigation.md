# Investigation — 20261015_presentacion-proyecto-bots

**Status:** in progress (outline only; audience and format not confirmed; nothing built)

## Request
User (2026-10-15): a presentation for the `bots` project ("I think we already have been working on something like that"). No Jira ticket.

## Is there an earlier presentation?
- No presentation file found in the repo (searched file names for pptx / presentation / slides / deck, the git log, the docs folder and the memory index). Closest material: `operations/events/20261014_monitoring-ai-alternatives/investigation.md` (this setup vs AI monitoring products; guardrails; limits), `docs/token_efficiency.md`, `.claude/commands/README.md`, and `docs/roles_infra_pm.html` (a role explainer, not about the bots).

## Statements by the user to use in the presentation (reported, not verified)
- Why investigation files exist: multitask across several projects, daily requests that interrupt the current work, and priorities that change (a new task can outrank the one in progress); the file keeps each task's state so it can be resumed.
- Cost: the daily work (not only alerting) can be done with a USD 20 subscription and the current Claude model; the same subscription is used for personal projects. Details given later: model Sonnet 5.5, starter Claude plan, USD 20. A web search (third-party blogs, not Anthropic's page) gave: Pro USD 20 monthly or about USD 17 annual, Claude Code included, limits not published (rolling 5-hour window). Whether the limits cover the real load was not measured.
- Check before presenting: if it is a personal plan, work data goes through a personal account; the plan's terms for work use and the company's data rules were not checked.

## Facts from the repo (2026-10-15)
- 37 skills in `.claude/commands/` (excluding the README); 4 sub-projects with 61 (loyalty), 53 (smartpedidos), 41 (operations), 54 (cloud) event folders = 209 before today's new ones; 59 memory files; 4 hook scripts in `.claude/hooks/` (3 guards plus the no-op blocker); first commit 2026-06-02 (28 commits in the root repo).
- Guard hooks: installed 2026-10-14 (`guard_mutating_cli.py`, `guard_secrets_in_writes.py`, `banner_guard.py`), 81 local test cases passing; the Stop hook was not exercised live; whether they apply from a sub-project was not verified (monitoring-ai-alternatives investigation).

## Draft outline (about 11 slides, Spanish)
1 What it is; 2 Why it exists; 3 The investigation file; 4 How it works (user runs, bot reads and writes, evidence in `data/`); 5 Skills by area; 6 Guardrails; 7 Cases of the week (GITIN-2222, GITIN-2229, GITIN-2236); 8 Versus an AI monitoring product (stronger: depth and own code; weaker: detection, unattended work, speed); 9 Limits and own errors (masking error, wrong SanitizeHeaders date); 10 Numbers; 11 Cost (USD 20 plan vs vendor list prices, labelled as reported and not like-for-like); 12 What's next.

## Open
- Audience (team, PM and directors, outside), format (local HTML deck or .pptx), edits to the outline.
- Whether to include the cost slide and how to word the personal-plan point.

## Update 2026-10-15 (afternoon): material for the "cases" and "limits" slides
- Case: the Mobile outage reported by Grido (after the healthcheck file was removed) and the lack of any alert led to GITIN-2238/GITIN-2239; the same day the review of the ECS alert showed events created but never delivered (an unresolved margin macro and, as hypothesis, missing read permission of the recipient on the AWS host group). Useful as an example of "an alert existing is not the same as an alert arriving" for the limits slide.
- Own errors worth showing honestly: the first run of several read-only scripts returned empty results because of API details (`webitems` flag, quoted web-item keys, `selectRights` in Zabbix 6.0, AWS CLI offsets); each was found from the saved output.
