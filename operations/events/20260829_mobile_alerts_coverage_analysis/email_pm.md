**Asunto:** Estado del proyecto — Mejora de alertas y balanceo de tráfico en MobileAppService (GITIN-1965)

Hola equipo,

Les comparto el estado del proyecto de revisión y mejora de las alertas y la infraestructura de tráfico de MobileAppService (la aplicación que da soporte a las operaciones móviles de los locales), ticket GITIN-1965 y sus subtareas.

**Objetivo del proyecto:** asegurar que el sistema de monitoreo detecte a tiempo situaciones de tráfico anómalo o degradación de servicio en MobileAppService, y revisar que la infraestructura que distribuye el tráfico entre los servidores esté correctamente configurada.

**Resumen por subtarea:**

| Subtarea | Estado |
|---|---|
| Línea base de tráfico y análisis de alertas (GITIN-1969) | Completado. Se estableció una referencia histórica de tráfico normal y se corrigió una inconsistencia en la retención de datos históricos de dos servidores |
| Auditoría de alertas a nivel de toda la flota de servicios (GITIN-1966) | En progreso. Se relevaron todas las alertas de tráfico configuradas y se identificaron mejoras de consistencia entre servidores, pendiente de definición final |
| Revisión de configuración del balanceador de carga (GITIN-1967) | En progreso |

**Trabajo completado:**
- Se construyó una referencia de tráfico normal por fin de semana para los dos servidores de MobileAppService, actualizable automáticamente, que permite comparar cualquier fin de semana futuro contra el comportamiento habitual sin necesidad de rehacer el análisis desde cero.
- Se identificó un evento de tráfico elevado en uno de los dos servidores durante el fin de semana del 29 y 30 de agosto, concentrado en un lapso puntual de aproximadamente una hora el sábado por la tarde. El origen de negocio de ese pico (por ejemplo, si correspondió a alguna campaña o lanzamiento puntual) no pudo confirmarse ni descartarse con la información disponible — solo se confirmó el aumento de tráfico en sí.
- Se corrigió una inconsistencia de configuración: dos de las métricas monitoreadas (uso de procesador y memoria) en ambos servidores retenían mucho menos historial que las demás, lo que limitaba la posibilidad de hacer comparaciones históricas confiables. Quedó alineado con el resto.
- Se relevaron todas las alertas de tráfico configuradas en la flota completa de servidores monitoreados y se identificaron casos donde distintos servidores similares tienen esquemas de alerta no coordinados entre sí — trabajo de consolidación en curso, sin impacto en el servicio.

**Hallazgo relevante:** se confirmó que, en un evento anterior ya cerrado, una alerta configurada de forma demasiado sensible permitió que tráfico real llegara a un servidor antes de que estuviera completamente listo para atenderlo, generando errores breves para los usuarios. La revisión en curso (GITIN-1967) busca corregir esa configuración de forma preventiva.

**Próximos pasos:**
- Confirmar si el pico de tráfico observado corresponde a un evento de negocio conocido, para poder documentarlo como referencia hacia adelante.
- Completar la revisión de la configuración del balanceador de carga y aplicar el ajuste preventivo mencionado arriba.

Para más información, los tickets de referencia son: GITIN-1966, GITIN-1967 y GITIN-1969 (subtareas de GITIN-1965).

Saludos,
Dante
