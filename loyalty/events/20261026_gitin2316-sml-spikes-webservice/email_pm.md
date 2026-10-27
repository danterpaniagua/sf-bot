**Asunto:** Pico de requests en el WebService de SmartLoyalty (26/10)

Hola,

Les resumo lo ocurrido con el pico de requests en el WebService. Más información en [GITIN-2316](https://smartit-ar.atlassian.net/browse/GITIN-2316).

- El 26/10, entre las 21:14 y las 22:00 (UTC-3), una única dirección IP externa envió 133.048 pedidos GET al WebService, casi todos a rutas que no existen. El 99,97 % recibió respuesta 404, y de esa dirección no hubo respuestas 200 ni 500.
- El pico fue de más de 300 pedidos por segundo entre las 21:21 y las 21:27, cuando lo habitual son menos de 1 GET por segundo: el servicio recibe casi solo POST.
- Solo uno de los tres servidores del WebService recibió ese tráfico, lo que es coherente con que el Load Balancer reparte por IP de origen.
- No se determinó el origen del tráfico.

**Propuesta**

- Configurar en IIS, en los tres servidores del WebService, un límite de pedidos por segundo por dirección IP, para cortar a quien supere ampliamente el uso normal. En uno de los servidores ya está activo en modo de prueba: registra lo que bloquearía, pero no bloquea nada.
- Sumar una denegación específica para la dirección de origen, una vez confirmado que no es propia ni una prueba autorizada.
- Revisar qué carpetas y tipos de archivo del sitio se pueden pedir desde Internet, y restringir los que no deban publicarse.
- Hoy el tráfico llega por HTTP a través del Load Balancer, sin un WAF delante; por eso la primera protección propuesta se hace en IIS. El límite por tasa reduce este tipo de tráfico pero no detiene cada pedido, y una protección delante del Load Balancer quedaría como una evaluación aparte.

Saludos,
