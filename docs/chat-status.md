# Chat status

The only status file for continuing a chat: overwrite it, do not create dated copies. To resume after `/clear`, read this file first, then the `investigation.md` of the event you pick up.

**Last update:** 2026-10-19, about 13:00 (-03:00). Built from the chat context only; no event folder was re-checked. Window: the chat since `/clear`, 8 events. Jira: GITIN-2251 (child of 2250), 2248, 2236, 2201; the Zabbix web scenarios doc and the Loyalty roadmap have no ticket yet. "Unverified" lists what only the user said or was not checked.

## Events

| Event | Status | Done / verified | Unverified | Next |
|---|---|---|---|---|
| Push blocked by secrets | Done (verified) | Pushed; HEAD equals the remote ref; 3 conf files untracked | Remote ref not fetched now | - |
| GITIN-2248 H3 | Investigating | Dips: 0-3 min/day to 10-12, 66 on 10-13 (rev 271); fix 643d17f | Rev 275 holds the fix; effect tonight | Re-check C7 tomorrow morning |
| DB check, same window (2251) | Investigating | Q1-Q15 run; no blocking, no bulk insert | Cause of the 97 s CPU unknown | Decide on Query Store |
| Loyalty roadmap (point queue) | Drafted | Story 1 with tasks a-h written; no ticket for now | Whether Mobile writes points | Further analysis of batch writers |
| Zabbix web scenarios doc | Done (user-stated) | Pull read: 16 scenarios, 37 steps; docs read and sent | Guide not checked row by row; no ticket for now | - |
| SmartPedidos roadmap (2236) | Drafted | Table final; CSV 48 rows; sheet linked | Sheet not compared with the CSV | Update the roadmap file |
| Fiscal bill demo (2201) | Done (user-stated) | LaTeX ticket built; PDF 12 cm, 110 KB | Unit read as cm; QR not validated | - |
| Context files and investigations | Done | CLAUDE.md edited in 4 projects; investigations updated | Not checked with `/doc-audit` | Commit when you decide |

## Needs you now

| Order | Item | Why it matters |
|---|---|---|
| 1 | Re-pull C7 tomorrow morning for GITIN-2248 | Evening and night hours of 10-19 test the fix |

## Where to resume (paths from the repo root `bots/`)

| Event | Folder or file |
|---|---|
| Push blocked by secrets | repo root; the remote is named `dpaniagua-gh` (not `origin`; `origin/main` is a stale ref); the three `...azure-eventhub-to-graylog*.conf` files stay local under `cloud/events/20260914_gitin2034-timetaken-elapsedms-promotion/data/` and are git-ignored |
| GITIN-2248 | `smartpedidos/events/20261017_gitin2248-platform-contenedores-caidos-20261016/` (section "Origin of the exit handlers") |
| DB check (2251) | `loyalty/events/20261018_gitin2251-webs-db-misma-ventana/` (`scripts/scripts.sql` has Q1-Q15, `data/` the outputs) |
| Loyalty roadmap | `loyalty/events/20261019_roadmap-loyalty/` |
| Zabbix web scenarios | `operations/events/20261019_zabbix-web-scenarios-doc/`, `docs/zabbix_web_scenarios.md`, `outputs/guia_qa_despliegue.md` |
| SmartPedidos roadmap (2236) | `smartpedidos/events/20261015_gitin2236-roadmap-smartpedidos/outputs/` (table, CSV; `scripts/tabla-a-csv.py`, `scripts/atomizar-tabla.py`) |
| Fiscal bill demo (2201) | `cloud/events/20261013_gitin2201-evaluar-proveedor-correos/outputs/factura-demo/` (`datos/`, `render.py`, `plantilla-factura.tex`, `build/`) |
| `summary-report` skill | `.claude/commands/summary-report.md` |

## Decisions and assumptions to carry

| Item | State |
|---|---|
| Sub-row ids in the roadmap table | Letters (1.a, 1.b), because Excel turns 1.1 into a date |
| CSV of the roadmap | UTF-8 with BOM, comma separator; regenerate after any table change |
| Roadmap priorities and estimates | Estimate only on the story row; sub-rows inherit the priority |
| Fiscal bill demo | Closed by the user; data invented, layout follows a printed ticket, no real taxpayer data copied; the 12 cm width was read from "12mm" and never confirmed |
| `ops.md` of any event | Written once at convergence; not written for 2251 |
| Commit authors | Names only in conversation, never in `events/` files |
| Jira tickets for the Zabbix doc and the Loyalty roadmap | None for now (user decision); folders keep no ticket id |
| Batch writers in the Loyalty point queue | Further analysis (user decision); not decided |

Disagreements: none found.

Next: re-pull C7 for GITIN-2248 tomorrow morning.
