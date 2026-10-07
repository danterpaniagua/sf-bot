# Eventos — 20260828_wscg01_zabbix_graylog_onboarding

## 2026-08-28 — Apertura y redefinición de alcance

He confirmado que `SFCG-WSCG-01` ya estaba dado de alta en Zabbix, a diferencia de lo que suponía el ticket original. He reorientado el trabajo a auditar la cobertura real contra el checklist estándar de onboarding, en vez de dar de alta el host desde cero.

## 2026-08-28 — Validación del checklist de onboarding

He relevado `host.get`, `trigger.get` e `item.get` sobre `SFCG-WSCG-01` (hostid `10676`) y he confirmado que las alertas de disco, CPU y RAM ya estaban correctamente configuradas a severidad Warning o superior. He encontrado dos gaps reales: el ítem `54600` tenía el nombre del host equivocado (`WebServiceV2` en vez de `WebServiceCG`), y no existía ningún trigger sobre el ítem de tasa total de requests IIS (`53770`) pese a que el ítem sí recolectaba datos.

He confirmado además que los ítems `54599`/`54600` (GET/POST por app, distintos del `_Total`) nunca recolectaron datos (`lastclock:0`) — mismo patrón de falla ya visto en `GITIN-1956`.

## 2026-08-28 — Corrección de la arquitectura de monitoreo SSL

Inicialmente he marcado como gap la ausencia de una alerta de vencimiento de certificado a nivel del host. Al revisar en el frontend de Zabbix, he confirmado que ese monitoreo es centralizado en el host `Zabbix server` (un ítem por servicio, no por VM) — la ausencia en `SFCG-WSCG-01` era el estado esperado, no un gap real. He corregido la validación del checklist en consecuencia.

## 2026-08-28 — Corrección del ítem 54600

He corregido, vía `item.update`, el nombre del ítem `54600` de `SmartLoyalty.WebServiceV2: IIS Method POST requests per second` a `SmartLoyalty.WebServiceCG: IIS Method POST requests per second`. He confirmado que la `key_` ya resolvía el macro correcto — el cambio es cosmético, no afecta el historial de datos.

## 2026-08-28 — Creación de macros y triggers sobre el ítem 53770

He intentado crear los macros de contexto `WEBSCG01` con `usermacro.create` y he fallado — ese método es host-scoped y requiere `hostid`. He corregido usando `usermacro.createglobal`, y he confirmado la creación de los 5 macros (`WARNING=15`, `AVERAGE=30`, `HIGH=50`, `OK<=10`, `TIME_NOK=5m`, valores provistos según capacidad de la VM). He creado la cadena de 3 triggers (Warning `26862` → Average `26863` → High `26864`) sobre el ítem `53770`, con las dependencias encadenadas. He verificado con `trigger.get` que los 3 quedaron en `state:0`/`error:""`, evaluando limpio.

## 2026-08-30 — Corrección de una conclusión previa (cruzada con GITIN-1966)

Al retomar el análisis de macros para `GITIN-1966`, he encontrado que mi búsqueda filtrada anterior (`search: {"macro": "PERF_COUNT_TRIG"}`) había devuelto vacío, llevándome a concluir que los macros base no estaban definidos en ningún lado y que los triggers de referencia de `SFCG-WSV2-01` no eran funcionales. Con un `usermacro.get` sin filtro he confirmado que esa conclusión era incorrecta — los macros base sí estaban definidos globalmente. La corrección del propio `SFCG-WSCG-01` (creación del contexto `WEBSCG01` y sus triggers) sigue siendo válida y necesaria de todos modos, ya que ese host efectivamente no tenía ningún trigger sobre el ítem `53770` — el error de diagnóstico fue sobre `SFCG-WSV2-01`, no sobre este ticket.

## 2026-08-31 — Redacción del ticket

He redactado `ops.md` para GITIN-1961 a partir del estado de `investigation.md`, dejando explícito que el lado Zabbix está completo salvo un punto opcional (causa raíz de `54599`/`54600`), y que el lado Graylog del onboarding todavía no arrancó — no lo he cerrado como resuelto.

## 2026-09-04 — Confirmación de logs Graylog vía NXLog

A partir de un mensaje real de Graylog, he confirmado que los logs de acceso IIS de `SFCG-WSCG-01` sí están llegando a Graylog, vía NXLog (`SourceModuleType: im_file`, `SourceModuleName: iis_w3c_mobile`). El mensaje de muestra corresponde a un health-check GET del Load Balancer Agent a `/swagger/ui/index`, tageado `ServiceName: SF-WEBSCG`. Queda abierto si el enrutamiento a un stream dedicado (en vez del stream por defecto "All Messages") es requisito para dar el onboarding por completo.

## 2026-09-04 — Segundo pathway de logging a nivel de aplicación

He encontrado que `SmartLoyalty.WebServiceCG` tiene su propia configuración de `system.diagnostics` (trace source), independiente de los logs de acceso IIS. Escribe un `.svclog` XML en `E:\Logs\SmartLoyalty.WebServiceCG\`. He confirmado que existe además una carpeta `csv` en ese mismo directorio, pero que está vacía — sin `delimitedListener` configurado que escriba ahí, a diferencia de `SFCG-MOBI-01` que sí lo tiene activo. He concluido que este pathway es un dead-end para el onboarding a Graylog tal como está hoy.

## 2026-09-04 — Análisis del .svclog real y corrección del mecanismo de envío

He analizado una muestra real del `.svclog` (~4.4MB, 1002 eventos) — la he mantenido solo local, nunca la he subido al repo (he agregado `*.svclog` al `.gitignore` raíz por contener PII real de clientes en algunos eventos). He encontrado dos clusters de excepciones (conectividad/SMTP sin PII, y capa de base de datos con `Email`/`UidId` reales en 438 de 451 eventos). He redactado un primer borrador de config NXLog basado en parsear el XML multilínea directamente, en el repo separado `sf-devops`.

Ese borrador ha quedado obsoleto al revisar los configs NXLog reales ya desplegados en `SFCG-MOBI-01` y `SFCG-WSCG-01`: en `MOBI-01` el mecanismo que realmente envía a Graylog es el CSV (`DelimitedListTraceListener`), no el XML — el input que lee el XML tiene su salida a Graylog comentada, muerta. `WSCG-01` no tiene ningún input de este tipo configurado, consistente con que su carpeta `csv` está vacía. He corregido el rumbo: si este pathway entra en alcance, el trabajo real es agregar un `delimitedListener` al trace config de `WSCG-01` (como tiene `MOBI-01`) y un input NXLog CSV a medida — no el parser XML ya descartado.

## 2026-09-04 — Re-chequeo de configs sf-devops y segunda muestra de .svclog

He revisado directamente `sf-devops/observability/nxlog/webservicecg/01/conf/` — he confirmado que `iis.conf` es el pathway activo real (coincide exacto con el mensaje de muestra ya confirmado) y que no existe ningún `svclog.conf` ni input CSV en este host, reconfirmando en forma independiente que el pathway de aplicación sigue sin cablear. De paso he confirmado por config (no solo sospecha) que `cs-uri-query` viaja sin redactar a Graylog junto con el DNI ya extraído aparte.

He analizado una segunda muestra real de `.svclog` (`/home/dpaniagua/Downloads/SmartLoyalty.WebServiceCG.svclog`, distinta por hash de la ya analizada), solo a nivel estructural — nunca he leído ni escrito valores reales. Mismo conteo de eventos (1002) y mismo rango de fechas que la primera muestra, mismos clusters de excepciones, y he confirmado de nuevo el patrón de PII (`Email` escapado dentro de bloques `TraceSourceLogger`). Esta muestra no tiene ningún salto de línea en todo el archivo — refuerza aún más la conclusión de que un lector basado en líneas no serviría acá.

## 2026-09-04 — Decisión de alcance y primer borrador del pathway de aplicación

He registrado la decisión de incorporar el pathway de logs a nivel de aplicación al alcance de `GITIN-1961`. He redactado dos artefactos, ninguno desplegado todavía:

1. `wscg01-webservicecg-tracesource-config.proposed.xml` — agrega el `delimitedListener` al trace config de `SFCG-WSCG-01`, siguiendo exactamente el patrón de `SFCG-MOBI-01` (mismo delimitador, mismo `maxTraceFileSizeKb`), apuntando a la carpeta `csv` ya existente pero vacía.
2. `sf-devops/observability/nxlog/webservicecg/01/conf/nxlog.d/svclog.conf` — nuevo archivo (separado de `iis.conf`, a diferencia de `MOBI-01` que los combina), con la extracción de `ErrorId`/`Email`/`UidType`/`UidId`/`Usuario`/`Endpoint` basada en la estructura confirmada en las dos muestras reales de `.svclog`.

He dejado explícito que este segundo artefacto no está validado contra una muestra CSV real — no existe ninguna todavía porque el `delimitedListener` no está desplegado. Falta: aplicar el cambio de trace config en el host (requiere reciclar el app pool), desplegar `svclog.conf`, y validar el regex contra una línea CSV real una vez que empiece a escribir datos.

## 2026-09-05 — Confirmación en vivo: el pathway de aplicación está desplegado y funcionando

He confirmado el despliegue de ambos artefactos (cambio de trace config + `svclog.conf`) en `SFCG-WSCG-01` — indirectamente, al recibir mensajes reales de Graylog con `SourceModuleName: svclog_input`. He confirmado que la extracción de campos funciona correctamente contra un evento real de excepción en `AccountRecovery`: `ErrorId`/`Email`/`UidType`/`UidId`/`Usuario`/`Endpoint` llegaron todos poblados como estaba previsto (sin reproducir los valores reales de email/DNI en ningún archivo, mismo criterio de PII de siempre).

He encontrado un problema real al revisar los mensajes: cada llamada lógica a `Logg.Error` genera 3 líneas físicas en el CSV del `delimitedListener` — una con la clasificación de excepción únicamente, una con el bloque de datos estructurado (la útil), y una línea en blanco sin ninguna señal. La causa es que `WriteFooter` de `DelimitedListTraceListener` sigue escribiendo su propia línea aunque `TraceOutputOptions` esté en `None`. He corregido `svclog.conf` para descartar las líneas en blanco (`if $raw_event =~ /^\s*$/ drop();`), dejando las otras dos líneas parciales tal cual — no están correlacionadas entre sí más allá de compartir timestamp y origen. Falta re-validar el fix contra datos frescos.

## 2026-09-05 — Cierre del ticket

He registrado el cierre de `GITIN-1961`, con el siguiente alcance final: onboarding a Zabbix completo (con el punto opcional de `54599`/`54600` sin resolver, no bloqueante), logs de acceso IIS confirmados en Graylog vía NXLog, y logs de aplicación (`.svclog`/CSV vía `delimitedListener`) confirmados en Graylog con datos reales tras el fix de la línea en blanco. No he re-validado ese fix contra datos frescos ni he evaluado si el stream por defecto ("All Messages") requiere reemplazo por uno dedicado — ninguno de los dos ha bloqueado el cierre, quedan como seguimiento fuera de este ticket si hace falta retomarlos.
