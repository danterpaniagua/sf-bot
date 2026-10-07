# Eventos — 20260920_cpu-spikes

## 2026-09-20 19:15 — Inicio de la investigación

Inicié la investigación de los picos de CPU reportados en `SFCG-DB01` a partir de las 19:15 hora local. Verifiqué disponibilidad de datos en `PNSSRL_AuditSysprocesses` para la ventana 22:15-23:23 GMT: 1.654 snapshots, 128 SPIDs distintos.

## 2026-09-20 19:15-20:26 — Confirmación de causa raíz: Query101 sin índices de soporte

Analicé el delta de CPU por SPID y por firma de consulta, y confirmé que `Query101-sql.xml` (`SmartLoyalty.WebServiceV2`) es el mayor contribuyente identificado: 91.704 ms totales en 19 SPIDs distintos. Verifiqué el inventario de índices de `SmlSt.CustomerAdditionalInformation` (~4,9M filas) y confirmé que no existe índice sobre `CardNumber`, `UidCode` ni `UidSerie` — solo `Id` (clustered) y `CustomerId`. Corroboré el hallazgo con una segunda fuente independiente (estadísticas de plan cache vía `sys.dm_exec_query_stats`): Query101 representa el 84,7% del CPU entre las consultas que tocan esa tabla/columna. Confirmé también que la tabla no está particionada.

## 2026-09-20 ~20:00 — Hallazgo de precedente: GITIN-1267

Encontré que este mismo patrón (Query101, mismo root cause) ya había sido documentado el 2026-05-17 bajo GITIN-1267 (`events/20260517_query101_webservicev2/`), con los mismos índices propuestos. Confirmé que ninguno de esos índices existía todavía — la remediación de esa investigación nunca se había aplicado.

## 2026-09-20 ~20:30 — Ticket asignado: GITIN-2074

Recibí el ticket Jira para esta ocurrencia: GITIN-2074, "[SML] Picos de CPU en DB".

## 2026-09-20 ~21:00 — Borrador de email a PM

Redacté un email a PMs con los hallazgos en lenguaje no técnico, hedgeado como corroborativo (no causal confirmado) respecto al patrón de CPU, e incluí el próximo paso de crear los índices faltantes.

## 2026-09-20 21:15 — Corrección: `WITH (ONLINE = ON)` no soportado en esta edición

Al preparar el script de remediación afirmé incorrectamente que Standard edition soporta operaciones de índice online desde 2016 SP1. Al ejecutarse, el servidor devolvió `Msg 1712` (feature exclusiva de Enterprise). Corregí el script a un build offline y documenté el nuevo riesgo: bloqueo de escrituras sobre la tabla durante toda la duración del build.

## 2026-09-21 07:21 — Confirmación del horario de backup full

Consulté `msdb.dbo.sysjobschedules`/`sysschedules` y confirmé que el backup full de `SmartFran.Solution.SmartLoyalty` corre domingo/lunes/miércoles a las 06:00 GMT (03:00 local). Documenté este hallazgo en `loyalty/docs/infrastructure.md`, que no tenía este dato registrado.

## 2026-09-21 ~07:25-07:31 — Verificación de ventana segura antes del build

Antes de ejecutar la creación de índices, verifiqué: backup full no estaba corriendo, no había locks sobre `SmlSt.CustomerAdditionalInformation`, y la carga general del servidor no mostraba tráfico real más allá de tareas internas de SQL Server. Durante esta verificación detecté un incidente de bloqueo activo y no relacionado sobre `Sml.CustomerPointsLog` — lo separé en su propio evento (`events/20260921_customerpointslog-blocking/`, GITIN-2076) y lo resolví ahí antes de continuar acá.

## 2026-09-21 07:32-07:34 — Creación de índices

Ejecuté `remediation_indexes.sql` contra `SmartFran.Solution.SmartLoyalty` durante la ventana confirmada como segura. `IX_CustomerAdditionalInformation_CardNumber` completó en ~1-2 minutos; `IX_CustomerAdditionalInformation_UidCode_UidSerie` completó en ~49 segundos.

## 2026-09-21 07:35 — Verificación de índices creados

Confirmé la existencia de ambos índices nuevos junto a los dos preexistentes (`PK` clustered sobre `Id`, `IX_CustomerAdditionalInformation_CustomerId`). Actualicé `loyalty/todo/TODO.md`: marqué la creación de índices como completada y agregué dos pendientes — sumar los índices nuevos a la rotación de mantenimiento existente, y el particionamiento de la tabla (todavía sin diseño).

## 2026-09-21 ~12:08-12:11 — Prueba con datos reales: los índices solos no alcanzan

Probé Query101 contra un `CardNumber` real con `SET STATISTICS IO ON`: 104.970 lecturas lógicas sobre `CustomerAdditionalInformation` — sin cambio respecto a la línea de base previa a los índices. Aislé la rama `CardNumber` (removiendo el `OR`) con el mismo valor real: bajó a 4 lecturas lógicas, seek limpio confirmado en el plan de ejecución. Confirmé así que el `OR`/`LOWER()` de la consulta, no un problema de caché, es la única causa de que los índices nuevos no se usen.

## 2026-09-21 ~12:13 — Validación de la reescritura propuesta (GITIN-1267) con datos reales

Probé la reescritura `OR`→`UNION` propuesta en GITIN-1267 contra datos reales, las dos ramas por separado: `CardNumber` real (8 lecturas lógicas totales) y `UidCode`+`UidSerie` real (4 lecturas lógicas) — ambas devolvieron la fila correcta. Confirmé una reducción de más del 99,99% respecto a las 104.970 lecturas de la consulta actual. Guardé `Query101_proposed.sql` y `demo_comparison.sql` como referencia reutilizable, actualicé `investigation.md`/`ops.md`/`email_pm.md`/`email_dev.md` con el resultado, y codifiqué esta metodología de validación (línea base + `STATISTICS IO` contra datos reales, por rama) en la skill `loyalty-dba-investigation` para futuras investigaciones.

## 2026-09-21 — Confirmación de los endpoints que consumen Query101

Revisé el código fuente y confirmé que Query101 es alcanzable desde 3 endpoints HTTP distintos en `SaleProviderController` (`GetCustomerAdditionalInformation`, `GetCustomerByCardNumber`, `GetCustomerByUidSerie`), no desde un único punto de llamada como estaba documentado. Descarté `CustomerApplicationService.GetFavoriteProductAndAverageWeight` y `AdditionalInformationController` (MobileAppService) como consumidores adicionales — ninguno de los dos toca esta consulta en el repositorio.

## 2026-09-21 ~15:32-15:34 — Verificación post-despliegue: la corrección funciona, pero el rollout está incompleto

Confirmé que la corrección ya estaba desplegada en producción: 10 planes en caché con `UNION`, con 4-6 lecturas lógicas — igual a lo probado manualmente. Pero también encontré planes de la versión vieja (`OR`) compilándose y ejecutándose recientemente (última ejecución 14:28 GMT). Con `PNSSRL_AuditSysprocesses` confirmé que la versión vieja seguía corriendo desde ambos hosts, `SFCG-WSV2-01` y `SFCG-WSV2-02`.

## 2026-09-21 — Hallazgo crítico: la corrección no existe en el control de versiones

Busqué en todas las ramas remotas del repositorio una versión de `Query101-sql.xml` con `UNION` — no encontré ninguna. Confirmé que la corrección que corre en producción existe únicamente como una edición manual sobre el archivo del servidor, sin commitear en ningún lado — el próximo despliegue normal la revertiría sin aviso. Documenté esto como H12 en `ops.md`, prioridad inmediata.

## 2026-09-21 — Causa del rollout incompleto y cierre del gap

Confirmé que la corrección se había copiado directo a `D:\SmartLoyalty.WebServiceV2\bin\Domain\Query\` en `SFCG-WSV2-01` únicamente. Identifiqué que `SFCG-WSV2-02` usa una ruta separada (`E:\...`) y probablemente nunca recibió el archivo. Tras la copia al segundo host, confirmé que ambos archivos quedaron idénticos, con la corrección aplicada en los dos. Se reiniciaron ambos servicios web (`SFCG-WSV2-01` y `SFCG-WSV2-02`) para eliminar cualquier proceso que pudiera seguir sirviendo la plantilla vieja desde memoria.

## 2026-09-21 ~15:48-16:00 — Confirmación final del rollout limpio

Revisé la proporción de ejecuciones viejas vs. nuevas por bucket de 10 minutos desde `PNSSRL_AuditSysprocesses`. Confirmé el patrón completo: 100% viejo antes de la corrección, una resurgencia entre 13:40-14:20 (coincidente con el gap de `SFCG-WSV2-02`, ya resuelto), y una racha limpia de 50 minutos (15:20-16:00, 17 ejecuciones, todas `UNION`) tras los reinicios. Dejé como único pendiente crítico de este ticket el commit de la corrección al control de versiones.
