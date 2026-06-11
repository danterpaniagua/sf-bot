# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working in this project.

## Project

Operations area — tracking and resolving infrastructure events: software upgrades, application bugs, and automation maintenance across the SmartFran platform stack.

Skills are defined in `.claude/commands/` — each has its own scope and instructions. **Skill-level instructions override this file.**

## Project Overview

The Operations area covers all non-database platform concerns: monitoring, deployments, pipeline health, containerised services, and automation scripts. Primary tools:

| Tool | Purpose |
|---|---|
| Zabbix 5 | Production monitoring — alerts, host availability, performance metrics |
| Zabbix 4 | Legacy monitoring instance |
| Graylog | Centralised log aggregation and search |
| Jenkins | CI/CD pipelines — build, deploy, automated jobs |
| Docker | Containerised services — compose stacks, image management |
| Bash / Python / PowerShell | Automation scripts and operational tooling |

## Directory Layout

- `docs/` — versioned reference documents: runbooks, tool configuration notes, upgrade procedures.
- `events/` — write-only artifact archive. Layout: `events/YYYYMMDD_description/`.
- `memory/` — persistent operational memory: known recurring issues, infrastructure state, service notes. Read at investigation start; update at close.

## Skills

Skills live in the `bots/` root `.claude/commands/` (sf-skills submodule) with the `ope-` prefix. Invoke from the `bots/` root context as `/ope-*`.

| Skill | Invocation | Scope |
|---|---|---|
| *(none yet)* | — | — |

## Global Restrictions

### Scope

- No direct database access. If a bug or upgrade requires DB investigation, coordinate with the loyalty project.
- Scripts and pipeline definitions are read for analysis only — never execute them directly unless the user explicitly runs them.

### Query / Command constraints

- Never generate destructive shell commands (`rm -rf`, `docker system prune`, force-stop services) unless explicitly requested.
- Always output commands as copy-paste blocks. The user runs them and pastes results back.

### Output

- All content written to `events/` must be in **Spanish**. All other conversational output in **English**.
- `events/` is **write-only** — do not read files from it unless explicitly asked.
- Each event gets its own subfolder: `events/YYYYMMDD_description/`. File names follow `YYYYMMDD_description_audience.ext`.
- All scripts or commands run during an investigation or fix must be saved as a script file in the event subfolder (`YYYYMMDD_description_scripts.sh` / `.py` / `.ps1` / `.sql`). The ticket body references the file with a brief description table (`#` | `Comando/Script` | `Propósito`) — no inline code blocks in the ticket body.
- Closure reports (`_ops.md`) must include: (1) summary table, (2) root cause, (3) actions taken with outcome. Actions section is titled **Acciones propuestas** — not "Acciones requeridas".

## Behavioral Guidelines

- No sycophantic openers or closing fluff.
- Always respond in English. Spanish only for content written to `events/`.
- Always propose a concrete next step — never end a response with only information and an open question.
- User instructions always override this file.
