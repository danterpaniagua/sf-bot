**Asunto:** GITIN-2209 — SmartPedidos reintenta en exceso la consulta de tokens de MercadoPago a SmartCloud cuando falla

Hola,

Estamos viendo que, cuando MercadoPago rechaza la renovación del token de una cuenta, SmartPedidos vuelve a pedirlo a SmartCloud una y otra vez, sin pausa. Eso llena el almacenamiento de logs de SmartCloud y queremos coordinar con ustedes cómo cortar esos reintentos.

**Qué vemos**

- Desde la noche del 7 de octubre (cerca de las 22:30), el servicio Business de SmartCloud en producción recibe alrededor de un millón de consultas por día al endpoint de credenciales de billetera, para 5 cuentas de MercadoPago. En una muestra de unos 40 segundos, 2 de esas cuentas fallaban en cada intento: MercadoPago rechaza la renovación de su token (autorización inválida) para la aplicación QR. Los fallos son unos 8,8 por segundo y se mantienen de día y de noche.
- Cada intento fallido deja unas seis líneas de log en SmartCloud, de modo que el volumen de ese servicio pasó de unos 170 mil mensajes por día a unos 4,5 millones. Con el espacio ya ampliado, el ritmo actual lo agotaría de nuevo en una a dos semanas (estimación), y el lunes 12 es feriado.
- Las consultas se hacen con el acceso de máquina a máquina que SmartPedidos usa para hablar con SmartCloud, y ese acceso está configurado tanto en el Concentrador como en Platform. Las 2 cuentas que fallan también aparecen en los errores de token de MercadoPago del Concentrador. Por eso creemos que el origen está del lado de SmartPedidos, pero todavía no pudimos confirmar cuál de los dos servicios hace la mayor parte de las consultas.

**Lo que vimos en el código de SmartPedidos**

- En el Concentrador, el chequeo periódico de apertura y cierre de sucursales de MercadoPago pide el token de cada sucursal. Si SmartCloud no devuelve un token, el Concentrador no recuerda ese resultado, así que en la pasada siguiente vuelve a pedirlo. Hay un mecanismo que evita pedidos simultáneos para una misma cuenta, pero no uno que espacie los reintentos después de un fallo.
- En Platform, al recibir cada pedido de MercadoPago con reglas de aceptación automática, si el token no está guardado se pide a SmartCloud en ese momento, también sin recordar el fallo previo.
- Hay varias sucursales por cuenta, así que una cuenta con token rechazado genera consultas repetidas.

**Qué dudas nos quedan**

- El Concentrador registra pocas líneas de error de este tipo (alrededor de 40 cada 5 minutos), muy por debajo de los ~8,8 fallos por segundo que ve SmartCloud. Hay que ver si Platform, otras instancias o algún otro ambiente apuntando a producción están haciendo el resto de las consultas.
- No sabemos si algo cambió en SmartPedidos alrededor del 7 de octubre a las 22:30 (despliegue, cambio de configuración, alta de sucursales).

**Proponemos coordinar**

1. Que el Concentrador y Platform recuerden por unos minutos, por cuenta, que SmartCloud no pudo entregar el token, y no lo vuelvan a pedir en ese lapso.
2. Que los reintentos tras un fallo tengan una espera creciente, en lugar de repetirse en cada pasada.
3. Que se registre un solo mensaje de error por cuenta y por intervalo, y no uno por sucursal.
4. Que confirmen cuál servicio y cuántas instancias consultan el endpoint de SmartCloud y con qué frecuencia.

Del lado de SmartCloud también proponemos un cambio equivalente, para que el servicio no reintente la renovación en cada consulta; está en las acciones del ticket y todavía no está decidido. Además necesitamos identificar a los titulares de esas 2 cuentas para que vuelvan a autorizar la vinculación con MercadoPago.

Más información: [GITIN-2209](https://smartit-ar.atlassian.net/browse/GITIN-2209)

Saludos,
Dante
