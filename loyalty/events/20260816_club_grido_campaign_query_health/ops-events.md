# Eventos — 20260816_club_grido_campaign_query_health

## 2026-08-18 08:40 — Inicio de investigación

Abrí la investigación a partir del reporte de una campaña masiva de marketing de Club Grido el domingo 2026-08-16, con pico reportado de 80 req/s POST y 100 req/s GET. Convertí la ventana solicitada (12:00–17:00 UTC-3) a GMT (15:00–20:00 UTC) y confirmé que el servicio afectado por la campaña es MobileAppService (`SFCG-MOBI-01/02`). Obtuve la URL del ticket Jira GITIN-1866.

## 2026-08-18 08:45 — Disponibilidad de datos confirmada

Ejecuté Q1 sobre `PNSSRL_AuditSysprocesses`: confirmé 60 snapshots entre 15:01:00 y 19:56:01 UTC, cadencia de ~5 minutos, cobertura completa de la ventana 15:00–20:00 UTC.

## 2026-08-18 08:46 — Delta de CPU por SPID

Ejecuté Q2 (top 50 por delta de CPU). Confirmé `blocked = 0` en todas las filas del top 50. Los mayores consumidores individuales fueron sesiones de `SFCG-WSIT-01` y `SFCG-WEBS-02/03`, no de MobileAppService.

## 2026-08-18 08:47 — Desglose por host y verificación de bloqueos

Ejecuté Q3 (desglose de CPU por host) y Q4 (verificación de bloqueos, 0 filas). Confirmé que `SFCG-WSV2-01` (WebServiceV2) fue el mayor consumidor de CPU de la ventana (306.890ms, ~mitad del total), mientras que MobileAppService (`SFCG-MOBI-01/02`) tuvo el mayor volumen de conexiones/sesiones pero CPU marginal (14.185ms, 2.4% del total).

## 2026-08-18 08:48 — Cruce con datos de Graylog (primera muestra)

Recibí conteo de hits por endpoint desde Graylog (solo respuestas OK) para la ventana original. Confirmé tiempos de respuesta saludables (menores a 100ms en promedio) en los endpoints de mayor volumen, consistente con el bajo costo de CPU medido para MobileAppService.

## 2026-08-18 08:49 — Identificación de Query077 vía TempdbProc

Ejecuté Q5 sobre `PNSSRL_TempdbProc`. Identifiqué que `SFCG-CLUB-01` ejecutó repetidamente Query077 (`AvailablePromotion`), explicando la totalidad de su consumo de CPU en la ventana. El consumidor dominante (`SFCG-WSV2-01`) no apareció en el top 20 de `TempdbProc` — sin huella en tempdb, su query queda sin identificar con las tablas de captura disponibles.

## 2026-08-18 08:51 — Corrección de ventana de pico real

Recibí una segunda tabla de Graylog que mostró mayor volumen de tráfico en la ventana 16:00–21:00 UTC, distinta a la ventana 15:00–20:00 UTC originalmente calculada. Detecté un hueco de cobertura en la hora 20:00–21:00 UTC.

## 2026-08-18 08:58 — Cierre de cobertura de la hora faltante

Ejecuté Q6 sobre la ventana 20:00–21:00 UTC (disponibilidad, bloqueos, desglose por host). Confirmé 12 snapshots sin huecos, cero bloqueos, y CPU de MobileAppService nuevamente marginal (327ms en `MOBI-02`, 0ms en `MOBI-01`). Cobertura completa de la ventana real de pico (16:00–21:00 UTC) confirmada.

## 2026-08-18 09:05 — Análisis de logs IIS crudos

Recibí y procesé la exportación cruda de logs IIS de Graylog (302.748 filas, `SFCG-MOBI-01/02`, ventana 15:25–20:55 UTC). Detecté una tasa sostenida de respuestas 400 (21.7% del tráfico total, hasta 66.5% en `SaveNewMember`), presente desde el inicio de la ventana y no vinculada a un pico puntual — hallazgo no visible desde el lado de base de datos. Detecté también un evento aislado de degradación de latencia y el único error 500 de todo el dataset, ambos concentrados en el bucket 20:55–20:58 UTC.

## 2026-08-18 09:10 — Redefinición de alcance del ticket

El alcance de este ticket se acotó a los hallazgos ya confirmados (lado de base de datos saludable, tasa de 400 sostenida, evento aislado de latencia/500). La causa raíz de la tasa de 400 y el análisis de capacidad/límites ante una campaña de mayor escala quedan como acciones propuestas para una investigación futura, sin resolver en este ticket.

## 2026-08-18 09:12 — Cierre de artefactos

Generé `ops.md`, `scripts.sql` y esta bitácora a partir del estado final de `investigation.md`.

## 2026-08-20 08:30 — Reapertura por segunda ocurrencia

Reabrí la investigación a partir de un reporte de pico adicional de tráfico sobre MobileAppService el 2026-08-19, ~100 req/s, ventana 21:00–22:00 UTC-3 (2026-08-20 00:00–01:00 UTC). Confirmé que no se superpone con la ventana del 2026-08-16 y que continúa bajo el mismo ticket GITIN-1866 por su alcance general de impacto de campañas.

## 2026-08-20 08:45 — Verificación de bloqueos y CPU, ventana del pico 2026-08-19

Ejecuté Q7 (disponibilidad, 12 snapshots sin huecos), Q8 (bloqueos, 0 filas) y Q9 (desglose de CPU por host) sobre la ventana 2026-08-20 00:00–01:00 UTC. Confirmé el mismo patrón que el 2026-08-16: sin bloqueos, CPU de MobileAppService marginal (156ms en `MOBI-02`, 0ms en `MOBI-01`), y `SFCG-WSV2-01` nuevamente como consumidor dominante a una tasa consistente con su carga base ya observada.

## 2026-08-20 08:58 — Análisis de logs IIS, ocurrencia 2026-08-19

Recibí y procesé la exportación Graylog de la ventana (84.428 filas totales, 28.028 de tipo `iis_w3c_mobile`). Confirmé que se repite la misma huella de tasa de 400 vista el 2026-08-16, en los mismos tres endpoints y mismo orden de magnitud (`SaveNewMember` 71.4%, `Login` 65.2%, `RecoveryPassword` 36.5%; 14.8% general). Sin errores 500 en esta ventana. Volumen medido (~4,7 req/s pico) muy por debajo del pico reportado (~100 req/s), misma discrepancia no reconciliada que en la primera ocurrencia.

## 2026-08-20 09:05 — Análisis de causa raíz por código fuente

Revisé el código fuente local de MobileAppService (`repo/dev-src-sol-smartloyalty/Front/MobileAppService/`) para confirmar el mecanismo que genera las respuestas 400. Identifiqué dos disparadores: `ModelValidatorFilter` (campos requeridos/formato inválido, antes de ejecutar la acción) y `Logger` (convierte cualquier excepción de negocio en un 400 genérico). Documenté el detalle endpoint por endpoint en `investigation.md`. Confirmé que parte de los fallos de `SaveNewMember`/`RecoveryPassword` (validación de teléfono, `InvalidUserName`) devuelve HTTP 200 con el fallo solo en el cuerpo — no capturado por la métrica de tasa de 400 usada en este ticket.

## 2026-08-20 09:15 — Atribución parcial vía campo `Action` de `svclog_input`

Contrasté el campo `Action` de los eventos `svclog_input` en Graylog (ventana 2026-08-19) contra la tabla de causas identificada por código fuente. Confirmé coincidencia para `InvalidPassword` (falla de autenticación en `Login`) y `customerEmailNotCompatible` (código exacto de `RecoveryPassword`), ambos sostenidos parejo en la ventana. Confirmé que ninguno de los códigos de `SaveNewMember` aparece en este campo — sin visibilidad alguna para ese endpoint con este dato.

## 2026-08-20 09:22 — Confirmación de brecha estructural en NXLog

Recibí y revisé la configuración real de NXLog en `SFCG-MOBI-01` y el `SystemDiagnostics.config` de la app. Confirmé que la brecha de atribución de `SaveNewMember` es estructural: el pipeline NXLog→Graylog descarta el contenido crudo de cualquier línea que no matchee uno de sus 5 regex (48.728 de 56.398 filas `svclog_input` llegan sin ningún campo extraído). Confirmé que el dato completo existe en el servidor (`SourceSwitch=All`) en dos archivos, incluyendo un `.svclog` XML nunca leído por NXLog — no ingerible automáticamente por limitación de producto (NXLog Community), pero disponible para extracción manual.

## 2026-08-20 09:27 — Actualización de artefactos

Actualicé `ops.md` y `scripts.sql` con los hallazgos de la ocurrencia 2026-08-19, el análisis de causa raíz por código fuente y la confirmación de la brecha estructural en NXLog, a partir del estado final de `investigation.md`.

## 2026-08-20 09:40 — Confirmación de formato del `.svclog` con muestra real

Recibí una muestra real de un registro `.svclog` de `SFCG-MOBI-01` (fuera de las ventanas de campaña, solo para confirmar formato). Confirmé la estructura: stream de `<E2ETraceEvent>` sin nodo raíz, sin saltos de línea, con un formato `<TraceSourceLogger>` interno que varía según el punto de log. La muestra corresponde a un caso exitoso de `RecoveryPassword` y no contiene ningún tag `<BusinessReport-*>` — consistente con la teoría de que ese tag solo aparece en el camino de fallo, pero aún no confirmado con una muestra real fallida dentro de la ventana de campaña.

## 2026-08-20 09:50 — Archivo `.svclog` real recibido — mecanismo confirmado, ventana equivocada

Recibí el archivo real `SmartLoyalty.MobileAppService.svclog` de `SFCG-MOBI-01` (6,4MB). Confirmé que su rango de tiempo (2026-08-20 05:00–12:33 UTC) no coincide con ninguna de las dos ventanas de campaña. Usándolo solo para validar el método de extracción, confirmé que los tags `<BusinessReport-*>` sí existen y son directamente atribuibles a endpoint mediante un prefijo `[OP] {endpoint}: ` en el mismo mensaje — incluyendo códigos de `SaveNewMember`, que antes no tenían ninguna visibilidad vía Graylog. Esto resuelve la duda mecánica de H11: el dato es recuperable manualmente una vez que se consigue el archivo correcto. Queda pendiente conseguir el archivo (o una copia rotada/archivada) que cubra las ventanas reales de campaña.

## 2026-08-20 09:55 — Cierre del intento de atribución retroactiva vía `.svclog`

Usuario confirmó que no existe ninguna copia rotada/archivada de `SmartLoyalty.MobileAppService.svclog`. Cerré la acción propuesta de atribución retroactiva para `SaveNewMember`/`Login`/`RecoveryPassword` en las ocurrencias del 2026-08-16 y 2026-08-19 como no recuperable — el dato existía en el servidor al momento del evento (`SourceSwitch=All`) pero rotó fuera del archivo antes de poder extraerse. El mecanismo queda validado y documentado para uso en ocurrencias futuras, con la salvedad de que requiere extracción dentro de la ventana de retención corta del archivo (~11–12h).
