**Asunto:** Caída de ~96% en el volumen de logs de Business/Sales — necesitamos confirmación del equipo de desarrollo

Hola equipo,

Les escribo por un hallazgo del evento `20260729_graylog_sin_datos` (carpeta `operations/events/20260729_graylog_sin_datos/`): desde el 28 de julio a las 3:00 am (hora local), el volumen de logs que Graylog recibe de Business y Sales cayó de forma sincronizada y sostenida en aproximadamente un 96%, sin recuperación hasta el momento.

Desde infraestructura descartamos varias causas: la VM de Graylog está saludable, el clúster de OpenSearch no está degradado, el Event Hub mantiene un flujo de batches estable antes y después del cambio, no hay eventos relevantes en Activity Log ni cambios en App Configuration en esa ventana horaria, y no encontramos ningún deploy registrado a esa hora.

Lo único que encontramos coincidiendo casi exactamente con el momento del cambio es un restart del servicio Logstash en el host de Graylog, a las 06:06:40 UTC. No pudimos determinar desde infraestructura si ese restart fue la causa o solo una coincidencia temporal.

En paralelo, detectamos fallas activas de indexado en el mismo período: documentos individuales de Business superan el límite de tamaño de término de OpenSearch. Esto parece estar relacionado con `EnableSensitiveDataLogging` habilitado sin condición de entorno en producción en Business, que registra valores completos de parámetros SQL en cada consulta.

Les pedimos que puedan revisar y confirmarnos:

- ¿Hubo algún cambio de nivel de logging (por ejemplo en `Microsoft.EntityFrameworkCore` u otra categoría) en Business o Sales alrededor de esa fecha y hora?
- Si lo hubo, ¿fue intencional? ¿Corresponde a la implementación de logs en curso o a la nueva ingesta que se venía evaluando?
- ¿Tiene sentido para ustedes revisar si `EnableSensitiveDataLogging` sigue siendo necesario en producción, dado que expone valores de parámetros y está generando las fallas de indexado mencionadas?

Cualquier información que puedan aportar nos ayuda a cerrar la causa raíz de este evento.

Quedamos a disposición para lo que necesiten. Gracias.
