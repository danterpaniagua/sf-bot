# Email (PM) — GITIN-2228: Graylog SmartCloud, retención de logs

**Asunto:** Graylog SmartCloud — alertas de lentitud del almacenamiento y decisión sobre retención de logs

Hola,

Desde el 15/10 el almacenamiento de logs de Graylog SmartCloud dispara alertas de lentitud varias veces por día. Todavía no está confirmada la causa. No vi señales de que se alcancen los límites de Azure; la lentitud coincide muchas veces con lecturas grandes de datos, aunque también la vi con poca carga; y las búsquedas no tenían ningún límite de tiempo. Ya configuré un máximo de 60 segundos y de 15 días por búsqueda; verifiqué que quedó guardado, pero no he visto todavía su efecto en las alertas.

Además, el espacio se está llenando, porque se guardan 30 a 40 días de todos los niveles de log. En los 8 servicios, el 64 % de los registros son de nivel Information con más de 7 días. Propongo conservar Information y Unknown 7 días y Warning o superior 30 días. Con menos datos guardados, las búsquedas deberían ser más livianas: en una medición de referencia, la primera búsqueda de 15 días de Information tardó entre 12 y 36 segundos, y la de Warning o Error entre 2,7 y 3,7 segundos; habría que repetirla después del cambio para ver cuánto mejora. Los logs de Warning o superior quedarían conservados al menos 30 días (las búsquedas desde Graylog llegarían hasta 15 días atrás). Hay dos formas de hacerlo:

- **A — reorganizar Graylog por nivel.** Es más prolija, pero agrega configuración nueva y obliga a rehacer dashboards; el espacio se libera de a poco.
- **B — una limpieza diaria que borra los Information de más de 7 días.** No cambia la estructura de Graylog. La primera pasada es grande, así que la haría escalonada, fuera de horas pico y con control.

En ambas opciones el borrado de los logs Information viejos es definitivo. Recomiendo **B**: el uso de Graylog es bajo (adopción temprana) y evita rediseñar lo que todavía está cambiando.

Para avanzar necesito que me confirmen si 7 días para los logs Information y Unknown (sin nivel) es adecuado, y que puedo borrar esos registros.

Más información: [GITIN-2228](https://smartit-ar.atlassian.net/browse/GITIN-2228)

Saludos
