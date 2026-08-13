# Eventos — 20260729_graylog_sin_datos

## 2026-07-29 — Inicio de la investigación

He recibido el reporte de que Graylog no está recibiendo datos desde las 2am del 29/07. He creado el archivo de investigación y he identificado que el host `smartfran-graylog-pro` corresponde a la instancia de Graylog dedicada a SmartCloud, distinta del stack Docker que sirve a SmartPedidos y SmartLoyalty.

## 2026-07-29 — Verificación de estado de VM y descarte de causa en App Services

**Comando:** C1 — Estado de VM / VM Agent
**Resultado:**
VM running, VM Agent Ready.

He confirmado que la VM está activa y saludable, descartando una caída de infraestructura como causa. He verificado además que no existen claves de configuración de logging (`Logging`, `ASPNETCORE_ENVIRONMENT`) en los App Settings de Business ni de Sales, y que el Activity Log de Azure no registra ningún evento relevante en la ventana investigada.

## 2026-07-29 — Corrección del alcance del reporte original

He recibido la corrección de que el problema no es una caída total sino una reducción del volumen de mensajes, y que el inicio real fue el 28/07 y no el 29/07 como se había reportado inicialmente.

## 2026-07-29/30 — Medición del volumen real vía Graylog REST API

**Comando:** C21, C25 — Búsqueda Views API, conteo de mensajes por hora y por stream (48h)
**Resultado:**
Business: 667.074 msgs/hora a las 02:00 ART del 28/07, caída a 22.488 msgs/hora a las 03:00 ART (-96,6%). Sales: 33.038 a 2.656 msgs/hora en el mismo lapso (-92%). Default Stream: 0 mensajes en toda la ventana.

He confirmado una caída sincronizada de volumen en ambos streams (Business y Sales), iniciada exactamente a las 2026-07-28 03:00 ART (06:00 UTC), sostenida sin recuperación durante más de 46 horas.

## 2026-07-30 — Descarte de Event Hub y App Configuration como causa

**Comando:** C24 — Métricas de Event Hub; C29-C33 — Auditoría de App Configuration
**Resultado:**
Event Hub mantiene cadencia de batches estable antes y después del cliff. App Configuration no contiene ninguna clave relacionada a logging/telemetry/sampling.

He descartado tanto el Event Hub como el App Configuration compartido como origen del cambio de volumen.

## 2026-07-30 — Hallazgo de fallas de indexado activas

**Comando:** C34-C36 — Conteo y detalle de fallas de indexado
**Resultado:**
62.876 fallas desde el momento exacto del cliff (06:00 UTC 28/07), 0 fallas en las 24h previas. Error: término inmenso en campo `event_original`, hasta 131KB, en índice `business__6`.

He identificado un problema activo y en curso de pérdida de datos por fallas de indexado, coincidente en el tiempo con la caída de volumen pero con causa técnica propia.

## 2026-07-30 — Confirmación del restart de Logstash y verificación del fix de 2026-07-02

**Comando:** C37-C39 — `az vm run-command` (systemctl status, journalctl, grep sobre config de Logstash)
**Resultado:**
Logstash reiniciado a las 2026-07-28 06:06:40 UTC. El fix del 2026-07-02 (`event_original` limitado a un único registro) sigue presente y correcto en la configuración activa.

He confirmado que el restart de Logstash coincide casi exactamente con el cliff de volumen, y he descartado que las fallas de indexado se deban a una reversión del fix — la causa es que registros individuales de Business superan por sí solos el límite de Lucene, consistente con `EnableSensitiveDataLogging(true)` hardcodeado en producción.

## 2026-07-30 — Cierre de la investigación y creación del ticket

He convergido el análisis y he creado el ticket (`_ops.md`) con dos hallazgos principales pendientes de confirmación: la causa exacta del restart de Logstash, y la confirmación por parte de desarrollo de si hubo un cambio intencional de verbosidad de logging.

## 2026-07-30 — Envío de comunicaciones y cierre del lado de Operaciones

He enviado un email al equipo de PMs informando la reducción de volumen en términos de negocio, y un email al equipo de desarrollo de CLOUD solicitando confirmación sobre el cambio de logging detectado el 28/07 a las 3:00 am y sobre el uso de `EnableSensitiveDataLogging` en producción. Con esto cierro el lado de Operaciones de esta investigación — el punto pendiente (causa raíz exacta del cambio de verbosidad) queda en manos del equipo de desarrollo de CLOUD.
