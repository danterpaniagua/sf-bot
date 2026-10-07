# GITIN-2088 — [OPE] Tareas de Mantenimiento

**Tags:** SmartLoyalty, SmartFran Cloud, Azure, SQL Server, SSL, SRE, PROD, Mantenimiento

## Resumen

Ticket agregador, multi-proyecto, que agrupa varias tareas de mantenimiento completadas en una misma sesión de trabajo (2026-09-22): reprogramación y optimización del job de mantenimiento de índices de SmartLoyalty (`PNSSRL_MantenimientoIndices`), confirmación de cobertura de índices nuevos, evaluación y descarte de un particionado propuesto, y automatización completa de renovación SSL para el sitio WebSite (`gestion.clubgrido.com.ar`). Cada ítem tiene su propio evento completo con el detalle técnico — este ticket no duplica ese contenido, lo resume y referencia.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2088](https://smartit-ar.atlassian.net/browse/GITIN-2088) |
| Sistema | Multi-proyecto — SmartLoyalty SQL Server (`SFCG-DB01`) y SmartFran Cloud/Azure (`WAF_APPs`, `SFCG-WSIT-01`) |
| Severidad | Media — mantenimiento proactivo y correctivo, sin incidente activo al momento del trabajo |
| Detectado | N/A — trabajo proactivo, ítems acumulados en un TODO informal antes de formalizarse bajo este ticket |
| Resuelto | 2026-09-22 |
| Responsable | Dante Paniagua |

## Causa raíz

No aplica de forma unificada — cada ítem agregado tiene su propia causa raíz, documentada en su ticket y evento correspondiente (ver Hallazgos).

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | [GITIN-2060](https://smartit-ar.atlassian.net/browse/GITIN-2060) — Reprogramación de `PNSSRL_MantenimientoIndices`: de 06:15 UTC diario a un esquema semanal que evita por completo los días de `Backup_FULL` (domingo/martes/jueves/sábado para el job de índices, lunes/miércoles/viernes para el backup — espaciado parejo, sin días consecutivos). **Chequeo post-cierre**: se verificó que el nuevo horario no genera solapamiento nuevo con el trabajo de TaskOperatorService — el motor de campañas (`Sch.Job`) no tiene jobs semanales activos actualmente, y la única interacción real encontrada (la sincronización ETL de `dbo.CustomerPointsLog`, crónicamente lenta, 3-6h diarias) es preexistente y no cambia con este ticket, ya que esa tarea corre los 7 días sin importar cuáles 3 ocupa `Backup_FULL`. Detalle completo en `loyalty/events/20260922_gitin2060-mantenimientoindices-reschedule/` | Alto (resuelto — corregía un riesgo de bloqueo con 3 incidentes previos confirmados) |
| H2 | [GITIN-2061](https://smartit-ar.atlassian.net/browse/GITIN-2061) — Rebuild de `IX_CustomerId` sobre `Sml.CustomerPointsLog` acotado a la partición activa mediante un job nuevo y separado; el mecanismo de exclusión del job viejo requirió una corrección adicional (`habilitado=0`) no prevista en el diseño original | Alto (resuelto) |
| H3 | [GITIN-2078](https://smartit-ar.atlassian.net/browse/GITIN-2078) — Confirmado que los nuevos índices de `CustomerAdditionalInformation` se cubren automáticamente por el job de mantenimiento existente, sin necesidad de cambio de configuración | Informativo (no-issue confirmado) |
| H4 | [GITIN-2077](https://smartit-ar.atlassian.net/browse/GITIN-2077) — Particionado de `CustomerAdditionalInformation` diseñado por completo pero descartado tras reevaluar riesgo/beneficio: alto riesgo de ejecución (triggers de doble escritura sobre una tabla de un hot path de checkout POS) contra un beneficio especulativo y sin fecha concreta | Bajo (deuda técnica documentada, no un riesgo activo) |
| H5 | [GITIN-1771](https://smartit-ar.atlassian.net/browse/GITIN-1771) — Automatización SSL completa para WebSite (ambos tramos, público y backend), con dos riesgos reales detectados y corregidos durante la ejecución (ver el evento correspondiente para detalle) | Media (resuelto) |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| `SFCG-DB01` | Host SQL Server — jobs de mantenimiento de índices reprogramados/optimizados |
| `SmartFran-Cloud-Sales-PRO` | No afectado por este ticket — ver [GITIN-2075](https://smartit-ar.atlassian.net/browse/GITIN-2075), explícitamente fuera de este agregador (aún sin resolver) |
| `WAF_APPs` / `SFCG-WSIT-01` | Automatización SSL de WebSite |

## Comandos ejecutados

No aplica directamente a este ticket agregador — cada ítem tiene su propio detalle de comandos en su evento local correspondiente (ver Hallazgos para los links a cada ticket Jira; el detalle técnico completo, incluyendo todos los comandos ejecutados, vive en los eventos locales de cada uno, no reproducido acá).

## Acciones propuestas

1. **(SRE) Completado** — Los cinco ítems agregados (H1-H5) están cerrados y verificados en sus respectivos tickets/eventos.
2. **(SRE) Pendiente, explícitamente fuera de este ticket** — [GITIN-2075](https://smartit-ar.atlassian.net/browse/GITIN-2075) (caídas por OOM en Sales-PRO) sigue sin resolver — mecanismo de reversión de `use32BitWorkerProcess` no confirmado, corrección aún no aplicada en producción. Seguimiento propio, no parte de este agregador.

## Hallazgos secundarios

Durante el trabajo de GITIN-1771 se detectó un nodo del backend de ClubSite AR (`192.168.50.122`) en estado `Unhealthy` — no relacionado, señalado en el evento de GITIN-1771, no investigado bajo este ticket.
