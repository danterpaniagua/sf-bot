Asunto: Incidente en Platform — resuelto

Hola,

Les cuento sobre un incidente que tuvimos el 05/08 en Platform.

El 05/08, entre aproximadamente las 16:30 y las 18:00 (hora local), PediGrido tuvo una degradación en su propio servicio: sus respuestas tardaron hasta más de dos minutos, y varias devolvieron errores de su lado. Durante esa misma ventana, registramos reinicios automáticos repetidos en Platform.

Aumentamos temporalmente la capacidad de los servidores afectados durante el incidente (escalamos hacia arriba). Los reinicios automáticos se detuvieron después de ese aumento de capacidad. Al día siguiente, una vez confirmado que ya no era necesaria esa capacidad adicional, la redujimos nuevamente a su nivel original (escalamos hacia abajo).

Reconfiguramos el mecanismo que disparaba esos reinicios automáticos, para que no dependa de la carga del proceso.

No tenemos confirmación de que PediGrido haya resuelto el problema de fondo de su lado, así que seguimos atentos por si se repite.

Para más información, el detalle completo está en el ticket GITIN-1783.

Saludos,
Dante
