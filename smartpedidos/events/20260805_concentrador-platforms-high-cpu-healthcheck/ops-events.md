# Eventos — 20260805_concentrador-platforms-high-cpu-healthcheck

## 2026-08-05 — Detección e investigación inicial

Reporte de degradación de CPU sostenida en concentrador-service y platform-service (cluster ECS `smartfran-pedidos-production`), aproximadamente 16:30-18:15 hora local. Relevamiento inicial: historial de eventos ECS (C1), `stoppedReason` de tareas detenidas (C2), `CPUUtilization` por servicio (C3), configuración de health check de ambos Target Groups (C4). Confirmado: platform-service sufrió un ciclo de reinicio de tareas por health check (~20 eventos, cada 2-3 min, 17:15-18:01); concentrador-service no fue reiniciado en ningún momento.

## 2026-08-05 — Causa raíz identificada

Exportación de Graylog (`All-Messages-search-result.csv`, 5693 filas, PERF/INFO de concentrador-service) más paneles de Grafana/CloudWatch (C7). Confirmado: degradación/caída parcial de la API de PediGrido (`app.pedigrido.com`) entre ~16:28 y 18:02 hora local — llamadas de 125-218s, 354 de ~1600 con error de servidor (524/502/503/500). Identificado en código: cliente HTTP compartido de concentrador-service sin timeout, cron de sincronización con PediGrido cada 1 minuto sin protección de superposición. Diff de task definitions (C5) descarta un despliegue de código como disparador — el único cambio fue cpu/memory.

## 2026-08-05 — Mitigación aplicada y ticket generado

Escalado de cpu/memory de ambas task definitions (concentrador-service `:317`→`:318`, `256`→`1024` CPU; platform-service `:252`→`:253`, `512`→`2048` CPU) como mitigación durante el incidente. Aumento posterior del `MinCapacity` del Application Auto Scaling de platform-service de `5` a `10`. Investigación convergida, ticket `GITIN-1783` generado con hallazgos, causa raíz y acciones propuestas. Email a Operaciones enviado con el resumen.

## 2026-08-06 — Reversión de la mitigación de capacidad

Task definitions revertidas a sus revisiones previas al incidente: concentrador-service `:318`→`:317`, platform-service `:253`→`:252`. Criterio: el escalado de cpu/memory nunca fue la corrección real, coincidió con la recuperación de PediGrido, no con una corrección del defecto de fondo (la causa raíz sostenida es la ausencia de timeout, no el mecanismo de health check). Verificación en dos tiempos vía `describe-services`/`describe-scalable-targets` (C8, C9): primer chequeo mostró el `MinCapacity` de platform-service aún en `10` (no revertido); segundo chequeo, más tarde la misma sesión, confirmó que también fue revertido a `5`. Estado final: ambos servicios de vuelta a su spec y capacidad previos al incidente, sin ningún colchón. Ticket y email a Operaciones actualizados para reflejar la reversión completa y el riesgo que reabre (fixes de código de los puntos 1 y 2 de Acciones propuestas todavía pendientes).

## 2026-08-06 — Validación directa en código de la ausencia de timeout

Lectura directa de `repos/dev-src-smartPedidos-concentradorService` (clon local de solo lectura). Confirmado: `api/src/utils/httpClient.js:5` — `axios.create()` sin objeto de configuración, ninguna clave `timeout` en el archivo. `api/src/controllers/branch.js:1110-1130` — `headersConfig` del llamado a `v1/locals/status` contiene solo `headers`, sin `timeout` por request. `api/src/controllers/branch.js:1744`/`:1767` — `schedulePediGridoOffline = '*/1 * * * *'` conectado a `checkOfflinePOSpedigrido()`, sin guarda de superposición visible. Los tres elementos de la causa raíz quedan confirmados por lectura de código, no solo inferidos de logs — agregado al ticket con referencias exactas de archivo y línea.

## 2026-08-06 — Verificación de timeout en platform-service (búsqueda pendiente de H6)

Lectura directa de `repos/dev-scr-smartPedidos-platformsService` (clon local de solo lectura), buscando `timeout` en todo el árbol `api/src`. Confirmado: `api/src/index.js:21` — `axios.defaults.timeout = 20000` (20 segundos), fijado una sola vez al arrancar el proceso, sin condición que lo desactive. `platforms/management/platform/thirdParty.js` (donde vive el llamado a `ConfirmarPedido`, líneas 162/259/434/519) importa el `axios` global y llama `axios.post(url, body, headers)` sin override de `timeout` por request — hereda el default de 20s. A diferencia de concentrador-service, platform-service no está expuesto al mismo mecanismo de acumulación sin límite. Actualicé la investigación y el ticket (Causa raíz, H6) para reflejar esto — H6 bajó de riesgo Medio a Bajo, dado que la brecha real (si PediGrido disparó o no la sobrecarga de platform-service) sigue abierta, pero el mecanismo de acumulación sin límite queda descartado para este servicio.

## 2026-08-06 — Segundo export de Graylog (logs propios de platform-service) y corrección del hallazgo de timeout

**Resultado:**
Recibí un segundo archivo de Graylog, `All-Messages-search-result(3).csv` (51.158 filas, 100% `platforms-service`, ventana 18:00 UTC 05/08 a 02:00 UTC 06/08) — cierra la brecha de datos que venía abierta desde la investigación inicial (H6). Analicé el archivo con un script Python ad-hoc (parseo de CSV + JSON embebido en el campo `message`, no guardado como script del evento por ser exploratorio de una sola vez).

Encontré dos correcciones al hallazgo que había escrito hace instantes: (1) los handlers reales de las acciones de PediGrido (`readyOrder`/`dispatchOrder`/`deliveryOrder`) están en `rapiboy.js:388/440/499`, no en `thirdParty.js` como asumí al leer solo el código — el `ConfirmarPedido` de `thirdParty.js` es un path genérico distinto, no el que genera los logs `platform=PediGrido` que aparecen en los datos reales. (2) el timeout de 20s de `axios.defaults.timeout` **no se cumple de forma estricta**: 24 de 8.420 llamadas a PediGrido superaron los 20.000ms (máximo real 34.353ms), todas con `status: 200`. Corregí la afirmación anterior en la investigación y el ticket — sigue siendo una situación mucho menos severa que la de concentrador-service (máximo 34,3s vs 125-218s), pero no es un límite estricto como había afirmado inicialmente.

Además, comparé la latencia dentro de la ventana confirmada de degradación de PediGrido (19:28-21:02 UTC) contra el resto de la exportación: el promedio no cambia (3.152ms vs 3.027ms), pero la tasa de llamadas severas (>20.000ms) es ~11 veces mayor dentro de la ventana (1,8% vs 0,16%). Esto es la primera evidencia propia de platform-service (no solo coincidencia temporal) de que la degradación de PediGrido también alcanzó sus propias llamadas — a escala mucho menor que en concentrador-service. Actualicé la investigación, el ticket (Causa raíz y H6) con esta corrección y este hallazgo.

## 2026-08-06 — Alarma de auto-scaling por CPU nunca se disparó durante el incidente

**Comando:** C12-C13 — `aws cloudwatch describe-alarm-history` sobre la alarma de la política existente de auto-scaling de platform-service (`Smartfran-Platform-CPU-Policy`), y `get-metric-statistics` de `CPUUtilization` (Average/Maximum) para la ventana 16:00-19:00 hora local del 05/08.
**Resultado:**
`describe-alarm-history` devolvió `AlarmHistoryItems: []` — sin ninguna transición de estado durante el incidente. Los datos de `CPUUtilization` muestran el promedio siempre por debajo de ~13% (máximo de promedio 12,7%) mientras el máximo llegó a 75,4% (16:40), 77,4% (16:55) y 46,3% (17:00).

Confirmé que la política de auto-scaling existente (target tracking sobre `ECSServiceAverageCPUUtilization`, umbral 60%) nunca pudo haberse disparado durante el incidente — un pico de CPU en una sola tarea, diluido entre 5 tareas del fleet, no acerca el promedio al 60%. Esto es una limitación estructural de la métrica (target tracking en ECS solo soporta promedio, no máximo), no una mala configuración. Documenté el hallazgo y propuse una política adicional de step-scaling sobre una alarma de CloudWatch con `Statistic: Maximum` — no ejecutada aún, pendiente de confirmación de umbrales.

## 2026-08-06 — Health check de platform-service reconfigurado (mecanismo reemplazado, no ajustado)

**Resultado:**
Confirmé vía `describe-target-groups` que el Target Group de platform-service quedó reconfigurado a `Path: /`, `Matcher: 404` (`Timeout: 5s`, `Interval: 30s`, `Unhealthy: 2`, `Healthy: 5`) — antes usaba `/api/metrics/health-check` con `Matcher: 200`, basado en el autorreporte de `os.loadavg() > 0.7` de la aplicación.

Validé contra el código fuente de platforms-service que un `GET /` sin autenticar responde `404` en operación normal: la ruta está explícitamente exceptuada del middleware JWT (`app.js:35`), el middleware de permisos no aplica ninguna verificación sin header `Authorization`, y ninguna ruta registrada (ni bajo `/api`, ni el router de PeYa montado en `/`) coincide con el path — cae al 404 implícito de Express. Con este cambio, el mecanismo que generó el ciclo de reinicios de platform-service durante el incidente (health check dependiente de la carga del proceso) queda eliminado, no solo ajustado con histéresis como proponía originalmente el ítem 4 de acciones propuestas — actualicé ese ítem en el ticket para reflejarlo como aplicado.
