# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Investigation of database events on the SmartLoyalty SQL Server instance (`SFCG-DB01`). Engine: Microsoft SQL Server 2022 Standard, 64-bit, version 16.0.4075.1, on Windows Server 2022 Datacenter. Skills are defined in `.claude/commands/` — each has its own scope and instructions. **Skill-level instructions override this file.**

## Project Overview

**Smart Loyalty** is a loyalty and delivery platform operated by Smartfran, serving **Club Grido** (ice cream franchise) and its franchise network across Argentina, Paraguay, and other Latin American countries. The platform manages loyalty points, promotions, and redemptions for a large network of Points of Sale (PDVs).

## Directory Layout

- `.claude/commands/` — skills (unprefixed); this is the **source of truth**. Invoked as `/fraud-points`, `/fraud-pos`, `/dba-investigation`, `/sre-output`, `/azure-nsg`. When working from the `bots/` root, the same skills are available as `/loyalty-*` via the sf-skills submodule — but edits always go here first.
- `queries/` — reference SQL for `PNSSRL`.
- `events/` — write-only artifact archive. Layout: `events/YYYYMMDD_description/`.
- `memory/` — persistent fraud actor memory: `known_hubs.md`, `known_relays.md`, `known_pos.md`, `actor_notes.md`. Read at investigation start; update at close.
- `docs/` — versioned skill reference documents.

## Global Restrictions

### Database scope

- **`PNSSRL`** — monitoring database. Default target for DBA investigation queries.
- **`SmartFran.Solution.SmartLoyalty`** — production database. Do not query it unless explicitly requested or active within a skill that grants implicit access (e.g. `fraud-points`).

### Query constraints

- **Read-only.** Never generate DML (`INSERT`, `UPDATE`, `DELETE`, `MERGE`) or DDL (`CREATE`, `ALTER`, `DROP`, `TRUNCATE`) against any database.
- **Temp tables** require explicit user approval. Default to CTEs.
- **Execution model:** never run queries directly. Output them as copy-paste blocks; the user runs them on the server and pastes results back.

### Output

- All content written to `events/` must be in **Spanish**. All other conversational output by Claude (analysis, queries, findings) in **English**. Email and ticket artifacts produced as skill outputs follow the audience's language (typically Spanish for PM/client-facing content).
- `events/` is **write-only** — do not read files from it unless explicitly asked.
- Each event or issue gets its own subfolder: `events/YYYYMMDD_description/`. File names inside follow `YYYYMMDD_description_audience.ext`.
- Operations Jira tickets must include full query text saved as a `.sql` file in the event subfolder, referenced by filename in the ticket body. Source columns: `PNSSRL_AuditSysprocesses.comando_ejecutado`, `PNSSRL_TempdbProc.Query_Text`.
- Closure reports (`_ops.md`) must include: (1) summary metrics table, (2) EventTypeCode breakdown (EventTypeCode | Eventos | Puntos), (3) participant detail (Cliente | Documento | EventTypeCode | Transacciones | Puntos) for the reported window. Actions section is titled **Acciones propuestas** — not "Acciones requeridas".

### Server timezone

SQL Server runs on **GMT (UTC+0)**. Captured timestamps (`hora_captura`, `fecha_hora_captura`) are GMT. User's local timezone defaults to **UTC-3**.

## Behavioral Guidelines

- No sycophantic openers or closing fluff.
- Always respond in English. Spanish only for content written to `events/`.
- Always propose a concrete next step — never end a response with only information and an open question.
- User instructions always override this file.
