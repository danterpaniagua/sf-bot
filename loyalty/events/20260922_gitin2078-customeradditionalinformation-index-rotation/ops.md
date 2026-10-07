# GITIN-2078 — Cobertura de mantenimiento para los nuevos índices de CustomerAdditionalInformation

**Tags:** SmartLoyalty, PNSSRL, Mantenimiento, PROD, SRE

## Resumen

`IX_CustomerAdditionalInformation_CardNumber` e `IX_CustomerAdditionalInformation_UidCode_UidSerie` se crearon el 2026-09-21 sobre `SmlSt.CustomerAdditionalInformation` (GITIN-2074) fuera del ciclo normal del job de mantenimiento de índices, generando la duda de si algo asegura su mantenimiento futuro. El análisis encontró que la tabla ya está registrada y habilitada en la tabla de control desde 2024, y que el mecanismo del job enumera índices de forma dinámica por tabla (no una lista fija) — evidencia directa, no inferida, para esta misma tabla. **Todavía no se confirma el resultado real**, porque el job no corrió desde que se crearon los índices nuevos.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | GITIN-2078 (subtarea de GITIN-2074) |
| Sistema | SmartLoyalty SQL Server (`PNSSRL` / `SmartFran.Solution.SmartLoyalty`) — `SFCG-DB01` |
| Severidad | Baja — probable no-issue, pendiente de una única confirmación |
| Detectado | N/A — duda planteada al crear los índices el 2026-09-21 |
| Resuelto | 2026-09-22 — confirmado no-issue |
| Responsable | Dante Paniagua |

## Causa raíz

No aplica todavía — el hallazgo hasta ahora indica que no hay una causa raíz que corregir, sino una premisa (falta de cobertura) que los datos no confirman.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | `SmlSt.CustomerAdditionalInformation` confirmada registrada en `PNSSRL_TablasModulos` (`id_tablas_modulos=479`) desde 2024-05-01, con `indexado=1, defragmentacion=1, habilitado=1` — la tabla siempre estuvo cubierta por el job diario | Informativo |
| H2 | Log de ejecución (`PNSSRL_DetallesEjecucionTablasModulos`, últimas 20 corridas) muestra exactamente 2 filas por corrida, una por cada uno de los 2 índices actuales de la tabla (`PK__Customer__3214EC074846ACB8`, siempre reorganize por baja fragmentación ~5%; `IX_CustomerAdditionalInformation_CustomerId`, siempre rebuild por fragmentación diaria 90-97%) — evidencia directa de enumeración dinámica por índice para esta tabla puntual, no una lista fija | Informativo |
| H3 | **Confirmado (2026-09-22).** Corrida manual de validación (03:58:59-05:10:32, 72 min total) alcanzó `id_tablas_modulos=479` a las 05:05:17 — el log muestra 4 filas, no 2: `IX_CustomerAdditionalInformation_CardNumber` e `IX_CustomerAdditionalInformation_UidCode_UidSerie` aparecen por nombre, ambos con `REBUILD` real (fragmentación 83%/84%, esperable para índices recién creados sin mantenimiento previo). Ningún cambio de configuración fue necesario | Informativo (confirmado) |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| `SmlSt.CustomerAdditionalInformation` (`SmartFran.Solution.SmartLoyalty`) | Tabla cuyos 2 índices nuevos están en duda de cobertura |
| `PNSSRL_TablasModulos` (`PNSSRL`) | Tabla de control — confirmada sin necesidad de cambio, fila 479 ya habilitada |

## Comandos ejecutados

| # | Query | Propósito |
|---|---|---|
| 1 | `INFORMATION_SCHEMA.COLUMNS` sobre `PNSSRL_TablasModulos` | Confirmar nombres reales de columnas |
| 2 | `SELECT * FROM PNSSRL_TablasModulos WHERE tabla LIKE '%CustomerAdditionalInformation%'` | Confirmar registro y estado de la fila de la tabla |
| 3 | `SELECT TOP 20 * FROM PNSSRL_DetallesEjecucionTablasModulos WHERE id_tablas_modulos = 479 ORDER BY fecha_hora_captura DESC` | Confirmar mecanismo de enumeración de índices por corrida |

Salida cruda persistida en `data/tablasmodulos_schema_and_row_20260922.txt` y `data/tablasmodulos_execution_log_id479_20260922.txt`.

## Acciones propuestas

1. **(SRE) Completado** — Confirmado vía corrida real (2026-09-22): 4 filas en el log para `id_tablas_modulos=479`, ambos índices nuevos cubiertos automáticamente. Cerrado como no-issue.
2. **(SRE) No aplica** — Ningún cambio en `PNSSRL_TablasModulos` ni nuevo job fue necesario.

## Hallazgos secundarios

Ninguno.
