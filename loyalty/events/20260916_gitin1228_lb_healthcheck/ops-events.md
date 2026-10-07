# Eventos — 20260916_gitin1228_lb_healthcheck

## 2026-09-16 09:00 — Inicio del ticket, derivado de GITIN-2053

He iniciado este ticket a partir de hallazgos de GITIN-2053: el probe TCP actual de `SFCG-MOBI-LB` no detecta salud a nivel de aplicación. He diseñado `healthcheck.ashx` (handler C#) reportando CPU, RAM y conectividad a base de datos, con timeout corto para evitar que una consulta a base de datos bloqueada (hallazgo de GITIN-2053) cuelgue el propio health check.

## 2026-09-16 09:30 — Definición de configuración

He resuelto usar `ConfigurationManager.AppSettings` vía `Config\AppSettings.config` para los umbrales de CPU/RAM, siguiendo el patrón ya existente en la aplicación. He confirmado que SRE tiene acceso completo al sistema de archivos de ambos servidores — no requiere intervención de desarrollo.

## 2026-09-16 09:55 — Despliegue confirmado en `SFCG-MOBI-02`

He confirmado el handler respondiendo correctamente en `SFCG-MOBI-02`, incluyendo conectividad real a base de datos. He guardado el archivo en el evento para referencia.

## 2026-09-16 10:15 — Prueba controlada de un solo servidor revela un caso límite real

He confirmado (vía Activity Log) que el Admin State de `SFCG-MOBI-01` fue seteado manualmente para aislar la prueba a un único servidor. Con `-01` aislado, el corte del probe al nuevo health check HTTP llevó a `-02` (solo, bajo carga completa) a superar su propio umbral de CPU/RAM y reportarse como no saludable, sacando todo el pool de rotación. He revertido el probe a TCP para restaurar el servicio de inmediato.

## 2026-09-16 10:45 — Root cause del fallo en puerto 8043 confirmado

He diagnosticado, mediante pruebas manuales en capas (TCP, TLS, HTTP), que el binding HTTPS de IIS en el puerto 8043 está limitado por hostname y rechaza solicitudes por IP directa — el mismo mecanismo que afectaría al probe real de Azure, que solo puede conectar por IP. He confirmado esto directamente vía `Get-WebBinding`. He decidido migrar el probe a HTTP puerto 8080 (binding wildcard, sin esta limitación).

## 2026-09-16 11:15 — Brecha de despliegue en `SFCG-MOBI-01` cerrada

He confirmado que `SFCG-MOBI-01` no tenía el handler ni la configuración desplegados. He verificado que sus bindings de IIS ya coinciden con los de `-02` (sin trabajo de binding necesario). He desplegado el handler y la configuración, y he confirmado una respuesta saludable con conectividad a base de datos exitosa.

## 2026-09-16 11:30 — Corte del probe exitoso

Con ambos servidores confirmados saludables de antemano, he migrado `SFCG-MOBI-LB-lbrule02` al nuevo probe HTTP en puerto 8080. He confirmado ambos servidores `Up` bajo el nuevo probe — corte exitoso, sin repetir el problema de la prueba anterior.

## 2026-09-16 11:45 — Corrección sobre `probeThreshold`

He verificado (documentación oficial de Azure) que `probeThreshold` no protege contra el caso de auto-remoción por CPU/RAM encontrado antes — ese parámetro solo aplica a timeouts de probe HTTP, no a respuestas explícitas no-200 como las que devuelve el propio handler. He dejado registrado que la corrección real de ese caso (umbral más alto o histéresis) sigue pendiente.

## 2026-09-16 12:00 — Redacción del ticket

He redactado `ops.md` con el estado consolidado: probe HTTP implementado y en producción en ambos servidores; balanceo ponderado por CPU/RAM (objetivo original del ticket) pendiente de definición de alcance.

## 2026-09-16 12:15 — Métrica de cola de requests agregada

He agregado `requestsQueued` (contador `ASP.NET\Requests Queued`) al handler, informativo por ahora — no afecta el status HTTP del health check hasta resolver el diseño de histéresis pendiente. He confirmado la respuesta correcta en `SFCG-MOBI-01`. He actualizado `ops.md` reflejando la nueva métrica.
