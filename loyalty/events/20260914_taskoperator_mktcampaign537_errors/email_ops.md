Asunto: TaskOperatorService — timeouts diarios por mantenimiento de índices sin optimizar (GITIN-2036)

Hola,

Les comparto el estado de [GITIN-2036](https://smartit-ar.atlassian.net/browse/GITIN-2036), relacionado con [GITIN-1981](https://smartit-ar.atlassian.net/browse/GITIN-1981).

**Qué detectamos**

- El job `MktAsignationPointActionManager` de TaskOperatorService (asignación de puntos de la campaña de nuevos clientes de Paraguay) viene registrando errores `Execution Timeout Expired` todos los días en la misma franja horaria temprana, desde hace al menos una semana — no es un evento aislado. La causa es bloqueo de sesión: mientras `PNSSRL_MantenimientoIndices` reconstruye el índice `IX_CustomerId` de `CustomerPointsLog`, cualquier otra sesión que necesite esa tabla queda en cola. Es el mismo mecanismo de bloqueo ya reportado en GITIN-1981 contra MobileAppService — TaskOperatorService es una segunda víctima confirmada.
- El mantenimiento de `IX_CustomerId` no está optimizado: reconstruye el índice completo (~397 millones de filas) todas las noches, cuando la tabla ya está particionada por año y solo la partición del año en curso (~51 millones de filas) tiene datos activos. Esto explica la mayor parte de la duración diaria del job — hasta 3 horas adicionales solo por este índice, con duración además muy variable noche a noche.
- Las campañas de este tipo (`MktAsignationPointActionManager`) corren las 24 horas, los 7 días, sin ninguna ventana de baja actividad — confirmado como comportamiento estándar de este tipo de job, no específico de esta campaña. Esto significa que reprogramar únicamente el horario del mantenimiento de índices no alcanza para resolver este síntoma puntual: reubicaría el bloqueo a otro tramo del día en vez de eliminarlo.
- El bloqueo no es específico de esta campaña: encontramos una segunda víctima independiente, `EtlDwGridoCustomerPointsLogProcessor` (el feed diario que alimenta el data warehouse). Corre todos los días dentro de la misma ventana y viene tardando entre 2 y 5 horas en completar (contra lo esperable para este tipo de paso), con una falla completa el 2026-09-09. Cualquier proceso que necesite acceder a `CustomerPointsLog` durante el mantenimiento queda expuesto al mismo problema.

**Qué proponemos**

- Acotar el rebuild de `IX_CustomerId` a la partición activa del año en curso, en vez de a toda la tabla — reduciría de forma significativa la duración de este paso y, con eso, la ventana de bloqueo.
- Para aplicarlo: excluir `CustomerPointsLog` del barrido diario actual y crear un paso nuevo y separado, con su propio horario real, que ejecute el rebuild acotado — no alcanza con un script manual suelto, necesita quedar como job recurrente.
- Mantener además la reprogramación de horario ya preparada en GITIN-1981 (mover `PNSSRL_MantenimientoIndices` de 06:15 UTC a 08:00 UTC) — sigue siendo válida para los otros afectados (MobileAppService, terminales POS, Zabbix), que sí tienen horarios reales de baja actividad. Es una corrección independiente de la de este ticket, no un reemplazo.
- Antes de aplicar el cambio en `IX_CustomerId` en producción, probarlo en un entorno de no-producción si existe uno disponible, o como mínimo aplicarlo primero bajo monitoreo cercano.
- Encontramos una alternativa adicional, más simple técnicamente: el job de campaña tiene su propio intervalo configurable (hoy cada 5 minutos). Ampliarlo no elimina la colisión, pero reduce mucho cuántas veces por día intenta acceder a la tabla durante el mantenimiento. No es una decisión solo técnica — afecta la velocidad de acreditación de puntos a los socios de la campaña, así que la vemos como algo a validar con quien sea dueño del motor de campañas, en paralelo al resto, no en su reemplazo.

**Riesgos**

- El comportamiento exacto de la tabla que controla el barrido diario está inferido a partir de su estructura, no confirmado contra la lógica real del procedimiento que lo ejecuta (está encriptado y no se puede leer directamente) — por eso recomendamos monitorear de cerca la primera vez que se aplique, no dejarlo desatendido desde el día uno.
- El rebuild acotado a la partición activa reduce la ventana de bloqueo, pero no la elimina por completo — sigue siendo una operación que retiene el mismo tipo de bloqueo mientras corre, solo que por mucho menos tiempo.
- El riesgo más importante es de secuencia: si se excluye `CustomerPointsLog` del barrido diario actual sin dejar funcionando el paso de reemplazo como job recurrente real, el índice quedaría sin ningún mantenimiento — peor que la situación actual. Por eso ambas partes del cambio tienen que aplicarse juntas, no una sin la otra.
- El cambio no fue probado todavía en un entorno de no-producción.
- Buena noticia sobre el problema actual: confirmamos contra el código real que ninguna falla genera pérdida ni duplicación de puntos para los socios — el diseño ya contempla esto y simplemente demora la acreditación hasta la próxima corrida exitosa. El impacto hoy es de tiempo, no de datos.

**Plan de reversión**

- La exclusión de `CustomerPointsLog` del barrido diario es un cambio de configuración simple y reversible en cualquier momento, sin tocar datos.
- El rebuild acotado en sí no necesita un paso de reversión propio: si se interrumpe a mitad de camino, el motor de base de datos revierte esa operación de forma limpia, sin riesgo de corrupción ni pérdida de datos.
- Si algo no se comporta como esperamos, alcanza con revertir el cambio de configuración para volver al comportamiento actual del job.

Detalle técnico completo (las sentencias exactas, no incluidas acá) en el ticket.

**Pendiente**

Ninguna de las tres correcciones está aplicada todavía. Quedo atento si necesitan que sume algo más desde el lado de TaskOperatorService antes de coordinar la aplicación.

Saludos.
