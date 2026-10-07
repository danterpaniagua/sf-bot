# Eventos — 20260829_concentrador-cpu-spikes

## 2026-08-29 18:16 — Apertura de investigación

He iniciado la investigación para GITIN-1964 (varios picos de CPU en concentrador-service, detectados vía Grafana desde las 10:00 -03:00). He identificado el precedente GITIN-1783 (05-08-2026), cuya causa raíz fue una degradación de la API de PediGrido combinada con la falta de timeout en `httpClient.js` y la ausencia de guard de solapamiento en el cron `checkOfflinePOSpedigrido`. He verificado contra el código actual (`develop@77c1061f`) que ninguno de los dos fixes de Dev pendientes de esa investigación fue implementado.

## 2026-08-29 18:23 — Diagnóstico AWS confirmado

He revisado el historial de eventos de ECS y las métricas de CloudWatch para concentrador-service y platform-service en la ventana 2026-08-29 10:00-18:20 -03:00. He confirmado picos reales de CPU en concentrador-service (Maximum 99-100% en múltiples buckets entre 10:00 y 13:15, más picos aislados a las 17:00 y 18:15), sin eventos de kill de ECS, consistente con el health check laxo del target group (Timeout 120s / Interval 300s / path `/`). He descartado a platform-service como afectado en esta ventana (CPU plano, máximo ~28%). He confirmado que el task definition activo (`:321`) seguía en la especificación pre-incidente (256 CPU / 512 MB), sin cambios de capacidad desde el revert de GITIN-1783.

## 2026-08-29 18:35 — Mitigación aplicada

Se aplicó la misma mitigación que en GITIN-1783: aumento de capacidad del task definition de concentrador-service (256/512 → 1024 CPU / 2048 MB), registrado manualmente (no mediante el comando scripteado ofrecido) como revisión `:322`. Se actualizó el servicio a esa revisión; el deployment está en curso, pendiente de confirmar estado estable y caída de los picos de CPU.

## 2026-08-29 18:40 — Email a PM redactado

He redactado un email a PM (`email_pm.md`) informando el evento, la mitigación preventiva aplicada y que la causa todavía está en investigación, con hedge explícito sobre el antecedente GITIN-1783 al no estar confirmado que sea la misma causa.

## 2026-08-29 19:15 — Causa raíz confirmada vía Graylog

He descartado la hipótesis de recurrencia de GITIN-1783 (degradación sostenida de PediGrido) y la hipótesis inicial de clustering de horarios de apertura/cierre de sucursales (`cronHorariosPediGrido`) al analizar una exportación de Graylog (55.860 filas, PERF de concentrador-service, ventana 09:00-20:10 -03:00). He confirmado que las ráfagas de volumen de logs coinciden, con 1 minuto de desfase, con cada pico de CPU de CloudWatch, y que están dominadas por llamadas hacia la API de PedidosYa (no PediGrido) con latencias de hasta 46 segundos (mediana 36,5s), todas con respuesta HTTP 200. He identificado en el código (`branch.js`) que el mecanismo `sincroCheckIns`/`enviarEstadoPedidosYa` procesa la totalidad de sucursales activas de PedidosYa sin límite de concurrencia en cada horario configurado, a través del mismo `httpClient` sin timeout señalado en GITIN-1783.

## 2026-08-29 19:20 — Trazado de historial de commits

Con el repo local actualizado (`develop@d5e57110`), he verificado que no hubo cambios en el código implicado desde el chequeo previo (`77c1061f`), solo commits no relacionados de manejo de errores de Rappi. He trazado el origen del mecanismo de `checkIns`: la forma de configuración dinámica se introdujo en el commit `59faec4e` (07/07/2026), migrando un arreglo fijo de horarios preexistente a un valor editable en base de datos, sin tocar la lógica de fan-out. La función `enviarEstadoPedidosYa` con su fan-out sin límite de concurrencia es anterior, del commit `2e1b7858` (23/05/2025) — no es una regresión reciente.

## 2026-08-29 19:30 — Ticket y comandos documentados

He escrito `ops.md` (resumen, causa raíz, hallazgos, acciones propuestas) y `scripts.sh` (comandos AWS ejecutados) para GITIN-1964, siguiendo la estructura de incidente de `sp-sre-output`.

## 2026-08-29 20:25 — Despliegue confirmado, verificación post-mitigación inconclusa

He confirmado, vía consola de AWS, que el despliegue de la revisión `:322` llegó a estado estable (completado 21:37:43 UTC). Al revisar CPUUtilization post-despliegue (18:37-20:22 hs) no encontré picos, pero esa ventana no incluye ningún horario programado de sincronización con PedidosYa — el próximo es a las 23:01 hs, todavía sin verificar. No doy la mitigación por confirmada hasta revisar ese horario.

## 2026-08-29 20:35 — Evidencia consolidada en la carpeta del evento

He copiado la exportación de Graylog (`7_graylog_perf_export.csv`, 55.860 filas) a la carpeta del evento — era la única evidencia relevante que todavía estaba solo en una descarga local. He actualizado las referencias en `investigation.md` y `scripts.sh` al nuevo nombre de archivo.

## 2026-08-29 20:40 — Ticket cerrado

He cerrado GITIN-1964 con la mitigación de capacidad aplicada. El aumento de capacidad es temporal — desescalado programado para el 31/08/2026 (lunes). La corrección de causa raíz en código (límite de concurrencia en `enviarEstadoPedidosYa`, timeout en `httpClient`) queda pendiente como seguimiento de Dev, fuera del alcance de este cierre. He documentado explícitamente en `investigation.md` y `ops.md` el riesgo de desescalar sin esa corrección — mismo patrón señalado como abierto en GITIN-1783. He agregado como acción propuesta escalar a Dev la implementación de la corrección de código con fecha límite antes del desescalado del 31/08.

## 2026-08-29 20:50 — Capacidad confirmada al cierre

He confirmado la capacidad vigente al momento del cierre: revisión `:322`, 1024 CPU / 2048 MB, `desired:1`/`running:1`. Queda como base documentada para el desescalado del 31/08.

## 2026-08-31 — Escalación a Dev antes del desescalado programado

He redactado un email a Dev (`email_dev.md`) retomando la acción propuesta 7 del ticket: hoy es la fecha programada de desescalado de la capacidad de concentrador-service, y las correcciones de código (límite de concurrencia en `enviarEstadoPedidosYa`, timeout en `httpClient`) siguen sin implementarse. He planteado el riesgo de desescalar sin esa corrección y he pedido coordinar si conviene sostener la capacidad ampliada hasta resolverla, sin fijar ninguna fecha estimada de mi parte.

## 2026-08-31 12:49 — Desescalado de capacidad aplicado

He confirmado, vía consola de AWS (deployment ID `fFhWEhbG-Z2tlOX3AlQmI`), que el despliegue de desescalado de `concentrador-service-production-service` completó exitosamente a las 2026-08-31T12:49:17.344Z: la tarea previa (`bb99d3437faa4d77b1a0ea9e58216f84`) drenó conexiones, se desregistró del target group `concetrador-serprod-tg` y se detuvo, y una nueva tarea inició correctamente. El registro y despliegue de esta revisión se realizaron manualmente, no vía CLI.

He confirmado con `describe-services` y `describe-task-definition` que la revisión activa es `concentrador-service-production-task:323` (`desired:1`/`running:1`), registrada el 2026-08-31T08:00:12-03:00 con `cpu:256`/`memory:512` — coincide exactamente con la especificación previa a la mitigación (`:321`). El desescalado programado en la acción propuesta 5 queda aplicado y confirmado.

## 2026-08-31 — Ticket cerrado con el riesgo explícitamente abierto

He cerrado GITIN-1964 sin confirmación de que los fixes de código de Dev (límite de concurrencia, timeout de `httpClient`) estén implementados. He dejado este punto explícitamente abierto en `investigation.md` — el cierre del ticket no implica que el riesgo esté resuelto. He actualizado `ops.md` e `investigation.md` para que ese seguimiento quede visible para quien retome el evento más adelante.
