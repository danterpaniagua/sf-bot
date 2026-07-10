# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working in this project.

## Project

Cloud area — tracking and resolving events related to Azure cloud services: Service Bus, CosmosDB, event-driven messaging, and cross-service integrations.

Skills are defined in the `bots/` root `.claude/commands/` (sf-skills submodule) with the `ope-` prefix. **Skill-level instructions override this file.**

## Directory Layout

- `events/` — write-only artifact archive. Layout: `events/YYYYMMDD_description/`.

## Skills

| Skill | Invocation | Scope |
|---|---|---|
| `ope-azure` | `/ope-azure` | Azure Monitor, Service Bus, NSGs, VMs, Action Groups |
| `ope-sre-output` | `/ope-sre-output` | Event artifacts: Jira tickets, closure reports, emails |

## Global Restrictions

### Query / Command constraints

- Always output commands as copy-paste blocks. The user runs them and pastes results back. Never tell the user to run a command — only provide the block.
- Never generate destructive commands unless explicitly requested.

### Output

- All content written to `events/` must be in **Spanish**. All other conversational output in **English**.
- `events/` is **write-only** — do not read files from it unless explicitly asked.
- Each event gets its own subfolder: `events/YYYYMMDD_description/`. File names follow `YYYYMMDD_description_audience.ext`.
- All scripts or commands run during an investigation must be saved as a script file in the event subfolder (`YYYYMMDD_description_scripts.sh`). The ticket body references the file with a brief description table (`#` | `Comando/Script` | `Propósito`) — no inline code blocks in the ticket body.
- Closure reports (`_ops.md`) are **Jira tickets describing work to be done** — write in future or imperative tense. Sections in order: **Resumen**, **Tabla resumen**, **Causa raíz**, **Hallazgos**, **Recursos afectados**, **Comandos ejecutados**, **Acciones propuestas**.
- Ops events file (`_ops-events.md`) entries use **pretérito perfecto impersonal, first person**: "se ha verificado", "se ha identificado". Never "el usuario" or "el operador".

## Behavioral Guidelines

- No sycophantic openers or closing fluff.
- Always respond in English. Spanish only for content written to `events/`.
- User instructions always override this file.
