# Eventos — 20260913_pos-net-http-timeout

## 2026-09-13 — Apertura de investigación

He recibido el reporte de varios POS en la nube mostrando el error genérico "Uups algo salió mal.... intente nuevamente", con el código subyacente `net_http_request_timeout`, count 100. He confirmado que ambos tenants (GRIDO y WEISS) están afectados y que el problema es recurrente, ya que se había presentado el día anterior también. He abierto la carpeta de evento y comenzado el registro en `investigation.md`.

## 2026-09-13 — Descarte de Load Balancer / Application Gateway

**Comando:** C3/C4 — Inventario de Load Balancers y Application Gateways en la suscripción
**Resultado:**
Ambos listados vacíos.

He confirmado que no existe ningún Load Balancer ni Application Gateway delante de los App Services de SmartFran Cloud, en línea con lo ya documentado en `docs/infrastructure.md` (ausencia de WAF/APIM). El tráfico llega directo a cada App Service.

## 2026-09-13 — Telemetría de App Insights vacía en Pos-PRO

**Comando:** C1/C5/C6 — Consulta de requests sin filtrar, verificación de Instrumentation Key y listado de componentes
**Resultado:**
0 resultados en `requests` para las últimas 6h; la Instrumentation Key del App Service coincide exactamente con el componente `SmartFran-Cloud-Pos-PRO_new`.

He verificado que no se trata de un problema de conexión entre el App Service y el componente de App Insights, sino de una ausencia real de telemetría. He dejado esto marcado como una brecha a seguir por separado, no como causa de este incidente.

## 2026-09-13 — Confirmación de tráfico vivo del cliente Pos.Wasm en Graylog

**Comando:** C15 — Consulta sobre el stream `smartfran-pos-wasm` (relay `SFC-PosWasmRelay-PRO`)
**Resultado:**
322.571 mensajes en 6h, con timestamps vigentes al momento de la consulta.

He confirmado que el cliente Pos.Wasm está activo y llamando exitosamente a los backends (Orders-PRO, Business-PRO, función RegisterBusinessLog), descartando que el problema esté del lado del cliente mismo.

## 2026-09-13 — Métricas de plataforma, Sales-PRO y Business-PRO

**Comando:** C7/C8 — Métricas de plataforma (Http5xx, AverageResponseTime, Threads, MemoryWorkingSet) 6h
**Resultado:**
Sales-PRO: picos intermitentes de Http5xx (36, 53, 12) correlacionados con aumento de Threads (54→81). Business-PRO: saludable en todas las métricas.

He descartado a Business-PRO como causa contribuyente y he identificado a Sales-PRO como el servicio con la señal más fuerte de degradación.

## 2026-09-13 — Hallazgo en el Event Log de Windows de Sales-PRO

**Comando:** C10 — Descarga de `eventlog.xml` vía Kudu VFS
**Resultado:**
Evento 1005 ("Failed to gracefully shutdown application") comienza a repetirse desde 2026-09-12T23:15:26Z, escalando a reinicios forzados cada 10-90 minutos durante todo el 13/09.

He identificado que el worker process de Sales-PRO viene siendo reiniciado a la fuerza de forma recurrente desde el día anterior al reporte, coincidiendo con el patrón temporal reportado inicialmente.

## 2026-09-13 — Descarte de un deploy reciente como disparador

**Comando:** C11 — Historial de deployments de Sales-PRO
**Resultado:**
Último deploy: 2026-09-02T20:23:45Z (`OneDeploy`), 10 días antes del inicio del patrón de crashes.

He descartado que un release reciente sea el disparador del problema.

## 2026-09-13 — Confirmación de causa raíz: System.OutOfMemoryException

**Comando:** C13/C14 — Listado de detectores y consulta del detector `appcrashes` (Proactive Crash Monitoring) de Sales-PRO
**Resultado:**
7 crashes confirmados el 13/09 (04:05, 17:30, 18:10, 18:40, 19:15, 20:30, 23:55 UTC), todos `0xE0434352 - CLR Exception`, dos de ellos identificados puntualmente como `System.OutOfMemoryException`.

He confirmado mediante el propio detector de Azure que Sales-PRO viene colapsando repetidamente por falta de memoria administrada, y que la escalada coincide con los reinicios forzados ya identificados en el Event Log.

## 2026-09-13 — Confirmación del mecanismo del lado cliente

**Comando:** C16 — Consulta sobre fallos HTTP del `HttpLoggingHandler` del cliente Pos.Wasm, 24h
**Resultado:**
3.005 fallos totales, patrón dominante `failed after ~100000 ms ... "OperationCanceled"` sobre `/api/v1/Sale/Create` y otros endpoints de Sales.

He confirmado que el timeout que aparece en el POS corresponde al timeout por defecto (~100s) del cliente HTTP de Pos.Wasm, que se agota porque Sales-PRO nunca responde durante las ventanas de crash.

## 2026-09-13 — Confirmación de picos de memoria previos al crash

**Comando:** métricas de plataforma en grano fino (PT1M), 23:30Z-01:15Z
**Resultado:**
`MemoryWorkingSet` sube de ~759MB a ~1.62GB entre 23:30 y 23:57Z; `Threads` sube de ~54 a 75-79 en el mismo período; ambos vuelven a valores base inmediatamente después del crash de las 23:55.

He confirmado el patrón de acumulación de memoria previo a cada crash, y he descartado que los dos timeouts residuales observados más tarde (00:34, 01:02) formen parte del mismo patrón, ya que en esos momentos la memoria estaba en valores normales.

## 2026-09-13 — Confirmación del techo de autoscaling

**Comando:** C18/C19 — Listado de instancias vivas de Sales-PRO y configuración de autoscaling del App Service Plan
**Resultado:**
4 instancias activas confirmadas; todos los perfiles de autoscaling tienen capacidad máxima = 4, sin excepción. El perfil activo en el momento del crash confirmado (fin de semana, "Profile 2") no tiene ninguna regla reactiva, capacidad fija en 4.

He confirmado que el autoscaling no puede aliviar la presión de memoria porque ya está en su techo configurado, y que durante la ventana del crash analizado no había ninguna regla de escalado activa por diseño del cronograma.

## 2026-09-13 — Reconciliación con los logs del lado servidor de Sales-PRO

**Comando:** C20/C21/C22 — Consultas sobre el stream `Service:"Sales"` (GELF directo) alrededor del crash confirmado, y correlación puntual por TraceKey
**Resultado:**
Tráfico continuo y exitoso en los logs agregados del servidor durante toda la ventana del crash (esperable dado que 3 de 4 instancias seguían sanas); 0 resultados al buscar el TraceKey exacto de una falla confirmada del lado cliente.

He confirmado de forma directa, no solo por correlación temporal, que al menos una request específica jamás fue procesada ni logueada por Sales-PRO, consistente con haber caído en la instancia que colapsó por falta de memoria.

## 2026-09-13 — Identificación de un candidato para el origen de la fuga de memoria

**Resultado:**
El endpoint `/api/v1/Shift/GetPaginatedForReportByFilterAsync` respondió en 5.120ms y 6.209ms en dos llamadas cercanas al crash, contra un baseline de 10-100ms para el resto de los endpoints.

He dejado marcado este endpoint como el candidato más fuerte encontrado hasta ahora para explicar el crecimiento de memoria, sin confirmarlo aún como la causa real de la fuga — queda como línea de seguimiento para el equipo de desarrollo.

## 2026-09-14 — Tabla de tiempos de respuesta por endpoint (Graylog, GITIN-2034)

**Comando:** C23-C26 — Pivot de Graylog (Views Search) sobre `ElapsedMilliseconds` agrupado por `Path`, en buckets de 10 minutos, ventana de 3 días
**Resultado:**
El primer intento, contra el stream `PROD-Sales-AppServicePlan` usado en el resto de este ticket, devolvió solo 32 resultados en 3 días. Conteos de diagnóstico confirmaron que ese stream tiene 1.300.402 mensajes totales en la ventana pero solo 32 con `ElapsedMilliseconds`. Identifiqué que el campo con buena cobertura (`TimeTaken`/`CsUriStem`, corregido hoy bajo GITIN-2034) vive en un stream separado, `PROD-Sales-AppServiceHTTPLogs`, según lo documentado en `20260826_appservicehttplogs-stream-split`. Repetí la consulta contra ese stream correcto: 21.943 mensajes coincidentes, y el pivot final arrojó 823 filas — pero **todas concentradas entre las 10:10 y las 15:10 (hora local) de hoy**, sin ningún dato de los días 11, 12 o 13 de septiembre. Esto es consistente con que el fix de GITIN-2034 (que corrige la promoción de este campo) se desplegó recién esta mañana.

He confirmado que la tabla de tiempos de respuesta por endpoint solicitada **no puede reconstruirse para la ventana real del incidente** (crashes del 12 y 13 de septiembre) usando el campo promovido por Graylog, porque no se promovía correctamente antes del fix de hoy.

## 2026-09-14 — Reconstrucción de la tabla completa de 3 días desde el JSON crudo (bypass de la promoción rota)

**Comando:** C27-C30 — verificación de campos anidados sin promover, export CSV crudo de Graylog (`properties` sin parsear) y agregación local en Python
**Resultado:**
Confirmé que el JSON crudo (`properties`, un string sin parsear con `CsUriStem`/`TimeTaken`) está presente en cada mensaje independientemente de si la promoción a campo de nivel superior funcionó o no — 314.915 mensajes solo en la ventana del crash. Exporté el CSV crudo completo de los 3 días (595.472 filas) vía el endpoint de export de Graylog, y lo agregué localmente en Python por bucket de 10 minutos y `CsUriStem`, generando `data/sales_timetaken_by_path_3d_10m_RAW.csv` (9.066 filas) — esta vez sí cubriendo la ventana real del incidente.

Este análisis **reemplaza la caracterización anterior del candidato H5**: `/api/v1/Shift/GetPaginatedForReportByFilterAsync` resultó ser crónicamente lento (4-16 segundos) durante los 3 días completos, incluso en horarios sin ningún crash cerca — no es un pico que precede a cada crash, es simplemente un endpoint siempre lento, sin correlación con el timing de los crashes. En cambio, encontré que al momento de cada crash confirmado, **prácticamente todos los endpoints del servidor se degradan simultáneamente** (ej. ventana 23:10-23:30 del 12/09: `Sale/Create` pasa de 88ms a 7,6s promedio con máximos de 263 segundos; mismo patrón en `WsFeAr/CaeRequest`, `PaymentMethod/GetAll`, `Shift/CreateAndOpen`, etc.) — consistente con el proceso completo trabado (GC bajo presión de memoria), no con una sola consulta agotando memoria por sí sola.

También encontré un techo muy consistente de ~230 segundos en decenas de mediciones de `max_ms` en distintos endpoints y horarios, que coincide con un timeout de plataforma de Azure App Service documentado (no verificado independientemente en esta sesión, señalado como interpretación fuerte, no como hecho confirmado) — sugiere que el proceso queda completamente sin responder y es la plataforma, no el código de la aplicación, la que corta la conexión a los ~230s. Además, el patrón de degradación se extiende en franjas de varias horas (ej. 01:00-04:00 y 14:50-21:20 del 13/09), mucho más amplias que los 7 crashes puntuales confirmados por el detector de Azure — sugiere que el impacto real en los POS pudo haber sido más prolongado de lo que reflejan esos 7 eventos puntuales. Todo esto documentado en detalle en `investigation.md`.

## 2026-09-14 — Confirmación del timeout de ~230s contra documentación oficial de Microsoft

**Resultado:**
Verifiqué el hallazgo H10 contra la documentación oficial de Microsoft ("Web request times out in Azure App Service", Microsoft Learn): el techo de ~230 segundos es el idle timeout del Azure Load Balancer — fijo en 230s para apps Windows (240s en Linux), no configurable desde el lado de la aplicación. Sales-PRO es Windows, coincide exacto con los valores observados. Confirmé que es la plataforma, no el código de la aplicación, la que corta la conexión cuando el proceso queda sin responder — elevé H10 de "no confirmado" a "confirmado" en `investigation.md` y `ops.md`.

## 2026-09-14 — Recurrencia confirmada en vivo, con techo de autoscaling reducido

**Comando:** C31-C35 — métricas CPU/RAM en vivo (sitio + plan), SKU del plan, recheck de autoscaling, recheck de instancias vivas, recheck de Event Log/detector de crashes
**Resultado:**
He recibido un reporte del usuario indicando que el patrón está ocurriendo de nuevo. Confirmé que se trata del mismo problema recurriendo, no uno nuevo: `MemoryWorkingSet` de Sales-PRO muestra al menos 3 ciclos completos de acumulación-y-reinicio solo en las últimas 6 horas, con un pico de ~2,27GB a las 20:35Z — superior al pico de 1,62GB confirmado el 13/09. Cada pico coincide con picos de `CpuTime`, `AverageResponseTime` (hasta 26,9 segundos) y `Http5xx` (hasta 72 errores), el mismo patrón de proceso completo trabado ya documentado.

Encontré además que el techo de autoscaling de `SmartFran-Cloud-Sales-Plan-PRO` fue **reducido de 4/4/4 a 3/3/3** en los perfiles fijos desde el 13/09 — un cambio de configuración real, no solo una diferencia de horario/cronograma, que agrava el incidente en la dirección opuesta a lo recomendado en `ops.md`. Confirmé además solo 2 instancias vivas en este momento, por debajo incluso de ese nuevo techo reducido.

Verifiqué el mecanismo contra el detector de crashes de Azure: **9 crashes confirmados hoy, todos `0xE0434352`** (mismo código que el `OutOfMemoryException` ya confirmado como causa raíz) — 8 nuevos en aproximadamente 6 horas, contra 7 en todo el día del 13/09. Cada uno de los 9 coincide exactamente con un pico ya identificado en las métricas. Esto confirma cuantitativamente que la recurrencia es peor que el incidente original, no solo una repetición.

He dejado registrado todo en `investigation.md`. Pendiente decisión del usuario sobre si revertir el techo de autoscaling a 4 (además de la corrección manual a 3 ya sugerida).

## 2026-09-15 — Generalización de la herramienta de reporte (reutilizable para los 8 App Services)

**Resultado:**
Generalicé el script de reporte HTTP/CPU/RAM construido en este evento (`graylog_timetaken_report.py`) para que sirva sobre cualquiera de los 8 App Services de producción, no solo Sales-PRO. Lo reubiqué en `cloud/scripts/appservice_perf_report.py` (siguiendo la convención ya existente en ese directorio) y externalicé la lista de crashes, antes hardcodeada en el código Python (`DEFAULT_INCIDENTS`), a un archivo de texto plano (`incidents.txt`, formato `ISO_TIMESTAMP|Label`) junto a este evento. Agregué el parámetro `--app-label` para que los títulos de los gráficos no queden fijos en "Sales-PRO".

Creé la nueva skill `cloud-appservice-perf-report` (`.claude/commands/`), con la tabla de referencia completa (stream ID de Graylog, nombre de App Service y de App Service Plan) para los 8 apps, y el flujo de 3 pasos (export crudo de Graylog, pull de CPU/RAM con las tres agregaciones de Azure Monitor, generación del reporte). Registrada en las tablas de skills de `cloud/CLAUDE.md` y del `CLAUDE.md` raíz.

Regeneré el reporte de este evento desde la nueva ubicación del script y confirmé que la salida es estructuralmente idéntica (7 paneles, mismos datos) antes de borrar el script viejo. Detalle completo del cambio en `investigation.md` y `scripts.sh` (entrada C43).

## 2026-09-15 — Ticket Jira asignado

He recibido del usuario el ticket Jira para este incidente: [GITIN-2040](https://smartit-ar.atlassian.net/browse/GITIN-2040). Actualicé la referencia en `ops.md` (antes marcada como pendiente) y en `investigation.md`.

## 2026-09-15 — Cronología de reportes y escalamiento

He recibido del usuario la cronología de reportes y escalamiento del incidente: CAC reportó incidentes el sábado 2026-09-12 a las 21:00 ART, hubo una reunión con los equipos de Dev y Ops el domingo 2026-09-13 a las 20:00 ART, y un escalamiento el lunes 2026-09-14 a las 20:00 ART. Agregué esta cronología a `ops.md` y confirmé que el primer reporte de CAC cae ~45 minutos después del inicio del crash-loop ya establecido (2026-09-12T23:15:26Z).
