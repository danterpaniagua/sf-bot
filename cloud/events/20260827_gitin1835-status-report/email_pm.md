**Asunto:** Estado del proyecto — Incorporación de servicios de SmartFran Cloud a Graylog (GITIN-1835)

Hola equipo,

Les comparto el estado del proyecto de incorporación de servicios de SmartFran Cloud a la
plataforma de observabilidad (Graylog), ticket GITIN-1835 y sus subtareas.

**Objetivo del proyecto:** centralizar los registros (logs) de los distintos servicios de SmartFran
Cloud en una única plataforma de monitoreo, con información estructurada y fácil de buscar, para
agilizar el diagnóstico de incidentes.

**Resumen por servicio:**

| Servicio | Estado |
|---|---|
| Business | Incorporado a Graylog, con información estandarizada y registros HTTP habilitados |
| Admin | Incorporado a Graylog, con información estandarizada y registros HTTP habilitados |
| Platform | Incorporado a Graylog, con información estandarizada y registros HTTP habilitados |
| Person | Incorporado a Graylog, con información estandarizada y registros HTTP habilitados |
| Catalog | Incorporado a Graylog, con información estandarizada y registros HTTP habilitados |
| Orders | Incorporado a Graylog, con información estandarizada y registros HTTP habilitados |
| Sales | Incorporado a Graylog mediante un mecanismo alternativo (limitación técnica de la plataforma en Windows); se corrigió una duplicación de mensajes detectada |
| Pos | Incorporado a Graylog mediante un mecanismo alternativo (limitación técnica de la plataforma en Windows); se corrigió una duplicación de mensajes detectada |
| Function Apps | 10 incorporadas en total; 3 configuradas pero pendientes de un cambio de código (equipo de desarrollo) para poder enviar datos utilizables |
| Dashboard de observabilidad | Completado — cuatro vistas iniciales disponibles |
| Normalización del campo "servicio" | En backlog, pendiente de priorización |

**Trabajo completado:**
- Ajuste del volumen de información enviada, reduciendo el ruido sin perder visibilidad clave.
- Estandarización de 23 campos de información (identificador de transacción, nivel de severidad,
  identificador de cliente, servicio, entorno, entre otros) de forma uniforme en todos los
  servicios — permite buscarlos y filtrarlos directamente en Graylog sin revisar el contenido
  completo de cada registro.
- Incorporación de los servicios web de la plataforma: 16 aplicaciones en total (8 servicios, en
  sus versiones de producción y desarrollo).
- Incorporación de registros de solicitudes HTTP para todos los servicios web, con una
  organización dedicada para evitar saturar los registros existentes.
- Corrección de dos problemas de duplicación de mensajes detectados durante el proceso (un mismo
  evento apareciendo más de una vez en la plataforma).
- Revisión de mensajes sin servicio identificado: la gran mayoría corresponde a comportamiento
  esperado (registros técnicos internos del framework); se identificó un caso puntual
  (notificaciones de billetera virtual) que podría beneficiarse de una mejora, pendiente de
  decisión.

**Ampliación de alcance — Function Apps:** el proyecto se amplió para incluir también las Function
Apps (un tipo de servicio distinto a las aplicaciones web, con configuración propia). Se
incorporaron 10 Function Apps en total. De estas, las 3 más recientes están correctamente
configuradas del lado de infraestructura, pero aún no envían información utilizable a Graylog: el
motivo identificado es que el código de esas aplicaciones no está preparado para emitir registros
en el formato que la plataforma espera, algo que requiere una modificación de código, no de
configuración. Estamos coordinando este punto con el equipo de desarrollo.

**Hallazgo de proceso:** durante el trabajo, detectamos que la configuración real de algunos
servicios en Azure no coincidía con lo definido en nuestro código de infraestructura — es decir,
la configuración había sido modificada manualmente por fuera del proceso normal. Esto fue
identificado y corregido.

**Dashboard de observabilidad:** se creó un nuevo dashboard en Graylog con cuatro vistas
iniciales — volumen de registros por servicio a lo largo del tiempo, distribución por ambiente,
principales clientes por volumen de actividad, y un cruce por módulo de negocio y ambiente. Esto
permite ver de un vistazo el estado general de los servicios sin necesidad de armar búsquedas
manuales. Quedan planteadas, como una segunda etapa, vistas adicionales sobre tasa de errores.

**En backlog:** normalización del campo "servicio" en los registros — actualmente un mismo servicio
puede aparecer identificado de dos formas distintas (nombre corto y nombre completo), lo que
dificulta filtrar de manera consistente. Queda pendiente de priorización.

Para más información, los tickets de referencia son: GITIN-1882, GITIN-1883, GITIN-1892,
GITIN-1901, GITIN-1905, GITIN-1908, GITIN-1914, GITIN-1924, GITIN-1930, GITIN-1932, GITIN-1933,
GITIN-1937 y GITIN-1946 (todas subtareas de GITIN-1835).

Saludos,
Dante
