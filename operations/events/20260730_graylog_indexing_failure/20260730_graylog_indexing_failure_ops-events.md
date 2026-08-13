# Eventos — 20260730_graylog_indexing_failure

## 2026-07-31 — Apertura del evento, separado de 20260729_graylog_sin_datos

He separado el seguimiento de las fallas de indexado (`event_original` excediendo el límite de término de Lucene en `business__6`) en su propio evento, ya que la causa raíz de este problema ya está confirmada en `20260729_graylog_sin_datos` (C34-C39) de forma independiente a la investigación aún abierta sobre la caída de volumen y el reinicio de Logstash. He creado el archivo de investigación con los hechos ya confirmados en el evento original como punto de partida.

## 2026-07-31 — Reconciliación del conteo de fallas de indexado

**Comando:** C40-C43 — Conteo de fallas vía API (`/api/system/indexer/failures/count`, tres ventanas `since`) y muestra de las 5 fallas más recientes
**Resultado:**
C40 (desde 2000, equivalente a total histórico): 62.874. C41 (desde el cliff, 2026-07-28 06:00 UTC): 62.874. C42 (desde hace ~1 hora): 62.931. C43: las 5 fallas más recientes están todas timestampeadas en el mismo segundo de la consulta (2026-07-31T12:18:46), sobre el índice `business__7` (rotado desde `business__6`), con la misma firma de error que antes (término inmenso en `event_original`, 131.193-131.735 bytes).

He verificado que los tres conteos (total, desde el cliff, y de la última hora) son prácticamente idénticos entre sí, lo cual solo es posible si la totalidad del historial de fallas visible actualmente corresponde a aproximadamente la última hora — es decir, la tasa de fallas ha aumentado de forma marcada respecto a las ~1.164/hora medidas el 2026-07-30, a un orden de magnitud de decenas por segundo. He confirmado además que las fallas siguen activas en este momento y que la causa raíz (registros individuales de Business que exceden el límite de Lucene en el campo `event_original`) no ha cambiado, solo el índice de destino, por rotación normal de Graylog. La cifra de 88.120 reportada desde el panel de UI no es directamente comparable a estos conteos por posibles diferencias de alcance/caché, pero la evidencia de esta sesión indica que el problema empeoró, no mejoró, desde la medición anterior.

## 2026-07-31 — Descarte del tamaño de registro individual como causa; confirmación del bug real en el pipeline

**Comando:** C44-C45 — Consulta a Log Analytics (workspace `SmartFranCloudPro`) de los registros más largos de Business en la misma ventana de las fallas de C43
**Resultado:**
Los registros individuales más largos encontrados (entradas EF Core `Executed`/`Executing DbCommand`, con `EnableSensitiveDataLogging` incluido) miden 2.918, 2.912, 2.398, 2.398 y 2.393 caracteres — muy por debajo del límite de 32.766 bytes de Lucene, y ~45 veces más chico que el término inmenso observado (131.193+ bytes).

He descartado el tamaño de un registro individual de Business, incluso con `EnableSensitiveDataLogging` activo, como causa suficiente por sí sola del error de indexado. Al decodificar el prefijo de 30 bytes que devuelve OpenSearch en el error (`{"records": [{ "time": "2026-0...`), he confirmado que el valor real de `event_original` en los documentos que fallan corresponde al formato de lote completo de Azure Diagnostic Settings, no a un único registro.

**Comando:** C46 — Lectura completa de `/etc/logstash/conf.d/azure-eventhub-to-graylog.conf` en `smartfran-graylog-pro`
**Resultado:**
El fix del 2026-07-02 (líneas 51-67) solo sobrescribe `event_original` dentro de un bloque `if record.is_a?(Hash)`, sin rama `else`. Si `records` no llega como Hash en ese punto (fallo de parseo JSON, fallo del filtro `split`, u otra forma inesperada), el bloque completo se omite en silencio y `event_original` conserva su valor de ingesta (`decorate_events => true`), que es el lote completo sin dividir.

He confirmado la causa raíz: no es una reversión del fix de 2026-07-02, sino una guarda condicional sin manejo de excepción — el código de la corrección sigue presente y correcto para el camino feliz, pero no cubre el caso en que las condiciones previas (parseo JSON, split) no se cumplen, y no hay ninguna métrica ni tag que indique cuándo esto ocurre.

## 2026-07-31 — Aplicación del fix

He confirmado con el usuario que esta corrección corresponde a Operaciones/SRE, no a Desarrollo, ya que el pipeline de Logstash es infraestructura propia del proyecto Graylog, no código de aplicación.

He preparado un parche de dos cambios sobre `azure-eventhub-to-graylog.conf`: (1) una rama `else` en la guarda existente que agrega el tag `event_original_guard_skipped` para dar visibilidad a futuro sobre cuándo se omite la corrección original, y (2) un filtro Ruby incondicional, ejecutado justo antes del output `gelf`, que trunca `event_original` a 30.000 bytes si lo excede, independientemente de la causa — esto cierra la clase de error completa sin depender de identificar la condición exacta que dispara la guarda.

He guardado una copia redactada (sin credenciales) del archivo parcheado en `settings/prod-sfcloud-monitoreo/etc/logstash/conf.d/azure-eventhub-to-graylog.conf`, reflejando el estado objetivo del pipeline.

**Comando:** C47 — Validación de sintaxis (`logstash --path.settings /etc/logstash -t`)
**Resultado:**
`Configuration OK`. También se observó que el pipeline tiene configurado `pipeline.ecs_compatibility: v8` a nivel de pipeline (no en este archivo `.conf`).

He validado que el parche es sintácticamente correcto antes de aplicarlo. He dejado señalado como riesgo abierto, no confirmado, que el modo `ecs_compatibility: v8` podría implicar un campo `[event][original]` anidado distinto del campo plano `event_original` que manipula este filtro — de ser así, el parche podría no estar actuando sobre el campo real que llega al output GELF. Decidí no investigar esto de forma estática y en su lugar verificarlo de forma directa tras el reinicio, comparando la tasa de fallas antes y después.

**Comando:** C48 — Reinicio de Logstash (`systemctl restart logstash`)
**Resultado:**
Servicio activo (`active (running)`), reiniciado a las 2026-07-31T14:06:33Z.

He reiniciado el servicio para aplicar el parche. Al momento de la verificación el servicio llevaba menos de un segundo activo, insuficiente para confirmar que el consumidor de Event Hub ya reanudó el consumo — pendiente confirmar con una espera adicional y el conteo de fallas posterior al reinicio (C49).

## 2026-07-31 — Verificación post-parche: el fix no tuvo efecto

**Comando:** C49-C50 — Conteo de fallas y muestra de las más recientes, ventana posterior a la reanudación del consumo (14:07:00Z en adelante)
**Resultado:**
18.186 fallas en ~522 segundos (~34,8 fallas/segundo). Muestra de las fallas más recientes (14:13:54Z, 7+ minutos después del reinicio): tamaños sin cambios (131.425-131.756 bytes), misma firma de error, mismo formato de lote completo.

He confirmado que el parche aplicado (rama `else` con tag más truncado incondicional sobre el campo plano `event_original`) no tuvo ningún efecto medible sobre la tasa de fallas ni sobre el tamaño de los documentos que siguen fallando. Esto descarta que el campo plano `event_original` sea el que efectivamente llega al output GELF — el pipeline tiene activo `pipeline.ecs_compatibility: v8`, lo cual sugiere que existe un campo anidado `[event][original]` (ECS), distinto del campo plano que manipula este filtro, y que es ese campo anidado el que realmente se está indexando sin truncar.

## 2026-07-31 — Incidente: caída del servicio por diagnóstico rubydebug, recuperación

**Comando:** C51-C52 — Filtro Ruby de diagnóstico estructural (solo tamaños, sin contenido) más habilitación temporal de `stdout { codec => rubydebug }`
**Resultado:**
`java.lang.OutOfMemoryError: Java heap space` a las 14:20:19Z, seguido de un ciclo de reinicios (3 reinicios en ~2 minutos, PIDs 599301/599539/599680).

He habilitado `rubydebug` para confirmar de forma más directa la existencia del campo anidado `[event][original]`, e intentó imprimir eventos completos de cientos de KB vía `amazing_print`, lo cual agotó el heap de 1GB de la JVM y dejó el servicio en un ciclo de caídas y reinicios. Antes de la caída se alcanzó a ver un fragmento con indentación consistente con un campo anidado (`"original" => "{\"records\": [...`), lo cual es evidencia parcial a favor de la teoría del campo ECS anidado, pero no una confirmación completa. He decidido no volver a usar `rubydebug` sin acotar fuertemente el volumen/tamaño capturado.

**Comando:** C53-C54 — Recuperación: restauración de la configuración original (`azure-eventhub-to-graylog.old`, respaldo previo a cualquier cambio de esta sesión) y reinicio
**Resultado:**
`Configuration OK`; servicio estable 30+ segundos después del reinicio, PID único, sin ciclo de reinicios, consumidor de Event Hub reconectado normalmente.

He priorizado la estabilidad del pipeline por sobre un fix incompleto y no verificado — no se encontró ningún archivo de respaldo `.bak-debug-*` en el host (pendiente investigar por qué), por lo que restauré desde el único respaldo confirmado disponible (`azure-eventhub-to-graylog.old`, previo a los cambios de hoy). Esto revirtió tanto el parche de la guarda/truncado como el diagnóstico agregado. Al cierre de esta sesión, `smartfran-graylog-pro` corre su configuración original previa al 2026-07-31 — la falla de indexado sigue activa y sin corregir, y el sistema está estable.
