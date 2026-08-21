# Eventos — 20260820_sales-default-stream-leak

## 2026-08-20 — Apertura de GITIN-1905

He abierto la investigación a partir de un reporte de bug: el Default Stream de Graylog viene acumulando una cantidad significativa de mensajes de Sales. He identificado en la documentación histórica de `cloud-graylog` que el stream dedicado de Sales, según esos documentos, tendría el ID `6a452a0d18ebc987b1ca003a`.

**Comando:** C1 — consulta contra ese ID de stream
**Resultado:**
El stream con ese ID corresponde hoy a `PROD-Business-AppServicePlan`, no a Sales.

He descartado esa referencia como desactualizada o incorrecta — la documentación histórica ya registraba un near-miss de confusión entre los streams de Sales y Business en la misma fecha (2026-07-03), lo que sugiere una posible reasignación de ID en ese momento, sin confirmarlo como causa definitiva.

## 2026-08-20 — Ubicación del stream real de Sales

**Comando:** C2 — listado completo de streams
**Resultado:**
ID real de Sales: `6a47c5c94b3c88a95fad7a7a`. Todos los streams de apps, incluido Sales, muestran `remove_matches_from_default_stream: true`.

He descartado la teoría inicial (Sales nunca actualizado con el flag, a diferencia de las 6 apps de GITIN-1834) — el flag ya está correctamente configurado.

**Comando:** C3 — configuración completa del stream real de Sales
**Resultado:**
Creado 2026-07-03, regla `field:name type:1 (exact) value:SMARTFRAN-CLOUD-SALES-PRO`, `remove_matches_from_default_stream: true`.

La configuración del stream en sí luce correcta — he identificado que el origen del problema debe estar en otro lado.

## 2026-08-20 — Cuantificación y confirmación de duplicación real

**Comando:** C4 — conteo de mensajes de Sales en Default Stream, 24h
**Resultado:**
1.101.464 mensajes.

**Comando:** C5 — mismo conteo, filtrado al stream de Sales
**Resultado:**
1.987.186 mensajes.

He descartado que se trate de datos históricos residuales — ambos conteos son grandes y consistentes con tráfico activo, no residuo. He identificado que la explicación más probable es una duplicación real y no dos poblaciones separadas de mensajes.

**Comando:** C6 — muestra real de un mensaje de Sales en Default Stream
**Resultado:**
Mensaje con `MessageTemplate` presente (confirmando origen directo-GELF/CLEF) y `"streams": ["6a47c5c94b3c88a95fad7a7a", "000000000000000000000001"]` — ambos IDs de stream en el mismo mensaje.

He confirmado la duplicación de forma directa, no solo por conteos agregados.

## 2026-08-20 — Causa raíz confirmada

He recordado que Sales tiene una segunda vía de ingesta a Graylog, un sink directo GELF/CLEF (GITIN-1811/1835) que no pasa por el pipeline de Logstash del Event Hub, con su propia Pipeline Rule (`sales-direct-gelf-clef-format.rule`) que enruta explícitamente hacia el stream de Sales vía `route_to_stream()`.

**Comando:** C7 — obtener ID y source real de la Pipeline Rule de Sales
**Resultado:**
Rule id `6a7f2cb84814bcaed30c8de3`. Confirmado `route_to_stream(id: "6a47c5c94b3c88a95fad7a7a")` presente, sin ningún `remove_from_stream()` correspondiente. El `when` real usa `$message.Service`/`$message.Environment`, no `Properties_Service`/`Properties_Environment` como tenía el archivo de referencia local.

He confirmado la causa raíz: como el Stream Router de Graylog evalúa las Stream Rules antes de correr las Pipeline Rules, y el campo `name` que usa la regla del stream de Sales recién se asigna dentro de esta misma Pipeline Rule, el mensaje ya queda asignado a Default Stream al momento de la ingesta — el `remove_matches_from_default_stream` del stream de Sales nunca llega a aplicarse para estos mensajes. He actualizado el archivo de referencia local `cloud-graylog/docs/sales-direct-gelf-clef-format.rule` para sincronizarlo con el source real y agregar el fix.

## 2026-08-20 — Fix aplicado y validado contra tráfico real

**Comando:** C8 ⚠️ — aplicar el fix a la Pipeline Rule real (agrega `remove_from_stream`)
**Resultado:**
`modified_at` actualizado a `2026-08-20T19:04:53.891Z`, source confirmado con la línea nueva.

**Comando:** C9 — conteo post-fix, ventana relativa de 5 minutos
**Resultado:**
8.403 mensajes.

He identificado que este resultado es inconcluso — la ventana (19:00:57 a 19:05:57) incluye mayormente tráfico previo al fix (aplicado a las 19:04:53), no aísla el comportamiento posterior.

**Comando:** C10 — conteo post-fix, ventana absoluta desde 1 segundo después del fix
**Resultado:**
0 mensajes.

He confirmado el fix contra tráfico real, no solo contra el source de la regla — ningún mensaje nuevo de Sales duplicado en Default Stream desde el momento del cambio en adelante. He dejado como seguimiento no bloqueante la decisión sobre los mensajes ya duplicados antes del fix (~2M+, quedan en Default Stream hasta que expiren por retención normal) y una auditoría opcional del resto de las Pipeline Rules en busca del mismo patrón.
