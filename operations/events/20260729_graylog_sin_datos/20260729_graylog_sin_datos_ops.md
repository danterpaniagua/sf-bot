# Caída de volumen en Graylog (SmartCloud) — Business y Sales, y fallas activas de indexado

**Tags:** Operaciones, SmartCloud, Graylog, Azure, Obserbavilidad, SRE

## Resumen

El 2026-07-29 se reportó que Graylog (instancia dedicada de SmartCloud, `smartfran-graylog-pro`, streams `PROD-Business-AppServicePlan` y `PROD-Sales-AppServicePlan`) dejó de recibir datos. La investigación determinó que no se trató de una caída total sino de una **reducción sostenida de volumen (~92-97%)**, sincronizada en ambos streams, iniciada el **2026-07-28 a las 03:00 ART (06:00 UTC)**. El volumen se **recuperó el 2026-07-31 a las 11:00 ART (14:00 UTC)**, de forma abrupta y sostenida (338K-446K mensajes/hora, dentro del rango pre-caída), coincidiendo con el primer reinicio de Logstash realizado ese día en el marco de una intervención no relacionada — evidencia circunstancial fuerte de que la causa era un estado degradado del consumidor de Event Hub que solo requería un reinicio del servicio, no un cambio de verbosidad de logging del lado de desarrollo (hipótesis alternativa que se venía considerando). Las fallas de indexado activas identificadas en paralelo durante esta investigación se separaron a un evento propio (`20260730_graylog_indexing_failure`), donde se confirmó su causa raíz — distinta a la de este evento — y se desplegó una corrección confirmada. Severidad: baja tras la recuperación del volumen y la corrección de las fallas de indexado; el origen exacto del estado degradado inicial del 2026-07-28 permanece sin confirmar de forma concluyente.

## Tabla resumen

| Campo | Valor |
|---|---|
| ID alerta | N/A — reportado directamente, no generó alerta automática |
| Sistema | Graylog SmartCloud (`smartfran-graylog-pro`) — streams Business y Sales |
| Severidad | Baja (post-recuperación; era Media mientras el volumen estuvo reducido) |
| Detectado | 2026-07-29 (reportado) — inicio real confirmado: 2026-07-28 06:00 UTC |
| Resuelto | Sí — volumen recuperado 2026-07-31 11:00 ART; fallas de indexado corregidas en `20260730_graylog_indexing_failure`. Causa raíz original del estado degradado (2026-07-28) no confirmada de forma concluyente, solo evidencia circunstancial |
| Responsable | Dante Paniagua |

## Causa raíz

No confirmada de forma concluyente, pero con evidencia circunstancial fuerte agregada el 2026-07-31. La evidencia original descartó una caída de infraestructura: la VM está activa y saludable, el clúster de OpenSearch no está degradado (estado yellow es el baseline normal de un nodo único), Event Hub mantuvo una cadencia de batches estable y sin cambios antes/después del cliff, y no hay eventos relevantes en Activity Log ni cambios en App Configuration en la ventana del incidente. El indicador más fuerte sigue siendo que el servicio **Logstash en el host de Graylog se reinició a las 2026-07-28 06:06:40 UTC**, prácticamente en el mismo momento del cliff de volumen — no se confirmó si ese restart fue la causa (crash) o un evento simultáneo no relacionado.

**Hallazgo agregado el 2026-07-31:** el volumen se recuperó de forma abrupta a las 11:00 ART (14:00 UTC), coincidiendo con el primer reinicio de Logstash de ese día, realizado en el marco de una intervención no relacionada (`20260730_graylog_indexing_failure`). Esto sugiere que el estado degradado del consumidor de Event Hub, alcanzado posiblemente en el reinicio original del 2026-07-28, persistía indefinidamente y solo se resolvía con un nuevo reinicio del servicio — no con el paso del tiempo ni con una acción de Desarrollo. La hipótesis de un cambio de verbosidad de logging en Business/Sales pierde fuerza frente a esta evidencia, aunque tampoco fue descartada de forma directa por el equipo de desarrollo. La coincidencia temporal es evidencia circunstancial, no una prueba definitiva — no se aisló "el reinicio" como única variable frente a otros cambios de esa misma intervención.

Las fallas de indexado identificadas en esta misma investigación tuvieron una causa raíz propia y distinta, no relacionada con la caída de volumen — ver `20260730_graylog_indexing_failure` para el detalle completo. Causa raíz real confirmada allí: una guarda condicional sin rama alternativa en el fix de Logstash del 2026-07-02 (no `EnableSensitiveDataLogging(true)`, como se sospechaba inicialmente en este evento — esa hipótesis fue descartada con evidencia de Log Analytics).

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Caída sincronizada de ~92-97% en el volumen de mensajes de Business y Sales, iniciada 2026-07-28 06:00 UTC, sostenida 46+ horas sin recuperación | Alto |
| H2 | Servicio Logstash en `smartfran-graylog-pro` reiniciado a las 2026-07-28 06:06:40 UTC — coincide casi exactamente con el cliff de volumen; causa del restart (crash vs. acción intencional) no confirmada | Alto |
| H3 | 62.876 fallas de indexado activas desde el mismo momento del cliff, continuando hasta el momento de este reporte — pérdida de datos en curso (~1.164 mensajes/hora) | Alto |
| H4 | Causa de las fallas de indexado: registros individuales de Business (no batches) superan el límite de término de Lucene (32.766 bytes), hasta 131KB observados — el fix del 2026-07-02 sigue vigente pero no cubre este caso | Alto |
| H5 | `EnableSensitiveDataLogging(true)` hardcodeado sin guard de entorno en Business `Program.cs` desde 2023-10-25 — registra valores completos de parámetros SQL en producción, causa probable del tamaño excesivo de los registros individuales | Medio |
| H6 | Descartado: caída de VM, degradación de clúster OpenSearch, cambio en App Service Settings, cambio en Azure App Configuration, evento relevante en Activity Log — ninguno coincide con la ventana del incidente | — |
| H7 | Brecha de RBAC data-plane: ningún principal (incluyendo el usuario que investigó) tiene el rol "App Configuration Data Reader/Owner" sobre `SmartFran-Cloud-Settings-PRO` — solo se pudo auditar mediante connection string de solo lectura | Bajo |
| H8 | Heap de JVM real provisionado en el nodo Graylog es 4GB — menor a las cifras de dimensionamiento ("pilot" ~12GB, "full fleet" ~32GB) documentadas en `cloud-graylog/CLAUDE.md`; no es causa de este incidente pero es una discrepancia de documentación a corregir por separado | Bajo |
| H9 | Volumen recuperado el 2026-07-31 a las 11:00 ART (14:00 UTC), de forma abrupta y sostenida (338K-446K mensajes/hora, dentro del rango pre-caída) — coincide con el primer reinicio de Logstash del día, realizado por una intervención no relacionada (`20260730_graylog_indexing_failure`). Evidencia circunstancial fuerte de que la causa raíz original era un estado degradado del consumidor de Event Hub, resuelto por el reinicio, no un cambio de verbosidad de logging | Medio |
| H10 | Actualización de H4/H5: la causa raíz real de las fallas de indexado, confirmada en `20260730_graylog_indexing_failure`, fue una guarda condicional sin rama alternativa en el fix de Logstash del 2026-07-02 — `EnableSensitiveDataLogging(true)` fue descartado como causa suficiente (registros individuales, incluso con logging sensible completo, no superan ~2,9KB, muy por debajo del límite de 32.766 bytes) | Bajo |

## Recursos afectados

| Componente | Impacto |
|---|---|
| Graylog `smartfran-graylog-pro` — streams `PROD-Business-AppServicePlan`, `PROD-Sales-AppServicePlan` | Cobertura de observabilidad reducida ~92-97% desde 2026-07-28 06:00 UTC |
| Índice `business__6` (OpenSearch) | Pérdida activa de datos por fallas de indexado, ~1.164 mensajes/hora |
| `SmartFran-Cloud-Business-PRO` (App Service) | Origen de los registros individuales sobredimensionados que causan las fallas de indexado |
| Servicio Logstash (`smartfran-graylog-pro`) | Reiniciado en el momento del incidente, causa del restart sin confirmar |

## Comandos ejecutados

Ver `20260729_graylog_sin_datos_scripts.sh` para el detalle completo. Resumen:

| # | Comando / Script | Propósito |
|---|---|---|
| C0-C1 | Azure CLI — estado de VM | Confirmar RG y estado de energía de `smartfran-graylog-pro` |
| C2, C22, C23 | Azure CLI — Activity Log | Buscar eventos de infraestructura en la ventana del cliff (2026-07-28 04:00-09:00 UTC) |
| C3-C4 | Azure CLI — App Settings | Descartar cambio de verbosidad vía configuración de App Service |
| C24 | Azure CLI — métricas Event Hub | Confirmar cadencia de batches estable antes/después del cliff |
| C29-C33 | Azure CLI — App Configuration | Descartar clave compartida de logging/telemetry como causa |
| C21, C25 | Graylog REST API (Views/Search) | Conteo de mensajes por hora y por stream, 48h |
| C34-C36 | Graylog REST API | Conteo y detalle de fallas de indexado, antes/después del cliff |
| C37-C39 | ⚠️ `az vm run-command` (lectura únicamente — `systemctl status`, `journalctl`, `grep`) | Estado y timing de Logstash, verificación del fix de `event_original` en la config activa |
| C40 (2026-07-31) | Graylog REST API (Views/Search) | Conteo de mensajes por hora, 24h, global (sin filtro de stream) — confirmación de la recuperación de volumen (Hallazgo H9) |

## Acciones propuestas

1. (SRE) Revisar el journal de Logstash inmediatamente anterior al reinicio del 2026-07-28 06:06:40 UTC, para completar la comprensión de la causa raíz original — ya no bloqueante para el cierre operativo de este evento, dado que el volumen se recuperó el 2026-07-31 (ver Hallazgo H9), pero queda pendiente si se quiere cerrar la incógnita de forma definitiva.
2. (Dev — Business) Evaluar deshabilitar o condicionar `EnableSensitiveDataLogging(true)` en `SmartFran.Cloud.Business.API/Program.cs` — hallazgo de seguridad real pero no relacionado a este evento; seguimiento movido a `20260730_graylog_indexing_failure` (acción 5 de ese evento) para no duplicar tracking entre tickets.
3. (SRE) Confirmar con el equipo de desarrollo de Business/Sales si hubo algún cambio intencional de nivel de logging alrededor del 2026-07-28 06:00 UTC — pierde prioridad frente a la evidencia de H9 (el reinicio de Logstash, no un cambio de logging, parece explicar la recuperación), pero puede confirmarse igualmente si surge la oportunidad, para cerrar la causa raíz original con certeza.
4. **Completado (2026-07-31).** (SRE) Guard en el pipeline de Logstash para `event_original` — implementado, desplegado y verificado en `20260730_graylog_indexing_failure`: truncado incondicional de `event_original` (plano) y `[event][original]` (anidado, ECS) antes del output GELF. Confirmado sin fallas nuevas por 5+ horas post-despliegue.
5. (SRE) Solicitar o asignar el rol "App Configuration Data Reader" sobre `SmartFran-Cloud-Settings-PRO` a quien realice auditorías de este tipo, para no depender de connection strings de acceso por clave en futuras investigaciones.
6. (SRE) Actualizar `cloud-graylog/CLAUDE.md` con el heap real provisionado en el nodo Graylog/OpenSearch (4GB) para que el documento de dimensionamiento refleje el estado actual, no solo las cifras de fases "pilot"/"full fleet". (Nota: distinto del heap de Logstash, ajustado por separado el 2026-07-31 de 1GB a 4GB en `20260730_graylog_indexing_failure` por un problema de estabilidad no relacionado.)

## Hallazgos secundarios

Ninguno adicional a los ya incluidos en la tabla de Hallazgos (H7, H8) por ser de menor severidad y no bloquear el cierre de este evento.
