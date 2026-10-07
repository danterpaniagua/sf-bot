# [SML] Deploy version 13.00.00 — GITIN-2132

**Tags:** `SmartLoyalty`, `SQLServer`, `PROD`

## Resumen

Despliegue de la versión 13.00.00 de SmartLoyalty (funcionalidad de Insignias) sobre la base `SmartFran.Solution.SmartLoyalty` del servidor de producción `SFCG-DB01`. El 2026-10-01 se ejecutaron en este orden los scripts de datos: carga del catálogo de insignias, reglas de transición de Argentina, reglas de transición de Paraguay y la carga inicial de insignias (`CargaInicial_Insignia_Final_v3`). La carga tomó su fecha de corte a las 09:29:41 UTC y terminó a las 09:35:12 UTC.

Verificación posterior (09:37 UTC): se cargaron 6.353.167 filas en `Sml.CustomerInsignia`, igual a la cantidad de socios activos de cada país (Argentina 6.234.214, Paraguay 118.953); los controles de consistencia dieron 0. Las 10 migraciones de EF esperadas figuran aplicadas en el historial del contexto de SmartLoyalty y el esquema coincide con lo esperado. Quedan puntos pendientes de verificar, listados en Acciones propuestas.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | GITIN-2132 |
| ID alerta | N/A — despliegue planificado |
| Sistema | SmartLoyalty — SQL Server `SFCG-DB01`, base `SmartFran.Solution.SmartLoyalty` |
| Severidad | N/A |
| Detectado | N/A |
| Resuelto | Parcial — scripts ejecutados y verificados; puntos pendientes (ver Acciones propuestas) |
| Responsable | SRE |

## Ejecución de los scripts

| # | Script (versión 13.00.00) | Ejecución |
|---|---|---|
| 1 | `Seed_Insignia` | Ejecutado en el orden indicado (resultado individual no revisado) |
| 2 | `Seed_InsigniaTransitionRules_AR` | Ejecutado (resultado individual no revisado) |
| 3 | `Seed_InsigniaTransitionRules_PY` | Ejecutado; las reglas resultantes son idénticas a las de Argentina (ver verificación) |
| 4 | `CargaInicial_Insignia_Final_v3` | Ejecutado; corte 09:29:41 UTC, fin 09:35:12 UTC (unos 5 min 30 s incluyendo los controles finales) |

Antes de ejecutar en producción se corrió un diagnóstico de impacto sobre el clon `SFCG-DB-CLON`: terminó sin errores en unos 12 min 50 s (solo tablas temporales). Se corrigieron en esa copia el nombre de columna de país (`Country_Id`) y las etiquetas/umbral del diagnóstico para que coincidan con las reglas reales.

## Causa raíz

N/A — despliegue planificado.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Verificación en producción (09:37 UTC): Argentina y Paraguay tienen 8 reglas activas cada una con umbrales idénticos (DOWNGRADE a 30/31/51/121 días y 4 UPGRADE). `Sml.CustomerInsignia` tiene 6.234.214 filas para Argentina y 118.953 para Paraguay, iguales a los socios activos. Sin socios activos sin fila, sin filas de socios dados de baja, sin duplicados, `CustomerInsigniaHistory` vacía; el control de socios sin ventas dio 0 filas. | Bajo |
| H2 | Distribución: Argentina — CONGELADO 44,7 %, IMBATIBLE 22,8 %, NUEVO 15,8 %, DERRETIDO 10,5 %, ANTOJO 6,1 %. Paraguay — NUEVO 63,4 %, CONGELADO 23,5 %, IMBATIBLE 7,7 %, DERRETIDO 3,3 %, ANTOJO 2,1 %. La proporción de NUEVO (socios sin ventas válidas anteriores al corte) en Paraguay es unas cuatro veces la de Argentina; no se investigó la causa. | Por evaluar |
| H3 | El script `CargaInicial` no define `SET XACT_ABORT ON` ni `TRY/CATCH`: las validaciones previas hacen `ROLLBACK` + `THROW`, pero un error en tiempo de ejecución dentro del `INSERT` continuaría hasta el `COMMIT`. La carga se hace en una sola transacción para unos 6,35 millones de filas. | Por evaluar |
| H4 | El script `Seed_InsigniaTransitionRules_PY` ejecutado no está en el repositorio de SmartLoyalty (en `main` y `test02` solo existen `Seed_Insignia`, `Seed_Rules_AR` y `CargaInicial`). | Medio |
| H5 | Índices (consulta de uso, 09:40 UTC): en `Sml.CustomerInsignia` existe `IX_CustomerId`, con la misma clave que la clave primaria (redundante). Las consultas del código por cliente usan la clave primaria. `__IX_CustomerInsignia_InsigniaId` no es usado por ninguna consulta del código en `main`. | Bajo |
| H6 | En `Sml.Sale`, las consultas por cliente usan `IX_CustomerId` (solo `CustomerId`) y luego buscan cada fila en la clave clustered para leer `SaleDate` e `InvalidatedPointsLogId` (12,6 millones de búsquedas y 12,45 millones de lookups acumulados desde el último reinicio, incluyendo todo el tráfico de la aplicación). No se midió el costo de las consultas por venta de la nueva versión. | Por evaluar |
| H7 | Recuperación: la base está en modelo FULL (datos 517,44 GB, log 331,49 GB); el último backup completo programado es del 2026-09-30 09:00 UTC (111,46 GB comprimido, 8 min 31 s) y los backups de log corren cada unos 10 minutos a Azure Blob. Se decidió no tomar un backup completo adicional: la cadena de logs cubre los cambios. | Bajo |
| H8 | Migraciones de EF (consulta de las 10:02 UTC sobre `Sml.__MigrationHistory`): están aplicadas las 10 esperadas, desde `202510301922175_UpdateTimeZoneTable` hasta `202609231326210_AddInsigniaRollbackColumns` (la última registrada); no falta ninguna ni hay otra inesperada entre las 15 más recientes. Las columnas de fecha de `CustomerInsignia` y `CustomerInsigniaHistory` son `datetimeoffset`; `InitializedDate` y `PreviousInsigniaSinceDate` son NOT NULL, `LastActivityTypeAtTransition` admite nulos y `InsigniaTransitionRule.CountryId` es `int` NOT NULL. El historial no registra la fecha de aplicación de cada migración. La herramienta MigrateDatabase informó «migrated OK» para los ocho contextos (Membership, SmartLoyalty, SmartLoyaltyCms, Survey, Mailing, Schedule, Spec y ETL); su salida no incluye hora ni servidor. | Bajo |

## Recursos afectados

| Componente | Participación |
|---|---|
| `SmartFran.Solution.SmartLoyalty` en `SFCG-DB01` | Destino de los scripts; tablas `Sml.Insignia`, `Sml.InsigniaTransitionRule`, `Sml.CustomerInsignia` |
| `Sml.Customer`, `Sml.Sale`, `Sml.SalePromotion`, `Sml.Promotion` | Leídas por la carga inicial |
| Backups de log en Azure Blob | Cadena de recuperación del período |

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | `scripts.sql` (diagnóstico de impacto, solo tablas temporales) | Simular la carga en el clon antes de producción |
| C2 | Scripts 1–4 de la versión 13.00.00 | Despliegue en producción |
| C3 | `scripts_verify.sql` (consultas de solo lectura, versión corta ejecutada) | Reglas por país, socios activos contra filas cargadas, distribución, controles de consistencia |
| C4 | Consulta de índices y uso (`sys.indexes`, `sys.dm_db_index_usage_stats`) | Revisar índices de las tablas nuevas y de `Sml.Sale` |
| C5 | Consultas de solo lectura de backups, credenciales, espacio y estado de jobs | Estado de la cadena de recuperación; ningún backup se ejecutó |
| C6 | Consulta de ejecuciones `Etl` y de jobs en curso | Confirmar que ningún proceso de TaskOperator ni job de SQL Agent coincidió con la carga |
| C7 | `scripts_migrations.sql` (solo lectura) | Comparar las migraciones de EF esperadas con el historial aplicado y verificar columnas y tipos |
| C8 | Herramienta MigrateDatabase | Aplicar las migraciones de EF de los ocho contextos antes de los scripts de datos |

La salida de cada paso está en la carpeta `data/` del evento.

## Recuperación

Archivos de backup de log que rodean la ventana de la carga (contenedor de backups, prefijo `SmartFran.Solution.SmartLoyalty_backup_`): `2026_10_01_092000_7494844.trn` (09:20 UTC), `2026_10_01_093001_4310614.trn` (09:30), `2026_10_01_093348_0384230.trn` (09:33, fuera de la grilla de 10 minutos) y `2026_10_01_094001_3311882.trn` (09:40). Para restaurar hasta después de la carga se requiere el completo del 2026-09-30 más todos los logs hasta al menos el de las 09:40 UTC; para restaurar a un punto anterior, detener en `09:29:40 UTC` dentro del log de las 09:30. No se determinó en cuál de los dos últimos archivos está el `COMMIT` de la carga.

## Acciones propuestas

1. (SRE) Revisar la salida de mensajes (Messages) de la ejecución de `CargaInicial` (errores, advertencias, tiempos), que no se revisó.
2. (SRE) Confirmar con el responsable de negocio si la proporción de NUEVO en Paraguay (63,4 %) es la esperada.
3. (Dev) Incorporar al repositorio el script de reglas de Paraguay ejecutado, junto a los demás de la versión 13.00.00.
4. (Dev) Evaluar agregar `SET XACT_ABORT ON` y manejo de errores al script de carga inicial para futuros usos.
5. (SRE) Confirmar el orden entre la fecha de corte de la carga (2026-10-01 09:29:41 UTC) y el despliegue de la aplicación de la versión 13.00.00: las ventas posteriores al corte dependen de que la aplicación nueva las procese.
6. (SRE) Medir, con la versión 13.00.00 en uso, el costo de las consultas por venta sobre `Sml.Sale` antes de decidir cualquier índice nuevo; considerar la eliminación del índice redundante `IX_CustomerId` de `Sml.CustomerInsignia` una vez verificado en la base.
7. (SRE) Verificar la retención del contenedor de backups para que los archivos de log listados no se eliminen antes de confirmar el próximo backup completo programado.
