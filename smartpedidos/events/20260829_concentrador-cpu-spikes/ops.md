# 20260829_concentrador-cpu-spikes

**Tags:** SmartPedidos, Concentrador, AWS, Graylog, Performance, PROD

## Resumen

El 29/08/2026, a partir de aproximadamente las 10:00 hs (hora local, -03:00), se detectaron mediante Grafana varios picos de uso de CPU en concentrador-service (cluster ECS `smartfran-pedidos-production`), repitiéndose en distintos horarios a lo largo del día hasta al menos las 18:15 hs. No se registraron caídas ni reinicios del servicio durante estos picos. El análisis identificó como causa la sincronización periódica de estado de sucursales hacia PedidosYa, que en cada disparo procesa el total de sucursales activas de la plataforma sin límite de concurrencia, saturando momentáneamente el proceso. platform-service no se vio afectado en esta ventana.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-1964](https://smartit-ar.atlassian.net/browse/GITIN-1964) |
| ID alerta | No se dispuso de ID de alerta de monitoreo — detección vía Grafana |
| Sistema | AWS ECS Fargate `smartfran-pedidos-production` — concentrador-service |
| Severidad | Media |
| Detectado | 29/08/2026 ~10:00 hs (hora local) |
| Resuelto | Sí (mitigado) — 29/08/2026. Aumento de capacidad es temporal: desescalado programado para el 31/08/2026 (lunes). Corrección de causa raíz en código (puntos 1-3 de Acciones propuestas) queda pendiente como seguimiento de Dev, no forma parte del cierre de este ticket |
| Responsable | SRE |

## Causa raíz

`sincroCheckIns()` registra un cron dinámico por cada horario configurado en `platform.checkIns`, por plataforma y país. Para PedidosYa, cada disparo ejecuta `enviarEstadoPedidosYa()`, que consulta todas las sucursales activas del país y, sobre cada una, realiza un `GET` seguido de un `PUT` contra la API de PedidosYa (`integration-middleware.us.restaurant-partners.com`) — sin límite de concurrencia ni agrupamiento en lotes, a través del mismo cliente HTTP compartido sin timeout configurado que ya fue identificado como defecto en GITIN-1783. Con más de 1.100 sucursales activas, cada disparo lanza esa cantidad de llamadas simultáneas.

**Confirmado con la exportación de Graylog de la ventana del incidente (55.860 filas, PERF de concentrador-service):** los horarios de mayor volumen de logs coinciden, con 1 minuto de desfase, con cada pico de CPU observado en CloudWatch. Dentro de esas ráfagas, las llamadas hacia PedidosYa tuvieron una mediana de 36,5 segundos de duración (máximo 46,1s), todas con respuesta HTTP 200 — es decir, sin fallas del lado de PedidosYa, consistente con saturación autoinducida del propio proceso al lanzar más de mil llamadas simultáneas, no con una caída del proveedor externo (a diferencia de GITIN-1783, donde PediGrido sí estaba caído).

**Validado contra el código fuente:** los horarios de disparo de esta sincronización son anteriores a julio de 2026 (existían como arreglo fijo en el código); lo que cambió en julio de 2026 fue únicamente la forma de configurarlos, migrada a un valor editable en base de datos. La lógica de fan-out sin límite de concurrencia en la sincronización con PedidosYa es anterior a ese cambio. No se identificó una regresión de código reciente — es un defecto preexistente que probablemente se volvió visible al crecer la cantidad de sucursales activas de PedidosYa hasta el volumen actual.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | CPU de concentrador-service alcanzó picos de 99-100% (máximo) en múltiples ventanas de 5 minutos entre las 10:00 y las 18:15 hs, con promedio bajo — picos breves y recurrentes, no saturación sostenida | Medio |
| H2 | Las ráfagas de logs PERF coinciden, con 1 minuto de desfase, con cada pico de CPU registrado en CloudWatch — correlación directa, no solo temporal | Alto |
| H3 | Dentro de las ráfagas, ~1.100 llamadas GET y hasta ~1.000 PUT hacia la API de PedidosYa con latencias de hasta 46 segundos (mediana 36,5s), todas con respuesta HTTP 200 | Alto |
| H4 | La sincronización de estado con PedidosYa procesa todas las sucursales activas del país sin límite de concurrencia ni agrupamiento en lotes, a través de un cliente HTTP compartido sin timeout — mismo defecto de `httpClient` identificado en GITIN-1783, aún sin corregir | Alto |
| H5 | No se registraron eventos de reinicio/kill de ECS en concentrador-service durante los picos, consistente con su health check laxo (timeout 120s / intervalo 300s); platform-service no mostró afectación en la misma ventana | Bajo |
| H6 | concentrador-service no tiene ninguna política de auto-scaling configurada y corre con una única tarea, sin redundancia | Medio |

## Recursos afectados

| Componente | Impacto |
|---|---|
| concentrador-service | Picos repetidos de CPU al 99-100% en múltiples ventanas a lo largo del día; sin caída ni reinicio del servicio |
| platform-service | Sin impacto en esta ventana (CPU estable, máximo ~28%) |

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | `aws ecs describe-services` (historial de eventos) | Confirmar si hubo reinicios de tarea en concentrador-service y platform-service |
| C2 | `aws cloudwatch get-metric-statistics` (`CPUUtilization`) | Verificar ventana y magnitud de los picos de CPU, ambos servicios |
| C3 | `aws ecs describe-services` (task definition activo) | Confirmar spec de capacidad vigente antes de la mitigación |
| C4 | `aws ecs describe-task-definition` | Confirmar cpu/memory del task definition `:321` |
| C5 | `aws elbv2 describe-target-groups` | Confirmar configuración de health check del target group |
| C6-C8 | Exportación Graylog (`service:concentrador-service AND category:PERF`) + análisis de volumen por minuto, composición por URL y distribución de `duration_ms` | Identificar causa raíz en logs PERF de concentrador-service |

Detalle completo de comandos en `scripts.sh`.

## Acciones propuestas

1. **(Dev)** Limitar la concurrencia del fan-out en `enviarEstadoPedidosYa` (y revisar si `enviarEstadoRappi`, `sendStatusUberEats`, `sendStateMercadoPago` comparten el mismo patrón) en lugar de procesar todas las sucursales activas en simultáneo.
2. **(Dev)** Agregar timeout al cliente HTTP compartido de concentrador-service (`utils/httpClient.js`) — mismo defecto señalado en GITIN-1783, todavía sin corregir.
3. (Dev) Evaluar una sincronización incremental (solo sucursales cuyo estado cambió desde la última corrida) en lugar de reprocesar la totalidad de la flota en cada horario configurado.
4. **(SRE, ya aplicada 29/08)** Escalado de capacidad del task definition de concentrador-service (`256/512` → `1024 CPU/2048 MB`, revisión `:322`) como mitigación temporal mientras se implementan los puntos 1-3. No corrige la causa raíz — mismo criterio que en GITIN-1783. Despliegue confirmado en estado estable el mismo día.
5. **(SRE) Completado, 31/08/2026** — Desescalado aplicado: `concentrador-service-production-task:323` (`cpu:256`/`memory:512`, registrada 2026-08-31T08:00:12-03:00), desplegado y confirmado (`desired:1`/`running:1`). Revierte exactamente a la especificación previa a la mitigación. **No confirmado si los puntos 1-3 estaban implementados al momento del desescalado** — ver seguimiento en Hallazgos secundarios.
6. (SRE) Evaluar agregar una política de auto-scaling a concentrador-service, actualmente sin ninguna configurada.
7. **(SRE) Completado, 31/08/2026** — Escalación a Dev enviada (`email_dev.md`) antes del desescalado, señalando el riesgo de revertir la capacidad sin la corrección de código. Respuesta de Dev / confirmación de si los fixes ya están implementados: pendiente.

## Hallazgos secundarios

- La configuración de horarios de sincronización con PedidosYa (`platform.checkIns`) fue migrada de un arreglo fijo en código a un valor editable en base de datos en julio de 2026, sin cambios en la lógica de fan-out. El defecto de concurrencia sin límite es anterior a ese cambio y no corresponde a una regresión reciente.
- **Seguimiento abierto (31/08/2026) — este ticket se cierra con este riesgo explícitamente sin resolver, por decisión:** la capacidad fue desescalada según lo programado (acción 5) sin confirmación de que los puntos 1-3 (límite de concurrencia, timeout de `httpClient`) ya estén implementados. Si no lo están, concentrador-service queda expuesto otra vez al mismo patrón de fan-out que causó los picos de CPU de este ticket, sin ninguna mitigación vigente, hasta el próximo horario de sincronización con PedidosYa. El cierre de GITIN-1964 no debe interpretarse como que este riesgo quedó atendido — seguimiento en `investigation.md`, que permanece abierto en este punto.
