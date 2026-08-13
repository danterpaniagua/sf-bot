# Eventos — 20260812_graylog_messages_not_arriving

## 2026-08-11 23:00 — Detección inicial

He detectado, al intentar agregar el campo `MessageId` a la configuración de NXLog de las VM `SFCG-SMTP-01`/`SFCG-SMTP-02` (servicio `SF-SMTPRL`), que los mensajes habían dejado de llegar a Graylog.

## 2026-08-11 23:00-00:30 — Revisión de configuración NXLog

**Comando:** C11 — Listado de `hMailServer\Logs\`
**Resultado:**
~80 archivos históricos coincidiendo con el wildcard `*.log`, hasta octubre de 2024.

He revisado exhaustivamente la configuración de NXLog en ambas VM: reglas de `drop`, el wildcard de archivos, el extractor CSV (`w3c_parser_mobile`, confirmé que su esquema de campos correspondía al formato real de hMailServer), el `Output` (`om_udp`) y la `Route`. He encontrado y corregido dos errores propios introducidos durante la revisión y un typo preexistente (`$Cardinaluty`). He revertido a la configuración original en ambas VM sin lograr estabilidad sostenida — el corte de envío ha recurrido incluso con la configuración original, lo cual descarta que las ediciones fueran la causa.

## 2026-08-12 00:30-01:00 — Descarte de teorías de red y disco

**Comando:** C10 — Envío UDP de prueba desde `SFCG-SMTP-01`
**Resultado:**
Mensaje recibido en Graylog en menos de un segundo.

He confirmado alcance de red desde `SFCG-SMTP-01` hacia Graylog mediante un envío UDP de prueba directo.

**Comando:** C1 — `df -h` en `sf-monitoreo`
**Resultado:**
Filesystem raíz en 20% de uso.

**Comando:** C2 — `docker ps`
**Resultado:**
Confirmé que `sf-monitoreo.smartfran.com` corre el stack Graylog/OpenSearch/MongoDB.

He descartado una alerta de disco de Elasticsearch de 19 días de antigüedad como causa activa, dado que el filesystem raíz está en 20% de uso.

## 2026-08-12 01:00-01:30 — Hallazgo de fallas de indexación

**Comando:** C9 — `curl .../api/system/indexer/failures`
**Resultado:**
32.448 fallas en las últimas 24 h (177.356 acumuladas), todas con el mismo error: `Limit of total fields [1000] has been exceeded`.

He confirmado que esto afecta tanto a `graylog_299` (índice por defecto de Graylog) como a `sp_platform__50` (SmartPedidos platform-service) — no es un problema específico de SF-SMTPRL sino sistémico del cluster de OpenSearch.

## 2026-08-12 01:30 — Identificación de la causa raíz real

**Comando:** C6 — `curl .../_cat/indices?v`
**Resultado:**
La mayoría de los índices del cluster en estado `red` (shards no asignados).

**Comando:** C7 — `curl .../_cluster/health`
**Resultado:**
`green`, 998/998 shards activos, apenas unos minutos después del comando anterior.

**Comando:** C8 — `curl .../_cluster/allocation/explain` sobre `aws_wafv2__189`
**Resultado:**
Shard confirmado `started`, sano.

**Comando:** C4 — `docker logs opensearch` (grep)
**Resultado:**
`Cluster is not recovered yet` seguido de `recovered [257] indices into cluster_state` a las 01:25:21 UTC.

**Comando:** C3 — `docker inspect opensearch`
**Resultado:**
`StartedAt: 2026-08-12T01:24:54Z`, `OOMKilled: false`.

He identificado que cada reinicio de OpenSearch deja el cluster no disponible durante su recuperación, y que cualquier mensaje enviado por NXLog durante esa ventana se pierde sin ningún error visible en el origen — independientemente de la configuración de NXLog, que nunca fue la causa real.

## 2026-08-12 01:48 — Confirmación de recuperación y redespliegue de MessageId

Con la causa real identificada, he redesplegado la extracción de `$MessageId` en ambas VM y he confirmado mensajes llegando correctamente a Graylog con el campo `MessageId` poblado (`5677615` en `SFCG-SMTP-01`, `126952` en `SFCG-SMTP-02`), sin errores de procesamiento.

## 2026-08-12 — Reinicio completo de la VM y corrección de la causa raíz

He tenido que reiniciar la VM completa (`sf-monitoreo.smartfran.com`) porque los servicios Docker (`graylog`/`opensearch`/`mongo`) no volvían con un reinicio normal.

**Comando:** `last reboot -F`
**Resultado:**
Boot actual a las 2026-08-12 01:24:46 — coincide exactamente con lo que había identificado antes como "reinicio del contenedor opensearch". Boot anterior corriendo sin interrupción desde el 19 de enero de 2026 (205 días), registrado como entrada colgada ("still running" duplicada) en vez de un rango cerrado — consistente con un corte forzado, no un apagado ordenado.

**Comando:** `docker inspect opensearch/graylog --format 'RestartCount={{.RestartCount}} StartedAt={{.State.StartedAt}}'`
**Resultado:**
`RestartCount=0` en ambos, `StartedAt` ~01:24:54-55Z.

He corregido el ticket: no fue un reinicio espontáneo y auto-resuelto del contenedor `opensearch` como había registrado antes — fue un corte de los servicios Docker que no se recuperó con medios normales y requirió forzar el reinicio de toda la VM. `RestartCount=0` confirma que fue un arranque único tras el reinicio de la VM, no un ciclo de reinicios de Docker.

## 2026-08-12 — Aclaración del reinicio y descarte de Zabbix/MariaDB como causa visible

He confirmado que el reinicio fue en dos pasos: primero `systemctl reboot` desde la VM, que quedó colgado más de una hora; ante eso, se forzó el reinicio desde la consola de AWS, que sí completó limpio (la secuencia ordenada de `dockerd` que había encontrado antes corresponde a este segundo intento, no al primero). Revisé `zabbix-server` y `mariadb` como posible causa del colgado inicial — ambos reiniciaron a la misma hora que el resto de los servicios (consistente con el reinicio de toda la VM, no con una falla propia), y sus logs no muestran nada anómalo en las ~11 h desde entonces. Ninguno de los dos logs alcanza a cubrir el período previo al colgado, así que esto no descarta una causa ahí, solo no encuentra evidencia. La causa exacta del colgado del primer `systemctl reboot` queda sin confirmar — pendiente revisar métricas de AWS (`StatusCheckFailed_System`, `VolumeQueueLength` del EBS) si se decide seguir esa línea.

## 2026-08-12 — Aplicación del fix de límite de campos de mapeo

He aplicado `index.mapping.total_fields.limit: 2000` en `graylog_299` y `sp_platform__50` (`{"acknowledged":true}`) y confirmé vía `_settings` que ambos índices muestran el límite nuevo (`"limit": "2000"`). Pendiente verificar que no haya otros índices acercándose al mismo límite.

## 2026-08-12 — Corrección del typo `$Cardinaluty`

He corregido `$Cardinaluty` a `$Cardinality` en la configuración de NXLog de `SFCG-SMTP-01` y `SFCG-SMTP-02`.

## 2026-08-12 — Apertura de ticket

He abierto este ticket (GITIN-1827, relacionado con GITIN-1821) para documentar la causa raíz real y las acciones pendientes — en particular, determinar el disparador exacto del reinicio de OpenSearch y decidir si se levanta el límite de campos de mapeo.
