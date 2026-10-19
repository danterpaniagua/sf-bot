**Asunto:** Estado SmartPedidos y SmartLoyalty del viernes 16-10 al domingo 18-10 — [GITIN-2252](https://smartit-ar.atlassian.net/browse/GITIN-2252), [GITIN-2248](https://smartit-ar.atlassian.net/browse/GITIN-2248), [GITIN-2250](https://smartit-ar.atlassian.net/browse/GITIN-2250)

**Detectado:** Desde el viernes la plataforma de SmartPedidos sigue perdiendo contenedores aun con la corrección de Desarrollo desplegada, con más caídas cada día (60, 66 y 96 tramos con menos tareas de las deseadas el 16, 17 y 18-10, este último hasta las 22:01); el domingo una instancia del WebService de SmartLoyalty se saturó dos veces y tuvo un aumento de peticiones desde las 17:00, Mobile tuvo un pico de tráfico a las 19:05 con un gráfico que mostró una cifra inflada, la cola de una tienda tenía 4 mensajes atascados desde hacía más de tres horas, y la CPU máxima por minuto de la plataforma (hasta 89 %) y de Concentrador (hasta 100 %) superó el 75 % todos los días.

**Corregido:** He vaciado la cola de la tienda 4719 y CAC confirmó que quedó resuelto, he configurado alertas de CPU, memoria, disco y estado del WebService en 14 servidores, y he bajado el umbral de ráfagas de Mobile para que un pico como el del domingo sea detectado; ninguna de las alertas nuevas se disparó todavía, así que no he probado que lleguen, y las caídas de la plataforma continuaron después de subir su capacidad.

**Pendiente:** Queda por decidir con Desarrollo cómo tratar las dos causas de caídas que siguen sin corregirse, identificar la causa de la saturación del WebService, analizar el comportamiento de Concentrador con más de una instancia (corre con una sola y llega a cerca de 100 % de CPU en el máximo por minuto), y comprobar que las alertas nuevas lleguen cuando se disparen.

| Proyecto | Componente | Antes | Después | Ticket |
|---|---|---|---|---|
| SmartPedidos | Capacidad mínima de la plataforma | 5 tareas | 10 tareas | [GITIN-2248](https://smartit-ar.atlassian.net/browse/GITIN-2248) |
| SmartPedidos | Alertas de caídas de la plataforma y de errores graves | Sin alertas de este tipo | Creadas el 15 y 16-10 (la de Concentrador queda inactiva hasta que Desarrollo registre esos errores) | [GITIN-2222](https://smartit-ar.atlassian.net/browse/GITIN-2222), [GITIN-2229](https://smartit-ar.atlassian.net/browse/GITIN-2229), [GITIN-2240](https://smartit-ar.atlassian.net/browse/GITIN-2240) |
| SmartPedidos | Cola de la tienda 4719 | 4 mensajes atascados desde las 16:34 | Vacía tras reiniciarla a las 20:13 | Sin ticket |
| SmartLoyalty | Alertas de CPU, memoria, estado del WebService y disco | Los avisos de CPU alta no llegaban a nadie | Tres niveles de aviso en 14 servidores, chequeo de estado del WebService y nivel adicional de disco | [GITIN-2250](https://smartit-ar.atlassian.net/browse/GITIN-2250) |
| SmartLoyalty | Umbral de ráfagas de Mobile | 60 peticiones por segundo | 45 peticiones por segundo | Sin ticket |
| SmartLoyalty | Gráficos de Mobile "por 10 minutos" | Suma de lecturas, que mostraba cerca de 180 | Máximo cada 5 minutos (unidad y títulos pendientes de ajustar) | Sin ticket |

Saludos.
