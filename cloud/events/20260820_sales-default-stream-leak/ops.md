# Mensajes de Sales duplicados en Default Stream — GITIN-1905

**Tags:** `SmartCloud`, `Graylog`, `PROD`

## Resumen

El Default Stream de Graylog venía acumulando una cantidad significativa de mensajes de Sales — reportado como bug el 2026-08-20. Los mensajes de Sales que llegan vía el sink directo GELF/CLEF (GITIN-1811/1835, el workaround para Windows donde `AppServiceConsoleLogs` no está soportado) quedaban duplicados de forma permanente tanto en Default Stream como en el stream dedicado `PROD-Sales-AppServicePlan`, pese a que este último tiene `remove_matches_from_default_stream: true` correctamente configurado. La causa fue una Pipeline Rule de Graylog que agregaba el mensaje al stream de Sales sin remover la asignación previa a Default Stream — un desajuste de larga data (la regla data del 14-08, sin relación con este hallazgo hasta ahora), no una regresión reciente. Corregido y validado contra tráfico real el mismo día.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | GITIN-1905 |
| ID alerta | N/A — reportado por el usuario, no alerta automática |
| Sistema | SmartFran Cloud — Graylog (`sfcloud-monitoreo`), Pipeline Rule de Sales (ingesta directa GELF/CLEF) |
| Severidad | Media — sin pérdida de datos ni impacto en disponibilidad, pero duplicación sostenida de ~1.1M mensajes/día indexados innecesariamente en Default Stream durante semanas, con el consiguiente costo de almacenamiento/carga de búsqueda |
| Detectado | 2026-08-20 |
| Resuelto | Sí — 2026-08-20. Confirmado contra tráfico real: 0 mensajes nuevos de Sales en Default Stream desde el momento del fix en adelante (ver H1, C10) |
| Responsable | SRE |

## Causa raíz

La Pipeline Rule `"GITIN-1835: CLEF Azure resource fields for Sales PRO"` (id `6a7f2cb84814bcaed30c8de3`) procesa cada mensaje directo-GELF de Sales y llama a `route_to_stream(id: "<stream de Sales>")` para agregarlo explícitamente al stream dedicado — pero nunca llamaba al `remove_from_stream(id: "<Default Stream>")` correspondiente. Graylog evalúa las Stream Rules **antes** de correr las Pipeline Rules, y el campo `name` que la regla del stream de Sales usa para matchear no existe todavía en ese momento — lo asigna esta misma Pipeline Rule, más tarde en el flujo. Como consecuencia, todo mensaje directo-GELF de Sales ya queda asignado a Default Stream en el momento de la ingesta, y `remove_matches_from_default_stream: true` (correctamente configurado en el stream de Sales) nunca llega a aplicarse, porque la exclusión automática solo actúa cuando la Stream Rule matchea en su momento normal de evaluación — no cuando un campo se completa después, vía pipeline. El resultado es una duplicación permanente, no intermitente, de todo el tráfico directo-GELF de Sales.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Confirmado con datos reales: 1.101.464 mensajes de Sales en Default Stream y 1.987.186 en el stream dedicado, ambos en la misma ventana de 24h — un mensaje real de muestra mostró ambos IDs de stream simultáneamente (`"streams": [sales_stream_id, default_stream_id]`), confirmando duplicación real y no dos poblaciones separadas. Corregido y validado: 0 mensajes nuevos en Default Stream desde el momento del fix (ventana absoluta post-fix, ver C10). | Alto (ya corregido) |
| H2 | El archivo de referencia local `cloud-graylog/docs/sales-direct-gelf-clef-format.rule` tenía una segunda desviación, sin relación con el bug de duplicación: la condición `when` usaba `Properties_Service`/`Properties_Environment`, mientras la regla real en producción usa los campos planos `$message.Service`/`$message.Environment` (la regla real fue modificada el 2026-08-18, causa de ese cambio específico no confirmada de forma independiente). Corregido en el mismo cambio para mantener el archivo de referencia sincronizado con lo desplegado. | Bajo (ya corregido) |
| H3 | Una referencia de documentación histórica de este proyecto (`cloud-graylog/operations/events/20260630_graylog-vm-terraform`) cita el ID de stream `6a452a0d18ebc987b1ca003a` como `PROD-Sales-AppServicePlan` — confirmado que ese ID corresponde hoy a `PROD-Business-AppServicePlan`. No se determinó si el stream fue reasignado en algún momento posterior o si la documentación histórica ya estaba equivocada — mencionado para que ningún ticket futuro reutilice ese ID como si fuera el de Sales. No se corrige el documento histórico en este ticket. | Bajo |
| H4 | Los mensajes ya duplicados antes del fix (aproximadamente 2 millones o más, acumulados desde que la regla se desplegó el 2026-08-14) permanecen en Default Stream — el fix solo previene nueva duplicación hacia adelante, no purga retroactivamente lo ya indexado. Queda como decisión pendiente si conviene purgarlos manualmente o dejarlos expirar por la política de retención normal del índice. | Bajo |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| Graylog Pipeline Rule | `6a7f2cb84814bcaed30c8de3` ("GITIN-1835: CLEF Azure resource fields for Sales PRO") — corregida, agregado `remove_from_stream()` |
| Graylog Stream | Default Stream (`000000000000000000000001`) y `PROD-Sales-AppServicePlan` (`6a47c5c94b3c88a95fad7a7a`) — sin cambios de configuración propia, la causa estaba en la Pipeline Rule, no en los streams |
| Repo `cloud-graylog` | `docs/sales-direct-gelf-clef-format.rule` — actualizado para reflejar el fix y sincronizar con la regla real desplegada (ver H2) |

## Comandos ejecutados

| # | Comando/Script | Propósito |
|---|---|---|
| C1 | `scripts.sh` — consulta contra el ID de stream citado en documentación histórica como Sales | Resultado: ese ID corresponde hoy a Business, no a Sales — referencia descartada (ver H3) |
| C2 | `scripts.sh` — listado completo de streams reales | Ubicar el ID real de Sales y confirmar `remove_matches_from_default_stream` en toda la flota |
| C3 | `scripts.sh` — configuración completa del stream real de Sales | Confirmar regla y flag — configuración correcta en apariencia |
| C4 | `scripts.sh` — conteo de mensajes de Sales en Default Stream, 24h | Cuantificar el problema — 1.101.464 mensajes |
| C5 | `scripts.sh` — mismo conteo, filtrado al stream de Sales | Confirmar que no son dos poblaciones separadas — 1.987.186 mensajes |
| C6 | `scripts.sh` — muestra real de un mensaje de Sales en Default Stream | Confirmar duplicación directa vía el campo `streams` del mensaje real (ver H1) |
| C7 | `scripts.sh` — obtener ID y source real de la Pipeline Rule de Sales | Confirmar causa raíz (`route_to_stream` sin `remove_from_stream`) y detectar drift adicional (ver H2) |
| C8 ⚠️ | `scripts.sh` — aplicar el fix a la Pipeline Rule real | Agregar `remove_from_stream()` — resultado: `modified_at` actualizado, source confirmado |
| C9 | `scripts.sh` — conteo post-fix, ventana relativa de 5 min | Inconcluso — ventana mezclaba tráfico previo y posterior al fix |
| C10 | `scripts.sh` — conteo post-fix, ventana absoluta desde el momento exacto del fix | Confirmar el fix contra tráfico real — resultado: 0 mensajes nuevos |

## Acciones propuestas

1. ~~Confirmar causa raíz de la duplicación~~ — **HECHO 2026-08-20** (ver H1).
2. ~~Aplicar el fix a la Pipeline Rule real (`remove_from_stream`)~~ — **HECHO 2026-08-20.**
3. ~~Validar el fix contra tráfico real, no solo contra el source de la regla~~ — **HECHO 2026-08-20.** 0 mensajes nuevos confirmados.
4. ~~Sincronizar el archivo de referencia local con la regla real desplegada~~ — **HECHO 2026-08-20** (ver H2).
5. **(SRE, seguimiento, no bloqueante)** Decidir si purgar manualmente los mensajes ya duplicados en Default Stream antes del fix (~2M+, ver H4) o dejarlos expirar por retención normal del índice.
6. **(SRE, seguimiento opcional)** Auditar el resto de las Pipeline Rules de este Graylog en busca del mismo patrón (`route_to_stream()` sin `remove_from_stream()` correspondiente) — no se hizo en este ticket, el alcance quedó acotado específicamente a la regla de Sales.
