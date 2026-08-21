# Token Efficiency — CLAUDE.md and Commands (2026-08-13)

Audit scope: root `CLAUDE.md`, sub-project `CLAUDE.md` files, `.claude/commands/*.md` skills, and `memory/` — measured against the current Claude Code model's context window. Report only; see "Open Items" for changes not yet applied.

## Verdict

Not an urgent problem. The always-loaded footprint is small relative to Sonnet 5's context window (~200K tokens). The real waste is in a handful of concrete redundancies, not raw file size.

## Always-loaded per session (fixed cost)

| Component | Size | ~Tokens |
|---|---|---|
| root `CLAUDE.md` | 15.6 KB | ~3,900 |
| + heaviest sub-project `CLAUDE.md` (operations) | +8.7 KB | ~6,060 combined |
| `memory/MEMORY.md` (index only) | 5.7 KB | ~1,430 |
| **Floor (root + MEMORY.md)** | | **~5,300** |
| **Ceiling (root + operations + MEMORY.md)** | | **~7,500** |

That's ~2-4% of context — not worth trimming for its own sake. Individual `memory/*.md` files and skills load on-demand (`Read`/`Skill`), not by default, so they don't add to this fixed tax.

## On-demand cost (loaded in full when a skill fires)

Skills already use progressive disclosure correctly (only load when invoked), but a few are large enough to matter when stacked against a copy-pasted SQL/log payload in the same turn:

| Skill | Size | ~Tokens |
|---|---|---|
| `loyalty-fraud-points.md` | 37.6 KB | ~9,400 |
| `cloud-invalid-sale.md` | 21.6 KB | ~5,400 |
| `ops-aws.md` | 19.5 KB | ~4,900 |
| `ope-zabbix.md` | 16.4 KB | ~4,100 |

Not flagged as broken — just the ones where trimming would have the most leverage if ever needed.

## Redundancy found

1. **`operations/CLAUDE.md` (lines 80-85) vs `cloud/CLAUDE.md` (lines 36-41)** — near-verbatim duplicate block (events/ write-only, folder naming, `ops.md` section order, ops-events voice rules). `loyalty/CLAUDE.md` handles this correctly by pointing back to root `CLAUDE.md` → "Investigation Files"; operations and cloud don't. Candidate fix: promote the shared block to root `CLAUDE.md` once, replace both copies with a pointer.
2. **Root `CLAUDE.md` "Static Code Analysis Mode" section (~20 lines) vs `.claude/commands/sp-static-analysis.md`** — same rules stated twice (HIGH-confidence only, max 120 words/issue, `No critical defects detected.` fallback). The root copy is dead weight since the skill is the actual invocation path.
3. **`memory/feedback_events_voice.md` (13.5 KB) and `memory/feedback_no_run_recommendations.md` (7.9 KB)** — size outliers; most feedback memories run 1-4 KB. Worth a read-through since memory entries are meant to be a terse rule + why + how-to-apply, not an essay.

## Open Items

- **#1 applied (2026-08-13):** `operations/CLAUDE.md` and `cloud/CLAUDE.md` no longer restate folder-naming, `ops.md` section format/tense, or `ops-events.md` voice rules inline — both now point to root `CLAUDE.md` → "Investigation Files (cross-project)" (folder naming) and the `ope-sre-output` skill (ops.md/ops-events format, already the authoritative source both projects invoke). Project-specific bits (Spanish/English rule, write-only rule, script-file requirement) stayed local since they aren't universal across all four sub-projects (loyalty and smartpedidos use different `ops.md` formats).
- **#2 applied (2026-08-13):** removed the "Static Code Analysis Mode" section from root `CLAUDE.md` — confirmed no other file referenced it, and `.claude/commands/sp-static-analysis.md` already fully (and more specifically) covers the same rules.
- **#3 still open:** `memory/feedback_events_voice.md` (now larger still after 2026-08-18/19 additions) and `memory/feedback_no_run_recommendations.md` (7.9 KB) — size outliers vs. the 1-4 KB norm for feedback memories. Needs a read-through since trimming memory content is a judgment call, not a mechanical dedup. For `feedback_events_voice.md` specifically, the length is largely a recurrence log (12+ occurrences) that's arguably load-bearing evidence for why a mechanized check was needed (see `voice-check.md`, added 2026-08-19) — trimming it isn't a clear win, flag for a human read rather than auto-condensing.
- **#4 applied (2026-08-19):** `loyalty/CLAUDE.md` had the same inline `ops-events.md` template duplication #1 fixed elsewhere — missing the voice/tense rule entirely, unlike `loyalty-sre-output.md`'s fuller version. Now points to the skill, closing the gap that #1 left open for this one project.
