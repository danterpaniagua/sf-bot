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

**Causa raíz:** los mensajes dejaron de llegar a Graylog durante la ventana en que la VM `sf-monitoreo.smartfran.com` se reinició (`2026-08-12`, boot confirmado a las `01:24:46` vía `last reboot -F`). El apagado de los contenedores previo al reinicio fue ordenado, no una caída/colgado: el log de `dockerd` (`journalctl -u docker`) muestra la secuencia de apagado a las `01:15:43-56` con `daemonShuttingDown=true` — `mongodb` cerró limpio (`exitStatus 0`), `opensearch` recibió `SIGTERM` correctamente (`exitStatus 143`), `graylog` no llegó a cerrar dentro del tiempo de gracia y fue forzado con `SIGKILL` (`exitStatus 137`, detalle menor, no indica un problema mayor). `journalctl -k` no muestra ningún evento de OOM-killer del kernel ni en el boot actual ni en el anterior. Cada contenedor venía corriendo sin interrupción `execDuration≈4474h` (~186 días, desde el 2026-02-06) hasta este reinicio — es el único reinicio registrado en toda la vida del stack aparte del arranque inicial. Tras el reinicio, los tres contenedores volvieron a levantar limpiamente (`RestartCount=0`, arranque único, no un ciclo de reinicios de Docker) y llevan **10 horas corriendo sanos** al momento de este chequeo, con el cluster de OpenSearch en `green`, `999/999` shards activos.

El cluster de OpenSearch es de un solo nodo (`discovery.type: single-node`); durante la recuperación posterior a cualquier reinicio (`Cluster is not recovered yet` → `recovered [257] indices into cluster_state`, `01:25:21` UTC), la totalidad de sus índices queda momentáneamente en estado `red` (shards primarios no asignados) mientras se reinicializan uno por uno, y con el volumen de datos actual (un solo índice, `graylog_299`, alcanza 472.8 GB) esa recuperación toma un tiempo no despreciable. Cualquier mensaje enviado por NXLog durante esa ventana se pierde sin ningún error visible del lado del emisor — UDP no tiene confirmación de entrega — lo cual se manifiesta exactamente como "el mensaje nunca llegó", indistinguible de un problema de red o configuración en el origen.

**Queda sin confirmar** por qué los servicios parecían no responder antes del reinicio de la VM (motivo original por el que se decidió reiniciar) — no hay evidencia de un colgado o caída previa en los logs revisados hasta ahora, solo la secuencia de apagado ordenada. No se debe asumir una causa hasta confirmarla. Riesgo ya conocido, independiente de este evento puntual: `bootstrap.memory_lock: true` está configurado sin el bloque `ulimits: memlock` correspondiente, y el heap de OpenSearch (`-Xms2g -Xmx2g`) corre habitualmente cerca del límite de memoria del contenedor (6 GB).

**Hallazgos:**

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | La VM se reinició (`2026-08-12 01:24:46`) tras 186 días de los contenedores corriendo sin interrupción. El apagado previo fue ordenado (sin OOM, sin colgado visible en los logs) y la recuperación posterior fue limpia (`RestartCount=0`, sanos desde hace 10 h). Queda sin confirmar por qué se decidió reiniciar la VM en primer lugar. Cada vez que el cluster se reinicie, queda no disponible por completo durante la recuperación (single-node, sin réplicas). | Medio — sin causa de fondo confirmada |
| H2 (resuelto) | Los índices `graylog_299` (Default Stream, 472.8 GB / ~1.45 mil millones de documentos) y `sp_platform__50` (SmartPedidos platform-service) estaban en el límite por defecto de OpenSearch de 1000 campos de mapeo por índice (`index.mapping.total_fields.limit`), confirmado vía `_cluster/allocation/explain` y el log de fallas de indexación (`Limit of total fields [1000] has been exceeded`, 32.448 fallos en 24 h, 177.356 acumulados). Bloqueaba la creación de nuevos índices en esas series de rotación (`graylog_300`, `sp_platform__51`, etc.) y cualquier mensaje que introdujera un campo nuevo no visto antes. Límite elevado a 2000 en ambos índices (2026-08-12). | Resuelto |
| H3 | `graylog_299` está muy por fuera de tamaño respecto a sus pares (`graylog_280`-`298`, ~3-4 GB cada uno) — no está rotando con normalidad, probablemente porque no puede crearse `graylog_300` mientras el mapeo esté en el límite de 1000 campos (H2). | Alto |
| H4 | Cero réplicas configuradas en todos los índices del cluster (`rep 0`) — sin redundancia; si algún shard resultara realmente corrupto (no solo temporalmente no asignado), no habría copia de respaldo. | Medio — riesgo estructural, sin pérdida de datos confirmada en este evento |
| H5 | Índice `aws_logs_51` rechaza documentos con `mapper_parsing_exception` — el campo `msg_rest_status` está mapeado como `long`, pero algunos documentos envían el string literal `"error"`, lo cual OpenSearch rechaza por conflicto de tipo (mecanismo distinto de H2). Fuente del campo/servicio de origen sin confirmar todavía. | Alto — falla activa y en curso, servicio de origen sin identificar |

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

1. Confirmar qué llevó a decidir el reinicio de la VM — los logs revisados (dockerd, kernel) no muestran evidencia de colgado, caída ni OOM antes del apagado ordenado a las 01:15; sin esa confirmación, no asumir una causa de fondo.
2. Corregir la configuración `bootstrap.memory_lock`/`ulimits: memlock` en el `docker-compose` de OpenSearch si el punto anterior confirma presión de memoria como causa.
3. ~~Aplicar `index.mapping.total_fields.limit` más alto en `graylog_299` y `sp_platform__50`~~ — completado 2026-08-12 (`{"acknowledged":true}`, límite elevado a 2000 en ambos). Verificar que no haya otros índices en la lista de fallas de indexación acercándose al mismo límite.
4. Definir una política de gestión de campos de mapeo para evitar que los índices vuelvan a acercarse al límite de 1000 campos.
5. Evaluar agregar réplicas (`rep 1`) si los recursos del host lo permiten.
6. ~~(SRE) Corregir el error de tipeo `$Cardinaluty` (debería ser `$Cardinality`) en la configuración de NXLog de ambas VM de relay~~ — completado 2026-08-12 en `SFCG-SMTP-01` y `SFCG-SMTP-02`. (Nota: se redesplegó `$MessageId` en ambas VM en un paso anterior y se confirmó funcionando correctamente en Graylog.)

**Hallazgos secundarios:**

- El extractor `mobile_json_extractor` y el input `TXT_UDP` de Graylog son infraestructura compartida, reutilizada originalmente para tráfico IIS/ClubSite (`w3c_parser_mobile`) y luego también para hMailServer — nombres heredados que no reflejan el uso actual, confuso para diagnósticos futuros.
