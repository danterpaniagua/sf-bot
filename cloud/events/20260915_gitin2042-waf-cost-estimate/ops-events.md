# Eventos — 20260915_gitin2042-waf-cost-estimate

## 2026-09-15 11:00 — Apertura de la investigación y contexto heredado

He creado `investigation.md` y he vinculado esta estimación con GITIN-1938 (Opción B: DNS directo, sin APIM, WAF extendido a retail). He confirmado que el alcance requiere dos ambientes completos (PROD y no-prod) según lo ya definido en esa investigación.

## 2026-09-15 11:05 — Datos de tráfico recibidos del dev de cloud responsable

He recibido por email el desglose de requests HTTP del POS (Blazor WASM), basado en lectura de código, no en medición real: piso de 8-10 requests por venta, techo ~20 con toda la configuración activa, más tráfico de fondo por POS abierto (heartbeat cada 50s, sync de promos cada 15min, relay de logs hasta 1 POST/5s, SignalR). El propio dev señaló que el tráfico de fondo (~30% de su estimación) debería resolverse antes de adoptar el WAF.

## 2026-09-15 11:15 — Pricing real vía Azure Retail Prices API

**Comando:** C1, C2
**Resultado:**
Front Door Premium: Base Fee $330/mes, Requests $0.015/10K, Data Transfer In $0.02/GB, Out $0.0825/GB — WAF incluido sin cargo adicional (no existe meter separado). Application Gateway WAF_v2 (`eastus2`): Fixed Cost $0.36/hora, Capacity Units $0.008/CU-hora.

He decidido estimar ambos productos en paralelo en lugar de comprometerme a uno solo.

## 2026-09-15 11:40 — Tráfico real Sales-PRO y validación de Pos-PRO

He reutilizado el dataset de `cloud/events/20260913_pos-net-http-timeout/` (Sales-PRO, misma ventana) como primer punto de datos reales: 698.431 requests en 91,67h para 200 franquicias. He verificado que el tráfico de Pos-PRO capturado por el filtro por defecto del script (`--all-paths` no usado) está dominado en 99,7% por `Status/Health` — no es tráfico de API de negocio ni de descarga de assets estáticos del cliente; el bundle WASM real queda fuera del alcance de este pull.

## 2026-09-15 12:00 — Tráfico real de los 7 App Services restantes

**Comando:** C3-C9
**Resultado:**
He obtenido el desglose real de Admin, Business, Catalog, Orders, Person, Platform y Pos, misma ventana que Sales. Total combinado de los 8 servicios: 3.231.060 requests (176,24 req/franquicia/hora). El heartbeat (`Orders/Queue/Heartbeat`, 1.251.110 hits) coincide de forma cercana con la estimación del dev (68,24 medido vs. 72/h estimado).

He detectado una discrepancia real entre el email del dev y los datos medidos: la consulta de favoritos que el dev describió como repetida 3 veces por venta aparece en los datos reales con un ratio de apenas 0,02 respecto a las ventas — ~150 veces menos de lo esperado. No la he asumido resuelta; queda como pregunta abierta para el dev.

## 2026-09-15 12:20 — Identificación real de las Function Apps y corrección de infrastructure.md

He incorporado el listado real de las 4 Function Apps, tomado de Azure Portal (`SFC-CodeGenerator-PRO`, `SFC-PosWasmRelay-PRO`, `SFC-ScheduledJobs-PRO`, `SFC-TicketProcess-PRO`, todas Linux, mismo plan `P0v3`). He corregido `cloud/docs/infrastructure.md`, que documentaba 3 Function Apps con una convención de nombres completamente distinta y desactualizada.

He revisado el código fuente (`cloud/repo/SmartFran.Cloud`, rama `dev`) para verificar si estas Function Apps exponen APIs HTTP o son exclusivamente procesos batch. He confirmado que la hipótesis de "solo batch" no se sostiene: `CodeGenerator` es 100% HTTP (`[HttpTrigger]`, sin timers), `PosWasmRelay` también, y `ScheduledJobs` combina 4 timers internos con 5 endpoints HTTP reales, incluyendo `RegisterBusinessLog` — el endpoint de "log de negocio" que el email del dev mencionaba y que no había podido ubicar en los 8 App Services.

## 2026-09-15 12:35 — Tráfico real de las Function Apps vía Azure Monitor

**Comando:** C10, C11
**Resultado:**
He confirmado que estas Function Apps exponen las métricas estándar de plataforma (`FunctionExecutionCount`, `Requests`, etc.), sin necesidad de instrumentación Graylog. Totales, misma ventana: CodeGenerator 112.951, ScheduledJobs 155.145 (mezcla HTTP+timer, no separable con esta métrica), TicketProcess 183 (coincide casi exacto con las ~183 ejecuciones de timer esperadas cada 30min, confirma tráfico HTTP real ~0), PosWasmRelay 712.172.

He actualizado la tasa combinada confirmada a 221,25 req/franquicia/hora (8 App Services + CodeGenerator + PosWasmRelay, ambos 100% HTTP) — ScheduledJobs queda como cota superior, no como cifra confirmada, dado que no puedo separar su porción HTTP real de sus 4 jobs internos con la métrica disponible.

## 2026-09-15 13:00 — Modelo de costos: Front Door Premium vs Application Gateway WAF_v2

He construido la proyección lineal a 1.500, 2.000 y 2.600 franquicias usando la tasa confirmada, para ambos productos, cubriendo PROD + no-prod según GITIN-1938. Para Front Door, el costo es directamente calculable (fee fijo + $/millón de requests). Para Application Gateway, he determinado que el costo variable de Capacity Units no es calculable con precisión a partir de conteo de requests solamente — depende de negociación TLS y overhead de reglas WAF, ambos dependientes de la carga real; la guía de Microsoft es medirlo empíricamente sobre un gateway en funcionamiento, que hoy no existe. He entregado un rango basado en una heurística no oficial (~10-30 req/seg por CU), explícitamente marcado como de baja confianza.

He corregido un error propio: las cifras de Front Door presentadas antes de este punto solo incluían el meter de Requests, sin el fee base ($330/mes ×2 ambientes = $660/mes). Con la corrección aplicada, Application Gateway resulta más económico que Front Door en los 4 escenarios evaluados (200/1.500/2.000/2.600 franquicias).

## 2026-09-15 13:20 — Gráfico de consumo por endpoint y alerta de heartbeat

He construido `data/endpoint_consumption_chart.html` (barras horizontales, ordenado por volumen, heartbeat destacado en color de alerta) combinando los 8 App Services y las 4 Function Apps — total 4.211.511 requests en la ventana. Heartbeat representa el 29,7% de ese total combinado (dato que reemplaza el 38,7% calculado antes, cuando la base todavía no incluía las Function Apps).

## 2026-09-15 13:35 — Gráfico de líneas, consumo por servicio en el tiempo

He construido `data/timeseries_by_service_chart.html` — 8 series (una por App Service), buckets de 10 minutos, ventana completa (550 puntos por serie). No incluye las 4 Function Apps: `FunctionExecutionCount` solo está disponible por hora (PT1H) en Azure Monitor, no al mismo grano de 10 minutos que los App Services vía Graylog. Paleta categórica de 8 colores validada (`validate_palette.js`, ambos modos, todos los checks en PASS salvo un WARN de contraste en 3 tonos claros ya mitigado con leyenda y tooltip con texto).

## 2026-09-15 13:50 — Gráfico apilado por hora, App Services + Function Apps

He agregado los datos de 10 minutos a buckets de 1 hora (grupos de 6, último grupo parcial de 4) y confirmado que el alineamiento coincide exactamente con los 92 buckets horarios de `FunctionExecutionCount` (mismo timestamp de inicio en cada punto, sin faltantes). Con esa granularidad común, he agregado un segundo gráfico apilado al mismo archivo (`timeseries_by_service_chart.html`) con los 8 App Services más una banda agrupada "Function Apps (4)" — no le asigné un color categórico propio a cada Function App porque el sistema de paleta valida como máximo 8 tonos; el desglose real de las 4 queda en el tooltip.

## 2026-09-15 14:10 — Re-intento de H6 con el nuevo campo FunctionName (GITIN-2050) — sin éxito para esta ventana

Con el onboarding de Graylog completado (GITIN-2050), he intentado cerrar H6 filtrando `SFC-ScheduledJobs-PRO` por `FunctionName` en la misma ventana de esta ticket. La primera exportación volvió con 0 bytes, ni siquiera el header del CSV — no lo he asumido como "0 resultados" sin verificar, dado el patrón ya visto en esta misma investigación de tratar un resultado vacío como si fuera una confirmación real. He corrido dos queries de control sobre la misma ventana: 600.837 mensajes reales de `FunctionAppLogs` para ScheduledJobs existen en la ventana, pero 0 tienen `FunctionName` poblado. Confirmado: la promoción de campos se desplegó recién hoy, después de que corriera casi toda la ventana de medición — no es retroactiva. He actualizado H6 en `ops.md` para reflejar el intento y su resultado, en vez de dejarlo como si nunca se hubiera probado.

## 2026-09-15 15:15 — Corrección: costo variable de AppGW estaba duplicado por error

He encontrado un error propio en el modelo de costos: había multiplicado ×2 tanto el costo fijo como el costo variable (Capacity Units) de Application Gateway para reflejar los 2 ambientes (PROD + no-prod), pero el costo variable de Front Door nunca se dobló de la misma forma — no-prod no tiene volumen real de franquicias que justifique duplicar tráfico ahí. He corregido AppGW para tratar el costo variable igual que Front Door: fijo ×2 (2 gateways reales), variable ×1 sobre la tasa medida de PROD solamente. Los totales de AppGW bajan levemente en los 4 escenarios (ej. a 2.600 franquicias: $557-$619 en vez de $588-$713). He actualizado `investigation.md` y `email_ops.md` con los números corregidos, y agregué una aclaración explícita en el mail sobre que son 2 WAFs reales, no una instancia facturada dos veces.

## 2026-09-15 16:00 — Tabla de pronóstico de requests y hora pico

He agregado al mail y a `investigation.md` una tabla de volumen de requests (hora/día/mes) para 200/1.500/2.000/2.600 franquicias, usando la tasa confirmada de 221,25 req/franquicia/hora. He medido también el pico real sobre los datos horarios ya construidos: 130.040 req/hora el 13/09 a las 19:20 UTC, 2,94x el promedio con 200 franquicias actuales. He proyectado ese mismo factor a 1.500/2.000/2.600 (no es una medición real a esa escala, lo dejé aclarado). He señalado que el costo ya calculado usa el promedio, no el pico — para Front Door no cambia nada (cobra por request real), pero para Application Gateway el rango de Capacity Units probablemente queda corto en la hora más cargada, ya que las CU se dimensionan para pico, no promedio — no recalculado, queda como brecha abierta.
