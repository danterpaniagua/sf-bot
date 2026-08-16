# GITIN-1864 — GESTION: log de transacciones lleno impide arranque de la aplicación

**Tags:** Operaciones, PROD, SRE

## Resumen

La base de datos `GESTION` (esquema local SmartFran POS, instancia SQL Server on-premise de sucursal) tenía su archivo de log de transacciones (`ROM_Log`) en 100% de uso, al límite de su `max_size` configurado (~9,77 GB), impidiendo el arranque de la aplicación `Gestion` con el error "The transaction log for database 'GESTION' is full due to 'LOG_BACKUP'". La causa fue que la base opera en modelo de recuperación FULL sin que nunca se haya configurado un backup de log — solo se ejecutan backups completos periódicos — por lo que el log creció sin control a lo largo de años de operación hasta agotar su espacio disponible. Se aplicó un cambio de modelo de recuperación a SIMPLE junto con un CHECKPOINT para truncar el log de inmediato, y se confirmó el arranque exitoso de la aplicación.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | GITIN-1864 |
| ID alerta | N/A — reportado directamente como falla de arranque de aplicación |
| Sistema | GESTION (SmartFran POS on-premise, instancia local de sucursal) |
| Severidad | Alta — aplicación de producción caída |
| Detectado | 2026-08-15 |
| Resuelto | 2026-08-15 |
| Responsable | Dante Paniagua |

## Causa raíz

`GESTION` está en modelo de recuperación FULL, que requiere backups de log periódicos para truncar el log de transacciones. El historial de backups (`msdb.dbo.backupset`), con registros desde 2019-04-07, muestra únicamente backups completos (tipo 'D') — nunca se ejecutó un backup de log (tipo 'L'), y tampoco existe ni existió un job de SQL Agent para esa tarea. Sin backups de log, el archivo `ROM_Log` (`C:\Smartfran\DATA\GESTION_log.ldf`) creció de forma no acotada durante años hasta alcanzar su `max_size` configurado (~9,77 GB) y llenarse por completo, bloqueando toda escritura nueva en la base y, con ello, el arranque de la aplicación.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | `GESTION` en modelo de recuperación FULL sin ningún backup de log registrado en 7+ años de historial | Alto |
| H2 | No existe ni existió job de SQL Agent para backup de log en esta instancia | Alto |
| H3 | Archivo de log (`ROM_Log`) llegó a ~92,6% de su propio `max_size` configurado antes de llenarse — margen de autogrowth insuficiente como mitigación de emergencia | Medio |
| H4 | No se identificó transacción activa/bloqueada como causa contribuyente — el problema es puramente de acumulación histórica sin truncado | Bajo |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| Base de datos | `GESTION` |
| Instancia | SQL Server on-premise, sucursal SmartFran POS (`C:\Smartfran\DATA\`) |
| Aplicación | `Gestion` (no podía iniciar) |

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | Recovery model / log_reuse_wait_desc | Diagnóstico inicial del estado de la base |
| C2 | DBCC SQLPERF(LOGSPACE) | Verificar % de uso del log |
| C3 | sys.database_files | Verificar tamaño y configuración de crecimiento del archivo de log |
| C4 | msdb.dbo.backupset | Auditar historial de backups (completos vs. log) |
| C5 | sys.dm_tran_database_transactions | Descartar transacción abierta como causa |
| C6 | sys.dm_os_volume_stats | Verificar espacio libre en disco |
| C7 | msdb.dbo.sysjobhistory | Verificar existencia de job de backup de log |
| C8 | ⚠️ ALTER DATABASE ... SET RECOVERY SIMPLE + CHECKPOINT | Truncar el log y resolver el bloqueo de arranque |
| C9 | DBCC SQLPERF(LOGSPACE) | Verificar truncado exitoso del log |

Detalle completo en `scripts.sql`.

## Acciones propuestas

1. **(SRE) Completado** — Cambio de modelo de recuperación de `GESTION` de FULL a SIMPLE, con `CHECKPOINT` para truncar el log de inmediato. Confirmado: uso de log bajó de 100% a 9,11%, aplicación `Gestion` arrancó correctamente.
2. **(SRE) Pendiente, opcional** — Evaluar `DBCC SHRINKFILE` sobre `ROM_Log` para recuperar espacio en disco del archivo sobredimensionado (actualmente ~9,05 GB), una vez confirmada la estabilidad post-fix.
3. **(SRE) Pendiente** — Confirmar si existen otras instancias `GESTION` en otras sucursales con el mismo patrón (FULL sin backup de log) para evitar recurrencia del mismo incidente en otro local.
