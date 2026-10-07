**Asunto:** GITIN-1946 — Function Apps SFC-*-PRO no emiten datos compatibles con el pipeline de Graylog (bloqueo de código, no de infraestructura)

Hola equipo,

Les comparto un hallazgo sobre GITIN-1946 (incorporación de las Function Apps
`SFC-CodeGenerator-PRO`, `SFC-ScheduledJobs-PRO` y `SFC-TicketProcessAsync-PRO` a Graylog).

La configuración de infraestructura (Diagnostic Settings) está completa y correcta en las tres apps.
Los datos aún no son visibles en Graylog.

Confirmamos que esto no se debe a falta de actividad: las tres apps reciben tráfico real (de decenas
a cientos de ejecuciones por hora, según métricas de Azure) y efectivamente generan logs — lo
verificamos capturando la salida en vivo de una de ellas mientras procesaba tráfico de producción.

El bloqueo real es de código de aplicación: las tres apps registran sus logs a través del logger por
defecto del host de Azure Functions, no a través del pipeline de Serilog (formato CLEF) que el resto
de los servicios ya usa y que nuestra integración con Graylog está preparada para interpretar. Como
resultado, los mensajes que sí se generan tienen un formato que nuestro pipeline actual no puede
procesar, y no llegan a Graylog ni siquiera en forma cruda.

Para que estas tres apps puedan reportar a Graylog, sería necesario alinear su logging al mismo
mecanismo (Serilog/CLEF) que ya usan las APIs y otras Function Apps del proyecto. Quedamos a
disposición para coordinar el detalle técnico con quien tome esta tarea del lado de desarrollo.

Para más información, el ticket de referencia es GITIN-1946.

Saludos,
Dante
