**Tags:** SmartCloud, CloudPOS, Graylog, PROD

## Resumen

Los mensajes de tráfico `smartfran-pos-wasm` (logs de la POS Blazor WASM relayados vía Azure Function) se encontraban duplicados en Graylog: el mismo mensaje aparecía simultáneamente en el Default Stream y en el stream `PROD-Pos-AppServicePlan`, afectando la precisión de las búsquedas y duplicando la escritura física en los índices de Graylog. El problema afecta a la plataforma SmartFran Cloud, componente de logging (Graylog, `smartfran-graylog-pro`), severidad Media — sin impacto en la disponibilidad del servicio POS, pero con impacto en observabilidad (conteos y búsquedas de logs poco confiables) y en almacenamiento (documentos duplicados). Detectado el 2026-08-25 vía reporte en Jira.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | GITIN-1933 |
| ID alerta | N/A — reportado directamente en Jira, no vía alerta automatizada |
| Sistema | Graylog (`smartfran-graylog-pro`) — tráfico `Service:"smartfran-pos-wasm"` |
| Severidad | Media |
| Detectado | 2026-08-25 |
| Resuelto | 2026-08-25 |
| Responsable | Dante Paniagua (SRE) |

## Causa raíz

Las dos Pipeline Rules creadas en GITIN-1924 para enrutar el tráfico `smartfran-pos-wasm` (una por `Environment`, hacia los streams `DEV` y `PROD-Pos-AppServicePlan`) usaban únicamente `route_to_stream()`, sin `remove_from_stream()`. Como consecuencia, cada mensaje quedaba como miembro simultáneo del Default Stream y del stream de destino. Dado que el Default Stream y el stream de destino tienen index sets propios y distintos (`graylog_4` para Default Stream; `pos__1` para `PROD-Pos-AppServicePlan`; `dev__6` para `DEV`), esa doble membresía de stream se traduce en una escritura física duplicada del mismo mensaje (mismo `_id`) en dos índices distintos — no solo una duplicación cosmética de conteo por stream, sino un doble documento real en el almacenamiento de Graylog. Una búsqueda sin filtrar por stream recorre ambos índices y devuelve ambos hits, lo que se percibe como "mensajes duplicados".

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Ambas Pipeline Rules de GITIN-1924 (`6a8c60ae4814bcaed31a5560` DEV, `6a8c60bf4814bcaed31a559d` PROD) usaban `route_to_stream()` sin `remove_from_stream()`, confirmado contra el texto vivo de la regla (C3) | Medio (mitigado) |
| H2 | El Default Stream y los streams de destino tienen index sets propios (`graylog_4` vs. `pos__1`/`dev__6`), por lo que la doble membresía de stream produce una escritura física duplicada del mismo `_id`, confirmado contra tráfico real (C1) | Medio (mitigado) |
| H3 | Los documentos escritos antes del fix (entre el despliegue de las reglas de GITIN-1924 el 2026-08-24 y el fix aplicado el 2026-08-25 ~12:46 UTC) permanecen duplicados en `graylog_4` + `pos__1`/`dev__6` — no se limpiaron en el alcance de este ticket | Bajo |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| Graylog — Default Stream | `000000000000000000000001`, index set `graylog_4` |
| Graylog — stream `PROD-Pos-AppServicePlan` | `6a7cb1884814bcaed30a8744`, index set `6a7cb1874814bcaed30a873d` (`pos__1`) |
| Graylog — stream `DEV` | `6a7a1b8a34e7b9a985f43cbc`, index `dev__6` |
| Graylog — Pipeline Rule DEV | `6a8c60ae4814bcaed31a5560` ("GITIN-1924: smartfran-pos-wasm to DEV") |
| Graylog — Pipeline Rule PROD | `6a8c60bf4814bcaed31a559d` ("GITIN-1924: smartfran-pos-wasm to PROD-Pos-AppServicePlan") |
| Host | `smartfran-graylog-pro` |

## Comandos ejecutados

Ver `scripts.sh` en esta carpeta de evento.

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | Views Search API — mensajes recientes `smartfran-pos-wasm`/Production | Confirmar duplicación real: mismo `_id`, dos índices |
| C2 | `GET /streams/{id}` | Confirmar nombre del stream de destino (`PROD-Pos-AppServicePlan`) |
| C3 | `GET /system/pipelines/rule` | Confirmar texto vivo de ambas reglas de GITIN-1924 |
| C4 | ⚠️ `PUT /system/pipelines/rule/{id}` — regla DEV | Agregar `remove_from_stream()` del Default Stream a la regla DEV |
| C5 | ⚠️ `PUT /system/pipelines/rule/{id}` — regla PROD | Agregar `remove_from_stream()` del Default Stream a la regla PROD |
| C6 | Views Search API — verificación post-fix (PROD) | Confirmar tráfico real posterior al fix: un solo stream, un solo índice |
| C7 | Views Search API — verificación post-fix (DEV) | Confirmar tráfico real posterior al fix: un solo stream, un solo índice |

## Acciones propuestas

1. **[Completado]** Se agregó `remove_from_stream(id: "000000000000000000000001")` a la Pipeline Rule DEV (`6a8c60ae4814bcaed31a5560`), 2026-08-25 12:45:44 UTC.
2. **[Completado]** Se agregó `remove_from_stream(id: "000000000000000000000001")` a la Pipeline Rule PROD (`6a8c60bf4814bcaed31a559d`), 2026-08-25 12:46:28 UTC.
3. **[Completado]** Se verificó contra tráfico real posterior al fix, en ambos lados: los mensajes de `smartfran-pos-wasm` quedan únicamente en su stream de destino (sin Default Stream) y se indexan una sola vez (`pos__1` para PROD, `dev__6` para DEV) — confirmado con `_id` únicos, sin repetición.
4. **[Pendiente — decisión no tomada]** Definir si se eliminan/reindexan los documentos duplicados ya escritos antes del fix (en `graylog_4` + `pos__1`/`dev__6`), o si se dejan como están y el fix solo aplica hacia adelante.
