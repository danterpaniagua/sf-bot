# Eventos — 20260915_mobileappservice_loadtest_errors

## 2026-09-15 15:30 — Inicio de investigación

He recibido el reporte de Grido sobre errores en MobileAppService durante una prueba de carga. He revisado el precedente GITIN-1909 (2026-08-21, mismo patrón) y he descartado `connectionTimeout=15s` como causa principal tras analizar la distribución de duraciones en `SmartFranCall.log`.

## 2026-09-15 17:30 — Burst de 503 a las 15:09 UTC root-causado

He confirmado mediante `httperr.log` de ambos servidores y Event Log de `SFCG-MOBI-02` que la tarea programada `CleanCSVLogs` ejecuta un `iisreset` completo diario a las `~15:09` UTC, coincidiendo con la ventana de la prueba de carga de hoy. He identificado el script (`D:\Util\scripts\cleanCsvLogs.ps1`) y su disparador diario (`StartBoundary 2024-12-05`, `DaysInterval 1`).

## 2026-09-15 17:45 — Remediación aplicada en `SFCG-MOBI-02`

He eliminado el disparador diario `~15:09` UTC de la tarea `CleanCSVLogs` en `SFCG-MOBI-02`, dejando únicamente el disparador "At startup". He descartado la misma acción en `SFCG-MOBI-01` (disparador a las `05:00` UTC) por no tener errores HTTP reales asociados en esa ventana.

## 2026-09-15 18:00 — Bloqueo SQL `06:00–08:00` UTC root-causado

He identificado mediante `PNSSRL_AuditSysprocesses` que el job `PNSSRL_MantenimientoIndices` ejecutó un `ALTER INDEX REBUILD` sobre `Sml.CustomerPointsLog`, manteniendo un lock `Sch-M` durante ~45 minutos y bloqueando las consultas de `Benefits/GetCustomerStatus`/`Customer/GetCustomerProfile`. He referenciado el hallazgo con GITIN-1981 (mismo mecanismo, ya abierto, sin corrección aplicada) y GITIN-1669 (primera ocurrencia).

## 2026-09-16 09:30 — Cruce con Graylog: confirmación independiente del bloqueo SQL

He confirmado que MobileAppService envía logs a Graylog (`sf-monitoreo.smartfran.com`, stream `SML_MobileApp`, `ServiceName:SF-MOBILE`). He cruzado la ventana de bloqueo (`06:15`–`07:35` UTC) contra el log IIS de Graylog y he encontrado un hueco de 49 minutos sin solicitudes completadas en `GetCustomerStatus`/`GetCustomerProfile`, coincidiendo con la ventana del lock SQL — tercera fuente de evidencia independiente confirmando el mismo hallazgo.

He detectado que los eventos `LoginSuccess` del log de servicio de MobileAppService registran la contraseña del cliente en texto plano — hallazgo de seguridad independiente del alcance de este ticket.

## 2026-09-16 10:30 — Ampliación del alcance a los buckets `06:00`–`08:00` UTC

He separado las fallas de `SmartFranCall.log` en la ventana de bloqueo por endpoint afectado, confirmando que el 80% de las fallas en esa ventana corresponden a `Benefits/GetCustomerStatus`/`Customer/GetCustomerProfile` — los mismos endpoints confirmados bloqueados vía SQL.

## 2026-09-16 11:00 — Análisis del pico `15:00–15:20` UTC

He analizado el pico de tráfico reportado por Grido (coincide con un reporte de latencia de Grido a las 12:00hs ARG). He separado las fallas por código HTTP (4XX/5XX) y por tipo, confirmando que solo 57 de 4.616 fallas corresponden a errores HTTP reales — el resto (2.653 registros) son solicitudes sin respuesta de servidor, consistente con presión de capacidad.

## 2026-09-16 11:30 — Desbalance de tráfico entre instancias detectado

He detectado que `SFCG-MOBI-01` recibió solo 1.4% del tráfico total durante el pico (`15:00`–`15:20` UTC) contra 98.6% en `SFCG-MOBI-02`, sin que el health probe TCP del Load Balancer reportara ningún problema (`DipAvailability` ~100% durante toda la ventana). He descartado que el probe TCP explique el desbalance por sí solo — queda pendiente confirmar el modo de distribución del LB.

## 2026-09-16 12:00 — Generación del ticket

He redactado `ops.md` con el estado consolidado de la investigación: dos hallazgos cerrados (`CleanCSVLogs`, bloqueo SQL referenciado a GITIN-1981) y dos en investigación (desbalance de tráfico, presión de capacidad en el pico).

## 2026-09-16 13:00 — Corrección de encuadre: campaña real, no prueba de carga

He corregido `investigation.md` y `ops.md`: el evento del 15/09/2026 fue tráfico real de clientes generado por una campaña de marketing, no una prueba de carga de Grido como se había asumido en todo el ticket hasta ahora. He revisado las causas raíz ya confirmadas (`CleanCSVLogs`, bloqueo SQL) y no cambian por esta corrección. He actualizado la interpretación del cluster `HTTP_4XX` en `Account/Login`/`RecoveryPassword`: ya no es atribuible a higiene de datos de test (credenciales reutilizadas), sino a fricción de autenticación real bajo volumen elevado. He elevado la Severidad de `ops.md` de Media-Alta a Alta, dado el impacto confirmado sobre clientes reales.
