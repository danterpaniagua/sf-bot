# Brief SmartPedidos y SmartLoyalty: del viernes 16-10 a hoy 18-10 ([GITIN-2252](https://smartit-ar.atlassian.net/browse/GITIN-2252), Guardia Día de la Madre)

Horas en UTC-3. Fuente: mis mediciones del 16 al 18-10 (Zabbix, CloudWatch, Azure Monitor) y las investigaciones de los tickets citados.

## Resumen

- Platform-service viene perdiendo tareas (contenedores) desde antes del viernes. La corrección de Desarrollo desplegada el viernes eliminó una de las causas (H4) y las caídas no bajaron, porque las otras dos causas siguen sin corregir. Medí 60, 66 y 96 tramos con menos tareas de las deseadas el 16, 17 y 18-10.
- El sábado 17-10 a las 11:28 subí el mínimo de tareas de platform-service de 5 a 10 y verifiqué que quedó en 10 corriendo a las 11:30. Las caídas continuaron después del cambio.
- Por el Día de la Madre reinicié todas las máquinas virtuales para empezar de cero.
- El domingo WEBS-02 se saturó dos veces y tuvo un aumento de peticiones POST desde las 17:10; la causa sigue sin identificarse.
- En Mobile el tablero mostró unas 180 peticiones, cifra que era una suma de lecturas; el pico real fue de 49,8 por segundo, sin alerta. Bajé el umbral de ráfaga de 60 a 45.
- A las 19:36 CAC consultó por la tienda 4719 (el local escuchaba un pedido y no le llegaba nada). Su cola tenía 4 mensajes atascados, recibidos cada 3 minutos y nunca borrados; a las 20:13 reinicié la cola y borré los 4 mensajes, y CAC confirmó que quedó resuelto. No leí los mensajes antes de borrarlos, así que no sé si esos pedidos llegaron a la tienda.

## Cronología

| Fecha / hora | Qué pasó | Estado de la información |
|---|---|---|
| 13 y 14-10 | Platform-service se detuvo 97 y 101 veces por día (según los avisos por mail) por un error no controlado que termina el proceso | Medido ([GITIN-2222](https://smartit-ar.atlassian.net/browse/GITIN-2222)) |
| 15-10 | Creé las alertas de Zabbix: tareas por debajo de las deseadas y errores FATAL de platform | Aplicado |
| 16-10 09:26 | Desarrollo fusionó la corrección; la revisión de platform arrancó a las 09:36 | Hora medida; infiero que la revisión incluye la corrección por el momento y porque desapareció ese error |
| 16-10 | 60 tramos con menos tareas de las deseadas (76 minutos), los más de los cuatro días comparados; desapareció la causa H4 y la H5 (error del registro de logs) quedó como única firma de FATAL | Medido; el tráfico de cada día no se controló |
| 16-10 | La alerta FATAL se abrió en el minuto de la caída en 48 de 60 casos; la de ECS se abrió cerca del inicio en 21 de 60 y no alcanzó 18 caídas. De 115 eventos, 114 avisos a Telegram se enviaron y 1 falló | Medido; no verifiqué que llegaran a las personas |
| 16-10 | Apliqué la alerta FATAL de Concentrador ([GITIN-2240](https://smartit-ar.atlassian.net/browse/GITIN-2240)); queda inactiva hasta que Concentrador registre líneas FATAL | Aplicado |
| 17-10 11:28 | Mínimo de tareas de platform-service de 5 a 10 (máximo 25) | Verificado |
| 18-10 | Reinicio de todas las máquinas virtuales por el Día de la Madre | Hecho |
| 18-10 19:36 a ~21:07 | Consulta de CAC por la tienda 4719; a las 20:13 reinicié la cola y borré 4 mensajes atascados | Medido (cola) y hecho |

## WebService (SFCG-WEBS-02) hoy, domingo 18-10 ([GITIN-2250](https://smartit-ar.atlassian.net/browse/GITIN-2250))

| Hora | Qué pasó | Estado de la información |
|---|---|---|
| 10:00 a 14:00 | CPU de WEBS-02 de 39 % a 86 %, y 95 % a 100 % desde las 14:03 (sostenido desde las 14:27), con menos pedidos que los otros dos servidores | Medido |
| desde ~14:34 | El balanceador dejó de enviarle conexiones nuevas: su chequeo de salud falló en el 100 % de los intentos, mientras Zabbix veía el puerto abierto | Medido; que el balanceador lo excluyera lo infiero |
| 13:38 y 14:38 | Zabbix abrió problemas de CPU alta (hasta 13:59 y 15:29) sin notificar a nadie, por falta de ruteo | Medido; el ruteo ya está corregido |
| 15:28 | Reinicié la máquina; el balanceador la readmitió desde las 15:38; CPU variable entre 22 % y 100 % | Medido |
| 16:34 a 17:10 | Segunda saturación (97 % a las 17:04) | Medido |
| ~17:02 | Los tres servidores subieron a la vez | Medido; causa desconocida |
| 17:10 a ~18:20 | Aumento de peticiones POST solo en WEBS-02: de 4 por segundo a 57 a las 17:15, unos 100 a las 17:20 y 247 a las 17:50; 40-50 desde las 18:25. Su CPU estuvo entre 31 % y 42 % | Medido; causa desconocida |
| 17:24 a 20:54 | Problema de "más de 30 POST por segundo" abierto y recuperado a las 20:54; envió avisos a Chat y Telegram (estado enviado, sin errores) | Medido |

La causa de la saturación no la identifiqué. Los candidatos que tengo, sin probar como causa: la consulta por minuto de Zabbix (13 a 28 s de CPU por ejecución en los dos servidores de 2 núcleos), el grupo de 3 procesos en 2 núcleos y la sensibilidad del chequeo de salud.

**Chequeo de salud (healthcheck.ashx).** Leí el código en WEBS-02: responde 400 si una muestra de 500 ms de CPU o el uso comprometido de memoria superan el 80 %, y 200 en otro caso; el balanceador lo consulta cada 15 segundos y una falla alcanza para marcar el servidor como no sano.
- Coincide con lo que vi: respondió 400 en 1,7 s con el servidor saturado (15:24) y 200 en 0,8 s tras el reinicio; 15 llamadas locales a las 17:40 respondieron 200 con memoria de 24 a 34 % y muestras de CPU de 0,7 a 69 %.
- Lo medí minuto a minuto desde las 10:00. En WEBS-02, con CPU de 80 a 100 % el chequeo falló en el 100 % de los minutos (disponibilidad media 13,9 %); de 60 a 80 %, en el 99 % (53,5 %); de 40 a 60 %, en el 43 %; bajo 40 %, en el 12 %. En WEBS-01 (4 núcleos) casi no falla (99,8 %). En los dos servidores de 2 núcleos falla además en 12 % a 17 % de los minutos con CPU promedio bajo 40 % (WEBS-02 50 minutos, WEBS-03 103 minutos); es compatible con una muestra única ruidosa, pero no lo demostré: no guardé el cuerpo de las respuestas 400.
- No pude contrastar la intención de diseño porque no hay especificación; el código solo lo leí en el archivo del servidor.

## Mobile hoy, domingo 18-10: cifra inflada del tablero

- **Lo que vi:** el gráfico "GET Requests / 10m" de Mobile mostraba cerca de 180 peticiones GET alrededor de las 19:00.
- **Lo que era:** una suma de diez lecturas de un minuto de una tasa por segundo (182,5 entre las 19:00 y las 19:09), no una cantidad de peticiones ni un máximo. La tasa real tuvo un pico de 49,8 por segundo en Mobile 02 (GET 40,1) a las 19:05 y volvió a lo normal hacia las 19:18; Mobile 01 no se movió.
- **El aumento de tráfico fue real** (unas 8 veces el nivel habitual de Mobile 02) pero no alcanzó ningún umbral, por eso no hubo aviso. En 30 días Mobile 02 tuvo 18 horas por encima de 45 peticiones por segundo, así que el pico no fue inusual para ese servidor.
- **Lo que hice:** bajé el umbral de ráfaga de Mobile de 60 a 45 peticiones por segundo y pasé los dos gráficos "por 10 minutos" a máximo cada 5 minutos. Falta cambiar la unidad y los títulos, y no he verificado que el umbral nuevo dispare.

## SmartPedidos: caídas, CPU y colas (medido el domingo, hasta las 22:01)

- **Caídas de platform-service** (tramos con menos tareas que las deseadas): 16-10 60 tramos y 76 minutos; 17-10 66 y 79 (14 y 17 antes del cambio a 10 tareas, 52 y 62 después); 18-10 96 y 135. Las cifras de antes y después del cambio no son directamente comparables (con 10 tareas "por debajo de lo deseado" es otra medida) y no controlé el tráfico de cada día. En el mínimo, el servicio bajó a 2 de 5 tareas el 16-10 y a 7 de 10 hoy. Las caídas se acentúan desde el viernes.
- **CPU:** el promedio por minuto de platform-service no pasó de 31 % ningún día; su máximo por minuto llegó a 87-89 %, con 28, 32 y 49 minutos sobre 75 % el 16, 17 y 18-10. Concentrador-service, que corre con una sola tarea, llegó a 99,9 %, 99,6 % y 100 % de máximo, con 13, 11 y 18 minutos sobre 75 % y 12, 1 y 5 sobre 90 %. Con el máximo por minuto, ambos servicios cruzan el 75 % todos los días.
- **Cola principal:** el volumen sigue una curva diaria (39 mensajes por minuto a las 10 h, 844 a las 15 h, 231 a 277 entre las 19 h y las 20 h); durante el pico de Mobile (19:02 a 19:18) fue de 248 por minuto contra 231 de media horaria. El mensaje más antiguo no pasó de 32 segundos en todo el día (el umbral de alerta es de 200 a 250 s) y hubo como máximo 8 mensajes visibles. Con estos datos no distingo picos puntuales sobre la curva diaria; en las ventanas de saturación de WEBS-02 el volumen estaba en el tramo alto de la curva (14 h a 16 h).
- **Colas de mensajes fallidos:** no vi ningún aumento de mensajes visibles desde las 10:00 (`DeadLetter.fifo` en 1 todo el día; `MainDeadLetter.fifo` bajó de 102 a 12 entre las 16:50 y las 21:17, solo descensos, y no sé quién o qué los retiró). Uso los mensajes visibles y no los enviados, porque los enviados no cuentan los que llegan por reintentos.
- **MongoDB:** durante el fin de semana la base de datos funcionó sin saturación de CPU, RAM ni red y sin alertas de CPU en Zabbix (revisado el domingo 18-10 a las 22:06; datos cada 10 minutos): el nodo más cargado llegó a 38,7 %, 40,6 % y 49,5 % de CPU el 16, 17 y 18-10 (el máximo el domingo a las 15:42). No he verificado conexiones, retraso de replicación, latencia de operaciones, IOPS ni cambios de primario: Zabbix no los recolecta.

## Pendiente

- Identificar la causa de la saturación de WEBS-02 y explicar el aumento de POST solo en ese servidor entre las 17:10 y las 18:20.
- Decidir si el chequeo de salud debe dejar de depender de una sola muestra de 500 ms en los servidores de 2 núcleos.
- Decidir con Desarrollo qué hacer con las dos causas de caídas de platform-service que siguen sin corregirse (H5 y el manejo de salida del proceso).
- Medir el efecto de las 10 tareas con más datos (caídas, líneas FATAL, CPU y pedidos por tarea) y verificar si la definición de infraestructura como código revertiría el mínimo de 10 en una próxima aplicación.
- Analizar el comportamiento de Concentrador con más de una instancia.
- Comprobar que las alertas nuevas lleguen cuando se disparen (ninguna se disparó todavía) y probar que el umbral de ráfaga de 45 dispare.
- Terminar el ajuste de los gráficos de Mobile (unidad y títulos) y decidir los gráficos "POST + GET", que usan un promedio.
- Cruzar los datos de los servidores WebService con la base de datos de SmartLoyalty en las ventanas de saturación y de aumento de POST ([GITIN-2251](https://smartit-ar.atlassian.net/browse/GITIN-2251)).
- Evaluar cambios de alertas de platform-service: una señal de un minuto para la alerta de tareas, su margen con 10 tareas y el aviso doble a Chat de los eventos FATAL. Ninguno está decidido.

## Tickets

- Escalamiento: [GITIN-2252](https://smartit-ar.atlassian.net/browse/GITIN-2252)
- Caídas de platform-service y capacidad: [GITIN-2248](https://smartit-ar.atlassian.net/browse/GITIN-2248)
- WebService de SmartLoyalty y alertas nuevas: [GITIN-2250](https://smartit-ar.atlassian.net/browse/GITIN-2250); base de datos en la misma ventana: [GITIN-2251](https://smartit-ar.atlassian.net/browse/GITIN-2251)
- Alertas de la plataforma: [GITIN-2222](https://smartit-ar.atlassian.net/browse/GITIN-2222), [GITIN-2229](https://smartit-ar.atlassian.net/browse/GITIN-2229) y [GITIN-2240](https://smartit-ar.atlassian.net/browse/GITIN-2240)
