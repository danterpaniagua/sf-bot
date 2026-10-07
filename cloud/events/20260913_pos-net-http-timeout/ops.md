**Tags:** `SmartCloud` `CloudPOS` `Azure` `Performance` `PROD`

## Resumen

Varios POS en la nube, en ambos tenants (GRIDO y WEISS), vienen mostrando el error genérico "Uups algo salió mal.... intente nuevamente" (código `net_http_request_timeout`) al operar, de forma recurrente desde el 2026-09-12. El App Service `SmartFran-Cloud-Sales-PRO` viene colapsando repetidamente por `System.OutOfMemoryException`, forzando reinicios de su worker process que dejan sin respuesta a las requests de POS que caen en la instancia afectada en ese momento, hasta que el cliente agota su propio timeout HTTP. Se deberá identificar y corregir el origen del crecimiento de memoria en Sales-PRO, y ajustar la capacidad de autoscaling del App Service Plan, hoy insuficiente para absorber el problema.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2040](https://smartit-ar.atlassian.net/browse/GITIN-2040) |
| ID alerta | N/A — reportado directamente, no vía alerta automática |
| Sistema | SmartFran Cloud — `SmartFran-Cloud-Sales-PRO` (App Service, ambos tenants GRIDO/WEISS) |
| Severidad | Alta |
| Detectado | 2026-09-13 (patrón recurrente; inicio real del crash-loop: 2026-09-12T23:15:26Z) |
| Resuelto | No — causa raíz confirmada, remediación pendiente |
| Responsable | Dante Paniagua, SRE |

## Causa raíz

`SmartFran-Cloud-Sales-PRO` viene sufriendo crashes repetidos por `System.OutOfMemoryException` (confirmado vía el detector de Proactive Crash Monitoring de Azure App Service: 7 crashes solo el 2026-09-13). Cada crash fuerza a ANCM a matar y reiniciar el worker process, dejando sin respuesta cualquier request en curso en esa instancia hasta que expira el timeout HTTP por defecto (~100s) del cliente `SFC.Sale` en Pos.Wasm (no tiene `Timeout` explícito configurado, a diferencia de `SFC.Sale.LongRunning`). El App Service Plan de Sales-PRO tiene un techo de autoscaling de 4 instancias en todos sus perfiles, ya alcanzado, por lo que no hay capacidad adicional disponible para absorber la presión de memoria. El origen exacto del crecimiento de memoria no está confirmado. Un análisis posterior sobre los 3 días completos de logs crudos (H9) mostró que, al momento de cada crash, prácticamente todos los endpoints del servidor se degradan a la vez (no uno solo) — descartando al candidato inicial (`GetPaginatedForReportByFilterAsync`) como causa aislada, ya que resultó ser crónicamente lento durante todo el período analizado, sin correlación con el momento de los crashes.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | `SmartFran-Cloud-Sales-PRO` crashea repetidamente por `System.OutOfMemoryException` (0xE0434352), confirmado vía el detector `appcrashes` de Azure — 7 crashes el 2026-09-13, inicio del patrón el 2026-09-12T23:15:26Z | Alto |
| H2 | El techo de autoscaling del App Service Plan (`SmartFran-Cloud-Sales-Plan-PRO`) es 4 instancias en los 3 perfiles configurados, sin excepción — ya alcanzado, sin capacidad de reacción adicional ante presión de memoria | Alto |
| H3 | El perfil de autoscaling activo la mayor parte del tiempo (noches de semana y fines de semana completos) no tiene ninguna regla reactiva — capacidad fija en 4 por cronograma, no por carga | Alto |
| H4 | El cliente `SFC.Sale` de Pos.Wasm no tiene timeout explícito configurado, heredando el default de 100s de `HttpClient` — confirmado en código (`Program.cs:214-218`) | Medio |
| H5 | **Revisado (ver H9-H11).** El endpoint `/api/v1/Shift/GetPaginatedForReportByFilterAsync` responde en 4-16 segundos — pero un análisis de los 3 días completos mostró que es así permanentemente, sin correlación con los crashes. Descartado como candidato aislado a la fuga de memoria | Bajo |
| H6 | La telemetría de App Insights (`requests`/`exceptions`/`dependencies`) está vacía para `Sales-PRO` y `Pos-PRO` en todas las consultas realizadas (48h) — brecha de observabilidad independiente de este incidente | Medio |
| H7 | En el stream `Service:"Sales"` de Graylog, los campos `ElapsedMilliseconds`/`StatusCode` no están efectivamente promovidos a nivel superior, pese a que la documentación (`docs/graylog-log-fields.md`, GITIN-1940) los da por confirmados — seguimiento bajo GITIN-2034 | Bajo |
| H8 | Ningún deploy reciente coincide con el inicio del patrón de crashes (último deploy a Sales-PRO: 2026-09-02, 10 días antes) — descarta un release como disparador | — |
| H9 | **Nuevo.** Reconstruyendo la tabla de tiempos de respuesta por endpoint sobre los 3 días completos (desde el JSON crudo, bypaseando la promoción rota de Graylog), se confirmó que en cada crash prácticamente todos los endpoints se degradan a la vez (ej. `Sale/Create` de 88ms a 7,6s promedio/263s máximo en la ventana previa al crash del 12/09 23:15) — consistente con el proceso completo trabado (presión de memoria/GC), no con una consulta puntual | Alto |
| H10 | **Nuevo, confirmado contra documentación oficial de Microsoft.** Decenas de mediciones de tiempo de respuesta en distintos endpoints y horarios convergen en un techo muy consistente de ~230 segundos. Verificado contra [Web request times out in Azure App Service](https://learn.microsoft.com/en-us/troubleshoot/azure/app-service/web-request-times-out-app-service) (Microsoft Learn): es el timeout de idle-connection del Azure Load Balancer, fijo en 230s para apps Windows (240s en Linux), no configurable desde el lado de la aplicación. Sales-PRO es Windows — coincide exacto. Confirma que es la plataforma, no el código de la app, la que corta la conexión cuando el proceso queda sin responder | Alto |
| H11 | **Nuevo.** El patrón de degradación (H9/H10) se extiende en franjas de varias horas el 13/09 (ej. 01:00-04:00 y 14:50-21:20 UTC), más amplias que los 7 crashes puntuales confirmados por el detector de Azure — el impacto real en los POS pudo haber sido más prolongado que lo que reflejan esos 7 eventos | Medio |

## Recursos afectados

| Recurso | Tipo | Detalle |
|---|---|---|
| `SmartFran-Cloud-Sales-PRO` | App Service | 4 instancias activas; crashea repetidamente por OOM |
| `SmartFran-Cloud-Sales-Plan-PRO` | App Service Plan | Techo de autoscaling en 4 instancias, ya alcanzado |
| GRIDO (tenant) | Franquicia | POS afectados, timeouts confirmados en tráfico real |
| WEISS / tenant adicional (`org_z72xsKwcFsVLHF3c`, `org_vV0MNYuL3COJnBWa`) | Franquicia | POS afectados, timeouts confirmados en tráfico real — mapeo exacto org_id→franquicia pendiente |

## Cronología de reportes y escalamiento

| Fecha/Hora (ART, UTC-3) | Evento |
|---|---|
| Sábado 2026-09-12, 21:00 | CAC reportó incidentes de POS |
| Domingo 2026-09-13, 20:00 | Reunión con equipos de Dev y Ops |
| Lunes 2026-09-14, 20:00 | Escalamiento |

El primer reporte de CAC (sábado 21:00 ART) cae ~45 minutos después del inicio confirmado del crash-loop (2026-09-12T23:15:26Z UTC = 20:15 ART) — consistente con la cronología técnica ya establecida.

## Comandos ejecutados

Ver `scripts.sh` para el detalle completo. Resumen:

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | App Insights requests sin filtrar (Pos-PRO) | Verificar si hay telemetría básica |
| C2 | `az account show` | Verificación de sesión/suscripción Azure CLI |
| C3 | Listado de Load Balancers | Descartar LB como parte del path de red |
| C4 | Listado de Application Gateways | Descartar App Gateway como parte del path de red |
| C5 | App settings de App Insights (Pos-PRO) | Confirmar Instrumentation Key correcta |
| C6 | Listado de componentes de App Insights | Confirmar mapeo componente↔App Service |
| C7 | Métricas de plataforma Sales-PRO (6h) | Buscar señales de degradación |
| C8 | Métricas de plataforma Business-PRO (6h) | Descartar a Business-PRO como causa |
| C9 | App Insights exceptions (Sales-PRO, 48h) | Buscar excepciones registradas por SDK |
| C10 | Descarga de `eventlog.xml` vía Kudu (Sales-PRO) | Hallar reinicios forzados del worker process |
| C11 | Historial de deployments (Sales-PRO) | Descartar un release como disparador |
| C12 | App Insights dependencies, targets fiscales (Sales-PRO) | Evaluar dependencia externa como causa |
| C13 | Listado de detectores de diagnóstico (Sales-PRO) | Ubicar el detector de crashes correcto |
| C14 | Detector `appcrashes` (Sales-PRO) | ★ Confirmación de causa raíz (OOM) |
| C15 | Graylog — sanity check `smartfran-pos-wasm` | Confirmar tráfico vivo del cliente |
| C16 | Graylog — fallos HTTP del `HttpLoggingHandler` (24h) | ★ Confirmación del mecanismo del lado cliente |
| C17 | Graylog — StatusCode 5xx en `smartfran-pos-wasm` | Descartar que las fallas lleguen a completarse con status |
| C18 | ARM — instancias vivas de Sales-PRO | Confirmar cantidad real de instancias |
| C19 | `az monitor autoscale list` | ★ Confirmar techo de autoscaling |
| C20 | Graylog — logs server-side Sales, ventana del crash | Reconciliar con la vista del cliente |
| C21 | Graylog — logs server-side Sales, ventana continuación | Completar la reconciliación |
| C22 | Graylog — correlación puntual por TraceKey | ★ Prueba directa end-to-end |

## Acciones propuestas

1. Investigar el origen del crecimiento de memoria en `SmartFran-Cloud-Sales-PRO`. Foco revisado: no es un endpoint aislado (H5 descartado) — investigar por qué el proceso completo queda sin responder (GC/presión de memoria general) y, si se confirma H10, por qué se alcanza un timeout de plataforma de ~230s con tanta frecuencia (Dev).
2. Revisar y ampliar el techo de autoscaling del App Service Plan `SmartFran-Cloud-Sales-Plan-PRO` — actualmente fijo en 4 instancias en todos los perfiles (SRE).
3. Agregar una regla de autoscaling reactiva (memoria o CPU) a los perfiles sin lógica de reacción ("Profile 1" noches de semana, "Profile 2" fin de semana), que hoy dejan la capacidad fija sin importar la carga (SRE).
4. Investigar por qué la telemetría de App Insights (`requests`/`exceptions`/`dependencies`) está vacía para los App Services Windows (`Sales-PRO`, `Pos-PRO`) — brecha de observabilidad independiente de este incidente (Dev/SRE).
5. Evaluar si corresponde un timeout explícito más corto (con reintento) o un manejo de error más claro en el cliente `SFC.Sale` de Pos.Wasm, dado que hoy hereda el default de 100s de `HttpClient` (Dev).
6. Confirmar el mapeo de `org_id` a franquicia para los dos tenants identificados en el tráfico de fallas (`org_z72xsKwcFsVLHF3c`, `org_vV0MNYuL3COJnBWa`) vía la clave `organizations` de App Configuration (SRE).

## Hallazgos secundarios

- Discrepancia de documentación en `docs/graylog-log-fields.md`: los campos `ElapsedMilliseconds`/`StatusCode` no están efectivamente promovidos a nivel superior en el stream `Service:"Sales"`, pese a que el documento da por confirmada esa promoción (GITIN-1940). Trabajo de promoción de `TimeTaken`/`ElapsedMilliseconds` en `PROD-Sales-AppServiceHTTPLogs` y en `event_original.Properties.ElapsedMilliseconds` tracked aparte bajo GITIN-2034.
- Dos instancias de `wn1xsdwk0006JP` (Sales-PRO) reportaron estado `UNKNOWN` en el listado de instancias del ARM API en el momento de la consulta — no investigado en profundidad en este ticket, queda como seguimiento.
