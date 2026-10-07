# Email a Operaciones — GITIN-2194

**Asunto:** Propuesta: reemplazar la consulta a timezonedb en el chequeo de UTC del Concentrador

Hola equipo,

Estuve viendo los falsos positivos que tenemos con el aviso "Concentrador: informacion cambios UTC en entorno production". En varios casos el correo parece marcar una diferencia que no existe. Un ejemplo reciente: Chile figuraba como -4 según timezonedb contra -3 en SmartPedidos, y la base de zonas horarias que trae Node (IANA) indica -3, igual que lo registrado en SmartPedidos. Todavía no confirmé la fecha de ese correo, por lo que no puedo afirmar si fue un error de la API o un cambio de hora real que justificaba el aviso.

Cómo funciona hoy: una vez por día, y también al iniciar el servicio en producción, el Concentrador consulta la API externa de timezonedb para cinco zonas y compara el resultado con el UTC guardado por país. Cualquier error de esa API también termina en un correo, y la clave de la API está escrita en el código.

Les propongo calcular el UTC esperado de cada país con la base de zonas horarias que ya trae Node, sin consultar ningún servicio externo. La comparación con lo registrado en SmartPedidos, el cron y el correo quedarían igual.

Qué mejora:
- Un servicio externo menos del que depender.
- Menos avisos que no corresponden a un cambio real.
- Un control local e inmediato.
- No agrega un nuevo punto de falla, porque quita una dependencia.
- El chequeo ya no necesita una credencial de un servicio externo.

Algo a tener en cuenta: los datos de zonas horarias vienen dentro de la versión de Node de la imagen. La imagen actual (`node:20.20`) trae la versión 2025c, que ya incluye el cambio de Paraguay. Un cambio de reglas posterior a esa versión solo aparecería al reconstruir la imagen con una versión más nueva. Los cambios reales de horario de Chile y Paraguay seguirían generando aviso, como corresponde.

Si les parece bien, preparo el cambio para que lo revisen. Más información: [GITIN-2194](https://smartit-ar.atlassian.net/browse/GITIN-2194)

Saludos,
Dante
