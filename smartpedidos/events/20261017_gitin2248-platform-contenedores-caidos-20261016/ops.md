# GITIN-2248 — [SP] Platform: Containers muertos

**Tags:** `SmartPedidos`, `Platform`, `AWS`, `SRE`, `PROD`

## Qué pasó

- Se informó que el 16-10 murieron contenedores de platform-service, el día en que se reportó el despliegue de la corrección de Desarrollo de [GITIN-2222](https://smartit-ar.atlassian.net/browse/GITIN-2222).
- Ese día hubo 60 tramos (76 minutos) con menos tareas en ejecución que las deseadas, a pesar de la corrección; el 13-10, 14-10 y 15-10 habían tenido 49, 50 y 53 tramos (66, 68 y 68 minutos).

## Resumen

El 16-10 las tareas de platform-service siguieron cayendo después del despliegue de la corrección de Desarrollo de GITIN-2222. La medición diaria de tareas en ejecución contra tareas deseadas muestra que las caídas son nuevas: de 0 a 3 minutos por día hasta el 12-10, 66 minutos el 13-10 (primera revisión registrada después de la integración de los manejadores de salida) y 68, 68, 76, 79 y 157 minutos en los días siguientes (el 18-10 con 10 tareas deseadas). El análisis del código y de los registros es coherente con que cada rechazo no manejado terminaba la tarea (manejador de salida) y con dos fallas del propio código que disparaban esos rechazos: el uso de una clase como función (corregido el 16-10 y desaparecido de los registros desde entonces) y una falla del registro de errores ante estructuras circulares. El 17-10 subí a 10 la capacidad mínima del Auto Scaling para amortiguar cada caída. Desarrollo dejó de terminar el proceso el 19-10 y corrigió el registro de errores el 20-10 (integrado en `develop`). Después de esos despliegues, la cantidad de tareas en ejecución se normalizó; es una observación posterior al despliegue y no se volvió a medir con CloudWatch para este ticket. La causa no se probó de punta a punta (no se leyó el contenido de las imágenes) y quedan acciones propuestas sobre alertas y capacidad.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2248](https://smartit-ar.atlassian.net/browse/GITIN-2248) |
| ID alerta | Zabbix: "Running tasks below desired" (ECS) y "Graylog: Platform FATAL detected" |
| Sistema | platform-service (ECS Fargate, SmartPedidos, PROD) |
| Severidad | NA (sin efecto medido sobre el flujo de pedidos) |
| Detectado | 2026-10-16 (reportado); las caídas se miden desde 2026-10-13 |
| Resuelto | Sí, según la observación posterior a los despliegues del 19-10 y 20-10 (tareas en ejecución normalizadas); no re-medido con CloudWatch |
| Responsable | SRE (medición y capacidad); Desarrollo (correcciones de código) |

## Causa raíz

NA

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Las caídas son nuevas: de 0 a 3 minutos por día con menos tareas en ejecución que las deseadas hasta el 12-10, y 66 (49 tramos) el 13-10, 68, 68, 76, 79 y 157 minutos los días siguientes hasta el 18-10. El 16-10 fue el día con más tramos (60). Las caídas se concentran de 16 a 01 h y casi no hay de 02 a 15 h. Concentrador-service casi no tuvo (0 tramos el 13, 15 y 16-10 y 1 minuto el 14-10). | Alto |
| H2 | Desde el cambio del 08-10 (integrado a `develop` el 09-10), cada rechazo no manejado o excepción no capturada registra un FATAL y termina el proceso; antes no lo terminaba. La primera revisión de la definición de tarea registrada después de esa integración es la 271 (2026-10-13 09:40), la fecha en que las caídas saltan de 2 a 66 minutos; es coherente con una relación, pero la revisión 271 incluye también otros cambios y no se leyó el contenido de las imágenes. | Alto |
| H3 | La corrección de Desarrollo del 16-10 (revisión 273, iniciada 09:36 -03:00, diez minutos después de su integración) eliminó la falla de la clase usada como función (40 de los 63 eventos FATAL de GITIN-2222): la última línea con esa firma es de las 01:27 del 16-10. Aun así las caídas no bajaron ese día (60 tramos, 76 minutos), porque quedaban la falla del registro de errores ante estructuras circulares y el manejador que termina el proceso. Las líneas de la falla circular pasaron de 49 a 51 por día a 72 el 16-10. | Alto |
| H4 | Las caídas se medían con 5 tareas deseadas y el 18-10 con 10; un minuto con 9 de 10 tareas también cuenta, por lo que los minutos del 17 y 18-10 no son comparables con los de los días con 5 tareas. | Informativo |
| H5 | El 17-10 a las 11:28 -03:00 la capacidad mínima del Auto Scaling de platform-service pasó de 5 a 10 y el servicio fue a 10 tareas deseadas y 10 en ejecución (verificado). Con 10 tareas una caída quita el 10 % de la capacidad y no el 20 %; no evita las caídas y duplica las tareas del servicio. No se comprobó si la definición de infraestructura como código del servicio tiene el mismo mínimo, por lo que una aplicación posterior podría revertirlo. | Medio |
| H6 | Eficacia de las alertas el 16-10: la alerta de ECS no tocó ningún problema abierto en 18 de las 60 caídas (las de una sola tarea por un minuto, que se diluyen en los promedios de 10 minutos) y abre con 3 a 5 minutos de retraso; la alerta de FATAL abrió dentro del minuto de la caída en 48 de las 60 y tuvo 2 problemas sin caída detrás. Zabbix generó 307 notificaciones para los 115 eventos de ambas alertas: ningún evento quedó sin notificación y 1 envío a Telegram falló tras 3 reintentos. | Medio |
| H7 | Por los conteos, cada evento FATAL parece notificarse dos veces en Google Chat (por dos acciones de Zabbix) y una en Telegram; no se verificó evento por evento ni en el espacio de Chat. | Bajo |
| H8 | Las alertas de código distinto de 200 de los healthchecks, de falta de datos y de FATAL de concentrador-service no se dispararon en ningún evento real; solo se probaron con cambios controlados. La de concentrador no puede dispararse mientras concentrador-service no registre líneas FATAL (GITIN-2240). | Medio |
| H9 | Antes de la corrección, la observación de que "no había caídas" a mediodía del 16-10 caía dentro del tramo tranquilo del día (sin caídas de 01:37 a 13:47): una observación de la mañana no muestra el efecto de una corrección. | Informativo |

## Acciones Tomadas

| # | Hora (UTC) | Acción |
|---|---|---|
| 1 | 2026-10-17 a 2026-10-19 | Mediciones de solo lectura: tareas en ejecución contra deseadas en CloudWatch por día y por hora desde el 05-10, eventos de las dos alertas en Zabbix el 16-10, líneas FATAL en Graylog por firma y día, entrega de las notificaciones de Zabbix, estado del servicio, de la definición de tarea y del Auto Scaling, y fechas de las revisiones de la definición de tarea. |
| 2 | 2026-10-17 14:28 | Subí a 10 la capacidad mínima del Auto Scaling de platform-service (antes 5); el servicio pasó a 10 tareas deseadas y en ejecución. Verificado en la actividad de escalado y en el servicio. |
| 3 | 2026-10-19 | Lectura del código de platform en `develop`: origen del manejador que termina el proceso, corrección del 19-10 que lo comenta y análisis de lo que deja sin cambio. Sin modificar nada. |
| 4 | 2026-10-20 | Lectura de `develop`: la corrección del registro de errores del 20-10 está integrada; el manejador sigue sin terminar el proceso. |

## Recursos afectados

| Componente | Estado |
|---|---|
| platform-service (ECS) | Caídas desde el 13-10; capacidad mínima 10 desde el 17-10; revisiones 273 (corrección del 16-10), 274 y 275 (19-10) registradas; contenido de las imágenes sin leer |
| concentrador-service (ECS) | Sin caídas relevantes en las fechas medidas |
| Alertas Zabbix de ECS y de FATAL de Platform | Funcionan con los límites de H6; el aviso de FATAL parece duplicarse en Chat (H7) |
| Auto Scaling de platform-service | Mínimo 10, máximo 25, dos políticas de seguimiento de destino |

## Acciones propuestas

| # | Responsable | Acción | Estado |
|---|---|---|---|
| 1 | SRE | Volver a medir con CloudWatch las caídas de la tarde y la noche del 19-10 y del 20-10 para confirmar la normalización observada, con el corte en el horario de cada despliegue. | Pendiente |
| 2 | Dev | Definir qué debe hacer Platform ante un rechazo no manejado o una excepción no capturada (seguir corriendo o terminar tras registrar el FATAL) y confirmar que las imágenes desplegadas contienen las correcciones del 19-10 y 20-10. | Por decidir |
| 3 | SRE | Decidir si la capacidad mínima de 10 se mantiene o vuelve a 5 una vez confirmada la normalización, y comprobar que la infraestructura como código no la revierta. | Por decidir |
| 4 | SRE | Evaluar una alerta de ECS basada en la señal de un minuto en vez de los promedios de 10 minutos y revisar el margen con 10 tareas. | Por decidir |
| 5 | SRE | Confirmar la doble notificación de FATAL en Chat y, si se confirma, dejar una sola acción. | Pendiente |
| 6 | SRE | Evaluar un contador de envíos fallidos a Telegram o una verificación de reintentos. | Por decidir |
| 7 | SRE | Contar en el buzón los correos de parada del 16-10 (formato nuevo, solo STOPPED) y compararlos con las 60 caídas y los 115 eventos de Zabbix. | Pendiente |
| 8 | Dev | Registrar líneas FATAL en concentrador-service para que su alerta pueda dispararse (GITIN-2240). | Pendiente |
