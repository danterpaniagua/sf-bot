# GITIN-1857 — Deuda Técnica

## Resumen

Epic de deuda técnica de SmartPedidos, cubriendo endurecimiento de Jenkins, actualización de dependencias, revisión de índices de MongoDB y trabajo de performance derivado. Los 12 subtareas están en estado terminal (Finalizada o Descartado) al 2026-09-17 — el epic está listo para cierre formal.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-1857](https://smartit-ar.atlassian.net/browse/GITIN-1857) |
| Alcance | Jenkins (Platform/Concentrador/BackOffice), dependencias (Axios/Tar), índices de MongoDB, Query Insights |
| Detectado | Épica preexistente; primer registro local 2026-09-04 |
| Resuelto | Sí (2026-09-17) — 12/12 subtareas en estado terminal |
| Responsable | Dante Paniagua (SRE) |

## Subtareas

| Ticket | Título | Estado | Detalle |
|---|---|---|---|
| [GITIN-1858](https://smartit-ar.atlassian.net/browse/GITIN-1858) | Correr Jenkins Platform | Finalizada | Aplicado y confirmado en ambos jobs (Platform y Concentrador) — toggle `RUN_BUGS_REPORT` (default `false`) y filtro de rama en el webhook. Ver `20260827_jenkins-bugreport-toggle-branch-filter/`. |
| [GITIN-1859](https://smartit-ar.atlassian.net/browse/GITIN-1859) | Correr Jenkins Concentrador | Descartado | Correctamente descartado — el trabajo real ya estaba cubierto por GITIN-1858 (ambos jobs se resolvieron juntos, no por separado). |
| [GITIN-2000](https://smartit-ar.atlassian.net/browse/GITIN-2000) | Concentrador: Upgrade Axios y Tar | Finalizada | Ver `20260908_gitin2000-axios-tar-upgrade/`. |
| [GITIN-2002](https://smartit-ar.atlassian.net/browse/GITIN-2002) | Platform: Upgrade Axios y Tar | Finalizada | Ver `20260908_gitin2002-platform-axios-tar-upgrade/`. |
| [GITIN-2006](https://smartit-ar.atlassian.net/browse/GITIN-2006) | Revisión índices de mongo | Finalizada | Ver `20260908_gitin2006-mongo-index-review/` — bloqueaba a GITIN-1744, ya resuelto. |
| [GITIN-2013](https://smartit-ar.atlassian.net/browse/GITIN-2013) | Query Insights: Slow queries | Finalizada | Ver `20260908_gitin2013-query-insights-slow-queries/` y su continuación `20260917_gitin2062_branches_index/`. Bloqueaba a GITIN-1744 (resuelto 2026-09-17); dos hallazgos quedan como deuda técnica de Dev, no bloquean el cierre. |
| [GITIN-2005](https://smartit-ar.atlassian.net/browse/GITIN-2005) | Bóveda | Descartado | Sin registro local — descartado directamente en Jira. |
| [GITIN-2011](https://smartit-ar.atlassian.net/browse/GITIN-2011) | Nueva Jenkinsfile solo para rama ope | Finalizada | Sin carpeta propia; referenciado como parte del mismo epic en `20260908_gitin2013-query-insights-slow-queries/investigation.md`. |
| [GITIN-2004](https://smartit-ar.atlassian.net/browse/GITIN-2004) | Graylog + alarmas | Descartado | Sin registro local — descartado directamente en Jira. |
| [GITIN-1957](https://smartit-ar.atlassian.net/browse/GITIN-1957) | Nuevo mensaje POST build a SmartPedidos team | Descartado | Nunca se construyó (confirmado 2026-09-04, sin registro local) — decisión de descartar, no de completar. |
| [GITIN-2023](https://smartit-ar.atlassian.net/browse/GITIN-2023) | Jenkins para BBOO | Finalizada | Ver `20260910_backoffice-jenkins-sonarqube-onboarding/ops-jenkins.md`. |
| [GITIN-2024](https://smartit-ar.atlassian.net/browse/GITIN-2024) | Sonarqube para BBOO | Finalizada | Ver `20260910_backoffice-jenkins-sonarqube-onboarding/ops-sonarqube.md`. |

## Hallazgos secundarios (deuda no bloqueante, heredada de subtareas)

- **GITIN-2013**: dos correcciones de código todavía a cargo de Dev, no confirmadas — método de conteo en `news.js` (`countDocuments()` → `estimatedDocumentCount()` para el caso sin filtro) y reordenamiento del pipeline `$lookup` en `branch.js` (aplicar el filtro de búsqueda antes de los `$lookup`, no después). Ninguna bloquea el cierre de este epic.
- **GITIN-2013**: patrón de `deleteMany()` sin batching en el trigger `clearCollection` (7 colecciones, secuencial, sin control de concurrencia) — flagueado, no accionado.
- **GITIN-2062** (bajo GITIN-2013): índice `branches.alreadyClosedRappi_1_lastGetNews_1` fue creado pero se confirmó vía `explain()` que el planner no lo usa — pendiente decidir si se elimina.

## Acciones propuestas

1. **(SRE)** — Cerrar formalmente GITIN-1857 en Jira — las 12 subtareas ya están en estado terminal.
2. **(Dev)** — Tomar los dos hallazgos de código pendientes de GITIN-2013 (ver Hallazgos secundarios) como items de backlog propio, si no lo son ya.
3. **(SRE)** — Decidir si eliminar el índice sin uso confirmado (`GITIN-2062`) o dejarlo, en caso de que otra consulta no identificada lo use.

## Archivos de evidencia

Este ticket consolida (no duplica) el trabajo detallado en cada subcarpeta listada en la tabla de Subtareas arriba.
