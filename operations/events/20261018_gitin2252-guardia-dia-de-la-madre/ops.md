# GITIN-2252 — [OPE] Guardia Día de la Madre

**Tags:** `Operaciones`, `SmartPedidos`, `SmartLoyalty`, `Obserbavilidad`, `SRE`, `AWS`, `PROD`

## Qué pasó

- Desde el viernes 2026-10-16 los contenedores de platform-service (SmartPedidos) siguen deteniéndose con la corrección de Desarrollo desplegada ([GITIN-2248](https://smartit-ar.atlassian.net/browse/GITIN-2248)).
- El domingo 2026-10-18 el servidor SFCG-WEBS-02 (WebService de SmartLoyalty) llegó a CPU casi total desde las 14:03 y volvió a saturarse entre las 16:34 y las 17:10 (horas UTC-3, [GITIN-2250](https://smartit-ar.atlassian.net/browse/GITIN-2250)).
- El domingo a las 19:05 Mobile 02 tuvo un aumento de tráfico sin alerta, y el tablero de SmartLoyalty mostró cerca de 180 peticiones GET.
- El domingo a las 19:36 atención al cliente (CAC) consultó por la tienda 4719, que escuchaba un pedido y no recibía nada.

## Resumen

Antes de la guardia los avisos de CPU alta de la mayoría de los servidores de SmartLoyalty no llegaban a ninguna persona: los problemas de CPU de WEBS-02 de las 13:38 y las 14:38 se abrieron en Zabbix sin notificar a nadie, y los umbrales de Mobile no cubrían aumentos de tráfico como el de las 19:05. Durante el fin de semana del Día de la Madre (SmartPedidos y SmartLoyalty, producción) se atendieron las caídas de platform-service, la saturación de WEBS-02 y un aumento de tráfico en Mobile 02, y se configuraron alertas nuevas en Zabbix; la causa de la saturación de WEBS-02 y la causa de fondo de las caídas de platform-service siguen sin resolverse. Detectado entre el 2026-10-16 y el 2026-10-18.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2252](https://smartit-ar.atlassian.net/browse/GITIN-2252) |
| ID alerta | N/A — reportes manuales y alertas de Zabbix |
| Sistema | platform-service y concentrador-service (SmartPedidos, AWS); SFCG-WEBS-01/02/03, SFCG-MOBI-01/02 y balanceador SFCG-WEBS-LB (SmartLoyalty); Zabbix 6.0 |
| Severidad | No definida |
| Detectado | 2026-10-16 a 2026-10-18 |
| Resuelto | No — ver Acciones propuestas |
| Responsable | SRE |

## Causa raíz

NA

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | La corrección de Desarrollo eliminó una de las causas de las detenciones de platform-service (H4 de [GITIN-2222](https://smartit-ar.atlassian.net/browse/GITIN-2222)) y las caídas siguieron el 16-10: 60 tramos con menos tareas de las deseadas (76 minutos), los más de los cuatro días comparados (el tráfico de cada día no se controló). Siguen sin corregirse el error del registro de logs (objeto circular, H5) y el manejo de salida del proceso (H3). | Alto |
| H2 | El 17-10 a las 11:28 (UTC-3) se subió el mínimo de tareas de platform-service de 5 a 10 (máximo 25) y quedó corriendo en 10. No hay mediciones posteriores a las 11:41 de ese día: el efecto sobre las caídas no está medido. | Medio |
| H3 | Alertas de platform-service del 16-10: la de errores FATAL se abre en el minuto de la caída en 48 de 60 casos; la de tareas bajo lo deseado se abre cerca del inicio en 21 de 60 y no alcanza 18 caídas de un minuto. De 115 eventos, 114 avisos a Telegram se enviaron y 1 falló por tiempo de espera. Los eventos FATAL probablemente avisan dos veces a Chat (no verificado por evento). La alerta de Concentrador no puede dispararse hasta que Desarrollo registre líneas FATAL ([GITIN-2240](https://smartit-ar.atlassian.net/browse/GITIN-2240)). | Medio |
| H4 | La saturación de WEBS-02 (95 % a 100 % desde las 14:03) coincidió con la sonda del balanceador fallando en el 100 % de los intentos desde las 14:34 hasta el reinicio de las 15:28, con menos tráfico que los otros dos servidores. La causa no se identificó; candidatas sin probar como causa: la consulta de Zabbix por minuto (13 a 28 s de CPU por ejecución en los dos servidores de 2 núcleos), el grupo de 3 procesos en 2 núcleos y la sensibilidad de la sonda. | Alto |
| H5 | Los problemas de CPU alta de WEBS-02 (13:38 y 14:38) no notificaron a nadie: los triggers del template solo tenían la etiqueta `scope:performance`, que no coincide con ninguna acción activa. | Medio |
| H6 | Sonda `healthcheck.ashx`: según el código leído en WEBS-02 responde 400 si una muestra de 500 ms de CPU o el uso comprometido de memoria superan 80 %. Con los datos del día, la sonda falla en el 100 % de los minutos con CPU de WEBS-02 entre 80 % y 100 %, y en el 12 % bajo 40 %; WEBS-01 (4 núcleos) casi no falla (99,8 % de éxito). En los dos servidores de 2 núcleos también falla en el 12 % a 17 % de los minutos con CPU promedio bajo 40 % (50 minutos en WEBS-02, 103 en WEBS-03): compatible con una muestra única ruidosa, no demostrado (el cuerpo de las respuestas 400 no se guardó). No hay especificación de diseño para contrastar. | Medio |
| H7 | WEBS-02 tuvo un aumento de peticiones POST de 4 por segundo a las 17:00 a 247 por segundo a las 17:50 (hasta ~18:20), con CPU entre 31 % y 42 %; los otros dos servidores no lo mostraron. El problema "más de 30 POST por segundo" se abrió a las 17:24 y se recuperó a las 20:54, y avisó por Chat y Telegram. Causa desconocida. | Medio |
| H8 | Mobile 02 pasó de ~6 a 49,8 peticiones por segundo a las 19:05 (GET 40,1; CPU de 22 % a 45,5 %) y volvió a lo normal hacia las 19:18; Mobile 01 no se movió. Ningún umbral se cruzó (promedios de 10, 5 y 3 minutos de 45, 75 y 100; ráfaga de 60 por muestra), por eso no hubo alerta; en 30 días Mobile 02 tuvo 18 horas sobre 45 por segundo. El gráfico "GET Requests / 10m" mostraba una suma de diez lecturas de un minuto de una tasa por segundo (182,5), no una cantidad ni un máximo. | Medio |
| H9 | Consulta de CAC por la tienda 4719: CAC informó que quedó resuelto. Qué se limpió en la cola, cuántos mensajes había y a qué pedido correspondía no está registrado. | Bajo |

## Acciones Tomadas

| # | Hora (UTC) | Acción |
|---|---|---|
| 1 | 2026-10-16 11:52 | Alerta FATAL de Concentrador creada en Zabbix (item, trigger de errores y trigger de falta de datos); queda inactiva hasta que haya líneas FATAL ([GITIN-2240](https://smartit-ar.atlassian.net/browse/GITIN-2240)) |
| 2 | 2026-10-17 14:28 | Mínimo de tareas de platform-service subido de 5 a 10; verificado desired 10 / running 10 a las 14:29 |
| 3 | 2026-10-18 18:28 | Reinicio de SFCG-WEBS-02; el balanceador la readmitió desde las 18:38 |
| 4 | 2026-10-18 20:29 | Tres niveles de alerta de CPU (advertencia 70 %, promedio 80 %, alto 85 %) en 14 servidores de producción de SmartLoyalty, con aviso a Chat |
| 5 | 2026-10-18 21:07 | Alerta de memoria comprometida (70 %, 75 %, 80 %) en los mismos 14 servidores; paso `Healthcheck` agregado al escenario web de Zabbix de la API de POS/Gestión |
| 6 | 2026-10-18 23:08 | Atención de la consulta de CAC por la tienda 4719; CAC confirmó después que quedó resuelto (la acción hecha sobre la cola no está registrada) |
| 7 | 2026-10-18 23:28 | Etiqueta `env:PROD` en los 84 triggers de CPU y memoria (también avisan a Telegram); trigger de falla del chequeo de salud (3 de los últimos 5 chequeos distintos de 200) y etiquetas de ruteo en los triggers V1 25746 y 25753 |
| 8 | 2026-10-18 23:37 | Alerta de disco en la plantilla de Windows: nivel alto al 95 % de uso y ruteo a Chat en los cinco triggers de disco existentes |
| 9 | 2026-10-18 23:43 a 23:50 | Gráficos "GET Requests / 10m" y "Mobile POST Requests / 10m" cambiados en el tablero de suma a máximo cada 5 minutos |
| 10 | 2026-10-18 23:54 | Umbral de ráfaga de Mobile bajado de 60 a 45 peticiones por segundo |

Lectura posterior (2026-10-18 23:56 UTC): los 84 triggers de CPU y memoria, el trigger del chequeo de salud y los triggers V1 existen sin problemas abiertos ni errores; los 14 items de memoria recolectan; los triggers de disco nuevos se ven en 2 de 14 servidores y los otros 12 esperan el descubrimiento horario. Ninguno de los avisos nuevos se disparó todavía, así que su entrega no está probada.

## Recursos afectados

| Recurso | Plataforma | Detalle |
|---|---|---|
| platform-service | SmartPedidos (AWS) | Detenciones de contenedores; mínimo de tareas 5 → 10 |
| concentrador-service | SmartPedidos (AWS) | Alerta FATAL creada, inactiva |
| SFCG-WEBS-01/02/03 y SFCG-WEBS-LB | SmartLoyalty | Saturación de WEBS-02, sonda del balanceador, alertas nuevas |
| SFCG-MOBI-01/02 | SmartLoyalty | Aumento de tráfico de las 19:05, umbral de ráfaga, gráficos del tablero |
| Zabbix y tablero SmartLoyalty | Monitoreo | Alertas nuevas, macro de ráfaga, gráficos de Mobile |

## Acciones propuestas

| # | Responsable | Acción | Estado |
|---|---|---|---|
| 1 | (Dev) | Decidir cómo tratar el error del registro de logs (H5) y el manejo de salida del proceso (H3), causas que siguen sin corregirse en platform-service | Por decidir |
| 2 | (SRE) | Medir el comportamiento de platform-service desde el cambio a 10 tareas (caídas, líneas FATAL, CPU, pedidos por tarea), separando antes y después de las 11:28 del 17-10 | Pendiente |
| 3 | (SRE) | Verificar si la definición de infraestructura como código revertiría el mínimo de 10 en una próxima aplicación | Pendiente |
| 4 | (SRE) | Identificar la causa de la saturación de WEBS-02 con una captura a nivel de pedido o código durante un episodio; evaluar la consulta de Zabbix por minuto y el grupo de procesos | Pendiente (ticket de seguimiento) |
| 5 | (SRE) / (Dev) | Chequeo de salud: guardar el cuerpo de la respuesta 400 durante una falla y evaluar no depender de una sola muestra de 500 ms en los servidores de 2 núcleos | Por decidir |
| 6 | (SRE) | Explicar el aumento de POST solo en WEBS-02 entre las 17:10 y las 18:20 | Pendiente |
| 7 | (SRE) | Confirmar la entrega de los avisos nuevos (Chat y Telegram), el posible aviso doble entre las acciones 7 y 12 y la aparición de los triggers de disco en los 12 servidores restantes | Pendiente |
| 8 | (SRE) | Terminar el ajuste de los gráficos de Mobile (unidad `req/s` y títulos) y decidir los gráficos "POST + GET", que usan un promedio | Parcial: máximo cada 5 minutos hecho |
| 9 | (SRE) | Probar que el umbral de ráfaga de 45 dispare | Pendiente |
| 10 | (SRE) | Evaluar cambios de alertas de platform-service: señal de un minuto para la alerta de tareas, su margen con 10 tareas y el aviso doble de los eventos FATAL | Por decidir |
| 11 | (SRE) | Ejecutar las consultas de solo lectura de la cola de la tienda 4719 y registrar qué se limpió y cuántos mensajes había | Pendiente |

## Hallazgos secundarios

- Mobile 01 recibe cerca de 0,3 peticiones por segundo frente a 5 a 8 de Mobile 02 durante todo el día; no se analizó el motivo.
- Mobile 02 tiene 473 puntos horarios en 30 días frente a 719 de Mobile 01 en el mismo dato; no se miraron las horas faltantes.
