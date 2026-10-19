# GITIN-2211 — [SP] Spikes en cola: antigüedad del mensaje más viejo en PRD_BranchMessages.fifo (11-10-2026 22:03)

**Etiquetas:** `SmartPedidos`, `AWS`, `Obserbavilidad`, `PROD`

## Resumen

El 11-10-2026 a las 22:03 (hora local, UTC-3) se vio en Grafana un pico en la antigüedad del mensaje más viejo de la cola `PRD_BranchMessages.fifo` (dato informado). Los datos de CloudWatch lo confirman: entre las 21:58 y las 22:02 la cola dejó de entregar y borrar mensajes mientras seguían entrando unos 440 a 570 por minuto; los mensajes visibles subieron de 35 a 1.989 y la antigüedad llegó a 306 s a las 22:03. A las 22:03 el consumo se reanudó y a las 22:04 la antigüedad volvió a 0. La alarma de CloudWatch pasó a ALARM a las 22:02:25 y ejecutó el escalamiento del servicio `platform-service` de 5 a 15 tareas (9 en ejecución a las 22:03, 15 a las 22:04, de nuevo 5 a las 22:39). El mismo patrón ocurrió 13 veces entre el 03-10 y el 13-10 a las 00:30 (2 a 5 minutos cada una, todas con antigüedad superior a 200 s, de 238 a 329 s); 4 de ellas fueron durante el fin de semana largo del 09 al 12-10 y la última, el 13-10 a las 00:30, cayó antes del primer día hábil. En 12 de las 13 paradas los logs de `platforms-service` no muestran una plataforma de delivery lenta: las llamadas a las plataformas del lado del consumo se detienen por completo y sus tiempos de respuesta son normales antes y después. En la parada del 13-10 aparecen, en los 3 minutos previos, tiempos de espera agotados (10 s) con la plataforma `I+D`. La causa de la parada del consumo no se determinó.

## Alcance

Análisis del escalamiento por antigüedad del mensaje más viejo de la cola principal: si se revisó en el momento, si los logs permitieron encontrar la causa, si escaló bien y si hay una plataforma lenta que genere la demora. Nivel de negocio. Fuera de alcance: análisis del código de escalamiento (función Lambda) y del código de Platform y Concentrador.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2211](https://smartit-ar.atlassian.net/browse/GITIN-2211) |
| ID alerta | `sendMailOldestMessage` (CloudWatch), estado ALARM de 22:02:25 a 22:10:25 el 11-10 |
| Sistema | SmartPedidos, cola SQS `PRD_BranchMessages.fifo` (us-east-1), servicio `platform-service` (ECS Fargate, producción) |
| Severidad | Por definir con Operaciones |
| Detectado | 2026-10-11 22:03 (Grafana, informado) |
| Resuelto | Parcial: el consumo se reanudó a las 22:03 y la cola volvió a 0 a las 22:04; la causa de la parada no está determinada y el patrón se repitió 13 veces en 11 días |
| Responsable | SRE (análisis y alertas); Dev (causa de la parada del consumo) |

## Causa raíz

NA

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | ¿Se revisó en el momento? Solo consta, por dato informado, que el pico se vio en Grafana a las 22:03. No hay registro de una acción manual esa noche; sí actuó el sistema por sí solo (alarma y escalamiento, H6). Según lo informado, no se había detectado que el comportamiento fuera recurrente, por lo que no se modificó el tamaño ni la cantidad permanente de tareas de `platform-service`. | Bajo |
| H2 | Qué ocurrió el 11-10 (hora local, datos de 1 minuto): recibidos y borrados en 0 a las 21:58, 21:59, 22:00 y 22:01 (22:02: 20 recibidos, 0 borrados) mientras los enviados seguían en 442–567 por minuto. Mensajes visibles: 35, 617, 1.099, 1.590 y 1.989 (22:02). Antigüedad: 4, 65, 125, 190, 247 (22:02) y 306 s (22:03). A las 22:03: 2.879 recibidos y 2.880 borrados en un minuto; a las 22:04 la antigüedad volvió a 0. Antes de la parada la cola estaba normal (380–560 enviados por minuto, recibidos y borrados casi iguales, antigüedad de 0 a 4 s). Las colas por sucursal no mostraron picos (hasta 15 mensajes por 5 minutos) y la cola de mensajes fallidos `MainDeadLetter.fifo` mantiene 30 a 77 mensajes todos los días sin recibir mensajes nuevos. | Medio |
| H3 | No es un hecho aislado: entre el 03-10 y el 13-10 hubo 13 paradas del consumo (2 a 5 minutos cada una) con antigüedad máxima de 238 a 329 s; las 13 superaron los 200 s, 11 llegaron a 250 s o más y 6 a 300 s o más. Inicios: 03-10 13:09, 21:43 y 22:44; 04-10 11:19, 19:09 y 20:15; 05-10 08:55; 06-10 21:01; 09-10 22:33; 10-10 19:42; 11-10 21:58; 12-10 16:56; 13-10 00:30. Las del 09, 10, 11 y 12-10 fueron durante el fin de semana largo (informado) y la del 13-10 a las 00:30 fue antes del primer día hábil. Entre las 00:35 y las 10:22 del 13-10 no hubo otra parada; todavía no se midió un día hábil completo. Es el mismo patrón de GITIN-2162. | Medio |
| H4 | ¿Hay una plataforma lenta? En 12 de las 13 paradas no se ve. El 11-10, las llamadas a PedidosYa, Rappi, PediGrido, UberEats y terceros para actualizar estados de pedidos (listo, despachado, entregado, visto) pasan de 100–115 por minuto a 0 desde las 21:57:58 hasta las 22:03:00 y vuelven con 665 llamadas en el primer minuto. Antes y después los tiempos son normales: PedidosYa «pedido listo» p95 de 102 ms antes y 90 ms después; PediGrido «entregado» p50 de 1,27 s antes y después (igual que en una ventana de control, 1,25 s); UberEats cerca de 1,1–1,2 s. En las otras 10 paradas con tráfico suficiente se repite: llamadas en 0 durante toda la parada y una ráfaga al terminar (por ejemplo 711, 931, 529 y 491 llamadas en el minuto siguiente), sin tiempos de espera agotados antes de la parada; los únicos errores de comunicación son respuestas 400 de Rappi y PediGrido; la parada del 05-10 08:55 tuvo poco tráfico y no permite concluir. **Excepción, la parada del 13-10 00:30:** en los 3 minutos previos la plataforma `I+D` devolvió «timeout of 10000ms exceeded» en 3 llamadas (00:27:46 ver pedido, 00:29:05 y 00:29:22 recibir pedido), y las llamadas de terceros tardaron entre 3,3 y 8,8 s antes de la parada y entre 2,7 y 9,7 s en los dos minutos posteriores (23 llamadas de 2,5 s o más entre las 00:27 y las 00:38, 17 de terceros y 5 de Rappi). La última llamada del lado del consumo fue a las 00:29:33 y la siguiente a las 00:35:06. Una plataforma lenta es un posible disparador de esa parada; no está probado, no explica las otras 12 y, con un tiempo de espera de 10 s por llamada, una sola llamada lenta no explica por sí sola cinco minutos sin ninguna llamada registrada. También en la parada del 12-10 aparece un timeout de `I+D` (17:01:32), pero 5 minutos después del inicio, cuando el consumo ya se había reanudado. Un registro de llamada solo se escribe al completarse. No se verificó si `I+D` forma parte del grupo «terceros» de los registros de latencia. | Medio |
| H5 | ¿Se encontró la causa en los logs? No. Durante las paradas de las 21:58–22:02 del 11-10 y de las 00:30–00:34 del 13-10 `platforms-service` siguió registrando entre 756 y 1.030 mensajes por minuto y atendiendo otras tareas (por ejemplo unas 730 a 950 consultas de token de MercadoPago por minuto, sin cambios), de modo que el servicio estaba activo; lo que se silencia es el procesamiento de los mensajes de la cola. Los errores propios del procesamiento de la cola (`setNews failed`) aparecen solo en el minuto de recuperación. Con los logs disponibles no se puede determinar por qué. El corte y la reanudación del 11-10 ocurren a menos de 2 segundos de minutos exactos (21:57:58 y 22:03:00), sin explicación. | Medio |
| H6 | ¿Escaló bien? El 11-10 el escalamiento se ejecutó y la cola se recuperó. La alarma pasó a ALARM a las 22:02:25, 4 minutos y 25 segundos después del inicio de la parada, y ejecutó la función que sube el servicio a 15 tareas. Tareas en ejecución: 5 hasta las 22:02, 9 a las 22:03, 15 a las 22:04; la antigüedad volvió a 0 a las 22:04. La alarma volvió a OK a las 22:10:25 y la función se ejecutó otra vez: la cantidad deseada volvió a 15 a las 22:11. Luego el servicio bajó en pasos de unos 3 minutos hasta 5 tareas a las 22:39. Las dos ejecuciones de la función terminaron sin errores, con 2,9 s de duración sobre un límite de 3 s. La función se ejecutó en el intervalo de cada una de las 12 paradas del 03 al 12-10; para la del 13-10 00:30 no se leyeron las tareas ni la ejecución de la función. El 11-10 el consumo se reanudó a las 22:03:00, unos 30 segundos después de pedir el escalamiento y antes de tener 15 tareas en ejecución; con estas series no se puede separar cuánto aportó el escalamiento a la recuperación. Las paradas también ocurrieron con 10 tareas (GITIN-2162), por lo que sumar tareas no se espera que elimine la causa. El pico de 306 s equivale a aproximadamente la mitad de los 10 minutos sin novedades tras los cuales, según lo informado, un pedido puede cancelarse. | Medio |
| H7 | La alarma de CloudWatch `sendMailOldestMessage` mide la antigüedad del mensaje más viejo de `PRD_BranchMessages.fifo` con estadístico Average en 300 s y umbral mayor a 25 s, sin cambios desde 2025-01-15; avisa al tema `Pedidos_Production`, que ejecuta la función de escalamiento y envía correos y SMS. Se informó que el disparador usa el estadístico Maximum; lo leído en la alarma es Average, y la alerta de Grafana por encima de 250 s (informada) es otra señal; no se verificó cuál de ellas corresponde a la indicación. Una segunda alarma, `sendMailOldestMessage100`, está en `INSUFFICIENT_DATA` desde 2025-02-22. | Medio |
| H8 | Una regla «mensajes enviados mayor a 0 y borrados igual a 0 durante 2 minutos seguidos» coincide con las 13 paradas y no genera ninguna otra corrida de 2 minutos o más en los 11 días (hay 3 minutos aislados sin borrados). Con datos por minuto estaría disponible entre 2 y 4 minutos antes que la antigüedad de 250 s en las paradas que la alcanzaron (el 11-10, después de las 21:59 contra las 22:03). La consulta `scripts-detect.sh` lista cada ocurrencia de cualquier rango. | Bajo |

## Detalle de cada parada

Hora local (UTC-3). Una parada es una corrida de 2 minutos o más con mensajes enviados mayor a 0 y borrados igual a 0 en `PRD_BranchMessages.fifo` (datos de 1 minuto). «Antigüedad máx.» es el máximo de la antigüedad del mensaje más viejo desde el inicio hasta 6 minutos después del fin. «Llamadas durante la parada» son las llamadas a plataformas del lado del consumo registradas por `platforms-service` en los logs. «Función» indica si se ejecutó la función de escalamiento en el intervalo de 15 minutos de la parada.

| # | Día | Inicio | Duración | Visibles máx. | Antigüedad máx. | Llamadas durante la parada | Timeouts de plataformas antes de la parada | Función |
|---|---|---|---|---|---|---|---|---|
| 1 | sáb 03-10 | 13:09 | 3 min | 376 | 239 s | 0 | no | sí |
| 2 | sáb 03-10 | 21:43 | 4 min | 2.380 | 322 s | 0 | no | sí |
| 3 | sáb 03-10 | 22:44 | 4 min | 2.932 | 305 s | 0 | no | sí |
| 4 | dom 04-10 | 11:19 | 5 min | 219 | 324 s | 0 | no | sí |
| 5 | dom 04-10 | 19:09 | 3 min | 862 | 287 s | 0 | no | sí |
| 6 | dom 04-10 | 20:15 | 3 min | 885 | 238 s | 0 | no | sí |
| 7 | lun 05-10 | 08:55 | 2 min | 21 | 263 s | sin tráfico suficiente para concluir (0 en toda la ventana) | no | sí |
| 8 | mar 06-10 | 21:01 | 3 min | 1.077 | 290 s | 0 | no | sí |
| 9 | vie 09-10 (fin de semana largo) | 22:33 | 3 min | 1.700 | 287 s | 0 | no | sí |
| 10 | sáb 10-10 (fin de semana largo) | 19:42 | 3 min | 680 | 260 s | 0 | no | sí |
| 11 | dom 11-10 (fin de semana largo) | 21:58 | 5 min | 1.989 | 306 s | 0 (4 en el último segundo) | no | sí (22:02:25) |
| 12 | lun 12-10 (feriado) | 16:56 | 5 min | 1.628 | 319 s | 0 | no; un timeout de `I+D` a las 17:01:32, 5 minutos después del inicio | sí |
| 13 | mar 13-10 (primer día hábil) | 00:30 | 5 min | 342 | 329 s | 0 | sí: 3 timeouts de 10 s de `I+D` entre las 00:27 y las 00:29 | no se leyó |

Fuentes: `scripts-c4.sh` y `scripts-detect.sh` (paradas), `scripts-c6.sh` (ejecuciones de la función), `scripts-c7.sh` y `scripts-c10.sh` (logs). Los fines de semana largo y el feriado son datos informados.

## Recursos afectados

| Componente | Estado observado |
|---|---|
| Cola `PRD_BranchMessages.fifo` (us-east-1) | Paradas de consumo de 2 a 5 minutos, 13 en 11 días; antigüedad máxima de 329 s |
| Servicio `platform-service` (ECS, cluster `smartfran-pedidos-production`) | Subió de 5 a 15 tareas por la alarma el 11-10 y volvió a 5; sin errores de plataformas en los logs de la parada del 11-10 |
| Plataforma `I+D` (tercero) | Tiempos de espera agotados de 10 s en los 3 minutos previos a la parada del 13-10 00:30 |
| Alarmas de CloudWatch sobre la cola | `sendMailOldestMessage` (Average, 300 s, > 25 s) activa; `sendMailOldestMessage100` en `INSUFFICIENT_DATA` desde 2025-02-22 |

## Comandos ejecutados

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | `scripts.sh` | Series de CloudWatch por cola (enviados, visibles, antigüedad) del 11-10 de 19:00 a 01:00 y de la franja equivalente del 04-10 (solo lectura; el límite de 500 series de la consulta dejó listas incompletas). Salidas en `data/` |
| C2 | `scripts-c2.sh` | `PRD_BranchMessages.fifo` y colas de mensajes fallidos por nombre, 10 días a 5 minutos (solo lectura) |
| C3 | `scripts-c3.sh` | Antigüedad, visibles, en vuelo, enviados, recibidos y borrados de `PRD_BranchMessages.fifo` del 11-10 21:30–22:30 a 1 minuto, y episodios de más de 60 s en 10 días (solo lectura) |
| C4 | `scripts-c4.sh` | 10 días a 1 minuto: corridas de 2 minutos o más con enviados mayor a 0 y borrados en 0 (solo lectura) |
| C5 | `scripts-c5.sh` | Configuración de la función de escalamiento, invocaciones, logs, eventos ECS, actividad de Application Auto Scaling y alarmas sobre SQS (solo lectura) |
| C6 | `scripts-c6.sh` | Política de invocación, suscripciones del tema SNS, historial de las alarmas del 11-10, invocaciones en 10 días y descarga del código de la función para consulta (solo lectura; el código no se analiza en este ticket) |
| C7 | `scripts-c7.sh` | Logs de `platforms-service` en Graylog por minuto, 11-10 21:50–22:10 y ventana de control 21:20–21:40 (solo lectura; mensajes crudos excluidos del control de versiones) |
| C8 | `scripts-c8.sh` | Tareas en ejecución y deseadas de `platform-service-production-service`, CPU y antigüedad por minuto, 11-10 21:50–22:45 (solo lectura) |
| C9 | `scripts-c9.sh` | Configuración completa de la alarma `sendMailOldestMessage`, sus cambios de configuración y alarmas relacionadas (solo lectura) |
| C10 | `scripts-c10.sh` | Logs de `platforms-service` por minuto alrededor de los otros inicios de parada, incluida la del 13-10 00:30 (solo lectura) |
| C11 | `scripts-detect.sh` | Lista cada ocurrencia de parada del consumo (2 minutos o más con enviados mayor a 0 y borrados en 0) y los minutos con antigüedad de 200 s o más en un rango; corrida sobre el fin de semana largo 09 a 12-10 y sobre el 13-10 hasta las 10:22 (solo lectura) |

## Acciones propuestas

1. (SRE) Decidir con Operaciones qué señal alerta: la alarma actual (Average mayor a 25 s en 5 minutos, que ejecuta el escalamiento) y la alerta de Grafana (mayor a 250 s) miden distinto; definir umbral y estadístico (Maximum según lo informado) y documentarlo.
2. (SRE) Evaluar una alerta de detección temprana sobre `PRD_BranchMessages.fifo`: mensajes enviados mayor a 0 y borrados en 0 durante 2 minutos seguidos (coincidió con las 13 paradas). Está propuesta, no decidida ni probada en producción.
3. (SRE) Volver a ejecutar `scripts-detect.sh` tras un día hábil completo para ver si las paradas ocurren con el patrón de tráfico de un día hábil, y leer las tareas y la ejecución de la función de la parada del 13-10 00:30.
4. (Operaciones / SRE) Consultar a la plataforma `I+D` sobre los tiempos de espera agotados del 13-10 entre las 00:27 y las 00:29, y verificar si coincide con alguna demora de su lado.
5. (SRE) Revisar la alarma `sendMailOldestMessage100`, en `INSUFFICIENT_DATA` desde 2025-02-22: corregirla o eliminarla.
6. (Dev) Investigar por qué el procesamiento de mensajes de la cola se detiene entre 2 y 5 minutos en todas las tareas a la vez (seguimiento en GITIN-2162).
7. (SRE) Confirmar con Operaciones quién revisó el episodio en el momento y qué acción se tomó; en este ticket solo consta que se vio en Grafana a las 22:03 (dato informado).
