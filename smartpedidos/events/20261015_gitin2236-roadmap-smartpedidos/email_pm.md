**Asunto:** Roadmap de Operaciones / SRE para SmartPedidos (borrador para revisar)

Hola,

Te comparto el borrador del roadmap de SmartPedidos que pediste, para que lo revisemos juntos. El detalle completo, con las tareas de cada Story, está en [GITIN-2236](https://smartit-ar.atlassian.net/browse/GITIN-2236).

**Cómo está armado**
- Son 12 Stories, cada una con sus tareas. Para cada una indico por qué hace falta, a qué proyecto pertenece (Platform, Concentrador o infraestructura), si necesita al equipo de desarrollo, qué tickets existen ya y una prioridad propuesta según criticidad y esfuerzo.
- En las tareas de logs, si el cambio no toca código de negocio, se puede hacer sin desarrollo.
- Donde no encontré un ticket, figura "No hay ticket aún".
- Cada Story incluye una estimación de tiempo de trabajo de SRE (en días de una persona, no fechas de entrega). El tiempo de desarrollo lo debe estimar el equipo de desarrollo donde se indica. Los tiempos se tomaron de proyectos anteriores y las alertas y tareas del día a día pausan el trabajo, por lo que los plazos reales pueden ser mayores.

**Stories, con la prioridad propuesta (criticidad / esfuerzo)**
1. Mejoras de despliegue: credenciales por usuario, ambientes, Docker, README del ambiente local y un rol por ambiente (Alta / Alta).
2. AWS WAF: reunir los accesos no autorizados de los últimos meses y habilitar reglas sin afectar el funcionamiento actual (Alta / Media).
3. Credenciales en código: migrarlas a un servicio de AWS y rotarlas, incluidas las claves de sal (Alta / Alta).
4. Escalado de Platform con varios umbrales; hoy se escala en un solo nivel (Alta / Media).
5. Revisión de logs: faltan logs FATAL en Concentrador y hay defectos en el código de registro (Alta / Baja).
6. Contratos entre SmartPedidos y SRE para logs y para consultas a la base (Media / Media).
7. Nuevas alertas en Zabbix a partir de Graylog; la de FATAL de Platform ya está creada (Media / Baja).
8. Graylog en los ambientes de desarrollo (Baja / Media).
9. Refactor del controlador de sucursales de Concentrador (Media / Alta).
10. Fallas silenciosas en el proceso que rechaza pedidos pendientes (Alta / Baja).
11. Deuda de logging en Platform (Baja a media / Media).
12. Gestión de la deuda técnica: mantener el registro al día y asignar tickets (Media / Baja).

**Qué necesito de tu parte**
- Revisar si el alcance es el que esperabas (hoy cubre trabajo de Operaciones / SRE y la deuda técnica que identificamos, no funcionalidades de producto).
- Confirmar o ajustar las prioridades.
- Decir si falta algún tema. Por ahora no encontré evidencia para incluir respaldos y recuperación ante desastres ni un proceso de guardias, y pueden sumarse si los consideran necesarios.

Todo lo marcado como propuesta está sujeto a esa revisión.

Saludos,
Dante
