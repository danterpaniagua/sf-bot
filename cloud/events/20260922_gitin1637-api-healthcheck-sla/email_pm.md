Asunto: Seguridad del healthcheck de las APIs — GITIN-1637

Hola,

Les comparto mi propuesta de seguridad para el healthcheck que estamos diseñando en las APIs de SmartFran Cloud.

El endpoint puede exponer, en la misma respuesta, tanto señales de escalado (CPU, RAM, cola de requests) como señales de salud por franquicia (conexión a base de datos, tiempos de respuesta). Por eso necesita estar restringido a un puñado de consumidores legítimos — no puede quedar abierto sin control, porque alguien con acceso podría usarlo para obtener información operativa que no debería ser pública, o para forzar carga sobre el sistema.

Tres mecanismos de protección habituales fueron propuestos y rechazados previamente para este caso puntual: autenticación de usuario (Auth0), autenticación por token (Token Based), y límite de tasa de pedidos (rate-limit) por sí solo. A esto se suma algo que sí confirmamos nosotros: tampoco es posible resolverlo restringiendo el acceso a nivel de rol dentro de la nube, porque esa plataforma no permite otorgar permisos sobre un endpoint específico dentro de una aplicación.

La alternativa que identificamos como viable es una regla de seguridad a nivel de firewall de aplicaciones web, que limite qué orígenes pueden llegar a este endpoint puntual — actúa antes de que el pedido llegue a la aplicación, sin depender de autenticación de usuario. **Hoy no existe este tipo de firewall delante de las APIs de SmartFran Cloud** — es una propuesta de incorporación, no una regla nueva sobre algo que ya está funcionando. El costo mensual de incorporarlo ya fue estimado en otro ticket relacionado (GITIN-2042), proyectado sobre distintos escenarios de crecimiento de franquicias — referencia directa para evaluar el esfuerzo de avanzar.

Por separado, pero relacionado a la confiabilidad de estas mismas instancias: también es muy importante aplicar un apagado ordenado (Nice Shutdown) en las instancias, para evitar pérdida de datos durante un escalado o un despliegue.

Para más información: [GITIN-1637](https://smartit-ar.atlassian.net/browse/GITIN-1637)
Estimación de costo del firewall: [GITIN-2042](https://smartit-ar.atlassian.net/browse/GITIN-2042)

Saludos,
