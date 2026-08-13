# 20260805_concentrador-platforms-high-cpu-healthcheck

**Tags:** SmartPedidos, Concentrador, Platform, AWS, Graylog, Performance, PROD

## Resumen

El 05/08/2026, concentrador-service y platform-service (SmartPedidos, cluster ECS `smartfran-pedidos-production`) presentaron degradación de CPU sostenida entre aproximadamente las 16:30 y las 18:15 (hora local, UTC-3). platform-service sufrió un ciclo repetido de reinicio de tareas por falla de health check — al menos 20 eventos de detención de tarea, cada 2-3 minutos, entre las 17:15 y las 18:01 — que dejó de repetirse tras un aumento de capacidad aplicado durante el incidente. concentrador-service no fue reiniciado en ningún momento, pero mostró picos sostenidos de CPU vinculados a llamadas salientes colgadas hacia la API de PediGrido (`app.pedigrido.com`), que sufrió una degradación/caída parcial durante la misma ventana.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-1783](https://smartit-ar.atlassian.net/browse/GITIN-1783) |
| ID alerta | No se dispuso de ID de alerta de monitoreo — detección por reporte directo |
| Sistema | AWS ECS Fargate `smartfran-pedidos-production` — concentrador-service y platform-service, ALB `pedidos-concentrador-alb` |
| Severidad | Alta |
| Detectado | 05/08/2026 ~16:30 (hora local, reportado) |
| Resuelto | 05/08/2026 ~18:15 (hora local, mitigado mediante escalado de cpu/memory de las task definitions — mitigación revertida el 06/08, ver Acciones propuestas) |
| Responsable | SRE |

## Causa raíz

La causa raíz confirmada es una degradación/caída parcial de la API de PediGrido (`app.pedigrido.com`) entre aproximadamente las 16:28 y las 18:02 (hora local), evidenciada en los logs PERF propios de concentrador-service: llamadas a `v1/locals/status` y `v1/Grido/ConfirmarPedido` con duraciones de entre 125 y 218 segundos, y 354 de aproximadamente 1600 llamadas devolviendo errores de servidor (524 Cloudflare gateway timeout, 502, 503, 500). El cliente HTTP compartido de concentrador-service (`utils/httpClient.js`, `axios.create()`) no define timeout, y el cron de sincronización con PediGrido (`checkOfflinePOSpedigrido`, cada 1 minuto) no tiene límite de concurrencia ni protección de superposición entre ejecuciones — por lo que cada ejecución durante la caída de PediGrido agregó un nuevo lote de llamadas colgadas sobre las ya pendientes, generando presión sostenida de CPU/event loop en concentrador-service durante cerca de 90 minutos.

**Validado directamente contra el código fuente (06/08/2026):** `api/src/utils/httpClient.js:5` — `axios.create()` se llama sin ningún objeto de configuración, no hay clave `timeout` en ningún lugar del archivo. `api/src/controllers/branch.js:1110-1130` — el llamado a `v1/locals/status` (`httpClient.put(urlAvailability, body, headersConfig)`) pasa `headersConfig` con solo `headers`, sin `timeout` a nivel de request tampoco. `api/src/controllers/branch.js:1744` y `:1767` — `schedulePediGridoOffline = '*/1 * * * *'` conectado a `checkOfflinePOSpedigrido()`, sin ninguna guarda de superposición visible en la función. Los tres elementos de la causa raíz están confirmados por lectura directa del código, no solo inferidos de los logs. PediGrido reportó por su parte no poder identificar qué proceso de su lado consumía su propio backend, lo cual es consistente con la evidencia relevada del lado de SmartPedidos, aunque no la reemplaza.

En paralelo, platform-service sufrió un ciclo de reinicio de tareas por health check — mecanismo confirmado vía configuración del Target Group del ALB: el endpoint `GET /metrics/health-check` se autorreporta no saludable cuando `os.loadavg()[0] > 0.7`, y el Target Group asociado tiene un umbral ajustado (`Interval: 30s`, `UnhealthyThreshold: 2`) que permite matar una tarea con apenas 30-60 segundos de falla sostenida.

**Verificado en código y contrastado con datos reales (06/08/2026):** a diferencia de concentrador-service, platform-service tiene un timeout global configurado (`api/src/index.js:21`, `axios.defaults.timeout = 20000`, 20 segundos) que en teoría cubre las llamadas a PediGrido (`rapiboy.js:388/440/499`, no `thirdParty.js` como se había asumido inicialmente). Sin embargo, un segundo export de Graylog con logs propios de platform-service (51.158 filas, ventana 18:00 UTC 05/08 a 02:00 UTC 06/08) muestra que ese timeout **no se cumple de forma estricta en producción**: 24 de 8.420 llamadas a PediGrido superaron los 20.000ms, con un máximo real de 34.353ms — todas con `status: 200` (respuesta exitosa, no abortada). Aun así, la magnitud sigue siendo muy inferior a la de concentrador-service (máximo real 34,3s vs 125-218s) y ninguna llamada quedó colgada de forma indefinida.

Comparando la latencia de esas llamadas dentro de la ventana confirmada de degradación de PediGrido (19:28-21:02 UTC) contra el resto de la exportación: el promedio prácticamente no cambia (3.152ms vs 3.027ms), pero la proporción de llamadas severas (>20.000ms) es **~11 veces mayor dentro de la ventana** (12 de 680, 1,8%) que fuera de ella (12 de 7.740, 0,16%). Esto es evidencia propia de platform-service —no solo coincidencia temporal— de que la degradación de PediGrido también llegó a sus llamadas, aunque a una escala mucho menor que en concentrador-service.

Como mitigación durante el incidente se escaló cpu/memory de ambas task definitions (concentrador-service `256`→`1024` CPU / `512`→`2048` memoria; platform-service `512`→`2048` CPU / `2048`→`5120` memoria), lo cual coincide con el fin de los reinicios y la baja sostenida de CPU observada después. Como acción de seguimiento posterior, ya aplicada, se aumentó el `MinCapacity` del Application Auto Scaling de platform-service de `5` a `10`.

**Actualización (06/08/2026):** el escalado de cpu/memory de ambas task definitions fue revertido a sus revisiones previas al incidente (concentrador-service `:318`→`:317`; platform-service `:253`→`:252`), y el `MinCapacity` del Application Auto Scaling de platform-service también fue revertido de `10` a `5`. El criterio para revertir es que ese escalado nunca fue la corrección real — coincidió con la recuperación de PediGrido, no con una corrección del defecto de fondo. La causa raíz que se sostiene como cierta a nivel interno sigue siendo la ausencia de timeout en el cliente HTTP compartido de concentrador-service, no el mecanismo de health check en sí (ese mecanismo es válido como explicación simplificada del *ciclo de reinicios* de platform-service, pero no como causa raíz de la presión de CPU de concentrador-service). Con esta reversión completa, **ambos servicios quedan exactamente en su estado previo al incidente, sin ningún colchón de capacidad**. Con las correcciones de código (timeout, guarda de superposición del cron) todavía sin implementar, un nuevo evento de degradación de PediGrido reproduciría el mismo patrón de falla del 05/08, sin ninguna mitigación vigente.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | platform-service sufrió al menos 20 reinicios de tarea por health check, cada 2-3 minutos, entre las 17:15 y las 18:01 del 05/08 — confirmado vía historial completo de eventos ECS, no inferido | Alto |
| H2 | Llamadas de concentrador-service a la API de PediGrido (`v1/locals/status`, `v1/Grido/ConfirmarPedido`) tomaron entre 125 y 218 segundos, con 354 de ~1600 llamadas devolviendo 524/502/503/500 | Alto |
| H3 | El cliente HTTP compartido de concentrador-service no define timeout, y el cron de sincronización con PediGrido (cada 1 minuto, sin límite de concurrencia ni guarda de superposición) permitió que las llamadas colgadas se acumularan sin control durante la degradación del proveedor | Alto |
| H4 | concentrador-service corre con `desiredCount: 1` (sin redundancia) y no fue reiniciado en ningún momento durante el incidente — su health check (`/`, matcher 404, timeout 120s, intervalo 300s) es genérico y no depende de CPU/carga | Medio |
| H5 | Los health check logs del ALB (`health_check_logs.s3.enabled`) están deshabilitados — no hay forma de confirmar directamente el historial de aprobación/falla de los health checks, ni de forma retroactiva ni a futuro sin habilitarlo | Medio |
| H6 | platform-service tiene timeout global de 20s configurado (`axios.defaults.timeout`, `index.js:21`), pero no se cumple de forma estricta en producción (24 de 8.420 llamadas a PediGrido lo superaron, máximo real 34,3s, todas exitosas) — aun así, muy por debajo de los 125-218s de concentrador-service. La tasa de llamadas severas (>20s) fue ~11x mayor dentro de la ventana de incidente que fuera de ella — evidencia propia de platform-service de que PediGrido también afectó sus llamadas, a escala menor | Bajo |
| H7 | El branch de memoria del health check de platforms-service (`usedMem > maxMemUsage`) nunca puede activarse — `usedMem` es un ratio 0-1 y el umbral configurado es `2` | Bajo |

## Recursos afectados

| Componente | Impacto |
|---|---|
| platform-service | Al menos 20 reinicios de tarea por health check entre 17:15-18:01; capacidad reducida durante el ciclo |
| concentrador-service | Degradación por llamadas HTTP colgadas hacia PediGrido; sin reinicios de tarea, pero con presión sostenida de CPU |
| PediGrido (proveedor externo) | Origen de la degradación — reportó no poder identificar el proceso consumidor en su propio backend |
| SQS MainDeadLetter | Backlog de mensajes visibles aproximadamente duplicado (55→109) en la misma ventana (hallazgo secundario, correlación no confirmada de forma causal) |

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | `aws ecs describe-services` (historial completo de eventos) | Confirmar patrón y ventana real de reinicios de tarea por servicio |
| C2 | `aws ecs describe-tasks` (`stoppedReason`) | Confirmar causa de detención de tareas específicas |
| C3 | `aws cloudwatch get-metric-statistics` (`CPUUtilization`) | Verificar ventana y magnitud de la saturación de CPU |
| C4 | `aws elbv2 describe-target-groups` / `describe-target-health` | Confirmar configuración real de health check por servicio |
| C5 | `aws ecs describe-task-definition` (diff de revisiones) | Confirmar que el cambio de task definition fue un escalado de cpu/memory, no un cambio de código |
| C6 | `aws elbv2 describe-load-balancer-attributes` / `aws s3api get-bucket-notification-configuration` | Verificar si los health check logs y access logs del ALB llegan a Graylog |
| C7 | Exportación Graylog (`All-Messages-search-result.csv`) + paneles de Grafana/CloudWatch (SQS, duración por `msg_rest_url`) | Identificar causa raíz en logs PERF de concentrador-service |
| C8 | `aws ecs describe-services` (revisión activa + deployments) | Confirmar estado real de la reversión de task definitions (06/08) |
| C9 | `aws application-autoscaling describe-scalable-targets` | Confirmar si el `MinCapacity` de platform-service fue revertido junto con la task definition |

Detalle completo de comandos y adjuntos en `scripts.sh` y en la carpeta del evento.

## Acciones propuestas

1. **(Dev, urgente)** Agregar timeout al cliente HTTP compartido de concentrador-service (`utils/httpClient.js`) y a las llamadas hacia PediGrido en `branch.js`. Prioridad elevada tras la reversión del 06/08: ya no queda ningún colchón de capacidad cubriendo este defecto.
2. **(Dev, urgente)** Agregar protección de solapamiento (lock / skip-if-running) al cron `checkOfflinePOSpedigrido` y limitar la concurrencia del fan-out por sucursal. Misma razón que el punto anterior.
3. (Dev) Corregir el branch de memoria muerto en `GET /metrics/health-check` de platforms-service (`usedMem > maxMemUsage` nunca se cumple) y devolver 503 en lugar de 400 para señalizar sobrecarga.
4. **(SRE, ya aplicada 06/08)** Reemplazado el mecanismo de health check autorreportado de platform-service — Target Group reconfigurado a `Path: /`, `Matcher: 404` (igual que concentrador-service), en vez de `/api/metrics/health-check` con `Matcher: 200` basado en `os.loadavg() > 0.7`. Elimina la dependencia del health check en la carga del proceso, no solo le agrega histéresis. Timing del Target Group (`Interval: 30s`, `UnhealthyThreshold: 2`) quedó sin cambios — más agresivo que el de concentrador-service, a confirmar si es intencional. Validado contra el código fuente que un `GET /` sin autenticar devuelve `404` en operación normal (exento de JWT explícitamente, sin ruta que lo capture, cae al 404 implícito de Express).
5. (SRE) Evaluar aumentar la redundancia de concentrador-service (actualmente `desiredCount: 1`, sin tarea de respaldo) — esto quedó sin resolver tanto antes como después de la reversión del 06/08.
6. (SRE) Evaluar habilitar `health_check_logs.s3` en el ALB `pedidos-concentrador-alb` para tener visibilidad directa de aprobación/falla de health checks a futuro.
7. (SRE) Escalar con PediGrido (proveedor externo) la degradación de su API durante la ventana del incidente, referenciando los tiempos de respuesta y códigos de error relevados.
8. **(SRE, ya aplicada 06/08)** Revertir el escalado de cpu/memory de ambas task definitions a sus revisiones previas al incidente, y revertir el `MinCapacity` de platform-service de `10` a `5` — ninguno de los dos corregía la causa raíz. Con esto, ambos servicios quedan sin ningún colchón de capacidad hasta que se resuelvan los puntos 1 y 2.

## Hallazgos secundarios

- Backlog de `MainDeadLetter` (SQS) aproximadamente duplicado (55→109 mensajes visibles) en la misma ventana del incidente — correlación observada, no confirmada como relacionada de forma causal directa.
