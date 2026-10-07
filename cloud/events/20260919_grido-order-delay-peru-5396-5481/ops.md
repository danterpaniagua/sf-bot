# GITIN-2084 — [CLOUD] Demoras en Branches de Peru

**Tags:** SmartCloud, AWS, Azure, Performance

## Resumen

Grido reportó demoras en la recepción de pedidos en sucursales de Perú (5396 y 5481), detectado el 2026-09-19; posteriormente se incorporó al alcance la sucursal 5523 como chequeo adicional, aún sin confirmar si es un reporte independiente o solo una verificación preventiva. La telemetría directa de las colas SQS confirma que la demora es real y recurrente (picos típicos de 2-3 minutos, hasta ~26 minutos en el peor caso registrado), y seguía ocurriendo al momento del último relevamiento. La investigación se desplazó del bridge Orders/SQS (sin errores encontrados ahí) hacia `SmartFran-Cloud-Sales-Plan-PRO`, donde se identificó saturación de CPU por instancia (99-100%) sin respuesta de autoscale, y un evento aislado y severo de cascada de timeouts HTTP en la API de Sales (2026-09-18, 21:50-22:00 UTC) que coincide en minutos con picos reales de demora en dos sucursales. Esta correlación es la hipótesis más fuerte encontrada hasta ahora, pero no está confirmada como causa: no se ha trazado una dependencia real entre Sales-PRO y el bridge de Orders, y el mismo patrón de saturación de CPU no reprodujo la cascada en otras ventanas equivalentes (9/19 y el cambio de SKU del 9/20).

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2084](https://smartit-ar.atlassian.net/browse/GITIN-2084) |
| ID alerta | N/A — reporte del cliente (Grido) |
| Sistema | SmartFran Cloud — Orders API / Sales API (sucursales Perú 5396, 5481, 5523) |
| Severidad | Alta (degradación confirmada con fallos HTTP 500 reales en Sales API durante el evento del 18/09) |
| Detectado | 2026-09-19 |
| Resuelto | Pendiente — investigación en curso, causa raíz no confirmada |
| Responsable | Dante Paniagua (SRE) |

## Causa raíz

No confirmada. La hipótesis con más evidencia hasta el momento es que la saturación de CPU por instancia en `SmartFran-Cloud-Sales-Plan-PRO`, combinada con cambios manuales de plan de hosting realizados el 2026-09-18 (21:06-22:06 UTC), derivó en una cascada de timeouts HTTP a nivel de toda la API de Sales (21:50-22:00 UTC, ~20 endpoints afectados, incluyendo fallos 500 en `Sale/Create` y `Sale/Close`), que a su vez coincidió en minutos con picos reales de demora en las colas de Orders de las sucursales 5396 y 5481. Sin embargo, no se ha trazado ninguna dependencia de código entre Sales-PRO y el bridge Orders/SQS que explique el mecanismo, y picos de CPU de magnitud equivalente en otras ventanas (2026-09-19, y el cambio de SKU del 2026-09-20) no reprodujeron una cascada similar — lo que debilita "saturación de CPU" como causa suficiente por sí sola.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Demora real y recurrente confirmada vía CloudWatch `ApproximateAgeOfOldestMessage` en las colas de 5396, 5481 y 5523 — típico 2-3 min, pico de ~26 min, aún activa al momento del último pull (2026-09-19). | Alto |
| H2 | Instancias individuales de `SmartFran-Cloud-Sales-Plan-PRO` saturan repetidamente a 99-100% de CPU, sin respuesta confiable de autoscale. | Alto |
| H3 | Cascada aislada y severa de timeouts HTTP en toda la API de Sales (2026-09-18, 21:50-22:00 UTC, ~20 endpoints, incluye fallos 500 en `Sale/Create`/`Sale/Close`), correlacionada en minutos con picos reales de demora en 5396 y 5481 — candidata más fuerte encontrada, no confirmada como causal. | Alto (no confirmado) |
| H4 | La cascada de H3 no se reprodujo en picos de CPU de magnitud equivalente en otras ventanas (2026-09-19) ni en el cambio manual de SKU del 2026-09-20 — debilita la teoría de "saturación de CPU sola" como disparador suficiente. | Medio (informativo) |
| H5 | Las consultas a Graylog filtradas por campo `Service:<X>` devuelven 0 resultados incluso para mensajes confirmados por otra vía — gap ya documentado en GITIN-2068, sin resolver, limita el diagnóstico basado en logs. | Medio |
| H6 | No existe aún una dependencia de código confirmada entre Sales-PRO y el bridge Orders/SQS que explique el mecanismo de H3. | Informativo — gap de investigación |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| SQS `5396PRD_PlatformMessages.fifo` | Demora recurrente confirmada |
| SQS `5481PRD_PlatformMessages.fifo` | Demora recurrente confirmada, peor pico (~26 min) |
| SQS `5523PRD_PlatformMessages.fifo` | Mismo patrón, alcance ampliado, ventana de 4h |
| App Service Plan `SmartFran-Cloud-Sales-Plan-PRO` | Saturación de CPU por instancia, cascada de timeouts del 18/09 |
| App Service Plan `SmartFran-Cloud-Orders-Plan-PRO` | Revisado, sin correlación directa encontrada hasta ahora |

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | SQS queue attributes (5396, 5481) | Snapshot de profundidad de cola |
| C2 | CloudWatch `ApproximateAgeOfOldestMessage` (5396, 5481, 48h) | Confirmar patrón de demora recurrente |
| C3 | Graylog query, intento fallido (host/path incorrecto) | Búsqueda de errores — no usar como referencia |
| C4 | Graylog query corregida, `Service:Orders AND AppLevel:Error AND (5396 OR 5481)` | Búsqueda de errores (0 resultados, inconcluyente — ver H5) |
| C5 | Graylog `Service:Orders` sin filtro, 1h | Chequeo de sanidad del filtro por campo (0 resultados, mismo gap conocido) |
| C6 | SQS queue attributes (5523) | Snapshot de profundidad de cola, alcance ampliado |
| C7 | CloudWatch `ApproximateAgeOfOldestMessage` (5523, 4h) | Confirmar mismo patrón en sucursal ampliada |
| C8 | Graylog free-text `"5523"`, 4h | Validar patrón de búsqueda libre vs. filtro por campo |

Detalle completo en `cloud/events/20260919_grido-order-delay-peru-5396-5481/scripts.sh`.

## Acciones propuestas

1. Trazar la dependencia real a nivel de código entre Sales-PRO y el bridge Orders API/SQS — necesario para explicar por qué una cascada del lado de Sales demoraría el procesamiento de la cola de Orders.
2. Verificar si Orders-PRO (el consumidor real de SQS) presentó alguna anomalía (errores, reinicios, deploys) en la ventana 22:00-22:10 UTC del 2026-09-18, inmediatamente posterior a la cascada.
3. Confirmar el tier/SKU real de `SmartFran-Cloud-Sales-Plan-PRO` antes y después del cambio manual del 2026-09-20T02:18Z (`az appservice plan show`).
4. Obtener la configuración de la regla de autoscale de `SmartFran-Cloud-Sales-Plan-PRO` (`az monitor autoscale show`) para determinar por qué no hubo scale-out durante los picos confirmados de 99-100% CPU del 2026-09-19.
5. Determinar qué diferenció la ventana del 2026-09-18 21:50-22:00 UTC de los demás eventos de CPU/cambio manual equivalentes que no reprodujeron la cascada.
6. Obtener baseline histórico previo al 2026-09-17 para 5396/5481/5523, para confirmar si el patrón de demora recurrente es nuevo o preexistente.
7. Re-consultar Graylog para la sucursal 5523 con un límite mayor (o filtro `AND AppLevel:Error`), dado que solo se muestreó 100 de 390 resultados totales.

## Hallazgos secundarios

- Varias consultas realizadas durante la investigación (CPU por instancia vía Azure Monitor, Application Insights `requests`/`dependencies`, y el reporte generado por `/cloud-appservice-perf-report`) no están aún registradas en `scripts.sh` — solo las consultas C1-C8 (SQS y Graylog) lo están. Se recomienda completar `scripts.sh` con los comandos faltantes para cumplir con la política de persistencia de evidencia del proyecto.
