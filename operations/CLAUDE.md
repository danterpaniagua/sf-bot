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
- `../docs/` — cross-project shared references. See `../docs/azure_nsg.md` for Azure NSG inventory, VNet topology, AADDS DC IPs, and CLI patterns.
- `events/` — write-only artifact archive. Layout: `events/YYYYMMDD_description/`.
- `memory/` — persistent operational memory: known recurring issues, infrastructure state, service notes. Read at investigation start; update at close.

## Skills

Skills live in the `bots/` root `.claude/commands/` (sf-skills submodule) with the `ope-` prefix. Invoke from the `bots/` root context as `/ope-*`.

| Skill | Invocation | Scope |
|---|---|---|
| `ope-azure` | `/ope-azure` | Azure AD DS health/alerts, Kerberos policy, VMs, NSGs, Monitor |
| `ope-aws` | `/ope-aws` | EC2, SQS, CloudWatch, IAM review, ECS, Fargate, ALB/NLB |
| `ope-zabbix` | `/ope-zabbix` | Custom healthcheck-to-Zabbix integration: UserParameter items, macros, triggers, alert routing |
| `ope-sre-output` | `/ope-sre-output` | Event artifacts: Jira tickets, closure reports, emails |

## Global Restrictions

### Scope

- No direct database access. If a bug or upgrade requires DB investigation, coordinate with the loyalty project.
- Scripts and pipeline definitions are read for analysis only — never execute them directly unless the user explicitly runs them.

### Query / Command constraints

- Never generate destructive shell commands (`rm -rf`, `docker system prune`, force-stop services) unless explicitly requested.
- Always output commands as copy-paste blocks. The user runs them and pastes results back. Never tell the user to run a command — only provide the block.

### Output

- All content written to `events/` must be in **Spanish**. All other conversational output in **English**.
- `events/` is **write-only** — do not read files from it unless explicitly asked.
- Each event gets its own subfolder: `events/YYYYMMDD_description/`. File names follow `YYYYMMDD_description_audience.ext`.
- All scripts or commands run during an investigation or fix must be saved as a script file in the event subfolder (`YYYYMMDD_description_scripts.sh` / `.py` / `.ps1` / `.sql`). The ticket body references the file with a brief description table (`#` | `Comando/Script` | `Propósito`) — no inline code blocks in the ticket body.
- Closure reports (`_ops.md`) are **Jira tickets describing work to be done** — write in future or imperative tense. Findings describe current state; actions describe what must happen. Never write as if remediation is already complete. Sections in order: **Resumen**, **Tabla resumen**, **Causa raíz**, **Hallazgos**, **Recursos afectados**, **Comandos ejecutados**, **Acciones propuestas**, **Hallazgos secundarios** (optional). Actions section is titled **Acciones propuestas** — not "Acciones requeridas".
- Ops events file (`_ops-events.md`) entries use **pretérito perfecto, first person**: "he verificado", "he identificado", "he confirmado". Yo soy quien ejecuta — never refer to the author as "el usuario", "el operador", or any third-person subject, and never use the impersonal "se ha..." construction.

### Ops Events File (`_ops-events.md`)

Every event produces a `_ops-events.md` file alongside the ticket. Append-only work journal — each entry records what was run, when, and what it returned. Never edit past entries.

**Before writing any command output or new finding to any file, ask the user:**
> ¿Lo registro como actividad (`_ops-events.md`) o actualizo el ticket (`_ops.md`)?

Entry format (`YYYYMMDD_description_ops-events.md`):

```
# Eventos — <event description>

## YYYY-MM-DD HH:MM — <short label>

**Comando:** CX — <name>
**Resultado:**
<output>

<paragraph, first-person pretérito perfecto, no bold label — interpretation of the result>
```

Omit the `**Comando:**` line when the entry documents a manual step (frontend configuration, UI walkthrough) rather than an actual command or script run — go straight from the heading to `**Resultado:**`. Only include `**Comando:**` when a real command/script was executed. The interpretation paragraph is plain text, not labeled `**Observación:**` — a normal paragraph, not necessarily one line.

Command output results are also recorded as commented `# OUTPUT (YYYY-MM-DD):` blocks in the scripts file immediately below the executed command.

## Behavioral Guidelines

- No sycophantic openers or closing fluff.
- Always respond in English. Spanish only for content written to `events/`.
- Always propose a concrete next step — never end a response with only information and an open question.
- User instructions always override this file.
- Never add `Co-Authored-By` to commit messages. All commits must be authored solely by the user.
