# Fallas de indexado en Graylog (SmartCloud) — término inmenso en event_original, Business

**Tags:** SmartCloud, Graylog, Azure, Obserbavilidad, SRE, PROD

## Resumen

Desde el 2026-07-28 06:00 UTC, Graylog (instancia dedicada de SmartCloud, `smartfran-graylog-pro`) presenta fallas activas de indexado sobre el stream de Business: documentos individuales exceden el límite de 32.766 bytes por término de OpenSearch/Lucene en el campo `event_original`, con tamaños observados de hasta 131KB+. Esto implica pérdida de datos en curso — los documentos que fallan no quedan indexados ni son buscables. La tasa de fallas escaló de forma marcada entre la detección inicial (~1.164/hora, medido 2026-07-30) y el momento de este reporte (~35/segundo, medido 2026-07-31). Se identificó la causa raíz en el pipeline de Logstash y se desplegó una mitigación el 2026-07-31, con una señal temprana positiva (0 fallas nuevas en los primeros ~79 segundos posteriores al despliegue), pendiente de confirmación con una ventana de observación más prolongada antes de considerar el incidente resuelto.

## Tabla resumen

| Campo | Valor |
|---|---|
| Jira | [GITIN-1730](https://smartit-ar.atlassian.net/browse/GITIN-1730) |
| ID alerta | N/A — identificado durante la investigación de `20260729_graylog_sin_datos`, separado a evento propio |
| Sistema | Graylog SmartCloud (`smartfran-graylog-pro`) — índices `business__6`/`business__7` |
| Severidad | Alta — pérdida de datos activa |
| Detectado | 2026-07-30 (fallas encontradas dentro de otra investigación); evento propio abierto 2026-07-31 |
| Resuelto | No — mitigación desplegada 2026-07-31, señal temprana positiva, pendiente confirmación de estabilidad prolongada |
| Responsable | Dante Paniagua |

## Causa raíz

El fix aplicado el 2026-07-02 (que reescribe `event_original` con el JSON de un único registro, en lugar del lote completo de Azure Event Hub) depende de una guarda condicional (`if record.is_a?(Hash)`) sin rama alternativa. Cuando el campo `records` no llega como un Hash en ese punto del pipeline (por fallo de parseo JSON, fallo del filtro `split`, u otra forma inesperada — condición exacta no determinada), el bloque completo se omite en silencio y `event_original` conserva su valor de ingesta original: el lote completo sin dividir, generado por `decorate_events => true` en el input `azure_event_hubs`. Esto reproduce, para un subconjunto de documentos, el mismo patrón de falla del incidente del 2026-07-02, sin ser una reversión del fix original — el código de la corrección sigue presente y correcto para el camino esperado.

Adicionalmente, el pipeline tiene activo `pipeline.ecs_compatibility: v8` a nivel de configuración (no visible en el archivo `.conf`, debe estar en `pipelines.yml`/`logstash.yml`). Esto sugiere la posible existencia de un campo anidado `[event][original]` (ECS), distinto del campo plano `event_original` que manipula el filtro del pipeline — evidencia parcial (no concluyente) obtenida de una captura de diagnóstico antes de que esta causara una caída del servicio por agotamiento de memoria (ver Hallazgos). Una primera mitigación que truncaba únicamente el campo plano no tuvo ningún efecto medible sobre la tasa de fallas, lo cual es consistente con esta hipótesis.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Fallas de indexado activas desde 2026-07-28 06:00 UTC — documentos individuales de Business exceden el límite de 32.766 bytes de Lucene en el campo `event_original`, hasta 131KB+ observados | Alto |
| H2 | Tasa de fallas escaló de ~1.164/hora (medido 2026-07-30) a ~35/segundo (medido 2026-07-31) — sin causa confirmada para el aumento | Alto |
| H3 | Causa raíz: guarda condicional sin rama alternativa en el fix del 2026-07-02 — cuando `records` no es un Hash en ese punto, `event_original` conserva el lote completo de ingesta sin que se registre ningún error o métrica | Alto |
| H4 | Posible campo anidado `[event][original]` (ECS), distinto del campo plano manipulado por el filtro, dado `pipeline.ecs_compatibility: v8` activo — evidencia parcial, no confirmada de forma concluyente | Medio |
| H5 | Mitigación desplegada 2026-07-31: truncado incondicional de ambos campos (`event_original` plano y `[event][original]` anidado) antes del output GELF — señal temprana positiva (0 fallas nuevas en ~79 segundos posteriores al despliegue), pendiente confirmación con ventana de observación más prolongada | Alto |
| H6 | Descartado como causa suficiente por sí sola: tamaño de un registro individual de Business, incluso con `EnableSensitiveDataLogging(true)` activo (máximo observado ~2,9KB, ~45 veces menor al término inmenso más pequeño registrado) — hallazgo de seguridad independiente, no relacionado a la causa de este incidente | Bajo |
| H7 | Durante el diagnóstico, la habilitación de `stdout { codec => rubydebug }` para inspeccionar eventos completos provocó un `OutOfMemoryError` y un ciclo de reinicios del servicio Logstash — revertido, sin impacto sostenido, pero a evitar como método de diagnóstico a este volumen/tamaño de evento | Bajo |

## Recursos afectados

| Componente | Impacto |
|---|---|
| Graylog `smartfran-graylog-pro` — índices `business__6`, `business__7` | Pérdida activa de datos por fallas de indexado desde 2026-07-28 06:00 UTC |
| Servicio Logstash (`smartfran-graylog-pro`) | Modificado — mitigación desplegada 2026-07-31; sujeto a un incidente de inestabilidad temporal durante el diagnóstico (revertido sin impacto sostenido) |
| `SmartFran-Cloud-Business-PRO` (App Service) | Origen de los registros individuales; también sujeto al hallazgo secundario de `EnableSensitiveDataLogging` (H6) |

## Comandos ejecutados

Ver `20260730_graylog_indexing_failure_scripts.sh` para el detalle completo. Resumen:

| # | Comando / Script | Propósito |
|---|---|---|
| C40-C43 | Graylog REST API — conteo y muestra de fallas de indexado | Reconciliar la cifra reportada por UI contra el método usado en `20260729_graylog_sin_datos`, confirmar que las fallas siguen activas |
| C44-C45 | Azure CLI — consulta a Log Analytics | Descartar el tamaño de un registro individual (incluso con `EnableSensitiveDataLogging`) como causa suficiente |
| C46 | ⚠️ `az vm run-command` (lectura únicamente) | Obtener la configuración completa del pipeline de Logstash, no solo la línea de `event_original` |
| C47-C50 | ⚠️ Parche v1 (SSH) — rama `else` con tag + truncado incondicional del campo plano `event_original`, reinicio y verificación | Primer intento de mitigación — sin efecto medible sobre la tasa de fallas |
| C51-C52 | ⚠️ Diagnóstico estructural + `rubydebug` (SSH) | Confirmar existencia de campo anidado `[event][original]` — causó `OutOfMemoryError` y ciclo de reinicios |
| C53-C54 | ⚠️ Restauración de configuración original y reinicio (SSH) | Recuperar estabilidad del servicio tras el incidente de C52 |
| C55-C58 | ⚠️ Parche v2 (SSH) — truncado incondicional de ambos campos (`event_original` y `[event][original]`), reinicio y verificación | Mitigación actualmente desplegada — señal temprana positiva |

## Acciones propuestas

1. (SRE) Confirmar la efectividad de la mitigación desplegada el 2026-07-31 con una ventana de observación prolongada (varias horas, no solo los ~79 segundos verificados hasta el momento) antes de dar este incidente por cerrado.
2. (SRE) Investigar por qué no se generó el archivo de respaldo `.bak-debug-*` esperado durante el primer intento de parche, para asegurar que los respaldos automáticos sean confiables en futuras intervenciones sobre este host.
3. (SRE) Una vez confirmada la mitigación de forma sostenida, evaluar si el tag de diagnóstico `event_original_guard_skipped` aporta valor de observabilidad continuo (para dimensionar cuán seguido se dispara la guarda) o si conviene retirarlo del pipeline.
4. (SRE) Confirmar de forma definitiva la existencia (o no) del campo anidado `[event][original]` mediante un método de diagnóstico que no comprometa la estabilidad del servicio (evitar `rubydebug` sin acotar fuertemente el volumen/tamaño capturado).
5. (Dev — Business) Evaluar deshabilitar o condicionar `EnableSensitiveDataLogging(true)` en `SmartFran.Cloud.Business.API/Program.cs` — hallazgo de seguridad independiente (H6), no relacionado a la causa de este incidente, que expone valores completos de parámetros SQL en producción.
6. (SRE) Confirmar con el equipo de desarrollo si existe un motivo conocido para el aumento abrupto de la tasa de fallas entre el 2026-07-30 y el 2026-07-31 — no investigado en profundidad en este evento.

## Hallazgos secundarios

Ninguno adicional a los ya incluidos en la tabla de Hallazgos (H6, H7) por ser de menor severidad y no bloquear el cierre de este evento.
