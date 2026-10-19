# Resumen guardia Día de la Madre ([GITIN-2252](https://smartit-ar.atlassian.net/browse/GITIN-2252)) — del viernes 16-10 al domingo 18-10

## SmartPedidos
- **Caídas de platform-service ([GITIN-2248](https://smartit-ar.atlassian.net/browse/GITIN-2248)):** la corrección de Desarrollo desplegada el viernes eliminó una causa (H4); quedan dos sin corregir (error del registro de logs y manejo de salida del proceso), pendientes de decisión con Desarrollo. Tramos con menos tareas que las deseadas por día: 60 (16-10), 66 (17-10) y 96 (18-10, hasta las 22:01); minutos: 76, 79 y 135. Los números no son directamente comparables tras el cambio a 10 tareas y el tráfico de cada día no se controló. Esta noche, entre las 21:14 y las 21:41, volvieron a abrirse avisos de caídas de la plataforma (solo he leído los nombres de los eventos).
- **Capacidad ([GITIN-2248](https://smartit-ar.atlassian.net/browse/GITIN-2248)):** el sábado 17-10 a las 11:28 subí el mínimo de tareas de 5 a 10. En el mínimo, el servicio bajó a 2 de 5 tareas el 16-10 y a 7 de 10 hoy.
- **CPU (máximo por minuto, criterio del umbral de 75 %):** platform-service llegó a 87-89 % cada día, con 28, 32 y 49 minutos sobre 75 % (16, 17 y 18-10); su promedio no pasó de 31 %. Concentrador-service llegó a 99,9 %, 99,6 % y 100 % cada día, con 13, 11 y 18 minutos sobre 75 % y 12, 1 y 5 minutos sobre 90 %; su promedio también llegó a 81,8 %, 99,6 % y 77,7 % en algún minuto (corre con una sola tarea, así que el promedio y el máximo se parecen). En ninguno de los dos casos el umbral de 75 % quedó sin cruzarse. Concentrador-service no mostró caídas de tareas en esos días (salvo un minuto el 17-10); no analicé qué causó sus picos de CPU.
- **Cola principal de pedidos:** sigue una curva diaria sin picos puntuales distinguibles (248 mensajes por minuto durante el pico de Mobile contra 231 de media horaria); el mensaje más antiguo no pasó de 32 s en todo el día. Lo que he observado (que los picos de WebService y Mobile también se ven en la cola) no se confirma ni se descarta con estos datos.
- **Colas de mensajes fallidos:** sin aumento de mensajes visibles en el día.
- **MongoDB:** durante el fin de semana la base de datos funcionó sin saturación de CPU, RAM ni red y sin alertas de CPU en Zabbix: el nodo más cargado llegó a 38,7 %, 40,6 % y 49,5 % de CPU el 16, 17 y 18-10 (el máximo el domingo 15:42). Conexiones, retraso de replicación, latencia de operaciones, IOPS y cambios de primario no los he verificado: Zabbix no los recolecta.
- **Tienda 4719 (domingo 19:36):** CAC consultó porque el local escuchaba un pedido y no recibía nada. La cola de la tienda tenía 4 mensajes atascados, recibidos cada 3 minutos y nunca borrados, el más viejo enviado hacia las 16:34. A las 20:13 reinicié la cola y borré los 4 mensajes; desaparecieron a las 20:14 y CAC confirmó que quedó resuelto. No sé por qué no se borraban ni si esos pedidos llegaron a la tienda.

## SmartLoyalty
- **Reinicio previo:** por el Día de la Madre reinicié todas las máquinas virtuales para empezar de cero.
- **WEBS-02 ([GITIN-2250](https://smartit-ar.atlassian.net/browse/GITIN-2250)):** saturado desde las 14:03 y de nuevo de 16:34 a 17:10; la sonda del balanceador lo sacó de rotación desde las 14:34 hasta que lo reinicié a las 15:28. Causa sin identificar.
- **Aumento de POST ([GITIN-2250](https://smartit-ar.atlassian.net/browse/GITIN-2250)):** desde las 17:10 solo en WEBS-02 (hasta 247 por segundo a las 17:50, con CPU de 31 % a 42 %); avisó por Chat y Telegram. Causa desconocida.
- **Chequeo de salud ([GITIN-2250](https://smartit-ar.atlassian.net/browse/GITIN-2250)):** falla cuando el servidor está ocupado, como indica su código; en los servidores de 2 núcleos también falla en 12 % a 17 % de los minutos con CPU bajo 40 % (no demostré el motivo).
- **Mobile:** pico de 49,8 peticiones por segundo en Mobile 02 a las 19:05, sin alerta (ningún umbral se cruzó). El tablero mostró unas 180 peticiones: era una suma de lecturas, no un máximo.

## Cambios aplicados
- He creado las alertas de caídas y de errores graves de la plataforma y la de Concentrador (15 y 16-10): [GITIN-2222](https://smartit-ar.atlassian.net/browse/GITIN-2222), [GITIN-2229](https://smartit-ar.atlassian.net/browse/GITIN-2229) y [GITIN-2240](https://smartit-ar.atlassian.net/browse/GITIN-2240).
- He configurado alertas nuevas en 14 servidores ([GITIN-2250](https://smartit-ar.atlassian.net/browse/GITIN-2250)): CPU (3 niveles), memoria comprometida, chequeo de salud del WebService y disco (nivel al 95 %, ya presente en los 14), con aviso a Chat y Telegram. Lectura de las 21:48: sin problemas abiertos ni errores; 47 avisos enviados desde las 20:28, ninguno proveniente de las alertas nuevas.
- He bajado el umbral de ráfaga de Mobile de 60 a 45 peticiones por segundo y he pasado los gráficos de Mobile a máximo cada 5 minutos.

## Pendiente
- Causa de la saturación de WEBS-02 y de las caídas de platform-service.
- Efecto de las 10 tareas: medir con más datos tras el cambio (hoy hay más tramos que antes, con la reserva de comparabilidad indicada).
- Comprobar que las alertas nuevas lleguen cuando se disparen (ninguna se disparó aún).
- Analizar el comportamiento de concentrador-service con más de una instancia (hoy corre con una sola tarea y llega a ~100 % de CPU en el máximo por minuto); no sé si más instancias lo resolverían.

## Tickets
- Escalamiento: [GITIN-2252](https://smartit-ar.atlassian.net/browse/GITIN-2252)
- Caídas de platform-service y capacidad: [GITIN-2248](https://smartit-ar.atlassian.net/browse/GITIN-2248)
- WebService de SmartLoyalty y alertas nuevas: [GITIN-2250](https://smartit-ar.atlassian.net/browse/GITIN-2250)
- Base de datos de SmartLoyalty en la misma ventana (subtarea de GITIN-2250): [GITIN-2251](https://smartit-ar.atlassian.net/browse/GITIN-2251)
- Alertas de la plataforma: [GITIN-2222](https://smartit-ar.atlassian.net/browse/GITIN-2222), [GITIN-2229](https://smartit-ar.atlassian.net/browse/GITIN-2229) (errores graves de platform) y [GITIN-2240](https://smartit-ar.atlassian.net/browse/GITIN-2240) (Concentrador)
- Sin ticket todavía: pico de Mobile del 19:05 (y el cambio de umbral de ráfaga y de gráficos), consulta de la tienda 4719, y las mediciones de CPU, colas y MongoDB de este resumen.
