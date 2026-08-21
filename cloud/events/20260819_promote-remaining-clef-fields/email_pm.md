**Asunto:** Estado GITIN-1892 — Campos adicionales de logs de aplicación en Graylog

Hola,

Te comparto el estado de GITIN-1892, el ticket relacionado a mejorar la búsqueda de logs de las aplicaciones de SmartFran Cloud en Graylog (la herramienta interna de monitoreo de logs). Es continuación de un ticket anterior ya cerrado (GITIN-1883), que resolvió el mismo problema para otro grupo de campos.

Hoy, varios datos técnicos de cada log de aplicación (por ejemplo: identificador de usuario, tipo de proceso, categoría del evento, código de error, resultado de auditoría de seguridad, entre otros) ya se están registrando, pero no se pueden buscar ni filtrar de forma individual — quedan agrupados dentro de un bloque de texto más grande. El objetivo de este ticket es habilitar esos campos como buscables por separado.

En total son 12 los campos en alcance:

- UserId
- Component
- ProcessType
- Category
- ErrorCode
- Operation
- Recovered
- Handled
- AuditAction
- AuditOutcome
- RequestId
- SourceContext

El trabajo está en curso: se está confirmando el comportamiento real de cada campo sobre datos de producción antes de aplicar el cambio al pipeline de logs.

No hay impacto en la disponibilidad de las aplicaciones ni en los datos ya almacenados — es una mejora de visibilidad y búsqueda sobre información que ya se registra hoy.

Más información en el ticket GITIN-1892.

Saludos,
Dante
