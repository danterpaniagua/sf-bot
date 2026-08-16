# Ticket — GITIN-1827

Relacionado con GITIN-1821.

**Tags:** `Operaciones`, `Graylog`, `Obserbavilidad`

**Resumen:** al intentar agregar el campo `MessageId` a la configuración de NXLog de las VM de relay de correo `SFCG-SMTP-01`/`SFCG-SMTP-02` (`192.168.50.161`/`.162`, servicio `SF-SMTPRL`), se detectó que los mensajes no estaban llegando a Graylog. La investigación inicial se centró en la configuración de NXLog sin encontrar causa ahí — resultó estar correcta en todas sus revisiones. La causa real es una interrupción intermitente del contenedor de OpenSearch que sostiene esta instancia de Graylog (`sf-monitoreo.smartfran.com`), no relacionada con NXLog, que afecta la ingesta de logs de múltiples servicios (SF-SMTPRL, SmartPedidos platform-service, WAF, y otros que comparten el mismo cluster).

**Tabla resumen:**

| Campo | Valor |
|---|---|
| Ticket Jira | GITIN-1827 |
| ID alerta | — (detectado durante trabajo de instrumentación, no por alerta automática) |
| Sistema | Graylog / OpenSearch — `sf-monitoreo.smartfran.com` (Docker: `graylog`, `opensearch`, `mongo`) |
| Severidad | Alto |
| Detectado | 2026-08-11/12 |
| Resuelto | Parcial |
| Responsable | (SRE) |

**Causa raíz:** los mensajes dejaron de llegar a Graylog durante la ventana en que la VM `sf-monitoreo.smartfran.com` se reinició (`2026-08-12`, boot confirmado a las `01:24:46/51` vía `last reboot -F` y `kern.log`). Secuencia exacta, confirmada con dos fuentes independientes (syslog/journald del host, y `aws cloudtrail lookup-events`):

- `01:15:43 UTC` — un `systemctl reboot` inicia un apagado ordenado: decenas de servicios se detienen en secuencia normal, incluyendo el inicio de la detención de `dockerd` (`Processing signal 'terminated'`).
- El apagado se congela por completo en ese punto: no existe **ningún** registro de log — de ningún subsistema, no solo Docker — entre `01:15:43` y `01:24:51`. Esto apunta a que todo el sistema se congeló, coincidiendo exactamente con el paso en que Docker debía cerrar de forma prolija el contenedor `opensearch`, que sostiene un índice de 472.8 GB (`graylog_299`) sin límite real de memoria de Docker y con el heap de la JVM sin lock (ver hallazgo de configuración abajo).
- `01:20:17 UTC` — ante el colgado, se forzó `StopInstances` desde la consola de AWS con `skipOsShutdown: true` (fuerza el corte, sin esperar el apagado ordenado del SO).
- `01:24:39 UTC` — `StartInstances` completa exitosamente (`previousState: stopped`), consistente con la línea de kernel del boot nuevo a las `01:24:51`.

Tiempo total desde el congelamiento hasta el boot nuevo: **~9 minutos** — no "más de una hora" como se había registrado en una nota anterior de este mismo ticket; esa cifra queda corregida por esta evidencia. No existe ningún evento `RebootInstances` en CloudTrail — la recuperación fue un ciclo de stop/start forzado por consola, no un reinicio.

**Configuración confirmada como causa habilitante (no solo sospecha):** revisado `graylog-compose.yml` — el archivo real que efectivamente creó los contenedores en ejecución, confirmado vía `docker inspect opensearch --format '{{index .Config.Labels "com.docker.compose.project.config_files"}}'` (existe un `docker-compose.yml` homónimo en el mismo directorio, pero está sin uso — memoria más baja, un bug propio de YAML, secretos hardcodeados en texto plano; recomendado eliminarlo o al menos limpiar los secretos, dado que su nombre casi idéntico ya generó confusión real durante esta investigación). En `graylog-compose.yml`: `bootstrap.memory_lock: true` está seteado en `opensearch` sin el bloque `ulimits: memlock` correspondiente (el lock de memoria no toma efecto). Además, los límites `deploy.resources.limits` (`6G` en `opensearch`, `4G` en `mongo`) **no aplican fuera de Docker Swarm** — este stack corre con `docker compose up` simple, no `docker stack deploy`, por lo que esos límites nunca estuvieron realmente en efecto. Es decir: `opensearch` no tenía techo real de memoria impuesto por Docker, y su heap tampoco estaba protegido contra swap. No se encontró una línea literal de `oom-killer` del kernel (nada se logueó durante el congelamiento en sí, ver arriba), pero el mecanismo es preciso y coherente, no solo circunstancial.

Cada contenedor venía corriendo sin interrupción desde hacía ~186 días (`2026-02-06` → `2026-08-12`) hasta este reinicio — es el único reinicio registrado en toda la vida del stack aparte del arranque inicial. Tras el reinicio, los tres contenedores volvieron a levantar limpiamente (`RestartCount=0`, arranque único) y llevan corriendo sanos desde entonces, con el cluster de OpenSearch en `green`.

El cluster de OpenSearch es de un solo nodo (`discovery.type: single-node`); durante la recuperación posterior a cualquier reinicio, la totalidad de sus índices queda momentáneamente en estado `red` (shards primarios no asignados) mientras se reinicializan uno por uno. Cualquier mensaje enviado por NXLog durante esa ventana se pierde sin ningún error visible del lado del emisor — UDP no tiene confirmación de entrega — lo cual se manifiesta exactamente como "el mensaje nunca llegó", indistinguible de un problema de red o configuración en el origen.

**Hallazgos:**

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 (resuelto) | La VM se congeló por completo (~9 min, `01:15:43`-`01:24:51`, confirmado por syslog/journald y CloudTrail) durante el apagado ordenado por `systemctl reboot`, justo al llegar al paso de detener Docker — coincide con que `opensearch` no tenía techo real de memoria (`deploy.resources.limits` ignorado fuera de Swarm) ni heap protegido contra swap (`bootstrap.memory_lock` sin `ulimits`). Se forzó `StopInstances`/`StartInstances` desde la consola de AWS. Recuperación posterior limpia (`RestartCount=0`). Cada vez que el cluster se reinicie, queda no disponible por completo durante la recuperación (single-node, sin réplicas). | Alto — causa habilitante confirmada, fix no aplicado todavía |
| H2 (resuelto) | Los índices `graylog_299` (Default Stream, 472.8 GB / ~1.45 mil millones de documentos) y `sp_platform__50` (SmartPedidos platform-service) estaban en el límite por defecto de OpenSearch de 1000 campos de mapeo por índice (`index.mapping.total_fields.limit`), confirmado vía `_cluster/allocation/explain` y el log de fallas de indexación (`Limit of total fields [1000] has been exceeded`, 32.448 fallos en 24 h, 177.356 acumulados). Bloqueaba la creación de nuevos índices en esas series de rotación (`graylog_300`, `sp_platform__51`, etc.) y cualquier mensaje que introdujera un campo nuevo no visto antes. Límite elevado a 2000 en ambos índices (2026-08-12). | Resuelto |
| H3 | `graylog_299` está muy por fuera de tamaño respecto a sus pares (`graylog_280`-`298`, ~3-4 GB cada uno) — no está rotando con normalidad, probablemente porque no puede crearse `graylog_300` mientras el mapeo esté en el límite de 1000 campos (H2). | Alto |
| H4 | Cero réplicas configuradas en todos los índices del cluster (`rep 0`) — sin redundancia; si algún shard resultara realmente corrupto (no solo temporalmente no asignado), no habría copia de respaldo. | Medio — riesgo estructural, sin pérdida de datos confirmada en este evento |
| H5 | Índice `aws_logs_51` rechaza documentos con `mapper_parsing_exception` — el campo `msg_rest_status` está mapeado como `long`, pero algunos documentos envían el string literal `"error"`, lo cual OpenSearch rechaza por conflicto de tipo (mecanismo distinto de H2). Fuente del campo/servicio de origen sin confirmar todavía. | Alto — falla activa y en curso, servicio de origen sin identificar |
| H6 (resuelto) | Agregada extracción de `$DeliveryStatus` en la configuración de NXLog de `SFCG-SMTP-01`/`SFCG-SMTP-02` — captura el texto de estado de SMTPDeliverer (ej. `Message delivery thread completed.`) de forma independiente de `$MessageId`, para poder detectar más rápido una futura repetición de este incidente comparando el volumen de eventos de hMailServer contra lo que efectivamente llega a Graylog. Desplegado y confirmado en ambas VM con datos reales; un bug menor de comilla sobrante en el valor capturado fue encontrado y corregido en el mismo ciclo. | Resuelto |
| H7 | Un cuarto tipo de fallo de indexado, mismo mecanismo que H5 pero campo distinto (`msg_branch_id`, `mapper_parsing_exception` por el string `"unknown"`), fue identificado durante este ticket pero **separado a GITIN-1854** (`operations/events/20260813_platform-service-branch-id-unknown-mapping-error/`) — causa raíz confirmada como bug de aplicación en `platforms-service`, fuera del alcance de este ticket. | Ver GITIN-1854 |

**Recursos afectados:**

| Recurso | Detalle |
|---|---|
| `opensearch` (Docker, `sf-monitoreo.smartfran.com`) | Reinicio del proceso ~2026-08-12 01:24:54 UTC |
| Índice `graylog_299` | 1000/1000 campos de mapeo, 472.8 GB, no rota con normalidad |
| Índice `sp_platform__50` | 1000/1000 campos de mapeo — SmartPedidos platform-service, afectado por la misma causa |
| VM `SFCG-SMTP-01` (`192.168.50.161`) / `SFCG-SMTP-02` (`192.168.50.162`) | Sin causa propia — afectadas como consumidoras del mismo Graylog/OpenSearch |

**Comandos ejecutados:** ver `scripts.sh` (Linux, `sf-monitoreo`) y `scripts.ps1` (PowerShell, VM de relay).

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | `df -h` | Descartar presión de disco en el filesystem raíz |
| C2 | `docker ps` | Confirmar que `sf-monitoreo.smartfran.com` corre el stack Graylog/OpenSearch/MongoDB |
| C3 | `docker inspect opensearch` | Confirmar `OOMKilled` y `StartedAt` del contenedor |
| C4 | `docker logs opensearch` (grep) | Encontrar el evento de reinicio y su horario exacto |
| C5 | `curl .../_mapping` | Contar campos de mapeo por índice |
| C6 | `curl .../_cat/indices?v` | Detectar el tamaño anómalo de `graylog_299` |
| C7 | `curl .../_cluster/health` | Confirmar estado real del cluster tras la recuperación |
| C8 | `curl .../_cluster/allocation/explain` | Confirmar que un shard puntual estaba sano, no corrupto |
| C9 | `curl .../api/system/indexer/failures` | Contar y agrupar fallas de indexación por mensaje de error |
| C10 (PowerShell) | Envío UDP de prueba desde `SFCG-SMTP-01` | Confirmar alcance de red hacia Graylog, independiente de NXLog/hMailServer |
| C11 (PowerShell) | Listado de `hMailServer\Logs\` | Confirmar volumen de archivos históricos coincidiendo con el wildcard de NXLog (línea de investigación descartada) |

**Acciones propuestas:**

1. ~~Confirmar qué llevó al congelamiento previo al reinicio de la VM~~ — completado 2026-08-13: congelamiento total del sistema (~9 min) confirmado por syslog/journald y CloudTrail, coincidiendo con el paso de detención de Docker/OpenSearch (ver Causa raíz).
2. **(SRE, pendiente)** Corregir `graylog-compose.yml`: reemplazar el bloque `deploy.resources.limits` (ignorado fuera de Swarm, nunca estuvo en efecto) por `mem_limit`/`mem_reservation` (claves que sí aplican bajo `docker compose up`), y agregar `ulimits: memlock: soft: -1, hard: -1` para que `bootstrap.memory_lock: true` funcione realmente. Requiere recrear los contenedores `opensearch`/`mongo` — ventana de mantenimiento planificada, no aplicar de forma casual (el propio reinicio del contenedor reproduce brevemente el síntoma de este ticket).
3. ~~Aplicar `index.mapping.total_fields.limit` más alto en `graylog_299` y `sp_platform__50`~~ — completado 2026-08-12 (`{"acknowledged":true}`, límite elevado a 2000 en ambos). Verificar que no haya otros índices en la lista de fallas de indexación acercándose al mismo límite.
4. Definir una política de gestión de campos de mapeo para evitar que los índices vuelvan a acercarse al límite de 1000 campos.
5. Evaluar agregar réplicas (`rep 1`) si los recursos del host lo permiten.
6. ~~(SRE) Corregir el error de tipeo `$Cardinaluty` (debería ser `$Cardinality`) en la configuración de NXLog de ambas VM de relay~~ — completado 2026-08-12 en `SFCG-SMTP-01` y `SFCG-SMTP-02`. (Nota: se redesplegó `$MessageId` en ambas VM en un paso anterior y se confirmó funcionando correctamente en Graylog.)

**Hallazgos secundarios:**

- El extractor `mobile_json_extractor` y el input `TXT_UDP` de Graylog son infraestructura compartida, reutilizada originalmente para tráfico IIS/ClubSite (`w3c_parser_mobile`) y luego también para hMailServer — nombres heredados que no reflejan el uso actual, confuso para diagnósticos futuros.
- Existe un `docker-compose.yml` sin uso en el mismo directorio que el `graylog-compose.yml` real (`/home/ubuntu/scritps/graylog/graylog/`) — versión vieja/divergente (memoria más baja, un bug de YAML propio con `healthcheck` mal ubicado, secretos de `OPENSEARCH_INITIAL_ADMIN_PASSWORD` hardcodeados en texto plano). Su nombre casi idéntico al archivo real causó confusión real durante esta misma investigación. Recomendado eliminarlo o al menos limpiar los secretos hardcodeados.
