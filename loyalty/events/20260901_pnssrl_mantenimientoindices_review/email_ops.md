Asunto: PNSSRL_MantenimientoIndices — bloqueo diario confirmado y horario propuesto

Hola,

Les comparto el estado de [GITIN-1981](https://smartit-ar.atlassian.net/browse/GITIN-1981).

**Detectado**

El job de SQL Agent `PNSSRL_MantenimientoIndices` corre todos los días a las 06:15 UTC (03:15 UTC-3) y reconstruye índices de forma offline sobre varias tablas, entre ellas `CustomerPointsLog`. Mientras dura la reconstrucción, cualquier consulta que necesite acceder a esa tabla queda en espera — esto bloquea tanto a MobileAppService como al chequeo de monitoreo de Zabbix sobre la misma tabla. Se confirmó hasta 38 sesiones bloqueadas en simultáneo en un solo pico. La duración del job es variable, entre ~2 y ~6 horas según el día.

**Horario propuesto: 08:00 UTC (05:00 UTC-3)**

Para definir el horario se cruzaron todas las restricciones conocidas del entorno:
- Horario de actividad de los terminales POS (10:00 a 02:00 UTC-3 del día siguiente).
- Backup completo semanal (domingo/lunes/miércoles, 06:00 UTC).
- Pico de tráfico propio de MobileAppService (07:00-08:00 UTC).
- El resto de las tareas automáticas y ETLs programados sobre la misma base (reportes, exportaciones, sincronizaciones) — se revisó cuáles de ellas tocan la misma tabla y en qué horario, para asegurarse de no mover el problema a otro proceso.

08:00 UTC es el único horario que queda libre de las tres primeras restricciones, y donde el resto de las tareas automáticas que sí coinciden solo generan demoras breves (segundos, no bloqueo sostenido) — no el tipo de bloqueo en vivo que afecta hoy a MobileAppService.

**Pendiente**

El cambio de horario está preparado pero no aplicado todavía — falta la aprobación final antes de correrlo contra producción.

Saludos.
