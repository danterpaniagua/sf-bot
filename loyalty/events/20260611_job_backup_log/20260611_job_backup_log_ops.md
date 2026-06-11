# Incidente — Job SQL Agent: Backup_Log fallando (2026-06-11)

## Resumen

| Campo | Detalle |
|---|---|
| Fecha detección | 2026-06-11 10:10 UTC (primer registro en historial) |
| Alerta origen | Zabbix — `MSSQL Job 'Operaciones_MaintenancePlan_Backups.Backup_Log': Failed to run` |
| Servidor | `SFCG-DB01` (SQL Server 2022 Standard, v16.0.4075.1) |
| Jobs afectados | `Operaciones_MaintenancePlan_Backups.Backup_Log`, `Operaciones_MaintenancePlan_Backups.Backup_FULL` |
| Frecuencia de fallo | Cada 10 minutos (cada ejecución programada desde las 10:10 UTC), Desde el último backup FULL |
| Impacto | Sin backup de log de transacciones en `SmartFran.Solution.SmartLoyalty` durante ~3 horas. Sin backup FULL |
| Resolución | 2026-06-11 13:20 UTC — Job SUCCEEDED |
| Estado | **Cerrado** |

---

## Descripción del incidente

El job `Operaciones_MaintenancePlan_Backups.Backup_Log` falló en todas sus ejecuciones desde las 10:10 UTC. El paquete SSIS del plan de mantenimiento terminaba en menos de 0,4 segundos con el error:

```
The EXECUTE permission was denied on the object 'sp_maintplan_open_logentry',
database 'msdb', schema 'dbo'.
```

La base `SmartFran.Solution.SmartLoyalty` está en modelo de recuperación `FULL`, por lo que los backups de log son críticos para controlar el crecimiento del transaction log y mantener la cadena de recuperabilidad.

---

## Análisis de causa raíz

### Causa primaria — Credencial de proveedor embebida en el paquete SSIS

El plan de mantenimiento almacena su paquete SSIS en `msdb.dbo.sysssispackages`. La cadena de conexión interna del paquete era:

```
Data Source=SFCG-DB01;User ID=promero;Integrated Security=False;...
```

El login `promero` correspondía a un DBA externo del proveedor PNS, cuyas credenciales habían sido revocadas o modificadas, dejando al paquete sin permisos de ejecución sobre `msdb.dbo.sp_maintplan_open_logentry`.

El job SQL Agent se ejecuta como `NT Service\SQLSERVERAGENT`, pero eso no tenía relevancia: el paquete SSIS usa su propia cadena de conexión interna con autenticación SQL, independiente del contexto del agente.

### Hallazgos adicionales

- El diseñador gráfico de planes de mantenimiento en SSMS no permite cambiar la conexión en la tarea `Back Up Transaction Logs`. La modificación debe hacerse directamente sobre el XML del paquete almacenado en msdb.
- `PNSSRL` está en modelo de recuperación `SIMPLE`. Los backups de log sobre esta base serían ignorados o fallarían; el plan de mantenimiento parece manejar esto internamente.
- `CAST(packagedata AS XML)` falla con error 529 — se debe ir por `CAST(CAST(packagedata AS VARBINARY(MAX)) AS XML)`.
- `CAST(@pkg AS NVARCHAR(MAX)) AS IMAGE` no está permitido — se debe convertir a `VARBINARY(MAX)`.

---

## Scripts ejecutados (en orden)

Scripts completos en: `20260611_job_backup_log_scripts.sql`

| # | Query | Propósito |
|---|---|---|
| Q1 | Historial del job | Ver las últimas 20 ejecuciones fallidas y el mensaje de error exacto |
| Q2 | Modelos de recuperación | Verificar qué bases están en FULL vs SIMPLE (log backup no aplica en SIMPLE) |
| Q3 | Login en `sys.server_principals` | Confirmar que `NT Service\SQLSERVERAGENT` existe como login a nivel servidor |
| Q4 | Usuario en `msdb` | Confirmar el mapeo del login al usuario de base de datos en msdb |
| Q5 | Lectura del paquete SSIS | Extraer la cadena de conexión embebida — reveló `User ID=promero;Integrated Security=False` |
| Q6 | `@@SERVERNAME` | Obtener el nombre exacto del servidor para construir la nueva cadena de conexión |
| Q7 | Crear `svc_maintplan` | Nuevo login de servicio con permisos mínimos en msdb para reemplazar `promero` |
| Q8 | Preview del fix | Verificar la nueva cadena de conexión en memoria antes de escribir en msdb |
| Q9 | Aplicar fix | Actualizar el XML del paquete SSIS en `sysssispackages` con Windows Auth |
| Q10 | Estado de todos los jobs | Confirmar SUCCEEDED en `Backup_Log` y salud general del agente |
| Q11 | Auditoría de paquetes SSIS | Revisar todos los paquetes en msdb en busca de credenciales SQL embebidas |

---

## Resultado

| Job | Estado final | Hora resolución |
|---|---|---|
| `Operaciones_MaintenancePlan_Backups.Backup_Log` | SUCCEEDED | 2026-06-11 13:20 UTC |
| Todos los demás jobs | SUCCEEDED | — |

---

## Auditoría de paquetes SSIS — credenciales embebidas

Se consultaron todos los paquetes SSIS almacenados en `msdb.dbo.sysssispackages`. Resultado:

| Paquete | Conexiones | Autenticación |
|---|---|---|
| `Operaciones_MaintenancePlan_Backups` | `Local server connection` | `Integrated Security=True` — correcto post-fix |
| `SqlTraceCollect`, `SqlTraceUpload` | `ConfigConnection`, `MdwConnection`, `TargetConnection` | `Integrated Security=SSPI` — Windows Auth |
| `PerfCountersCollect`, `PerfCountersUpload` | Ídem | `Integrated Security=SSPI` — Windows Auth |
| `QueryActivityCollect`, `QueryActivityUpload` | Ídem | `Integrated Security=SSPI` — Windows Auth |
| `TSQLQueryCollect`, `TSQLQueryUpload` | `ConfigConnection` | NULL (sin conexión configurada) |

**Ningún paquete tiene credenciales SQL embebidas.** El incidente de `promero` era el único caso.

**Observación secundaria:** `SqlTraceUpload.MdwConnection` apunta a `Initial Catalog=myMDW` mientras los demás paquetes de Data Collector usan `MDW`. Posible error de configuración en el Data Collector. Sin impacto en el incidente actual; registrado para seguimiento.

---

## Acciones propuestas

1. **Deshabilitar `promero`** — `ALTER LOGIN promero DISABLE;` — no eliminar hasta confirmar que ningún otro sistema externo lo referencia.
2. **Verificar Data Collector** — `SqlTraceUpload.MdwConnection` apunta a `myMDW` en lugar de `MDW`; confirmar si el Data Collector está activo y si esa base existe.
