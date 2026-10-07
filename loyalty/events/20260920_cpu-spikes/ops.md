# GITIN-2074 — [SML] Picos de CPU en DB

**Tags:** SmartLoyalty, WebServiceV2, CPU, PROD, SRE

## Resumen

El 2026-09-20 entre las 19:15 y las 20:23 hora local (22:15-23:23 GMT) se detectó un pico sostenido de CPU en `SFCG-DB01`, originado principalmente en `Query101-sql.xml` (`SmartLoyalty.WebServiceV2`), que consulta `SmlSt.CustomerAdditionalInformation` en cada venta. La tabla (~4,9M filas) no tenía índice sobre ninguno de los campos que usa la consulta (`CardNumber`, `UidCode`, `UidSerie`), forzando un scan del índice clustered en cada ejecución. Este mismo hallazgo ya había sido documentado el 2026-05-17 bajo GITIN-1267, con la misma causa raíz y los mismos índices propuestos — esa remediación nunca se había aplicado. Se crearon los dos índices faltantes el 2026-09-21 durante una ventana confirmada como de bajo tráfico. **Pruebas posteriores a la creación confirmaron que los índices no aportan ninguna mejora medible mientras la estructura `OR`/`LOWER()` de la consulta siga así** — no es una mitigación parcial como se asumió inicialmente. La reescritura de la consulta (`OR`→`UNION`, remover `LOWER()`, resolver el `TRY_CAST` en el join con `Article`) sigue pendiente del lado de Dev, y ahora es un requisito para que los índices tengan algún efecto, no solo para la rama de `UidCode`.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2074](https://smartit-ar.atlassian.net/browse/GITIN-2074) |
| Sistema | SmartLoyalty SQL Server (`SmartFran.Solution.SmartLoyalty`) — `SFCG-DB01` |
| Severidad | Media-Alta — recurrencia de un problema ya conocido (GITIN-1267), con impacto real reportado en facturación de sucursales |
| Detectado | 2026-09-20 19:15 hora local |
| Resuelto | Parcial — índices creados, consulta reescrita y desplegada en ambos hosts, rollout confirmado (50 min sin ejecuciones de la versión anterior). Pendiente: commitear el cambio al control de versiones (riesgo de reversión, ver H12); particionamiento (GITIN-2077) y rotación de mantenimiento (GITIN-2078) siguen abiertos como subtareas |
| Responsable | Dante Paniagua |

## Causa raíz

`Query101-sql.xml`, invocada una vez por venta desde `SaleProviderApplicationServiceV2.cs:772`, filtra `SmlSt.CustomerAdditionalInformation` por `CardNumber OR (UidCode + UidSerie)`. Sin índice sobre ninguno de esos tres campos, cada ejecución recorre el índice clustered completo (~4,9M filas). Bajo volumen elevado de ventas, esto generó presión de CPU sostenida y concurrente. El patrón — `OR` que impide seek, `LOWER()` sobre `UidCode` que bloquea cualquier índice sobre esa columna, y `TRY_CAST` sobre `FavoriteProduct` en el join con `Article` — es idéntico al documentado en GITIN-1267 cuatro meses antes.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Query101 confirmado como principal contribuyente de CPU en la ventana analizada: 91.704 ms totales, 19 SPIDs distintos, 2 hosts (`SFCG-WSV2-01/02`) — vía delta de CPU por snapshot | Alto |
| H2 | Sin índice sobre `CardNumber`, `UidCode` ni `UidSerie` en `SmlSt.CustomerAdditionalInformation` — solo `Id` (clustered) y `CustomerId` (nonclustered) | Alto |
| H3 | Corroboración independiente vía estadísticas de plan cache (`sys.dm_exec_query_stats`): Query101 representa el 84,7% del CPU entre las consultas que tocan esa tabla/columna (3.386.462 ms / 876 ejecuciones) | Alto |
| H4 | `SmlSt.CustomerAdditionalInformation` no está particionada (partition_number=1 único) | Medio |
| H5 | Recurrencia confirmada de GITIN-1267 (2026-05-17) — mismo query, misma causa raíz, misma remediación propuesta nunca aplicada | Alto |
| H6 | Corroboración externa: reporte interno de demoras en facturación desde las 18:22 hora local — 53 minutos antes del inicio de la ventana analizada con `PNSSRL_AuditSysprocesses`. Direccionalmente consistente con Query101, sin cruce a nivel de SPID/sucursal confirmado | Medio (no confirmado a nivel de correlación) |
| H7 | Reporte de "CPU 100%" no corroborado por los chequeos de carga en vivo (`sys.dm_exec_requests`) realizados esa noche — origen del dato no identificado | Bajo |
| H8 | El servidor es SQL Server 2022 Standard — `WITH (ONLINE = ON)` no disponible (`Msg 1712`). El build de los índices nuevos tuvo que ejecutarse offline, con lock de escritura sobre la tabla durante toda su duración — cambia el perfil de riesgo de cualquier mantenimiento futuro sobre esta tabla | Medio |
| H9 | **Confirmado con pruebas reales post-creación: los índices nuevos no aportan ninguna mejora mientras la estructura `OR`/`LOWER()` de Query101 siga así.** Prueba aislada (mismo `CardNumber`, sin la rama `UidCode`): `CustomerAdditionalInformation` pasa de 104.970 lecturas lógicas (Query101 completa, con `OR`) a 4 lecturas lógicas (solo `CardNumber`, seek limpio confirmado en el plan de ejecución). No es una mitigación parcial — la reescritura de la consulta es requisito para que el índice tenga algún efecto | Alto |
| H10 | **La reescritura propuesta en GITIN-1267 (`OR`→`UNION`, sin `LOWER()`) fue probada con datos reales, ambas ramas: `CardNumber` (8 lecturas totales) y `UidCode`+`UidSerie` (4 lecturas), contra 104.970 de la consulta original — reducción de más del 99,99% en ambos caminos de búsqueda. La corrección propuesta no es solo teóricamente correcta, está probada contra datos reales** | Alto (positivo — validación de la solución) |
| H11 | La corrección ya está desplegada y corriendo en producción (confirmado vía plan cache: planes `UNION` reales con lecturas de 4-6). Rollout inicialmente parcial — `SFCG-WSV2-02` (`E:\...`) no había recibido el archivo copiado a `SFCG-WSV2-01` (`D:\...`) — **ya resuelto**: se confirmó que ambos archivos son ahora idénticos, con la corrección aplicada en los dos hosts | Medio (resuelto, dejado por trazabilidad) |
| H12 | **Crítico: la corrección desplegada no existe en el control de versiones, en ninguna rama.** `Query101-sql.xml` en el repositorio (`main`, sincronizado con `origin/main`) sigue con la versión `OR` original; se buscó en todas las ramas remotas y ninguna tiene la versión `UNION`. La corrección que está corriendo en producción existe únicamente como una edición manual sobre el archivo del servidor — el próximo despliegue normal desde el repositorio la revertiría silenciosamente | Alto |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| `SFCG-DB01` | Host de base de datos afectado por el pico de CPU |
| `SmlSt.CustomerAdditionalInformation` (`SmartFran.Solution.SmartLoyalty`) | Tabla sin índices de soporte, origen del scan repetido |
| `SmartLoyalty.WebServiceV2` (`SFCG-WSV2-01`/`SFCG-WSV2-02`) | Aplicación que ejecuta Query101 en el flujo de venta |
| Facturación en sucursales (POS) | Impacto reportado — demoras al facturar, coincidente en horario |

## Comandos ejecutados

| # | Archivo | Propósito |
|---|---|---|
| — | `Query101.sql` | Texto completo de la consulta responsable, extraído de `PNSSRL_AuditSysprocesses.comando_ejecutado` |
| — | `remediation_indexes.sql` | Los dos índices nonclustered creados como mitigación (`CardNumber`; `UidCode`+`UidSerie`) |

Detalle completo de las consultas de diagnóstico (delta de CPU por SPID, inventario de índices, estadísticas de plan cache, chequeo de partición, chequeos de carga/tempdb pre-build) en los archivos numerados bajo `data/` — no se mantuvo un `scripts.sql` consolidado para este ticket, cada resultado quedó persistido individualmente a medida que se ejecutaba.

## Resultado de las pruebas (antes / después)

Lecturas lógicas sobre `SmlSt.CustomerAdditionalInformation`, medidas con `SET STATISTICS IO ON` contra datos reales:

| Escenario | Consulta actual (con `OR`) | Índices solos, sin reescritura | Reescritura propuesta (`UNION`, sin `LOWER()`) |
|---|---|---|---|
| Búsqueda por `CardNumber` | 104.970 | 104.970 (sin cambio) | 8 |
| Búsqueda por `UidCode`+`UidSerie` | 104.970 | No probado por separado (bloqueado por el mismo `OR`) | 4 |

La columna "Índices solos" confirma H9: crear los índices no alcanza mientras la consulta mantenga el `OR`. La columna "Reescritura propuesta" confirma H10: con el `UNION` aplicado, ambas búsquedas bajan a un dígito. Detalle y archivos fuente: `data/09_post_index_plancache_check.txt`, `data/10_post_index_execution_plan.txt`, `data/11_isolated_cardnumber_test.txt`, `data/12_optimized_query_union_test.txt`.

**Confirmación con tráfico real de producción** (no solo la prueba manual), promedio ponderado por ejecuciones reales una vez desplegada la corrección:

| Métrica | Antes (`OR`, producción real) | Después (`UNION`, producción real) | Mejora |
|---|---|---|---|
| Tiempo transcurrido promedio | 327,03 ms | 0,42 ms | ~99,87% |
| CPU promedio | 3.314,82 ms | 0,26 ms | ~99,99% |
| Lecturas lógicas promedio | 104.399,1 | 5,6 | ~99,99% |
| Ejecuciones muestreadas | 84 | 36 | — |

Fuente: `data/13_post_deploy_plancache_check.txt`, filtrado a filas con forma de Query101 (>10.000 lecturas lógicas del lado `OR`) para excluir otras consultas que comparten el mismo filtro de texto.

## Acciones propuestas

1. **(SRE) Completado** — Creación de `IX_CustomerAdditionalInformation_CardNumber` e `IX_CustomerAdditionalInformation_UidCode_UidSerie`, ejecutada 2026-09-21 durante una ventana confirmada sin backup activo, sin locks sobre la tabla y sin tráfico real. Sin la reescritura del punto 2, los índices no tienen ningún efecto (ver H9) — no es una mitigación parcial.
2. **(Dev) Desplegado en producción, sin commitear — validado con datos reales, riesgo de reversión silenciosa** — La reescritura de Query101 (`OR`→`UNION`, sin `LOWER()`) ya corre en producción y funciona (ver H10, H11): reduce las lecturas lógicas de 104.970 a un dígito en ambas ramas de búsqueda. **No existe en el control de versiones en ninguna rama (H12)** — el próximo despliegue normal la revertiría sin aviso. Prioridad inmediata: commitear el cambio ya aplicado antes de cualquier otro despliegue sobre WebServiceV2. El rollout a ambos hosts (`SFCG-WSV2-01` y `SFCG-WSV2-02`) ya está confirmado completo (H11) — queda solo el commit pendiente. Estructural, aparte: agregar `FavoriteProductId INT` con FK a `Article.Id` para eliminar el `TRY_CAST` en el join. Detalle completo, incluyendo el precedente de GITIN-1267, en `investigation.md`.
3. **(SRE) Pendiente** — Particionar `SmlSt.CustomerAdditionalInformation`. Sin diseño de partition key todavía — ver `loyalty/todo/TODO.md`. Subtarea: [GITIN-2077](https://smartit-ar.atlassian.net/browse/GITIN-2077).
4. **(SRE) Pendiente** — Sumar los dos índices nuevos a la rotación de mantenimiento existente (p. ej. `PNSSRL_MantenimientoIndices`), coordinado con el particionamiento del punto 3. Subtarea: [GITIN-2078](https://smartit-ar.atlassian.net/browse/GITIN-2078).

## Hallazgos secundarios

Durante la verificación de ventana segura para la creación de índices (2026-09-21), se detectó un incidente de bloqueo activo y no relacionado sobre `Sml.CustomerPointsLog` — separado en su propio evento (`events/20260921_customerpointslog-blocking/`, GITIN-2076), resuelto ahí antes de continuar con este ticket.

Reportes de esa misma noche sobre demoras de DNI "en OP y en cloud" y una cola de AWS SQS para la sucursal 5612 corresponden a SmartFran Cloud / SmartPedidos-AWS — plataformas y código distintos de `SFCG-DB01`, no investigados bajo este ticket.
