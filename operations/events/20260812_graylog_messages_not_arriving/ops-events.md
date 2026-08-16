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

## 2026-08-13 — Regla NXLog adicional para detección temprana

He agregado una regla adicional a la configuración de NXLog en `SFCG-SMTP-01`/`SFCG-SMTP-02`: `if $raw_event =~ /SMTPDeliverer - Message\s(\d+): (.*)/ { $DeliveryStatus = $2; }`, sin modificar la extracción de `$MessageId` (queda a cargo de la regla genérica ya existente). El objetivo es poder comparar a futuro el volumen de eventos de estado de SMTPDeliverer que genera hMailServer contra lo que efectivamente llega a Graylog, para detectar más rápido una eventual repetición de la pérdida silenciosa de UDP durante indisponibilidad del cluster de OpenSearch que causó este incidente. Pendiente de despliegue en ambas VM.

## 2026-08-13 — Confirmación del despliegue en ambas VM y hallazgo de bug menor

He confirmado, con documentos reales de Graylog, que la regla `$DeliveryStatus` está desplegada y funcionando en ambas VM (`SFCG-SMTP-01`, `Cardinality "01"`, `192.168.50.161`, y `SFCG-SMTP-02`, `Cardinality "02"`, `192.168.50.162`) — `MessageId` y `DeliveryStatus` se capturan de forma independiente y correcta (mismo `MessageId` a lo largo del ciclo de vida de un mensaje, con distintos valores de `DeliveryStatus`).

He encontrado un bug menor en la expresión regular: `$DeliveryStatus` incluye una comilla doble sobrante al final (ej. `Message delivery thread completed."`), porque `(.*)` captura de forma voraz la comilla de cierre del campo en el log crudo de hMailServer. Fix identificado: reemplazar `(.*)` por `([^"]*)`, que se detiene naturalmente antes de esa comilla. Pendiente de desplegar en ambas VM.

## 2026-08-13 — Fix del bug de comilla sobrante confirmado resuelto

He confirmado, con documentos reales de Graylog desde `SFCG-SMTP-02` (`Cardinality "02"`), que el fix (`(.*)` → `([^"]*)`) resuelve el problema: `DeliveryStatus` llega limpio, sin la comilla sobrante, tanto en `"Message delivery thread completed."` como en rutas de archivo (`...{GUID}.eml`). He confirmado el mismo resultado en `SFCG-SMTP-01` (`Cardinality "01"`) con datos reales de Graylog — `DeliveryStatus` limpio en ambas VM, sin comilla sobrante.

## 2026-08-13 — Nuevo tipo de fallo de indexado detectado y separado a ticket propio

He detectado un cuarto tipo de fallo de indexado (mismo mecanismo que `msg_rest_status`, campo distinto): `msg_branch_id` mapeado como `long`, rechazando documentos que envían el literal `"unknown"`. Afecta simultáneamente a `sp_platform__50` y `graylog_299`, mismos IDs de documento en ambos. Al identificar la causa raíz como un bug de aplicación en `platforms-service` — no relacionado con el reinicio de OpenSearch que es el alcance de este ticket — lo separé a un ticket propio: `operations/events/20260813_platform-service-branch-id-unknown-mapping-error/` (GITIN-1854).

## 2026-08-13 — Revisión del docker-compose real y fortalecimiento de la teoría de OOM

He revisado el `docker-compose.yml` real del stack y confirmé dos cosas: `bootstrap.memory_lock: true` está seteado en `opensearch` sin el bloque `ulimits: memlock` correspondiente (el lock de memoria no toma efecto realmente), y los límites `deploy.resources.limits` (`6G` en `opensearch`, `4G` en `mongo`) no aplican fuera de Docker Swarm — confirmé que este stack corre con `docker compose up` simple, no `docker stack deploy`, por lo que esos límites nunca estuvieron realmente en efecto. Esto fortalece la teoría de un OOM a nivel de host (no de cgroup, lo cual explicaría `OOMKilled: false`) como causa del reinicio, y explicaría por qué el `systemctl reboot` inicial quedó colgado. Pendiente confirmar de forma definitiva revisando `dmesg`/`journalctl -k` alrededor de las 01:24 UTC del 2026-08-12.

## 2026-08-13 — Secuencia exacta de apagado encontrada en syslog/kern.log del host real

He encontrado en `/var/log/syslog` y `/var/log/kern.log.1` del host real que a las 01:15:43 UTC comenzó un apagado ordenado por `systemctl reboot` — decenas de servicios se detuvieron en secuencia normal, incluyendo el inicio de la detención de `dockerd` (`Processing signal 'terminated'`). Confirmé, extrayendo el rango completo con `sed`, que no hay **ningún** registro de log — de ningún subsistema — entre `Stopping PackageKit Daemon...` (01:15:43) y la primera línea de kernel del boot nuevo (01:24:51), un silencio total de ~9 minutos. Esto apunta a que todo el sistema se congeló en ese instante, coincidiendo con el paso de detención de Docker (que tiene que cerrar de forma prolija el índice de OpenSearch de 472.8GB, sin límite real de memoria y con el heap de la JVM sin lock) — un mecanismo preciso, no solo evidencia circunstancial, aunque sigue sin existir una línea literal de `oom-killer` (nada se logueó durante el congelamiento en sí).

**Discrepancia sin resolver:** lo ya registrado anteriormente en este archivo dice que el `systemctl reboot` "quedó colgado más de una hora" antes del reinicio forzado desde la consola de AWS. Eso no coincide con la ventana de silencio técnico de ~9 minutos encontrada ahora (01:15:43 → 01:24:46/51). No he confirmado el origen de la cifra de "más de una hora" — pendiente de aclarar antes de dar por cerrado este punto.

## 2026-08-13 — Corrección: la cifra de "más de una hora" no se sostiene, confirmado vía CloudTrail

He confirmado vía `aws cloudtrail lookup-events` que la cifra de "más de una hora" que había registrado antes para el colgado del `systemctl reboot` es incorrecta. `StopInstances` (`i-0d38e3a088f7c4893`, usuario `dpaniagua`, consola) se ejecutó a las 01:20:17 UTC con `skipOsShutdown: true` (fuerza el apagado, sin esperar el shutdown ordenado del SO) — solo ~4,5 minutos después del congelamiento (01:15:43). `StartInstances` completó exitosamente a las 01:24:39 UTC (`previousState: stopped`), consistente con la línea de kernel del boot nuevo a las 01:24:51. Tiempo total desde el congelamiento hasta el boot nuevo: ~9 minutos, confirmado por dos fuentes independientes (timestamps de boot en syslog/journald, y timestamps de CloudTrail) — no "más de una hora". No existe ningún evento `RebootInstances` — la recuperación fue un ciclo de stop/start forzado por consola, no un reinicio.

## 2026-08-13 — Identificado archivo compose incorrecto durante validación, corregido

Al validar el compose del stack (`docker compose config`) encontré un error de YAML (`healthcheck` mal ubicado dentro de `depends_on.mongo`) en `/home/ubuntu/scritps/graylog/graylog/docker-compose.yml`. Tras revisar ese archivo en detalle (heap de OpenSearch en `1g`, límite de memoria intentado en `2G`, un secreto de `OPENSEARCH_INITIAL_ADMIN_PASSWORD` hardcodeado en texto plano) noté que no coincidía con los números ya documentados en este ticket (`2g`/`6G`). Confirmé vía `docker inspect opensearch --format '{{index .Config.Labels "com.docker.compose.project.config_files"}}'` que el archivo real que creó los contenedores en ejecución es `graylog-compose.yml`, no `docker-compose.yml` — este último está sin uso, es una versión vieja/divergente. Verifiqué `graylog-compose.yml` directamente y confirmé que coincide exactamente con lo ya documentado (heap `2g`, límite `6G`/`4G`, `deploy:` ignorado bajo `docker compose up`) — sin necesidad de corregir nada de lo ya registrado. El archivo `docker-compose.yml` sin uso queda como hallazgo secundario — recomendado eliminarlo o limpiar sus secretos hardcodeados, dado que su nombre casi idéntico causó esta confusión.
