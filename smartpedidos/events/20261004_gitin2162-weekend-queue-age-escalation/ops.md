# [SP] Comportamiento serrucho en PRD_BranchMessages.fifo y escalamientos de platform-service

**Tags:** `SmartPedidos`, `Platform`

## Resumen

Entre el jueves 01-10 y el lunes 05-10 la antigüedad del mensaje más viejo (`ApproximateAgeOfOldestMessage`) de la cola `PRD_BranchMessages.fifo` mostró un comportamiento en serrucho: valores de 0 a 4 segundos la mayor parte del tiempo y 9 episodios cortos (de 5 a 10 minutos cada uno) con picos de 227 a 324 segundos. En cada episodio los borrados de la cola caen casi a cero y, al terminar, un pico de borrados vacía lo acumulado. `platform-service` escaló después de cada episodio (hasta 14 tareas) y volvió a su capacidad base en pasos de 3 minutos, lo que dibuja el mismo serrucho en la cantidad de tareas. El domingo 04-10 se fijó la capacidad mínima en 10 tareas; con ese mínimo ocurrieron dos episodios más, y el servicio escaló dos veces más durante la noche. La causa raíz no está determinada y el servicio queda en monitoreo.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2162](https://smartit-ar.atlassian.net/browse/GITIN-2162) |
| ID alerta | Observado en Grafana (`ApproximateAgeOfOldestMessage`). No se disparó ninguna alerta de Zabbix en los 9 episodios (eventos revisados hasta el lun 05-10 09:14); según lo informado, no hay alarmas de CloudWatch para esta métrica |
| Sistema | SmartPedidos — platform-service (ECS Fargate, cluster `smartfran-pedidos-production`), cola SQS `PRD_BranchMessages.fifo` |
| Severidad | No definida |
| Detectado | Grafana. Escalamientos informados: sábado 03-10 (13h, 21h, 22h) y domingo 04-10 (11h) |
| Resuelto | No. En monitoreo |
| Responsable | SRE |

## Cronología de escalamientos

Horarios en ART (UTC-3). "Pico" es la antigüedad máxima del mensaje más viejo en el episodio.

| # | Episodio | Pico | Escalado de platform-service |
|---|---|---|---|
| 1 | Jue 01-10 22:54 | 301 s | 23:01 a 14 tareas (política de CPU); vuelve a 5 a las 23:39 |
| 2 | Vie 02-10 14:09 | 253 s | 14:20 a 14 tareas (política de CPU); vuelve a 5 a las 14:50 |
| 3 | Vie 02-10 20:14 | 227 s | 20:21 a 14 tareas (política de CPU); vuelve a 5 a las 20:51 |
| 4 | Sáb 03-10 13:09 | 239 s | 13:14 a 14 tareas (política de CPU); vuelve a 5 a las 13:48 |
| 5 | Sáb 03-10 21:39 | 322 s | 21:49 a 14 tareas (política de CPU); vuelve a 5 a las 22:22 |
| 6 | Sáb 03-10 22:44 | 305 s | 22:49 a 14 tareas (política de CPU); vuelve a 5 a las 23:25 |
| 7 | Dom 04-10 11:19 | 324 s | ~11:25 a 10 tareas (política de CPU); vuelve a 5 a las 11:45 |
| — | Dom 04-10 15:24 | — | Se fija la capacidad mínima del servicio en 10 tareas |
| 8 | Dom 04-10 19:05 | 287 s | 19:15 a 14 tareas (política por requests); vuelve a 10 a las 19:28 |
| 9 | Dom 04-10 20:15 | 238 s | 20:23 a 14 tareas (política por requests); vuelve a 10 a las 20:34 |
| — | Lun 05-10 08:42 | — | ECS detiene 5 tareas; el servicio queda en 5 deseadas / 5 en ejecución |

El escalado ocurrió entre 5 y 12 minutos después del inicio de cada episodio. Después del episodio 9 no hubo valores superiores a 60 segundos hasta el lunes 05-10 08:55 (fin de los datos revisados).

## Causa raíz

No determinada. El patrón observado (todos los consumidores dejan de borrar mensajes a la vez durante 5 a 10 minutos, sin relación con el volumen de mensajes ni con la cantidad de tareas, mientras platform-service sigue respondiendo HTTP con normalidad) apunta a un elemento compartido por la ruta de consumo de la cola, no a falta de capacidad. Las hipótesis no han sido probadas (llamadas a MongoDB o a SQS sin timeout dentro del consumidor, o un bloqueo por grupo de mensajes FIFO).

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Solo 12 de 864 intervalos de 5 minutos (72 h) superan los 60 s de antigüedad; no hubo acumulación sostenida de mensajes. Los episodios siguen una curva de rampa y caída brusca | Medio |
| H2 | En cada episodio los borrados caen casi a cero y luego hay un pico de recuperación (ej. dom 04-10 11:19: 210 mensajes enviados y 0 borrados; sáb 03-10 22:44: 3593 enviados y 120 borrados, luego 6965 borrados) | Medio |
| H3 | Los episodios no dependen del volumen: ocurren con ~3 mil mensajes por hora y con alto volumen. El intervalo más cargado de la ventana (~41 mil mensajes por hora) tuvo antigüedad máxima de 9 s | Medio |
| H4 | Los episodios 8 y 9 ocurrieron con capacidad mínima en 10 tareas; más tareas no los evitó | Alto |
| H5 | platform-service respondió HTTP con normalidad en los 9 episodios (métricas del ALB hasta el lun 05-10 09:14): tiempo medio de respuesta de 3 a 8 ms, tráfico estable, sin errores 5XX de destino y sin hosts no saludables en el target group | Bajo |
| H6 | Ningún mensaje llegó a `MainDeadLetter.fifo` en las 72 h revisadas | Bajo |
| H7 | La cola tiene visibilidad de 30 s, redrive a `MainDeadLetter.fifo` con `maxReceiveCount` 2 y es FIFO. El consumidor procesa lotes de 10 y no tiene timeout propio sobre el procesamiento; las llamadas HTTP a las plataformas tienen timeout por defecto de 10 s (axios) | Medio |
| H8 | La CPU máxima del servicio llega a 44–100 % en varios episodios mientras el promedio se mantiene entre 5 y 15 % | Medio |
| H9 | Ninguna alerta de Zabbix se disparó en los 9 episodios (eventos revisados hasta el lun 05-10 09:14). Las únicas alertas relacionadas con AWS en el período son de ALB 4XX/5XX en el host `Zabbix server`, sin relación temporal con los episodios; no se encontraron en los eventos alertas de ECS ni de SQS de producción | Medio |
| H10 | Base de datos sin hallazgos, según lo informado por el equipo (sin métricas de base de datos adjuntas en este ticket) | Bajo |
| H11 | El mismo patrón en la misma cola se observó el 25-09 con GITIN-2110, antes de la definición de tarea `platform-service-production-task:268` (registrada el 28-09) | Medio |

## Recursos afectados

| Componente | Observación |
|---|---|
| platform-service | Consumidor de `PRD_BranchMessages.fifo`; escaló entre 5 y 14 tareas durante los episodios; hoy en 5 tareas (0.5 vCPU / 1 GB por tarea) |
| `PRD_BranchMessages.fifo` | Cola donde se observa el serrucho de antigüedad |
| concentrador-service | Sin cambios observados (1 tarea) |

## Comandos ejecutados

Todos son de solo lectura; las salidas están en `data/` del evento.

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | `scripts.sh` — métricas SQS de `PRD_BranchMessages.fifo` (72 h) | Antigüedad, profundidad, enviados y borrados |
| C2 | `scripts.sh` — `describe-services` (ECS) | Estado y eventos de los servicios |
| C3 | `scripts.sh` — `describe-scaling-activities` | Historial de escalado automático |
| C4 | `scripts.sh` — CPU y memoria ECS (72 h) | Uso de recursos de ambos servicios |
| C5 | `scripts.sh` — `get-queue-attributes` | Configuración de la cola |
| C6 | `scripts.sh` — métricas de `MainDeadLetter.fifo` y mensajes en vuelo | Descartar mensajes envenenados |
| C7 | `scripts.sh` — target group, definición de tarea `:268` y métricas del ALB | Verificar el lado HTTP del servicio |
| C8 | `scripts.sh` — eventos de triggers de Zabbix desde el 01-10 | Verificar alertas durante los episodios |
| C9 | `scripts.sh` — segunda extracción dom 04-10 15:00 a lun 05-10 (cola, escalado, CPU/memoria, eventos de Zabbix y métricas del ALB) | Episodios 8 y 9 y escalados nocturnos |

## Acciones propuestas

1. (SRE) Revisar en Graylog los logs de platform-service en las ventanas de los episodios (por ejemplo dom 04-10 11:15–11:30 ART): errores del consumidor o silencio de logs.
2. (SRE) Confirmar la capacidad mínima configurada hoy para platform-service (el servicio está en 5 tareas desde el lunes 05-10 08:42).
3. (SRE) Volver a extraer las métricas de la cola y del escalado dentro de 24 a 48 horas para verificar si el patrón se repite.
4. (SRE) Evaluar una alerta sobre `ApproximateAgeOfOldestMessage` de `PRD_BranchMessages.fifo` (valor habitual de 0 a 4 s frente a 181–324 s en los episodios), dado que ninguna alerta de Zabbix se disparó.
5. (Dev) Evaluar timeouts e instrumentación del consumidor para las llamadas a MongoDB y SQS dentro del procesamiento de cada lote.
