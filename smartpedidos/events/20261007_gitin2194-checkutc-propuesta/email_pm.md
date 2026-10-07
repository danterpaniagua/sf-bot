# Email a PMs — GITIN-2194

**Asunto:** Propuesta para reducir avisos innecesarios de zona horaria en el Concentrador

Hola,

Estuve viendo los avisos que parecen falsos positivos del correo "Concentrador: informacion cambios UTC en entorno production". Por ejemplo, en uno de ellos el servicio externo informaba para Chile una hora distinta de la configurada en SmartPedidos, mientras que la información de zonas horarias de nuestra propia plataforma coincidía con lo configurado. Todavía no pudimos confirmar si ese aviso fue un error del servicio externo o un cambio de horario legítimo.

Cómo funciona hoy: una vez por día, y también cada vez que el servicio se inicia en producción, el Concentrador consulta un servicio externo de zonas horarias para cinco países y compara el resultado con la hora configurada en SmartPedidos. Si encuentra una diferencia, envía el correo.

Les propongo calcular la hora esperada de cada país con la información de zonas horarias que ya incluye la plataforma, sin consultar ningún servicio externo. La comparación con lo configurado, la frecuencia del control y el correo quedarían igual, y seguiríamos recibiendo aviso ante cambios reales de horario, por ejemplo de verano en Chile o Paraguay.

Qué mejora:
- Un servicio externo menos del que depender.
- Menos avisos que no corresponden a un cambio real.
- Un control local e inmediato.
- No agrega un nuevo punto de falla, porque quita una dependencia.
- No se necesitan credenciales para esta consulta.

Para tener en cuenta: la información de zonas horarias se actualiza cuando se reconstruye la plataforma con una versión más nueva. Si un país cambiara sus reglas de horario, el aviso llegaría cuando la plataforma incorpore esa actualización.

Más información: [GITIN-2194](https://smartit-ar.atlassian.net/browse/GITIN-2194)

Saludos,
Dante
