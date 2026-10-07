Asunto: Resultado del análisis — posible inicio de temporada alta (MobileAppService, SmartPedidos, WebService, WebServiceV2)

Hola equipo,

Les comparto el resultado de extender a otros servicios el análisis que arrancamos sobre MobileAppService, para chequear si lo que vimos ahí es un caso aislado o parte de un patrón más amplio.

**Punto de partida:** en el trabajo de línea base de tráfico de MobileAppService (GITIN-1969), confirmamos un aumento real de tráfico el fin de semana del 29-30/08, concentrado en un pico puntual el sábado por la tarde, por encima de los tres fines de semana anteriores. No pudimos confirmar si corresponde a un evento de negocio puntual (entrada a temporada alta) o no — solo el aumento de tráfico en sí quedó confirmado.

**Resultado del chequeo cruzado:**
- **SmartPedidos:** también muestra un aumento real. Contando directamente la cantidad de eventos de pedidos generados (la métrica más directa de actividad real que pudimos conseguir), este fin de semana tuvo un 32% más de volumen que el único fin de semana anterior completo con el que pudimos comparar (la base de datos solo retiene 15 días de historial, así que no llegamos a tener más de un fin de semana de referencia limpio). El procesamiento del sistema (uso de CPU, tiempo de espera en cola) se mantuvo estable pese al mayor volumen — es decir, hubo más actividad real, pero el sistema la absorbió sin mostrar señales de sobrecarga.
- **WebService (on-premise de SmartFran):** no pudimos completar la comparación contra fines de semana anteriores — encontramos que este servicio retenía muy poco historial de datos (una inconsistencia de configuración, ya corregida para adelante), y ese historial no se puede recuperar retroactivamente. Sí pudimos ver el detalle de este fin de semana con precisión de 15 minutos: hay un pico real el domingo 11:45 (46,7 req/s, con un instante puntual de 1 minuto llegando a 221 req/s dentro de esa ventana) — no tenemos con qué compararlo todavía, pero queda documentado como referencia.
- **WebServiceV2 (SmartCloud):** mismo problema de historial que WebService — es una plataforma distinta (SmartCloud, no on-premise), no comparable con el punto anterior. Volumen de tráfico bastante menor, mismo patrón de picos sábado/domingo a la tarde, sin datos anteriores para comparar.

**Conclusión, con lo que tenemos hasta ahora:** tanto MobileAppService como SmartPedidos muestran un aumento real de actividad este fin de semana, lo que es más consistente con un posible inicio de temporada alta que un evento aislado de un solo servicio. La base de comparación de SmartPedidos es más débil que la de Mobile (un solo fin de semana de referencia en vez de tres), y todavía nos falta el dato de WebService y WebServiceV2 para completar el panorama — ambos quedan con la primera comparación real recién disponible el próximo fin de semana. Vamos a poder confirmar con más solidez en ese momento.

Saludos,
Dante
