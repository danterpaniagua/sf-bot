# Token Efficiency — CLAUDE.md and Commands

Audit scope: root `CLAUDE.md`, sub-project `CLAUDE.md` files and their imports, `.claude/commands/*.md` skills, and the auto-memory index. Measured 2026-10-28 from file sizes and from `/context` of a session started at the `bots/` root (700K auto-compact window, model Sonnet 5.5). Token figures use **2.7 bytes per token**, measured on the root `CLAUDE.md` (34,073 B = 12.3K tokens in `/context`); an estimate of 4 bytes per token undercounts these Spanish-and-code files by a third.

## Verdict

Not urgent against a 700K window, but the fixed cost has tripled since the 2026-08-13 audit and is now mostly incident narrative in the root `CLAUDE.md`. Against a 200K window the same fixed cost would be 12-13 %.

## Always-loaded per session (fixed cost)

Measured in `/context` at the `bots/` root, before any message:

| Component | Tokens |
|---|---|
| System prompt | 2.8K |
| System tools (the rest, about 27K, are deferred and load on demand) | 17.2K |
| Skills list (72 skills, descriptions only) | 6.6K |
| MCP server instructions | 0.7K |
| Root `CLAUDE.md` (34.1 KB) | 12.3K |
| Imported `docs/tags.md` (3.0 KB) | 1.4K |
| Auto-memory index `MEMORY.md` (13.7 KB, 70 lines) | 5.4K |
| **Total** | **about 46K (6.6 % of 700K)** |

Memory files (root `CLAUDE.md`, `tags.md`, `MEMORY.md`) are 19.2K of that. Working from a sub-project adds its own `CLAUDE.md` and its imported alert matrix (estimated at 2.7 bytes per token):

| Sub-project | `CLAUDE.md` | Imported `docs/zabbix_alert_matrix.md` | Added |
|---|---|---|---|
| `cloud/` | 13.6 KB, ~5.0K | none | ~5.0K |
| `loyalty/` | 11.7 KB, ~4.3K | 4.4 KB, ~1.6K | ~5.9K |
| `operations/` | 13.1 KB, ~4.8K | 2.8 KB, ~1.0K | ~5.8K |
| `smartpedidos/` | 14.3 KB, ~5.3K | 1.8 KB, ~0.7K | ~6.0K |

So the fixed cost from a sub-project is about 52K tokens (7.5 % of 700K). Only these four small imports exist by decision (`CLAUDE.md` → "Imported Reference"); every other doc is read on demand and costs nothing until opened.

## What changed since 2026-08-13

| Item | 2026-08-13 | 2026-10-28 |
|---|---|---|
| Root `CLAUDE.md` | 15.6 KB | 34.1 KB (incident narratives and "Why:" blocks kept on purpose; the history cleanup applies to `docs/` only) |
| `MEMORY.md` (index) | 5.7 KB | 13.7 KB, 70 lines, 7 lines over 250 characters (the longest 414) |
| Operations `CLAUDE.md` | 8.7 KB | 13.1 KB |
| Imports | none | `docs/tags.md` plus three alert matrices (snapshots of 2026-10-18) |

## On-demand cost (loaded in full when a skill fires)

| Skill | Size | ~Tokens |
|---|---|---|
| `loyalty-fraud-points.md` | 37.6 KB | ~13.9K |
| `ope-zabbix.md` | 24.4 KB | ~9.0K |
| `ops-aws.md` | 23.1 KB | ~8.5K |
| `cloud-invalid-sale.md` | 20.4 KB | ~7.6K (was 25.8 KB before compaction, 21.6 KB at the first audit) |
| `ope-sre-output.md`, `sp-sre-output.md`, `loyalty-sre-output.md` | 14.5-15.0 KB each | ~5.4-5.6K |
| `cloud-azure.md` | 12.6 KB | ~4.7K |

Skills use progressive disclosure correctly (they load only when invoked); the large ones matter when stacked against a pasted SQL or log payload in the same turn. Not broken, just the ones where trimming has the most leverage.

## Redundancy and open items

1. **Root `CLAUDE.md` is the biggest lever** (12.3K, 27 % of the fixed cost). Most of it is dated incident narrative that explains why a rule exists. Keeping it is a decision (memory `keep-incident-narratives`); trimming it, or moving the narratives to a doc read on demand, would save roughly half of it, and a `CLAUDE.md` changes only on the user's request.
2. **`MEMORY.md` is an index, not a store**: 13.7 KB over 70 lines means many entries carry the rule itself. One line of about 150 characters per entry would take it to roughly 8 KB. Needs a human read: trimming memory content is a judgment call.
3. **`feedback_events_voice.md` (19.4 KB) and `feedback_no_run_recommendations.md` (8.2 KB)** remain size outliers (most feedback memories run 0.75-4 KB). They load on demand, not every session.
4. **Alert-matrix imports are snapshots** of 2026-10-18: each session pays for them whether or not the task touches alerts, and they age. Candidates to turn into a read-on-demand pointer if the budget matters.

Sub-project `CLAUDE.md` files point to root `CLAUDE.md` → "Investigation Files (cross-project)" for folder naming and to the `*-sre-output` skills for `ops.md`/`ops-events.md` format and voice; keep it that way rather than restating those rules inline (loyalty and smartpedidos use different `ops.md` formats, so only project-specific bits stay local).
