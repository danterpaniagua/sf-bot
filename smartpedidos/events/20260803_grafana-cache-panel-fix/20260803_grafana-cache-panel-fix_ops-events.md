# Eventos — 20260803_grafana-cache-panel-fix

## 2026-08-03 15:10 — Reporte inicial del error

El usuario reportó que el panel "MongoDB: Cache" en el dashboard de `monitoreosp.smartfran.com` fallaba con `Metric request error` (500) al graficar `CACHE_USAGE_USED` para las 3 réplicas de `PedidosSmartfran` vía el datasource de MongoDB Atlas.

## 2026-08-03 15:15 — Descarte de causas por configuración del panel

Probé variaciones de la categoría de métrica (`database_measurements` vs `process_measurements`) y presencia/ausencia de los campos `database`/`disk` en el JSON del panel — mismo error en todos los casos. Confirmé, con una prueba de aislación pedida al usuario, que otros paneles del mismo datasource (CPU, RAM, Network Traffic) funcionaban con datos reales, acotando el problema específicamente a la dimensión `CACHE_USAGE_USED`.

## 2026-08-03 15:30 — Configuración de API key de Grafana

El usuario pidió guardar un API key de Grafana (TTL 24 días). Por política del proyecto no se persiste en el repo ni en memoria — se guardó en `~/.grafana_vars` (fuera del repo, permisos 600) y se agregó un `source` condicional en `~/.bashrc`.

## 2026-08-03 15:35 — Réplica del error fuera del navegador y ubicación del plugin

Con el API key, repliqué la query fallida directamente contra `api/tsdb/query` — mismo error genérico sin más detalle en el cuerpo de la respuesta. Vía `api/frontend/settings` (accesible sin permisos de Admin/Editor) identifiqué el datasource id 2 como el plugin `grafana-mongodb-atlas-datasource` v1.0.0 (2019-04-10, sin actualizaciones), repositorio público en GitHub.

## 2026-08-03 15:40 — Causa raíz confirmada

Comparé el código fuente del plugin (`src/types.ts`, hardcodea `CACHE_USAGE_USED`/`CACHE_USAGE_DIRTY`) contra la especificación OpenAPI oficial de MongoDB Atlas (`mongodb/openapi`, GitHub) para el endpoint de measurements que el plugin consume — los nombres válidos reales son `CACHE_USED_BYTES`/`CACHE_DIRTY_BYTES`. Confirmé además, leyendo el backend en Go del plugin, que no valida el `dimensionId` recibido contra su propia lista — permite corregir editando directamente el JSON del panel sin parchear el plugin.

## 2026-08-03 15:45 — Corrección aplicada y verificada

Di instrucciones paso a paso (panel ▾ → More ▸ Panel JSON) y el JSON corregido con `dimensionId: "CACHE_USED_BYTES"` para las 3 réplicas. El usuario confirmó que el panel ahora muestra datos correctamente.

## 2026-08-03 15:50 — Ticket formalizado

Usuario proveyó el ticket Jira [GITIN-1748](https://smartit-ar.atlassian.net/browse/GITIN-1748). Se documentó el ticket completo (`investigation.md`, ticket principal, este log, y `_scripts.sh` con los comandos de diagnóstico).
