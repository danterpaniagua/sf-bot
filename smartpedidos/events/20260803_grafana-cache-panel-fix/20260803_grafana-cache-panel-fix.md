# 20260803_grafana-cache-panel-fix

**Tags:** SmartPedidos, MongoDB, Grafana

## Resumen

El panel "MongoDB: Cache" del dashboard de monitoreo en `monitoreosp.smartfran.com` (cluster `PedidosSmartfran`, MongoDB Atlas) fallaba con un error genérico (`Metric request error`, HTTP 500) al graficar el uso de caché de WiredTiger por réplica. El panel es parte del monitoreo activo definido para la ventana post-downsize de `20260803_mongodb-downsize-m20` ([GITIN-1741](https://smartit-ar.atlassian.net/browse/GITIN-1741)). Se identificó la causa raíz mediante lectura directa del código fuente del plugin de datasource y comparación contra la especificación OpenAPI oficial de MongoDB Atlas, y se aplicó una corrección directa sobre el JSON del panel, verificada como funcional.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-1748](https://smartit-ar.atlassian.net/browse/GITIN-1748) |
| Sistema | Grafana (`monitoreosp.smartfran.com`) — datasource `SmartFran - MongoDB Atlas`, plugin `grafana-mongodb-atlas-datasource` |
| Severidad | Medio |
| Detectado | 03/08/2026 |
| Resuelto | 03/08/2026 |
| Responsable | SRE |

## Causa raíz

El plugin de datasource `grafana-mongodb-atlas-datasource` (Valiton GmbH, **v1.0.0, publicado 2019-04-10, sin actualizaciones desde entonces**, compilado para Grafana 6.x pero corriendo sobre Grafana 7.3.7) tiene hardcodeados en su código fuente (`src/types.ts`) los nombres de dimensión `CACHE_USAGE_USED` y `CACHE_USAGE_DIRTY` para la categoría "Process Measurements". Comparando contra la especificación OpenAPI oficial de MongoDB Atlas (repositorio público `mongodb/openapi`) para el endpoint que el plugin efectivamente consume (`GET /groups/{groupId}/processes/{processId}/measurements`), los nombres válidos reales son `CACHE_USED_BYTES` y `CACHE_DIRTY_BYTES` — los dos valores hardcodeados en el plugin nunca fueron correctos. El resto de las dimensiones del plugin (incluyendo la que confirmó que la conexión/datasource funcionaba, `NETWORK_BYTES_IN`) sí coinciden con la API real.

**Por qué costó diagnosticar esto:** el backend del plugin descarta el error real devuelto por la API de Atlas y responde siempre con el mensaje genérico `{"message": "Metric request error"}`, sin más detalle ni en el cuerpo de la respuesta HTTP ni en el Query Inspector de Grafana. No hay forma de llegar a la causa por configuración o por los canales normales de diagnóstico (logs del cliente, inspector de queries) — requirió leer el código fuente del plugin y contrastarlo con la especificación pública de la API de Atlas. Este tiempo de diagnóstico es atribuible directamente a que tanto Grafana como el plugin están desactualizados (plugin sin mantenimiento desde 2019, sin versión mayor posterior que pudiera haber corregido el nombre o mejorado el manejo de errores).

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Panel "MongoDB: Cache" sin datos desde su creación por nombre de dimensión inválido (`CACHE_USAGE_USED` en vez de `CACHE_USED_BYTES`) | Medio — afectaba visibilidad de un panel definido como parte del monitoreo de rollback de GITIN-1741 |
| H2 | El backend del plugin reenvía el `dimensionId` recibido hacia la API de Atlas sin validarlo contra su propia lista hardcodeada — permitió corregir el panel editando directamente el JSON, sin necesidad de parchear o redesplegar el plugin | Bajo — informativo, es la vía que habilitó la corrección |
| H3 | El mismo error de nombre existe en `CACHE_USAGE_DIRTY` (debería ser `CACHE_DIRTY_BYTES`) — no usado aún en ningún panel, pero fallará igual si se agrega una serie de caché "Dirty" a futuro | Medio — riesgo latente, no materializado |

## Recursos afectados

| Componente | Impacto |
|---|---|
| Grafana (`monitoreosp.smartfran.com`) | Panel "MongoDB: Cache" sin datos hasta la corrección de hoy |
| Datasource `SmartFran - MongoDB Atlas` (plugin `grafana-mongodb-atlas-datasource` v1.0.0) | Fuente del bug — sin mantenimiento desde 2019, afecta potencialmente a otros paneles no auditados que usen dimensiones de caché |
| Monitoreo de `20260803_mongodb-downsize-m20` (GITIN-1741) | El panel corregido es parte de las métricas de Cache Usage definidas como criterio de rollback en ese ticket |

## Comandos ejecutados

Ver `20260803_grafana-cache-panel-fix_scripts.sh` para el detalle completo (comandos C1–C5: verificación de API key, replicación de la query fallida contra `api/tsdb/query`, identificación del plugin vía `api/frontend/settings`, comparación del código fuente del plugin contra la especificación OpenAPI de Atlas, y la corrección aplicada).

| # | Comando / Script | Propósito |
|---|---|---|
| C1–C2 | `20260803_grafana-cache-panel-fix_scripts.sh` | Confirmar autenticación y replicar el error fuera del navegador |
| C3 | `20260803_grafana-cache-panel-fix_scripts.sh` | Identificar plugin, versión y repositorio exactos |
| C4 | `20260803_grafana-cache-panel-fix_scripts.sh` | Confirmar causa raíz contra la especificación oficial de la API |
| C5 | `20260803_grafana-cache-panel-fix_scripts.sh` | Corrección aplicada (vía UI, no API) |

## Acciones propuestas

1. (SRE) ✅ Ya aplicado — corregido `dimensionId`/`dimensionName` de `CACHE_USAGE_USED` → `CACHE_USED_BYTES` en las 3 réplicas del panel "MongoDB: Cache". Confirmado funcionando por el usuario.
2. (SRE) Auditar el resto de los paneles que usan el datasource `SmartFran - MongoDB Atlas` en busca del mismo patrón (nombre de dimensión no coincide con la API real de Atlas) — no se descarta que otros paneles tengan el mismo problema sin haber sido notados aún.
3. (SRE) Evaluar reemplazo o fork mantenido del plugin `grafana-mongodb-atlas-datasource` — está sin actualizaciones desde 2019, compilado contra Grafana 6.x mientras el servidor corre 7.3.7, y oculta el error real de la API de Atlas ante cualquier falla futura, no solo esta.
4. (SRE) Si se agrega en el futuro una serie de caché "Dirty" a este u otro panel, usar `CACHE_DIRTY_BYTES` — no `CACHE_USAGE_DIRTY` (mismo bug, no materializado aún, ver H3).

## Hallazgos secundarios

- El tiempo de diagnóstico de este ticket es en sí mismo evidencia de deuda técnica: Grafana 7.3.7 (~2020) y un plugin sin mantenimiento desde 2019 significan que cualquier problema similar futuro con este datasource va a requerir el mismo nivel de investigación manual (lectura de código fuente + comparación contra la API real), no un diagnóstico de rutina. Vale la pena considerarlo al priorizar la Acción 3.
