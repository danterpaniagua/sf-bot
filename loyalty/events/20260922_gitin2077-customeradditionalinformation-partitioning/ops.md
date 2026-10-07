# GITIN-2077 — Particionado de SmlSt.CustomerAdditionalInformation

**Tags:** SmartLoyalty, PNSSRL, Mantenimiento, PROD, SRE

## Resumen

Se evaluó particionar `SmlSt.CustomerAdditionalInformation` (~4.9M filas, `SmartFran.Solution.SmartLoyalty`) ante el crecimiento proyectado de la red de franquicias (~200 a ~2600, 13x), bajo la premisa de que esta tabla escala proporcionalmente. El diseño técnico se completó por completo (partición por hash de `CustomerId`, `N=16`, migración vía tabla sombra + backfill + triggers de doble escritura + corte con `sp_rename`), pero **se decidió no ejecutar la migración tras reevaluar riesgo vs. beneficio**: el costo real de mantenimiento hoy es bajo (~3,5 minutos diarios) y la tabla tiene un patrón de escritura y perfil de consumo estructuralmente distinto al de `Sml.CustomerPointsLog` (que sí justificó GITIN-2060/2061). El riesgo de ejecución de la migración (triggers de doble escritura sobre una tabla del hot path de checkout POS, corte en vivo) se consideró alto frente a un beneficio especulativo y sin fecha concreta.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | GITIN-2077 (subtarea de GITIN-2074; precedente: GITIN-1267) |
| Sistema | SmartLoyalty SQL Server (`SmartFran.Solution.SmartLoyalty`) — `SFCG-DB01` |
| Severidad | Baja — deuda técnica identificada, no un riesgo activo confirmado |
| Detectado | N/A — propuesto como subtarea de GITIN-2074 (2026-09-20) |
| Resuelto | 2026-09-22 — descartado (alto riesgo, bajo beneficio actual), diseño documentado para retomar si cambia la señal |
| Responsable | Dante Paniagua |

## Causa raíz

No aplica — no hay un problema activo confirmado en esta tabla hoy. La motivación fue puramente proactiva/preventiva ante un crecimiento futuro proyectado, no un incidente ni una degradación medida.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Diseño técnico completo: partición hash por `CustomerId` (`N=16`, ~4M filas/partición a escala 13x), migración vía tabla sombra (no rebuild in-place) | Informativo |
| H2 | Particionado por año (como `CustomerPointsLog`) descartado tras confirmar directamente que no existe ninguna columna de fecha inmutable — `LastBuyDate` muta en cada compra | Informativo |
| H3 | Revisión de código fuente confirmó: escrituras son `DELETE`+`INSERT` (nunca `UPDATE`), la app nunca lee el `Id` generado, sin EF, sin hints de índice — migración estructuralmente segura para la app si se ejecutara | Informativo |
| H4 | **Costo real medido de mantenimiento hoy: ~3,5 minutos** (corrida real 2026-09-22, ver `events/20260922_gitin2078-customeradditionalinformation-index-rotation/`) — sin incidentes de bloqueo reportados nunca para esta tabla, a diferencia de `CustomerPointsLog` (3 incidentes confirmados: GITIN-1866, GITIN-2036, GITIN-2076) | Informativo (clave para la decisión) |
| H5 | **Perfil estructuralmente distinto a `CustomerPointsLog`**: esta tabla nunca tiene más de una fila por cliente (patrón `DELETE`+`INSERT`), consumida por un solo hot path (`SaleProviderController`, 3 endpoints) — no crece por volumen de ventas sino por clientes distintos. Extrapolación 13x (~64M filas) estimaría ~30-45 min de mantenimiento, lejos del riesgo de bloqueo de horas que sí tuvo `CustomerPointsLog` | Informativo (clave para la decisión) |
| H6 | Riesgo de ejecución real identificado durante el diseño: condición de carrera entre backfill y triggers de doble escritura, secuencia de corte (`sp_rename` + limpieza de triggers), sin entorno no-productivo para probar — todo esto sobre una tabla de un hot path de checkout POS en producción | Medio (motivó la decisión de no ejecutar) |

## Recursos afectados

Ninguno — no se aplicó ningún cambio.

## Comandos ejecutados

Ninguno ejecutado contra producción. DDL completo (función/esquema de partición, tabla sombra, triggers) diseñado y documentado en `investigation.md`, no ejecutado.

## Acciones propuestas

1. **(SRE) Descartado por ahora** — No ejecutar la migración. Diseño completo queda documentado en `investigation.md` para retomar sin partir de cero si la señal cambia.
2. **(SRE) Pendiente, sin urgencia** — Monitorear el tiempo de mantenimiento diario de esta tabla (vía `PNSSRL_DetallesEjecucionTablasModulos`, `id_tablas_modulos=479`) a medida que la red de franquicias crece. Revisar este diseño si el tiempo de mantenimiento crece materialmente (ej. supera ~15-20 minutos) o si surge una fecha concreta para el crecimiento a 2600 franquicias.

## Hallazgos secundarios

Ninguno.
